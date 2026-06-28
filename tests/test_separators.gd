extends GutTest

## Testy separatorow / petli cisnienia (ETAP 2B): stabilnosc, T_sat(P), oraz
## aktywacja (dotad uspionego) haka cisnienia - trip i rozerwanie obiegu.

const DT := 0.02

var _params: SeparatorParams
var _sep: SteamSeparators


func before_each() -> void:
	_params = SeparatorParams.new()
	_sep = SteamSeparators.new(_params)


func _settle(production: float, external: float, seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		_sep.step(production, external, DT)


# --- Petla cisnienia: rownowaga i monotonicznosc ---

func test_nominal_pressure_stable() -> void:
	_settle(1.0, 0.0, 30.0)
	assert_almost_eq(_sep.get_pressure(), _params.pressure_setpoint, 1e-3,
		"Produkcja 1.0 = zrzut -> cisnienie stabilne na nastawie ~7 MPa")
	assert_almost_eq(_sep.get_dump_flow(), 1.0, 1e-3, "Zrzut rownowazy nominalna produkcje")


func test_steam_quality() -> void:
	assert_almost_eq(_sep.steam_quality(), 0.15, 1e-9, "Jakosc pary na wylocie ~15%")


func test_higher_production_raises_equilibrium_pressure() -> void:
	var sep_low := SteamSeparators.new(SeparatorParams.new())
	for i in range(int(round(40.0 / DT))):
		sep_low.step(1.0, 0.0, DT)
	var sep_high := SteamSeparators.new(SeparatorParams.new())
	for i in range(int(round(40.0 / DT))):
		sep_high.step(1.8, 0.0, DT)
	assert_gt(sep_high.get_pressure(), sep_low.get_pressure(),
		"Wieksza produkcja pary -> wyzsze cisnienie rownowagi")


func test_pressure_backward_euler_no_oscillation() -> void:
	# Po naglym skoku niebilansu pary cisnienie dochodzi MONOTONICZNIE do nowej
	# rownowagi - backward Euler, bez oscylacji/overshootu (wolna dynamika pojemnosciowa).
	_settle(1.0, 0.0, 20.0)
	var prev := _sep.get_pressure()
	for i in range(int(round(40.0 / DT))):
		_sep.step(1.8, 0.0, DT)   # skok produkcji w gore
		var now := _sep.get_pressure()
		assert_gt(now, prev - 1e-9, "Cisnienie rosnie monotonicznie (brak oscylacji)")
		prev = now


# --- T_sat(P) ---

func test_tsat_increases_with_pressure() -> void:
	assert_almost_eq(_sep.saturation_temp(), _params.tsat_ref, 1e-9,
		"Przy nastawie 7 MPa T_sat = 558 K (spojne z 1C)")
	_sep.set_dump_available(false)
	_settle(1.0, 0.0, 10.0)   # cisnienie rosnie
	assert_gt(_sep.saturation_temp(), _params.tsat_ref,
		"Wyzsze cisnienie -> wyzsza temperatura nasycenia")


# --- Utrata odbioru -> wzrost cisnienia ---

func test_loss_of_dump_raises_pressure_monotonically() -> void:
	_sep.set_dump_available(false)
	var prev := _sep.get_pressure()
	for i in range(int(round(20.0 / DT))):
		_sep.step(1.0, 0.0, DT)
		var now := _sep.get_pressure()
		assert_gt(now, prev - 1e-9, "Bez odbioru cisnienie rosnie monotonicznie")
		prev = now
	assert_gt(_sep.get_pressure(), _params.pressure_setpoint + 0.5, "Cisnienie wyraznie wzroslo")


func test_overproduction_exceeds_trip_threshold() -> void:
	# Druga droga do tripu: produkcja > przepustowosc zrzutu (overpower->overpressure).
	var trip := SafetyParams.new().pressure_trip_mpa
	for i in range(int(round(60.0 / DT))):
		_sep.step(3.0, 0.0, DT)   # 3.0 > dump_max 2.0 -> cisnienie ucieka
	assert_gt(_sep.get_pressure(), trip,
		"Produkcja ponad przepustowosc zrzutu -> cisnienie powyzej progu tripu")


# --- Integracja w Simulation: oba scenariusze haka z przyczyna w logu ---

func test_loss_of_offtake_triggers_pressure_trip_with_cause() -> void:
	# Utrata odbioru pary (zrzut zamkniety) przy nominale -> RPS wymusza SCRAM.
	var sim := Simulation.new(0)
	sim.set_dump_available(false)
	sim.advance(45.0)
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.SCRAM,
		"Utrata odbioru -> wysokie cisnienie -> auto-SCRAM")
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("Wysokie cisnienie obiegu"):
			found = true
	assert_true(found, "Log zdarzen zawiera przyczyne: Wysokie cisnienie obiegu")


func test_sustained_loss_of_offtake_ruptures_with_cause() -> void:
	# Bez RPS (obejscie) utrata odbioru prowadzi do ROZERWANIA obiegu.
	var sim := Simulation.new(0)
	sim.set_protection_enabled(false)
	sim.set_dump_available(false)
	sim.advance(120.0)
	assert_true(sim.is_failed(), "Przedluzona utrata odbioru -> awaria")
	assert_eq(sim.get_failure(), FailureConditions.Type.CIRCUIT_RUPTURE,
		"Przyczyna: rozerwanie obiegu (eksplozja parowa)")
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("Rozerwanie obiegu"):
			found = true
	assert_true(found, "Log zdarzen zawiera przyczyne: Rozerwanie obiegu")


func test_nominal_no_pressure_trip() -> void:
	# Regresja: domyslny sim trzyma cisnienie na nastawie, bez nuisance-tripu.
	var sim := Simulation.new(0)
	sim.advance(30.0)
	assert_almost_eq(sim.state.pressure_mpa, 7.0, 0.05, "Nominalne cisnienie ~7 MPa")
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.OPERATE, "Brak tripu cisnieniowego")
	assert_false(sim.is_failed())


func test_pressure_serialization_roundtrip() -> void:
	var sim := Simulation.new(1)
	sim.advance(1.0)
	var snapshot := sim.state.to_dict()
	var restored := PlantState.new()
	restored.from_dict(snapshot)
	assert_almost_eq(restored.pressure_mpa, sim.state.pressure_mpa, 1e-9, "Cisnienie przetrwa serializacje")
	assert_eq(restored.to_dict(), snapshot, "Pelny roundtrip stanu z cisnieniem")
