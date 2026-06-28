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
# Okno POTWIERDZENIA sygnalu AZ [s]: warunek musi sie utrzymac tak dlugo, zanim
# wymusi SCRAM. Filtruje artefakty (prompt jump po skokowym impulsie daje krotki
# okres na ~0.08 s) od realnego rozbiegania (warunek utrzymany sekundami).
# Manualny AZ-5 jest NATYCHMIASTOWY (bez okna). Warunki przegranej tez (backstop).
# UPROSZCZENIE: jedno wspolne okno dla wszystkich auto-tripow (realny RPS ma rozne).
@export var trip_confirmation_time_s: float = 0.5
# Niski ORM [rownowazne prety] - prog tripu/interlocku (limit czarnobylski = 15).
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

# --- ORM (operating reactivity margin) i sprzezenia - ETAP 1E-3 ---
# ORM jako rownowazna liczba w pelni wsunietych pretow: ORM = orm_rods_scale * rod_insertion.
# UPROSZCZENIE: model punktowy nie ma rozkladu PRZESTRZENNEGO pretow (realny ORM od niego
# zalezy); to skalarny proxy "jak gleboko wsuniety jest bank pretow".
# Skala dobrana tak, by nominalna pozycja krytyczna (x~0.24) dawala ORM ~30 (norma RBMK).
@export var orm_rods_scale: float = 125.0            # rownowazne prety / jednostka x
# Prog wlaczenia amplifikacji void (ustawiony PONIZEJ nominalnego ORM ~30, z marginesem).
# ORM >= onset -> mnoznik void = 1.0 (fizyka nominalna nietknieta).
@export var orm_onset_rods: float = 26.0
# Sila sprzezenia ORM->efektywny wsp. pustkowy: mnoznik = 1 + gain * deficyt(ORM).
# Wzmacnia void, gdy ORM niski - podtrzymuje ekskursje po prompt-krytycznym spike'u.
@export var orm_void_gain: float = 2.5               # przy ORM=0 void coeff x3.5
# Interlock/trip niskiego ORM (post-1986 = wlaczony; pre-1986 = wylaczony -> pulapka).
@export var orm_protection_enabled: bool = true

# --- Efekt dodatniego scramu (grafitowe wyporniki) - ETAP 1E-3 ---
@export var enable_positive_scram_effect: bool = false
# Maksymalna amplituda dodatniego impulsu scramu [-] (przy pelnym deficycie ORM).
# Skalowana przez deficyt ORM: przy ORM>=onset = 0 (SCRAM czysto ujemny -> zawsze wylacza).
# Dobrana tak, by EMERGENTNIE przekroczyc prog natychmiastowej krytycznosci (beta~650 pcm)
# DOPIERO przy bardzo niskim ORM (~6, deficyt ~0.77 -> ~770 pcm > beta -> rozbieganie na
# pretach natychmiastowych, mechanizm Czarnobyla); przy ORM~15 (~420 pcm < beta) odzyskiwalne.
@export var positive_scram_worth: float = 0.010
# Czas trwania impulsu (przejscie wypornik->absorber w dolnym rdzeniu) [s].
@export var positive_scram_duration_s: float = 3.0


## Preset historyczny PRZED 1986: efekt dodatniego scramu obecny, interlock ORM wylaczony,
## wolny SCRAM ~18 s. Mozliwa "pulapka czarnobylska".
static func pre_1986() -> SafetyParams:
	var p := SafetyParams.new()
	p.enable_positive_scram_effect = true
	p.orm_protection_enabled = false
	p.scram_full_insertion_time_s = 18.0
	return p

## Preset historyczny PO 1986: brak efektu dodatniego scramu, interlock ORM aktywny,
## szybszy SCRAM ~12 s. Zabezpieczenia blokuja niebezpieczne konfiguracje.
static func post_1986() -> SafetyParams:
	var p := SafetyParams.new()
	p.enable_positive_scram_effect = false
	p.orm_protection_enabled = true
	p.scram_full_insertion_time_s = 12.0
	return p


func validate() -> void:
	assert(overpower_trip_fraction > 1.0, "SafetyParams: overpower_trip_fraction musi byc > 1.0")
	assert(period_trip_seconds > 0.0, "SafetyParams: period_trip_seconds musi byc > 0")
	assert(fuel_temp_trip_k < fuel_melt_temp_k,
		"SafetyParams: trip temp. paliwa musi byc PONIZEJ progu topnienia (margines)")
	assert(void_trip_fraction > 0.0 and void_trip_fraction <= 1.0,
		"SafetyParams: void_trip_fraction w (0,1]")
	assert(trip_confirmation_time_s >= 0.0, "SafetyParams: trip_confirmation_time_s musi byc >= 0")
	assert(clad_temp_fuel_weight >= 0.0 and clad_temp_fuel_weight <= 1.0,
		"SafetyParams: clad_temp_fuel_weight w [0,1]")
	assert(power_runaway_fraction > overpower_trip_fraction,
		"SafetyParams: prog rozbiegania musi byc powyzej progu przemocowania")
	assert(scram_full_insertion_time_s > 0.0, "SafetyParams: scram_full_insertion_time_s > 0")
	assert(orm_rods_scale > 0.0, "SafetyParams: orm_rods_scale musi byc > 0")
	assert(orm_onset_rods > 0.0, "SafetyParams: orm_onset_rods musi byc > 0")
	assert(orm_void_gain >= 0.0, "SafetyParams: orm_void_gain musi byc >= 0")
	assert(positive_scram_worth >= 0.0, "SafetyParams: positive_scram_worth musi byc >= 0")
	assert(positive_scram_duration_s > 0.0, "SafetyParams: positive_scram_duration_s > 0")
