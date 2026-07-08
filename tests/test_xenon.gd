extends GutTest

## Testy zatrucia ksenonowego Xe-135 / I-135 (ETAP 1D).
##
## IZOLACJA (duzy dt, bo dynamika godzinowa): rownowaga, punkt staly, narastanie, JAMA
## KSENONOWA po wylaczeniu (szczyt 9-11 h), glebokosc rosnie z moca, wypalanie tlumi Xe.
## INTEGRACJA (krok 50 Hz, w punkcie): wpiecie rho_xenon przez istniejacy hak; domyslnie OFF.

const DT_XE := 300.0   # 5 min - dynamika ksenonu jest godzinowa (backward Euler dt-agnostyczny)
const HOUR := 3600.0


# --- IZOLACJA: rownowaga i punkt staly ---

func test_equilibrium_worth_is_explicit_param() -> void:
	# Przy rownowadze nominalnej reaktywnosc = equilibrium_worth_nominal DOKLADNIE (jawny param).
	var xp := XenonParams.new()
	var xe := Xenon.new(xp)   # _init -> initialize_equilibrium(1.0)
	assert_almost_eq(xe.xenon_reactivity(), xp.equilibrium_worth_nominal, 1e-9,
		"Worth rownowagi = jawny parametr (~-2700 pcm)")


func test_equilibrium_is_fixed_point() -> void:
	var xe := Xenon.new(XenonParams.new())
	var xe0 := xe.get_xenon()
	var i0 := xe.get_iodine()
	for i in range(500):
		xe.step(1.0, DT_XE)
	assert_almost_eq(xe.get_xenon(), xe0, 1e-6, "Xe w rownowadze pozostaje staly (punkt staly)")
	assert_almost_eq(xe.get_iodine(), i0, 1e-6, "I w rownowadze pozostaje stale")


func test_buildup_from_clean_reaches_equilibrium() -> void:
	var xp := XenonParams.new()
	var xe := Xenon.new(xp)
	xe.initialize_equilibrium(0.0)          # czysty rdzen (I=Xe=0)
	var early := 0.0
	for i in range(int(round(6.0 * HOUR / DT_XE))):
		xe.step(1.0, DT_XE)
	early = xe.get_xenon()
	for i in range(int(round(60.0 * HOUR / DT_XE))):
		xe.step(1.0, DT_XE)
	assert_gt(early, 0.0, "Xe narasta z czystego rdzenia")
	assert_almost_eq(xe.xenon_reactivity(), xp.equilibrium_worth_nominal, 1e-3,
		"Po dostatecznym czasie narastanie osiaga rownowage nominalna")


# --- IZOLACJA: JAMA KSENONOWA (marquee) ---

func test_iodine_pit_after_shutdown() -> void:
	var xp := XenonParams.new()
	var xe := Xenon.new(xp)                 # rownowaga przy mocy nominalnej
	var eq_rho := xe.xenon_reactivity()
	var peak_rho := eq_rho
	var peak_t := 0.0
	var t := 0.0
	for i in range(int(round(30.0 * HOUR / DT_XE))):
		xe.step(0.0, DT_XE)                 # wylaczenie: strumien -> 0
		t += DT_XE
		if xe.xenon_reactivity() < peak_rho:
			peak_rho = xe.xenon_reactivity()
			peak_t = t
	assert_lt(peak_rho, eq_rho, "Jama: Xe rosnie po wylaczeniu -> rho glebiej ujemne niz rownowaga")
	assert_gt(peak_t, 5.0 * HOUR, "Szczyt jamy grubo po wylaczeniu (rzad ~9-11 h)")
	assert_lt(peak_t, 16.0 * HOUR, "Szczyt jamy w realnym oknie (nie natychmiast)")
	# Po szczycie Xe zanika - reaktywnosc wraca ku zeru.
	assert_gt(xe.xenon_reactivity(), peak_rho, "Po szczycie jama sie wyplyca (Xe zanika)")


func test_pit_deeper_at_higher_power() -> void:
	var deep := Xenon.new(XenonParams.new())
	deep.initialize_equilibrium(1.0)        # wysoka moc przed wylaczeniem
	var shallow := Xenon.new(XenonParams.new())
	shallow.initialize_equilibrium(0.4)     # niska moc przed wylaczeniem
	var peak_deep := deep.xenon_reactivity()
	var peak_shallow := shallow.xenon_reactivity()
	for i in range(int(round(30.0 * HOUR / DT_XE))):
		deep.step(0.0, DT_XE)
		shallow.step(0.0, DT_XE)
		peak_deep = minf(peak_deep, deep.xenon_reactivity())
		peak_shallow = minf(peak_shallow, shallow.xenon_reactivity())
	assert_lt(peak_deep, peak_shallow, "Wyzsza moc przed wylaczeniem -> glebsza jama")


# --- IZOLACJA: wlasnosci ---

func test_xenon_reactivity_non_positive() -> void:
	var xe := Xenon.new(XenonParams.new())
	xe.initialize_equilibrium(0.0)
	for i in range(int(round(40.0 * HOUR / DT_XE))):
		xe.step(1.0, DT_XE)
		assert_lte(xe.xenon_reactivity(), 0.0, "Ksenon jest absorberem -> rho <= 0")


func test_burnup_suppresses_xenon_at_power() -> void:
	var with_burnup := XenonParams.new()          # burnup_rate_nominal = 3e-5
	var no_burnup := XenonParams.new()
	no_burnup.burnup_rate_nominal = 0.0
	var a := Xenon.new(with_burnup)
	var b := Xenon.new(no_burnup)
	assert_lt(a.get_xenon(), b.get_xenon(),
		"Wypalanie neutronowe trzyma Xe przy mocy PONIZEJ poziomu bez wypalania")


func test_step_finite_and_deterministic() -> void:
	var a := Xenon.new(XenonParams.new())
	var b := Xenon.new(XenonParams.new())
	for i in range(300):
		a.step(1.5, DT_XE)
		b.step(1.5, DT_XE)
	assert_true(is_finite(a.get_xenon()), "Xe skonczone")
	assert_eq(a.get_xenon(), b.get_xenon(), "Te same wejscia -> identyczne Xe (determinizm)")
	assert_eq(a.get_iodine(), b.get_iodine(), "Te same wejscia -> identyczne I")


# --- INTEGRACJA: wpiecie przez hak (w punkcie; pelna jama zwalidowana w izolacji) ---

func test_xenon_wired_into_reactivity_when_enabled() -> void:
	var sim := Simulation.new(0)
	sim.set_xenon_enabled(true)
	sim.advance(1.0)                        # wklad wchodzi z opoznieniem 1 kroku
	assert_lt(sim.state.rho_xenon, 0.0, "Wlaczony ksenon wnosi ujemna reaktywnosc")
	assert_almost_eq(sim.state.rho_xenon, sim.xenon_params.equilibrium_worth_nominal, 1e-3,
		"rho_xenon w stanie = worth rownowagi (wpiety przez hak)")
	assert_gt(sim.state.xenon_conc, 0.0, "Stezenie Xe raportowane w stanie")


func test_xenon_disabled_by_default_regression() -> void:
	var sim := Simulation.new(0)            # domyslnie OFF
	assert_false(sim.is_xenon_enabled(), "Ksenon domyslnie WYLACZONY")
	sim.advance(5.0)
	assert_eq(sim.state.rho_xenon, 0.0, "Wylaczony ksenon -> brak wkladu (168 testow nietkniete)")
	assert_almost_eq(sim.state.reactor_power_fraction, 1.0, 0.05, "Nominal nietkniety")
	assert_false(sim.is_failed(), "Brak awarii")
