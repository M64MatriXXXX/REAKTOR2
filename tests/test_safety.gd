extends GutTest

## Testy warstwy bezpieczenstwa (ETAP 1E-1): maszyna stanow, RPS/sygnaly AZ,
## warunki przegranej oraz wymog przechwycenia meltdownu przy flow=0.5.


# --- Maszyna stanow ---

func test_state_machine_legal_transitions() -> void:
	var sm := ReactorStateMachine.new()
	# Sim startuje w OPERATE -> kontrolowane wylaczenie do SHUTDOWN.
	assert_eq(sm.get_state(), ReactorStateMachine.State.OPERATE, "Start w OPERATE")
	assert_true(sm.request(ReactorStateMachine.State.SHUTDOWN, true), "OPERATE->SHUTDOWN legalne")
	assert_true(sm.request(ReactorStateMachine.State.STARTUP, true), "SHUTDOWN->STARTUP przy interlockach")
	assert_true(sm.request(ReactorStateMachine.State.OPERATE, true), "STARTUP->OPERATE legalne")


func test_startup_blocked_without_interlocks() -> void:
	var sm := ReactorStateMachine.new()
	sm.request(ReactorStateMachine.State.SHUTDOWN, true)
	assert_false(sm.request(ReactorStateMachine.State.STARTUP, false),
		"SHUTDOWN->STARTUP zablokowane bez spelnionych interlockow")
	assert_eq(sm.get_state(), ReactorStateMachine.State.SHUTDOWN, "Stan bez zmiany")


func test_illegal_transition_rejected() -> void:
	var sm := ReactorStateMachine.new()
	sm.request(ReactorStateMachine.State.SHUTDOWN, true)
	assert_false(sm.request(ReactorStateMachine.State.OPERATE, true),
		"SHUTDOWN->OPERATE (z pominieciem STARTUP) nielegalne")


func test_scram_latches_until_manual_reset() -> void:
	var sm := ReactorStateMachine.new()
	assert_true(sm.trigger_scram(), "Pierwsze wejscie w SCRAM")
	assert_false(sm.trigger_scram(), "Ponowny SCRAM nie jest 'nowym' wejsciem")
	assert_true(sm.is_scrammed())
	assert_false(sm.request(ReactorStateMachine.State.OPERATE, true),
		"Ze SCRAM zwykle sterowanie nie wraca do pracy")
	assert_true(sm.reset_to_shutdown(), "Reczny reset ze SCRAM do SHUTDOWN")
	assert_eq(sm.get_state(), ReactorStateMachine.State.SHUTDOWN)


# --- RPS / sygnaly AZ ---

func _safe_state() -> PlantState:
	var s := PlantState.new()
	s.reactor_power_fraction = 1.0
	s.reactor_period_seconds = INF
	s.fuel_temp = 800.0
	s.coolant_temp = 550.0
	s.void_fraction = 0.0
	s.coolant_flow_fraction = 1.0
	return s


func test_rps_no_trip_at_nominal() -> void:
	var rps := ProtectionSystem.new(SafetyParams.new())
	assert_true(rps.evaluate(_safe_state(), false).is_empty(),
		"W nominale brak sygnalow AZ")


func test_rps_overpower_trip() -> void:
	var rps := ProtectionSystem.new(SafetyParams.new())
	var s := _safe_state()
	s.reactor_power_fraction = 1.2
	assert_true(TripSignal.Type.OVERPOWER in rps.evaluate(s, false), "Trip przemocowania")


func test_rps_period_trip_only_for_short_positive_period() -> void:
	var rps := ProtectionSystem.new(SafetyParams.new())
	var s := _safe_state()
	s.reactor_period_seconds = 10.0   # krotki dodatni okres = rozbieganie
	assert_true(TripSignal.Type.PERIOD in rps.evaluate(s, false), "Krotki okres -> trip")
	s.reactor_period_seconds = INF
	assert_false(TripSignal.Type.PERIOD in rps.evaluate(s, false), "Stabilna moc -> brak trip")
	s.reactor_period_seconds = -5.0   # ujemny = moc maleje, nie rozbiega
	assert_false(TripSignal.Type.PERIOD in rps.evaluate(s, false), "Ujemny okres -> brak trip")


func test_rps_fuel_temp_trip() -> void:
	var rps := ProtectionSystem.new(SafetyParams.new())
	var s := _safe_state()
	s.fuel_temp = 2900.0
	assert_true(TripSignal.Type.FUEL_TEMP in rps.evaluate(s, false), "Trip wysokiej temp. paliwa")


func test_rps_void_trip() -> void:
	var rps := ProtectionSystem.new(SafetyParams.new())
	var s := _safe_state()
	s.void_fraction = 0.8
	assert_true(TripSignal.Type.VOID in rps.evaluate(s, false), "Trip nadmiernego wrzenia")


func test_rps_low_flow_trip() -> void:
	var rps := ProtectionSystem.new(SafetyParams.new())
	var s := _safe_state()
	s.coolant_flow_fraction = 0.3
	assert_true(TripSignal.Type.LOW_FLOW in rps.evaluate(s, false), "Trip niskiego przeplywu")


func test_rps_manual_az5() -> void:
	var rps := ProtectionSystem.new(SafetyParams.new())
	assert_true(TripSignal.Type.MANUAL_AZ5 in rps.evaluate(_safe_state(), true),
		"Manualny AZ-5 zawsze daje sygnal")


# --- Warunki przegranej ---

func test_failure_meltdown_threshold() -> void:
	var fc := FailureConditions.new(SafetyParams.new())
	var s := _safe_state()
	s.fuel_temp = 3200.0
	assert_eq(fc.check(s), FailureConditions.Type.FUEL_MELTDOWN, "T_paliwa > 3120K -> meltdown")
	s.fuel_temp = 3000.0
	# 3000K: clad = 0.7*3000+0.3*550 = 2265 > 2120 -> i tak awaria koszulki, ale NIE meltdown.
	assert_ne(fc.check(s), FailureConditions.Type.FUEL_MELTDOWN, "Ponizej 3120K to nie meltdown")


func test_clad_proxy_weighting() -> void:
	var fc := FailureConditions.new(SafetyParams.new())
	var s := _safe_state()
	s.fuel_temp = 1000.0
	s.coolant_temp = 600.0
	# 0.7*1000 + 0.3*600 = 880
	assert_almost_eq(fc.clad_temp(s), 880.0, 1e-9, "Proxy koszulki wazone 0.7/0.3")


func test_clad_failure_before_meltdown() -> void:
	# Koszulka uszkadza sie przy nizszej temp. paliwa niz topnienie paliwa.
	var fc := FailureConditions.new(SafetyParams.new())
	var s := _safe_state()
	s.coolant_temp = 700.0
	s.fuel_temp = 2800.0   # clad = 0.7*2800+0.3*700 = 2170 > 2120, paliwo < 3120
	assert_eq(fc.check(s), FailureConditions.Type.CLAD_FAILURE,
		"Uszkodzenie koszulki przed meltdownem paliwa")


func test_failure_power_runaway() -> void:
	var sp := SafetyParams.new()
	var fc := FailureConditions.new(sp)
	var s := _safe_state()
	s.reactor_power_fraction = sp.power_runaway_fraction + 1.0
	assert_eq(fc.check(s), FailureConditions.Type.POWER_RUNAWAY, "Rozbieganie mocy -> awaria")


func test_no_failure_at_nominal() -> void:
	var fc := FailureConditions.new(SafetyParams.new())
	assert_eq(fc.check(_safe_state()), FailureConditions.Type.NONE, "Nominal bez awarii")


# --- Integracja w Simulation ---

func test_auto_scram_on_overpower() -> void:
	# Duzy impuls reaktywnosci w nominale -> RPS lapie przemocowanie/okres -> auto-SCRAM.
	# Sprawdzamy SAM moment zadzialania: tuz po przekroczeniu progu stan = SCRAM i prety ida w dol.
	var sim := Simulation.new(0)
	sim.set_external_reactivity(0.002)   # +200 pcm
	var guard := 0
	while sim.get_reactor_state() != ReactorStateMachine.State.SCRAM and guard < 3000:
		sim.step()
		guard += 1
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.SCRAM, "RPS wymusil SCRAM")
	assert_false(sim.state.active_trips.is_empty(), "W momencie SCRAM aktywny sygnal AZ")
	assert_false(sim.get_event_log().is_empty(), "Zdarzenie SCRAM zapisane w logu")
	# Po wygaszeniu prety wsuniete i moc spadla (zabezpieczenie zadzialalo).
	sim.advance(40.0)
	assert_gt(sim.state.rod_insertion, 0.9, "Prety pelne wsuniecie po SCRAM")
	assert_lt(sim.state.reactor_power_fraction, 1.0, "Moc spadla po SCRAM (reaktor podkrytyczny)")


func test_manual_az5_scrams_and_latches() -> void:
	var sim := Simulation.new(0)
	sim.scram()
	sim.advance(1.0)
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.SCRAM, "AZ-5 -> SCRAM")
	assert_false(sim.request_state(ReactorStateMachine.State.OPERATE),
		"Ze SCRAM nie wracamy do OPERATE zwyklym sterowaniem")
	assert_true(sim.reset_after_scram(), "Reczny reset po SCRAM")
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.SHUTDOWN, "Po resecie SHUTDOWN")


func test_meltdown_catches_low_flow_during_rise() -> void:
	# WYMOG (uzytkownik): prog meltdownu (3120 K) musi zlapac flow=0.5 W TRAKCIE
	# narastania temperatury, ZANIM model "ustabilizuje sie" na ~3860 K (stan
	# niefizyczny - paliwo juz stopione). Izolujemy prog meltdownu: koszulka i
	# rozbieganie wylaczone, RPS rozbrojony (brak interwencji), awarie aktywne.
	var sp := SafetyParams.new()
	sp.clad_failure_temp_k = 1.0e9       # izolacja: tylko meltdown lapie
	sp.power_runaway_fraction = 1.0e9
	var sim := Simulation.new(0, null, null, null, sp)
	sim.set_protection_enabled(false)
	sim.set_coolant_flow(0.5)

	var guard := 0
	while not sim.is_failed() and guard < 5000:   # max 100 s
		sim.step()
		guard += 1

	assert_true(sim.is_failed(), "Awaria wykryta")
	assert_eq(sim.get_failure(), FailureConditions.Type.FUEL_MELTDOWN, "Przyczyna: meltdown paliwa")
	assert_true(sim.state.fuel_temp >= 3120.0, "Zlapane na progu topnienia")
	assert_lt(sim.state.fuel_temp, 3860.0,
		"Zlapane w trakcie narastania, PRZED niefizyczna stabilizacja ~3860 K")
	assert_lt(sim.state.sim_time_seconds, 20.0, "Meltdown wczesnie (podczas ekskursji)")

	# Stan ZAMROZONY po awarii: dalsze advance() nic nie zmienia.
	var tick_at_fail := sim.state.tick
	var temp_at_fail := sim.state.fuel_temp
	var executed := sim.advance(50.0)
	assert_eq(executed, 0, "Po awarii advance() nie wykonuje krokow")
	assert_eq(sim.state.tick, tick_at_fail, "Tick zamrozony")
	assert_almost_eq(sim.state.fuel_temp, temp_at_fail, 1e-9,
		"Temp. paliwa nie 'dochodzi' do 3860 K - rdzen juz stopiony")


func test_default_layered_failure_low_flow_catches_before_plateau() -> void:
	# Domyslne progi (obrona warstwowa): przy flow=0.5 awaria latch'uje sie ZANIM
	# paliwo osiagnie niefizyczne ~3860 K (w praktyce pierwsza jest koszulka).
	var sim := Simulation.new(0)
	sim.set_protection_enabled(false)   # bez auto-SCRAM, by sprawdzic same warunki przegranej
	sim.set_coolant_flow(0.5)
	var guard := 0
	while not sim.is_failed() and guard < 5000:
		sim.step()
		guard += 1
	assert_true(sim.is_failed(), "Przy flow=0.5 nastepuje przegrana")
	assert_lt(sim.state.fuel_temp, 3860.0, "Zlapane przed niefizyczna stabilizacja")


func test_nominal_no_trip_no_failure() -> void:
	var sim := Simulation.new(0)
	sim.advance(60.0)
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.OPERATE, "Nominal: praca OPERATE")
	assert_false(sim.is_failed(), "Nominal: brak awarii")
	assert_true(sim.state.active_trips.is_empty(), "Nominal: brak sygnalow AZ")
