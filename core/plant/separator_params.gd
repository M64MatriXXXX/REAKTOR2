class_name SeparatorParams
extends Resource

## Konfigurowalne stale separatorow / bebnow parowych (ETAP 2B).
##
## RBMK-1000: 4 bebny (2 na petle), cisnienie ~7 MPa, jakosc pary na wylocie ~15%.
## Modelujemy PETLE CISNIENIA (produkcja pary - odbior) i jakosc pary.
## Poziom wody odlozony w pelni do 2E (regulacja feedwater). Jednostki SI / [MPa].

# --- Konfiguracja ---
@export var drum_count: int = 4                  # bebny separatorow (2 na petle)
@export var steam_quality: float = 0.15          # jakosc pary na wylocie (~15%)

# --- Petla cisnienia ---
# Cisnienie nominalne / nastawa regulatora zrzutu [MPa].
@export var pressure_setpoint: float = 7.0
@export var nominal_pressure: float = 7.0
# Pojemnosc cisnieniowa: dP/dt = K_P * (produkcja - odbior). MALE K_P = WOLNA, pojemnosciowa
# dynamika (duza objetosc bebnow). [MPa/s na jednostke niebilansu pary].
# Parametr do globalnego strojenia (po 2C: wybieg pomp sprzezony z turbogeneratorem).
@export var pressure_capacitance: float = 0.05

# --- Regulator zrzutu pary (BRU) - TRWALY komponent (w 2C turbina dochodzi jako odbior) ---
# Zrzut otwiera sie proporcjonalnie powyzej dump_closed_pressure: W = gain*(P - P_zamk).
# Dobrane tak, by w nominale (produkcja 1.0) zrzut=1.0 przy P=setpoint (rownowaga ~7 MPa).
@export var dump_closed_pressure: float = 6.9     # MPa (ponizej - zrzut zamkniety)
@export var dump_gain: float = 10.0               # 1/MPa  (10*(7-6.9)=1.0 w nominale)
# Maks. przepustowosc zrzutu [-] (krotnosc nominalnego strumienia pary).
# UPROSZCZENIE (do 2C): zrzut wymiarowany, by absorbowac nominal; w 2C turbina przejmuje
# role glownego odbiornika, zrzut wraca do realnej (mniejszej) pojemnosci bypassu.
@export var dump_max_capacity: float = 2.0

# --- Temperatura nasycenia T_sat(P) (sprzezenie cisnienie->void) ---
# Linearyzacja wokol punktu pracy: T_sat = tsat_ref + dtsat_dp*(P - tsat_ref_pressure).
# Steam tables ~10 K/MPa przy 7 MPa. UPROSZCZENIE: liniowe w zakresie operacyjnym.
@export var tsat_ref: float = 558.0               # K przy tsat_ref_pressure
@export var tsat_ref_pressure: float = 7.0        # MPa
@export var dtsat_dp: float = 10.0                # K/MPa
# Sprzezenie P->void (przez T_sat) DOMYSLNIE WYLACZONE - DLUG DO GLOBALNEGO STROJENIA (po 2C).
# Wlaczone nadmiernie tlumi szybkie ekskursje (wygasza emergentny Czarnobyl) - wymaga
# wspolnego strojenia K_P/dtsat z pelnym ukladem, by nie zaburzyc zwalidowanej fizyki void.
# Cisnienie i tak dziala JEDNOKIERUNKOWO: produkcja->cisnienie->hak (trip/rozerwanie).
@export var enable_void_coupling: bool = false

# --- Produkcja pary ---
# Strumien pary [-] = steam_production_per_power * ulamek mocy cieplnej.
# UPROSZCZENIE (dlug do uzgodnienia po 2C): produkcja pary ~ moc cieplna; lokalny "void"
# z 1C pozostaje OSOBNYM proxy reaktywnosci (nie tym samym strumieniem masowym).
@export var steam_production_per_power: float = 1.0

# --- Poziom wody w bebnach (ETAP 2E) ---
# NOWY stan masowy nalozony na 2B; NIE dotyka rownania cisnienia (poziom byl odlozony do 2E).
@export var water_level_setpoint: float = 1.0     # nominalny poziom (masa wody bebnow)
# Pojemnosc [s nominalnego przeplywu na jednostke poziomu]: DUZA = wolna dynamika (duzy zapas).
@export var water_capacity: float = 40.0
# Sprzezenie wsteczne do chlodzenia rdzenia (osuszenie -> spadek przeplywu): ponizej lowlow
# wspolczynnik chlodzenia maleje liniowo do min przy dryout. Powyzej lowlow = 1.0 (bez wplywu).
@export var cooling_lowlow_level: float = 0.3
@export var cooling_dryout_level: float = 0.0
# Minimalny wspolczynnik > 0: przy pelnym osuszeniu przeplyw nie spada do zera (ochrona modelu
# termicznego przed dzieleniem przez zero); resztkowy przeplyw i tak nie chlodzi rdzenia.
@export var cooling_min_factor: float = 0.05


func validate() -> void:
	assert(drum_count > 0, "SeparatorParams: drum_count musi byc > 0")
	assert(steam_quality > 0.0 and steam_quality < 1.0, "SeparatorParams: steam_quality w (0,1)")
	assert(pressure_setpoint > 0.0, "SeparatorParams: pressure_setpoint musi byc > 0")
	assert(pressure_capacitance > 0.0, "SeparatorParams: pressure_capacitance musi byc > 0")
	assert(dump_gain > 0.0, "SeparatorParams: dump_gain musi byc > 0")
	assert(dump_max_capacity > 0.0, "SeparatorParams: dump_max_capacity musi byc > 0")
	assert(dump_closed_pressure < pressure_setpoint,
		"SeparatorParams: dump_closed_pressure musi byc < setpoint (zrzut otwiera sie do nastawy)")
	assert(water_level_setpoint > 0.0, "SeparatorParams: water_level_setpoint musi byc > 0")
	assert(water_capacity > 0.0, "SeparatorParams: water_capacity musi byc > 0")
	assert(cooling_dryout_level < cooling_lowlow_level,
		"SeparatorParams: dryout musi byc PONIZEJ lowlow (degradacja chlodzenia miedzy nimi)")
