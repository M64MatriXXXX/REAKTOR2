extends GutTest

## Testy turbiny + generatora + sieci (ETAP 2C): para->MWe, bramka synchronizacji,
## zrzut obciazenia (overspeed -> BRU) spinajacy 2B+2C, regresja 2B.

const DT := 0.02

var _tp: TurbineParams
var _turb: Turbine


func before_each() -> void:
	_tp = TurbineParams.new()
	_turb = Turbine.new(_tp)


# --- Turbina (mechanika) ---

func test_disconnected_holds_no_admission() -> void:
	# Odlaczona turbina nie pobiera pary (governor zamyka), obroty synchroniczne - gotowa do sync.
	for i in range(int(round(5.0 / DT))):
		_turb.step(false, 1.0, DT)
	assert_almost_eq(_turb.get_steam_offtake(), 0.0, 1e-3, "Odlaczona: brak poboru pary")
	assert_almost_eq(_turb.get_speed(), 1.0, 1e-6, "Odlaczona: obroty synchroniczne (gotowa do sync)")


func test_connected_tracks_demand() -> void:
	_turb.synchronize()   # READY_TO_SYNC -> SYNCHRONIZED (start nominalny @ obroty 1.0)
	for i in range(int(round(8.0 / DT))):
		_turb.step(true, 1.0, DT)
	assert_almost_eq(_turb.get_steam_offtake(), 1.0, 1e-2, "Pod siecia admisja sledzi zapotrzebowanie")
	assert_almost_eq(_turb.get_speed(), 1.0, 1e-6, "Pod siecia obroty zablokowane na synchronicznych")


func test_load_rejection_overspeeds_and_trips() -> void:
	_turb.synchronize()
	for i in range(int(round(5.0 / DT))):
		_turb.step(true, 1.0, DT)   # pod obciazeniem
	var peak := 0.0
	for i in range(int(round(5.0 / DT))):
		_turb.step(false, 1.0, DT)  # zrzut obciazenia (rozlaczenie od sieci)
		peak = maxf(peak, _turb.get_speed())
	assert_true(_turb.is_tripped(), "Zrzut obciazenia -> overspeed -> trip turbiny")
	# Po tripie turbina STYGNIE (wybieg 2F-1) - sprawdzamy SZCZYT obrotow, nie wartosc koncowa.
	assert_gt(peak, _tp.overspeed_trip_fraction, "Obroty przekroczyly prog nadobrotowy")


# --- Generator: MWe + bramka sync ---

func test_electrical_output() -> void:
	var gen := Generator.new(_tp)
	assert_almost_eq(gen.electrical_output_mw(true, 1.0), 1000.0, 1e-6,
		"Pod siecia pelna admisja -> 1000 MWe")
	assert_eq(gen.electrical_output_mw(false, 1.0), 0.0, "Odlaczony -> 0 MWe")


func test_sync_gate_window() -> void:
	var gen := Generator.new(_tp)
	assert_true(gen.can_synchronize(1.0), "Obroty synchroniczne -> mozna zalaczyc")
	assert_true(gen.can_synchronize(1.0 + _tp.sync_tolerance * 0.5), "W oknie -> mozna")
	assert_false(gen.can_synchronize(1.10), "Daleko od synchronizmu -> NIE wolno zalaczyc")


# --- Integracja w Simulation ---

func test_steam_to_electrical_when_connected() -> void:
	var sim := Simulation.new(0)
	sim.set_grid_demand(1.0)
	assert_true(sim.synchronize_generator(), "Synchronizacja przy obrotach nominalnych OK")
	sim.advance(15.0)
	assert_true(sim.state.grid_connected, "Generator pod siecia")
	assert_almost_eq(sim.state.electrical_power_mw, 1000.0, 30.0, "Para -> ~1000 MWe")
	assert_almost_eq(sim.state.grid_frequency_hz, 50.0, 1e-3, "Czestotliwosc 50 Hz (zsynchronizowana)")


func test_unsynchronized_connection_is_failure_with_cause() -> void:
	# Doprowadzamy turbine do nadobrotow (zrzut obciazenia), potem proba ponownego
	# zalaczenia poza synchronizacja -> uszkodzenie generatora.
	var sim := Simulation.new(0)
	sim.set_grid_demand(1.0)
	sim.synchronize_generator()
	sim.advance(15.0)
	sim.reject_load()
	sim.advance(1.0)   # turbina rozpedzona (krotkie okno - potem wybieg ja wystudza)
	assert_gt(sim.state.turbine_speed, 1.05, "Turbina w nadobrotach poza oknem sync po zrzucie")
	sim.synchronize_generator()   # proba zalaczenia poza oknem sync
	assert_true(sim.is_failed(), "Zalaczenie poza synchronizacja -> awaria")
	assert_eq(sim.get_failure(), FailureConditions.Type.GENERATOR_DESYNC, "Przyczyna: desync")
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("poza synchronizacja"):
			found = true
	assert_true(found, "Log zdarzen zawiera przyczyne: zalaczenie poza synchronizacja")


func test_load_rejection_overspeed_and_bru_pickup() -> void:
	# KLUCZOWY TEST INTEGRACYJNY 2B+2C: siec -> turbina -> BRU -> cisnienie.
	var sim := Simulation.new(0)
	sim.set_grid_demand(1.0)
	sim.synchronize_generator()
	sim.advance(15.0)
	var dump_connected := sim.state.steam_dump_flow   # przy turbinie online zrzut maly
	var elec_connected := sim.state.electrical_power_mw
	assert_gt(elec_connected, 900.0, "Pod siecia turbina oddaje moc")

	sim.reject_load()
	sim.advance(10.0)
	assert_true(sim.state.turbine_tripped, "Zrzut obciazenia -> overspeed -> trip turbiny")
	assert_eq(sim.state.electrical_power_mw, 0.0, "Po rozlaczeniu brak mocy elektrycznej")
	assert_gt(sim.state.steam_dump_flow, dump_connected + 0.3,
		"BRU przejmuje pare po odcieciu turbiny (zrzut wyraznie rosnie)")
	assert_lt(sim.state.pressure_mpa, 8.5, "Cisnienie opanowane przez BRU (brak tripu cisnieniowego)")
	assert_false(sim.is_failed(), "Blok przetrwal zrzut obciazenia (BRU zadzialal)")


func test_nominal_turbine_offline_regression() -> void:
	# Domyslnie turbina offline -> zachowanie 2B (zrzut reguluje cisnienie 7 MPa).
	var sim := Simulation.new(0)
	sim.advance(20.0)
	assert_false(sim.state.grid_connected, "Domyslnie generator odlaczony")
	assert_eq(sim.state.electrical_power_mw, 0.0, "Brak mocy elektrycznej (turbina offline)")
	assert_false(sim.state.turbine_tripped, "Turbina nietknieta")
	assert_almost_eq(sim.state.pressure_mpa, 7.0, 0.05, "Cisnienie 7 MPa (zrzut reguluje, 2B)")


func test_determinism_and_serialization_with_turbine() -> void:
	var a := Simulation.new(5)
	var b := Simulation.new(5)
	a.set_grid_demand(0.8)
	b.set_grid_demand(0.8)
	a.synchronize_generator()
	b.synchronize_generator()
	a.advance(4.0)
	b.advance(4.0)
	assert_eq(a.state.to_dict(), b.state.to_dict(), "Determinizm z turbina/siecia")
	var restored := PlantState.new()
	restored.from_dict(a.state.to_dict())
	assert_eq(restored.to_dict(), a.state.to_dict(), "Roundtrip stanu z polami 2C")
