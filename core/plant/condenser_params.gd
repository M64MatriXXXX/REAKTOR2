class_name CondenserParams
extends Resource

## Konfigurowalne stale skraplacza (ETAP 2D).
##
## Skraplacz pracuje pod GLEBOKA PROZNIA (~5 kPa abs), utrzymywana przez uklad
## odsysania powietrza + wode chlodzaca. Jednostka: kPa abs (NIE MPa - 0.005 MPa
## byloby nieczytelne; cisnienie skraplacza operatorzy czytaja w kPa / % prozni).
##
## MODEL PROZNI: cisnienie dazy do PODLOGI zaleznej od sprawnosci ukladu prozni
## (P_floor rosnie, gdy uklad pada - nieszczelnosc powietrzna), plus naddatek od
## doplywu pary. Degradacja prozni (health -> 0) podnosi P_floor NIEZALEZNIE od pary
## (zepsuty uklad traci proznie nawet bez pary). To oddziela UTRATE PROZNI od
## KATASTROFY z doplywem pary: CONDENSER_RUPTURE wymaga zrzutu BRU-K, nie samego P.

# --- Punkt pracy ---
@export var nominal_pressure_kpa: float = 5.0    # nominalne cisnienie skraplacza
@export var min_pressure_kpa: float = 4.0        # podloga prozni przy pelnej sprawnosci

# --- Dynamika prozni ---
# Pojemnosc: dP/dt = Kc*(doplyw_pary - odbior). MALE Kc = WOLNA, pojemnosciowa dynamika.
# WAZNE (margines progow): male Kc rozciaga przejscie miedzy progami (lockout->trip) na
# wiele krokow -> progi przekraczane ODDZIELNIE (test kolejnosci stabilny). Zbyt duze Kc
# moze wepchnac oba progi w jeden krok - DLUG do globalnego strojenia (margines vs tempo
# degradacji prozni; przy szybkim spadku health stroic Kc lub rozstaw progow).
@export var pressure_capacitance_kc: float = 0.1
# Wydajnosc kondensacji [1/kPa]: odbior = removal_gain*(P - P_floor). Dobrana, by w nominale
# (health=1, doplyw~1) P_eq = min + 1/removal_gain = 5 kPa.
@export var removal_gain: float = 1.0
# Wzrost podlogi prozni przy utracie sprawnosci [kPa]: P_floor = min + leak_gain*(1-health).
# Dobrane, by calkowita utrata (health=0) dala P_floor > rupture (proznia rozrywa sie sama,
# ale BEZ rozerwania skraplacza, jesli zrzut BRU-K juz odciety przez interlock).
@export var vacuum_leak_gain: float = 50.0

# --- Progi (WYMUSZONA RELACJA topologiczna: lockout < trip < rupture) ---
# Argument kaskadowy: interlock BRU-K MUSI zadzialac przed tripem turbiny, inaczej trip
# wepchnalby pare w umierajacy skraplacz -> CONDENSER_RUPTURE (zabezpieczenie = przyczyna awarii).
@export var bru_k_lockout_kpa: float = 20.0      # interlock: odciecie zrzutu BRU-K do skraplacza
@export var turbine_trip_kpa: float = 35.0       # warunek pracy turbiny: utrata prozni -> trip
@export var rupture_kpa: float = 50.0            # rozerwanie skraplacza (TYLKO przy doplywie BRU-K)


func validate() -> void:
	assert(min_pressure_kpa > 0.0, "CondenserParams: min_pressure_kpa musi byc > 0")
	assert(nominal_pressure_kpa >= min_pressure_kpa,
		"CondenserParams: nominal musi byc >= min (proznia nie glebsza niz podloga)")
	assert(pressure_capacitance_kc > 0.0, "CondenserParams: pressure_capacitance_kc musi byc > 0")
	assert(removal_gain > 0.0, "CondenserParams: removal_gain musi byc > 0")
	assert(vacuum_leak_gain > 0.0, "CondenserParams: vacuum_leak_gain musi byc > 0")
	# ZAMROZENIE RELACJI PROGOW (statyczna, pierwsza linia obrony przed regresja kolejnosci):
	assert(bru_k_lockout_kpa < turbine_trip_kpa,
		"CondenserParams: lockout BRU-K musi byc PONIZEJ progu tripu turbiny (kolejnosc kaskadowa)")
	assert(turbine_trip_kpa < rupture_kpa,
		"CondenserParams: trip turbiny musi byc PONIZEJ progu rozerwania skraplacza")
