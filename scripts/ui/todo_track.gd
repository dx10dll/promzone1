class_name TodoTrack
extends RefCounted
## 1.49: «Что делать» — выполненный совет не пропадает мгновенно, а ~3 секунды реального времени
## висит зачёркнутым с галочкой и только потом уходит. Следим только за строками-проблемами
## (письма, тревоги, долги, проверки, советы…) — у счётчиков (заказы, цели) причины «устранить» нет.

const GHOST_S := 3.0
const KEYED := ["letter", "fire", "strike", "wrench", "money", "bolt_off", "inspect", "engineer", "office", "plan"]
const BY_TEXT := ["letter", "engineer", "office"]   ## у этих значок общий, а советов бывает несколько — различаем по тексту

var _prev: Array = []     ## [{"key": String, "item": Array}] — строки прошлого пересчёта
var ghosts: Array = []    ## [{"key", "item", "left", "idx"}]


## Ключ строки или "" — если это не «проблема», а счётчик/подпункт.
static func key_of(it: Array) -> String:
	var ic := str(it[0])
	if not KEYED.has(ic):
		return ""
	if ic == "letter" and str(it[2]) == "":
		return ""   # «Ещё писем: N» — счётчик
	return ic + ("|" + str(it[1]) if BY_TEXT.has(ic) else "")


## Новый пересчёт списка: то, что было и пропало, уходит в «выполнено».
func update(items: Array) -> void:
	var cur := {}
	var now: Array = []
	for i in items.size():
		var k := key_of(items[i])
		if k == "":
			continue
		cur[k] = true
		now.append({"key": k, "item": items[i]})
	for p: Dictionary in _prev:
		if not cur.has(str(p["key"])) and not _has_ghost(str(p["key"])):
			ghosts.append({"key": p["key"], "item": p["item"], "left": GHOST_S, "idx": int(p.get("idx", 0))})
	ghosts = ghosts.filter(func(g: Dictionary) -> bool: return not cur.has(str(g["key"])))
	for i in items.size():
		var k2 := key_of(items[i])
		if k2 != "":
			for n: Dictionary in now:
				if n["key"] == k2:
					n["idx"] = i
	_prev = now


func _has_ghost(k: String) -> bool:
	return ghosts.any(func(g: Dictionary) -> bool: return str(g["key"]) == k)


## Время реальное. true — какая-то строка только что ушла насовсем.
func tick(delta: float) -> bool:
	var gone := false
	for g: Dictionary in ghosts:
		g["left"] = float(g["left"]) - delta
	var n := ghosts.size()
	ghosts = ghosts.filter(func(g: Dictionary) -> bool: return float(g["left"]) > 0.0)
	gone = ghosts.size() != n
	return gone


## Список для показа: живые строки и на их местах — выполненные («✓», зачёркнуто).
func merged(items: Array) -> Array:
	var out := items.duplicate()
	for g: Dictionary in ghosts:
		var src: Array = g["item"]
		var gi: Array = [src[0], src[1], "", UITheme.MUTED, func() -> void: pass, "ghost"]
		out.insert(mini(int(g["idx"]), out.size()), gi)
	return out
