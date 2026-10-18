class_name MusicDirector
extends RefCounted
## 1.28: подбирает музыку к времени суток и обстановке на заводе.
## Утро — «Первая смена», день — «Норма», аврал — «Встречный план», вечер — «Пересменка», ночь — «Ночная смена».
## Трек не обрывается: новый список вступает, когда доиграет текущий.

const TITLES := {
	"music_menu": "«Проходная»", "music_morning": "«Первая смена»", "music_shop": "«Норма»",
	"music_march": "«Встречный план»", "music_evening": "«Пересменка»", "music_night": "«Ночная смена»",
	"music_calm": "«Тихий цех»", "music_waltz": "«Заводской вальс»",
}
const ALL := ["music_morning", "music_shop", "music_march", "music_evening", "music_night", "music_calm", "music_waltz"]
const CLASSIC := ["music_calm", "music_waltz"]
const RUSH_HOURS := 30.0   ## заказ со сроком ближе этого (игровых часов) и не готов — аврал


## Настроение сейчас: morning | day | rush | evening | night.
static func mood(sim: Sim) -> String:
	var h := sim.hour()
	if h >= 22 or h < 6:
		return "night"
	if h >= 18:
		return "evening"
	if _rush(sim):
		return "rush"
	if h < 10:
		return "morning"
	return "day"


static func _rush(sim: Sim) -> bool:
	for o: Dictionary in sim.orders.list:
		if str(o.get("status", "")) != "active":
			continue
		var left := float(o.get("deadline", 1e12)) - sim.minute
		if left > 0.0 and left < RUSH_HOURS * 60.0:
			return true
	return false


## Список треков по режиму из настроек: 0 — по времени суток, 1 — всё подряд, 2 — старые два вальса.
static func playlist(sim: Sim, mode: int) -> Array:
	if mode == 1:
		return ALL
	if mode == 2:
		return CLASSIC
	match mood(sim):
		"night":
			return ["music_night", "music_calm"]
		"evening":
			return ["music_evening", "music_waltz"]
		"rush":
			return ["music_march", "music_shop"]
		"morning":
			return ["music_morning", "music_shop"]
	return ["music_shop", "music_calm", "music_march"]
