class_name ReactorParams
extends Resource

## Konfigurowalne stale fizyczne rdzenia (strojenie balansu gry).
##
## Wartosci domyslne: standardowy 6-grupowy zestaw danych opoznionych neutronow
## dla rozszczepienia termicznego U-235 (typ. dane podrecznikowe / Keepin).
## Jednostki SI. Zmieniaj tu, aby stroic dynamike bez dotykania logiki.
##
## Definicje:
##   beta_i  - udzial opoznionych neutronow grupy i [-]
##   lambda_i- stala rozpadu prekursorow grupy i [1/s]
##   beta    - calkowity udzial opoznionych neutronow = sum(beta_i) [-]
##   gen_time- czas generacji neutronow natychmiastowych Lambda [s]

# Stale rozpadu prekursorow lambda_i [1/s] - od najwolniejszej do najszybszej grupy.
@export var lambda: PackedFloat64Array = PackedFloat64Array([
	0.0124, 0.0305, 0.111, 0.301, 1.13, 3.01,
])

# Udzialy opoznionych neutronow beta_i [-]. Suma ~= 0.0065 (U-235).
@export var beta_groups: PackedFloat64Array = PackedFloat64Array([
	0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273,
])

# Czas generacji neutronow natychmiastowych Lambda [s].
# UPROSZCZENIE: pojedyncza, stala wartosc (~1e-4 s) zamiast zaleznej od stanu rdzenia.
# Uzasadnienie: w punktowej kinetyce Lambda traktujemy jako parametr; zaleznosc od
# wypalenia/temperatury jest drugorzedna dla grywalnosci i bedzie ewentualnie dostrojona.
@export var gen_time: float = 1.0e-4


## Calkowity udzial opoznionych neutronow beta = sum(beta_i).
func total_beta() -> float:
	var sum := 0.0
	for b in beta_groups:
		sum += b
	return sum


## Liczba grup opoznionych neutronow (spojnosc tablic).
func group_count() -> int:
	return beta_groups.size()


## Walidacja konfiguracji - wolana w _init Neutronics dla wczesnego wykrycia bledow.
func validate() -> void:
	assert(lambda.size() == beta_groups.size(),
		"ReactorParams: lambda i beta_groups musza miec ta sama dlugosc")
	assert(gen_time > 0.0, "ReactorParams: gen_time (Lambda) musi byc > 0")
	for l in lambda:
		assert(l > 0.0, "ReactorParams: kazda lambda_i musi byc > 0")
