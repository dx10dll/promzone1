class_name Faults
extends RefCounted
## 1.18: аварии на сетях — обрыв провода и прорыв водопровода. Клетка сети становится «чертежом»
## (сеть разорвана, дальше ток или вода не идут), рабочие чинят её как обычную прокладку.
## Аварийная бригада за деньги чинит сама — через час.

const LAYERS := {"cable": "Обрыв провода", "pipe": "Прорыв водопровода"}
const CREW_COST := {"cable": 9000.0, "pipe": 12000.0}

var sim: Sim
var list: Dictionary = {}   ## "слой:индекс клетки" -> {layer, i, at, fix_at}
var rev := 0


func _init(s: Sim) -> void:
	sim = s


static func key(layer: String, i: int) -> String:
	return "%s:%d" % [layer, i]


func at(layer: String, c: Vector2i) -> bool:
	return sim.world.inb(c) and list.has(key(layer, sim.world.idx(c)))


func count(layer: String = "") -> int:
	if layer == "":
		return list.size()
	var n := 0
	for f: Dictionary in list.values():
		if str(f["layer"]) == layer:
			n += 1
	return n


## Где может случиться авария: проложенная клетка на участке, по которой что-то питается
## (не тупиковый обрезок и не клетка внутри самой подстанции или насосной).
func spot(layer: String) -> Vector2i:
	var cand := candidates(layer)
	if cand.is_empty():
		return Vector2i(-1, -1)
	return cand[sim.rng.randi_range(0, cand.size() - 1)]


func candidates(layer: String) -> Array[Vector2i]:
	var w := sim.world
	var arr := w.net_layer(layer)
	var cand: Array[Vector2i] = []
	var hidden: Array[Vector2i] = []   # под стеной или станком — только если открытых клеток нет
	if arr.size() != w.w * w.h:
		return cand
	for i in arr.size():
		if arr[i] != 1:
			continue
		var c := w.cell_of(i)
		if not w.in_plot(c):
			continue
		var tid := w.occ[i]
		if tid >= 0:
			var t: Thing = sim.things.get(tid)
			if t and (str(t.def().get("power_source", "")) != "" or t.kind() == "pump" or t.kind() == "water_source"):
				continue
		var nb := 0
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if w.net_at(layer, c + d) == 1:
				nb += 1
		if nb >= 2:
			if w.wall[i] != World.W_NONE or w.occ[i] >= 0:
				hidden.append(c)
			else:
				cand.append(c)
	return cand if not cand.is_empty() else hidden


## Устроить аварию в клетке. Возвращает true, если получилось.
func make(layer: String, c: Vector2i) -> bool:
	var w := sim.world
	if not w.inb(c) or w.net_at(layer, c) != 1:
		return false
	var i := w.idx(c)
	w.net_set(layer, i, 2)
	list[key(layer, i)] = {"layer": layer, "i": i, "at": sim.minute, "fix_at": -1.0}
	rev += 1
	return true


## Вызвать аварийную бригаду: деньги сразу, починят через час.
func call_crew(layer: String, i: int) -> bool:
	var k := key(layer, i)
	if not list.has(k):
		return false
	var cost := float(CREW_COST.get(layer, 10000.0))
	sim.spend(cost, "Аварийная бригада: " + str(LAYERS.get(layer, "авария")).to_lower())
	list[k]["fix_at"] = sim.minute + 60.0
	return true


func tick() -> void:
	if list.is_empty():
		return
	for k in list.keys():
		var f: Dictionary = list[k]
		var layer := str(f["layer"])
		var i := int(f["i"])
		var arr := sim.world.net_layer(layer)
		if i >= arr.size() or arr[i] != 2:
			list.erase(k)   # починили (или убрали кабель совсем)
			rev += 1
			continue
		if float(f["fix_at"]) >= 0.0 and sim.minute >= float(f["fix_at"]):
			sim.complete_net(layer, i)
			list.erase(k)
			rev += 1
			sim.notify("Аварийная бригада закончила: %s устранён." % str(LAYERS.get(layer, "авария")).to_lower(), Sim.LVL_GOOD, sim.world.cell_of(i))


func to_dict() -> Dictionary:
	return {"list": list.values()}


func from_dict(d: Dictionary) -> void:
	list.clear()
	for f: Dictionary in d.get("list", []):
		var layer := str(f.get("layer", "cable"))
		var i := int(f.get("i", 0))
		list[key(layer, i)] = {"layer": layer, "i": i, "at": float(f.get("at", 0.0)), "fix_at": float(f.get("fix_at", -1.0))}
	rev += 1
