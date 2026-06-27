class_name Simulation
extends RefCounted

## Glowny orkiestrator symulacji.
##
## Odpowiada za:
##  - posiadanie PlantState,
##  - deterministyczny krok czasu o stalej dlugosci (fixed timestep),
##  - wywolanie modeli fizycznych: reaktywnosc (prety + sprzezenia) -> neutronika
##    -> (1C) termohydraulika -> (1D) ksenon -> obieg/turbina/sieć -> bezpieczenstwo.
##
## Determinizm: przy zadanym ziarnie (seed) i tej samej sekwencji komend
## wynik jest identyczny. To warunek konieczny testow i multiplayera.
##
## ETAP 1B: rho liczy ReactivityModel z pozycji pretow i sprzezen. Wejscia termiczne
##          (T_paliwa, T_chlodziwa, pustki) sa na razie na wartosciach REFERENCYJNYCH
##          (sprzezenia = 0); realne wartosci dostarczy termohydraulika w 1C.
##          Reaktorem steruja PRETY (set_rod_target / scram) + opcjonalny bias zewn.

# Stala czestotliwosc kroku fizyki. 50 Hz -> dt = 0.02 s.
const PHYSICS_HZ: float = 50.0
const FIXED_DT: float = 1.0 / PHYSICS_HZ   # [s]
const _ACCUMULATOR_EPSILON: float = 1.0e-9

var state: PlantState
var neutronics: Neutronics
var reactivity_model: ReactivityModel
var control_rods: ControlRods
var params: ReactorParams
var reactivity_params: ReactivityParams

# Wejscia termiczne - w 1B na wartosciach referencyjnych (sprzezenia = 0 do 1C).
var _fuel_temp: float = 0.0
var _coolant_temp: float = 0.0
var _void_fraction: float = 0.0
var _external_reactivity: float = 0.0      # bias zewnetrzny (scenariusze/testy)
var _xenon_reactivity: float = 0.0         # wklad ksenonu (hak do 1D)

var _time_accumulator: float = 0.0
var _rng: RandomNumberGenerator


## seed_value - ziarno determinizmu; opcjonalne zestawy stalych (domyslnie standardowe).
func _init(seed_value: int = 0, reactor_params: ReactorParams = null,
		react_params: ReactivityParams = null) -> void:
	state = PlantState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	params = reactor_params if reactor_params != null else ReactorParams.new()
	reactivity_params = react_params if react_params != null else ReactivityParams.new()

	neutronics = Neutronics.new(params)
	reactivity_model = ReactivityModel.new(reactivity_params)

	# Wejscia termiczne startowo = referencja (sprzezenia neutralne).
	_fuel_temp = reactivity_params.fuel_temp_ref
	_coolant_temp = reactivity_params.coolant_temp_ref
	_void_fraction = reactivity_params.void_ref

	# Prety startuja na POZYCJI KRYTYCZNEJ przy referencji: rho calkowite = 0 przy n=1.
	# Czynniki poza pretami w punkcie odniesienia sprowadzaja sie do excess_reactivity.
	var critical_insertion := reactivity_model.critical_rod_insertion(
		reactivity_params.excess_reactivity)
	control_rods = ControlRods.new(
		reactivity_params.rod_speed_normal,
		reactivity_params.rod_speed_scram,
		critical_insertion)

	neutronics.initialize_steady_state(1.0)
	_sync_state()


# --- Sterowanie operatorskie ---

## Ustawia docelowe zaglebienie pretow (0..1).
func set_rod_target(insertion: float) -> void:
	control_rods.set_target(insertion)

## Awaryjne wsuniecie pretow (AZ-5).
func scram() -> void:
	control_rods.scram()

## Bias reaktywnosci zewnetrznej (scenariusze/eksperymenty/testy).
func set_external_reactivity(value: float) -> void:
	_external_reactivity = value

## Ustawia wejscia termiczne (do 1C zastapi to termohydraulika; przydatne w testach/scenariuszach).
func set_thermal_inputs(fuel_temp: float, coolant_temp: float, void_fraction: float) -> void:
	_fuel_temp = fuel_temp
	_coolant_temp = coolant_temp
	_void_fraction = void_fraction


## Wykonuje JEDEN krok symulacji o staly FIXED_DT.
func step() -> void:
	state.tick += 1
	state.sim_time_seconds += FIXED_DT

	# 1) Kinematyka pretow.
	control_rods.step(FIXED_DT)

	# 2) Bilans reaktywnosci z aktualnego stanu.
	var inputs := ReactivityInputs.new()
	inputs.rod_insertion = control_rods.get_insertion()
	inputs.fuel_temp = _fuel_temp
	inputs.coolant_temp = _coolant_temp
	inputs.void_fraction = _void_fraction
	inputs.xenon_reactivity = _xenon_reactivity
	inputs.external_reactivity = _external_reactivity
	var rho := reactivity_model.total_reactivity(inputs)

	# 3) Neutronika (kinetyka punktowa).
	neutronics.step(rho, FIXED_DT)

	_sync_state(inputs)


## Przepisuje wynik modeli fizycznych do serializowalnego PlantState (kanal dla UI/sieci).
func _sync_state(inputs: ReactivityInputs = null) -> void:
	state.reactor_power_fraction = neutronics.get_power_fraction()
	state.reactor_period_seconds = neutronics.get_reactor_period()
	state.rod_insertion = control_rods.get_insertion()

	if inputs == null:
		inputs = ReactivityInputs.new()
		inputs.rod_insertion = control_rods.get_insertion()
		inputs.fuel_temp = _fuel_temp
		inputs.coolant_temp = _coolant_temp
		inputs.void_fraction = _void_fraction
		inputs.xenon_reactivity = _xenon_reactivity
		inputs.external_reactivity = _external_reactivity

	var breakdown := reactivity_model.reactivity_breakdown(inputs)
	state.reactivity = breakdown["total"]
	state.rho_rods = breakdown["rods"]
	state.rho_doppler = breakdown["doppler"]
	state.rho_void = breakdown["void"]
	state.rho_coolant = breakdown["coolant"]
	state.rho_xenon = breakdown["xenon"]


## Posuwa symulacje o zadany realny czas, dzielac go na stale kroki FIXED_DT.
## Trwaly akumulator gwarantuje niezaleznosc fizyki od FPS i to, ze reszta czasu
## nie ginie, lecz przenosi sie do kolejnego wywolania (poprawnosc + brak dryfu).
## Epsilon kompensuje to, ze 0.02 s nie jest dokladnie reprezentowalne w double.
## Zwraca liczbe wykonanych krokow.
func advance(real_delta_seconds: float) -> int:
	var steps := 0
	_time_accumulator += real_delta_seconds
	while _time_accumulator >= FIXED_DT - _ACCUMULATOR_EPSILON:
		step()
		_time_accumulator -= FIXED_DT
		steps += 1
	return steps
