class_name XenonParams
extends Resource

## Konfigurowalne stale zatrucia ksenonowego Xe-135 / I-135 (ETAP 1D).
##
## Lancuch: rozszczepienia -> I-135 -(rozpad)-> Xe-135; Xe usuwany przez rozpad I WYPALANIE
## neutronowe (duzy przekroj absorpcji). Po wylaczeniu wypalanie znika, a I dalej rozpada sie
## w Xe -> Xe ROSNIE (jama ksenonowa, szczyt ~9-11 h), potem zanika ~1-2 doby.
##
## Stezenia BEZWYMIAROWE (Sigma_f * flux_nominal ≡ 1). Stale rozpadu realne (SI, 1/s).
##
## JAWNE POKRETLA STROJENIA (nie efekt uboczny stalych mikroskopowych - by globalne strojenie
## sterowalo nimi wprost):
##   - equilibrium_worth_nominal : reaktywnosc rownowagi przy mocy nominalnej [Δρ] (skala worth),
##   - burnup_rate_nominal       : tempo wypalania przy nominale -> GLEBOKOSC JAMY (wyzsze=glebsza).

# --- Stale mikroskopowe (realne, konfigurowalne) ---
@export var lambda_i: float = 2.9306e-5    # rozpad I-135 [1/s] (T½ ~ 6.57 h)
@export var lambda_xe: float = 2.1066e-5   # rozpad Xe-135 [1/s] (T½ ~ 9.14 h)
@export var gamma_i: float = 0.06386       # wydajnosc rozszczepieniowa I-135 [-]
@export var gamma_xe: float = 0.00228      # bezposrednia wydajnosc Xe-135 [-]

# --- POKRETLO GLEBOKOSCI JAMY ---
# Wypalanie Xe przy nominalnym strumieniu: sigma_Xe * flux_nominal [1/s]. Wyzsze -> mocniej
# stlumione Xe przy mocy -> po wylaczeniu wiekszy skok z rezerwuaru I -> GLEBSZA i POZNIEJSZA jama.
# Domyslne 9e-5 -> szczyt ~8.7 h, ~-5500 pcm. Czas szczytu asymptotuje do ln(lambda_i/lambda_xe)/
# (lambda_i-lambda_xe) ~ 11.1 h (klasyczne okno; wynika wprost ze stalych rozpadu).
@export var burnup_rate_nominal: float = 9.0e-5

# --- POKRETLO WORTH ---
# Reaktywnosc rownowagi Xe przy mocy nominalnej [Δρ] (UJEMNA - absorber). Reaktywnosc liczona
# jako equilibrium_worth_nominal * (Xe / Xe_rownowagi_nominalnej) -> przy nominale = ta wartosc
# DOKLADNIE, a jama skaluje sie stosunkiem Xe/Xe_eq (sterowanym przez burnup_rate_nominal).
@export var equilibrium_worth_nominal: float = -0.027   # ~ -2700 pcm


func validate() -> void:
	assert(lambda_i > 0.0, "XenonParams: lambda_i musi byc > 0")
	assert(lambda_xe > 0.0, "XenonParams: lambda_xe musi byc > 0")
	assert(gamma_i >= 0.0 and gamma_xe >= 0.0, "XenonParams: wydajnosci >= 0")
	assert(burnup_rate_nominal >= 0.0, "XenonParams: burnup_rate_nominal musi byc >= 0")
	assert(equilibrium_worth_nominal <= 0.0,
		"XenonParams: worth ksenonu musi byc <= 0 (absorber)")
