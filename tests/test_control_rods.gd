extends GutTest

## Testy kinematyki pretow regulacyjnych (ETAP 1B).

const DT := 0.02


func test_starts_at_given_insertion() -> void:
	var rods := ControlRods.new(0.01, 0.3, 0.25)
	assert_almost_eq(rods.get_insertion(), 0.25, 1e-9, "Start na zadanej pozycji")
	assert_true(rods.is_at_target(), "Na starcie cel = pozycja")


func test_moves_toward_target_at_normal_speed() -> void:
	var rods := ControlRods.new(0.01, 0.3, 0.0)
	rods.set_target(1.0)
	rods.step(DT)   # ruch o 0.01 * 0.02 = 0.0002
	assert_almost_eq(rods.get_insertion(), 0.0002, 1e-9, "Ruch z predkoscia normalna")


func test_reaches_target_without_overshoot() -> void:
	var rods := ControlRods.new(0.5, 0.5, 0.0)
	rods.set_target(0.1)
	# 0.5 * 0.02 = 0.01 na krok -> 10 krokow do 0.1, sprawdzamy brak przeskoku.
	for i in range(20):
		rods.step(DT)
	assert_almost_eq(rods.get_insertion(), 0.1, 1e-9, "Osiaga cel bez przeskoku")
	assert_true(rods.is_at_target())


func test_target_is_clamped_to_unit_range() -> void:
	var rods := ControlRods.new(0.01, 0.3, 0.5)
	rods.set_target(5.0)
	assert_almost_eq(rods.get_target(), 1.0, 1e-9, "Cel klamrowany do 1.0")
	rods.set_target(-3.0)
	assert_almost_eq(rods.get_target(), 0.0, 1e-9, "Cel klamrowany do 0.0")


func test_scram_drives_full_insertion_at_scram_speed() -> void:
	var rods := ControlRods.new(0.01, 0.3, 0.2)
	rods.scram()
	assert_almost_eq(rods.get_target(), 1.0, 1e-9, "SCRAM: cel = pelne wsuniecie")
	assert_true(rods.is_scram_active())
	rods.step(DT)   # ruch o 0.3 * 0.02 = 0.006 (predkosc SCRAM, nie normalna)
	assert_almost_eq(rods.get_insertion(), 0.206, 1e-9, "SCRAM rusza z predkoscia awaryjna")


func test_scram_overrides_normal_control() -> void:
	var rods := ControlRods.new(0.01, 0.3, 0.5)
	rods.scram()
	rods.set_target(0.0)   # proba "odwolania" SCRAM zwyklym sterowaniem - ignorowana
	assert_almost_eq(rods.get_target(), 1.0, 1e-9, "Po SCRAM zwykle sterowanie nie cofa pretow")


func test_full_scram_insertion_time() -> void:
	# v_scram = 0.3 1/s -> pelne wsuniecie z 0.0 w ~3.33 s.
	var rods := ControlRods.new(0.01, 0.3, 0.0)
	rods.scram()
	var t := 0.0
	while not rods.is_at_target() and t < 10.0:
		rods.step(DT)
		t += DT
	assert_almost_eq(t, 1.0 / 0.3, 0.05, "Pelny SCRAM w ~3.33 s")
	assert_almost_eq(rods.get_insertion(), 1.0, 1e-9)
