extends GutTest

## Testy ukladu wody zasilajacej + domkniecia petli masy (ETAP 2E).
##
## Sedno: (1) ZAMROZENIE bilansu masy - w zamknietej petli masa stala, jedyny ubytek to BRU-A;
## (2) feedwater jako wezel bezpieczenstwa - za malo wody -> osuszenie -> utrata chlodzenia
## rdzenia (sprzezenie wsteczne do ETAPU 1), za duzo -> porywanie wody do turbiny (graded);
## (3) regresja: poziom (2B) i hotwell (2D) wchodza BEZ przerabiania fizyki cisnienia/prozni.

const DT := 0.02


# --- (1) Bilans masy: zamrozenie inwariancji + ksiegowanie BRU-A ---

func test_closed_loop_mass_conserved() -> void:
	# ZAMROZENIE BILANSU: nominal USTALONY (turbina offline, brak BRU-A, make-up=0) -> masa stala.
	# Ustalone cisnienie jest swiadome: podczas transientu cisnieniowego masa pary w bebnie
	# zmienia sie (konwersja woda<->para), wiec masa wody nie bylaby idealnie stala bez wycieku.
	var sim := Simulation.new(0)
	sim.advance(2.0)
	var mass_early := sim.state.total_water_mass
	sim.advance(60.0)
	assert_almost_eq(sim.state.total_water_mass, mass_early, 0.02,
		"Zamknieta petla w ustalonym cisnieniu: masa wody zachowana")
	assert_almost_eq(sim.state.bru_a_lost_cumulative, 0.0, 1e-6, "Brak ubytku BRU-A w nominale")


func test_bru_a_loss_accounted() -> void:
	# Utrata prozni -> zrzut na BRU-A (atmosfera). Ubytek masy = DOKLADNIE skumulowany BRU-A.
	# Turbina offline -> magnituda zrzutu reguluje 7 MPa bez zmian, brak transientu cisnieniowego
	# separatora -> brak pozornego ubytku z konwersji woda<->para (czysty rachunek).
	var sim := Simulation.new(0)
	var mass_start := sim.state.total_water_mass
	sim.set_vacuum_health(0.1)
	sim.advance(20.0)
	var mass_lost := mass_start - sim.state.total_water_mass
	assert_gt(mass_lost, 0.3, "Masa ubywa po przejsciu zrzutu na BRU-A")
	assert_almost_eq(mass_lost, sim.state.bru_a_lost_cumulative, 0.05,
		"Ubytek masy = skumulowany ubytek BRU-A (jedyny policzalny kanal, jednostki poziomu)")


# --- (2) Feedwater jako wezel bezpieczenstwa ---

func test_nominal_feedwater_holds_separator_level() -> void:
	var sim := Simulation.new(0)
	sim.advance(30.0)
	assert_almost_eq(sim.state.separator_level, 1.0, 0.02, "Regulacja trzyma poziom separatora")
	assert_almost_eq(sim.state.deaerator_level, 1.0, 0.05, "Poziom deaeratora utrzymany")
	assert_almost_eq(sim.state.hotwell_level, 1.0, 0.05, "Poziom hotwellu utrzymany")


func test_feedwater_loss_dries_separator_and_starves_core() -> void:
	# Sprzezenie WSTECZNE do ETAPU 1: utrata feedwater -> osuszenie -> spadek przeplywu chlodziwa
	# -> przegrzanie rdzenia (istniejaca fizyka 1C/1E). RPS OFF, by power nie zostal scramowany
	# (badamy surowy lancuch do awarii rdzenia). Aktywuje hak ETAPU 1 nowa przyczyna.
	var sim := Simulation.new(0)
	sim.set_protection_enabled(false)   # bez auto-SCRAM (inaczej SCRAM zatrzymalby wrzenie)
	sim.fail_feedwater()
	var failed := false
	for i in range(int(round(150.0 / DT))):
		sim.step()
		if sim.is_failed():
			failed = true
			break
	assert_true(failed, "Utrata feedwater -> osuszenie -> przegrzanie -> awaria rdzenia")
	assert_lt(sim.state.separator_level, 0.3, "Separator osuszony (poziom ponizej lowlow)")
	var f := sim.get_failure()
	assert_true(f == FailureConditions.Type.FUEL_MELTDOWN \
			or f == FailureConditions.Type.CLAD_FAILURE \
			or f == FailureConditions.Type.POWER_RUNAWAY,
		"Awaria rdzenia z utraty chlodzenia (meltdown/koszulka/rozbieganie)")


func test_low_separator_level_trips_scram() -> void:
	# RPS ON: niski poziom separatora -> trip LOW_SEP_LEVEL -> SCRAM z przyczyna w logu.
	var sim := Simulation.new(0)
	sim.fail_feedwater()
	sim.advance(45.0)
	assert_lt(sim.state.reactor_power_fraction, 0.1, "SCRAM wsunal prety -> moc spadla")
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("Niski poziom wody"):
			found = true
	assert_true(found, "Log zawiera przyczyne SCRAM: niski poziom wody w separatorach")


func test_overfill_carryover_trips_turbine() -> void:
	# Za duzo wody (graded jak lockout->rupture w 2D): high -> ochronny trip turbiny;
	# high-high -> awaria TURBINE_WATER_INDUCTION (woda realnie w turbinie).
	var sim := Simulation.new(0)
	sim.set_feed_override(3.0)   # wymuszony nadmiar wody zasilajacej
	var failed := false
	for i in range(int(round(40.0 / DT))):
		sim.step()
		if sim.is_failed():
			failed = true
			break
	assert_true(sim.state.turbine_tripped, "Wysoki poziom -> ochronny trip turbiny")
	assert_true(failed, "Bardzo wysoki poziom -> awaria")
	assert_eq(sim.get_failure(), FailureConditions.Type.TURBINE_WATER_INDUCTION,
		"Przyczyna: porywanie wody do turbiny")
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("porywanie wody"):
			found = true
	assert_true(found, "Log zawiera przyczyne: porywanie wody do turbiny")


func test_deaerator_depletion_limits_feedwater() -> void:
	# Utrata pomp kondensatu -> deaerator nie jest uzupelniany -> opada do minimum ssania ->
	# pompy zasilajace traca ssanie -> przeplyw zasilajacy odciety. Protection/failures OFF,
	# by izolowac sam mechanizm zbiornika (bez SCRAM/awarii rdzenia jako zaklocenia).
	var sim := Simulation.new(0)
	sim.set_protection_enabled(false)
	sim.set_failure_states_enabled(false)
	sim.set_condensate_pump_running(false)   # brak doplywu do deaeratora
	sim.advance(60.0)
	assert_lt(sim.state.deaerator_level, 0.1, "Deaerator wyczerpany do minimum ssania")
	assert_lt(sim.state.feedwater_flow, 0.3, "Pompy zasilajace odciete (utrata ssania)")


# --- (3) Regresja: 2B i 2D nietkniete ---

func test_pressure_loop_2b_unchanged_with_level() -> void:
	# Warstwa poziomu NIE rusza petli cisnienia 2B - nominal trzyma 7 MPa jak przed 2E.
	var sim := Simulation.new(0)
	sim.advance(20.0)
	assert_almost_eq(sim.state.pressure_mpa, 7.0, 0.05, "Cisnienie 7 MPa (regulacja 2B nietknieta)")


func test_vacuum_loop_2d_unchanged_with_hotwell() -> void:
	# Warstwa hotwellu NIE rusza petli prozni 2D - nominal trzyma ~5 kPa, progi bez zmian.
	var sim := Simulation.new(0)
	sim.advance(20.0)
	assert_almost_eq(sim.state.condenser_pressure_kpa, 5.0, 1.0, "Proznia ~5 kPa (2D nietknieta)")
	assert_false(sim.is_failed(), "Nominal: brak awarii")


# --- Determinizm + sanity numeryczny ---

func test_feedwater_step_stays_finite() -> void:
	var fp := FeedwaterParams.new()
	var fw := Feedwater.new(fp)
	for i in range(500):
		fw.step(0.0, 0.0, 5.0, DT)   # pusty separator/hotwell, duzy strumien pary
	assert_true(is_finite(fw.get_feedwater_flow()), "Przeplyw zasilajacy skonczony")
	assert_true(is_finite(fw.get_deaerator_level()), "Poziom deaeratora skonczony")
	assert_gt(fw.get_deaerator_level(), -1e-6, "Poziom deaeratora nieujemny")


func test_determinism_and_serialization_with_feedwater() -> void:
	var a := Simulation.new(7)
	var b := Simulation.new(7)
	a.fail_feedwater()
	b.fail_feedwater()
	a.advance(4.0)
	b.advance(4.0)
	assert_eq(a.state.to_dict(), b.state.to_dict(), "Determinizm z petla masy wody")
	var restored := PlantState.new()
	restored.from_dict(a.state.to_dict())
	assert_eq(restored.to_dict(), a.state.to_dict(), "Roundtrip stanu z polami 2E")
