class_name ReactivityInputs
extends RefCounted

## Typowany kontener wejsc do ReactivityModel (czytelnosc + determinizm).
## Wszystkie pola w jednostkach SI / bezwymiarowych.

var rod_insertion: float = 0.0       # [-] zaglebienie pretow 0..1 (1 = wsuniete)
var fuel_temp: float = 0.0           # [K] temperatura paliwa
var coolant_temp: float = 0.0        # [K] temperatura chlodziwa
var void_fraction: float = 0.0       # [-] frakcja pustek 0..1
var xenon_reactivity: float = 0.0    # [-] wklad ksenonu (z modulu xenon, 1D)
var external_reactivity: float = 0.0 # [-] bias zewnetrzny (scenariusze/testy)


## Tworzy wejscia w punkcie ODNIESIENIA (sprzezenia = 0): temperatury i pustki
## rowne wartosciom referencyjnym, prety wyciagniete. Punkt startowy do strojenia.
static func at_reference(params: ReactivityParams, rod_insertion: float = 0.0) -> ReactivityInputs:
	var inp := ReactivityInputs.new()
	inp.rod_insertion = rod_insertion
	inp.fuel_temp = params.fuel_temp_ref
	inp.coolant_temp = params.coolant_temp_ref
	inp.void_fraction = params.void_ref
	return inp
