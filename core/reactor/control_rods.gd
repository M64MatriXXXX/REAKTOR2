class_name ControlRods
extends RefCounted

## Kinematyka pretow regulacyjnych (gdzie sa prety) - oddzielona od fizyki
## reaktywnosci (jaki rho z tego wynika; to liczy ReactivityModel).
##
## Pozycja = zaglebienie 0..1 (0 = wyciagniete, 1 = wsuniete). Prety ruszaja sie
## ku celowi ze skonczona predkoscia (normalna lub SCRAM).

var _position: float = 0.0
var _target: float = 0.0
var _speed: float = 0.0            # aktualna predkosc [1/s]
var _speed_normal: float = 0.01
var _speed_scram: float = 0.30
var _scram_active: bool = false
var _scram_elapsed: float = 0.0   # [s] czas od wywolania SCRAM (profil efektu dodatniego, 1E-3)


func _init(speed_normal: float, speed_scram: float, start_insertion: float = 0.0) -> void:
	_speed_normal = speed_normal
	_speed_scram = speed_scram
	_speed = speed_normal
	_position = clampf(start_insertion, 0.0, 1.0)
	_target = _position


## Ustawia cel zaglebienia (0..1) i predkosc normalna. Ignorowane po SCRAM-ie
## (SCRAM ma pierwszenstwo - pretow nie da sie "odwolac" zwyklym sterowaniem).
func set_target(insertion: float) -> void:
	if _scram_active:
		return
	_target = clampf(insertion, 0.0, 1.0)
	_speed = _speed_normal


## Awaryjne wsuniecie wszystkich pretow (AZ-5): cel = 1.0, predkosc SCRAM.
func scram() -> void:
	_scram_active = true
	_target = 1.0
	_speed = _speed_scram


## Ruch pretow ku celowi o krok, ograniczony predkoscia. Klamruje do 0..1.
func step(dt: float) -> void:
	if _scram_active:
		_scram_elapsed += dt
	var max_step := _speed * dt
	var diff := _target - _position
	if absf(diff) <= max_step:
		_position = _target
	else:
		_position += signf(diff) * max_step
	_position = clampf(_position, 0.0, 1.0)


## Ustawia pozycje pretow BEZPOSREDNIO (bez rampy) - do inicjalizacji stanu (np. zimny start
## ustawia prety wsuniete). Ignorowane po SCRAM. Cel = pozycja (brak ruchu po ustawieniu).
func set_position(insertion: float) -> void:
	if _scram_active:
		return
	_position = clampf(insertion, 0.0, 1.0)
	_target = _position


func get_insertion() -> float:
	return _position


func get_target() -> float:
	return _target


func is_at_target() -> bool:
	return is_equal_approx(_position, _target)


func is_scram_active() -> bool:
	return _scram_active


## Czas [s], jaki uplynal od wywolania SCRAM (0 zanim SCRAM aktywny).
## Sluzy do profilu czasowego efektu dodatniego scramu (1E-3b).
func get_scram_elapsed() -> float:
	return _scram_elapsed
