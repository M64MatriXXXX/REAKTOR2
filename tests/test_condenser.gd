extends GutTest

## Testy skraplacza + prozni + routingu BRU (ETAP 2D).
##
## Sedno: STOPNIOWANE zabezpieczenia prozni w WYMUSZONEJ kolejnosci (topologia przeplywu
## pary). Test kolejnosci (test_vacuum_loss_locks_bru_k_before_turbine_trip) ZAMRAZA relacje:
## interlock BRU-K MUSI zadzialac przed tripem turbiny, inaczej trip wepchnalby pare w
## umierajacy skraplacz -> CONDENSER_RUPTURE (zabezpieczenie = przyczyna awarii).

const DT := 0.02


# --- Jednostkowe: model prozni ---

func test_nominal_vacuum_steady() -> void:
	# Nominal (turbina offline, zrzut nominalny do skraplacza): proznia ~5 kPa, zrzut na BRU-K.
	var sim := Simulation.new(0)
	sim.advance(20.0)
	assert_almost_eq(sim.state.condenser_pressure_kpa, 5.0, 1.0, "Proznia nominalna ~5 kPa")
	assert_false(sim.state.bru_route_atmosphere, "Zrzut na BRU-K (skraplacz), nie atmosfera")
	assert_true(sim.state.bru_k_dumping, "Zrzut nominalny wplywa do skraplacza")
	assert_false(sim.is_failed(), "Nominal: brak awarii (regresja - 2D nie rusza nominału)")


func test_vacuum_degradation_raises_pressure() -> void:
	# Spadek sprawnosci ukladu prozni -> cisnienie skraplacza rosnie monotonicznie.
	var sim := Simulation.new(0)
	sim.set_vacuum_health(0.5)   # podloga prozni ~29 kPa
	sim.advance(2.0)
	var p_early := sim.state.condenser_pressure_kpa
	sim.advance(10.0)
	var p_late := sim.state.condenser_pressure_kpa
	assert_gt(p_late, p_early, "Cisnienie skraplacza rosnie w czasie przy utracie prozni")
	assert_gt(p_late, 20.0, "Degradacja podnosi cisnienie znaczaco ponad nominal")


func test_condenser_step_stays_finite_under_transients() -> void:
	# Sanity numeryczny: skoki doplywu i sprawnosci -> cisnienie skonczone, nie ponizej podlogi.
	var cp := CondenserParams.new()
	var c := Condenser.new(cp)
	for i in range(500):
		c.step(0.0, 1.0, DT)
	assert_almost_eq(c.get_pressure_kpa(), 5.0, 0.5, "Stabilizacja na ~5 kPa przy doplywie 1.0")
	c.set_vacuum_health(0.0)
	for i in range(500):
		c.step(2.0, 2.0, DT)   # gwaltowny doplyw + zerowa proznia
	assert_true(is_finite(c.get_pressure_kpa()), "Cisnienie skonczone pod transientem")
	assert_gt(c.get_pressure_kpa(), cp.min_pressure_kpa - 1e-6, "Cisnienie nie spada ponizej podlogi")


# --- Interlock BRU-K + trip turbiny ---

func test_bru_k_lockout_routes_to_atmosphere() -> void:
	# Przekroczenie progu lockout -> zrzut przelaczony K->A, skraplacz przestaje przyjmowac pare.
	var sim := Simulation.new(0)
	sim.set_vacuum_health(0.3)   # podloga ~39 kPa (przekracza lockout 20)
	sim.advance(15.0)
	assert_true(sim.state.bru_route_atmosphere, "Zrzut przelaczony na BRU-A (atmosfera)")
	assert_false(sim.state.bru_k_dumping, "Skraplacz nie przyjmuje juz zrzutu BRU-K")


func test_vacuum_loss_trips_turbine() -> void:
	# Gleboka utrata prozni (P >= prog tripu) -> trip turbiny, przyczyna w logu.
	var sim := Simulation.new(0)
	sim.set_grid_demand(1.0)
	sim.synchronize_generator()
	sim.advance(15.0)
	assert_false(sim.state.turbine_tripped, "Turbina pracuje przed utrata prozni")
	sim.set_vacuum_health(0.1)   # podloga ~49 kPa (przekracza trip 35)
	sim.advance(20.0)
	assert_true(sim.state.turbine_tripped, "Utrata prozni -> trip turbiny")
	assert_ne(sim.get_failure(), FailureConditions.Type.CONDENSER_RUPTURE,
		"Bez zrzutu BRU-K do skraplacza brak rozerwania (sama utrata prozni != katastrofa)")
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("utrata prozni"):
			found = true
	assert_true(found, "Log zawiera przyczyne tripu: utrata prozni skraplacza")


func test_bru_k_without_vacuum_ruptures_condenser() -> void:
	# Pulapka (aktywacja uspionego haka): zrzut BRU-K wymuszony bez prozni -> CONDENSER_RUPTURE.
	var sim := Simulation.new(0)
	sim.set_force_bru_k(true)     # interlock obejscie (override)
	sim.set_vacuum_health(0.0)    # podloga ~54 kPa (przekracza rupture 50)
	sim.advance(30.0)
	assert_true(sim.is_failed(), "Zrzut BRU-K bez prozni -> awaria")
	assert_eq(sim.get_failure(), FailureConditions.Type.CONDENSER_RUPTURE, "Przyczyna: rozerwanie skraplacza")
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("Rozerwanie skraplacza"):
			found = true
	assert_true(found, "Log zawiera przyczyne: rozerwanie skraplacza")


# --- TEST ZAMRAZAJACY RELACJE PROGOW (rdzen wymogu) ---

func test_vacuum_loss_locks_bru_k_before_turbine_trip() -> void:
	# Przy utracie prozni interlock BRU-K MUSI zadzialac PRZED tripem turbiny, a para musi
	# pojsc w BRU-A, nie w skraplacz. Zabezpiecza przed cicha regresja kolejnosci progow.
	var sim := Simulation.new(0)
	sim.set_vacuum_health(0.1)   # podloga ~49 kPa -> przejdzie przez lockout (20) i trip (35)

	var tick_lockout := -1
	var tick_trip := -1
	for i in range(int(round(30.0 / DT))):
		sim.step()
		if tick_lockout < 0 and sim.state.bru_route_atmosphere:
			tick_lockout = sim.state.tick
		if tick_trip < 0 and sim.state.turbine_tripped:
			tick_trip = sim.state.tick
		if tick_trip >= 0:
			break

	assert_gt(tick_lockout, -1, "Interlock BRU-K zadzialal (zrzut -> BRU-A)")
	assert_gt(tick_trip, -1, "Trip turbiny od utraty prozni nastapil")
	assert_lt(tick_lockout, tick_trip, "BRU-K odciety PRZED tripem turbiny (kolejnosc kaskadowa)")
	# W chwili tripu turbiny para NIE idzie w skraplacz (zrzut juz na BRU-A).
	assert_false(sim.state.bru_k_dumping, "Przy tripie turbiny skraplacz nie przyjmuje zrzutu BRU-K")
	assert_ne(sim.get_failure(), FailureConditions.Type.CONDENSER_RUPTURE,
		"Kolejnosc uchronila skraplacz (brak rozerwania)")


func test_threshold_relation_holds_in_defaults() -> void:
	# Statyczne zamrozenie relacji: lockout < trip < rupture (druga linia obrony obok validate()).
	var cp := CondenserParams.new()
	assert_lt(cp.bru_k_lockout_kpa, cp.turbine_trip_kpa, "lockout BRU-K < trip turbiny")
	assert_lt(cp.turbine_trip_kpa, cp.rupture_kpa, "trip turbiny < rozerwanie skraplacza")


# --- Integracja: pelny lancuch + determinizm ---

func test_full_vacuum_fail_chain_2b_2c_2d() -> void:
	# Lancuch 2B+2C+2D: turbina pod siecia -> utrata prozni -> trip turbiny -> separator
	# odzyskuje zrzut, ale interlock kieruje go na BRU-A (nie w skraplacz) -> blok przetrwa.
	var sim := Simulation.new(0)
	sim.set_grid_demand(1.0)
	sim.synchronize_generator()
	sim.advance(15.0)
	sim.set_vacuum_health(0.1)
	sim.advance(25.0)

	assert_true(sim.state.turbine_tripped, "Turbina tripnieta od utraty prozni")
	assert_gt(sim.state.steam_dump_flow, 0.3, "Po tripie turbiny separator odzyskuje zrzut (BRU)")
	assert_true(sim.state.bru_route_atmosphere, "Zrzut kierowany na BRU-A (skraplacz bez prozni)")
	assert_false(sim.state.bru_k_dumping, "Skraplacz chroniony - nie przyjmuje zrzutu")
	assert_ne(sim.get_failure(), FailureConditions.Type.CONDENSER_RUPTURE, "Brak rozerwania skraplacza")
	assert_lt(sim.state.pressure_mpa, 10.5, "Cisnienie obiegu opanowane (BRU-A odbiera pare)")


func test_determinism_and_serialization_with_condenser() -> void:
	var a := Simulation.new(5)
	var b := Simulation.new(5)
	a.set_vacuum_health(0.3)
	b.set_vacuum_health(0.3)
	a.advance(5.0)
	b.advance(5.0)
	assert_eq(a.state.to_dict(), b.state.to_dict(), "Determinizm z pętla prozni skraplacza")
	var restored := PlantState.new()
	restored.from_dict(a.state.to_dict())
	assert_eq(restored.to_dict(), a.state.to_dict(), "Roundtrip stanu z polami 2D")
