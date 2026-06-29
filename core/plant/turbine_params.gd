class_name TurbineParams
extends Resource

## Konfigurowalne stale turbiny + generatora (ETAP 2C).
##
## RBMK-1000: 2 turbiny K-500-65/3000 po 500 MWe = 1000 MWe; 3000 obr/min <-> 50 Hz.
## UPROSZCZENIE: jeden EKWIWALENTNY stopien (WP+NP zlane, reheat jako sprawnosc).
## Pelny model multi-stopniowy + maszyna stanow turbiny (rozruch/obracarka) -> 2F.
## Jednostki: moc [MWe], obroty znormalizowane (1.0 = synchroniczne 3000/min = 50 Hz).

# Moc elektryczna przy pelnej admisji pary (2x500 MWe).
@export var nominal_electrical_mw: float = 1000.0
# Czestotliwosc synchroniczna [Hz].
@export var synchronous_frequency_hz: float = 50.0

# Stala czasowa zaworow admisji pary [s] (jak szybko turbina zmienia pobor pary).
@export var valve_time_s: float = 1.0
# Maks. admisja pary [-] (krotnosc nominalnego strumienia).
@export var max_admission: float = 1.2

# --- Bezwladnosc wirnika / overspeed ---
# Przyrost obrotow na jednostke mocy mechanicznej przy ODLACZENIU od sieci [1/s].
# Bez obciazenia elektrycznego para rozpedza wirnik. Dobrane: zrzut pelnego obciazenia
# -> overspeed w ~1 s, jesli zawory nie zamkna sie odpowiednio szybko.
# UPROSZCZENIE: wybieg (coast-down bez pary) i sprzezenie z pompami ГЦН -> 2F/globalne.
@export var overspeed_accel_gain: float = 0.2
# Prog zadzialania zabezpieczenia nadobrotowego (turbina odcina pare) [-].
@export var overspeed_trip_fraction: float = 1.10   # 110% = 55 Hz / 3300 obr/min

# --- Synchronizacja (MINIMALNA bramka - do obudowania pelna maszyna stanow w 2F) ---
# Okno obrotow, w ktorym wolno zalaczyc generator do sieci [-]. Poza nim = uszkodzenie.
@export var sync_tolerance: float = 0.02            # +/-2% obrotow synchronicznych


func validate() -> void:
	assert(nominal_electrical_mw > 0.0, "TurbineParams: nominal_electrical_mw musi byc > 0")
	assert(valve_time_s > 0.0, "TurbineParams: valve_time_s musi byc > 0")
	assert(max_admission > 0.0, "TurbineParams: max_admission musi byc > 0")
	assert(overspeed_accel_gain > 0.0, "TurbineParams: overspeed_accel_gain musi byc > 0")
	assert(overspeed_trip_fraction > 1.0, "TurbineParams: overspeed_trip_fraction musi byc > 1.0")
	assert(sync_tolerance > 0.0, "TurbineParams: sync_tolerance musi byc > 0")
