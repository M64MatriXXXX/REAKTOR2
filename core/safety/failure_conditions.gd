class_name FailureConditions
extends RefCounted

## Warunki przegranej (failure states) - ETAP 1E-1.
##
## Co krok sprawdza fizyczne progi katastrofy. Pierwsza wykryta awaria konczy gre
## (Simulation zamraza stan - dalsza "stabilizacja" powyzej progow jest niefizyczna).
## Kazdy warunek ma czytelny lancuch przyczynowy do logu zdarzen (ETAP 2).
##
## Cisnienie (CIRCUIT_RUPTURE) to HAK do 1C' (obieg jeszcze niemodelowany).

enum Type {
	NONE,
	FUEL_MELTDOWN,    # topnienie paliwa UO2
	CLAD_FAILURE,     # uszkodzenie koszulki (cyrkon) - wczesniejszy etap
	POWER_RUNAWAY,    # niekontrolowane rozbieganie mocy (eksplozja energetyczna)
	CIRCUIT_RUPTURE,  # rozerwanie obiegu (eksplozja parowa)
	GENERATOR_DESYNC, # zalaczenie generatora do sieci poza synchronizacja (ETAP 2C)
}

var params: SafetyParams


func _init(safety_params: SafetyParams) -> void:
	params = safety_params


## Proxy temperatury koszulki: wazona srednia paliwo/chlodziwo (w strone paliwa).
## UPROSZCZENIE: model 2-wezlowy nie ma osobnego wezla koszulki.
func clad_temp(state: PlantState) -> float:
	var w := params.clad_temp_fuel_weight
	return w * state.fuel_temp + (1.0 - w) * state.coolant_temp


## Zwraca typ pierwszej wykrytej awarii (lub NONE). Kolejnosc: najciezsza wprost.
func check(state: PlantState) -> int:
	if state.fuel_temp >= params.fuel_melt_temp_k:
		return Type.FUEL_MELTDOWN
	if state.reactor_power_fraction >= params.power_runaway_fraction:
		return Type.POWER_RUNAWAY
	if state.pressure_mpa >= params.pressure_rupture_mpa:
		return Type.CIRCUIT_RUPTURE
	if clad_temp(state) >= params.clad_failure_temp_k:
		return Type.CLAD_FAILURE
	return Type.NONE


static func describe(t: int) -> String:
	match t:
		Type.NONE: return "Brak awarii"
		Type.FUEL_MELTDOWN: return "Stopienie paliwa (meltdown rdzenia)"
		Type.CLAD_FAILURE: return "Uszkodzenie koszulki paliwowej"
		Type.POWER_RUNAWAY: return "Niekontrolowane rozbieganie mocy (eksplozja)"
		Type.GENERATOR_DESYNC: return "Zalaczenie generatora poza synchronizacja (uszkodzenie)"
		Type.CIRCUIT_RUPTURE: return "Rozerwanie obiegu (eksplozja parowa)"
	return "Nieznana awaria"
