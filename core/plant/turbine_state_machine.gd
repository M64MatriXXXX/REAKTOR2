class_name TurbineStateMachine
extends RefCounted

## Maszyna stanow turbiny - ETAP 2F-1.
##
## OBUDOWUJE minimalna bramke synchronizacji z 2C (nie zastepuje): przejscie
## READY_TO_SYNC->SYNCHRONIZED nadal zalezy od warunku generator.can_synchronize()
## sprawdzanego na zewnatrz; tu zyje sam LEGALNY cykl stanow maszyny.
##
## Cykl: STOPPED (obracarka) -> ROLLING (rozbieg na parze) -> READY_TO_SYNC (obroty w oknie)
##       -> SYNCHRONIZED (pod siecia, obciazenie). TRIPPED (zawory zamkniete, wybieg) z kazdego.
##
## START NOMINALNY = READY_TO_SYNC (turbina kreci sie synchronicznie, gotowa do zalaczenia -
## spojnie z 2C, gdzie turbina startowala @ obrotach 1.0). Pelna sekwencja zimnego rozruchu
## (cold_start -> roll -> sync -> load) wchodzi w procedurach bloku 2F-2.

enum State { STOPPED, ROLLING, READY_TO_SYNC, SYNCHRONIZED, TRIPPED }

var _state: int = State.READY_TO_SYNC


func get_state() -> int:
	return _state


func state_name() -> String:
	match _state:
		State.STOPPED: return "STOPPED"
		State.ROLLING: return "ROLLING"
		State.READY_TO_SYNC: return "READY_TO_SYNC"
		State.SYNCHRONIZED: return "SYNCHRONIZED"
		State.TRIPPED: return "TRIPPED"
	return "UNKNOWN"


func is_tripped() -> bool:
	return _state == State.TRIPPED

func is_synchronized() -> bool:
	return _state == State.SYNCHRONIZED


## Zimny start: postawienie turbiny na obracarce (STOPPED). Niedozwolone spod sieci
## (najpierw odciazyc/rozlaczyc) ani ze SCRAM/TRIPPED (wymaga resetu w 2F-2).
func cold_start() -> bool:
	if _state == State.SYNCHRONIZED or _state == State.TRIPPED:
		return false
	_state = State.STOPPED
	return true


## Rozbieg na parze: STOPPED -> ROLLING.
func roll() -> bool:
	if _state != State.STOPPED:
		return false
	_state = State.ROLLING
	return true


## Osiagniecie obrotow synchronicznych (wywolanie z fizyki): ROLLING -> READY_TO_SYNC.
func reach_sync_speed() -> bool:
	if _state != State.ROLLING:
		return false
	_state = State.READY_TO_SYNC
	return true


## Synchronizacja: READY_TO_SYNC -> SYNCHRONIZED (bramka sprawdzana NA ZEWNATRZ).
func synchronize() -> bool:
	if _state != State.READY_TO_SYNC:
		return false
	_state = State.SYNCHRONIZED
	return true


## Trip z dowolnego stanu (poza TRIPPED). Zwraca true, gdy to NOWE wejscie w TRIPPED.
func trip() -> bool:
	if _state == State.TRIPPED:
		return false
	_state = State.TRIPPED
	return true
