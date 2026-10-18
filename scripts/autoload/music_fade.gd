class_name MusicFade
extends RefCounted
## 1.31: перекрёстная смена двух треков равной мощности (sin/cos) и выбор «музыкального» момента.
## Математика отдельно от плееров — её проверяет тест stage131.

const XFADE := 7.0        ## обычная смена трека, с
const XFADE_MENU := 3.5   ## меню ↔ игра
const FADE_IN := 1.5      ## вступление после тишины
const MAX_WAIT := 17.0    ## дольше конца фразы не ждём

var dur := XFADE
var t := XFADE
var active := false


func start(seconds: float) -> void:
	dur = maxf(0.05, seconds)
	t = 0.0
	active = true


func step(delta: float) -> void:
	if not active:
		return
	t += delta
	if t >= dur:
		t = dur
		active = false


func progress() -> float:
	return clampf(t / dur, 0.0, 1.0)


## Громкость входящего трека: sin — вместе с cos уходящего сумма мощностей всегда 1, «провала» в середине нет.
static func gain_in(p: float) -> float:
	return sin(clampf(p, 0.0, 1.0) * PI * 0.5)


static func gain_out(p: float) -> float:
	return cos(clampf(p, 0.0, 1.0) * PI * 0.5)


## Ближайшая граница фразы (phrase секунд от начала трека) не раньше pos + lead; если ждать дольше max_wait — сразу.
static func next_boundary(pos: float, phrase: float, lead: float = 0.4, max_wait: float = MAX_WAIT) -> float:
	if phrase <= 0.0:
		return pos + lead
	var b := ceilf((pos + lead) / phrase) * phrase
	if b - pos > max_wait:
		return pos + lead
	return b
