class_name ProtectionSystem
extends RefCounted

## System zabezpieczen reaktora (RPS) - ETAP 1E-1.
##
## Niezalezny od sterowania (PCS) i nad nim NADRZEDNY. Co krok ocenia warunki AZ
## na podstawie aktualnego PlantState; kazdy spelniony warunek -> SCRAM.
## Progi w SafetyParams (konfigurowalne).
##
## ORM i cisnienie to na razie HAKI (ORM - 1E-3, cisnienie - 1C').

var params: SafetyParams


func _init(safety_params: SafetyParams) -> void:
	params = safety_params
	params.validate()


## Zwraca liste aktywnych sygnalow AZ (TripSignal.Type) dla danego stanu.
## manual_az5 - czy operator wcisnal przycisk AZ-5 (sygnal manualny).
## Kolejnosc deterministyczna (wazne dla determinizmu i porownan stanu).
func evaluate(state: PlantState, manual_az5: bool) -> Array[int]:
	var trips: Array[int] = []

	if state.reactor_power_fraction > params.overpower_trip_fraction:
		trips.append(TripSignal.Type.OVERPOWER)

	# Period trip: tylko DODATNI, krotki okres = rozbieganie. INF/ujemny nie liczy sie.
	var period := state.reactor_period_seconds
	if period > 0.0 and period < params.period_trip_seconds:
		trips.append(TripSignal.Type.PERIOD)

	if state.fuel_temp > params.fuel_temp_trip_k:
		trips.append(TripSignal.Type.FUEL_TEMP)

	if state.void_fraction > params.void_trip_fraction:
		trips.append(TripSignal.Type.VOID)

	if state.coolant_flow_fraction < params.low_flow_trip_fraction:
		trips.append(TripSignal.Type.LOW_FLOW)

	# HAK: LOW_ORM (1E-3), PRESSURE (1C') - dodane, gdy modele beda gotowe.

	if manual_az5:
		trips.append(TripSignal.Type.MANUAL_AZ5)

	return trips
