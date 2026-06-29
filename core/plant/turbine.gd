class_name Turbine
extends RefCounted

## Turbina (ETAP 2C) - strona mechaniczna: admisja pary -> moc mechaniczna -> obroty.
##
## UPROSZCZENIE: jeden ekwiwalentny stopien (WP+NP zlane, reheat jako sprawnosc w MWe).
## Admisja pary = zadanie poboru (governor sledzi zapotrzebowanie sieci). Para to
## jednoczesnie OBCIAZENIE separatorow (external_offtake) i zrodlo momentu wirnika.
##
## Obroty (znormalizowane, 1.0 = synchroniczne 3000/min):
##   - POD SIECIA (connected): wirnik zablokowany na obrotach synchronicznych (siec sztywna);
##     moc mechaniczna = moc elektryczna oddawana do sieci.
##   - ODLACZONY (load rejection): brak obciazenia elektrycznego -> para ROZPEDZA wirnik
##     (overspeed). Zabezpieczenie nadobrotowe odcina pare (trip) -> para idzie do BRU.
##
## INTEGRATOR: zawory - filtr 1. rzedu (analityczny); obroty - jawny krok (ograniczony,
## bo po tripie admisja->0 i przyspieszanie ustaje). Sprzezenia szybkie turbina <-> wolne
## separatory rozprzega opoznienie 1 kroku w Simulation.

var params: TurbineParams

var _admission: float = 0.0    # [-] aktualna admisja pary (pobor)
var _speed: float = 1.0        # [-] obroty znormalizowane (1.0 = synchroniczne)
var _tripped: bool = false     # zabezpieczenie nadobrotowe zadzialalo (zawory zamkniete)


func _init(turbine_params: TurbineParams) -> void:
	params = turbine_params
	params.validate()


## Krok o dlugosci dt. connected - czy generator pod siecia; demand - zadanie poboru [-].
## Governor: POD SIECIA admisja sledzi zapotrzebowanie; ODLACZONA -> zamkniecie pary
## (utrzymanie obrotow synchronicznych, gotowosc do sync; przy load rejection zawory
## zamykaja sie z bezwladnoscia, wiec wirnik chwilowo przyspiesza -> overspeed).
func step(connected: bool, demand: float, dt: float) -> void:
	var target := 0.0
	if not _tripped and connected:
		target = clampf(demand, 0.0, params.max_admission)
	_admission += (target - _admission) * (1.0 - exp(-dt / params.valve_time_s))

	if connected:
		# Siec sztywna trzyma wirnik na obrotach synchronicznych.
		_speed = 1.0
	else:
		# Bez obciazenia elektrycznego moc mechaniczna rozpedza wirnik.
		_speed += params.overspeed_accel_gain * _admission * dt

	# Zabezpieczenie nadobrotowe: odciecie pary.
	if _speed > params.overspeed_trip_fraction:
		_tripped = true


## Strumien pary pobierany przez turbine (= obciazenie separatorow, external_offtake).
func get_steam_offtake() -> float:
	return _admission

## Moc mechaniczna [-] (= admisja; przekladana na MWe w generatorze, gdy pod siecia).
func mechanical_power() -> float:
	return _admission

func get_speed() -> float:
	return _speed

func is_tripped() -> bool:
	return _tripped

## Reczny trip turbiny (zamkniecie zaworow).
func trip() -> void:
	_tripped = true
