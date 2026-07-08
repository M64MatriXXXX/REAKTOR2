class_name Xenon
extends RefCounted

## Zatrucie ksenonowe Xe-135 / I-135 (ETAP 1D).
##
## Rownania (stezenia bezwymiarowe, Sigma_f*flux_nominal ≡ 1; p = ulamek mocy = strumien):
##   dI/dt  = gamma_i*p - lambda_i*I
##   dXe/dt = gamma_xe*p + lambda_i*I - lambda_xe*Xe - burnup_rate_nominal*p*Xe
##   rho_Xe = equilibrium_worth_nominal * (Xe / Xe_eq_nominal)      (<= 0, absorber)
##
## JAMA KSENONOWA: po wylaczeniu (p->0) znika czlon wypalania (burnup*p*Xe), ale I dalej
## rozpada sie w Xe -> Xe rosnie do szczytu (~9-11 h), potem zanika. Glebokosc sterowana
## przez burnup_rate_nominal (wyzsze -> nizsze Xe_eq przy mocy -> wiekszy skok z rezerwuaru I).
##
## INTEGRATOR: niejawny (backward) Euler, liniowy w I i Xe -> bezwarunkowo stabilny, dt-AGNOSTYCZNY
## (dynamika godzinowa: w izolacji testowana duzym dt; w symulacji krok 50 Hz - tez stabilny).

var params: XenonParams

var _iodine: float = 0.0
var _xenon: float = 0.0
var _xe_eq_nominal: float = 1.0   # rownowaga Xe przy p=1 (normalizacja worth) - stala z params


func _init(xenon_params: XenonParams) -> void:
	params = xenon_params
	params.validate()
	# Rownowaga Xe przy mocy nominalnej (p=1): (gamma_i + gamma_xe) / (lambda_xe + burnup_nom).
	# (lambda_i*I_eq = gamma_i przy p=1). Sluzy do normalizacji worth -> rho_Xe(nominal)=worth.
	_xe_eq_nominal = (params.gamma_i + params.gamma_xe) \
		/ (params.lambda_xe + params.burnup_rate_nominal)
	initialize_equilibrium(1.0)


## Ustawia I, Xe w rownowadze dla zadanej mocy p (start ustalony, jak reszta modeli).
##   I_eq  = gamma_i*p / lambda_i
##   Xe_eq = (gamma_xe + gamma_i)*p / (lambda_xe + burnup_rate_nominal*p)
func initialize_equilibrium(power_fraction: float) -> void:
	var p := maxf(0.0, power_fraction)
	_iodine = params.gamma_i * p / params.lambda_i
	if p <= 0.0:
		_xenon = 0.0
	else:
		_xenon = (params.gamma_xe + params.gamma_i) * p \
			/ (params.lambda_xe + params.burnup_rate_nominal * p)


## Krok o dlugosci dt przy zadanej mocy p. Niejawny Euler (Xe uzywa I^{k+1}).
func step(power_fraction: float, dt: float) -> void:
	var p := maxf(0.0, power_fraction)
	_iodine = (_iodine + dt * params.gamma_i * p) / (1.0 + dt * params.lambda_i)
	var removal := params.lambda_xe + params.burnup_rate_nominal * p
	_xenon = (_xenon + dt * (params.gamma_xe * p + params.lambda_i * _iodine)) \
		/ (1.0 + dt * removal)
	_iodine = maxf(0.0, _iodine)
	_xenon = maxf(0.0, _xenon)


## Reaktywnosc ksenonu [Δρ] (<= 0). Normalizowana: przy rownowadze nominalnej = worth.
func xenon_reactivity() -> float:
	return params.equilibrium_worth_nominal * (_xenon / _xe_eq_nominal)


func get_iodine() -> float:
	return _iodine

func get_xenon() -> float:
	return _xenon
