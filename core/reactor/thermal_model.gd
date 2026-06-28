class_name ThermalModel
extends RefCounted

## Termohydraulika rdzenia - model 2-wezlowy (lumped) + frakcja pustek (ETAP 1C).
##
## Lancuch ciepla (jednostki SI):
##   moc neutronowa n  --(zrodlo objetosciowe)-->  PALIWO
##   PALIWO  --(przewodnosc UA)-->  CHLODZIWO
##   CHLODZIWO  --(przeplyw m_dot*c_p)-->  wynoszenie ciepla (T_inlet -> T_coolant)
##   T_coolant > T_sat  ==>  WRZENIE  ==>  frakcja pustek (void), algebraicznie
##
## Rownania stanu (dwa wezly):
##   C_f * dT_f/dt = P_nom*n - UA*(T_f - T_c)
##   C_c * dT_c/dt = UA*(T_f - T_c) - W*(T_c - T_in)
## gdzie W = W_nom * coolant_flow_fraction (strumien pojemnosci cieplnej chlodziwa).
##
## INTEGRATOR: niejawny (backward) Euler na ukladzie 2x2, rozwiazany ANALITYCZNIE.
## Uklad jest stabilny i liniowy; backward Euler jest bezwarunkowo stabilny, wiec
## pojedynczy krok dt=0.02 s wystarcza (stale czasowe ~1-5 s). Bez subkrokow.
##
## Wyprowadzenie (krok h), uklad rownan na (T_f^{k+1}, T_c^{k+1}):
##   a11 = C_f/h + UA            a12 = -UA
##   a21 = -UA                   a22 = C_c/h + UA + W
##   b1  = C_f/h * T_f^k + P_nom*n
##   b2  = C_c/h * T_c^k + W*T_in
##   det = a11*a22 - a12*a21
##   T_f^{k+1} = ( b1*a22 - a12*b2 ) / det
##   T_c^{k+1} = ( a11*b2 - a21*b1 ) / det
##
## Frakcja pustek (model PROGOWY, UPROSZCZENIE): liniowa od przegrzania ponad T_sat,
## obcieta do [0, void_fraction_max]. Liczona z NOWEJ T_c po aktualizacji temperatur.

var params: ThermalParams

var _fuel_temp: float = 0.0          # [K]
var _coolant_temp: float = 0.0       # [K]
var _void_fraction: float = 0.0      # [-]
var _last_heat_fraction: float = 0.0 # ostatni ulamek mocy CIEPLNEJ (prompt+decay)
# Aktualna temperatura nasycenia [K] - domyslnie stala z params (ETAP 1C); od 2B
# zmienna z cisnieniem separatorow (T_sat(P), wpinane z opoznieniem 1 kroku w Simulation).
var _saturation_temp: float = 0.0


func _init(thermal_params: ThermalParams) -> void:
	params = thermal_params
	params.validate()
	_saturation_temp = params.saturation_temp
	initialize_steady_state(1.0)


## Ustawia biezaca temperature nasycenia (z cisnienia separatorow, ETAP 2B).
## Domyslnie (bez wywolania) pozostaje stala params.saturation_temp - testy 1C bez zmian.
func set_saturation_temp(saturation_temp: float) -> void:
	_saturation_temp = saturation_temp


## Ustawia rownowage cieplna (dT/dt = 0) dla zadanej mocy przy PELNYM przeplywie.
## Z rownan rownowagi:
##   T_c = T_in + P_nom*n / W_nom
##   T_f = T_c  + P_nom*n / UA
## Przy n=1 daje to (dla domyslnych stalych) T_c=550 K, T_f=800 K, void=0 -
## punkt odniesienia spojny z ReactivityParams (warunek startu nominalnego).
func initialize_steady_state(power_fraction: float) -> void:
	_last_heat_fraction = power_fraction
	var q := params.nominal_thermal_power * power_fraction
	_coolant_temp = params.coolant_inlet_temp + q / params.coolant_flow_heat_rate_nominal
	_fuel_temp = _coolant_temp + q / params.fuel_to_coolant_conductance
	_void_fraction = _compute_void(_coolant_temp)


## Jeden krok termiki o dlugosci dt.
## heat_fraction         - ulamek mocy CIEPLNEJ (prompt*n + decay); n=1 -> ~1.0,
##                         po SCRAM rozszczepienia gasna, ale decay daje podloge.
## coolant_flow_fraction - wzgledny przeplyw chlodziwa 0..1 (1 = nominalny).
func step(heat_fraction: float, coolant_flow_fraction: float, dt: float) -> void:
	_last_heat_fraction = heat_fraction
	var ua := params.fuel_to_coolant_conductance
	var w := params.coolant_flow_heat_rate_nominal * maxf(0.0, coolant_flow_fraction)
	var cf_h := params.fuel_heat_capacity / dt
	var cc_h := params.coolant_heat_capacity / dt

	var a11 := cf_h + ua
	var a12 := -ua
	var a21 := -ua
	var a22 := cc_h + ua + w
	var b1 := cf_h * _fuel_temp + params.nominal_thermal_power * heat_fraction
	var b2 := cc_h * _coolant_temp + w * params.coolant_inlet_temp

	var det := a11 * a22 - a12 * a21   # zawsze > 0 dla dodatnich stalych
	_fuel_temp = (b1 * a22 - a12 * b2) / det
	_coolant_temp = (a11 * b2 - a21 * b1) / det
	_void_fraction = _compute_void(_coolant_temp)


## Frakcja pustek z temperatury chlodziwa (prog nasycenia + liniowy wzrost, obciety).
## Prog = biezaca T_sat (stala w 1C; zalezna od cisnienia od 2B).
func _compute_void(coolant_temp: float) -> float:
	var superheat := coolant_temp - _saturation_temp
	if superheat <= 0.0:
		return 0.0
	return minf(params.void_fraction_max, params.void_gain_per_kelvin * superheat)


func get_fuel_temp() -> float:
	return _fuel_temp

func get_coolant_temp() -> float:
	return _coolant_temp

func get_void_fraction() -> float:
	return _void_fraction

## Aktualna moc cieplna [W] (= P_nom * ulamek mocy cieplnej, prompt+decay).
func get_thermal_power_watts() -> float:
	return params.nominal_thermal_power * _last_heat_fraction
