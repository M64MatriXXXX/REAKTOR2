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
var main_pumps: MainCirculationPumps
var steam_separators: SteamSeparators
var turbine: Turbine
var generator: Generator
var grid: Grid
var condenser: Condenser
var params: ReactorParams
var reactivity_params: ReactivityParams
var thermal_params: ThermalParams
var pump_params: PumpParams
var separator_params: SeparatorParams
var turbine_params: TurbineParams
var condenser_params: CondenserParams

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
var _xenon_reactivity: float = 0.0         # wklad ksenonu (hak do 1D)

# Routing zrzutu pary (ETAP 2D). Domyslnie zrzut idzie do skraplacza (BRU-K), jesli proznia
# zachowana; interlock przelacza na BRU-A (atmosfera). _force_bru_k OMIJA interlock (override
# operatorski / test pulapki CONDENSER_RUPTURE - zrzut wepchniety do skraplacza bez prozni).
var _force_bru_k: bool = false
var _bru_route_atmosphere: bool = false    # aktualna trasa zrzutu (true = BRU-A)
var _bru_a_logged: bool = false            # jednorazowy log przelaczenia na BRU-A

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
	pump_params = PumpParams.new()
	separator_params = SeparatorParams.new()
	turbine_params = TurbineParams.new()
	condenser_params = CondenserParams.new()

	neutronics = Neutronics.new(params)
	reactivity_model = ReactivityModel.new(reactivity_params)
	thermal_model = ThermalModel.new(thermal_params)
	decay_heat = DecayHeat.new(thermal_params)
	main_pumps = MainCirculationPumps.new(pump_params)
	steam_separators = SteamSeparators.new(separator_params)
	turbine = Turbine.new(turbine_params)
	generator = Generator.new(turbine_params)
	grid = Grid.new(turbine_params.synchronous_frequency_hz)
	condenser = Condenser.new(condenser_params)
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
	if not generator.can_synchronize(turbine.get_speed()):
		_log("Proba zalaczenia poza synchronizacja (obroty=%.3f)" % turbine.get_speed())
		_latch_failure(FailureConditions.Type.GENERATOR_DESYNC)
		return false
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

# --- Sterowanie skraplaczem / proznia (ETAP 2D) ---

## Degradacja/przywrocenie sprawnosci ukladu prozni (scenariusz utraty prozni). 1.0 = nominal.
func set_vacuum_health(health: float) -> void:
	condenser.set_vacuum_health(health)

## Wymuszenie zrzutu na BRU-K mimo interlocku (override operatorski). UWAGA: bez prozni
## prowadzi do CONDENSER_RUPTURE - sluzy do badania pulapki (i jej testu).
func set_force_bru_k(force: bool) -> void:
	_force_bru_k = force

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

	# 4) Cieplo powylaczeniowe: rezerwuar produktow rozpadu (trwa po SCRAM).
	decay_heat.step(fission_power, FIXED_DT)
	# Calkowite cieplo = czesc prompt (z rozszczepien) + decay (z rozpadu).
	var heat_fraction := thermal_params.prompt_heat_fraction * fission_power \
		+ decay_heat.get_decay_power_fraction()

	# 5) Pompy ГЦН (bezwladnosc) -> przeplyw chlodziwa. Tryb manualny ma pierwszenstwo.
	main_pumps.step(FIXED_DT)
	_coolant_flow_fraction = _manual_flow_value if _manual_flow_override \
		else main_pumps.get_flow_fraction()

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

	# 8) Separatory: produkcja pary (~ moc cieplna) - odbior (turbina + zrzut BRU) -> cisnienie.
	steam_separators.step(heat_fraction, turbine.get_steam_offtake(), FIXED_DT)

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
	state.grid_connected = grid.is_breaker_closed()
	state.grid_frequency_hz = grid.frequency_hz(turbine.get_speed())

	# Skraplacz / proznia / routing BRU (ETAP 2D).
	state.condenser_pressure_kpa = condenser.get_pressure_kpa()
	state.condenser_vacuum_fraction = condenser.vacuum_fraction()
	state.condenser_steam_inflow = condenser.get_steam_inflow()
	state.bru_route_atmosphere = _bru_route_atmosphere
	state.bru_k_dumping = condenser.is_dumping_to_condenser()

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
