class_name Feedwater
extends RefCounted

## Uklad wody zasilajacej - ETAP 2E.
##
## Deaerator (zbiornik buforowy) + pompy kondensatu (hotwell->deaerator) + pompy zasilajace
## (deaerator->separator) + REGULACJA poziomu separatora. Domyka petle masy wody.
##
## REGULACJA (1-elementowa): przeplyw zasilajacy sledzi strumien pary (feedforward) plus trim
## bledu poziomu separatora -> w stanie ustalonym poziom trzyma sie nastawy. Pompa kondensatu
## analogicznie trzyma poziom deaeratora. Bezwladnosc pomp = filtr 1. rzedu (jak ГЦН w 2A).
##
## Pompy moga stracic SSANIE (deaerator/hotwell ponizej minimum -> przeplyw odciety) i moga byc
## ZTRIPOWANE (awaria/utrata zasilania). Make-up (woda uzupelniajaca) DOMYSLNIE 0 - jawny przez
## set_makeup; inaczej maskowalby ubytek w tescie inwariancji masy.
##
## UPROSZCZENIE: jeden zbiornik deaeratora zamiast lancucha podgrzewaczy regeneracyjnych.

var params: FeedwaterParams

var _deaerator_level: float = 0.0
var _feed_flow: float = 0.0         # [-] przeplyw wody zasilajacej (deaerator -> separator)
var _cond_flow: float = 0.0         # [-] przeplyw kondensatu (hotwell -> deaerator)
var _feed_pump_running: bool = true
var _cond_pump_running: bool = true
var _makeup_flow: float = 0.0       # [-] dopływ uzupelniajacy (domyslnie 0 = petla zamknieta)
var _feed_override: float = -1.0    # [-] jawny tryb manualny przeplywu zasilajacego (< 0 = regulacja)


func _init(feedwater_params: FeedwaterParams) -> void:
	params = feedwater_params
	params.validate()
	_deaerator_level = params.deaerator_setpoint
	# Start w stanie ustalonym nominalnym (jak separator/pompy ГЦН): przeplywy = nominalna para,
	# by uniknac transientu rozruchowego osuszajacego poziomy.
	_feed_flow = 1.0
	_cond_flow = 1.0


## Krok ukladu o dlugosci dt.
## sep_level     - aktualny poziom separatora [-] (regulowana wielkosc),
## hotwell_level - aktualny poziom hotwellu [-] (ssanie pomp kondensatu),
## steam_out     - strumien pary z rdzenia [-] (feedforward = ile wody ubywa przez wrzenie).
func step(sep_level: float, hotwell_level: float, steam_out: float, dt: float) -> void:
	# --- Pompy zasilajace: utrzymanie poziomu separatora ---
	var fw_target := 0.0
	if _feed_override >= 0.0:
		fw_target = _feed_override                       # tryb manualny (scenariusz/test przelewu)
	elif _feed_pump_running:
		fw_target = steam_out + params.level_gain * (params.deaerator_setpoint - sep_level)
	fw_target = clampf(fw_target, 0.0, params.feed_pump_max if _feed_override < 0.0 else fw_target)
	# Utrata ssania: pusty deaerator nie wypompuje wody.
	if _deaerator_level <= params.deaerator_min_suction:
		fw_target = 0.0
	_feed_flow += (fw_target - _feed_flow) * (1.0 - exp(-dt / params.feed_pump_time_s))

	# --- Pompy kondensatu: utrzymanie poziomu deaeratora ---
	var cond_target := 0.0
	if _cond_pump_running:
		cond_target = _feed_flow + params.level_gain * (params.deaerator_setpoint - _deaerator_level)
	cond_target = clampf(cond_target, 0.0, params.cond_pump_max)
	# Utrata ssania: pusty hotwell nie wypompuje kondensatu.
	if hotwell_level <= params.hotwell_min_suction:
		cond_target = 0.0
	_cond_flow += (cond_target - _cond_flow) * (1.0 - exp(-dt / params.cond_pump_time_s))

	# --- Bilans deaeratora: doplyw kondensatu + make-up - odplyw zasilajacy ---
	_deaerator_level += (_cond_flow - _feed_flow + _makeup_flow) / params.deaerator_capacity * dt
	_deaerator_level = maxf(0.0, _deaerator_level)


## Awaria/utrata zasilania pomp zasilajacych (wybieg do 0 wg stalej czasowej).
func set_feed_pump_running(running: bool) -> void:
	_feed_pump_running = running

func set_cond_pump_running(running: bool) -> void:
	_cond_pump_running = running

## Dopływ wody uzupelniajacej (make-up). Domyslnie 0 (petla zamknieta).
func set_makeup(flow: float) -> void:
	_makeup_flow = maxf(0.0, flow)

## Jawny tryb manualny przeplywu zasilajacego (override regulacji). Ujemny = powrot do regulacji.
## Uzywany do scenariusza przelewu (overfill) -> porywanie wody do turbiny.
func set_feed_override(flow: float) -> void:
	_feed_override = flow

func get_feedwater_flow() -> float:
	return _feed_flow

func get_condensate_flow() -> float:
	return _cond_flow

func get_deaerator_level() -> float:
	return _deaerator_level

func get_makeup_flow() -> float:
	return _makeup_flow
