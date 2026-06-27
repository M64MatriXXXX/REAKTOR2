class_name SafetyParams
extends Resource

## Konfigurowalne progi zabezpieczen i warunkow awarii (ETAP 1E-1).
##
## Wartosci startowe oparte na realnym RBMK-1000 (dokument referencyjny 1E).
## Wszystko konfigurowalne; globalne strojenie dopiero po komplecie 1E+1D.
## Jednostki SI / bezwymiarowe (moc jako ulamek nominalu, n=1 -> 3200 MWth).

# --- Sygnaly AZ (auto-SCRAM) ---
# Przekroczenie mocy [-] (ulamek nominalu).
@export var overpower_trip_fraction: float = 1.10        # > 110% nominalu
# Period trip: okres reaktora ponizej progu (tylko DODATNI, krotki = rozbieganie) [s].
@export var period_trip_seconds: float = 20.0
# Wysoka temperatura paliwa [K] (margines do topnienia 3120 K).
@export var fuel_temp_trip_k: float = 2800.0
# Nadmierne wrzenie [-] (frakcja pustek).
@export var void_trip_fraction: float = 0.70
# Niski przeplyw chlodziwa [-] (ulamek nominalu).
@export var low_flow_trip_fraction: float = 0.50
# Niski ORM [rownowazne prety] - HAK do 1E-3 (ORM jeszcze nieliczony w 1E-1).
@export var orm_trip_equivalent_rods: float = 15.0
# Wysokie cisnienie [MPa] - HAK do 1C' (obieg jeszcze niemodelowany).
@export var pressure_trip_mpa: float = 8.5

# --- Warunki przegranej (failure states) ---
# Meltdown paliwa: topnienie UO2 [K]. Powyzej - rdzen stopiony (stan niefizyczny do utrzymania).
@export var fuel_melt_temp_k: float = 3120.0
# Uszkodzenie koszulki (cyrkon) [K] - wczesniejszy etap niz topnienie paliwa.
@export var clad_failure_temp_k: float = 2120.0
# Waga paliwa w proxy temperatury koszulki: T_clad = w*T_fuel + (1-w)*T_coolant.
# UPROSZCZENIE: model 2-wezlowy nie ma osobnego wezla koszulki; wazymy w strone paliwa.
@export var clad_temp_fuel_weight: float = 0.70
# Katastrofalne rozbieganie mocy [-] = eksplozja energetyczna (scenariusz czarnobylski).
# Backstop powyzej szczytu ekskursji niskoprzeplywowej; konfigurowalny do strojenia.
@export var power_runaway_fraction: float = 100.0
# Rozerwanie obiegu (eksplozja parowa) [MPa] - HAK do 1C'.
@export var pressure_rupture_mpa: float = 10.5

# --- Prety AZ (realny, konfigurowalny czas) ---
# Czas pelnego wsuniecia pretow AZ z pozycji wyciagnietej [s].
# Realny RBMK pre-1986: ~18-20 s (wolny SCRAM to czesc dramatu RBMK).
# Post-1986 skrocono do ~12 s; BAZ szybsze - parametryzacja w 1E-3.
@export var scram_full_insertion_time_s: float = 18.0

# --- Efekt dodatniego scramu (grafitowe wyporniki) - HAK do 1E-3 ---
@export var enable_positive_scram_effect: bool = false


func validate() -> void:
	assert(overpower_trip_fraction > 1.0, "SafetyParams: overpower_trip_fraction musi byc > 1.0")
	assert(period_trip_seconds > 0.0, "SafetyParams: period_trip_seconds musi byc > 0")
	assert(fuel_temp_trip_k < fuel_melt_temp_k,
		"SafetyParams: trip temp. paliwa musi byc PONIZEJ progu topnienia (margines)")
	assert(void_trip_fraction > 0.0 and void_trip_fraction <= 1.0,
		"SafetyParams: void_trip_fraction w (0,1]")
	assert(clad_temp_fuel_weight >= 0.0 and clad_temp_fuel_weight <= 1.0,
		"SafetyParams: clad_temp_fuel_weight w [0,1]")
	assert(power_runaway_fraction > overpower_trip_fraction,
		"SafetyParams: prog rozbiegania musi byc powyzej progu przemocowania")
	assert(scram_full_insertion_time_s > 0.0, "SafetyParams: scram_full_insertion_time_s > 0")
