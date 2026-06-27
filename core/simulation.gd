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
## ETAP 1C: wejscia termiczne (T_paliwa, T_chlodziwa, pustki) liczy ThermalModel
##          z aktualnej mocy i przeplywu chlodziwa. SPRZEZENIE Z OPOZNIENIEM 1 KROKU:
##          reaktywnosc w kroku k korzysta ze stanu cieplnego z konca kroku k-1
##          (najpierw neutronika, potem termika) - prostsze i stabilne (bez iteracji
##          w obrebie kroku). Realny obieg pomp/zaworow/cisnienia dojdzie w 1C'.
##          Reaktorem steruja PRETY (set_rod_target / scram) + przeplyw + bias zewn.
##
## ETAP 1E-1: warstwa BEZPIECZENSTWA (RPS) niezalezna i NADRZEDNA nad sterowaniem.
##          Po fizyce kazdego kroku: ProtectionSystem ocenia sygnaly AZ -> auto-SCRAM;
##          FailureConditions sprawdza warunki przegranej -> latch awarii (stan zamrozony,
##          dalsza ewolucja niefizyczna). Maszyna stanow gatekeeper przejsc; wyjscie ze
##          SCRAM tylko recznie (reset_after_scram). Zabezpieczenia i awarie mozna wylaczyc
##          (set_protection_enabled / set_failure_states_enabled) - tryb "Czarnobyl" / badanie
##          surowej fizyki. Czas SCRAM realny i konfigurowalny (SafetyParams, ~18 s pre-1986).

# Stala czestotliwosc kroku fizyki. 50 Hz -> dt = 0.02 s.
const PHYSICS_HZ: float = 50.0
const FIXED_DT: float = 1.0 / PHYSICS_HZ   # [s]
const _ACCUMULATOR_EPSILON: float = 1.0e-9

var state: PlantState
var neutronics: Neutronics
var reactivity_model: ReactivityModel
var control_rods: ControlRods
var thermal_model: ThermalModel
var decay_heat: DecayHeat
var params: ReactorParams
var reactivity_params: ReactivityParams
var thermal_params: ThermalParams

# Warstwa bezpieczenstwa (ETAP 1E-1).
var safety_params: SafetyParams
var protection_system: ProtectionSystem
var failure_conditions: FailureConditions
var state_machine: ReactorStateMachine

# Stan cieplny CACHE - aktualizowany przez ThermalModel na koncu kazdego kroku,
# czytany przez bilans reaktywnosci w NASTEPNYM kroku (sprzezenie z opoznieniem 1 kroku).
var _fuel_temp: float = 0.0
var _coolant_temp: float = 0.0
var _void_fraction: float = 0.0
var _coolant_flow_fraction: float = 1.0    # wzgledny przeplyw chlodziwa 0..1 (1 = nominal)
var _external_reactivity: float = 0.0      # bias zewnetrzny (scenariusze/testy)
var _xenon_reactivity: float = 0.0         # wklad ksenonu (hak do 1D)

# Bezpieczenstwo (ETAP 1E-1).
var _manual_az5: bool = false              # zatrzasniety przycisk operatora AZ-5
var _protection_enabled: bool = true       # RPS uzbrojony (false = tryb "Czarnobyl")
var _failure_states_enabled: bool = true   # warunki przegranej aktywne (false = surowa fizyka)
var _failure: int = 0                       # FailureConditions.Type (0 = NONE); !=0 zamraza sim
var _event_log: Array[String] = []         # log zdarzen (alarmy/SCRAM/awaria) dla UI (ETAP 2)

var _time_accumulator: float = 0.0
var _rng: RandomNumberGenerator


## seed_value - ziarno determinizmu; opcjonalne zestawy stalych (domyslnie standardowe).
func _init(seed_value: int = 0, reactor_params: ReactorParams = null,
		react_params: ReactivityParams = null, therm_params: ThermalParams = null,
		safe_params: SafetyParams = null) -> void:
	state = PlantState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	params = reactor_params if reactor_params != null else ReactorParams.new()
	reactivity_params = react_params if react_params != null else ReactivityParams.new()
	thermal_params = therm_params if therm_params != null else ThermalParams.new()
	safety_params = safe_params if safe_params != null else SafetyParams.new()

	neutronics = Neutronics.new(params)
	reactivity_model = ReactivityModel.new(reactivity_params)
	thermal_model = ThermalModel.new(thermal_params)
	decay_heat = DecayHeat.new(thermal_params)
	protection_system = ProtectionSystem.new(safety_params)
	failure_conditions = FailureConditions.new(safety_params)
	state_machine = ReactorStateMachine.new()

	# Stan cieplny startowo = rownowaga dla n=1 przy pelnym przeplywie.
	# Dla domyslnych stalych daje to T_paliwa=800 K, T_chlodziwa=550 K, void=0,
	# czyli punkt ODNIESIENIA spojny z pozycja krytyczna pretow (sprzezenia ~0).
	thermal_model.initialize_steady_state(1.0)
	decay_heat.initialize_steady_state(1.0)
	_fuel_temp = thermal_model.get_fuel_temp()
	_coolant_temp = thermal_model.get_coolant_temp()
	_void_fraction = thermal_model.get_void_fraction()

	# Prety startuja na POZYCJI KRYTYCZNEJ przy referencji: rho calkowite = 0 przy n=1.
	# Czynniki poza pretami w punkcie odniesienia sprowadzaja sie do excess_reactivity.
	# Predkosc SCRAM z SafetyParams (realny czas, ~18 s pre-1986), nie z 1B.
	var critical_insertion := reactivity_model.critical_rod_insertion(
		reactivity_params.excess_reactivity)
	var scram_speed := 1.0 / safety_params.scram_full_insertion_time_s
	control_rods = ControlRods.new(
		reactivity_params.rod_speed_normal,
		scram_speed,
		critical_insertion)

	neutronics.initialize_steady_state(1.0)
	_sync_state()


# --- Sterowanie operatorskie ---

## Ustawia docelowe zaglebienie pretow (0..1).
func set_rod_target(insertion: float) -> void:
	control_rods.set_target(insertion)

## Manualne awaryjne wylaczenie (przycisk AZ-5). Zatrzasniete (RPS nadrzedny).
func scram() -> void:
	_manual_az5 = true
	_trigger_scram([TripSignal.Type.MANUAL_AZ5])

## Uzbrojenie/rozbrojenie RPS (auto-SCRAM). false = tryb "Czarnobyl" (zabezpieczenia obejscia).
func set_protection_enabled(enabled: bool) -> void:
	_protection_enabled = enabled

## Wlaczenie/wylaczenie warunkow przegranej. false = badanie surowej fizyki bez konca gry.
func set_failure_states_enabled(enabled: bool) -> void:
	_failure_states_enabled = enabled

## Reczny reset po SCRAM do SHUTDOWN (jedyne wyjscie ze SCRAM). Zwraca true, jesli wykonano.
func reset_after_scram() -> bool:
	if not state_machine.reset_to_shutdown():
		return false
	_manual_az5 = false
	_log("Reset po SCRAM -> SHUTDOWN")
	return true

## Operatorskie zadanie przejscia stanu (PCS). Zwraca true, jesli legalne i wykonane.
func request_state(target: int) -> bool:
	return state_machine.request(target, _start_interlocks_ok())

func get_reactor_state() -> int:
	return state_machine.get_state()

func is_failed() -> bool:
	return _failure != FailureConditions.Type.NONE

func get_failure() -> int:
	return _failure

func get_event_log() -> Array[String]:
	return _event_log.duplicate()

## Bias reaktywnosci zewnetrznej (scenariusze/eksperymenty/testy).
func set_external_reactivity(value: float) -> void:
	_external_reactivity = value

## Ustawia wzgledny przeplyw chlodziwa 0..1 (1 = nominalny). Spadek -> wrzenie -> void.
## UPROSZCZENIE (1C): przeplyw skalarny, natychmiastowy; bezwladnosc pomp i obieg w 1C'.
func set_coolant_flow(flow_fraction: float) -> void:
	_coolant_flow_fraction = clampf(flow_fraction, 0.0, 1.0)

## Aktualny stan cieplny (diagnostyka/testy): [T_paliwa K, T_chlodziwa K, void].
func get_thermal_state() -> Array:
	return [_fuel_temp, _coolant_temp, _void_fraction]


## Wykonuje JEDEN krok symulacji o staly FIXED_DT.
func step() -> void:
	# Po wykryciu awarii stan jest ZAMROZONY - dalsza ewolucja bylaby niefizyczna
	# (np. "stabilizacja" rdzenia powyzej temperatury topnienia paliwa). Gra zakonczona.
	if _failure != FailureConditions.Type.NONE:
		return

	state.tick += 1
	state.sim_time_seconds += FIXED_DT

	# 1) Kinematyka pretow.
	control_rods.step(FIXED_DT)

	# 2) Bilans reaktywnosci z aktualnego stanu. Stan cieplny pochodzi z KONCA
	#    poprzedniego kroku (sprzezenie z opoznieniem 1 kroku) - patrz naglowek.
	var inputs := ReactivityInputs.new()
	inputs.rod_insertion = control_rods.get_insertion()
	inputs.fuel_temp = _fuel_temp
	inputs.coolant_temp = _coolant_temp
	inputs.void_fraction = _void_fraction
	inputs.xenon_reactivity = _xenon_reactivity
	inputs.external_reactivity = _external_reactivity
	var rho := reactivity_model.total_reactivity(inputs)

	# 3) Neutronika (kinetyka punktowa) -> nowa moc rozszczepien.
	neutronics.step(rho, FIXED_DT)
	var fission_power := neutronics.get_power_fraction()

	# 4) Cieplo powylaczeniowe: rezerwuar produktow rozpadu (trwa po SCRAM).
	decay_heat.step(fission_power, FIXED_DT)
	# Calkowite cieplo = czesc prompt (z rozszczepien) + decay (z rozpadu).
	var heat_fraction := thermal_params.prompt_heat_fraction * fission_power \
		+ decay_heat.get_decay_power_fraction()

	# 5) Termohydraulika reaguje na cieplo; wynik trafi do reaktywnosci nast. kroku.
	thermal_model.step(heat_fraction, _coolant_flow_fraction, FIXED_DT)
	_fuel_temp = thermal_model.get_fuel_temp()
	_coolant_temp = thermal_model.get_coolant_temp()
	_void_fraction = thermal_model.get_void_fraction()

	_sync_state(inputs)

	# 6) Warstwa bezpieczenstwa (RPS nadrzedny): auto-SCRAM i warunki przegranej.
	_evaluate_safety()


## Przepisuje wynik modeli fizycznych do serializowalnego PlantState (kanal dla UI/sieci).
func _sync_state(inputs: ReactivityInputs = null) -> void:
	state.reactor_power_fraction = neutronics.get_power_fraction()
	state.reactor_period_seconds = neutronics.get_reactor_period()
	state.rod_insertion = control_rods.get_insertion()

	# Stan cieplny (ETAP 1C).
	state.fuel_temp = _fuel_temp
	state.coolant_temp = _coolant_temp
	state.void_fraction = _void_fraction
	state.coolant_flow_fraction = _coolant_flow_fraction
	state.thermal_power_mw = thermal_model.get_thermal_power_watts() / 1.0e6
	state.decay_heat_fraction = decay_heat.get_decay_power_fraction()

	# Bezpieczenstwo (ETAP 1E): proxy koszulki + stan bloku.
	state.clad_temp = failure_conditions.clad_temp(state)
	state.reactor_state = state_machine.get_state()

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


## Warstwa bezpieczenstwa po fizyce kroku (ETAP 1E-1).
## 1) RPS (jesli uzbrojony): aktywne sygnaly AZ -> auto-SCRAM.
## 2) Warunki przegranej (jesli wlaczone): pierwsza awaria zamraza symulacje.
func _evaluate_safety() -> void:
	# 1) Sygnaly AZ z oknem potwierdzenia (debounce). Manualny AZ-5 liczy sie zawsze;
	#    auto-trip-y tylko przy uzbrojonym RPS i po utrzymaniu warunku (filtr artefaktow).
	var trips: Array[int] = []
	if _protection_enabled:
		trips = protection_system.update(state, _manual_az5, FIXED_DT)
	elif _manual_az5:
		trips.append(TripSignal.Type.MANUAL_AZ5)
	state.active_trips = trips

	if not trips.is_empty():
		_trigger_scram(trips)

	# 2) Warunki przegranej.
	if _failure_states_enabled:
		var f := failure_conditions.check(state)
		if f != FailureConditions.Type.NONE:
			_failure = f
			state.failure_state = f
			state.failure_cause = FailureConditions.describe(f)
			_log("AWARIA: %s (T_paliwa=%.0fK, moc=%.2f, void=%.2f)" % [
				state.failure_cause, state.fuel_temp,
				state.reactor_power_fraction, state.void_fraction])


## Wymusza SCRAM (RPS lub manual). Loguje przyczyne raz, przy nowym wejsciu w stan SCRAM.
func _trigger_scram(causes: Array[int]) -> void:
	if state_machine.trigger_scram():
		var names: Array[String] = []
		for c in causes:
			names.append(TripSignal.describe(c))
		_log("SCRAM (AZ): " + ", ".join(names))
	control_rods.scram()


## Warunki wstepne startu (SHUTDOWN->STARTUP). 1E-1: przeplyw, RPS, brak awarii.
## ORM i cisnienie dojda jako dodatkowe interlocki w 1E-3 / 1C'.
func _start_interlocks_ok() -> bool:
	if _failure != FailureConditions.Type.NONE:
		return false
	if not _protection_enabled:
		return false
	return _coolant_flow_fraction >= safety_params.low_flow_trip_fraction


func _log(message: String) -> void:
	_event_log.append("[t=%.2fs] %s" % [state.sim_time_seconds, message])


## Posuwa symulacje o zadany realny czas, dzielac go na stale kroki FIXED_DT.
## Trwaly akumulator gwarantuje niezaleznosc fizyki od FPS i to, ze reszta czasu
## nie ginie, lecz przenosi sie do kolejnego wywolania (poprawnosc + brak dryfu).
## Epsilon kompensuje to, ze 0.02 s nie jest dokladnie reprezentowalne w double.
## Zwraca liczbe wykonanych krokow.
func advance(real_delta_seconds: float) -> int:
	# Po awarii stan jest zamrozony - czas nie plynie (gra zakonczona).
	if _failure != FailureConditions.Type.NONE:
		return 0
	var steps := 0
	_time_accumulator += real_delta_seconds
	while _time_accumulator >= FIXED_DT - _ACCUMULATOR_EPSILON:
		step()
		_time_accumulator -= FIXED_DT
		steps += 1
	return steps
