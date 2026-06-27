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
var reactivity: float = 0.0               # [-] aktualna calkowita reaktywnosc rho
var reactor_period_seconds: float = INF   # [s] okres reaktora (INF gdy moc stala)

# --- Reaktywnosc i prety (ETAP 1B) ---
var rod_insertion: float = 0.0            # [-] zaglebienie pretow 0..1 (1 = wsuniete)
# Rozbicie reaktywnosci na wklady (dla wskaznikow/alarmow w ETAP 2).
var rho_rods: float = 0.0
var rho_doppler: float = 0.0
var rho_void: float = 0.0
var rho_coolant: float = 0.0
var rho_xenon: float = 0.0

# UWAGA (ETAP 1C+): dojda pola termiki, cisnienia, frakcji pustek, ksenonu itd.


## Zwraca slownik z pelnym stanem - podstawa save/load oraz synchronizacji sieciowej.
func to_dict() -> Dictionary:
	return {
		"sim_time_seconds": sim_time_seconds,
		"tick": tick,
		"reactor_power_fraction": reactor_power_fraction,
		"reactivity": reactivity,
		"reactor_period_seconds": reactor_period_seconds,
		"rod_insertion": rod_insertion,
		"rho_rods": rho_rods,
		"rho_doppler": rho_doppler,
		"rho_void": rho_void,
		"rho_coolant": rho_coolant,
		"rho_xenon": rho_xenon,
	}


## Odtwarza stan ze slownika (np. snapshot od hosta w multiplayerze).
func from_dict(data: Dictionary) -> void:
	sim_time_seconds = data.get("sim_time_seconds", 0.0)
	tick = data.get("tick", 0)
	reactor_power_fraction = data.get("reactor_power_fraction", 0.0)
	reactivity = data.get("reactivity", 0.0)
	reactor_period_seconds = data.get("reactor_period_seconds", INF)
	rod_insertion = data.get("rod_insertion", 0.0)
	rho_rods = data.get("rho_rods", 0.0)
	rho_doppler = data.get("rho_doppler", 0.0)
	rho_void = data.get("rho_void", 0.0)
	rho_coolant = data.get("rho_coolant", 0.0)
	rho_xenon = data.get("rho_xenon", 0.0)


## Gleboka kopia stanu (przydatna do snapshotow i testow regresji).
func duplicate_state() -> PlantState:
	var copy := PlantState.new()
	copy.from_dict(to_dict())
	return copy
