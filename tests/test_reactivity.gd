extends GutTest

## Testy bilansu reaktywnosci i sprzezen (ETAP 1B).
## Kluczowy: sanity-check ujemnego sprzezenia mocowego w rezimie referencyjnym
## (Doppler przewaza nad czlonem pustkowym -> maly impuls reaktywnosci jest tlumiony).

const DT := 0.02

var _params: ReactivityParams
var _model: ReactivityModel


func before_each() -> void:
	_params = ReactivityParams.new()
	_model = ReactivityModel.new(_params)


# --- Prety: krzywa S ---

func test_rod_worth_endpoints_and_midpoint() -> void:
	assert_almost_eq(_model.rod_reactivity(0.0), 0.0, 1e-12, "rho(0)=0 (prety wyciagniete)")
	assert_almost_eq(_model.rod_reactivity(1.0), -_params.total_rod_worth, 1e-9,
		"rho(1) = -W (pelne wsuniecie)")
	assert_almost_eq(_model.rod_reactivity(0.5), -_params.total_rod_worth * 0.5, 1e-9,
		"rho(0.5) = -W/2 (symetria krzywej S)")


func test_rod_worth_is_monotonic_decreasing() -> void:
	var prev := _model.rod_reactivity(0.0)
	for i in range(1, 21):
		var x := i / 20.0
		var val := _model.rod_reactivity(x)
		assert_lt(val, prev + 1e-12, "rho_rods maleje monotonicznie z zaglebieniem")
		prev = val


func test_rod_differential_worth_peaks_at_center() -> void:
	# Differential worth = |d rho/dx| ma maksimum w x=0.5.
	var h := 1e-4
	var deriv_center := absf(_model.rod_reactivity(0.5 + h) - _model.rod_reactivity(0.5 - h))
	var deriv_quarter := absf(_model.rod_reactivity(0.25 + h) - _model.rod_reactivity(0.25 - h))
	assert_gt(deriv_center, deriv_quarter,
		"Differential worth wiekszy w srodku rdzenia niz przy x=0.25")


# --- Doppler ---

func test_doppler_zero_at_reference() -> void:
	assert_almost_eq(_model.doppler_reactivity(_params.fuel_temp_ref), 0.0, 1e-12,
		"Doppler = 0 w temperaturze referencyjnej")


func test_doppler_negative_above_reference() -> void:
	assert_lt(_model.doppler_reactivity(_params.fuel_temp_ref + 100.0), 0.0,
		"Wzrost temp. paliwa -> ujemny wklad (sprzezenie stabilizujace)")
	assert_gt(_model.doppler_reactivity(_params.fuel_temp_ref - 100.0), 0.0,
		"Spadek temp. paliwa -> dodatni wklad")


func test_doppler_local_slope_about_minus_2_5_pcm_per_k() -> void:
	# Lokalna pochodna w T_ref powinna wynosic ~ -2.5 pcm/K = -2.5e-5 /K.
	var slope := _model.doppler_temp_derivative(_params.fuel_temp_ref)
	assert_almost_eq(slope, -2.5e-5, 0.2e-5, "Nachylenie Dopplera ~ -2.5 pcm/K w T_ref")


# --- Void (dodatni, RBMK) ---

func test_void_zero_at_reference_and_positive_above() -> void:
	assert_almost_eq(_model.void_reactivity(_params.void_ref), 0.0, 1e-12,
		"Void = 0 w punkcie odniesienia")
	assert_gt(_model.void_reactivity(0.5), 0.0,
		"Wzrost frakcji pustek -> DODATNI wklad (cecha RBMK)")


# --- Chlodziwo ---

func test_coolant_sign_follows_config() -> void:
	# Domyslnie coeff dodatni -> wzrost temp. chlodziwa daje dodatni wklad.
	var sign_above := _model.coolant_temp_reactivity(_params.coolant_temp_ref + 50.0)
	assert_eq(signf(sign_above), signf(_params.coolant_temp_coeff),
		"Znak wkladu chlodziwa zgodny z konfiguracja")


# --- Suma i rozbicie ---

func test_total_equals_sum_of_contributions() -> void:
	var inp := ReactivityInputs.new()
	inp.rod_insertion = 0.3
	inp.fuel_temp = 900.0
	inp.coolant_temp = 600.0
	inp.void_fraction = 0.2
	inp.xenon_reactivity = -0.001
	inp.external_reactivity = 0.0003
	var manual := _model.rod_reactivity(0.3) \
		+ _model.doppler_reactivity(900.0) \
		+ _model.void_reactivity(0.2) \
		+ _model.coolant_temp_reactivity(600.0) \
		+ (-0.001) + 0.0003 + _params.excess_reactivity
	assert_almost_eq(_model.total_reactivity(inp), manual, 1e-12,
		"total_reactivity = suma wszystkich wkladow + excess")


func test_breakdown_components_sum_to_total() -> void:
	var inp := ReactivityInputs.new()
	inp.rod_insertion = 0.4
	inp.fuel_temp = 850.0
	inp.coolant_temp = 560.0
	inp.void_fraction = 0.1
	var b := _model.reactivity_breakdown(inp)
	var sum: float = b["rods"] + b["doppler"] + b["void"] + b["coolant"] \
		+ b["xenon"] + b["external"] + b["excess"]
	assert_almost_eq(b["total"], sum, 1e-12, "Skladniki rozbicia sumuja sie do total")
	assert_almost_eq(b["total"], _model.total_reactivity(inp), 1e-12,
		"Rozbicie spojne z total_reactivity")


# --- Pozycja krytyczna ---

func test_critical_rod_insertion_zeroes_total_at_reference() -> void:
	var x_crit := _model.critical_rod_insertion(_params.excess_reactivity)
	assert_gt(x_crit, 0.0, "Pozycja krytyczna przy CZESCIOWYM wsunieciu (dzieki excess)")
	assert_lt(x_crit, 1.0)
	var inp := ReactivityInputs.at_reference(_params, x_crit)
	assert_almost_eq(_model.total_reactivity(inp), 0.0, 1e-7,
		"Przy pozycji krytycznej i referencji calkowite rho ~ 0")


# --- WSPOLCZYNNIK MOCOWY (kluczowy warunek realizmu) ---

func test_negative_power_coefficient_at_nominal() -> void:
	# Punkt nominalny: paliwo gorace i responsywne (duze dT/dP), pustki malo czule.
	# Doppler MUSI przewazyc -> ujemny power coefficient (stabilny normalny rezim).
	var dfuel_dp := 500.0   # K na jednostke mocy (reprezentatywne; 1C dostarczy realne)
	var dvoid_dp := 0.15    # void na jednostke mocy
	var alpha_power := _model.power_coefficient(_params.fuel_temp_ref, dfuel_dp, dvoid_dp)
	assert_lt(alpha_power, 0.0,
		"W punkcie nominalnym power coefficient < 0 (Doppler przewaza nad void)")


func test_positive_power_coefficient_at_low_power() -> void:
	# Niska moc: paliwo zimne i malo responsywne (male dT/dP), pustki bardzo czule.
	# Czlon pustkowy przewaza -> DODATNI power coefficient (rezim niestabilny "Czarnobyl").
	var dfuel_dp := 100.0
	var dvoid_dp := 0.5
	var alpha_power := _model.power_coefficient(_params.coolant_temp_ref, dfuel_dp, dvoid_dp)
	assert_gt(alpha_power, 0.0,
		"Przy niskiej mocy/duzych pustkach power coefficient > 0 (niestabilnosc)")


# --- DYNAMICZNY sanity-check: tlumienie impulsu vs runaway bez sprzezenia ---

func test_small_positive_impulse_is_damped_with_feedback() -> void:
	# Spinamy reaktywnosc z neutronika i kwazi-statycznym sprzezeniem moc->temp/void
	# (tylko w tescie; realne dynamiczne sprzezenie da 1C). Maly impuls +50 pcm:
	#  - ZE sprzezeniem (Doppler dominuje) -> moc ograniczona, nowy punkt rownowagi,
	#  - BEZ sprzezenia -> niepohamowany wzrost.
	var x_crit := _model.critical_rod_insertion(_params.excess_reactivity)
	var impulse := 0.0005           # +50 pcm
	var k_fuel := 500.0             # dT_fuel/dn (reprezentatywne nominalne)
	var k_void := 0.15             # dvoid/dn
	var seconds := 200.0

	var n_feedback := _run_closed_loop(x_crit, impulse, k_fuel, k_void, seconds, true)
	var n_no_feedback := _run_closed_loop(x_crit, impulse, k_fuel, k_void, seconds, false)

	assert_gt(n_feedback, 1.0, "Po impulsie moc nieco rosnie...")
	assert_lt(n_feedback, 1.2, "...ale jest TLUMIONA do nowego punktu rownowagi")
	assert_gt(n_no_feedback, 1.5, "Bez sprzezenia ten sam impuls daje niepohamowany wzrost")
	assert_lt(n_feedback, n_no_feedback,
		"Sprzezenie zwrotne wyraznie redukuje ekskursje mocy")


func test_impulse_response_settles() -> void:
	# Ze sprzezeniem moc ustala sie (na koncu praktycznie stala).
	var x_crit := _model.critical_rod_insertion(_params.excess_reactivity)
	var n_190 := _run_closed_loop(x_crit, 0.0005, 500.0, 0.15, 190.0, true)
	var n_200 := _run_closed_loop(x_crit, 0.0005, 500.0, 0.15, 200.0, true)
	assert_almost_eq(n_200, n_190, 5e-3, "Odpowiedz na impuls ustabilizowala sie")


## Zamknieta petla: neutronika + reaktywnosc z opcjonalnym kwazi-statycznym sprzezeniem.
func _run_closed_loop(x_crit: float, impulse: float, k_fuel: float, k_void: float,
		seconds: float, feedback: bool) -> float:
	var neu := Neutronics.new(ReactorParams.new())
	neu.initialize_steady_state(1.0)
	var steps := int(round(seconds / DT))
	for i in range(steps):
		var n := neu.get_power_fraction()
		var inp := ReactivityInputs.new()
		inp.rod_insertion = x_crit
		inp.coolant_temp = _params.coolant_temp_ref
		inp.external_reactivity = impulse
		if feedback:
			inp.fuel_temp = _params.fuel_temp_ref + k_fuel * (n - 1.0)
			inp.void_fraction = _params.void_ref + k_void * (n - 1.0)
		else:
			inp.fuel_temp = _params.fuel_temp_ref
			inp.void_fraction = _params.void_ref
		neu.step(_model.total_reactivity(inp), DT)
	return neu.get_power_fraction()
