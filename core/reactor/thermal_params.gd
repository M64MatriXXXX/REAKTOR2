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

# --- Cieplo powylaczeniowe (decay heat) - ETAP 1E-2 ---
# Moc cieplna rdzenia dzieli sie na czesc PROMPT (deponowana natychmiast z rozszczepien)
# i czesc DECAY (rozpad produktow rozszczepienia, trwa PO wylaczeniu reakcji lancuchowej).
# Przy n=1 w rownowadze: prompt + sum(decay) = 1.0 (kalibracja 800/550 zachowana).
# Ulamek mocy z rozpadu (decay) w rownowadze ~ 6.6% (RBMK/typowy LWR).
@export var prompt_heat_fraction: float = 0.934      # 1 - sum(decay_equilibrium_fraction)

# Model rezerwuarowy (kilka grup) jako fit przyblizenia Way-Wigner ~0.066*t^-0.2.
# UPROSZCZENIE: 3 grupy zamiast pelnego widma ~23 grup ANS; dobrane, by oddac
# przebieg od sekund do godzin (istotny dla mechaniki chlodzenia po SCRAM).
# dE_i/dt = (f_i)*n - lambda_i*E_i ; w rownowadze E_i = decay_equilibrium_fraction_i * n.
@export var decay_lambda: PackedFloat64Array = PackedFloat64Array([
	0.5, 0.01, 0.0001,   # [1/s]: szybka (~2s), srednia (~100s), wolna (~2.8h)
])
@export var decay_equilibrium_fraction: PackedFloat64Array = PackedFloat64Array([
	0.020, 0.025, 0.021,   # [-] wklad grupy do mocy przy n=1 (suma = 0.066)
])


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
	assert(decay_lambda.size() == decay_equilibrium_fraction.size(),
		"ThermalParams: decay_lambda i decay_equilibrium_fraction musza miec ta sama dlugosc")
	for l in decay_lambda:
		assert(l > 0.0, "ThermalParams: kazda decay_lambda musi byc > 0")
	var decay_sum := 0.0
	for f in decay_equilibrium_fraction:
		assert(f >= 0.0, "ThermalParams: decay_equilibrium_fraction musi byc >= 0")
		decay_sum += f
	assert(absf(prompt_heat_fraction + decay_sum - 1.0) < 1.0e-6,
		"ThermalParams: prompt_heat_fraction + sum(decay) musi = 1.0 (kalibracja mocy)")
