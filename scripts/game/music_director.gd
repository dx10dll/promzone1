class_name MusicDirector
extends RefCounted
## 1.28: подбирает музыку к времени суток и обстановке на заводе.
## 1.31: восемнадцать треков; у каждого настроения свой список, зимой — «Первый снег», в дождь — «Дождь над крышей цеха».
## Смена — плавная (Snd: два плеера, перекрёстное затухание); новое настроение вступает на границе музыкальной фразы.
## Один и тот же трек два раза подряд не играет.

const TITLES := {
	"music_menu": "«Проходная»", "music_morning": "«Первая смена»", "music_shop": "«Норма»",
	"music_march": "«Встречный план»", "music_evening": "«Пересменка»", "music_night": "«Ночная смена»",
	"music_calm": "«Тихий цех»", "music_waltz": "«Заводской вальс»",
	"music_estrada": "«Огни проспекта»", "music_accwaltz": "«Над заводской рекой»", "music_folk": "«Тропинка к проходной»",
	"music_foundry": "«Литейный цех»", "music_jazz": "«Буфет на втором этаже»", "music_march2": "«Ударная вахта»",
	"music_rain": "«Дождь над крышей цеха»", "music_radio": "«Ночной эфир»", "music_winter": "«Первый снег»",
	"music_dawn": "«Утренний автобус»",
}
const ALL := ["music_morning", "music_shop", "music_march", "music_evening", "music_night", "music_calm", "music_waltz",
	"music_estrada", "music_accwaltz", "music_folk", "music_foundry", "music_jazz", "music_march2", "music_rain",
	"music_radio", "music_winter", "music_dawn"]
const NEW_131 := ["music_estrada", "music_accwaltz", "music_folk", "music_foundry", "music_jazz", "music_march2",
	"music_rain", "music_radio", "music_winter", "music_dawn"]
const CLASSIC := ["music_calm", "music_waltz", "music_accwaltz"]
const MENU := ["music_menu", "music_accwaltz", "music_rain", "music_waltz"]
const MOODS := {
	"night": ["music_night", "music_radio", "music_calm"],
	"evening": ["music_evening", "music_accwaltz", "music_jazz", "music_waltz", "music_estrada"],
	"rush": ["music_march", "music_march2", "music_foundry", "music_shop"],
	"morning": ["music_morning", "music_folk", "music_dawn", "music_shop"],
	"day": ["music_shop", "music_estrada", "music_jazz", "music_foundry", "music_dawn", "music_calm", "music_folk"],
}
## Длина музыкальной фразы (4 такта), с — на её границе удобно сменить трек.
const PHRASE := {
	"music_menu": 12.63, "music_morning": 10.0, "music_shop": 8.89, "music_march": 8.28, "music_evening": 8.57,
	"music_night": 14.55, "music_calm": 8.0, "music_waltz": 8.0,
	"music_estrada": 8.57, "music_accwaltz": 8.18, "music_folk": 7.74, "music_foundry": 10.0, "music_jazz": 7.27,
	"music_march2": 7.74, "music_rain": 14.55, "music_radio": 16.0, "music_winter": 11.71, "music_dawn": 9.23,
}
## Треки 1.28 и старше — петли, обрываются на последнем такте: их перекрываем долгой сменой.
## Новые (1.31) кончаются сами — каденцией и затуханием; после них иногда бывает короткая тишина.
const LOOPED := ["music_menu", "music_morning", "music_shop", "music_march", "music_evening", "music_night", "music_calm", "music_waltz"]
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


static func is_winter(sim: Sim) -> bool:
	return sim.season != null and sim.season.season_id() == "winter"


static func is_rain(sim: Sim) -> bool:
	return sim.season != null and sim.season.is_raining()


## Список треков по режиму из настроек: 0 — по обстановке, 1 — всё подряд, 2 — только вальсы.
## Первый в списке — «лицо» настроения: он вступает первым, когда настроение сменилось.
static func playlist(sim: Sim, mode: int) -> Array:
	if mode == 1:
		return ALL
	if mode == 2:
		return CLASSIC
	return for_mood(mood(sim), is_winter(sim), is_rain(sim))


static func for_mood(m: String, winter: bool, rain: bool) -> Array:
	var pl: Array = (MOODS.get(m, MOODS["day"]) as Array).duplicate()
	if m == "rush":
		return pl
	if rain:
		pl.insert(0, "music_rain")
	elif winter and m != "night":
		pl.insert(0, "music_winter")
	return pl


static func phrase(name: String) -> float:
	return float(PHRASE.get(name, 8.0))


## За сколько секунд до конца трека начинать смену на следующий.
static func overlap(name: String) -> float:
	return MusicFade.XFADE if LOOPED.has(name) else 2.5


static func soft_end(name: String) -> bool:
	return not LOOPED.has(name)


## Следующий трек: случайный из списка, но не из двух последних сыгранных (если есть из чего выбрать).
## r — случайное число 0..1 (передаётся снаружи, чтобы тест мог проверить выбор).
static func pick_next(list: Array, history: Array, r: float) -> String:
	if list.is_empty():
		return ""
	if list.size() == 1:
		return str(list[0])
	var avoid := mini(2, list.size() - 1)
	var recent := history.slice(maxi(0, history.size() - avoid))
	var cands: Array = []
	for n: Variant in list:
		if not recent.has(n):
			cands.append(n)
	if cands.is_empty():
		for n2: Variant in list:
			if history.is_empty() or n2 != history.back():
				cands.append(n2)
	return str(cands[clampi(int(r * cands.size()), 0, cands.size() - 1)])


## Первый трек нового списка: его «лицо», если оно не звучало только что, иначе — случайный.
static func first_of(list: Array, history: Array, r: float) -> String:
	if list.is_empty():
		return ""
	var head := str(list[0])
	var recent := history.slice(maxi(0, history.size() - 2))
	if list.size() == 1 or not recent.has(head):
		return head
	return pick_next(list, history, r)
