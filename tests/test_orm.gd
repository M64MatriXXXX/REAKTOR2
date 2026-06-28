extends GutTest

## Testy ORM i sprzezenia ORM->efektywny wsp. pustkowy (ETAP 1E-3a).
## Kluczowy (concern 1): przy NOMINALNYM ORM reaktor stabilny; niestabilnosc
## odblokowuje dopiero NISKI ORM (dodatnia petla nalozona na petle pustkowa).

const DT := 0.02

var _sp: SafetyParams
var _orm: ORM


func before_each() -> void:
	_sp = SafetyParams.new()
	_orm = ORM.new(_sp)


# --- Model ORM ---

func test_orm_scales_with_insertion() -> void:
	assert_almost_eq(_orm.equivalent_rods(0.0), 0.0, 1e-9, "Prety wyciagniete -> ORM 0")
	assert_almost_eq(_orm.equivalent_rods(1.0), _sp.orm_rods_scale, 1e-9, "Pelne wsuniecie -> ORM max")
	# Nominalna pozycja krytyczna (~0.2423) powinna dawac ORM ~30 (norma RBMK).
	var orm_nominal := _orm.equivalent_rods(0.2423)
	assert_between(orm_nominal, 28.0, 32.0, "ORM w nominale ~30 rownowaznych pretow")
	assert_gt(_orm.equivalent_rods(0.3), _orm.equivalent_rods(0.2),
		"Glebiej wsuniete prety -> wyzszy ORM (wiekszy zapas)")


func test_void_multiplier_unity_at_or_above_onset() -> void:
	# ORM >= onset -> mnoznik DOKLADNIE 1.0 (fizyka nominalna nietknieta).
	assert_almost_eq(_orm.void_coeff_multiplier(_sp.orm_onset_rods), 1.0, 1e-9,
		"Na progu onset mnoznik = 1.0")
	assert_almost_eq(_orm.void_coeff_multiplier(35.0), 1.0, 1e-9, "Powyzej onset mnoznik = 1.0")
	assert_almost_eq(_orm.void_coeff_multiplier(30.0), 1.0, 1e-9, "Nominalny ORM mnoznik = 1.0")


func test_void_multiplier_grows_below_onset() -> void:
	var m_low := _orm.void_coeff_multiplier(10.0)
	var m_lower := _orm.void_coeff_multiplier(2.0)
	assert_gt(m_low, 1.0, "Ponizej onset mnoznik > 1 (wzmocniony void)")
	assert_gt(m_lower, m_low, "Nizszy ORM -> wiekszy mnoznik (monotoniczne wzmocnienie)")
	# ORM=0 -> mnoznik = 1 + gain.
	assert_almost_eq(_orm.void_coeff_multiplier(0.0), 1.0 + _sp.orm_void_gain, 1e-9,
		"Przy ORM=0 mnoznik = 1 + orm_void_gain")


func test_orm_below_limit_flag() -> void:
	assert_true(_orm.is_below_limit(10.0), "ORM 10 < limit 15")
	assert_false(_orm.is_below_limit(30.0), "ORM 30 > limit")


# --- CONCERN 1: stabilnosc @ nominalny ORM, niestabilnosc @ niski ORM ---

func test_nominal_orm_stable_low_orm_unstable() -> void:
	# Ten sam maly impuls reaktywnosci w zamknietej petli (neutronika + kwazi-statyczne
	# sprzezenie moc->temp/void). Przy ORM nominalnym Doppler przewaza (tlumienie);
	# przy niskim ORM wzmocniony void przewaza (rozbieganie).
	# Zwracamy MAKSIMUM mocy w przebiegu (odporne na pozniejsze przepelnienie przy
	# silnym rozbieganiu - neutronika moze sklamrowac n do 0 po ekstremalnej ekskursji).
	var n_nominal := _run_loop(_orm.equivalent_rods(0.2423), 0.0005, 200.0)  # ORM ~30
	var n_low := _run_loop(8.0, 0.0005, 200.0)                               # ORM ~8

	assert_lt(n_nominal, 1.2, "Nominalny ORM: impuls wytlumiony (stabilnie)")
	assert_gt(n_low, 1.5, "Niski ORM: ten sam impuls rozbiega sie (niestabilnie)")
	assert_lt(n_nominal, n_low, "Niski ORM wyraznie destabilizuje wzgledem nominalnego")


func test_void_multiplier_one_reproduces_baseline() -> void:
	# Regresja: mnoznik=1 (nominalny ORM) daje DOKLADNIE bazowa fizoke 1C (nie zepsulismy nominalu).
	var rp := ReactivityParams.new()
	var model := ReactivityModel.new(rp)
	var base := model.void_reactivity(0.3)
	var with_mult := model.void_reactivity(0.3, 1.0)
	assert_almost_eq(with_mult, base, 1e-12, "Mnoznik 1.0 = bazowy wklad pustkowy")


## Zamknieta petla z konfigurowalnym mnoznikiem void (wyliczanym z ORM).
func _run_loop(orm_equiv: float, impulse: float, seconds: float) -> float:
	var rp := ReactivityParams.new()
	var model := ReactivityModel.new(rp)
	var neu := Neutronics.new(ReactorParams.new())
	neu.initialize_steady_state(1.0)
	var multiplier := _orm.void_coeff_multiplier(orm_equiv)
	var x_crit := model.critical_rod_insertion(rp.excess_reactivity)
	var k_fuel := 500.0
	var k_void := 0.15
	var steps := int(round(seconds / DT))
	var max_power := 0.0
	for i in range(steps):
		var n := neu.get_power_fraction()
		var inp := ReactivityInputs.new()
		inp.rod_insertion = x_crit
		inp.coolant_temp = rp.coolant_temp_ref
		inp.fuel_temp = rp.fuel_temp_ref + k_fuel * (n - 1.0)
		inp.void_fraction = rp.void_ref + k_void * (n - 1.0)
		inp.void_coeff_multiplier = multiplier
		inp.external_reactivity = impulse
		neu.step(model.total_reactivity(inp), DT)
		max_power = maxf(max_power, neu.get_power_fraction())
	return max_power


# --- LOW_ORM trip (interlock) zalezny od ery ---

func test_low_orm_trip_only_when_protection_enabled() -> void:
	var s := PlantState.new()
	s.reactor_power_fraction = 1.0
	s.reactor_period_seconds = INF
	s.fuel_temp = 800.0
	s.coolant_temp = 550.0
	s.coolant_flow_fraction = 1.0
	s.orm_equivalent_rods = 10.0   # ponizej limitu 15

	var rps_post := ProtectionSystem.new(SafetyParams.post_1986())
	assert_true(TripSignal.Type.LOW_ORM in rps_post.evaluate_raw(s, false),
		"Post-1986: niski ORM wyzwala interlock")

	var rps_pre := ProtectionSystem.new(SafetyParams.pre_1986())
	assert_false(TripSignal.Type.LOW_ORM in rps_pre.evaluate_raw(s, false),
		"Pre-1986: brak interlocku ORM (pulapka mozliwa)")
