class_name Simulation
extends RefCounted

## Glowny orkiestrator symulacji.
##
## Odpowiada za:
##  - posiadanie PlantState,
##  - deterministyczny krok czasu o stalej dlugosci (fixed timestep),
##  - (ETAP 1) wywolanie modeli fizycznych: neutronika -> reaktywnosc ->
##    termohydraulika -> ksenon -> obieg/turbina/sieć -> bezpieczenstwo.
##
## Determinizm: przy zadanym ziarnie (seed) i tej samej sekwencji komend
## wynik jest identyczny. To warunek konieczny testow i multiplayera.
##
## ETAP 1A: step() prowadzi kinetyke punktowa (Neutronics). Reaktywnosc rho jest
##          na razie wejsciem zewnetrznym/skryptowym (set_reactivity). Pelny bilans
##          reaktywnosci (pret, Doppler, void, ksenon) dojdzie w podetapie 1B.

# Stala czestotliwosc kroku fizyki. 50 Hz -> dt = 0.02 s.
const PHYSICS_HZ: float = 50.0
const FIXED_DT: float = 1.0 / PHYSICS_HZ   # [s]

var state: PlantState
var neutronics: Neutronics
var params: ReactorParams

var _commanded_reactivity: float = 0.0     # rho zadawane z zewnatrz (wejscie 1A)
var _time_accumulator: float = 0.0         # trwaly akumulator czasu (fixed timestep)
var _rng: RandomNumberGenerator


## seed_value - ziarno determinizmu; reactor_params - opcjonalne stale (domyslnie standardowe).
func _init(seed_value: int = 0, reactor_params: ReactorParams = null) -> void:
	state = PlantState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	params = reactor_params if reactor_params != null else ReactorParams.new()
	neutronics = Neutronics.new(params)
	# Start w rownowadze na mocy nominalnej (n=1).
	neutronics.initialize_steady_state(1.0)
	_sync_state()


## Ustawia reaktywnosc rho zadawana z zewnatrz (wejscie testowe/skryptowe w ETAP 1A).
func set_reactivity(value: float) -> void:
	_commanded_reactivity = value


## Wykonuje JEDEN krok symulacji o staly FIXED_DT.
## ETAP 1B: przed neutronika wejdzie obliczenie pelnego rho, po niej termohydraulika.
func step() -> void:
	state.tick += 1
	state.sim_time_seconds += FIXED_DT
	neutronics.step(_commanded_reactivity, FIXED_DT)
	_sync_state()


## Przepisuje wynik modeli fizycznych do serializowalnego PlantState (kanal dla UI/sieci).
func _sync_state() -> void:
	state.reactor_power_fraction = neutronics.get_power_fraction()
	state.reactivity = _commanded_reactivity
	state.reactor_period_seconds = neutronics.get_reactor_period()


## Posuwa symulacje o zadany realny czas, dzielac go na stale kroki FIXED_DT.
## Trwaly akumulator gwarantuje niezaleznosc fizyki od FPS i to, ze reszta czasu
## nie ginie, lecz przenosi sie do kolejnego wywolania (poprawnosc + brak dryfu).
## Epsilon kompensuje to, ze 0.02 s nie jest dokladnie reprezentowalne w double.
## Zwraca liczbe wykonanych krokow.
const _ACCUMULATOR_EPSILON: float = 1.0e-9

func advance(real_delta_seconds: float) -> int:
	var steps := 0
	_time_accumulator += real_delta_seconds
	while _time_accumulator >= FIXED_DT - _ACCUMULATOR_EPSILON:
		step()
		_time_accumulator -= FIXED_DT
		steps += 1
	return steps
