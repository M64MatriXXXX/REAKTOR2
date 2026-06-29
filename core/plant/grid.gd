class_name Grid
extends RefCounted

## Siec elektroenergetyczna (ETAP 2C) - prosty model zapotrzebowania i czestotliwosci.
##
## UPROSZCZENIE: zapotrzebowanie jako zadawalny profil (stale/skokowe) + zrzut obciazenia
## jako zdarzenie (rozlaczenie). Pelna dynamika czestotliwosci systemu energetycznego
## uproszczona: czestotliwosc = znormalizowane obroty turbiny * 50 Hz (gdy zsynchronizowana).
##
## Stan polaczenia (wylacznik generatora) trzymany TU - "pod siecia" / "odlaczony".

var _demand_fraction: float = 0.0   # [-] zapotrzebowanie (ulamek mocy nominalnej)
var _connected: bool = false        # czy generator zalaczony do sieci (wylacznik zamkniety)
var _nominal_frequency_hz: float = 50.0


func _init(nominal_frequency_hz: float = 50.0) -> void:
	_nominal_frequency_hz = nominal_frequency_hz


## Zadanie zapotrzebowania sieci (0..1 mocy nominalnej).
func set_demand(demand_fraction: float) -> void:
	_demand_fraction = maxf(0.0, demand_fraction)

func get_demand() -> float:
	return _demand_fraction

## Zalaczenie do sieci (zamkniecie wylacznika generatora) - po sprawdzeniu synchronizacji.
## Nazwa unika kolizji z Object.connect (API sygnalow Godota).
func close_breaker() -> void:
	_connected = true

## Zrzut obciazenia / rozlaczenie od sieci (otwarcie wylacznika, load rejection).
func open_breaker() -> void:
	_connected = false

func is_breaker_closed() -> bool:
	return _connected


## Czestotliwosc generatora [Hz] = obroty * nominalna (pod siecia ~ 50 Hz, locked).
func frequency_hz(turbine_speed: float) -> float:
	return _nominal_frequency_hz * turbine_speed
