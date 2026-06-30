class_name Turbine
extends RefCounted

## Turbina - strona mechaniczna (2C) + PELNA MASZYNA STANOW i wybieg (2F-1).
##
## UPROSZCZENIE: jeden ekwiwalentny stopien (WP+NP zlane, reheat jako sprawnosc w MWe).
## Admisja pary = obciazenie separatorow (external_offtake) i zrodlo momentu wirnika.
##
## Zachowanie zalezy od STANU maszyny (TurbineStateMachine), obudowujacej bramke sync z 2C:
##   STOPPED       - obracarka: brak admisji, wirnik stygnie do zera.
##   ROLLING       - rozbieg na parze: governor predkosci ku obrotom synchronicznym (1.0).
##   READY_TO_SYNC - obroty synchroniczne, brak obciazenia (admisja ~0); gotowa do zalaczenia.
##   SYNCHRONIZED  - pod siecia: admisja sledzi zapotrzebowanie (2C). Po rozlaczeniu (load
##                   rejection) zawory zamykaja sie z bezwladnoscia -> wirnik ROZPEDZA sie
##                   (overspeed) -> zabezpieczenie nadobrotowe -> TRIPPED.
##   TRIPPED       - zawory zamkniete; WYBIEG: obroty zanikaja ku zeru ze stala turbiny.
##
## INTEGRATOR: zawory i obroty - filtr 1. rzedu (analityczny, bezwarunkowo stabilny), jak ГЦН.
##
## START NOMINALNY = READY_TO_SYNC @ obroty 1.0 (spojnie z 2C). Zimny rozruch przez cold_start().

var params: TurbineParams
var state_machine: TurbineStateMachine

var _admission: float = 0.0    # [-] aktualna admisja pary (pobor)
var _speed: float = 1.0        # [-] obroty znormalizowane (1.0 = synchroniczne)


func _init(turbine_params: TurbineParams) -> void:
	params = turbine_params
	params.validate()
	state_machine = TurbineStateMachine.new()   # start READY_TO_SYNC @ obroty 1.0


# --- Komendy operatorskie / procedury ---

## Zimny start: turbina na obracarce (STOPPED), wirnik zatrzymany.
func cold_start() -> void:
	if state_machine.cold_start():
		_speed = 0.0
		_admission = 0.0

## Rozbieg na parze (STOPPED -> ROLLING).
func roll() -> void:
	state_machine.roll()

## Synchronizacja (READY_TO_SYNC -> SYNCHRONIZED). Bramke sprawdza wywolujacy (Simulation).
func synchronize() -> void:
	state_machine.synchronize()

## Trip turbiny (zamkniecie zaworow) - z dowolnego stanu.
func trip() -> void:
	state_machine.trip()


## Krok o dlugosci dt. grid_connected - czy wylacznik generatora zamkniety; demand - pobor [-].
func step(grid_connected: bool, demand: float, dt: float) -> void:
	var valve_alpha := 1.0 - exp(-dt / params.valve_time_s)
	var coast_alpha := 1.0 - exp(-dt / params.turbine_coast_down_time_s)

	match state_machine.get_state():
		TurbineStateMachine.State.STOPPED:
			_admission += (0.0 - _admission) * valve_alpha
			_speed += (0.0 - _speed) * coast_alpha

		TurbineStateMachine.State.ROLLING:
			# Governor predkosci: para rozkreca wirnik ku obrotom synchronicznym.
			_admission += (params.roll_admission - _admission) * valve_alpha
			_speed += (1.0 - _speed) * (1.0 - exp(-dt / params.roll_time_s))
			if absf(_speed - 1.0) <= params.sync_tolerance:
				state_machine.reach_sync_speed()

		TurbineStateMachine.State.READY_TO_SYNC:
			# Obroty synchroniczne, brak obciazenia - admisja schodzi do zera.
			_admission += (0.0 - _admission) * valve_alpha
			_speed = 1.0

		TurbineStateMachine.State.SYNCHRONIZED:
			if grid_connected:
				# Siec sztywna trzyma wirnik; admisja sledzi zapotrzebowanie.
				var target := clampf(demand, 0.0, params.max_admission)
				_admission += (target - _admission) * valve_alpha
				_speed = 1.0
			else:
				# Zrzut obciazenia: zawory zamykaja sie z bezwladnoscia -> nadobroty.
				_admission += (0.0 - _admission) * valve_alpha
				_speed += params.overspeed_accel_gain * _admission * dt
				if _speed > params.overspeed_trip_fraction:
					state_machine.trip()

		TurbineStateMachine.State.TRIPPED:
			# Zawory zamkniete, wirnik stygnie (wybieg) ku zeru.
			_admission += (0.0 - _admission) * valve_alpha
			_speed += (0.0 - _speed) * coast_alpha


## Strumien pary pobierany przez turbine (= obciazenie separatorow, external_offtake).
func get_steam_offtake() -> float:
	return _admission

## Moc mechaniczna [-] (= admisja; przekladana na MWe w generatorze, gdy pod siecia).
func mechanical_power() -> float:
	return _admission

func get_speed() -> float:
	return _speed

func is_tripped() -> bool:
	return state_machine.is_tripped()

func is_synchronized() -> bool:
	return state_machine.is_synchronized()

func get_state() -> int:
	return state_machine.get_state()
