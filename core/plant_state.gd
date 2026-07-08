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
var pumps_running: int = 0                # liczba czynnych pomp ГЦН (ETAP 2A)
var thermal_power_mw: float = 0.0         # [MW] aktualna moc cieplna (prompt+decay)

# --- Separatory / obieg parowy (ETAP 2B) ---
var pressure_mpa: float = 0.0             # [MPa] cisnienie obiegu (separatory)
var steam_quality: float = 0.0            # [-] jakosc pary na wylocie separatora (~0.15)
var steam_dump_flow: float = 0.0          # [-] strumien zrzutu pary (BRU)

# --- Turbina / generator / siec (ETAP 2C) ---
var electrical_power_mw: float = 0.0      # [MWe] moc elektryczna oddawana do sieci
var turbine_speed: float = 1.0            # [-] obroty turbiny (1.0 = synchroniczne)
var turbine_tripped: bool = false         # zabezpieczenie nadobrotowe turbiny
var turbine_state: int = 2                # TurbineStateMachine.State (READY_TO_SYNC=2, ETAP 2F-1)
var grid_connected: bool = false          # generator zalaczony do sieci
var grid_frequency_hz: float = 0.0        # [Hz] czestotliwosc generatora
var blackout: bool = false                # utrata zasilania zewnetrznego (pompy na wybiegu, 2F-1)
var pump_supply_fraction: float = 1.0     # [-] zasilanie szyny pomp (1.0 = pelne)
var decay_heat_fraction: float = 0.0      # [-] ulamek mocy z rozpadu (cieplo powylaczeniowe)

# --- Skraplacz / proznia / routing BRU (ETAP 2D) ---
var condenser_pressure_kpa: float = 0.0   # [kPa abs] cisnienie skraplacza (~5 kPa nominalnie)
var condenser_vacuum_fraction: float = 0.0 # [-] frakcja prozni 0..1 (1.0 = pelna proznia)
var condenser_steam_inflow: float = 0.0   # [-] doplyw pary do skraplacza (wydech turbiny + BRU-K)
var bru_route_atmosphere: bool = false    # zrzut przelaczony na BRU-A (atmosfera) zamiast BRU-K
var bru_k_dumping: bool = false           # zrzut BRU-K aktualnie wplywa do skraplacza

# --- Uklad wody zasilajacej / petla masy (ETAP 2E) ---
# Poziomy domyslnie NOMINALNE (1.0): stan bez informacji o wodzie traktowany jako nominalny,
# by nie wywolywac falszywego tripu niskiego poziomu (np. recznie budowane stany w testach).
var separator_level: float = 1.0          # [-] poziom wody bebnow separatora (nominał 1.0)
var hotwell_level: float = 1.0           # [-] zapas kondensatu w hotwellu
var deaerator_level: float = 1.0          # [-] zapas wody w deaeratorze
var feedwater_flow: float = 0.0           # [-] przeplyw wody zasilajacej (deaerator->separator)
var condensate_flow: float = 0.0          # [-] przeplyw kondensatu (hotwell->deaerator)
var makeup_flow: float = 0.0              # [-] dopływ uzupelniajacy (domyslnie 0)
var total_water_mass: float = 0.0         # [-] suma zapasow (separator+hotwell+deaerator)
var bru_a_lost_cumulative: float = 0.0    # [-] skumulowany ubytek masy przez BRU-A (atmosfera)

# --- Ksenon (ETAP 1D) ---
var iodine_conc: float = 0.0              # [-] stezenie I-135 (bezwymiarowe)
var xenon_conc: float = 0.0               # [-] stezenie Xe-135 (bezwymiarowe)

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
		"pumps_running": pumps_running,
		"pressure_mpa": pressure_mpa,
		"steam_quality": steam_quality,
		"steam_dump_flow": steam_dump_flow,
		"electrical_power_mw": electrical_power_mw,
		"turbine_speed": turbine_speed,
		"turbine_tripped": turbine_tripped,
		"turbine_state": turbine_state,
		"grid_connected": grid_connected,
		"grid_frequency_hz": grid_frequency_hz,
		"blackout": blackout,
		"pump_supply_fraction": pump_supply_fraction,
		"thermal_power_mw": thermal_power_mw,
		"decay_heat_fraction": decay_heat_fraction,
		"condenser_pressure_kpa": condenser_pressure_kpa,
		"condenser_vacuum_fraction": condenser_vacuum_fraction,
		"condenser_steam_inflow": condenser_steam_inflow,
		"bru_route_atmosphere": bru_route_atmosphere,
		"bru_k_dumping": bru_k_dumping,
		"separator_level": separator_level,
		"hotwell_level": hotwell_level,
		"deaerator_level": deaerator_level,
		"feedwater_flow": feedwater_flow,
		"condensate_flow": condensate_flow,
		"makeup_flow": makeup_flow,
		"total_water_mass": total_water_mass,
		"bru_a_lost_cumulative": bru_a_lost_cumulative,
		"iodine_conc": iodine_conc,
		"xenon_conc": xenon_conc,
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
	pumps_running = data.get("pumps_running", 0)
	pressure_mpa = data.get("pressure_mpa", 0.0)
	steam_quality = data.get("steam_quality", 0.0)
	steam_dump_flow = data.get("steam_dump_flow", 0.0)
	electrical_power_mw = data.get("electrical_power_mw", 0.0)
	turbine_speed = data.get("turbine_speed", 1.0)
	turbine_tripped = data.get("turbine_tripped", false)
	turbine_state = data.get("turbine_state", 2)
	grid_connected = data.get("grid_connected", false)
	grid_frequency_hz = data.get("grid_frequency_hz", 0.0)
	blackout = data.get("blackout", false)
	pump_supply_fraction = data.get("pump_supply_fraction", 1.0)
	thermal_power_mw = data.get("thermal_power_mw", 0.0)
	decay_heat_fraction = data.get("decay_heat_fraction", 0.0)
	condenser_pressure_kpa = data.get("condenser_pressure_kpa", 0.0)
	condenser_vacuum_fraction = data.get("condenser_vacuum_fraction", 0.0)
	condenser_steam_inflow = data.get("condenser_steam_inflow", 0.0)
	bru_route_atmosphere = data.get("bru_route_atmosphere", false)
	bru_k_dumping = data.get("bru_k_dumping", false)
	separator_level = data.get("separator_level", 0.0)
	hotwell_level = data.get("hotwell_level", 0.0)
	deaerator_level = data.get("deaerator_level", 0.0)
	feedwater_flow = data.get("feedwater_flow", 0.0)
	condensate_flow = data.get("condensate_flow", 0.0)
	makeup_flow = data.get("makeup_flow", 0.0)
	total_water_mass = data.get("total_water_mass", 0.0)
	bru_a_lost_cumulative = data.get("bru_a_lost_cumulative", 0.0)
	iodine_conc = data.get("iodine_conc", 0.0)
	xenon_conc = data.get("xenon_conc", 0.0)
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
