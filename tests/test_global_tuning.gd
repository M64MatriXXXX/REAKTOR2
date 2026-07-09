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
	# Regresja: domyslny reaktor NIETKNIETY (ksenon OFF, void-coupling OFF, excess bazowy).
	var sim := Simulation.new(0)
	assert_false(sim.is_xenon_enabled(), "Domyslny: ksenon WYLACZONY")
	assert_false(sim.separator_params.enable_void_coupling, "Domyslny: void-coupling WYLACZONY")
	assert_almost_eq(sim.reactivity_params.excess_reactivity, 0.005, 1e-9, "Domyslny excess bazowy 500 pcm")


# --- GT-V (wezel V): void-coupling + K_P (fizyczne) + dtsat (stala tablicowa) ---

func test_dtsat_is_steam_table_constant() -> void:
	# dtsat to STALA FIZYCZNA (dT_sat/dP @7 MPa z tablic parowych ~9.7 K/MPa), NIE strojona.
	# Ten test broni granicy fizyka/galka: ktos "nastroi" dtsat -> test pada.
	assert_almost_eq(SeparatorParams.new().dtsat_dp, 9.7, 0.4,
		"dtsat = stala tablicowa dT_sat/dP @7 MPa (~9.7 K/MPa), nie parametr strojony")


func test_kp_gives_physical_drum_response_time() -> void:
	# K_P=0.15 dobrane z KRYTERIUM FIZYCZNEGO (nie na oko): czas odpowiedzi cisnienia bebna na
	# pelny niebilans (zrzut zamkniety) ~10 s - buforowanie bebnow RBMK, okno fizyczne ~10-20 s.
	var sim := Simulation.new(0)
	sim.separator_params.pressure_capacitance = 0.15
	sim.set_protection_enabled(false)
	sim.set_failure_states_enabled(false)
	sim.advance(2.0)
	sim.set_dump_available(false)
	var t_relief := -1.0
	for i in range(int(round(60.0 / 0.02))):
		sim.step()
		if sim.state.pressure_mpa >= 8.5:
			t_relief = sim.state.sim_time_seconds - 2.0
			break
	assert_gt(t_relief, 7.0, "K_P=0.15: odpowiedz cisnienia bebna w oknie fizycznym (dolna granica)")
	assert_lt(t_relief, 14.0, "K_P=0.15: odpowiedz cisnienia bebna ~10 s (gorna granica; kryterium, nie oko)")


func test_tuned_void_nominal_self_stabilizing() -> void:
	# (1a) REGRESJA samostabilizacji: przy nominale (void=0, bo 8 K ponizej wrzenia) wlaczenie
	# void-coupling NIE psuje stabilnosci - maly dodatni impuls tlumiony, power_coefficient < 0.
	# (To regresja, nie test funkcji void-coupling - ta jest usupiona przy void=0.)
	var sim := Simulation.tuned(0)
	sim.advance(10.0)
	var p0 := sim.state.reactor_power_fraction
	sim.set_external_reactivity(0.0005)   # +50 pcm
	sim.advance(40.0)
	var p1 := sim.state.reactor_power_fraction
	assert_lt(p1, 1.5, "Impuls +50 pcm: moc osiada na skonczonej rownowadze (nie rozbiega)")
	assert_gt(p1, p0, "Dodatni impuls -> wyzsza moc (nowa rownowaga)")
	assert_lt(-0.0005 / (p1 - p0), 0.0, "power_coefficient < 0 przy nominale (samostabilizacja, pelne sprzezenie)")
	assert_false(sim.is_failed(), "Nominal tuned+void bez awarii")


func test_void_coupling_recovers_reactor_from_excursion() -> void:
	# (1b, poziom EKSKURSJI) Void-coupling ODZYSKUJE reaktor z ekskursji wrzenia; bez niego runaway.
	# UWAGA: model void (1C) jest BISTABILNY - brak stabilnego UMIARKOWANEGO void, wiec test w
	# rezimie posrednim (jak chcial user) wymaga WZBOGACENIA MODELU void -> zadanie wezla O.
	# Tu dowodzimy tylko, ze void-coupling robi cos uzytecznego (recovery), nawet jesli na poziomie ekskursji.
	assert_lt(_excursion_final_power(true), 2.0, "Z void-coupling reaktor sie UTRZYMUJE (moc ograniczona)")
	assert_gt(_excursion_final_power(false), 5.0, "Bez void-coupling ekskursja ROZBIEGA sie (runaway)")


func _excursion_final_power(void_on: bool) -> float:
	var sim := Simulation.new(0)   # base+void (ksenon OFF) - izolacja efektu void-coupling
	sim.separator_params.enable_void_coupling = void_on
	sim.separator_params.pressure_capacitance = 0.15
	sim.set_protection_enabled(false)
	sim.set_failure_states_enabled(false)
	sim.advance(2.0)
	sim.set_coolant_flow(0.5)      # ponizej progu wrzenia -> ekskursja void-driven
	sim.advance(120.0)
	return sim.state.reactor_power_fraction


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
