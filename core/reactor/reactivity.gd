class_name ReactivityModel
extends RefCounted

## Bilans reaktywnosci rho jako suma wkladow czastkowych:
##   rho = rho_prety + rho_doppler + rho_pustki + rho_chlodziwo
##         + rho_ksenon + rho_zewn + rho_excess
##
## Wszystkie wklady w jednostkach bezwzglednych Δρ [-]. Wspolczynniki w ReactivityParams.
## Termohydraulika (1C) i ksenon (1D) wchodza jako WEJSCIA liczbowe (ReactivityInputs),
## dzieki czemu model jest testowalny w izolacji.

var params: ReactivityParams


func _init(reactivity_params: ReactivityParams) -> void:
	params = reactivity_params
	params.validate()


## Prety regulacyjne - integralna wartosc pretow (krzywa S):
##   rho_rods(x) = -W * (x - sin(2*pi*x)/(2*pi)),  x = zaglebienie 0..1
## Wlasnosci: rho(0)=0, rho(1)=-W, rho(0.5)=-W/2; differential worth max w x=0.5.
func rod_reactivity(insertion: float) -> float:
	var x := clampf(insertion, 0.0, 1.0)
	return -params.total_rod_worth * (x - sin(TAU * x) / TAU)


## Sprzezenie paliwowe (Doppler), forma rezonansowa √T, ujemne.
##   rho_doppler = a * (sqrt(T_fuel) - sqrt(T_ref))
## ZABEZPIECZENIE: T_fuel w kelwinach i > 0.
func doppler_reactivity(fuel_temp: float) -> float:
	var t := maxf(fuel_temp, 1.0)
	return params.doppler_coeff_sqrt * (sqrt(t) - sqrt(params.fuel_temp_ref))


## Pochodna wkladu Dopplera po temperaturze paliwa: d(rho_doppler)/dT = a/(2*sqrt(T)).
## Uzywana do liczenia wspolczynnika mocowego (power coefficient).
func doppler_temp_derivative(fuel_temp: float) -> float:
	var t := maxf(fuel_temp, 1.0)
	return params.doppler_coeff_sqrt / (2.0 * sqrt(t))


## Sprzezenie pustkowe (void) - dla RBMK DODATNIE.
func void_reactivity(void_fraction: float) -> float:
	return params.void_coeff * (void_fraction - params.void_ref)


## Wspolczynnik temperaturowy chlodziwa (maly, znak wg konfiguracji).
func coolant_temp_reactivity(coolant_temp: float) -> float:
	return params.coolant_temp_coeff * (coolant_temp - params.coolant_temp_ref)


## Calkowita reaktywnosc (suma wszystkich wkladow + nadwyzka paliwa).
func total_reactivity(inputs: ReactivityInputs) -> float:
	return rod_reactivity(inputs.rod_insertion) \
		+ doppler_reactivity(inputs.fuel_temp) \
		+ void_reactivity(inputs.void_fraction) \
		+ coolant_temp_reactivity(inputs.coolant_temp) \
		+ inputs.xenon_reactivity \
		+ inputs.external_reactivity \
		+ params.excess_reactivity


## Rozbicie reaktywnosci na skladniki (dla wskaznikow/alarmow w UI).
## Suma skladnikow rowna total (spojnosc gwarantowana przez konstrukcje).
func reactivity_breakdown(inputs: ReactivityInputs) -> Dictionary:
	var rods := rod_reactivity(inputs.rod_insertion)
	var doppler := doppler_reactivity(inputs.fuel_temp)
	var void_r := void_reactivity(inputs.void_fraction)
	var coolant := coolant_temp_reactivity(inputs.coolant_temp)
	return {
		"rods": rods,
		"doppler": doppler,
		"void": void_r,
		"coolant": coolant,
		"xenon": inputs.xenon_reactivity,
		"external": inputs.external_reactivity,
		"excess": params.excess_reactivity,
		"total": rods + doppler + void_r + coolant
			+ inputs.xenon_reactivity + inputs.external_reactivity + params.excess_reactivity,
	}


## Wspolczynnik mocowy (power coefficient) d(rho)/dP w danym punkcie pracy.
##   d(rho)/dP = (d rho_doppler/dT_fuel) * dT_fuel/dP
##             + void_coeff * dvoid/dP
##             + coolant_temp_coeff * dT_coolant/dP
## Czulosci dT_fuel/dP, dvoid/dP, dT_coolant/dP dostarcza termohydraulika (1C).
## Warunek stabilnosci normalnego rezimu: power_coefficient < 0 (Doppler przewaza).
func power_coefficient(fuel_temp: float, dfuel_temp_dpower: float,
		dvoid_dpower: float, dcoolant_temp_dpower: float = 0.0) -> float:
	return doppler_temp_derivative(fuel_temp) * dfuel_temp_dpower \
		+ params.void_coeff * dvoid_dpower \
		+ params.coolant_temp_coeff * dcoolant_temp_dpower


## Pozycja krytyczna pretow: zaglebienie x, dla ktorego rho_rods(x) = -other_reactivity,
## czyli calkowita reaktywnosc = 0 przy zadanym wkladzie pozostalych czlonow.
## rod_reactivity jest monotonicznie malejaca, wiec rozwiazanie jest jednoznaczne.
func critical_rod_insertion(other_reactivity: float) -> float:
	var target := -other_reactivity   # docelowa wartosc rho_rods
	if target >= 0.0:
		return 0.0                    # prety wyciagniete (lub stan nadkrytyczny)
	if target <= -params.total_rod_worth:
		return 1.0                    # prety pelni wsuniete (niewystarczajace)
	var lo := 0.0
	var hi := 1.0
	for _iter in range(200):
		var mid := 0.5 * (lo + hi)
		if rod_reactivity(mid) > target:
			lo = mid                  # za malo wsuniete (rho zbyt wysokie)
		else:
			hi = mid
	return 0.5 * (lo + hi)
