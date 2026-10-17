class_name Water
extends RefCounted
## Водопровод: трубы (world.pipe) от насосов к туалетам, раковинам и испытательному стенду.
## Сеть — связная группа клеток с трубой. Прибор с водой, если труба заведена в его клетку
## подключения (1.18 — не в соседнюю), а в этой же сети есть насос.
## 1.15: городского водопровода нет — скважинный насос сам даёт воду на 10 приборов,
## насосная станция (под током, в техпомещении) — на 24.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var sim: Sim
var net_of := PackedInt32Array()
var net_src: Array[bool] = []      ## есть ли в сети работающий насос
var thing_net: Dictionary = {}     ## id прибора -> индекс сети
var low: Dictionary = {}           ## 1.13: id прибора -> true — не хватило напора
var net_cap: Array[int] = []       ## сколько приборов тянет сеть (все насосы в ней)
var net_fix: Array[int] = []       ## сколько приборов в сети
var bonus := 0                     ## старые сохранения: запас напора, чтобы завод не встал
var rev := 0                       ## 1.18: растёт при каждом пересчёте (помещения следят за водой)
const CITY_FIXTURES := 10          ## до 1.20: сколько приборов тянул скважинный насос
const UNLIMITED := 100000          ## 1.20: насос даёт воду всем приборам сети
var _sig := ""
var _res_sig := 0


func _init(s: Sim) -> void:
	sim = s


func _net_at(c: Vector2i) -> int:
	var w := sim.world
	if not w.inb(c) or net_of.size() != w.w * w.h:
		return -1
	return net_of[w.idx(c)]


## 1.18: труба должна заходить в клетку прибора (у насоса — в любую его клетку).
func _touch(t: Thing) -> Array[Vector2i]:
	if t.kind() == "water_source" or t.kind() == "pump":
		return t.cells()
	var arr: Array[Vector2i] = [t.inlet_cell()]
	return arr


## Насосные станции, которые сейчас качают (для подписи пересчёта).
func _pumps_sig() -> String:
	var out := ""
	for t: Thing in sim.things.values():
		if t.kind() == "pump":
			out += "%d%s," % [t.id, "1" if pump_running(t) else "0"]
	return out


func pump_running(t: Thing) -> bool:
	return t.built and t.enabled and not t.demolish and sim.power.powered(t) and sim.rooms.zone_ok(t)


func update() -> void:
	var sig := "%d|%d|%d|%s" % [sim.world.pipe_rev, sim.thing_rev, sim.rooms.rev, _pumps_sig()]
	if sig == _sig:
		return
	_sig = sig
	var w := sim.world
	var n := w.w * w.h
	net_of.resize(n)
	net_of.fill(-1)
	net_src.clear()
	thing_net.clear()
	var nid := 0
	for i in n:
		if w.pipe[i] != 1 or net_of[i] >= 0:
			continue
		var queue: Array[Vector2i] = [w.cell_of(i)]
		net_of[i] = nid
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d: Vector2i in DIRS:
				var nb := c + d
				if not w.inb(nb):
					continue
				var ni := w.idx(nb)
				if w.pipe[ni] == 1 and net_of[ni] < 0:
					net_of[ni] = nid
					queue.append(nb)
		net_src.append(false)
		nid += 1
	for t: Thing in sim.things.values():
		if not t.built or (t.kind() != "water_source" and not t.needs_water()):
			continue
		for c2 in _touch(t):
			var k := _net_at(c2)
			if k >= 0:
				thing_net[t.id] = k
				if t.kind() == "water_source":
					net_src[k] = true
				break
	for tp: Thing in sim.things.values():
		if tp.kind() == "pump" and pump_running(tp):
			for c4 in _touch(tp):
				var kp := _net_at(c4)
				if kp >= 0:
					thing_net[tp.id] = kp
					net_src[kp] = true
					break
	# напор: скважинный насос тянет 10 приборов, каждая работающая насосная станция — 24.
	# Кому не хватило — самые дальние от насосов: вода есть, но «чуть капает».
	low.clear()
	net_cap.clear()
	net_fix.clear()
	var fixtures: Array = []
	for k2 in nid:
		net_cap.append(bonus if net_src[k2] else 0)
		net_fix.append(0)
		fixtures.append([])
	var srcs: Array[Thing] = []
	for t2: Thing in sim.things.values():
		if not thing_net.has(t2.id):
			continue
		var k3 := int(thing_net[t2.id])
		if t2.kind() == "water_source":
			srcs.append(t2)
			net_cap[k3] += UNLIMITED   # 1.20: без ограничения приборов
		elif t2.kind() == "pump":
			if pump_running(t2):
				srcs.append(t2)
				net_cap[k3] += UNLIMITED
		else:
			net_fix[k3] += 1
			(fixtures[k3] as Array).append(t2)
	for k4 in nid:
		var fx: Array = fixtures[k4]
		if fx.size() <= net_cap[k4]:
			continue
		var dist := func(t3: Thing) -> float:
			var best := INF
			for sc: Thing in srcs:
				if int(thing_net.get(sc.id, -1)) == k4:
					best = minf(best, Vector2(t3.cell - sc.cell).length())
			return best
		fx.sort_custom(func(a: Thing, b: Thing) -> bool: return dist.call(a) < dist.call(b))
		for j in range(net_cap[k4], fx.size()):
			low[(fx[j] as Thing).id] = true
	# 1.18: помещения пересчитываются, только если у кого-то вода появилась или пропала
	var wet := PackedInt32Array()
	for tid in thing_net.keys():
		var k5 := int(thing_net[tid])
		if k5 < net_src.size() and net_src[k5] and not low.has(tid):
			wet.append(int(tid))
	wet.sort()
	var rs := hash(wet)
	if rs != _res_sig:
		_res_sig = rs
		rev += 1


## Есть ли вода у прибора (туалет, раковина, стенд). Приборы без водопровода в определении — всегда да.
func has_water(t: Thing) -> bool:
	if not t.needs_water():
		return true
	update()
	var k := int(thing_net.get(t.id, -1))
	return k >= 0 and k < net_src.size() and net_src[k] and not low.has(t.id)


## Прибор подключён, но воды не хватает — нужен насос.
func weak(t: Thing) -> bool:
	update()
	return low.has(t.id)


func connected(t: Thing) -> bool:
	update()
	return thing_net.has(t.id)


func has_source() -> bool:
	return not sim.things_of("water_source").is_empty() or not sim.things_of("pump").is_empty()
