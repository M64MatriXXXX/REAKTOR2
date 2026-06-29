class_name TripSignal
extends RefCounted

## Sygnaly awaryjnego wylaczenia AZ (ETAP 1E-1).
## Kazdy aktywny sygnal wymusza SCRAM. Sluzy tez do logu zdarzen / alarmow (ETAP 2).

enum Type {
	OVERPOWER,    # przekroczenie mocy
	PERIOD,       # zbyt krotki okres reaktora (rozbieganie)
	FUEL_TEMP,    # wysoka temperatura paliwa
	VOID,         # nadmierne wrzenie (frakcja pustek)
	LOW_FLOW,     # niski przeplyw / utrata pomp
	LOW_ORM,      # niski operating reactivity margin (hak do 1E-3)
	PRESSURE,     # wysokie cisnienie obiegu (hak do 1C')
	LOW_SEP_LEVEL, # niski poziom wody w separatorach (utrata feedwater, ETAP 2E)
	MANUAL_AZ5,   # przycisk operatora AZ-5
}


static func describe(t: int) -> String:
	match t:
		Type.OVERPOWER: return "Przekroczenie mocy"
		Type.PERIOD: return "Zbyt krotki okres reaktora (rozbieganie)"
		Type.FUEL_TEMP: return "Wysoka temperatura paliwa"
		Type.VOID: return "Nadmierne wrzenie (pustki)"
		Type.LOW_FLOW: return "Niski przeplyw chlodziwa"
		Type.LOW_ORM: return "Niski ORM"
		Type.PRESSURE: return "Wysokie cisnienie obiegu"
		Type.LOW_SEP_LEVEL: return "Niski poziom wody w separatorach"
		Type.MANUAL_AZ5: return "Manualny AZ-5"
	return "Nieznany sygnal AZ"
