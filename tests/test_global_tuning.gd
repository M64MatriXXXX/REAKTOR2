extends GutTest

## GT-2 (globalne strojenie): ZAMROZENIE bilansu excess <-> worth ksenonu.
##
## Weryfikuje - BEZ zmiany domyslnej (excess i enable_xenon stosowane RAZEM dopiero w GT-3,
## matched pair) - ze podniesienie excess o worth ksenonu:
##  (1) przywraca krytycznosc w TYM SAMYM punkcie (prety ~0.24, ORM ~30) przy docelowym worthcie,
##  (2) utrzymuje BEZPIECZNY margines wylaczenia (prety pelni wsuniete = podkrytyczne) NAWET
##      w najgorszym przypadku, gdy ksenon zaniknal i juz NIE pomaga.
##
## To zamraza, ze excess = 3200 pcm to poprawna wartosc dla GT-3, zanim wlaczymy ksenon.

# Net reaktywnosci przy pretach pelni wsunietych musi byc PONIZEJ tego progu (~3*beta podkryt.).
const SAFE_SHUTDOWN_MARGIN := -0.02


func _baseline_excess() -> float:
	return ReactivityParams.new().excess_reactivity          # 0.005 (obecny domyslny)

func _xenon_worth() -> float:
	return XenonParams.new().equilibrium_worth_nominal        # -0.027 (docelowy)

func _excess_target() -> float:
	# excess docelowy = oryginalny margines operacyjny + pokrycie worthu ksenonu.
	return _baseline_excess() - _xenon_worth()                # 0.005 - (-0.027) = 0.032


func test_excess_target_covers_xenon_worth() -> void:
	assert_almost_eq(_excess_target(), 0.032, 1e-9,
		"excess docelowy = baseline + |worth ksenonu| (~3200 pcm)")
	# Net operating excess po ksenonie = oryginalny (para zwiazana - matched pair).
	assert_almost_eq(_excess_target() + _xenon_worth(), _baseline_excess(), 1e-9,
		"Net excess po ksenonie = oryginalny ~500 pcm")


func test_criticality_restored_at_same_point() -> void:
	var rm := ReactivityModel.new(ReactivityParams.new())
	var orm := ORM.new(SafetyParams.new())
	# Krytycznosc z docelowym excessem + ksenonem: net = excess_target + worth = baseline.
	var x_target := rm.critical_rod_insertion(_excess_target() + _xenon_worth())
	var x_baseline := rm.critical_rod_insertion(_baseline_excess())
	assert_almost_eq(x_target, x_baseline, 1e-6, "Krytycznosc odzyskana w TYM SAMYM punkcie pretow")
	assert_almost_eq(x_target, 0.2423, 1e-3, "Punkt krytyczny ~0.24 (nominal zachowany)")
	assert_almost_eq(orm.equivalent_rods(x_target), 30.0, 1.0, "ORM przy krytycznosci ~30 (norma RBMK)")


func test_tuned_preset_nominal_stable() -> void:
	# GT-3 (wezel X): preset tuned (excess=0.032 + enable_xenon, matched pair) - nominal stabilny
	# w tym samym punkcie co bazowy, z realnym ksenonem w rownowadze. Domyslna konfiguracja
	# (Simulation.new) POZOSTAJE bazowa/OFF - przelaczenie domyslnej na tuned to OSTATNI wezel DAG.
	var sim := Simulation.tuned(0)
	assert_true(sim.is_xenon_enabled(), "Preset tuned: ksenon WLACZONY")
	sim.advance(60.0)
	assert_almost_eq(sim.state.reactor_power_fraction, 1.0, 0.02, "Nominal tuned stabilny (moc ~1)")
	assert_almost_eq(sim.state.rho_xenon, -0.027, 1e-3, "rho_xenon w rownowadze nominalnej (~-2700 pcm)")
	assert_almost_eq(sim.state.rod_insertion, 0.2423, 1e-2, "Prety na krytycznej Z ksenonem (~0.24)")
	assert_almost_eq(sim.state.orm_equivalent_rods, 30.0, 1.5, "ORM ~30 (norma RBMK, matched pair)")
	assert_false(sim.is_failed(), "Nominal tuned bez awarii")


func test_default_config_untouched_by_tuning() -> void:
	# Regresja: domyslny reaktor NIETKNIETY (ksenon OFF, excess bazowy) - izolacja zachowana.
	var sim := Simulation.new(0)
	assert_false(sim.is_xenon_enabled(), "Domyslny: ksenon WYLACZONY")
	assert_almost_eq(sim.reactivity_params.excess_reactivity, 0.005, 1e-9, "Domyslny excess bazowy 500 pcm")


func test_shutdown_margin_safe_at_target_excess() -> void:
	var rm := ReactivityModel.new(ReactivityParams.new())
	# NAJGORSZY przypadek: ksenon zaniknal (=0) i juz NIE pomaga podkrytycznosci.
	# net(prety=1.0) = rho_rods(1.0) + excess_target.
	var shutdown_worst := rm.rod_reactivity(1.0) + _excess_target()
	assert_lt(shutdown_worst, SAFE_SHUTDOWN_MARGIN,
		"Prety pelni wsuniete podkrytyczne NAWET bez pomocy ksenonu (podniesiony excess nie zjadl marginesu)")
	# W chwili wylaczenia (ksenon jeszcze ~-2700) margines jest GLEBSZY.
	var shutdown_at := rm.rod_reactivity(1.0) + _excess_target() + _xenon_worth()
	assert_lt(shutdown_at, shutdown_worst, "Z ksenonem margines wylaczenia glebszy niz bez")
