class_name DecayHeat
extends RefCounted

## Cieplo powylaczeniowe (decay heat) - ETAP 1E-2.
##
## Po wylaczeniu reakcji lancuchowej (SCRAM) rdzen NADAL generuje cieplo z rozpadu
## produktow rozszczepienia: ~6.6% mocy zaraz po wylaczeniu, malejace w czasie.
## To kluczowa, realna mechanika: SCRAM zatrzymuje rozszczepienia, NIE cale cieplo.
## Utrata chlodzenia PO scramie i tak moze doprowadzic do uszkodzenia (mechanizm Fukushima).
##
## Model REZERWUAROWY (kilka grup) - fit przyblizenia Way-Wigner (~0.066*t^-0.2):
##   dE_i/dt = f_i * n - lambda_i * E_i
## gdzie:
##   E_i - wklad grupy i do ulamka mocy cieplnej [-] (rezerwuar produktow rozpadu)
##   n   - aktualny ulamek mocy ROZSZCZEPIEN (z neutroniki)
##   f_i = decay_equilibrium_fraction_i * lambda_i (tak, by w rownowadze E_i = frac_i * n)
##   lambda_i - stala rozpadu grupy [1/s]
## Calkowite cieplo powylaczeniowe = sum_i E_i.
##
## INTEGRATOR: niejawny (backward) Euler na kazdej grupie (bezwarunkowo stabilny):
##   E_i^{k+1} = (E_i^k + h * f_i * n) / (1 + h * lambda_i)

var params: ThermalParams

var _reservoirs: PackedFloat64Array   # E_i [-]


func _init(thermal_params: ThermalParams) -> void:
	params = thermal_params
	_reservoirs = PackedFloat64Array()
	_reservoirs.resize(params.decay_lambda.size())
	initialize_steady_state(1.0)


## Ustawia rownowage rezerwuarow dla zadanego ulamka mocy rozszczepien.
## W rownowadze E_i = decay_equilibrium_fraction_i * n (suma -> ~0.066*n przy n=1).
func initialize_steady_state(power_fraction: float) -> void:
	for i in range(_reservoirs.size()):
		_reservoirs[i] = params.decay_equilibrium_fraction[i] * power_fraction


## Krok rozpadu o dlugosci dt. fission_power_fraction - aktualne n z neutroniki.
func step(fission_power_fraction: float, dt: float) -> void:
	for i in range(_reservoirs.size()):
		var lam := params.decay_lambda[i]
		var f := params.decay_equilibrium_fraction[i] * lam
		_reservoirs[i] = (_reservoirs[i] + dt * f * fission_power_fraction) / (1.0 + dt * lam)


## Calkowity ulamek mocy cieplnej z rozpadu produktow rozszczepienia [-].
func get_decay_power_fraction() -> float:
	var total := 0.0
	for e in _reservoirs:
		total += e
	return total
