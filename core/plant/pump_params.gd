class_name PumpParams
extends Resource

## Konfigurowalne stale glownych pomp cyrkulacyjnych (ГЦН) - ETAP 2A.
##
## RBMK-1000: 8 pomp (4 na petle), zwykle 3 pracujace + 1 rezerwa na petle.
## Przeplyw nominalny (=1.0) daje 6 czynnych pomp. Jednostki SI / bezwymiarowe.

# --- Konfiguracja ---
@export var loops: int = 2                    # petle obiegu
@export var pumps_per_loop: int = 4           # pomp na petle (3 prac. + 1 rezerwa)
@export var nominal_running_per_loop: int = 3 # czynne w nominale -> 6 pomp = przeplyw 1.0

# --- Bezwladnosc (filtr 1. rzedu) ---
# Czas rozbiegu do predkosci znamionowej [s].
@export var spin_up_time_s: float = 10.0
# Czas WYBIEGU (coast-down) przy utracie zasilania [s] - duza bezwladnosc (flywheel).
# !!! PARAMETR O PODWYZSZONEJ WADZE DO STROJENIA !!!
# Decyduje, ile czasu ma operator przy utracie pomp (utrzymanie chlodzenia podczas SCRAM).
# Ma realne/historyczne znaczenie (test wybiegu pomp w Czarnobylu 1986). Stroic ostroznie.
@export var coast_down_time_s: float = 30.0
# Czas zatrzymania przy ZACIECIU (seizure) [s] - nagle, bez wybiegu.
@export var seizure_time_s: float = 1.5


## Calkowita liczba pomp.
func total_pumps() -> int:
	return loops * pumps_per_loop


## Liczba czynnych pomp w nominale (-> przeplyw 1.0).
func nominal_running() -> int:
	return loops * nominal_running_per_loop


## Wklad pojedynczej pompy do calkowitego ulamka przeplywu (liniowo, UPROSZCZENIE).
func flow_per_pump() -> float:
	return 1.0 / float(nominal_running())


func validate() -> void:
	assert(loops > 0, "PumpParams: loops musi byc > 0")
	assert(pumps_per_loop > 0, "PumpParams: pumps_per_loop musi byc > 0")
	assert(nominal_running_per_loop > 0 and nominal_running_per_loop <= pumps_per_loop,
		"PumpParams: nominal_running_per_loop w (0, pumps_per_loop]")
	assert(spin_up_time_s > 0.0, "PumpParams: spin_up_time_s musi byc > 0")
	assert(coast_down_time_s > 0.0, "PumpParams: coast_down_time_s musi byc > 0")
	assert(seizure_time_s > 0.0, "PumpParams: seizure_time_s musi byc > 0")
