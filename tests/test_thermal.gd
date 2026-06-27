extends GutTest

## Testy termohydrauliki (ETAP 1C): model 2-wezlowy + frakcja pustek.
## Sprawdzaja rownowage spojna z punktem odniesienia, kierunki reakcji i wrzenie.

const DT := 0.02

var _params: ThermalParams
var _model: ThermalModel


func before_each() -> void:
	_params = ThermalParams.new()
	_model = ThermalModel.new(_params)


# --- Rownowaga / spojnosc z punktem odniesienia ---

func test_steady_state_matches_reference_point() -> void:
	# Przy n=1 i pelnym przeplywie rownowaga musi trafic w punkty odniesienia
	# ReactivityParams: T_paliwa=800 K, T_chlodziwa=550 K, void=0.
	_model.initialize_steady_state(1.0)
	assert_almost_eq(_model.get_coolant_temp(), 550.0, 1e-6, "T_chlodziwa rownowagi = 550 K")
	assert_almost_eq(_model.get_fuel_temp(), 800.0, 1e-6, "T_paliwa rownowagi = 800 K")
	assert_almost_eq(_model.get_void_fraction(), 0.0, 1e-12, "void = 0 w nominale")


func test_equilibrium_is_a_fixed_point() -> void:
	# Krok przy n=1, flow=1 ze stanu rownowagi nie powinien ruszyc temperatur.
	_model.initialize_steady_state(1.0)
	for i in range(500):   # 10 s
		_model.step(1.0, 1.0, DT)
	assert_almost_eq(_model.get_coolant_temp(), 550.0, 1e-4, "Rownowaga stabilna (chlodziwo)")
	assert_almost_eq(_model.get_fuel_temp(), 800.0, 1e-4, "Rownowaga stabilna (paliwo)")
	assert_almost_eq(_model.get_void_fraction(), 0.0, 1e-12, "Brak pustek w rownowadze nominalnej")


# --- Kierunki reakcji ---

func test_higher_power_raises_temperatures() -> void:
	_model.initialize_steady_state(1.0)
	for i in range(3000):   # 60 s przy n=1.2 -> nowa, wyzsza rownowaga
		_model.step(1.2, 1.0, DT)
	assert_gt(_model.get_fuel_temp(), 800.0, "Wieksza moc -> wyzsza T_paliwa (napedza Doppler)")
	assert_gt(_model.get_coolant_temp(), 550.0, "Wieksza moc -> wyzsza T_chlodziwa")


func test_fuel_responds_faster_than_coolant_settles_eventually() -> void:
	# Po skoku mocy T_paliwa rosnie; sprawdzamy monotoniczny wzrost w pierwszych krokach.
	_model.initialize_steady_state(1.0)
	var prev := _model.get_fuel_temp()
	for i in range(50):
		_model.step(1.5, 1.0, DT)
		var now := _model.get_fuel_temp()
		assert_gt(now, prev - 1e-9, "T_paliwa rosnie monotonicznie po skoku mocy")
		prev = now


# --- Wrzenie / frakcja pustek ---

func test_no_void_below_saturation() -> void:
	# Pelny przeplyw, n=1 -> chlodziwo 550 K < T_sat 558 K -> brak pustek.
	_model.initialize_steady_state(1.0)
	for i in range(1000):
		_model.step(1.0, 1.0, DT)
	assert_eq(_model.get_void_fraction(), 0.0, "Ponizej nasycenia void = 0")


func test_reduced_flow_causes_boiling_and_void() -> void:
	# Spadek przeplywu -> chlodziwo przekracza T_sat -> pojawiaja sie pustki (RBMK).
	_model.initialize_steady_state(1.0)
	for i in range(5000):   # 100 s przy flow=0.4
		_model.step(1.0, 0.4, DT)
	# Rownowaga analityczna: T_c = 540 + 3.2e9/(0.4*3.2e8) = 565 K -> void = 0.02*7 = 0.14.
	assert_almost_eq(_model.get_coolant_temp(), 565.0, 0.5, "Niski przeplyw -> T_chlodziwa ~565 K")
	assert_gt(_model.get_void_fraction(), 0.0, "Niski przeplyw -> DODATNIA frakcja pustek")
	assert_almost_eq(_model.get_void_fraction(), 0.14, 0.02, "void ~0.14 przy flow=0.4")


func test_void_is_monotonic_in_inverse_flow() -> void:
	# Mniejszy przeplyw -> wieksze pustki (przy tej samej mocy).
	var void_high_flow := _settle_void(1.0, 0.7)
	var void_low_flow := _settle_void(1.0, 0.4)
	assert_gt(void_low_flow, void_high_flow, "Nizszy przeplyw daje wieksza frakcje pustek")


func test_void_capped_at_max() -> void:
	# Skrajnie niski przeplyw nie przekracza void_fraction_max.
	var v := _settle_void(1.0, 0.05)
	assert_lte(v, _params.void_fraction_max + 1e-12, "void nie przekracza maksimum")


# --- Stabilnosc numeryczna kroku cieplnego ---

func test_thermal_step_stays_finite_under_transients() -> void:
	_model.initialize_steady_state(1.0)
	for i in range(2000):
		var n := 1.0 + 0.5 * sin(i * 0.05)   # szarpany przebieg mocy
		var flow := 0.5 + 0.4 * cos(i * 0.03)
		_model.step(n, flow, DT)
		assert_true(is_finite(_model.get_fuel_temp()), "T_paliwa skonczona")
		assert_true(is_finite(_model.get_coolant_temp()), "T_chlodziwa skonczona")
		assert_between(_model.get_void_fraction(), 0.0, _params.void_fraction_max + 1e-9,
			"void w zakresie [0, max]")


## Pomocnik: ustala frakcje pustek dla zadanej mocy i przeplywu (dlugie dojscie do rownowagi).
func _settle_void(power: float, flow: float) -> float:
	var m := ThermalModel.new(_params)
	m.initialize_steady_state(1.0)
	for i in range(8000):
		m.step(power, flow, DT)
	return m.get_void_fraction()
