extends SceneTree

## Headless runner symulacji (ETAP 0).
##
## Uruchamia rdzen BEZ UI, posuwa symulacje o zadana liczbe sekund
## i wypisuje przebieg parametrow do konsoli oraz do pliku CSV.
## Sluzy do walidacji fizyki (ETAP 1) i szybkiego "rozruszania" rdzenia.
##
## Uruchomienie (po zainstalowaniu Godota):
##   godot --headless --script res://tools/headless_runner.gd -- --seconds 10 --seed 1 --out out/run.csv
##
## UWAGA: argumenty po "--" trafiaja do OS.get_cmdline_user_args() (Godot 4.x).

func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var seconds: float = float(args.get("seconds", "5"))
	var seed_value: int = int(args.get("seed", "0"))
	var out_path: String = args.get("out", "out/run.csv")
	# Sterowanie pretami: docelowe zaglebienie 0..1 (domyslnie -1 = bez zmiany / pozycja krytyczna).
	var rod_target: float = float(args.get("rod-target", "-1"))
	# Bias reaktywnosci zewnetrznej [Δρ] na caly przebieg (np. impuls testowy).
	var external: float = float(args.get("external", "0"))
	# Czas [s], w ktorym wywolac SCRAM (ujemny = bez SCRAM).
	var scram_at: float = float(args.get("scram-at", "-1"))
	# Wzgledny przeplyw chlodziwa 0..1 (1 = nominal). Spadek -> wrzenie -> void.
	var flow: float = float(args.get("flow", "1"))
	# Co ile krokow zapisywac wiersz (1 = kazdy krok). Domyslnie 5 -> 10 Hz zapisu.
	var sample_every: int = int(args.get("sample", "5"))
	# Uzbrojenie RPS (auto-SCRAM). 0 = tryb "Czarnobyl" (zabezpieczenia obejscia).
	var protection: int = int(args.get("protection", "1"))
	# Warunki przegranej. 0 = surowa fizyka bez konca gry (do badania ekskursji).
	var failures: int = int(args.get("failures", "1"))

	print("=== REAKTOR headless runner (ETAP 1E-1) ===")
	print("seconds=%s seed=%s rod_target=%s external=%s scram_at=%s flow=%s protection=%s failures=%s out=%s" % [
		seconds, seed_value, rod_target, external, scram_at, flow, protection, failures, out_path])

	var sim := Simulation.new(seed_value)
	sim.set_external_reactivity(external)
	sim.set_coolant_flow(flow)
	sim.set_protection_enabled(protection != 0)
	sim.set_failure_states_enabled(failures != 0)
	if rod_target >= 0.0:
		sim.set_rod_target(rod_target)
	var total_steps := int(round(seconds * Simulation.PHYSICS_HZ))
	var scram_done := false

	var rows: PackedStringArray = []
	rows.append("tick,sim_time_s,rod_insertion,reactivity,rho_rods,rho_doppler,rho_void,rho_coolant,reactor_power_fraction,reactor_period_s,fuel_temp_k,coolant_temp_k,clad_temp_k,void_fraction,thermal_power_mw,reactor_state,failure")

	for i in range(total_steps):
		if scram_at >= 0.0 and not scram_done and sim.state.sim_time_seconds >= scram_at:
			sim.scram()
			scram_done = true
		sim.step()
		if sim.state.tick % sample_every == 0:
			rows.append("%d,%.4f,%.6f,%.8f,%.8f,%.8f,%.8f,%.8f,%.8f,%.4f,%.3f,%.3f,%.3f,%.6f,%.3f,%d,%d" % [
				sim.state.tick,
				sim.state.sim_time_seconds,
				sim.state.rod_insertion,
				sim.state.reactivity,
				sim.state.rho_rods,
				sim.state.rho_doppler,
				sim.state.rho_void,
				sim.state.rho_coolant,
				sim.state.reactor_power_fraction,
				sim.state.reactor_period_seconds,
				sim.state.fuel_temp,
				sim.state.coolant_temp,
				sim.state.clad_temp,
				sim.state.void_fraction,
				sim.state.thermal_power_mw,
				sim.state.reactor_state,
				sim.state.failure_state,
			])
		# Awaria konczy gre - przerywamy przebieg.
		if sim.is_failed():
			break

	_write_csv(out_path, rows)
	print("Zapisano %d wierszy do %s" % [rows.size() - 1, out_path])
	print("Stan koncowy: t=%.2fs rod=%.4f rho=%.6f power=%.6f period=%.2fs stan=%s" % [
		sim.state.sim_time_seconds, sim.state.rod_insertion, sim.state.reactivity,
		sim.state.reactor_power_fraction, sim.state.reactor_period_seconds,
		sim.state_machine.state_name()])
	print("  termika: T_paliwa=%.1fK T_chlodziwa=%.1fK T_koszulki=%.1fK void=%.4f moc_cieplna=%.1fMW" % [
		sim.state.fuel_temp, sim.state.coolant_temp, sim.state.clad_temp,
		sim.state.void_fraction, sim.state.thermal_power_mw])
	if sim.is_failed():
		print("  PRZEGRANA: %s" % sim.state.failure_cause)
	var log := sim.get_event_log()
	if not log.is_empty():
		print("  --- log zdarzen (%d) ---" % log.size())
		for entry in log:
			print("  " + entry)

	quit()


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < raw.size():
		var token := raw[i]
		if token.begins_with("--"):
			var key := token.substr(2)
			var value := "true"
			if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				value = raw[i + 1]
				i += 1
			result[key] = value
		i += 1
	return result


func _write_csv(path: String, rows: PackedStringArray) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Nie mozna otworzyc pliku do zapisu: %s" % path)
		return
	file.store_string("\n".join(rows) + "\n")
	file.close()
