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
var rho_positive_scram: float = 0.0       # [-] dodatni impuls efektu scramu (1E-3)

# --- Termohydraulika (ETAP 1C) ---
var fuel_temp: float = 0.0                # [K] temperatura paliwa
var coolant_temp: float = 0.0             # [K] temperatura chlodziwa
var clad_temp: float = 0.0                # [K] temperatura koszulki (proxy, ETAP 1E)
var void_fraction: float = 0.0            # [-] frakcja pustek 0..1
var coolant_flow_fraction: float = 1.0    # [-] wzgledny przeplyw chlodziwa 0..1
var thermal_power_mw: float = 0.0         # [MW] aktualna moc cieplna (prompt+decay)
var decay_heat_fraction: float = 0.0      # [-] ulamek mocy z rozpadu (cieplo powylaczeniowe)

# --- Bezpieczenstwo / stan bloku (ETAP 1E) ---
var orm_equivalent_rods: float = 0.0      # [-] ORM jako rownowazne prety (1E-3)
var reactor_state: int = 0                # ReactorStateMachine.State (OPERATE=2 na starcie)
var active_trips: Array[int] = []         # aktywne sygnaly AZ w tym kroku (TripSignal.Type)
var failure_state: int = 0               # FailureConditions.Type (0 = NONE)
var failure_cause: String = ""            # czytelny opis przyczyny przegranej

# UWAGA (ETAP 1C'+): dojda pola obiegu (cisnienie, przeplyw masowy pomp), ksenonu itd.


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
		"rho_positive_scram": rho_positive_scram,
		"fuel_temp": fuel_temp,
		"coolant_temp": coolant_temp,
		"clad_temp": clad_temp,
		"void_fraction": void_fraction,
		"coolant_flow_fraction": coolant_flow_fraction,
		"thermal_power_mw": thermal_power_mw,
		"decay_heat_fraction": decay_heat_fraction,
		"orm_equivalent_rods": orm_equivalent_rods,
		"reactor_state": reactor_state,
		"active_trips": active_trips.duplicate(),
		"failure_state": failure_state,
		"failure_cause": failure_cause,
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
	rho_positive_scram = data.get("rho_positive_scram", 0.0)
	fuel_temp = data.get("fuel_temp", 0.0)
	coolant_temp = data.get("coolant_temp", 0.0)
	clad_temp = data.get("clad_temp", 0.0)
	void_fraction = data.get("void_fraction", 0.0)
	coolant_flow_fraction = data.get("coolant_flow_fraction", 1.0)
	thermal_power_mw = data.get("thermal_power_mw", 0.0)
	decay_heat_fraction = data.get("decay_heat_fraction", 0.0)
	orm_equivalent_rods = data.get("orm_equivalent_rods", 0.0)
	reactor_state = data.get("reactor_state", 0)
	active_trips.clear()
	for t in data.get("active_trips", []):
		active_trips.append(int(t))
	failure_state = data.get("failure_state", 0)
	failure_cause = data.get("failure_cause", "")


## Gleboka kopia stanu (przydatna do snapshotow i testow regresji).
func duplicate_state() -> PlantState:
	var copy := PlantState.new()
	copy.from_dict(to_dict())
	return copy
