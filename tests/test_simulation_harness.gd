extends GutTest

## Testy szkieletu ETAPU 0: petla stalokrokowa, determinizm, serializacja.
## Te testy NIE sprawdzaja fizyki (jeszcze jej nie ma) - tylko poprawnosc harnessu.

func test_fixed_dt_is_50hz() -> void:
	assert_almost_eq(Simulation.FIXED_DT, 0.02, 1e-9, "Krok fizyki powinien wynosic 0.02 s (50 Hz)")


func test_step_advances_time_by_fixed_dt() -> void:
	var sim := Simulation.new(0)
	sim.step()
	assert_eq(sim.state.tick, 1, "Po jednym kroku tick = 1")
	assert_almost_eq(sim.state.sim_time_seconds, Simulation.FIXED_DT, 1e-9, "Czas rosnie o staly dt")


func test_advance_runs_correct_number_of_steps() -> void:
	var sim := Simulation.new(0)
	var steps := sim.advance(1.0)   # 1 s przy 50 Hz -> 50 krokow
	assert_eq(steps, 50, "1 sekunda powinna dac 50 krokow")
	assert_eq(sim.state.tick, 50)


func test_determinism_same_seed_same_result() -> void:
	var a := Simulation.new(42)
	var b := Simulation.new(42)
	a.advance(2.0)
	b.advance(2.0)
	assert_eq(a.state.to_dict(), b.state.to_dict(), "To samo ziarno -> identyczny stan")


func test_plant_state_roundtrip_serialization() -> void:
	var sim := Simulation.new(1)
	sim.advance(0.5)
	var snapshot := sim.state.to_dict()
	var restored := PlantState.new()
	restored.from_dict(snapshot)
	assert_eq(restored.to_dict(), snapshot, "Serializacja tam i z powrotem zachowuje stan")
