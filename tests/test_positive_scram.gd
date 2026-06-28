extends GutTest

## Testy efektu dodatniego scramu i emergentnego scenariusza "Czarnobyl" (ETAP 1E-3b).
##
## (concern 2) Efekt wyskalowany: przy niskim ORM + pustkach AZ-5 wywoluje rozbieganie,
##             ale w normalnych warunkach (nominalny ORM) SCRAM dalej wylacza reaktor.
## (concern 3) Katastrofa EMERGUJE ze zlozenia (dodatni scram + dodatni void + niski ORM),
##             nie z zaskryptowania - dowod: ten sam setup i AZ-5, rozne tylko ery.


## Wrazliwa konfiguracja "Czarnobyl": prety wyciagniete (niski ORM), chlodziwo blisko
## wrzenia (void usupiony), proxy ksenonu trzyma krytycznosc na niskiej mocy, RPS obejscia.
func _chernobyl_sim(era: SafetyParams) -> Simulation:
	var sim := Simulation.new(0, null, null, null, era)
	sim.set_protection_enabled(false)        # zabezpieczenia obejscia (jak w 1986)
	sim.set_rod_target(0.05)                  # wyciagniete prety -> bardzo niski ORM
	sim.set_coolant_flow(0.55)                # blisko wrzenia (void usupiony, ale na progu)
	sim.set_external_reactivity(-0.0050)      # proxy ksenonu: krytycznosc na niskiej mocy
	return sim


# --- concern 2: normalny SCRAM dalej wylacza (nawet pre-1986) ---

func test_normal_scram_shuts_down_even_pre1986() -> void:
	# Nominalny ORM (~30) -> deficyt 0 -> efekt dodatniego scramu = 0 (z definicji).
	var sim := Simulation.new(0, null, null, null, SafetyParams.pre_1986())
	sim.advance(5.0)
	sim.scram()
	var peak_spike := 0.0
	for i in range(200):   # 4 s okna efektu
		sim.step()
		peak_spike = maxf(peak_spike, sim.state.rho_positive_scram)
	assert_almost_eq(peak_spike, 0.0, 1e-9,
		"Nominalny ORM: brak impulsu dodatniego (SCRAM czysto ujemny)")
	sim.advance(30.0)
	assert_false(sim.is_failed(), "Normalny SCRAM wylacza reaktor nawet pre-1986")
	assert_lt(sim.state.reactor_power_fraction, 0.1, "Reaktor wygaszony")


func test_positive_scram_disabled_post1986() -> void:
	# Post-1986: efekt dodatniego scramu wylaczony niezaleznie od ORM.
	var sim := _chernobyl_sim(SafetyParams.post_1986())
	sim.set_failure_states_enabled(false)
	sim.advance(28.0)
	sim.scram()
	var peak := 0.0
	for i in range(200):
		sim.step()
		peak = maxf(peak, sim.state.rho_positive_scram)
	assert_almost_eq(peak, 0.0, 1e-9, "Post-1986: brak efektu dodatniego scramu")


# --- Efekt dodatniego scramu skaluje sie z niskim ORM ---

func test_positive_scram_spike_present_at_low_orm() -> void:
	var sim := _chernobyl_sim(SafetyParams.pre_1986())
	sim.set_failure_states_enabled(false)   # mierzymy impuls, nie konczymy gry
	sim.advance(28.0)
	assert_lt(sim.state.orm_equivalent_rods, 10.0, "Setup: bardzo niski ORM przed AZ-5")
	sim.scram()
	var peak := 0.0
	for i in range(200):   # 4 s
		sim.step()
		peak = maxf(peak, sim.state.rho_positive_scram)
	assert_gt(peak, 0.005, "Niski ORM -> wyrazny dodatni impuls scramu (>500 pcm, ~prompt)")


func test_positive_scram_profile_vanishes_after_duration() -> void:
	# Impuls znika po positive_scram_duration_s (przejscie wypornik->absorber).
	var sim := _chernobyl_sim(SafetyParams.pre_1986())
	sim.set_failure_states_enabled(false)
	sim.advance(28.0)
	sim.scram()
	var dur := sim.safety_params.positive_scram_duration_s
	sim.advance(dur + 1.0)
	assert_almost_eq(sim.state.rho_positive_scram, 0.0, 1e-9,
		"Po czasie trwania impuls dodatniego scramu wygasa")


# --- concern 3: EMERGENTNY scenariusz "Czarnobyl" ---

func test_emergent_chernobyl_pre1986_fails_post1986_safe() -> void:
	# PRE-1986: ten sam setup i to samo AZ-5 -> katastrofa EMERGUJE ze zlozenia
	# (dodatni scram -> skok mocy -> wrzenie -> ORM-wzmocniony dodatni void -> rozbieganie).
	var pre := _chernobyl_sim(SafetyParams.pre_1986())
	pre.advance(28.0)
	# Dowod braku zaskryptowania: PRZED AZ-5 stan jest stabilny i niegrozny.
	assert_false(pre.is_failed(), "Przed AZ-5 brak awarii (nie zaskryptowane)")
	assert_lt(pre.state.void_fraction, 0.001, "Przed AZ-5 void usupiony (ponizej wrzenia)")
	assert_lt(pre.state.reactor_power_fraction, 1.2, "Przed AZ-5 niska, stabilna moc")
	pre.scram()
	pre.advance(15.0)
	assert_true(pre.is_failed(),
		"PRE-1986: zlozenie dodatni-scram + void + niski ORM -> katastrofa po AZ-5")

	# POST-1986: identyczna konfiguracja i AZ-5 -> bezpieczne wylaczenie.
	var post := _chernobyl_sim(SafetyParams.post_1986())
	post.advance(28.0)
	post.scram()
	post.advance(15.0)
	assert_false(post.is_failed(),
		"POST-1986: brak efektu dodatniego -> AZ-5 bezpiecznie wylacza ten sam stan")
	assert_lt(post.state.reactor_power_fraction, 0.1, "POST-1986: reaktor wygaszony")


func test_chernobyl_failure_chain_is_power_or_thermal() -> void:
	# Awaria to skutek rozbiegania/przegrzania (lancuch fizyczny), nie dowolny stan.
	var pre := _chernobyl_sim(SafetyParams.pre_1986())
	pre.advance(28.0)
	pre.scram()
	pre.advance(15.0)
	var f := pre.get_failure()
	assert_true(
		f == FailureConditions.Type.POWER_RUNAWAY \
		or f == FailureConditions.Type.FUEL_MELTDOWN \
		or f == FailureConditions.Type.CLAD_FAILURE,
		"Przyczyna: rozbieganie mocy / meltdown / uszkodzenie koszulki")
