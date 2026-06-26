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
	# Co ile krokow zapisywac wiersz (1 = kazdy krok). Domyslnie 5 -> 10 Hz zapisu.
	var sample_every: int = int(args.get("sample", "5"))

	print("=== REAKTOR headless runner (ETAP 0) ===")
	print("seconds=%s seed=%s out=%s sample_every=%s" % [seconds, seed_value, out_path, sample_every])

	var sim := Simulation.new(seed_value)
	var total_steps := int(round(seconds * Simulation.PHYSICS_HZ))

	var rows: PackedStringArray = []
	rows.append("tick,sim_time_s,reactor_power_fraction")

	for i in range(total_steps):
		sim.step()
		if sim.state.tick % sample_every == 0:
			rows.append("%d,%.4f,%.6f" % [
				sim.state.tick,
				sim.state.sim_time_seconds,
				sim.state.reactor_power_fraction,
			])

	_write_csv(out_path, rows)
	print("Zapisano %d wierszy do %s" % [rows.size() - 1, out_path])
	print("Stan koncowy: t=%.2fs power=%.4f" % [
		sim.state.sim_time_seconds, sim.state.reactor_power_fraction])

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
