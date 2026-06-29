class_name FeedwaterParams
extends Resource

## Konfigurowalne stale ukladu wody zasilajacej (ETAP 2E).
##
## Deaerator (zbiornik buforowy) + pompy kondensatu (hotwell->deaerator) + pompy zasilajace
## (deaerator->separator) + regulacja poziomu separatora. Jednostki znormalizowane: przeplyw
## 1.0 = nominalny strumien pary/wody przy pelnej mocy; masa/poziom 1.0 = nominalny zapas.
##
## DOMKNIECIE PETLI MASY: woda krazy hotwell -> deaerator -> separator -> (wrzenie) ->
## skraplacz -> hotwell. Jedynym kanalem UBYTKU jest BRU-A (zrzut do atmosfery).

# --- Deaerator (zbiornik) ---
@export var deaerator_setpoint: float = 1.0      # nominalny zapas wody w deaeratorze
# Pojemnosc [s nominalnego przeplywu na jednostke poziomu]: DUZA = wolna, bezwladna dynamika
# poziomu (duzy zapas wody). Wspolna skala z separatorem/hotwellem.
@export var deaerator_capacity: float = 40.0
@export var deaerator_min_suction: float = 0.05  # ponizej - pompy zasilajace traca ssanie

# --- Pompy zasilajace (deaerator -> separator) ---
@export var feed_pump_max: float = 2.0           # maks. przepustowosc [-]
@export var feed_pump_time_s: float = 3.0        # bezwladnosc (filtr 1. rzedu)

# --- Pompy kondensatu (hotwell -> deaerator) ---
@export var cond_pump_max: float = 2.0
@export var cond_pump_time_s: float = 3.0
@export var hotwell_min_suction: float = 0.05    # ponizej - pompy kondensatu traca ssanie

# --- Regulacja poziomu (sterowanie 1-elementowe: feedforward + trim bledu poziomu) ---
# Przeplyw = strumien_pary (feedforward) + level_gain*(nastawa - poziom). Feedforward trzyma
# poziom dokladnie w stanie ustalonym; trim koryguje odchylke.
@export var level_gain: float = 1.0


func validate() -> void:
	assert(deaerator_setpoint > 0.0, "FeedwaterParams: deaerator_setpoint musi byc > 0")
	assert(deaerator_capacity > 0.0, "FeedwaterParams: deaerator_capacity musi byc > 0")
	assert(feed_pump_max > 0.0, "FeedwaterParams: feed_pump_max musi byc > 0")
	assert(feed_pump_time_s > 0.0, "FeedwaterParams: feed_pump_time_s musi byc > 0")
	assert(cond_pump_max > 0.0, "FeedwaterParams: cond_pump_max musi byc > 0")
	assert(cond_pump_time_s > 0.0, "FeedwaterParams: cond_pump_time_s musi byc > 0")
	assert(level_gain >= 0.0, "FeedwaterParams: level_gain musi byc >= 0")
