extends GutTest

## Testy SPRZEZENIA neutronika <-> termohydraulika w pelnej Simulation (ETAP 1C).
## Tu fizyka jest juz zamknieta: moc -> cieplo -> temp/void -> reaktywnosc -> moc,
## ze sprzezeniem o opoznieniu 1 kroku (najpierw neutronika, potem termika).


# --- Nominal: rownowaga i dominacja Dopplera ---

func test_nominal_start_holds_steady() -> void:
	var sim := Simulation.new(0)
	sim.advance(60.0)
	assert_almost_eq(sim.state.reactor_power_fraction, 1.0, 5e-3,
		"Start nominalny trzyma moc ~1 (punkt krytyczny + rownowaga cieplna)")
	assert_eq(sim.state.void_fraction, 0.0, "Brak pustek w nominale (chlodziwo < T_sat)")
	assert_almost_eq(sim.state.fuel_temp, 800.0, 1.0, "T_paliwa rownowagi ~800 K")
	assert_almost_eq(sim.state.coolant_temp, 550.0, 1.0, "T_chlodziwa rownowagi ~550 K")


func test_doppler_damps_impulse_at_nominal() -> void:
	# Realne sprzezenie (zastepuje kwazi-statyczny model z testu 1B):
	# +50 pcm w nominale -> Doppler grzeje paliwo i TLUMI ekskursje do ~1.08.
	var sim := Simulation.new(0)
	sim.set_external_reactivity(0.0005)
	sim.advance(120.0)
	var p := sim.state.reactor_power_fraction
	assert_gt(p, 1.0, "Impuls +50 pcm nieco podnosi moc...")
	assert_lt(p, 1.15, "...ale Doppler dominuje -> moc ograniczona (~1.08)")
	assert_eq(sim.state.void_fraction, 0.0, "W nominale brak wrzenia mimo impulsu")
	assert_gt(sim.state.fuel_temp, 800.0, "Paliwo cieplejsze -> ujemny Doppler tlumi")


# --- Niski przeplyw: dodatni wsp. pustkowy -> regim niestabilny ---

func test_low_flow_triggers_void_and_power_excursion() -> void:
	# Spadek przeplywu -> wrzenie -> DODATNI wklad pustkowy przewaza -> ekskursja mocy.
	# To realny odpowiednik "dodatniego power coefficient" z testu 1B.
	var sim := Simulation.new(0)
	sim.set_coolant_flow(0.5)
	sim.advance(60.0)
	assert_gt(sim.state.void_fraction, 0.0, "Niski przeplyw -> wrzenie (pustki)")
	assert_gt(sim.state.rho_void, 0.0, "Wklad pustkowy DODATNI (cecha RBMK)")
	assert_gt(sim.state.reactor_power_fraction, 1.5,
		"Dodatnie sprzezenie pustkowe -> wyrazna ekskursja mocy (niestabilnosc)")


func test_low_flow_more_sensitive_than_nominal() -> void:
	# Ten sam maly impuls: nominal tlumiony, niski przeplyw silnie wzmocniony.
	var sim_nom := Simulation.new(0)
	sim_nom.set_external_reactivity(0.0005)
	sim_nom.advance(60.0)
	var sim_low := Simulation.new(0)
	sim_low.set_coolant_flow(0.5)
	sim_low.set_external_reactivity(0.0005)
	sim_low.advance(60.0)
	assert_lt(sim_nom.state.reactor_power_fraction, 1.2, "Nominal: impuls wytlumiony")
	assert_gt(sim_low.state.reactor_power_fraction,
		sim_nom.state.reactor_power_fraction * 2.0,
		"Niski przeplyw/duze pustki: uklad znacznie bardziej wrazliwy")


# --- ZADANIE (a): petla void + opoznienie 1 kroku NIE oscyluje numerycznie ---

func test_void_feedback_loop_no_sustained_oscillation() -> void:
	# Przy NOMINALNYCH stalych czasowych dodatnie sprzezenie pustkowe z opoznieniem
	# 1 kroku daje odpowiedz TLUMIONA (najwyzej jedno przeregulowanie), a nie
	# narastajaca/utrzymujaca sie oscylacje numeryczna. Sprawdzamy wprost:
	#  - przebieg pozostaje skonczony i ograniczony,
	#  - ustala sie do nowej rownowagi,
	#  - po wygasnieciu ekskursji (t>40 s) jest monotoniczny (brak dzwonienia).
	var sim := Simulation.new(0)
	sim.set_coolant_flow(0.5)
	var powers: Array[float] = []
	var steps := int(round(250.0 / Simulation.FIXED_DT))
	for i in range(steps):
		sim.step()
		powers.append(sim.state.reactor_power_fraction)

	var n := powers.size()
	assert_true(is_finite(powers[n - 1]), "Moc pozostaje skonczona (brak blow-up)")
	assert_lt(powers[n - 1], 200.0, "Moc ograniczona (Doppler + nasycenie void limituja)")

	# Ustabilizowanie: koniec ~ stan 10 s wczesniej.
	assert_almost_eq(powers[n - 1], powers[n - 501], 1e-2,
		"Odpowiedz ustala sie do nowej rownowagi")

	# Brak utrzymujacych sie oscylacji: po t=40 s zero zmian kierunku (z tolerancja 1).
	var start := int(round(40.0 / Simulation.FIXED_DT))
	var reversals := 0
	var prev_dir := 0
	for i in range(start + 1, n):
		var d := powers[i] - powers[i - 1]
		if absf(d) < 1e-7:
			continue
		var dir := 1 if d > 0.0 else -1
		if prev_dir != 0 and dir != prev_dir:
			reversals += 1
		prev_dir = dir
	assert_lte(reversals, 1,
		"Petla void + opoznienie 1 kroku: odpowiedz tlumiona, bez oscylacji numerycznych")


func test_scram_recovers_from_low_flow_excursion() -> void:
	# Po ekskursji niskoprzeplywowej SCRAM wsuwa prety i sprowadza moc w dol.
	var sim := Simulation.new(0)
	sim.set_coolant_flow(0.5)
	sim.advance(30.0)
	var peak := sim.state.reactor_power_fraction
	sim.scram()
	sim.advance(30.0)
	assert_lt(sim.state.reactor_power_fraction, peak,
		"SCRAM redukuje moc po ekskursji (prety przewazaja dodatni void)")
