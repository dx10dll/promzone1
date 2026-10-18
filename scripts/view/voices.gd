class_name Voices
## 1.29: голоса людей — какие реплики «бубнежа» звучат у человека, его тон и громкость.
## Без обращений к автозагрузкам, чтобы проверять в тестах; сами плееры — в SoundLayer.

const ZOOM := 1.0              ## голоса слышно только с такого приближения камеры
const BUBBLES := ["talk", "chat", "argue", "fight", "laugh"]
const TALK_M := ["v_talk_m1", "v_talk_m2", "v_talk_m3", "v_talk_m4"]
const TALK_F := ["v_talk_f1", "v_talk_f2", "v_talk_f3", "v_talk_f4"]
const OLD_M := ["v_talk_mo1"]
const OLD_F := ["v_talk_fo1"]
const ARGUE_M := ["v_argue_m1", "v_argue_m2"]
const ARGUE_F := ["v_argue_f1"]
const LAUGH_M := ["v_laugh_m1"]
const LAUGH_F := ["v_laugh_f1"]
const CROWD := "v_crowd"
const ALL := [TALK_M, TALK_F, OLD_M, OLD_F, ARGUE_M, ARGUE_F, LAUGH_M, LAUGH_F]


## Человек сейчас разговаривает (значок беседы над головой и уже стоит на месте).
static func is_talking(w: Worker) -> bool:
	if not w.present or not (w.bubble in BUBBLES):
		return false
	if w.task and w.task.kind in ["social", "brief"]:
		return str(w.task.current().get("t", "")) == "work"
	return true


## Набор реплик для человека: по полу, возрасту и настроению беседы.
static func pool(w: Worker) -> Array:
	var fem := w.female
	match w.bubble:
		"argue", "fight":
			return ARGUE_F if fem else ARGUE_M
		"laugh":
			return LAUGH_F if fem else LAUGH_M
	if w.age >= 52:
		return OLD_F if fem else OLD_M
	return TALK_F if fem else TALK_M


## Свой голос у каждого: постоянная высота тона по номеру человека.
static func pitch(w: Worker) -> float:
	return 0.9 + 0.2 * fposmod(float(w.id) * 0.6180339, 1.0)


## Громкость голоса: тем громче, чем сильнее приближение и ближе к середине экрана.
static func db(z: float, dist_k: float, loud: bool) -> float:
	var vk := clampf((z - ZOOM) / 1.2, 0.0, 1.0)
	return lerpf(-17.0, -5.0, vk) - 9.0 * clampf(dist_k, 0.0, 1.0) + (2.5 if loud else 0.0)
