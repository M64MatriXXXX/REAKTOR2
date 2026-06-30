class_name Neutronics
extends RefCounted

## Kinetyka punktowa reaktora z 6 grupami opoznionych neutronow.
##
## Rownania (jednostki SI, n znormalizowane: n=1 -> moc nominalna):
##   dn/dt   = ((rho - beta)/Lambda) * n + sum_i lambda_i * C_i
##   dC_i/dt = (beta_i/Lambda) * n - lambda_i * C_i
## gdzie:
##   n        - gestosc neutronow (proporcjonalna do mocy) [-]
##   rho      - reaktywnosc [-] (w ETAP 1A wejscie zewnetrzne; pelny bilans w reactivity.gd)
##   beta     - calkowity udzial opoznionych neutronow [-]
##   Lambda   - czas generacji neutronow natychmiastowych [s]
##   C_i      - "stezenie" prekursorow grupy i (w jednostkach n) [-]
##   lambda_i - stala rozpadu prekursorow grupy i [1/s]
##
## INTEGRATOR: niejawny (backward) Euler z subkrokami.
## Uklad jest sztywny (Lambda~1e-4 s, lambda_i do ~3 1/s), wiec metody jawne sa
## niestabilne przy dt=0.02 s. Backward Euler jest bezwarunkowo stabilny.
## Poniewaz w obrebie subkroku rho jest stale, schemat rozwiazujemy ANALITYCZNIE
## (bez iteracji): z rownania prekursorow wyrazamy C_i^{k+1} przez n^{k+1},
## podstawiamy do rownania na n i dostajemy bezposrednie rozwiazanie liniowe.
##
## Wyprowadzenie (subkrok dlugosci h):
##   C_i^{k+1} = (C_i^k + h*(beta_i/Lambda)*n^{k+1}) / (1 + h*lambda_i)
##   n^{k+1}   = (n^k + h*S0 + h*S) / (1 - a - h*S1)
##     a  = h*(rho - beta)/Lambda
##     S0 = sum_i lambda_i * C_i^k / (1 + h*lambda_i)
##     S1 = sum_i lambda_i * h*(beta_i/Lambda) / (1 + h*lambda_i)
##     S  = zrodlo rozruchowe (ETAP 2F-2; domyslnie 0 -> bit-identycznie jak 1A)

# Docelowa dlugosc subkroku [s]. Krok symulacji (dt) dzielimy na tyle subkrokow,
# by kazdy byl <= tej wartosci. Mniejsze h = wieksza dokladnosc.
const SUBSTEP_TARGET_DT: float = 1.0e-3

# Zabezpieczenie przed dzieleniem przez ~0 przy stanie nadkrytycznym natychmiastowym
# (rho >= beta). Fizycznie oznacza to gwaltowna ekskursje mocy; numerycznie ograniczamy
# mianownik, by uniknac inf/NaN i pozwolic mocy urosnac (teren meltdownu).
const MIN_DENOMINATOR: float = 1.0e-9

var params: ReactorParams

var _n: float = 1.0                       # gestosc neutronow (moc) [-]
var _precursors: PackedFloat64Array       # C_i [-]
var _last_reactivity: float = 0.0         # ostatnio uzyte rho (do okresu reaktora)


func _init(reactor_params: ReactorParams) -> void:
	params = reactor_params
	params.validate()
	_precursors = PackedFloat64Array()
	_precursors.resize(params.group_count())
	initialize_steady_state(1.0)


## Ustawia stan rownowagi (dn/dt = 0 oraz dC_i/dt = 0) dla zadanej mocy.
## Prekursory w rownowadze: C_i = (beta_i/Lambda) * n / lambda_i.
func initialize_steady_state(power_fraction: float) -> void:
	_n = power_fraction
	var gen := params.gen_time   # Lambda
	for i in range(params.group_count()):
		_precursors[i] = (params.beta_groups[i] / gen) * _n / params.lambda[i]
	_last_reactivity = 0.0


## Wykonuje jeden krok kinetyki o dlugosci dt, dzielac go na stabilne subkroki.
## rho - reaktywnosc obowiazujaca w tym kroku.
func step(reactivity: float, dt: float) -> void:
	_last_reactivity = reactivity
	var substeps := maxi(1, int(ceil(dt / SUBSTEP_TARGET_DT)))
	var h := dt / float(substeps)
	for _s in range(substeps):
		_solve_substep(reactivity, h)


## Pojedynczy subkrok niejawnego Eulera (rozwiazanie analityczne, patrz naglowek).
func _solve_substep(reactivity: float, h: float) -> void:
	var gen := params.gen_time
	var a := h * (reactivity - params.total_beta()) / gen

	var s0 := 0.0   # wklad istniejacych prekursorow
	var s1 := 0.0   # wspolczynnik przy n^{k+1} (produkcja prekursorow)
	for i in range(params.group_count()):
		var lam := params.lambda[i]
		var denom_i := 1.0 + h * lam
		s0 += lam * _precursors[i] / denom_i
		s1 += lam * h * (params.beta_groups[i] / gen) / denom_i

	var denom := 1.0 - a - h * s1
	if absf(denom) < MIN_DENOMINATOR:
		denom = MIN_DENOMINATOR if denom >= 0.0 else -MIN_DENOMINATOR

	# Czlon zrodlowy h*S (ETAP 2F-2): przy S=0 to dodanie 0.0 -> wynik bit-identyczny jak 1A.
	var n_next := (_n + h * s0 + h * params.neutron_source) / denom
	# Moc nie moze byc ujemna (artefakt numeryczny przy ekstremalnym tranzjencie).
	n_next = maxf(0.0, n_next)

	# Aktualizacja prekursorow przy nowej wartosci n.
	for i in range(params.group_count()):
		var lam := params.lambda[i]
		_precursors[i] = (_precursors[i] + h * (params.beta_groups[i] / gen) * n_next) / (1.0 + h * lam)

	_n = n_next


## Aktualny ulamek mocy (n).
func get_power_fraction() -> float:
	return _n


## Kopia stezen prekursorow C_1..C_6 (diagnostyka i testy).
func get_precursors() -> PackedFloat64Array:
	return _precursors.duplicate()


## Okres reaktora T = n / (dn/dt) [s]. Liczony z ciaglego rownania przy ostatnim rho.
## Zwraca INF, gdy moc jest praktycznie stala (dn/dt ~ 0).
func get_reactor_period() -> float:
	var dndt := ((_last_reactivity - params.total_beta()) / params.gen_time) * _n
	for i in range(params.group_count()):
		dndt += params.lambda[i] * _precursors[i]
	if absf(dndt) < 1.0e-12:
		return INF
	return _n / dndt
