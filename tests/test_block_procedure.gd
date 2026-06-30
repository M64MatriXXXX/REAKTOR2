extends GutTest

## Testy procedur rozruchu/wylaczenia bloku + capstone integracyjny (ETAP 2F-2).
##
## Sedno: (1) ZAMROZENIE kolejnosci - kazdy interlock (start-bez-przeplywu, roll-bez-prozni,
## sync-przed-rozbiegiem, load-bez-sync) blokuje Z PRZYCZYNA W LOGU; (2) capstone: pelny cykl
## zycia bloku zimno -> moc -> zimno; (3) regresja niestabilnosci pre/post-1986 przez pelny blok.

const DT := 0.02


func _log_has(sim: Simulation, text: String) -> bool:
	for entry in sim.get_event_log():
		if entry.contains(text):
			return true
	return false


# --- (1) ZAMROZENIE kolejnosci: 4 interlocki, kazdy z przyczyna w logu ---

func test_cannot_start_reactor_without_flow() -> void:
	var sim := Simulation.new(0)
	sim.request_state(ReactorStateMachine.State.SHUTDOWN)   # OPERATE -> SHUTDOWN
	sim.set_coolant_flow(0.3)                               # przeplyw ponizej progu startu
	sim.step()                                              # zastosuj przeplyw
	assert_false(sim.request_state(ReactorStateMachine.State.STARTUP),
		"Start reaktora bez przeplywu zablokowany")
	assert_true(_log_has(sim, "za niski przeplyw"), "Przyczyna w logu: za niski przeplyw")


func test_cannot_roll_turbine_without_vacuum() -> void:
	var sim := Simulation.new(0)
	sim.cold_start_turbine()                # turbina STOPPED
	sim.set_vacuum_health(0.0)              # utrata prozni
	sim.advance(40.0)                       # cisnienie skraplacza rosnie ponad prog roll-u
	assert_gt(sim.state.condenser_pressure_kpa, 15.0, "Setup: proznia utracona")
	assert_false(sim.roll_turbine(), "Rozbieg turbiny bez prozni zablokowany")
	assert_true(_log_has(sim, "brak prozni"), "Przyczyna w logu: brak prozni skraplacza")


func test_cannot_sync_before_rolling() -> void:
	var sim := Simulation.new(0)
	sim.cold_start_turbine()
	sim.roll_turbine()                      # STOPPED -> ROLLING (proznia/cisnienie nominalne OK)
	assert_eq(sim.turbine.get_state(), TurbineStateMachine.State.ROLLING, "Turbina w rozbiegu")
	assert_false(sim.synchronize_generator(), "Sync w trakcie rozbiegu zablokowana")
	assert_false(sim.is_failed(), "Interlock odmawia bez awarii")
	assert_true(_log_has(sim, "turbina nie gotowa"), "Przyczyna w logu: turbina nie gotowa")


func test_cannot_load_before_sync() -> void:
	var sim := Simulation.new(0)                            # turbina READY_TO_SYNC, nie pod siecia
	assert_false(sim.request_load(1.0), "Obciazenie przed synchronizacja zablokowane")
	assert_true(_log_has(sim, "nie pod siecia"), "Przyczyna w logu: generator nie pod siecia")


# --- (2) CAPSTONE: pelny cykl zycia bloku ---

func test_full_block_startup_to_power_and_shutdown() -> void:
	var sim := Simulation.new(0)
	sim.cold_shutdown()                     # blok zimny (SHUTDOWN, prety in, turbina STOPPED, zrodlo)
	var proc := BlockProcedure.new()
	proc.start_up(1.0)

	# Rozruch: zimno -> wznoszenie mocy -> rozbieg -> sync -> obciazenie -> ONLINE.
	var online := false
	for i in range(int(round(500.0 / DT))):
		proc.step(sim)
		sim.step()
		if proc.is_online():
			online = true
			break
	assert_true(online, "Blok ozyl: zimny start -> ONLINE")
	# Po wejsciu ONLINE admisja pary narasta do zapotrzebowania - chwila na pelne obciazenie.
	for i in range(int(round(20.0 / DT))):
		proc.step(sim)
		sim.step()
	assert_gt(sim.state.electrical_power_mw, 900.0, "Pelna moc elektryczna pod siecia")
	assert_true(sim.state.grid_connected, "Generator pod siecia")
	assert_almost_eq(sim.state.reactor_power_fraction, 1.0, 0.05, "Reaktor na nominale")
	assert_eq(sim.turbine.get_state(), TurbineStateMachine.State.SYNCHRONIZED, "Turbina pod siecia")
	assert_false(sim.is_failed(), "Rozruch bez awarii")

	# Wylaczenie: odciazenie -> trip turbiny -> redukcja mocy -> SHUTDOWN.
	proc.shut_down()
	var cold := false
	for i in range(int(round(400.0 / DT))):
		proc.step(sim)
		sim.step()
		if proc.is_cold():
			cold = true
			break
	assert_true(cold, "Blok wrocil do stanu zimnego (DONE_COLD)")
	assert_eq(sim.get_reactor_state(), ReactorStateMachine.State.SHUTDOWN, "Reaktor SHUTDOWN")
	assert_true(sim.state.turbine_tripped, "Turbina odstawiona")
	assert_lt(sim.state.reactor_power_fraction, 0.1, "Moc wygaszona")
	assert_almost_eq(sim.state.total_water_mass, 3.0, 0.1, "Masa wody zachowana w pelnym cyklu (regresja 2E)")
	assert_false(sim.is_failed(), "Pelny cykl zycia bez awarii")


# --- (3) Regresja niestabilnosci przez pelny zintegrowany blok ---

func _chernobyl_sim(era: SafetyParams) -> Simulation:
	# Wrazliwa konfiguracja: prety wyciagniete (niski ORM), chlodziwo blisko wrzenia,
	# proxy ksenonu trzyma krytycznosc na niskiej mocy, RPS obejscia (jak 1986).
	var sim := Simulation.new(0, null, null, null, era)
	sim.set_protection_enabled(false)
	sim.set_rod_target(0.05)
	sim.set_coolant_flow(0.55)
	sim.set_external_reactivity(-0.0050)
	return sim


func test_instability_regression_pre_vs_post_1986() -> void:
	# Capstone-regresja: zlozenie niestabilnosci (dodatni scram + dodatni void + niski ORM)
	# przez PELNY zintegrowany blok 2F (sekundarna petla, FSM, zrodlo). PRE-1986 -> katastrofa
	# po AZ-5, POST-1986 -> bezpieczne wylaczenie tego samego stanu. Weryfikuje, nie dodaje fizyki.
	var pre := _chernobyl_sim(SafetyParams.pre_1986())
	pre.advance(28.0)
	assert_false(pre.is_failed(), "Przed AZ-5 stan stabilny (nie zaskryptowane)")
	pre.scram()
	pre.advance(15.0)
	assert_true(pre.is_failed(), "PRE-1986: niestabilnosc -> katastrofa po AZ-5 (przez pelny blok)")

	var post := _chernobyl_sim(SafetyParams.post_1986())
	post.advance(28.0)
	post.scram()
	post.advance(15.0)
	assert_false(post.is_failed(), "POST-1986: bezpieczne wylaczenie tego samego stanu")
	assert_lt(post.state.reactor_power_fraction, 0.1, "POST-1986: reaktor wygaszony")


# --- Determinizm ---

func test_determinism_with_sequencer() -> void:
	var a := Simulation.new(0)
	var b := Simulation.new(0)
	a.cold_shutdown()
	b.cold_shutdown()
	var pa := BlockProcedure.new()
	var pb := BlockProcedure.new()
	pa.start_up(1.0)
	pb.start_up(1.0)
	for i in range(int(round(100.0 / DT))):
		pa.step(a)
		a.step()
		pb.step(b)
		b.step()
	assert_eq(a.state.to_dict(), b.state.to_dict(), "Determinizm z sekwencerem rozruchu")
	assert_eq(pa.get_phase(), pb.get_phase(), "Sekwencer deterministyczny")
