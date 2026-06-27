class_name PlantState
extends RefCounted

## Pelny, serializowalny stan bloku energetycznego.
##
## Ta klasa to PROSTY KONTENER DANYCH. Nie zawiera logiki fizyki.
## Stanowi jedyny kanal odczytu stanu dla UI / multiplayera (zasada separacji:
## core/ nigdy nie importuje ui/, world/, net/).
##
## ETAP 0: pola minimalne, sluzace do uruchomienia petli i eksportu CSV.
## ETAP 1: dojda pelne pola fizyczne (neutron_flux, fuel_temperature,
##         coolant_pressure, void_fraction, xenon_concentration, itd.).
##         Patrz plan klas neutroniki.

# --- Czas symulacji ---
var sim_time_seconds: float = 0.0   # [s] czas od startu symulacji
var tick: int = 0                   # numer kroku (do determinizmu/debug)

# --- Neutronika (ETAP 1A) ---
var reactor_power_fraction: float = 0.0   # [-] ulamek mocy nominalnej (n), n=1 -> nominalna
var reactivity: float = 0.0               # [-] aktualna reaktywnosc rho (w 1A wejscie zewnetrzne)
var reactor_period_seconds: float = INF   # [s] okres reaktora (INF gdy moc stala)

# UWAGA (ETAP 1B+): dojda pola termiki, cisnienia, frakcji pustek, ksenonu itd.


## Zwraca slownik z pelnym stanem - podstawa save/load oraz synchronizacji sieciowej.
func to_dict() -> Dictionary:
	return {
		"sim_time_seconds": sim_time_seconds,
		"tick": tick,
		"reactor_power_fraction": reactor_power_fraction,
		"reactivity": reactivity,
		"reactor_period_seconds": reactor_period_seconds,
	}


## Odtwarza stan ze slownika (np. snapshot od hosta w multiplayerze).
func from_dict(data: Dictionary) -> void:
	sim_time_seconds = data.get("sim_time_seconds", 0.0)
	tick = data.get("tick", 0)
	reactor_power_fraction = data.get("reactor_power_fraction", 0.0)
	reactivity = data.get("reactivity", 0.0)
	reactor_period_seconds = data.get("reactor_period_seconds", INF)


## Gleboka kopia stanu (przydatna do snapshotow i testow regresji).
func duplicate_state() -> PlantState:
	var copy := PlantState.new()
	copy.from_dict(to_dict())
	return copy
