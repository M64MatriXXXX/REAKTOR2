class_name SteamSeparators
extends RefCounted

## Separatory / bebny parowe - ETAP 2B.
##
## Pierwszy element strony wtornej. Rozdziela pare (jakosc ~15%) od wody i prowadzi
## PETLE CISNIENIA obiegu: cisnienie rosnie, gdy produkcja pary > odbior, spada gdy <.
##
## ODBIOR PARY (gdzie idzie para bez turbiny):
##   odbior_calkowity = zrzut_regulowany(P) + odbior_zewnetrzny
##   - zrzut (BRU) to TRWALY komponent: w 2B trzyma cisnienie na nastawie (tryb rozruchowy),
##     w 2C turbina dochodzi jako odbior_zewnetrzny (glowny odbiornik), zrzut zostaje jako bypass.
##
## INTEGRATOR: niejawny (backward) Euler. Zrzut liniowy w P -> krok jest LINIOWYM wzorem,
## bezwarunkowo stabilny (mianownik > 1), bez oscylacji - wlasciwy dla wolnej, pojemnosciowej
## dynamiki. Sprzezenie P->void (przez T_sat) realizujemy z OPOZNIENIEM 1 KROKU w Simulation.
##
## Poziom wody: ODLOZONY w pelni do 2E (regulacja feedwater).

var params: SeparatorParams

var _pressure: float = 0.0      # [MPa]
var _dump_flow: float = 0.0     # [-] aktualny strumien zrzutu
var _dump_available: bool = true
var _water_level: float = 0.0   # [-] poziom wody bebnow (ETAP 2E)


func _init(separator_params: SeparatorParams) -> void:
	params = separator_params
	params.validate()
	# Start na nastawie -> brak transientu w nominale (produkcja=odbior).
	_pressure = params.pressure_setpoint
	_water_level = params.water_level_setpoint


## Krok petli cisnienia o dlugosci dt.
## steam_production   - strumien pary z rdzenia [-] (~ moc cieplna),
## external_offtake   - odbior zewnetrzny [-] (turbina w 2C; 0 w 2B).
func step(steam_production: float, external_offtake: float, dt: float) -> void:
	var g := params.dump_gain
	var pc := params.dump_closed_pressure
	var kp := params.pressure_capacitance
	var dmax := params.dump_max_capacity if _dump_available else 0.0

	# Niejawny krok zakladajacy zrzut w strefie liniowej.
	var p_lin := (_pressure + dt * kp * (steam_production - external_offtake + g * pc)) \
		/ (1.0 + dt * kp * g)
	var dump := g * (p_lin - pc)

	if dump < 0.0:
		# Zrzut zamkniety (P ponizej progu otwarcia) - krok jawny z odbiorem = tylko zewnetrzny.
		dump = 0.0
		_pressure += dt * kp * (steam_production - external_offtake)
	elif dump > dmax:
		# Zrzut nasycony (max przepustowosc) - krok jawny ze stalym odbiorem.
		dump = dmax
		_pressure += dt * kp * (steam_production - dmax - external_offtake)
	else:
		_pressure = p_lin

	_pressure = maxf(0.0, _pressure)
	_dump_flow = dump


## Temperatura nasycenia dla aktualnego cisnienia (linearyzacja). Wieksze P -> wyzsze T_sat.
func saturation_temp() -> float:
	return params.tsat_ref + params.dtsat_dp * (_pressure - params.tsat_ref_pressure)


## Utrata/przywrocenie odbioru pary (zrzut). false = odbiornik niedostepny -> cisnienie rosnie.
func set_dump_available(available: bool) -> void:
	_dump_available = available


func get_pressure() -> float:
	return _pressure

func get_dump_flow() -> float:
	return _dump_flow

func steam_quality() -> float:
	return params.steam_quality


# --- Poziom wody bebnow (ETAP 2E) - NOWY stan masowy, NIE wplywa na petle cisnienia ---

## Aktualizacja poziomu: doplyw wody zasilajacej - ubytek przez wrzenie (strumien pary).
func update_level(feedwater_in: float, steam_out: float, dt: float) -> void:
	_water_level += (feedwater_in - steam_out) / params.water_capacity * dt
	_water_level = maxf(0.0, _water_level)


func get_water_level() -> float:
	return _water_level


## Wspolczynnik chlodzenia rdzenia (sprzezenie wsteczne do ETAPU 1): osuszenie bebnow ->
## utrata wody krazacej -> spadek przeplywu chlodziwa. >= lowlow -> 1.0 (bez wplywu);
## miedzy lowlow a dryout maleje liniowo do cooling_min_factor.
func level_cooling_factor() -> float:
	if _water_level >= params.cooling_lowlow_level:
		return 1.0
	var span := params.cooling_lowlow_level - params.cooling_dryout_level
	var frac := (_water_level - params.cooling_dryout_level) / span
	return clampf(frac, params.cooling_min_factor, 1.0)
