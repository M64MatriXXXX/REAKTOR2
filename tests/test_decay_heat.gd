extends GutTest

## Testy ciepla powylaczeniowego (decay heat) - ETAP 1E-2.
## Sedno: SCRAM zatrzymuje rozszczepienia, ale NIE cieplo z rozpadu produktow.

const DT := 0.02

var _params: ThermalParams
var _decay: DecayHeat


func before_each() -> void:
	_params = ThermalParams.new()
	_decay = DecayHeat.new(_params)


# --- Rownowaga ---

func test_equilibrium_about_6_6_percent() -> void:
	_decay.initialize_steady_state(1.0)
	assert_almost_eq(_decay.get_decay_power_fraction(), 0.066, 1e-6,
		"W rownowadze przy n=1 decay ~ 6.6% mocy")


func test_equilibrium_is_fixed_point() -> void:
	_decay.initialize_steady_state(1.0)
	for i in range(500):   # 10 s przy n=1
		_decay.step(1.0, DT)
	assert_almost_eq(_decay.get_decay_power_fraction(), 0.066, 1e-4,
		"Rownowaga decay stabilna przy stalej mocy")


func test_scales_with_power() -> void:
	_decay.initialize_steady_state(0.5)
	assert_almost_eq(_decay.get_decay_power_fraction(), 0.033, 1e-6,
		"Decay skaluje sie z poziomem mocy (0.5 -> 3.3%)")


# --- Persystencja po wylaczeniu ---

func test_decays_after_shutdown_monotone_and_positive() -> void:
	_decay.initialize_steady_state(1.0)
	var prev := _decay.get_decay_power_fraction()
	# Po SCRAM rozszczepienia gasna (n=0); decay maleje, ale POZOSTAJE dodatnie.
	for i in range(500):   # 10 s
		_decay.step(0.0, DT)
		var now := _decay.get_decay_power_fraction()
		assert_lt(now, prev + 1e-12, "Decay maleje monotonicznie po wylaczeniu")
		assert_gt(now, 0.0, "Decay pozostaje dodatnie (cieplo wciaz generowane)")
		prev = now


func test_decay_level_after_10s_in_way_wigner_band() -> void:
	_decay.initialize_steady_state(1.0)
	for i in range(500):   # 10 s po SCRAM
		_decay.step(0.0, DT)
	var frac := _decay.get_decay_power_fraction()
	# Way-Wigner ~0.066*10^-0.2 ~ 4.2%; model w przyblizonym pasmie.
	assert_between(frac, 0.03, 0.055, "Decay po 10 s w okolicy przyblizenia Way-Wigner (~4%)")


func test_no_decay_without_operating_history() -> void:
	_decay.initialize_steady_state(0.0)   # reaktor nigdy nie pracowal
	assert_eq(_decay.get_decay_power_fraction(), 0.0, "Bez historii mocy brak decay")
	for i in range(100):
		_decay.step(0.0, DT)
	assert_eq(_decay.get_decay_power_fraction(), 0.0, "Nadal zero (nie ma co rozpadac)")


# --- Integracja w Simulation: podloga cieplna i mechanika Fukushima ---

func test_thermal_floor_dominated_by_decay_after_scram() -> void:
	# Po SCRAM moc rozszczepien (n) gasnie, ale moc CIEPLNA ma podloge z rozpadu.
	var sim := Simulation.new(0)
	sim.advance(30.0)
	assert_almost_eq(sim.state.thermal_power_mw, 3200.0, 50.0, "Nominal: ~3200 MWth")
	sim.scram()
	sim.advance(60.0)   # chlodzenie utrzymane
	assert_lt(sim.state.reactor_power_fraction, 0.05, "Rozszczepienia praktycznie wygaszone")
	assert_gt(sim.state.decay_heat_fraction, 0.025, "Cieplo powylaczeniowe wciaz znaczace")
	assert_gt(sim.state.decay_heat_fraction, sim.state.reactor_power_fraction,
		"Po SCRAM cieplo z rozpadu PRZEWAZA nad rozszczepieniami")
	assert_gt(sim.state.thermal_power_mw, 80.0, "Moc cieplna ma podloge (decay), nie spada do 0")


func test_decay_heat_reheats_core_without_cooling() -> void:
	# Mechanika Fukushima: SCRAM + utrata chlodzenia -> decay heat dogrzewa rdzen.
	var sim_cooled := Simulation.new(0)
	sim_cooled.set_failure_states_enabled(false)   # badamy temp., nie koniec gry
	sim_cooled.advance(30.0)
	sim_cooled.scram()
	sim_cooled.advance(180.0)

	var sim_lost := Simulation.new(0)
	sim_lost.set_failure_states_enabled(false)
	sim_lost.advance(30.0)
	sim_lost.scram()
	sim_lost.set_coolant_flow(0.0)   # utrata chlodzenia razem ze SCRAM
	sim_lost.advance(180.0)

	assert_gt(sim_lost.state.fuel_temp, sim_cooled.state.fuel_temp + 150.0,
		"Bez chlodzenia rdzen znacznie cieplejszy (decay heat dogrzewa)")
	assert_gt(sim_lost.state.fuel_temp, 700.0,
		"Bez chlodzenia rdzen pozostaje goracy mimo wygaszenia reakcji")
