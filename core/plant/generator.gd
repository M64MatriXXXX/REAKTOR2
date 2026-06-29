class_name Generator
extends RefCounted

## Generator (ETAP 2C) - strona elektryczna + BRAMKA SYNCHRONIZACJI.
##
## Moc elektryczna [MWe] = moc mechaniczna turbiny * nominal (gdy pod siecia).
##
## SYNCHRONIZACJA - wersja MINIMALNA (bramka): zalaczenie do sieci wolno wykonac tylko,
## gdy obroty turbiny mieszcza sie w oknie synchronicznym; zalaczenie POZA oknem =
## uszkodzenie generatora. Zaprojektowane tak, by pelna maszyna stanow turbiny w 2F
## mogla je OBUDOWAC (dodac etapy obracarka/rozbieg/sync), nie zastapic - analogicznie
## do regulatora zrzutu BRU w 2B. Tu zyje sam WARUNEK dopuszczalnosci zalaczenia.

var params: TurbineParams


func _init(turbine_params: TurbineParams) -> void:
	params = turbine_params


## Moc elektryczna [MWe]. Gdy pod siecia: moc mechaniczna turbiny * nominal; inaczej 0.
func electrical_output_mw(connected: bool, mechanical_power: float) -> float:
	if not connected:
		return 0.0
	return mechanical_power * params.nominal_electrical_mw


## Bramka synchronizacji: czy wolno zalaczyc do sieci przy danych obrotach turbiny.
## Spelniona tylko w oknie +/- sync_tolerance wokol obrotow synchronicznych (1.0).
func can_synchronize(turbine_speed: float) -> bool:
	return absf(turbine_speed - 1.0) <= params.sync_tolerance
