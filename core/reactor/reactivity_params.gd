class_name ReactivityParams
extends Resource

## Konfigurowalne stale bilansu reaktywnosci (zestaw startowy RBMK-podobny).
##
## Konwencja: reaktywnosc rho bezwymiarowa [-]; 1 pcm = 1e-5 (per cent mille).
## Wartosci wewnetrznie w jednostkach bezwzglednych Δρ; w komentarzach podano pcm.
## To PUNKT WYJSCIA do strojenia balansu - NIE wartosci sztywno wpisane w logike.
## Po spieciu z termohydraulika (1C) nalezy je dostroic.

const PCM: float = 1.0e-5   # 1 pcm = 1e-5 Δρ (pomocniczo przy strojeniu)

# --- Prety regulacyjne (krzywa S) ---
# Calkowita wartosc pretow (pelne wsuniecie -> pelne wyciagniecie).
@export var total_rod_worth: float = 0.060        # 6000 pcm (~9.2 beta)
# Predkosc normalna pretow [1/s] (pelny przesuw ~100 s).
@export var rod_speed_normal: float = 0.01        # 1/s
# Predkosc przy SCRAM [1/s] (pelne wsuniecie ~3.3 s).
# UPROSZCZENIE: RBMK historycznie ~18-20 s dla pretow AZ; 2-4 s jest grywalniejsze.
@export var rod_speed_scram: float = 0.30         # 1/s

# --- Doppler (paliwo), forma rezonansowa √T, UJEMNY ---
# rho_doppler = doppler_coeff_sqrt * (sqrt(T_fuel) - sqrt(fuel_temp_ref))
# Dobrane tak, by lokalna pochodna w fuel_temp_ref dawala ~ -2.5 pcm/K:
#   doppler_coeff_sqrt = alpha_D_linear * 2 * sqrt(fuel_temp_ref)
#   = -2.5e-5 * 2 * sqrt(800) ≈ -1.414e-3
@export var doppler_coeff_sqrt: float = -1.414e-3 # Δρ/√K
@export var fuel_temp_ref: float = 800.0          # K (temp. paliwa przy mocy nominalnej)

# --- Wspolczynnik pustkowy (void), DODATNI - cecha RBMK ---
# rho_void = void_coeff * (void_fraction - void_ref)
# +4300 pcm na jednostke void_fraction -> ~+3000 pcm przez zakres operacyjny 0-0.7.
@export var void_coeff: float = 0.043             # 4300 pcm / (jedn. void)
@export var void_ref: float = 0.0

# --- Wspolczynnik temperaturowy chlodziwa (maly, konfigurowalny znak) ---
# rho_coolant = coolant_temp_coeff * (T_coolant - coolant_temp_ref)
@export var coolant_temp_coeff: float = 2.0e-5    # +2 pcm/K
@export var coolant_temp_ref: float = 550.0       # K (~280 °C)

# --- Nadwyzka reaktywnosci paliwa (excess) ---
# Staly dodatni bias, by krytycznosc wypadala przy CZESCIOWYM wsunieciu pretow
# (operator szuka pozycji krytycznej - bardziej realistyczne i grywalne).
@export var excess_reactivity: float = 0.005      # +500 pcm


## Walidacja - wolana w _init ReactivityModel.
func validate() -> void:
	assert(total_rod_worth > 0.0, "ReactivityParams: total_rod_worth musi byc > 0")
	assert(rod_speed_normal > 0.0, "ReactivityParams: rod_speed_normal musi byc > 0")
	assert(rod_speed_scram > 0.0, "ReactivityParams: rod_speed_scram musi byc > 0")
	assert(fuel_temp_ref > 0.0, "ReactivityParams: fuel_temp_ref musi byc > 0")
	assert(excess_reactivity < total_rod_worth,
		"ReactivityParams: excess musi byc < total_rod_worth (inaczej brak pozycji krytycznej)")
