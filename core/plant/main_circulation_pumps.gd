class_name MainCirculationPumps
extends RefCounted

## Glowne pompy cyrkulacyjne (ГЦН) - ETAP 2A.
##
## Zastepuje skalarny, natychmiastowy przeplyw z ETAPU 1 realnym modelem 8 pomp
## z BEZWLADNOSCIA. Kazda pompa ma predkosc (0..1) zmieniajaca sie ku celowi z
## konfigurowalna stala czasowa. Calkowity przeplyw = liniowa suma czynnych pomp.
##
## SEDNO REALIZMU - trzy rozne stale czasowe spadku predkosci:
##   - utrata zasilania (off, sprawna): powolny WYBIEG (coast_down) - flywheel, czas na SCRAM,
##   - ZACIECIE (failed): nagle zatrzymanie (seizure_time),
##   - rozbieg (on): narastanie ku 1 (spin_up).
##
## INTEGRATOR: filtr 1. rzedu, rozwiazanie ANALITYCZNE (bezwarunkowo stabilne):
##   speed += (target - speed) * (1 - exp(-dt / tau))
##
## UPROSZCZENIE: przeplyw = suma liniowa predkosci pomp (bez krzywej dlawienia head-flow).

var params: PumpParams

var _running: PackedInt32Array     # 1 = zasilanie wlaczone, 0 = wylaczone (na pompe)
var _failed: PackedInt32Array      # 1 = zacieta (mechanicznie zatrzymana)
var _speed: PackedFloat64Array     # predkosc 0..1 (stan inercyjny)


func _init(pump_params: PumpParams) -> void:
	params = pump_params
	params.validate()
	var n := params.total_pumps()
	_running = PackedInt32Array()
	_failed = PackedInt32Array()
	_speed = PackedFloat64Array()
	_running.resize(n)
	_failed.resize(n)
	_speed.resize(n)
	# Konfiguracja NOMINALNA: pierwsze nominal_running() pomp czynne @ pelna predkosc,
	# reszta (rezerwa) wylaczona. Daje przeplyw = 1.0 (zgodny z ETAP 1).
	var running_count := params.nominal_running()
	for i in range(n):
		_failed[i] = 0
		if i < running_count:
			_running[i] = 1
			_speed[i] = 1.0
		else:
			_running[i] = 0
			_speed[i] = 0.0


## Komenda zasilania pompy i (true = wlacz). Zacieta pompa i tak sie nie rozkreci.
func set_pump_running(index: int, running: bool) -> void:
	if index < 0 or index >= _running.size():
		return
	_running[index] = 1 if running else 0


## Awaria mechaniczna (zaciecie) pompy i - nagle zatrzymanie, bez wybiegu.
func fail_pump(index: int) -> void:
	if index < 0 or index >= _failed.size():
		return
	_failed[index] = 1


## Ustawia pierwsze n pomp jako czynne, reszte wylaczona (wygodne dla scenariuszy).
func set_running_count(n: int) -> void:
	for i in range(_running.size()):
		_running[i] = 1 if i < n else 0


## Krok bezwladnosci o dlugosci dt. Kazda pompa dazy do celu z wlasciwa stala czasowa.
func step(dt: float) -> void:
	for i in range(_speed.size()):
		var powered := _running[i] == 1 and _failed[i] == 0
		var target := 1.0 if powered else 0.0
		var tau: float
		if _failed[i] == 1:
			tau = params.seizure_time_s          # zaciecie: nagle
		elif target > _speed[i]:
			tau = params.spin_up_time_s           # rozbieg
		else:
			tau = params.coast_down_time_s        # wybieg (utrata zasilania)
		_speed[i] += (target - _speed[i]) * (1.0 - exp(-dt / tau))


## Calkowity ulamek przeplywu chlodziwa (1.0 = nominal przy 6 czynnych pompach).
func get_flow_fraction() -> float:
	var total := 0.0
	for s in _speed:
		total += s
	return total * params.flow_per_pump()


## Liczba pomp z zasilaniem i bez zaciecia (sterowane jako czynne).
func running_count() -> int:
	var count := 0
	for i in range(_running.size()):
		if _running[i] == 1 and _failed[i] == 0:
			count += 1
	return count


func get_pump_speed(index: int) -> float:
	if index < 0 or index >= _speed.size():
		return 0.0
	return _speed[index]


func is_failed(index: int) -> bool:
	return index >= 0 and index < _failed.size() and _failed[index] == 1
