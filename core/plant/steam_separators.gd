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


func _init(separator_params: SeparatorParams) -> void:
	params = separator_params
	params.validate()
	# Start na nastawie -> brak transientu w nominale (produkcja=odbior).
	_pressure = params.pressure_setpoint


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
