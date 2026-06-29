class_name Condenser
extends RefCounted

## Skraplacz + proznia - ETAP 2D.
##
## Odbiera pare z WYDECHU TURBINY i (warunkowo) ze zrzutu BRU-K, skrapla ja pod
## gleboka proznia. Proznia to WARUNEK pracy obiegu: jej utrata uruchamia STOPNIOWANE
## zabezpieczenia w WYMUSZONEJ kolejnosci (topologia przeplywu pary):
##   1) interlock BRU-K  - odciecie zrzutu DO skraplacza (przy bru_k_lockout_kpa),
##   2) trip turbiny     - utrata prozni jako warunek pracy maszyny (przy turbine_trip_kpa).
## Kolejnosc 1->2 jest WYMUSZONA: odwrocona czynilaby trip turbiny PRZYCZYNA awarii
## (wepchnalby pare w umierajacy skraplacz -> CONDENSER_RUPTURE). Patrz CondenserParams.
##
## MODEL: cisnienie -> PODLOGA prozni (zalezna od health, niezalezna od pary) + naddatek
## od doplywu pary. Dzieki temu po tripie turbiny (doplyw->0) proznia NIE wraca cudownie,
## jesli uklad prozni jest zepsuty (health niski -> podloga wysoka).
## INTEGRATOR: niejawny (backward) Euler, liniowy w P -> bezwarunkowo stabilny (jak 2B).
## Interlock czyta ZMIERZONE P z konca POPRZEDNIEGO kroku (kauzalnie, opoznienie 1 kroku).

const ATMOSPHERIC_KPA: float = 101.325

var params: CondenserParams

var _pressure_kpa: float = 0.0
var _vacuum_health: float = 1.0     # 1.0 = pelna sprawnosc ukladu prozni; 0 = calkowita utrata
var _steam_inflow: float = 0.0      # [-] aktualny doplyw pary (wydech turbiny + BRU-K)
var _bru_k_admitted: bool = false   # czy w tym kroku zrzut BRU-K trafil do skraplacza


func _init(condenser_params: CondenserParams) -> void:
	params = condenser_params
	params.validate()
	_pressure_kpa = params.nominal_pressure_kpa


## Podloga prozni: rosnie, gdy uklad odsysania pada (nieszczelnosc powietrzna).
## Przy health=1 = min_pressure; przy health=0 = min + vacuum_leak_gain.
func _pressure_floor() -> float:
	return params.min_pressure_kpa + params.vacuum_leak_gain * (1.0 - _vacuum_health)


## Krok prozni o dlugosci dt.
## turbine_exhaust - para z wydechu turbiny [-] (zawsze do skraplacza),
## bru_k_flow      - zrzut BRU-K skierowany do skraplacza [-] (0, gdy interlock odcial).
func step(turbine_exhaust: float, bru_k_flow: float, dt: float) -> void:
	_steam_inflow = maxf(0.0, turbine_exhaust) + maxf(0.0, bru_k_flow)
	_bru_k_admitted = bru_k_flow > 0.0
	var floor_p := _pressure_floor()
	var g := params.removal_gain
	var kc := params.pressure_capacitance_kc
	# Niejawny krok: odbior = g*(P - floor) liniowy w P -> mianownik > 1, bezwarunkowo stabilny.
	_pressure_kpa = (_pressure_kpa + dt * kc * (_steam_inflow + g * floor_p)) \
		/ (1.0 + dt * kc * g)
	_pressure_kpa = maxf(params.min_pressure_kpa, _pressure_kpa)


## Interlock BRU-K: skraplacz przyjmuje zrzut tylko z zachowana proznia.
func accepts_dump() -> bool:
	return _pressure_kpa < params.bru_k_lockout_kpa

## Warunek pracy turbiny: proznia ponizej progu tripu.
func vacuum_ok_for_turbine() -> bool:
	return _pressure_kpa < params.turbine_trip_kpa

## Degradacja/przywrocenie sprawnosci ukladu prozni (scenariusz/awaria). 1.0 = nominal.
func set_vacuum_health(health: float) -> void:
	_vacuum_health = clampf(health, 0.0, 1.0)

func get_pressure_kpa() -> float:
	return _pressure_kpa

## Frakcja prozni 0..1 wzgledem atmosfery (wskaznik UI; 1.0 = pelna proznia).
func vacuum_fraction() -> float:
	return clampf(1.0 - _pressure_kpa / ATMOSPHERIC_KPA, 0.0, 1.0)

func get_steam_inflow() -> float:
	return _steam_inflow

func get_vacuum_health() -> float:
	return _vacuum_health

## Czy do skraplacza wplywa zrzut BRU-K (warunek pulapki CONDENSER_RUPTURE).
func is_dumping_to_condenser() -> bool:
	return _bru_k_admitted
