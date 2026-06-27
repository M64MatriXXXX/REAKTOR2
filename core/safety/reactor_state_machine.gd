class_name ReactorStateMachine
extends RefCounted

## Maszyna stanow reaktora (ETAP 1E-1).
##
## Realny RBMK pracuje w jasno zdefiniowanych stanach z dozwolonymi przejsciami.
## Zasada nadrzedna: RPS (zabezpieczenia) sa niezalezne i NADRZEDNE nad sterowaniem.
## Wyjscie ze SCRAM mozliwe TYLKO recznie (reset do SHUTDOWN) - po "analizie poawaryjnej".
## Nie da sie wrocic do pracy bezposrednio ze SCRAM.
##
## UWAGA (1E-1): Simulation startuje w punkcie nominalnym (n=1), wiec domyslnym
## stanem jest OPERATE. Pelna sekwencja zimnego rozruchu (SHUTDOWN->STARTUP->OPERATE
## z rampa mocy) to przyszly etap; logika przejsc jest juz tu i przetestowana.

enum State { SHUTDOWN, STARTUP, OPERATE, SCRAM }

var _state: int = State.OPERATE


func get_state() -> int:
	return _state


func state_name() -> String:
	match _state:
		State.SHUTDOWN: return "SHUTDOWN"
		State.STARTUP: return "STARTUP"
		State.OPERATE: return "OPERATE"
		State.SCRAM: return "SCRAM"
	return "UNKNOWN"


func is_scrammed() -> bool:
	return _state == State.SCRAM


## Operatorskie zadanie przejscia (PCS). Zwraca true, jesli przejscie LEGALNE i wykonane.
## start_interlocks_ok - czy spelnione warunki startu (dotyczy SHUTDOWN->STARTUP).
## Ze stanu SCRAM zwykle sterowanie NIE dziala (tylko reset_to_shutdown).
func request(target: int, start_interlocks_ok: bool) -> bool:
	if _state == State.SCRAM:
		return false
	if target == State.STARTUP and _state == State.SHUTDOWN:
		if not start_interlocks_ok:
			return false
		_state = State.STARTUP
		return true
	if target == State.OPERATE and _state == State.STARTUP:
		_state = State.OPERATE
		return true
	if target == State.SHUTDOWN and (_state == State.STARTUP or _state == State.OPERATE):
		_state = State.SHUTDOWN
		return true
	return false


## Wymuszenie SCRAM (RPS lub manual AZ-5) - nadrzedne, z kazdego stanu poza SCRAM.
## Zwraca true, jesli to NOWE wejscie w SCRAM (do logowania zdarzenia raz).
func trigger_scram() -> bool:
	if _state == State.SCRAM:
		return false
	_state = State.SCRAM
	return true


## Reczny reset po SCRAM do SHUTDOWN (jedyne wyjscie ze SCRAM).
func reset_to_shutdown() -> bool:
	if _state != State.SCRAM:
		return false
	_state = State.SHUTDOWN
	return true
