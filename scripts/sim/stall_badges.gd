class_name StallBadges
extends RefCounted
## 1.49: значки проблем над станками. Состояние считается не каждый кадр, а не чаще раза в REFRESH_S
## реальных секунд и только когда сдвинулись игровые минуты или станки. Причина должна продержаться
## HOLD_MIN игровых минут (станок между двумя деталями «ждёт заготовку» доли минуты — не проблема), иначе значок мигал бы.
## Значок «нет работы» (станок без заказа) — нейтральный, показывается только в слое «Загрузка станков».

const REFRESH_S := 0.5
const HOLD_MIN := 15.0
const KINDS := ["power", "operator", "input", "full", "idle"]

var shown: Dictionary = {}     ## id станка -> {"k": вид, "why": String, "hint": String, "lvl": int, "m": Thing}
var _since: Dictionary = {}    ## id станка -> [вид, минута, с которой держится причина]
var _last_min := -1e9
var _last_rev := -1
var _real := 0.0


## Кадровый вызов: delta — реальные секунды. true — набор значков изменился.
func tick(sim: Sim, delta: float) -> bool:
	_real -= delta
	if _real > 0.0:
		return false
	_real = REFRESH_S
	if sim.minute == _last_min and sim.thing_rev == _last_rev:
		return false
	return refresh(sim)


## Пересчёт сразу (для тестов и первого кадра). true — набор значков изменился.
func refresh(sim: Sim) -> bool:
	_last_min = sim.minute
	_last_rev = sim.thing_rev
	var old := _sig()
	var seen := {}
	for m in sim.things_of("machine"):
		if not m.built or m.demolish:
			continue
		var r := Stall.reason(sim, m)
		var k := str(r.get("k", ""))
		if k == "":
			continue
		seen[m.id] = true
		var cur: Array = _since.get(m.id, [])
		if cur.is_empty() or str(cur[0]) != k:
			cur = [k, sim.minute]
			_since[m.id] = cur
		if sim.minute - float(cur[1]) >= HOLD_MIN or k == "power" and sim.minute - float(cur[1]) >= 1.0:
			r["m"] = m
			shown[m.id] = r
		else:
			shown.erase(m.id)
	for id in _since.keys():
		if not seen.has(id):
			_since.erase(id)
			shown.erase(id)
	return _sig() != old


func _sig() -> String:
	var ids := shown.keys()
	ids.sort()
	var s := ""
	for id in ids:
		s += "%d%s," % [int(id), str((shown[id] as Dictionary)["k"])]
	return s


## Что показывать на карте: без нейтрального «нет работы», если слой «Загрузка станков» не включён.
func visible_list(with_idle: bool) -> Array:
	var out: Array = []
	for id in shown.keys():
		var r: Dictionary = shown[id]
		if str(r["k"]) == "idle" and not with_idle:
			continue
		out.append(r)
	return out


static func title(k: String) -> String:
	match k:
		"power":
			return L.t("Нет питания")
		"operator":
			return L.t("Нет оператора")
		"input":
			return L.t("Нет заготовки")
		"full":
			return L.t("Выход полон")
	return L.t("Нет работы")
