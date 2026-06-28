extends GutTest

## Testy glownych pomp cyrkulacyjnych ГЦН (ETAP 2A): bezwladnosc, awarie, sprzezenie
## z przeplywem i (dotad uspionym) tripem niskiego przeplywu.

const DT := 0.02

var _params: PumpParams
var _pumps: MainCirculationPumps


func before_each() -> void:
	_params = PumpParams.new()
	_pumps = MainCirculationPumps.new(_params)


func _settle(seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		_pumps.step(DT)


# --- Konfiguracja nominalna ---

func test_nominal_config_gives_full_flow() -> void:
	assert_eq(_pumps.running_count(), 6, "Nominalnie 6 czynnych pomp (3+1 rezerwa na petle)")
	assert_almost_eq(_pumps.get_flow_fraction(), 1.0, 1e-9, "6 czynnych pomp -> przeplyw 1.0")
	assert_eq(_params.total_pumps(), 8, "Lacznie 8 pomp ГЦН")


# --- Bezwladnosc ---

func test_pump_spin_up_is_not_instant() -> void:
	# Pompa rezerwowa (index 6) startuje od zera - narasta ku 1 z bezwladnoscia.
	_pumps.set_pump_running(6, true)
	_pumps.step(DT)
	var early := _pumps.get_pump_speed(6)
	assert_gt(early, 0.0, "Pompa zaczyna sie rozkrecac")
	assert_lt(early, 0.05, "...ale nie skokowo (bezwladnosc rozbiegu)")
	_settle(15.0)
	assert_gt(_pumps.get_pump_speed(6), 0.7, "Po czasie rozbiegu predkosc blisko znamionowej")


func test_coast_down_is_slow_on_power_loss() -> void:
	# Utrata zasilania czynnej pompy -> POWOLNY wybieg (flywheel daje czas).
	_pumps.set_pump_running(0, false)
	_settle(1.0)
	assert_gt(_pumps.get_pump_speed(0), 0.9, "Po 1 s wybieg ledwie zwolnil (duza bezwladnosc)")


func test_seizure_is_faster_than_coast_down() -> void:
	# Zaciecie zatrzymuje pompe znacznie szybciej niz wybieg przy utracie zasilania.
	var coast := MainCirculationPumps.new(PumpParams.new())
	coast.set_pump_running(0, false)        # utrata zasilania
	var seize := MainCirculationPumps.new(PumpParams.new())
	seize.fail_pump(0)                       # zaciecie
	for i in range(int(round(1.5 / DT))):
		coast.step(DT)
		seize.step(DT)
	assert_lt(seize.get_pump_speed(0), coast.get_pump_speed(0),
		"Zaciecie zatrzymuje pompe szybciej niz wybieg")
	assert_lt(seize.get_pump_speed(0), 0.5, "Zacieta pompa szybko traci predkosc")
	assert_gt(coast.get_pump_speed(0), 0.9, "Wybiegajaca pompa wciaz kreci")


# --- Przeplyw vs liczba pomp ---

func test_losing_pump_reduces_flow() -> void:
	_pumps.set_running_count(5)
	_settle(200.0)   # pelny wybieg jednej pompy do zera (~6.7 stalej czasowej)
	assert_almost_eq(_pumps.get_flow_fraction(), 5.0 / 6.0, 1e-3,
		"5 czynnych pomp -> przeplyw ~0.833")


func test_flow_monotonic_with_running_count() -> void:
	var f6 := _flow_after_count(6)
	var f5 := _flow_after_count(5)
	var f4 := _flow_after_count(4)
	assert_gt(f6, f5, "Wiecej czynnych pomp -> wiekszy przeplyw")
	assert_gt(f5, f4, "Monotonicznie")


func _flow_after_count(n: int) -> float:
	var p := MainCirculationPumps.new(PumpParams.new())
	p.set_running_count(n)
	for i in range(int(round(200.0 / DT))):
		p.step(DT)
	return p.get_flow_fraction()


# --- Integracja w Simulation: trip niskiego przeplywu + wybieg "kupuje czas" ---

func test_pump_loss_triggers_low_flow_trip_with_cause() -> void:
	# Prog tripu 0.7 + zaciecie 3 z 6 pomp -> przeplyw ~0.5 < 0.7 -> RPS wymusza SCRAM,
	# z niewielkimi pustkami (LOW_FLOW jest jednoznaczna przyczyna, bez konkurencji void/period).
	var sp := SafetyParams.new()
	sp.low_flow_trip_fraction = 0.7
	var sim := Simulation.new(0, null, null, null, sp)
	for idx in [3, 4, 5]:
		sim.fail_pump(idx)
	sim.advance(8.0)
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.SCRAM,
		"Utrata pomp -> niski przeplyw -> auto-SCRAM")
	# Przyczyna LOW_FLOW jawnie w logu zdarzen.
	var found := false
	for entry in sim.get_event_log():
		if entry.contains("Niski przeplyw chlodziwa"):
			found = true
	assert_true(found, "Log zdarzen zawiera przyczyne: Niski przeplyw chlodziwa")
	assert_lt(sim.state.coolant_flow_fraction, 0.7, "Przeplyw faktycznie ponizej progu tripu")


func test_coast_down_buys_time_before_trip() -> void:
	# Calkowita utrata zasilania pomp (wybieg). Przez kilka sekund przeplyw pozostaje
	# wysoko - realny margines czasu na zadzialanie SCRAM (element bezpieczenstwa).
	var sim := Simulation.new(0)
	sim.set_pump_running_count(0)   # utrata zasilania wszystkich pomp -> wybieg
	sim.advance(5.0)
	assert_gt(sim.state.coolant_flow_fraction, 0.7,
		"Po 5 s wybiegu przeplyw wciaz wysoki (czas na reakcje)")
	assert_false(sim.is_failed(), "Wybieg zapobiega natychmiastowej awarii")


# --- Determinizm i serializacja ---

func test_determinism_with_pump_ops() -> void:
	var a := Simulation.new(7)
	var b := Simulation.new(7)
	a.set_pump_running_count(4)
	b.set_pump_running_count(4)
	a.advance(3.0)
	b.advance(3.0)
	assert_eq(a.state.to_dict(), b.state.to_dict(), "To samo ziarno + komendy -> identyczny stan")


func test_pumps_running_serialized() -> void:
	var sim := Simulation.new(1)
	sim.set_pump_running_count(5)
	sim.advance(1.0)
	var snapshot := sim.state.to_dict()
	var restored := PlantState.new()
	restored.from_dict(snapshot)
	assert_eq(restored.pumps_running, sim.state.pumps_running, "pumps_running przetrwa serializacje")
	assert_eq(restored.to_dict(), snapshot, "Pelny roundtrip stanu z pompami")
