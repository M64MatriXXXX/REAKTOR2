extends GutTest

## Testy sanity-check kinetyki punktowej (ETAP 1A).
## Walidacja fizyki: krytycznosc, rownowaga prekursorow, zgodnosc okresu reaktora
## z rownaniem inhour, stabilnosc numeryczna, determinizm.

const DT := 0.02   # krok symulacji [s] (50 Hz)

var _params: ReactorParams


func before_each() -> void:
	_params = ReactorParams.new()


## Pomocniczo: prowadzi kinetyke przez 'seconds' przy stalym rho, zwraca koncowe n.
func _run(rho: float, seconds: float, n0: float = 1.0) -> float:
	var neu := Neutronics.new(_params)
	neu.initialize_steady_state(n0)
	var steps := int(round(seconds / DT))
	for i in range(steps):
		neu.step(rho, DT)
	return neu.get_power_fraction()


## Rownanie inhour: f(omega) = Lambda*omega + sum beta_i*omega/(omega+lambda_i) - rho.
## Zwraca stabilny (najwiekszy) dodatni pierwiastek omega; okres T = 1/omega.
func _inhour_omega(rho: float) -> float:
	var lo := 1.0e-9
	var hi := 100.0
	for _iter in range(200):
		var mid := 0.5 * (lo + hi)
		if _inhour_f(mid, rho) > 0.0:
			hi = mid
		else:
			lo = mid
	return 0.5 * (lo + hi)


func _inhour_f(omega: float, rho: float) -> float:
	var value := _params.gen_time * omega - rho
	for i in range(_params.group_count()):
		value += _params.beta_groups[i] * omega / (omega + _params.lambda[i])
	return value


# --- Parametry ---

func test_total_beta_is_about_0_0065() -> void:
	assert_almost_eq(_params.total_beta(), 0.0065, 5.0e-5,
		"Calkowity udzial opoznionych neutronow U-235 ~= 0.0065")


# --- Krytycznosc ---

func test_critical_power_is_constant() -> void:
	# rho = 0, start w rownowadze -> moc stala (do precyzji maszynowej).
	var n_end := _run(0.0, 60.0, 1.0)
	assert_almost_eq(n_end, 1.0, 1.0e-6, "Przy rho=0 moc powinna pozostac stala")


func test_precursors_in_equilibrium_after_init() -> void:
	# Po initialize_steady_state pochodna dC_i/dt powinna byc ~0:
	#   (beta_i/Lambda)*n - lambda_i*C_i = 0
	var neu := Neutronics.new(_params)
	neu.initialize_steady_state(1.0)
	var c := neu.get_precursors()
	for i in range(_params.group_count()):
		var dcdt := (_params.beta_groups[i] / _params.gen_time) * 1.0 - _params.lambda[i] * c[i]
		assert_almost_eq(dcdt, 0.0, 1.0e-9, "Prekursor grupy %d powinien byc w rownowadze" % i)


# --- Reaktywnosc dodatnia: zgodnosc z okresem inhour ---

func test_positive_reactivity_period_matches_inhour() -> void:
	# Mierzymy okres e-skladania mocy w oknie asymptotycznym i porownujemy
	# z teoretycznym okresem z rownania inhour. To realna walidacja dynamiki.
	var rho := 0.001
	var neu := Neutronics.new(_params)
	neu.initialize_steady_state(1.0)

	# Okno pomiaru [150 s, 300 s] - na tyle pozno, by transjenty (najwolniejszy
	# mod zaniku ~kilkadziesiat s) zdazyly w duzej mierze zaniknac.
	var n_at_150 := 0.0
	var total := int(round(300.0 / DT))
	var t150 := int(round(150.0 / DT))
	for i in range(total):
		neu.step(rho, DT)
		if i + 1 == t150:
			n_at_150 = neu.get_power_fraction()
	var n_at_300 := neu.get_power_fraction()

	assert_gt(n_at_300, n_at_150, "Przy dodatniej reaktywnosci moc rosnie")

	var measured_period := 150.0 / log(n_at_300 / n_at_150)   # T = dt_okna / ln(n2/n1)
	var expected_period := 1.0 / _inhour_omega(rho)
	# Tolerancja 18%: blad backward Eulera + resztkowa niepelna asymptotyka.
	assert_almost_eq(measured_period, expected_period, expected_period * 0.18,
		"Zmierzony okres reaktora powinien byc zgodny z rownaniem inhour")


# --- Reaktywnosc ujemna ---

func test_negative_reactivity_decreases_power() -> void:
	var n_end := _run(-0.001, 30.0, 1.0)
	assert_lt(n_end, 1.0, "Przy ujemnej reaktywnosci moc maleje")
	assert_gt(n_end, 0.0, "Moc pozostaje dodatnia")
	assert_true(is_finite(n_end), "Brak NaN/inf")


func test_subcritical_decay_not_instant() -> void:
	# Silne ujemne rho (jak przy wlozeniu pretow): szybki spadek natychmiastowy,
	# potem powolny zanik z prekursorow - moc nie spada od razu do zera.
	var neu := Neutronics.new(_params)
	neu.initialize_steady_state(1.0)
	for i in range(int(round(0.1 / DT))):
		neu.step(-0.05, DT)
	var n_prompt := neu.get_power_fraction()
	assert_lt(n_prompt, 0.5, "Szybki spadek natychmiastowy (prompt drop)")
	assert_gt(n_prompt, 0.0, "Po prompt drop moc wciaz dodatnia (prekursory)")

	for i in range(int(round(10.0 / DT))):
		neu.step(-0.05, DT)
	var n_later := neu.get_power_fraction()
	assert_lt(n_later, n_prompt, "Moc dalej maleje wskutek rozpadu prekursorow")
	assert_gt(n_later, 0.0, "Moc nadal dodatnia, brak natychmiastowego zera")


# --- Stabilnosc numeryczna ---

func test_numerical_stability_long_run() -> void:
	for rho in [0.0, 0.001, -0.001]:
		var n_end := _run(rho, 60.0, 1.0)
		assert_true(is_finite(n_end), "rho=%f: wynik skonczony (brak NaN/inf)" % rho)
		assert_gt(n_end, 0.0, "rho=%f: moc dodatnia" % rho)


# --- Determinizm ---

func test_determinism_identical_runs() -> void:
	var a := Neutronics.new(ReactorParams.new())
	var b := Neutronics.new(ReactorParams.new())
	a.initialize_steady_state(1.0)
	b.initialize_steady_state(1.0)
	for i in range(500):
		a.step(0.0008, DT)
		b.step(0.0008, DT)
	assert_eq(a.get_power_fraction(), b.get_power_fraction(),
		"Te same wejscia -> identyczna moc")
	assert_eq(a.get_precursors(), b.get_precursors(),
		"Te same wejscia -> identyczne prekursory")


# --- Stan nadkrytyczny natychmiastowy (prompt critical) ---

func test_prompt_critical_rapid_growth_stays_finite() -> void:
	# rho > beta -> nadkrytycznosc NATYCHMIASTOWA (super prompt critical):
	# czlon natychmiastowy ((rho-beta)/Lambda) > 0 napedza gwaltowny wzrost mocy.
	# Wynik musi pozostac skonczony (zabezpieczenie mianownika przed inf/NaN).
	var rho := _params.total_beta() + 0.001
	var n_end := _run(rho, 1.0, 1.0)
	assert_gt(n_end, 10.0, "Przy rho>beta moc gwaltownie rosnie (ekskursja natychmiastowa)")
	assert_true(is_finite(n_end), "Wynik pozostaje skonczony mimo ekskursji")
