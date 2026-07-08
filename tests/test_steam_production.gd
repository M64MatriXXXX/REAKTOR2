extends GutTest

## Testy STRUKTURALNEJ korekty produkcji pary (GT-1 globalnego strojenia).
##
## Produkcja pary = cieplo oddane do chlodziwa UA*(T_f-T_c)/P_nom (nie chwilowa moc). ZAMRAZA:
## (a) w stanie ustalonym = ulamek mocy (magnituda nietknieta), (b) w transiencie LAGuje ze
## stala termiczna paliwa tau_f=C_f/UA (opoznienie WYNIKA z 1C), (c) w granicy szybkiego paliwa
## (C_f->0) redukuje sie do "para natychmiast" - czyli S to poprawna korekta, nie arbitralny lag.

const DT := 0.02


func test_steady_state_steam_equals_power() -> void:
	var tm := ThermalModel.new(ThermalParams.new())
	tm.initialize_steady_state(1.0)
	assert_almost_eq(tm.get_steam_production(), 1.0, 1e-6, "Nominal: produkcja pary = moc (magnituda)")
	tm.initialize_steady_state(0.5)
	assert_almost_eq(tm.get_steam_production(), 0.5, 1e-6, "Polowa mocy: produkcja pary = 0.5")


func test_boiling_response_time_is_fuel_thermal_constant() -> void:
	# Stala opoznienia WYNIKA z 1C: tau_f = C_f / UA (nie dobrana arbitralnie pod K_P).
	var tp := ThermalParams.new()
	var tm := ThermalModel.new(tp)
	assert_almost_eq(tm.boiling_response_time(),
		tp.fuel_heat_capacity / tp.fuel_to_coolant_conductance, 1e-9,
		"Stala odpowiedzi pary = termiczna stala paliwa C_f/UA (z modelu 1C)")


func test_steam_lags_power_step() -> void:
	# Skok mocy: produkcja pary NIE skacze natychmiast - narasta z opoznieniem ~tau_f.
	var tm := ThermalModel.new(ThermalParams.new())
	tm.initialize_steady_state(1.0)
	tm.step(2.0, 1.0, DT)
	assert_lt(tm.get_steam_production(), 1.2, "Po skoku mocy para NIE skacze od razu (lag)")
	var tau := tm.boiling_response_time()
	for i in range(int(round(tau / DT))):
		tm.step(2.0, 1.0, DT)
	var at_tau := tm.get_steam_production()
	assert_gt(at_tau, 1.4, "Po tau_f para w polowie drogi do nowej wartosci (dolna granica)")
	assert_lt(at_tau, 1.9, "...ale jeszcze nie ustalona (gorna granica) - to jest LAG")
	for i in range(int(round(40.0 / DT))):
		tm.step(2.0, 1.0, DT)
	assert_almost_eq(tm.get_steam_production(), 2.0, 0.02, "Po dostatecznym czasie para dochodzi do mocy")


func test_fast_fuel_limit_is_instant_steam() -> void:
	# Granica szybkiego wrzenia (C_f -> 0, tau_f -> 0): para NATYCHMIAST za moca (=stary model).
	var tp := ThermalParams.new()
	tp.fuel_heat_capacity = 6.4e3          # ~1000x mniejsza -> tau_f ~ 0.5 ms
	var tm := ThermalModel.new(tp)
	tm.initialize_steady_state(1.0)
	for i in range(3):
		tm.step(2.0, 1.0, DT)
	assert_almost_eq(tm.get_steam_production(), 2.0, 0.05,
		"Szybkie paliwo -> produkcja pary praktycznie natychmiast (redukcja do 'para natychmiast')")


func test_steam_production_non_negative() -> void:
	var tm := ThermalModel.new(ThermalParams.new())
	tm.initialize_steady_state(1.0)
	for i in range(int(round(30.0 / DT))):
		tm.step(0.0, 1.0, DT)              # gwaltowne wygaszenie mocy
	assert_gte(tm.get_steam_production(), 0.0, "Produkcja pary nieujemna")
