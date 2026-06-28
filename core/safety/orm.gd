class_name ORM
extends RefCounted

## Operating Reactivity Margin (ORM) - ETAP 1E-3.
##
## Najwazniejszy, specyficzny dla RBMK parametr bezpieczenstwa i bezposrednia
## przyczyna Czarnobyla: zapas ujemnej reaktywnosci dostepny w pretach.
## Gdy zbyt wiele pretow wyciagnietych (niski ORM): (1) ROSNIE efektywny dodatni
## wspolczynnik pustkowy, (2) ROSNIE efekt dodatniego scramu - reaktor staje sie
## niestabilny, a SCRAM moze nie zdazyc.
##
## UPROSZCZENIE (kluczowe): model PUNKTOWY nie ma rozkladu PRZESTRZENNEGO pretow,
## od ktorego realny ORM zalezy. Tu ORM to skalarny proxy glebokosci banku pretow:
##   ORM_equiv = orm_rods_scale * rod_insertion
## (wiecej wsunietych pretow -> wiekszy zapas ujemnej reaktywnosci -> wyzszy ORM).

var params: SafetyParams


func _init(safety_params: SafetyParams) -> void:
	params = safety_params


## ORM jako rownowazna liczba w pelni wsunietych pretow [-].
func equivalent_rods(rod_insertion: float) -> float:
	return params.orm_rods_scale * clampf(rod_insertion, 0.0, 1.0)


## Deficyt ORM w [0,1]: 0 gdy ORM >= onset (norma), rosnie do 1 przy ORM=0.
## Wspolna miara dla amplifikacji void i skalowania efektu dodatniego scramu.
func deficit_factor(orm_equiv: float) -> float:
	return clampf((params.orm_onset_rods - orm_equiv) / params.orm_onset_rods, 0.0, 1.0)


## Mnoznik efektywnego wsp. pustkowego: 1.0 przy ORM >= onset, rosnie ponizej.
## To DODATNIA petla nalozona na petle pustkowa - odblokowuje niestabilnosc niskim ORM.
func void_coeff_multiplier(orm_equiv: float) -> float:
	return 1.0 + params.orm_void_gain * deficit_factor(orm_equiv)


## Czy ORM ponizej limitu bezpieczenstwa (trip/interlock; limit czarnobylski = 15).
func is_below_limit(orm_equiv: float) -> bool:
	return orm_equiv < params.orm_trip_equivalent_rods
