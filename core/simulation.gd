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
var xenon: Xenon
var main_pumps: MainCirculationPumps
var steam_separators: SteamSeparators
var turbine: Turbine
var generator: Generator
var grid: Grid
var condenser: Condenser
var feedwater: Feedwater
var params: ReactorParams
var reactivity_params: ReactivityParams
var thermal_params: ThermalParams
var xenon_params: XenonParams
var pump_params: PumpParams
var separator_params: SeparatorParams
var turbine_params: TurbineParams
var condenser_params: CondenserParams
var feedwater_params: FeedwaterParams

# Warstwa bezpieczenstwa (ETAP 1E-1).
var safety_params: SafetyParams
var protection_system: ProtectionSystem
var failure_conditions: FailureConditions
var state_machine: ReactorStateMachine
var orm_model: ORM

# Stan cieplny CACHE - aktualizowany przez ThermalModel na koncu kazdego kroku,
# czytany przez bilans reaktywnosci w NASTEPNYM kroku (sprzezenie z opoznieniem 1 kroku).
var _fuel_temp: float = 0.0
var _coolant_temp: float = 0.0
var _void_fraction: float = 0.0
var _coolant_flow_fraction: float = 1.0    # wzgledny przeplyw chlodziwa 0..1 (zrodlo: pompy lub override)
# Tryb przeplywu (ETAP 2A): domyslnie z pomp ГЦН. set_coolant_flow() przelacza w jawny
# TRYB MANUALNY (override) - dla testow/scenariuszy ETAPU 1; UI ma jasno widziec zrodlo.
var _manual_flow_override: bool = false
var _manual_flow_value: float = 1.0
var _external_reactivity: float = 0.0      # bias zewnetrzny (scenariusze/testy)
var _xenon_reactivity: float = 0.0         # wklad ksenonu [Δρ] (ETAP 1D; 0 gdy wylaczony)
# Ksenon DOMYSLNIE WYLACZONY (jak enable_void_coupling / enable_positive_scram): worth ~-2700 pcm
# przy excess +500 pcm uczynilby reaktor podkrytycznym. Aktywacja + balans excess = GLOBALNE
# STROJENIE. OFF -> _xenon_reactivity=0, fizyka rdzenia jak dotad (168 testow nietkniete).
var _xenon_enabled: bool = false

# Routing zrzutu pary (ETAP 2D). Domyslnie zrzut idzie do skraplacza (BRU-K), jesli proznia
# zachowana; interlock przelacza na BRU-A (atmosfera). _force_bru_k OMIJA interlock (override
# operatorski / test pulapki CONDENSER_RUPTURE - zrzut wepchniety do skraplacza bez prozni).
var _force_bru_k: bool = false
var _bru_route_atmosphere: bool = false    # aktualna trasa zrzutu (true = BRU-A)
var _bru_a_logged: bool = false            # jednorazowy log przelaczenia na BRU-A

# Petla masy wody (ETAP 2E). Skumulowany ubytek przez BRU-A = jedyny policzalny kanal wycieku.
var _bru_a_lost_cumulative: float = 0.0
var _carryover_logged: bool = false        # jednorazowy log porywania wody do turbiny

# Blackout / wybieg (ETAP 2F-1). Utrata zasilania zewnetrznego: pompy ГЦН zasilane z
# wybiegajacego turbogeneratora (coast_down_output) zamiast sieci.
var _blackout: bool = false

# Diagnostyka GT-1: gdy true, produkcja pary = CHWILOWA moc (stary model, "para natychmiast"),
# zamiast cieplo-oddane-do-chlodziwa z 1C. Sluzy do CZYSTEGO porownania S (bez konfundu C_f).
var _steam_instant: bool = false

# Bezpieczenstwo (ETAP 1E-1).
var _manual_az5: bool = false              # zatrzasniety przycisk operatora AZ-5
var _protection_enabled: bool = true       # RPS uzbrojony (false = tryb "Czarnobyl")
var _failure_states_enabled: bool = true   # warunki przegranej aktywne (false = surowa fizyka)
var _failure: int = 0                       # FailureConditions.Type (0 = NONE); !=0 zamraza sim
var _event_log: Array[String] = []         # log zdarzen (alarmy/SCRAM/awaria) dla UI (ETAP 2)
var _orm_equivalent: float = 0.0           # ORM (rownowazne prety) - liczony co krok (1E-3)
var _positive_scram_reactivity: float = 0.0 # dodatni impuls efektu scramu (1E-3b)
var _scram_orm_deficit: float = 0.0        # deficyt ORM ZATRZASNIETY w chwili SCRAM (skala impulsu)

var _time_accumulator: float = 0.0
var _rng: RandomNumberGenerator


## PRESET TUNED (globalne strojenie GT-3): reaktor z pelna fizyka (excess pokrywajacy worth
## ksenonu + enable_xenon ON). Domyslna konfiguracja (Simulation.new) POZOSTAJE bazowa/uproszczona
## - dzieki temu eksperymenty stroją JEDNO sprzezenie naraz. Przelaczenie domyslnej na tuned =
## OSTATNI, jawny krok strojenia (koniec GT-5, po pelnej walidacji). Preset rosnie z kolejnymi
## wezlami (GT-4 void-coupling, GT-5 ORM...). Matched pair: excess ustawiony -> ksenon wlaczony.
static func tuned(seed_value: int = 0) -> Simulation:
	var rp := ReactivityParams.new()
	rp.excess_reactivity -= XenonParams.new().equilibrium_worth_nominal   # +|worth Xe| -> 0.032
	var sim := Simulation.new(seed_value, null, rp, null, null)
	sim.set_xenon_enabled(true)
	sim.reinitialize_critical()   # prety na pozycji krytycznej Z ksenonem (nominal 0.24)
	return sim


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
	xenon_params = XenonParams.new()
	pump_params = PumpParams.new()
	separator_params = SeparatorParams.new()
	turbine_params = TurbineParams.new()
	condenser_params = CondenserParams.new()
	feedwater_params = FeedwaterParams.new()

	neutronics = Neutronics.new(params)
	reactivity_model = ReactivityModel.new(reactivity_params)
	thermal_model = ThermalModel.new(thermal_params)
	decay_heat = DecayHeat.new(thermal_params)
	xenon = Xenon.new(xenon_params)
	main_pumps = MainCirculationPumps.new(pump_params)
	steam_separators = SteamSeparators.new(separator_params)
	turbine = Turbine.new(turbine_params)
	generator = Generator.new(turbine_params)
	grid = Grid.new(turbine_params.synchronous_frequency_hz)
	condenser = Condenser.new(condenser_params)
	feedwater = Feedwater.new(feedwater_params)
	protection_system = ProtectionSystem.new(safety_params)
	failure_conditions = FailureConditions.new(safety_params)
	state_machine = ReactorStateMachine.new()
	orm_model = ORM.new(safety_params)

	# Przeplyw startowy z pomp w konfiguracji nominalnej (6 czynnych -> 1.0).
	_coolant_flow_fraction = main_pumps.get_flow_fraction()
	# Cisnienie startowe = nastawa separatorow. Sprzezenie P->void (T_sat) domyslnie OFF
	# (dlug do globalnego strojenia) - bez niego T_sat pozostaje stale 558 K jak w 1C.
	if separator_params.enable_void_coupling:
		thermal_model.set_saturation_temp(steam_separators.saturation_temp())

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
	_orm_equivalent = orm_model.equivalent_rods(control_rods.get_insertion())
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
## INTERLOCK (2F-2): start reaktora (SHUTDOWN->STARTUP) wymaga przeplywu chlodziwa - odmowa z logiem.
func request_state(target: int) -> bool:
	var ok := state_machine.request(target, _start_interlocks_ok())
	if not ok and target == ReactorStateMachine.State.STARTUP \
			and state_machine.get_state() == ReactorStateMachine.State.SHUTDOWN \
			and _coolant_flow_fraction < safety_params.low_flow_trip_fraction:
		_log("Interlock: start reaktora zablokowany - za niski przeplyw chlodziwa (%.2f < %.2f)" % [
			_coolant_flow_fraction, safety_params.low_flow_trip_fraction])
	return ok

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

## Wlaczenie/wylaczenie wkladu reaktywnosci ksenonu (ETAP 1D). DOMYSLNIE OFF - patrz _xenon_enabled.
## UWAGA: przy wlaczeniu wymaga podniesienia excess_reactivity, by pokryc worth ksenonu (globalne strojenie).
func set_xenon_enabled(enabled: bool) -> void:
	_xenon_enabled = enabled

func is_xenon_enabled() -> bool:
	return _xenon_enabled

## Przelicza pozycje krytyczna pretow z uwzglednieniem rownowagi ksenonowej (GT-3) i ustawia
## na niej prety. Potrzebne po wlaczeniu ksenonu: bez tego prety staja na krytycznej dla samego
## excessu (za plytko), a ksenon czyni reaktor podkrytycznym. Z ksenonem: net = excess + rho_Xe.
func reinitialize_critical() -> void:
	var xenon_r := xenon.xenon_reactivity() if _xenon_enabled else 0.0
	# Wklad ksenonu MUSI byc spojny od pierwszego kroku (inaczej prety krytyczne-z-ksenonem +
	# _xenon_reactivity=0 -> reaktor prompt-nadkrytyczny na kroku 1). Ustawiamy go tu.
	_xenon_reactivity = xenon_r
	var crit := reactivity_model.critical_rod_insertion(reactivity_params.excess_reactivity + xenon_r)
	control_rods.set_position(crit)
	_orm_equivalent = orm_model.equivalent_rods(crit)
	_sync_state()

## Diagnostyka GT-1: produkcja pary = chwilowa moc (stary model) zamiast cieplo z 1C.
## Do czystego porownania S; NIE do normalnego uzytku (para powstaje z ciepla, nie z mocy).
func set_steam_instant(instant: bool) -> void:
	_steam_instant = instant

## Wymusza przeplyw chlodziwa 0..1 w jawnym TRYBIE MANUALNYM (override pomp ГЦН).
## Uzywane przez scenariusze/testy ETAPU 1; pompy sa wtedy pomijane jako zrodlo przeplywu.
## UPROSZCZENIE: bezposrednie zadanie przeplywu, bez bezwladnosci (ta jest w modelu pomp).
func set_coolant_flow(flow_fraction: float) -> void:
	_manual_flow_override = true
	_manual_flow_value = clampf(flow_fraction, 0.0, 1.0)

## Powrot do przeplywu sterowanego POMPAMI (wyjscie z trybu manualnego).
func use_pump_flow() -> void:
	_manual_flow_override = false

## Czy przeplyw pochodzi z trybu manualnego (override), czy z pomp (UI: zrodlo przeplywu).
func is_manual_flow() -> bool:
	return _manual_flow_override

# --- Sterowanie pompami ГЦН (ETAP 2A) ---
## Komenda zasilania pompy i (true = wlacz).
func set_pump_running(index: int, running: bool) -> void:
	main_pumps.set_pump_running(index, running)

## Awaria (zaciecie) pompy i.
func fail_pump(index: int) -> void:
	main_pumps.fail_pump(index)

## Ustawia liczbe czynnych pomp (pierwsze n wlaczone).
func set_pump_running_count(n: int) -> void:
	main_pumps.set_running_count(n)

## Utrata/przywrocenie odbioru pary (zrzut BRU). false -> cisnienie rosnie (ETAP 2B).
func set_dump_available(available: bool) -> void:
	steam_separators.set_dump_available(available)

# --- Sterowanie turbina / generatorem / siecia (ETAP 2C) ---

## Zadanie zapotrzebowania sieci (0..1 mocy nominalnej) - turbina sledzi pobor pary.
func set_grid_demand(demand_fraction: float) -> void:
	grid.set_demand(demand_fraction)

## Proba zalaczenia generatora do sieci. BRAMKA SYNCHRONIZACJI: poza oknem obrotow =
## uszkodzenie generatora (przegrana). Zwraca true, jesli zsynchronizowano i zalaczono.
func synchronize_generator() -> bool:
	if grid.is_breaker_closed():
		return true
	# INTERLOCK (2F-2): synchronizacja dozwolona tylko z turbiny gotowej (po rozbiegu).
	# Stan inny niz READY_TO_SYNC -> odmowa BEZ awarii (np. proba przed rozbiegiem / po tripie).
	if turbine.get_state() != TurbineStateMachine.State.READY_TO_SYNC:
		_log("Interlock: synchronizacja zablokowana - turbina nie gotowa (stan %s)" %
			turbine.state_machine.state_name())
		return false
	# Bramka 2C: w stanie READY, ale poza oknem obrotow -> zalaczenie = uszkodzenie generatora.
	if not generator.can_synchronize(turbine.get_speed()):
		_log("Proba zalaczenia poza synchronizacja (obroty=%.3f)" % turbine.get_speed())
		_latch_failure(FailureConditions.Type.GENERATOR_DESYNC)
		return false
	turbine.synchronize()   # FSM: READY_TO_SYNC -> SYNCHRONIZED (obudowuje bramke 2C)
	grid.close_breaker()
	_log("Generator zsynchronizowany i zalaczony do sieci")
	return true

## Zrzut obciazenia / rozlaczenie od sieci (load rejection) - turbina traci obciazenie.
func reject_load() -> void:
	if grid.is_breaker_closed():
		grid.open_breaker()
		_log("Zrzut obciazenia (rozlaczenie od sieci)")

## Reczny trip turbiny (zamkniecie zaworow).
func trip_turbine() -> void:
	turbine.trip()

## Zimny start turbiny: na obracarke (STOPPED). Procedura rozruchu (2F-2).
func cold_start_turbine() -> void:
	turbine.cold_start()

## Rozbieg turbiny na parze (STOPPED -> ROLLING). Zwraca true, jesli dozwolony.
## INTERLOCK (2F-2): rozbieg wymaga USTALONEJ PROZNI skraplacza i cisnienia pary - inaczej
## stygnaca turbina rozkrecana bez prozni / bez pary. Odmowa z przyczyna w logu.
func roll_turbine() -> bool:
	if condenser.get_pressure_kpa() > turbine_params.roll_min_vacuum_kpa:
		_log("Interlock: rozbieg turbiny zablokowany - brak prozni skraplacza (%.1f kPa)" %
			condenser.get_pressure_kpa())
		return false
	if steam_separators.get_pressure() < turbine_params.roll_min_pressure_mpa:
		_log("Interlock: rozbieg turbiny zablokowany - za niskie cisnienie pary (%.2f MPa)" %
			steam_separators.get_pressure())
		return false
	turbine.roll()
	return true

## Obciazenie turbiny (zadanie poboru pary). Zwraca true, jesli dozwolone.
## INTERLOCK (2F-2): obciazac wolno dopiero gdy generator POD SIECIA (po synchronizacji).
func request_load(demand: float) -> bool:
	if not turbine.is_synchronized() or not grid.is_breaker_closed():
		_log("Interlock: obciazenie zablokowane - generator nie pod siecia (stan turbiny %s)" %
			turbine.state_machine.state_name())
		return false
	grid.set_demand(clampf(demand, 0.0, 1.0))
	return true

## Krytyczna pozycja pretow przy aktualnym nadmiarze reaktywnosci (sterowanie mocy w 2F-2).
func get_critical_insertion() -> float:
	return reactivity_model.critical_rod_insertion(reactivity_params.excess_reactivity)

## Wlacza/zmienia zrodlo rozruchowe (podkrytyczna podloga umozliwiajaca rozruch z zimnego).
func set_neutron_source(source: float) -> void:
	params.neutron_source = maxf(0.0, source)

## Stawia blok w STANIE ZIMNYM (procedura wyjsciowa do rozruchu, 2F-2): reaktor SHUTDOWN,
## prety wsuniete, turbina na obracarce (STOPPED), niska moc gotowosci na zrodle rozruchowym.
## Pompy zostaja czynne (przeplyw konieczny do interlocku startu). cold_source - zrodlo (podloga).
func cold_shutdown(cold_source: float = 1.0e-3, standby_power: float = 0.01) -> void:
	state_machine.request(ReactorStateMachine.State.SHUTDOWN, true)
	control_rods.set_position(1.0)               # prety wsuniete (stan zimny, bez rampy)
	set_neutron_source(cold_source)              # zrodlo rozruchowe -> podkrytyczna podloga
	neutronics.initialize_steady_state(standby_power)
	decay_heat.initialize_steady_state(standby_power)
	xenon.initialize_equilibrium(0.0)             # czysty rdzen (ksenon zanika/zaniknal na zimno)
	turbine.cold_start()                          # turbina na obracarce
	if grid.is_breaker_closed():
		grid.open_breaker()
	_log("Blok w stanie zimnym (SHUTDOWN, prety wsuniete, turbina STOPPED, zrodlo rozruchowe)")

## Blackout (utrata zasilania zewnetrznego): turbina tripuje, a jej WYBIEG zasila pompy ГЦН
## (historyczny test wybiegu - turbogenerator "kupuje czas" pompom). Domyka dlug sprzezenia 2A/2C.
func trigger_blackout() -> void:
	if _blackout:
		return
	_blackout = true
	if grid.is_breaker_closed():
		grid.open_breaker()
	turbine.trip()
	_log("Blackout: utrata zasilania zewnetrznego - pompy ГЦН na wybiegu turbogeneratora")

# --- Sterowanie skraplaczem / proznia (ETAP 2D) ---

## Degradacja/przywrocenie sprawnosci ukladu prozni (scenariusz utraty prozni). 1.0 = nominal.
func set_vacuum_health(health: float) -> void:
	condenser.set_vacuum_health(health)

## Wymuszenie zrzutu na BRU-K mimo interlocku (override operatorski). UWAGA: bez prozni
## prowadzi do CONDENSER_RUPTURE - sluzy do badania pulapki (i jej testu).
func set_force_bru_k(force: bool) -> void:
	_force_bru_k = force

# --- Sterowanie woda zasilajaca / petla masy (ETAP 2E) ---

## Awaria/utrata zasilania pomp zasilajacych (wybieg do 0). Osuszenie separatorow -> utrata
## chlodzenia rdzenia (sprzezenie wsteczne do ETAPU 1 przez wspolczynnik chlodzenia).
func fail_feedwater() -> void:
	feedwater.set_feed_pump_running(false)

func set_feed_pump_running(running: bool) -> void:
	feedwater.set_feed_pump_running(running)

func set_condensate_pump_running(running: bool) -> void:
	feedwater.set_cond_pump_running(running)

## Dopływ wody uzupelniajacej (make-up). Domyslnie 0 (petla zamknieta - test inwariancji masy).
func set_makeup(flow: float) -> void:
	feedwater.set_makeup(flow)

## Jawne wymuszenie przeplywu zasilajacego (override regulacji) - scenariusz przelewu separatora.
func set_feed_override(flow: float) -> void:
	feedwater.set_feed_override(flow)

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

	# ORM z aktualnej pozycji pretow + efekt dodatniego scramu (1E-3).
	_orm_equivalent = orm_model.equivalent_rods(control_rods.get_insertion())
	_positive_scram_reactivity = _compute_positive_scram()

	# 2) Bilans reaktywnosci z aktualnego stanu. Stan cieplny pochodzi z KONCA
	#    poprzedniego kroku (sprzezenie z opoznieniem 1 kroku) - patrz naglowek.
	#    Niski ORM wzmacnia efektywny wsp. pustkowy (dodatnia petla na petli void).
	var inputs := ReactivityInputs.new()
	inputs.rod_insertion = control_rods.get_insertion()
	inputs.fuel_temp = _fuel_temp
	inputs.coolant_temp = _coolant_temp
	inputs.void_fraction = _void_fraction
	inputs.xenon_reactivity = _xenon_reactivity
	inputs.external_reactivity = _external_reactivity
	inputs.void_coeff_multiplier = orm_model.void_coeff_multiplier(_orm_equivalent)
	inputs.positive_scram_reactivity = _positive_scram_reactivity
	var rho := reactivity_model.total_reactivity(inputs)

	# 3) Neutronika (kinetyka punktowa) -> nowa moc rozszczepien.
	neutronics.step(rho, FIXED_DT)
	var fission_power := neutronics.get_power_fraction()

	# 3b) Ksenon (ETAP 1D): dynamika Xe/I napedzana strumieniem (~moc rozszczepien). Wklad
	#     reaktywnosci wchodzi w NASTEPNYM kroku (opoznienie 1 kroku, spojnie z reszta sprzezen).
	#     Domyslnie WYLACZONY -> _xenon_reactivity=0 (balans z excess -> globalne strojenie).
	xenon.step(fission_power, FIXED_DT)
	_xenon_reactivity = xenon.xenon_reactivity() if _xenon_enabled else 0.0

	# 4) Cieplo powylaczeniowe: rezerwuar produktow rozpadu (trwa po SCRAM).
	decay_heat.step(fission_power, FIXED_DT)
	# Calkowite cieplo = czesc prompt (z rozszczepien) + decay (z rozpadu).
	var heat_fraction := thermal_params.prompt_heat_fraction * fission_power \
		+ decay_heat.get_decay_power_fraction()

	# 5) Pompy ГЦН (bezwladnosc) -> przeplyw chlodziwa. Tryb manualny ma pierwszenstwo.
	#    SPRZEZENIE WSTECZNE 2E: osuszenie separatorow obniza efektywny przeplyw chlodziwa
	#    (mnoznik z KONCA poprzedniego kroku, opoznienie 1 kroku) - utrata wody krazacej.
	#    Przy nominalnym poziomie mnoznik = 1.0 (fizyka 1C/2A nietknieta).
	#    SPRZEZENIE WYBIEGU 2F-1: podczas blackoutu szyna pomp = wyjscie wybiegowe turbogeneratora
	#    (obroty turbiny z konca poprzedniego kroku) -> przeplyw pomp sledzi bezwladnosc turbiny.
	if _blackout:
		main_pumps.set_supply_fraction(generator.coast_down_output(turbine.get_speed()))
	main_pumps.step(FIXED_DT)
	var base_flow := _manual_flow_value if _manual_flow_override \
		else main_pumps.get_flow_fraction()
	_coolant_flow_fraction = base_flow * steam_separators.level_cooling_factor()

	# 6) Termohydraulika. Opcjonalne sprzezenie cisnienie->void (T_sat) z opoznieniem 1 kroku;
	#    domyslnie OFF (dlug do globalnego strojenia) -> T_sat stale 558 K, fizyka void jak w 1C.
	if separator_params.enable_void_coupling:
		thermal_model.set_saturation_temp(steam_separators.saturation_temp())
	thermal_model.step(heat_fraction, _coolant_flow_fraction, FIXED_DT)
	_fuel_temp = thermal_model.get_fuel_temp()
	_coolant_temp = thermal_model.get_coolant_temp()
	_void_fraction = thermal_model.get_void_fraction()

	# 7) Turbina: sledzi pobor pary (zapotrzebowanie sieci); pod siecia oddaje moc, po
	#    odlaczeniu rozpedza sie (overspeed). Para turbiny = odbior zewnetrzny separatorow.
	var was_tripped := turbine.is_tripped()
	turbine.step(grid.is_breaker_closed(), grid.get_demand(), FIXED_DT)
	if turbine.is_tripped() and not was_tripped:
		_log("Trip turbiny: zabezpieczenie nadobrotowe (obroty=%.3f)" % turbine.get_speed())

	# 8) Separatory: produkcja pary - odbior (turbina + zrzut BRU) -> cisnienie.
	#    GT-1 (strukturalny): produkcja pary = CIEPLO ODDANE DO CHLODZIWA z 1C (opoznione
	#    tau_f za moca), nie chwilowa moc. Rozwiazuje "para reaguje natychmiast" (napiecie K_P).
	var steam_production := heat_fraction if _steam_instant \
		else thermal_model.get_steam_production()
	steam_separators.step(steam_production, turbine.get_steam_offtake(), FIXED_DT)

	# 8b) Routing zrzutu BRU-K/BRU-A + skraplacz (ETAP 2D). Interlock BRU-K czyta ZMIERZONA
	#     proznie z KONCA POPRZEDNIEGO kroku (kauzalnie, opoznienie 1 kroku): zrzut idzie do
	#     skraplacza tylko z zachowana proznia - inaczej w atmosfere (BRU-A). _force_bru_k omija
	#     interlock (override / test pulapki). WYMUSZONA KOLEJNOSC: lockout (tu) PRZED tripem
	#     turbiny (nizej) - inaczej trip wepchnalby pare w umierajacy skraplacz (rupture).
	var dump_flow := steam_separators.get_dump_flow()
	var route_to_condenser := _force_bru_k or condenser.accepts_dump()
	_bru_route_atmosphere = (dump_flow > 0.0) and not route_to_condenser
	if _bru_route_atmosphere and not _bru_a_logged:
		_bru_a_logged = true
		_log("Interlock BRU-K: utrata prozni skraplacza -> zrzut przelaczony na BRU-A (atmosfera)")
	var bru_k_flow := dump_flow if route_to_condenser else 0.0
	condenser.step(turbine.get_steam_offtake(), bru_k_flow, FIXED_DT)

	# Warunek pracy turbiny: utrata prozni -> trip (dziala od nastepnego kroku; log teraz).
	if not condenser.vacuum_ok_for_turbine() and not turbine.is_tripped():
		turbine.trip()
		_log("Trip turbiny: utrata prozni skraplacza (P_skr=%.1f kPa)" % condenser.get_pressure_kpa())

	# Pulapka: zrzut BRU-K wpychany do skraplacza bez prozni -> rozerwanie skraplacza.
	# Przy DZIALAJACYM interlocku nie wystapi (zrzut juz na BRU-A); ujawnia sie po _force_bru_k.
	if condenser.is_dumping_to_condenser() \
			and condenser.get_pressure_kpa() >= condenser_params.rupture_kpa:
		_latch_failure(FailureConditions.Type.CONDENSER_RUPTURE)

	# 8c) Petla masy wody (ETAP 2E). Separator traci wode przez WRZENIE (steam_out = produkcja
	#     pary), zyskuje przez wode zasilajaca; hotwell zyskuje skroplona pare (to co dotarlo
	#     do skraplacza = turbina + BRU-K), traci przez pompy kondensatu. Regulacja feedwater
	#     trzyma poziom separatora. JEDYNY ubytek masy z petli to BRU-A (atmosfera).
	#     BRAMKA: tryb manualny przeplywu (set_coolant_flow) to ETAP-1 tryb surowej fizyki -
	#     OMIJA wtorny uklad wody (poziomy trzymane nominalnie, bez sprzezenia i tripow poziomu).
	if not _manual_flow_override:
		# Wrzenie = produkcja pary z 1C (opozniona, GT-1), spojnie z wejsciem separatora.
		var steam_out := steam_production * separator_params.steam_production_per_power
		var condensed_in := condenser.get_steam_inflow()
		feedwater.step(steam_separators.get_water_level(), condenser.get_hotwell_level(),
			steam_out, FIXED_DT)
		steam_separators.update_level(feedwater.get_feedwater_flow(), steam_out, FIXED_DT)
		condenser.update_hotwell(condensed_in, feedwater.get_condensate_flow(), FIXED_DT)

		# Ubytek BRU-A: zrzut na atmosfere = masa opuszczajaca petle (jedyny policzalny kanal).
		# Ksiegowany w jednostkach POZIOMU (dzielony przez pojemnosc), spojnie z masa zbiornikow,
		# by ΔM_total = ubytek BRU-A dokladnie (przy jednolitej pojemnosci rezerwuarow).
		var bru_a_flow := steam_separators.get_dump_flow() if _bru_route_atmosphere else 0.0
		_bru_a_lost_cumulative += bru_a_flow * FIXED_DT / separator_params.water_capacity

		# Przelew separatora -> porywanie wody do turbiny (graded, jak lockout->rupture w 2D):
		#   high  -> ochronny trip turbiny; high-high -> awaria (uderzenie wodne / induction).
		var sep_level := steam_separators.get_water_level()
		if sep_level >= safety_params.separator_level_highhigh_fail:
			_latch_failure(FailureConditions.Type.TURBINE_WATER_INDUCTION)
		elif sep_level >= safety_params.separator_level_high_trip and not turbine.is_tripped():
			turbine.trip()
			if not _carryover_logged:
				_carryover_logged = true
				_log("Trip turbiny: porywanie wody do turbiny (poziom separatora=%.2f)" % sep_level)

	_sync_state(inputs)

	# 9) Warstwa bezpieczenstwa (RPS nadrzedny): auto-SCRAM i warunki przegranej.
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
	state.pumps_running = main_pumps.running_count()
	state.thermal_power_mw = thermal_model.get_thermal_power_watts() / 1.0e6
	state.decay_heat_fraction = decay_heat.get_decay_power_fraction()
	state.iodine_conc = xenon.get_iodine()
	state.xenon_conc = xenon.get_xenon()
	state.orm_equivalent_rods = _orm_equivalent

	# Separatory / obieg parowy (ETAP 2B).
	state.pressure_mpa = steam_separators.get_pressure()
	state.steam_quality = steam_separators.steam_quality()
	state.steam_dump_flow = steam_separators.get_dump_flow()

	# Turbina / generator / siec (ETAP 2C).
	state.electrical_power_mw = generator.electrical_output_mw(
		grid.is_breaker_closed(), turbine.mechanical_power())
	state.turbine_speed = turbine.get_speed()
	state.turbine_tripped = turbine.is_tripped()
	state.turbine_state = turbine.get_state()
	state.grid_connected = grid.is_breaker_closed()
	state.grid_frequency_hz = grid.frequency_hz(turbine.get_speed())
	state.blackout = _blackout
	state.pump_supply_fraction = main_pumps.get_supply_fraction()

	# Skraplacz / proznia / routing BRU (ETAP 2D).
	state.condenser_pressure_kpa = condenser.get_pressure_kpa()
	state.condenser_vacuum_fraction = condenser.vacuum_fraction()
	state.condenser_steam_inflow = condenser.get_steam_inflow()
	state.bru_route_atmosphere = _bru_route_atmosphere
	state.bru_k_dumping = condenser.is_dumping_to_condenser()

	# Uklad wody zasilajacej / petla masy (ETAP 2E).
	state.separator_level = steam_separators.get_water_level()
	state.hotwell_level = condenser.get_hotwell_level()
	state.deaerator_level = feedwater.get_deaerator_level()
	state.feedwater_flow = feedwater.get_feedwater_flow()
	state.condensate_flow = feedwater.get_condensate_flow()
	state.makeup_flow = feedwater.get_makeup_flow()
	state.total_water_mass = state.separator_level + state.hotwell_level + state.deaerator_level
	state.bru_a_lost_cumulative = _bru_a_lost_cumulative

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
	state.rho_positive_scram = breakdown.get("positive_scram", 0.0)


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
		_latch_failure(failure_conditions.check(state))


## Zatrzask pierwszej awarii (zamraza symulacje). Wspolny dla RPS i zdarzen 2C
## (np. zalaczenie poza synchronizacja). NONE i awaria gdy juz przegrana - ignorowane.
func _latch_failure(f: int) -> void:
	if f == FailureConditions.Type.NONE:
		return
	if not _failure_states_enabled:
		return
	if _failure != FailureConditions.Type.NONE:
		return
	_failure = f
	state.failure_state = f
	state.failure_cause = FailureConditions.describe(f)
	_log("AWARIA: %s (T_paliwa=%.0fK, moc=%.2f, cisnienie=%.2fMPa)" % [
		state.failure_cause, state.fuel_temp,
		state.reactor_power_fraction, state.pressure_mpa])


## Efekt dodatniego scramu (grafitowe wyporniki) - ETAP 1E-3b.
## Przez pierwsze positive_scram_duration_s po wywolaniu SCRAM grafit wypiera wode z
## dolu rdzenia -> chwilowy DODATNI impuls, ZANIM absorber przewazy. Amplituda skalowana
## DEFICYTEM ORM: przy ORM >= onset = 0 (SCRAM czysto ujemny -> zawsze wylacza); przy
## niskim ORM rosnie do positive_scram_worth. Profil sin (narasta i wygasa po duration).
## Przy duzych pustkach + niskim ORM ten impuls moze wywolac rozbieganie (mechanizm RBMK).
func _compute_positive_scram() -> float:
	if not safety_params.enable_positive_scram_effect:
		return 0.0
	if not control_rods.is_scram_active():
		return 0.0
	var t := control_rods.get_scram_elapsed()
	var tau := safety_params.positive_scram_duration_s
	if t <= 0.0 or t >= tau:
		return 0.0
	# Amplituda wg ORM ZATRZASNIETEGO w chwili scramu (konfiguracja przed wsunieciem pretow),
	# nie wg rosnacego ORM podczas wsuwania - to konfiguracja startowa wyznacza efekt.
	var amplitude := safety_params.positive_scram_worth * _scram_orm_deficit
	return amplitude * sin(PI * t / tau)


## Wymusza SCRAM (RPS lub manual). Loguje przyczyne raz, przy nowym wejsciu w stan SCRAM.
func _trigger_scram(causes: Array[int]) -> void:
	if state_machine.trigger_scram():
		# Zatrzask deficytu ORM z konfiguracji w chwili scramu (skala efektu dodatniego).
		_scram_orm_deficit = orm_model.deficit_factor(_orm_equivalent)
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
