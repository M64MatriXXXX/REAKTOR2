extends GutTest

## Testy pelnej maszyny stanow turbiny + wybiegu + sprzezenia wybieg turbiny->pompy (ETAP 2F-1).
##
## Sedno: (1) FSM obudowuje bramke sync z 2C (cykl STOPPED->ROLLING->READY->SYNCHRONIZED,
## trip->TRIPPED z wybiegiem); (2) ZAMROZENIE sprzezenia wybiegu - podczas blackoutu przeplyw
## pomp ГЦН sledzi bezwladnosc wybiegajacej turbiny (krotszy wybieg turbiny -> nizszy przeplyw).

const DT := 0.02


# --- FSM: rozbieg / synchronizacja / wybieg ---

func test_roll_up_reaches_sync_speed() -> void:
	var tp := TurbineParams.new()
	tp.roll_time_s = 5.0
	var t := Turbine.new(tp)
	t.cold_start()
	assert_eq(t.get_state(), TurbineStateMachine.State.STOPPED, "Zimny start -> obracarka (STOPPED)")
	assert_almost_eq(t.get_speed(), 0.0, 1e-6, "Wirnik zatrzymany")
	t.roll()
	assert_eq(t.get_state(), TurbineStateMachine.State.ROLLING, "Rozbieg (ROLLING)")
	var reached := false
	for i in range(int(round(60.0 / DT))):
		t.step(false, 0.0, DT)
		if t.get_state() == TurbineStateMachine.State.READY_TO_SYNC:
			reached = true
			break
	assert_true(reached, "Rozbieg osiagnal obroty synchroniczne -> READY_TO_SYNC")
	assert_almost_eq(t.get_speed(), 1.0, tp.sync_tolerance + 1e-3, "Obroty ~ synchroniczne")


func test_cannot_synchronize_stopped_turbine() -> void:
	# Bramka sync (2C, obudowana): turbiny na obracarce (obroty 0) nie wolno zalaczyc.
	var sim := Simulation.new(0)
	sim.cold_start_turbine()
	assert_false(sim.synchronize_generator(), "Sync turbiny na obracarce zablokowana")
	assert_eq(sim.get_failure(), FailureConditions.Type.GENERATOR_DESYNC,
		"Proba sync poza oknem (obroty 0) -> desync")


func test_full_lifecycle_roll_sync_load() -> void:
	# Pelny cykl rozruchu turbiny: obracarka -> rozbieg -> sync -> obciazenie.
	var sim := Simulation.new(0)
	sim.turbine_params.roll_time_s = 5.0
	sim.cold_start_turbine()
	sim.roll_turbine()
	var ready := false
	for i in range(int(round(60.0 / DT))):
		sim.step()
		if sim.turbine.get_state() == TurbineStateMachine.State.READY_TO_SYNC:
			ready = true
			break
	assert_true(ready, "Turbina rozbiegnieta -> READY_TO_SYNC")
	sim.advance(0.5)   # obroty ustalone dokladnie na 1.0
	sim.set_grid_demand(1.0)
	assert_true(sim.synchronize_generator(), "Sync w oknie OK")
	assert_eq(sim.turbine.get_state(), TurbineStateMachine.State.SYNCHRONIZED, "Pod siecia")
	sim.advance(15.0)
	assert_gt(sim.state.electrical_power_mw, 900.0, "Pod siecia turbina oddaje moc")


func test_trip_coasts_down_to_zero() -> void:
	var tp := TurbineParams.new()
	tp.turbine_coast_down_time_s = 5.0
	var t := Turbine.new(tp)
	t.synchronize()
	for i in range(int(round(3.0 / DT))):
		t.step(true, 1.0, DT)
	t.trip()
	assert_eq(t.get_state(), TurbineStateMachine.State.TRIPPED, "Trip -> TRIPPED")
	for i in range(int(round(20.0 / DT))):
		t.step(false, 0.0, DT)
	assert_lt(t.get_speed(), 0.1, "Wirnik wystygl ku zeru (wybieg)")


# --- ZAMROZENIE sprzezenia wybieg turbiny -> pompy ---

func test_coastdown_couples_pump_flow_to_turbine_inertia() -> void:
	# Dwie identyczne symulacje, rozna bezwladnosc WYBIEGU turbiny. Podczas blackoutu pompy ГЦН
	# zasilane wybiegiem turbogeneratora -> przeplyw SLEDZI bezwladnosc turbiny. Krotszy wybieg
	# turbiny -> nizsza szyna zasilania -> nizszy przeplyw pomp. Zamraza domkniety dlug 2A/2C.
	var a := Simulation.new(0)
	var b := Simulation.new(0)
	b.turbine_params.turbine_coast_down_time_s = 5.0   # turbina B stygnie szybciej (A: 30s)
	a.set_protection_enabled(false); a.set_failure_states_enabled(false)
	b.set_protection_enabled(false); b.set_failure_states_enabled(false)
	a.trigger_blackout(); b.trigger_blackout()
	a.advance(8.0); b.advance(8.0)
	assert_lt(b.state.turbine_speed, a.state.turbine_speed, "Turbina B wystygla szybciej")
	assert_lt(b.state.pump_supply_fraction, a.state.pump_supply_fraction,
		"Szyna pomp B nizsza (sledzi wybieg turbiny)")
	assert_lt(b.state.coolant_flow_fraction, a.state.coolant_flow_fraction,
		"Przeplyw pomp B nizszy - sprzezenie wybieg turbiny -> pompy ГЦН")


func test_blackout_pumps_fed_by_coastdown_buys_time() -> void:
	# Blackout: pompy na wybiegu turbogeneratora -> przeplyw przez chwile wysoki (kupiony czas),
	# szyna zasilania ponizej pelnej (sledzi stygnaca turbine).
	var sim := Simulation.new(0)
	sim.set_protection_enabled(false)
	sim.set_failure_states_enabled(false)
	sim.trigger_blackout()
	sim.advance(3.0)
	assert_true(sim.state.blackout, "Blackout aktywny")
	assert_true(sim.state.turbine_tripped, "Turbina tripnieta w blackoucie")
	assert_lt(sim.state.pump_supply_fraction, 1.0, "Szyna pomp ponizej pelnej (wybieg)")
	assert_gt(sim.state.coolant_flow_fraction, 0.7, "Przeplyw wciaz wysoki (wybieg kupuje czas)")


func test_determinism_with_blackout() -> void:
	var a := Simulation.new(3)
	var b := Simulation.new(3)
	a.set_failure_states_enabled(false)
	b.set_failure_states_enabled(false)
	a.trigger_blackout()
	b.trigger_blackout()
	a.advance(3.0)
	b.advance(3.0)
	assert_eq(a.state.to_dict(), b.state.to_dict(), "Determinizm z blackoutem/wybiegiem turbiny")
