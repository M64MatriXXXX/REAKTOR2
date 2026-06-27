class_name ThermalParams
extends Resource

## Konfigurowalne stale termohydrauliki (zestaw STARTOWY do strojenia).
##
## Model 2-wezlowy (lumped): paliwo -> chlodziwo, plus algebraiczna frakcja pustek.
## Jednostki SI. Wartosci dobrane tak, by w punkcie nominalnym (n=1, pelny przeplyw)
## ustalala sie rownowaga ZGODNA z punktami odniesienia ReactivityParams:
##   T_paliwa  -> fuel_temp_ref    (800 K)
##   T_chlodziwa -> coolant_temp_ref (550 K)
##   void      -> void_ref         (0)
## Dzieki temu start nominalny jest spojny z pozycja krytyczna pretow z ETAP 1B.
##
## To PUNKT WYJSCIA, nie wartosci sztywne - po spieciu calosci 1C nalezy je dostroic.

# --- Moc cieplna ---
# Nominalna moc cieplna rdzenia [W]. RBMK-1000 ~ 3200 MWth.
@export var nominal_thermal_power: float = 3.2e9      # W (3200 MWth)

# --- Wezel PALIWA ---
# Przewodnosc cieplna paliwo->chlodziwo UA [W/K] (efektywna, przez koszulke).
# Dobrana z rownowagi: P_nom = UA * (T_fuel_ref - T_cool_ref) = UA * 250 K.
@export var fuel_to_coolant_conductance: float = 1.28e7   # W/K  (= 3.2e9 / 250)
# Pojemnosc cieplna paliwa C_f [J/K]. Stala czasowa tau_f = C_f/UA ~ 5 s.
@export var fuel_heat_capacity: float = 6.4e7         # J/K  (tau_f = 5 s)

# --- Wezel CHLODZIWA ---
# Temperatura wlotowa chlodziwa do rdzenia [K] (~267 C).
@export var coolant_inlet_temp: float = 540.0         # K
# Strumien pojemnosci cieplnej chlodziwa (m_dot * c_p) przy PELNYM przeplywie [W/K].
# Dobrany z rownowagi: P_nom = W_flow * (T_cool_ref - T_inlet) = W_flow * 10 K.
@export var coolant_flow_heat_rate_nominal: float = 3.2e8  # W/K  (= 3.2e9 / 10)
# Pojemnosc cieplna wezla chlodziwa C_c [J/K]. Stala czasowa rzedu ~1 s.
@export var coolant_heat_capacity: float = 3.0e8      # J/K

# --- Wrzenie / frakcja pustek (model PROGOWY, pkt 1 planu) ---
# UPROSZCZENIE: zamiast korelacji dwufazowej - prog nasycenia + liniowy wzrost void.
# Ponizej T_sat void=0; powyzej rosnie liniowo z przegrzaniem, do void_fraction_max.
# T_sat dla cisnienia obiegu RBMK (~7 MPa) ~ 285 C ~ 558 K.
@export var saturation_temp: float = 558.0            # K
# Przyrost frakcji pustek na 1 K przegrzania ponad T_sat [1/K].
@export var void_gain_per_kelvin: float = 0.02        # 1/K (void=0.7 przy +35 K)
# Gorne ograniczenie frakcji pustek [-].
@export var void_fraction_max: float = 1.0


## Walidacja - wolana w _init ThermalModel.
func validate() -> void:
	assert(nominal_thermal_power > 0.0, "ThermalParams: nominal_thermal_power musi byc > 0")
	assert(fuel_to_coolant_conductance > 0.0, "ThermalParams: UA musi byc > 0")
	assert(fuel_heat_capacity > 0.0, "ThermalParams: fuel_heat_capacity musi byc > 0")
	assert(coolant_flow_heat_rate_nominal > 0.0,
		"ThermalParams: coolant_flow_heat_rate_nominal musi byc > 0")
	assert(coolant_heat_capacity > 0.0, "ThermalParams: coolant_heat_capacity musi byc > 0")
	assert(void_gain_per_kelvin >= 0.0, "ThermalParams: void_gain_per_kelvin musi byc >= 0")
	assert(void_fraction_max > 0.0, "ThermalParams: void_fraction_max musi byc > 0")
