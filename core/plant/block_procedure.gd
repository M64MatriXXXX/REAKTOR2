class_name BlockProcedure
extends RefCounted

## Sekwencer rozruchu/wylaczenia bloku - ETAP 2F-2.
##
## Autopilot "operator wg procedury": co krok inspekcjonuje stan bloku i wydaje NASTEPNA
## legalna komende, respektujac interlocki (Simulation odmawia + loguje przyczyne, sekwencer
## czeka). Jedno zrodlo prawdy procedury - uzywaja go i capstone-test, i runner CSV.
##
## ROZRUCH: COLD -> start reaktora (wymaga przeplywu) -> wznoszenie mocy (proporcjonalne
## sterowanie pretami) -> rozbieg turbiny (wymaga prozni+cisnienia) -> sync (wymaga gotowej
## turbiny) -> obciazenie (wymaga sieci) -> ONLINE.
## WYLACZENIE: odciazenie -> trip turbiny -> redukcja mocy -> prety wsuniete -> SHUTDOWN.
##
## Sterowanie mocy: prety = krytyczna + gain*(moc - nastawa), klamrowane (max wyciag ogranicza
## nadkrytycznosc -> okres > prog tripu, lagodne wznoszenie). Ujemne sprzezenie -> moc do nastawy.

enum Phase {
	COLD, STARTING_REACTOR, RAISING_POWER, ROLLING_TURBINE, SYNCING, LOADING, ONLINE,
	SHUTTING_DOWN, COOLING_DOWN, DONE_COLD,
}
enum Goal { IDLE, ONLINE, COLD }

var _phase: int = Phase.COLD
var _goal: int = Goal.IDLE
var _power_setpoint: float = 0.0

# Sterowanie mocy pretami.
var rod_gain: float = 0.05           # wzmocnienie proporcjonalne przy UTRZYMANIU mocy (blad mocy)
var max_withdraw: float = 0.03       # maks. wyciag ponizej krytycznej (klamra przy utrzymaniu)
# Wznoszenie na KONTROLOWANYM OKRESIE (jak realny rozruch): wstawiamy prety TYLKO gdy okres
# grozi tripem (< period_min_s, powyzej progu 20 s z marginesem); inaczej WYCIAGAMY -> moc
# rosnie monotonicznie, a okres nie spada do tripu. Bias na wyciaganie = pewne wznoszenie.
var period_min_s: float = 25.0
var rod_lead: float = 0.05           # wyprzedzenie celu pretow (aktuator rusza z predkoscia normalna)
var roll_power_fraction: float = 0.9 # ulamek nastawy, przy ktorym wolno rozbiegac turbine
var shutdown_power_threshold: float = 0.05  # ponizej tej mocy wsuwamy prety na full -> SHUTDOWN


## Rozpoczyna rozruch do zadanej mocy docelowej (ulamek nominalu).
func start_up(target_power: float = 1.0) -> void:
	_goal = Goal.ONLINE
	_power_setpoint = target_power
	if _phase == Phase.DONE_COLD:
		_phase = Phase.COLD


## Rozpoczyna wylaczenie bloku do stanu zimnego.
func shut_down() -> void:
	_goal = Goal.COLD
	_power_setpoint = 0.0
	_phase = Phase.SHUTTING_DOWN


func get_phase() -> int:
	return _phase

func phase_name() -> String:
	match _phase:
		Phase.COLD: return "COLD"
		Phase.STARTING_REACTOR: return "STARTING_REACTOR"
		Phase.RAISING_POWER: return "RAISING_POWER"
		Phase.ROLLING_TURBINE: return "ROLLING_TURBINE"
		Phase.SYNCING: return "SYNCING"
		Phase.LOADING: return "LOADING"
		Phase.ONLINE: return "ONLINE"
		Phase.SHUTTING_DOWN: return "SHUTTING_DOWN"
		Phase.COOLING_DOWN: return "COOLING_DOWN"
		Phase.DONE_COLD: return "DONE_COLD"
	return "UNKNOWN"

func is_online() -> bool:
	return _phase == Phase.ONLINE

func is_cold() -> bool:
	return _phase == Phase.DONE_COLD


## Krok sekwencera (wolac PRZED sim.step()). Wydaje nastepna legalna komende.
func step(sim: Simulation) -> void:
	match _goal:
		Goal.ONLINE:
			_step_startup(sim)
		Goal.COLD:
			_step_shutdown(sim)


## Sterowanie mocy pretami ku nastawie.
## - przy mocy < nastawy: WZNOSZENIE na kontrolowanym okresie (okres < safe_period -> wsun prety;
##   inaczej -> wyciagaj). Trzyma okres ~ safe_period (>> prog tripu) -> lagodnie, bez period-SCRAM.
## - przy mocy ~ nastawie: UTRZYMANIE proporcjonalne (ujemne sprzezenie -> moc stabilna na nastawie).
func _control_power(sim: Simulation, setpoint: float) -> void:
	var crit := sim.get_critical_insertion()
	var power := sim.state.reactor_power_fraction
	if power >= 0.99 * setpoint:
		var target := clampf(crit + rod_gain * (power - setpoint), crit - max_withdraw, 1.0)
		sim.set_rod_target(target)
		return
	# Wznoszenie na kontrolowanym okresie. Wstaw prety TYLKO gdy okres grozi tripem
	# (0 < period < period_min); w kazdym innym przypadku (podkrytycznie / dlugi okres) WYCIAGAJ.
	var period := sim.state.reactor_period_seconds
	var pos := sim.control_rods.get_insertion()
	if period > 0.0 and period < period_min_s:
		sim.set_rod_target(clampf(pos + rod_lead, 0.0, 1.0))   # grozi tripem -> wsun troche
	else:
		sim.set_rod_target(clampf(pos - rod_lead, 0.0, 1.0))   # wyciagaj -> moc rosnie


func _secondary_ready(sim: Simulation) -> bool:
	return sim.state.pressure_mpa >= sim.turbine_params.roll_min_pressure_mpa \
		and sim.state.condenser_pressure_kpa <= sim.turbine_params.roll_min_vacuum_kpa


func _step_startup(sim: Simulation) -> void:
	match _phase:
		Phase.COLD:
			if sim.get_reactor_state() == ReactorStateMachine.State.OPERATE:
				_phase = Phase.RAISING_POWER       # cieply start (juz w OPERATE)
			elif sim.request_state(ReactorStateMachine.State.STARTUP):
				_phase = Phase.STARTING_REACTOR
		Phase.STARTING_REACTOR:
			_control_power(sim, _power_setpoint)
			if sim.state.reactor_power_fraction > 0.5 * _power_setpoint:
				sim.request_state(ReactorStateMachine.State.OPERATE)
				_phase = Phase.RAISING_POWER
		Phase.RAISING_POWER:
			_control_power(sim, _power_setpoint)
			if sim.state.reactor_power_fraction >= roll_power_fraction * _power_setpoint \
					and _secondary_ready(sim):
				if sim.roll_turbine():
					_phase = Phase.ROLLING_TURBINE
		Phase.ROLLING_TURBINE:
			_control_power(sim, _power_setpoint)
			if sim.turbine.get_state() == TurbineStateMachine.State.READY_TO_SYNC:
				_phase = Phase.SYNCING
		Phase.SYNCING:
			_control_power(sim, _power_setpoint)
			if sim.synchronize_generator():
				_phase = Phase.LOADING
		Phase.LOADING:
			_control_power(sim, _power_setpoint)
			if sim.request_load(_power_setpoint):
				_phase = Phase.ONLINE
		Phase.ONLINE:
			_control_power(sim, _power_setpoint)   # utrzymanie mocy na nastawie


func _step_shutdown(sim: Simulation) -> void:
	match _phase:
		Phase.SHUTTING_DOWN:
			sim.request_load(0.0)                  # odciazenie
			if sim.turbine.is_synchronized():
				sim.reject_load()                  # rozlaczenie od sieci
			sim.trip_turbine()                     # zamkniecie pary turbiny
			_phase = Phase.COOLING_DOWN
		Phase.COOLING_DOWN:
			# Wyłaczenie: zdecydowane wsuwanie pretow (moc maleje na ujemnym okresie - bez tripu).
			sim.set_rod_target(1.0)
			if sim.state.reactor_power_fraction < shutdown_power_threshold:
				if sim.get_reactor_state() == ReactorStateMachine.State.OPERATE:
					sim.request_state(ReactorStateMachine.State.SHUTDOWN)
				_phase = Phase.DONE_COLD
		Phase.DONE_COLD:
			sim.set_rod_target(1.0)
