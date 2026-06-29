class_name ProtectionSystem
extends RefCounted

## System zabezpieczen reaktora (RPS) - ETAP 1E-1 + filtr persystencji (1E-2).
##
## Niezalezny od sterowania (PCS) i nad nim NADRZEDNY. Co krok ocenia warunki AZ
## na podstawie aktualnego PlantState. Progi w SafetyParams (konfigurowalne).
##
## DEBOUNCE: auto-trip wymusza SCRAM dopiero, gdy warunek UTRZYMA sie przez
## trip_confirmation_time_s (filtruje prompt jump / szum od realnego rozbiegania).
## Manualny AZ-5 dziala natychmiast. Stan czasow aktywnosci jest WEWNETRZNY -
## to czyni RPS stanowym; determinizm zachowany (stala kolejnosc, krok dt).
##
## ORM i cisnienie to na razie HAKI (ORM - 1E-3, cisnienie - 1C').

# Auto-trip-y objete oknem potwierdzenia (bez manualnego AZ-5). Stala kolejnosc!
const AUTO_TRIPS: Array[int] = [
	TripSignal.Type.OVERPOWER,
	TripSignal.Type.PERIOD,
	TripSignal.Type.FUEL_TEMP,
	TripSignal.Type.VOID,
	TripSignal.Type.LOW_FLOW,
	TripSignal.Type.LOW_ORM,
	TripSignal.Type.PRESSURE,
	TripSignal.Type.LOW_SEP_LEVEL,
]
const _CONFIRM_EPSILON: float = 1.0e-9

var params: SafetyParams
var _active_time: Dictionary = {}   # TripSignal.Type -> ciagly czas aktywnosci warunku [s]


func _init(safety_params: SafetyParams) -> void:
	params = safety_params
	params.validate()
	for t in AUTO_TRIPS:
		_active_time[t] = 0.0


## Surowa (chwilowa, bezstanowa) ocena warunkow AZ - bez okna potwierdzenia.
## manual_az5 - przycisk operatora. Kolejnosc deterministyczna.
func evaluate_raw(state: PlantState, manual_az5: bool) -> Array[int]:
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

	# Niski ORM tylko, gdy interlock uzbrojony (post-1986). Pre-1986 -> pulapka mozliwa.
	if params.orm_protection_enabled \
			and state.orm_equivalent_rods < params.orm_trip_equivalent_rods:
		trips.append(TripSignal.Type.LOW_ORM)

	# Wysokie cisnienie obiegu (separatory, ETAP 2B).
	if state.pressure_mpa > params.pressure_trip_mpa:
		trips.append(TripSignal.Type.PRESSURE)

	# Niski poziom wody w separatorach (utrata feedwater, ETAP 2E).
	if state.separator_level < params.separator_level_low_trip:
		trips.append(TripSignal.Type.LOW_SEP_LEVEL)

	if manual_az5:
		trips.append(TripSignal.Type.MANUAL_AZ5)

	return trips


## Stanowa ocena z oknem potwierdzenia. Zwraca POTWIERDZONE sygnaly AZ (te, ktore
## wymuszaja SCRAM): auto-trip utrzymany >= trip_confirmation_time_s + manualny AZ-5.
## Wolac raz na krok fizyki (aktualizuje liczniki czasu).
func update(state: PlantState, manual_az5: bool, dt: float) -> Array[int]:
	var raw := evaluate_raw(state, false)   # manual obslugiwany osobno (natychmiast)
	var confirmed: Array[int] = []
	for t in AUTO_TRIPS:
		if t in raw:
			_active_time[t] += dt
			if _active_time[t] >= params.trip_confirmation_time_s - _CONFIRM_EPSILON:
				confirmed.append(t)
		else:
			_active_time[t] = 0.0
	if manual_az5:
		confirmed.append(TripSignal.Type.MANUAL_AZ5)
	return confirmed
