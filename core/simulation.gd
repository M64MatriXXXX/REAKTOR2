class_name Simulation
extends RefCounted

## Glowny orkiestrator symulacji.
##
## Odpowiada za:
##  - posiadanie PlantState,
##  - deterministyczny krok czasu o stalej dlugosci (fixed timestep),
##  - (ETAP 1) wywolanie modeli fizycznych: neutronika -> reaktywnosc ->
##    termohydraulika -> ksenon -> obieg/turbina/sieć -> bezpieczenstwo.
##
## Determinizm: przy zadanym ziarnie (seed) i tej samej sekwencji komend
## wynik jest identyczny. To warunek konieczny testow i multiplayera.
##
## ETAP 0: step() jedynie posuwa czas i ustawia placeholderowa wartosc mocy,
##         by zademonstrowac petle i eksport CSV. Fizyka wejdzie w ETAPIE 1.

# Stala czestotliwosc kroku fizyki. 50 Hz -> dt = 0.02 s.
const PHYSICS_HZ: float = 50.0
const FIXED_DT: float = 1.0 / PHYSICS_HZ   # [s]

var state: PlantState
var _rng: RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	state = PlantState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


## Wykonuje JEDEN krok symulacji o staly FIXED_DT.
## ETAP 1: tutaj wpiety zostanie lancuch modeli fizycznych.
func step() -> void:
	# UPROSZCZENIE (ETAP 0): brak fizyki. Placeholderowa "moc" rosnie liniowo
	# i nasyca sie do 1.0 - sluzy wylacznie do testu petli i eksportu danych.
	state.tick += 1
	state.sim_time_seconds += FIXED_DT
	state.reactor_power_fraction = minf(1.0, state.reactor_power_fraction + 0.001)


## Posuwa symulacje o zadany realny czas, dzielac go na stale subkroki.
## Akumulator gwarantuje niezaleznosc fizyki od FPS renderowania.
## Zwraca liczbe wykonanych krokow.
func advance(real_delta_seconds: float) -> int:
	var steps := 0
	var remaining := real_delta_seconds
	while remaining >= FIXED_DT:
		step()
		remaining -= FIXED_DT
		steps += 1
	return steps
