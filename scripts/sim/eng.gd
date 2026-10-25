class_name Eng
extends RefCounted
## Инженерные сети (1.6): вентиляция (воздуховоды, вытяжные вентиляторы и зонты, загазованность
## помещений), сжатый воздух (компрессор, пневмомагистраль, пневмоинструмент), своя котельная,
## спецоценка условий труда (СОУТ) с доплатами и молоком за вредность, средства индивидуальной защиты.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Выбросы работающего станка: «единиц загазованности в час» для помещения в 30 клеток.
const FUMES := {"welding": 40.0, "paint": 34.0, "heat": 14.0, "casting": 36.0, "milling": 3.0, "turning": 2.0, "drilling": 1.5, "assembly": 0.6}
const STUFFY := 35.0             ## душно
const SMOKY := 65.0              ## дым и пары: тяжело работать
const HOOD_K := 0.25             ## под вытяжным зонтом в помещение уходит четверть выбросов
const VENT_K := 1.1              ## доля воздуха в час, которую уносит вентиляция при кратности 1
const LOCAL := 25.0              ## дым у самого сварочного поста или камеры без зонта (для СОУТ)
const PPE_WEAR := 5.0            ## износ комплекта СИЗ за смену, %
const MILK_COST := 70.0          ## пол-литра молока на человека за смену
const SOUT_COST := 2500.0        ## замеры на одном рабочем месте
const SOUT_DAYS := 2
const BONUS := [0.0, 0.04, 0.08, 0.12]
const CLASS_NAMES := ["2", "3.1", "3.2", "3.3"]
const CLASS_TEXT := ["допустимые условия", "вредные условия 1-й степени", "вредные 2-й степени", "вредные 3-й степени"]
const BOILER_K := 0.45           ## газ своей котельной — доля от цены городского тепла
const COMP_NOISE := 88.0


class Net:
	var id := 0
	var cells: Array[Vector2i] = []
	var srcs: Array[int] = []      ## вентиляторы или компрессоры
	var users: Array[int] = []     ## зонты или потребители воздуха
	var rooms: Array[int] = []
	var area := 0
	var cap := 0.0
	var demand := 0.0


var sim: Sim
# вентиляция
var vnet_of := PackedInt32Array()
var vnets: Array[Net] = []
var thing_vnet: Dictionary = {}    ## id вентилятора или зонта -> индекс сети
var room_vent: Dictionary = {}     ## id помещения -> кратность воздухообмена (0 — нет вентиляции)
var fumes: Dictionary = {}         ## id помещения -> загазованность 0–100
var hooded: Dictionary = {}        ## id станка -> над ним работает зонт
var _vsig := ""
# сжатый воздух
var anet_of := PackedInt32Array()
var anets: Array[Net] = []
var thing_anet: Dictionary = {}    ## id компрессора или потребителя -> индекс сети
var _asig := ""
# котельная
var boiler_rads: Dictionary = {}   ## id батареи -> id котла
var _bsig := ""
# СОУТ, СИЗ, молоко
var sout: Dictionary = {}          ## id станка (строкой) -> {"cls", "day", "f": [названия факторов]}
var sout_until := -1.0             ## когда лаборатория закончит замеры
var sout_ids: Array = []           ## какие места сейчас оценивают
var milk_on := false
var milk_due := 0
var _t := 0.0
var _mood_t := 0.0
var _clean_air_t := 0.0


func _init(s: Sim) -> void:
	sim = s


# ================================================================ общие сети

## Связные группы клеток слоя (воздуховоды или пневмомагистраль).
func _flood(layer: PackedByteArray, out_of: PackedInt32Array) -> Array[Net]:
	var w := sim.world
	var nets: Array[Net] = []
	for i in w.w * w.h:
		if layer[i] != 1 or out_of[i] >= 0:
			continue
		var net := Net.new()
		net.id = nets.size()
		var queue: Array[Vector2i] = [w.cell_of(i)]
		out_of[i] = net.id
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			net.cells.append(c)
			for d: Vector2i in DIRS:
				var nb := c + d
				if not w.inb(nb):
					continue
				var ni := w.idx(nb)
				if layer[ni] == 1 and out_of[ni] < 0:
					out_of[ni] = net.id
					queue.append(nb)
		nets.append(net)
	return nets


## 1.18: воздуховод и пневмомагистраль заводят в клетку прибора (у агрегата — в любую его клетку).
func _touch(t: Thing, whole: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if whole:
		out = t.cells()
	else:
		out.append(t.inlet_cell())
	return out


func _net_at(of: PackedInt32Array, c: Vector2i) -> int:
	var w := sim.world
	if not w.inb(c) or of.size() != w.w * w.h:
		return -1
	return of[w.idx(c)]


# ================================================================ вентиляция

func _vent_topology() -> void:
	var sig := "%d|%d|%d" % [sim.world.duct_rev, sim.thing_rev, sim.rooms.rev]
	if sig == _vsig:
		return
	_vsig = sig
	var w := sim.world
	if w.duct.size() != w.w * w.h:
		w.duct.resize(w.w * w.h)
		w.duct.fill(0)
	vnet_of.resize(w.w * w.h)
	vnet_of.fill(-1)
	vnets = _flood(w.duct, vnet_of)
	thing_vnet.clear()
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var k := t.kind()
		if k != "vent_fan" and k != "vent_hood":
			continue
		var ni := -1
		for c in _touch(t, true):
			ni = _net_at(vnet_of, c)
			if ni >= 0:
				break
		if ni < 0 and k == "vent_fan":
			# вентилятор без воздуховодов тянет воздух только из своего помещения
			var solo := Net.new()
			solo.id = vnets.size()
			vnets.append(solo)
			ni = solo.id
		if ni < 0:
			continue
		thing_vnet[t.id] = ni
		if k == "vent_fan":
			vnets[ni].srcs.append(t.id)
			var fr := sim.rooms.room_of_thing(t)
			if fr and not vnets[ni].rooms.has(fr.id):
				vnets[ni].rooms.append(fr.id)
		else:
			vnets[ni].users.append(t.id)
	for r in sim.rooms.list:
		for c in r.cells:
			var ni2 := _net_at(vnet_of, c)
			if ni2 >= 0 and not vnets[ni2].rooms.has(r.id):
				vnets[ni2].rooms.append(r.id)
	# воздух общий на всё помещение: зоны одного зала проветриваются вместе
	for net0 in vnets:
		var extra: Array[int] = []
		for rid0 in net0.rooms:
			if rid0 >= 0 and rid0 < sim.rooms.list.size():
				for r1 in sim.rooms.space_rooms(sim.rooms.list[rid0].space):
					if not net0.rooms.has(r1.id) and not extra.has(r1.id):
						extra.append(r1.id)
		net0.rooms.append_array(extra)
	for net in vnets:
		net.area = 0
		for rid in net.rooms:
			if rid >= 0 and rid < sim.rooms.list.size():
				net.area += sim.rooms.list[rid].area()


## Мощность сетей вентиляции (вентиляторы под напряжением) и кратность воздухообмена помещений.
func _vent_update() -> void:
	_vent_topology()
	room_vent.clear()
	for net in vnets:
		net.cap = 0.0
		for fid in net.srcs:
			var f: Thing = sim.things.get(fid)
			if f and f.enabled and not f.demolish and sim.power.powered(f):
				net.cap += float(f.def().get("vent_cap", 80))
		if net.cap <= 0.0 or net.area <= 0:
			continue
		var k := net.cap / float(net.area)
		for rid in net.rooms:
			room_vent[rid] = minf(2.0, float(room_vent.get(rid, 0.0)) + k)
	hooded.clear()
	for net2 in vnets:
		if net2.cap <= 0.0:
			continue
		for hid in net2.users:
			var h: Thing = sim.things.get(hid)
			if h == null:
				continue
			for m in sim.things_of("machine"):
				if m.rect().grow(1).has_point(h.cell):
					hooded[m.id] = true


func vent_k(r: Rooms.Room) -> float:
	return float(room_vent.get(r.id, 0.0)) if r else 0.0


func ventilated(r: Rooms.Room) -> bool:
	return vent_k(r) >= 0.5


func fan_ok(f: Thing) -> bool:
	var ni := int(thing_vnet.get(f.id, -1))
	return ni >= 0 and ni < vnets.size() and vnets[ni].cap > 0.0 and sim.power.powered(f)


## Зонт подключён к воздуховоду, а в сети есть работающий вентилятор.
func hood_ok(h: Thing) -> bool:
	var ni := int(thing_vnet.get(h.id, -1))
	return ni >= 0 and ni < vnets.size() and vnets[ni].cap > 0.0


func vnet_of_thing(t: Thing) -> Net:
	var ni := int(thing_vnet.get(t.id, -1))
	return vnets[ni] if ni >= 0 and ni < vnets.size() else null


## Сколько воздух уходит сам: окна, двери (доля в час).
func _natural(r: Rooms.Room) -> float:
	return 0.10 + 0.05 * mini(r.windows, 4) + 0.03 * mini(r.doors, 3)


func _emission(m: Thing) -> float:
	var e := float(FUMES.get(m.process(), 0.0))
	if bool(hooded.get(m.id, false)):
		e *= HOOD_K
	return e


## Загазованность, к которой придёт помещение при обычной загрузке станков (70%) — для СОУТ и проверок.
func eq_fumes(r: Rooms.Room) -> float:
	if r == null:
		return 0.0
	var inp := 0.0
	for tid in r.things:
		var m: Thing = sim.things.get(tid)
		if m and m.kind() == "machine" and m.enabled:
			inp += _emission(m) * 0.7
	inp *= 30.0 / maxf(12.0, float(r.area()))
	return clampf(inp / (_natural(r) + VENT_K * minf(1.5, vent_k(r))), 0.0, 100.0)


func fumes_of(r: Rooms.Room) -> float:
	return float(fumes.get(r.id, 0.0)) if r else 0.0


## Сколько дыма вдыхает человек: в респираторе — меньше.
func exposure(w: Worker) -> float:
	var f := fumes_of(sim.rooms.room_at(w.cell()))
	if w.dressed and w.ppe > 0.0:
		f *= 0.7
	return f


func _fumes_step(hours: float) -> void:
	var keep := {}
	# дым расходится по всему помещению-постройке: считаем по залу, пишем каждой его зоне
	for sp in sim.rooms.spaces:
		if sp.rooms.is_empty():
			continue
		var r: Rooms.Room = sim.rooms.list[sp.rooms[0]]
		var inp := 0.0
		for tid in sp.things:
			var m: Thing = sim.things.get(tid)
			if m and m.kind() == "machine" and m.working:
				inp += _emission(m)
		inp *= 30.0 / maxf(12.0, float(sp.cells.size()))
		var k := _natural(r) + VENT_K * minf(1.5, vent_k(r))
		var f0 := float(fumes.get(r.id, 0.0))
		var eq := inp / k
		var f := eq + (f0 - eq) * exp(-k * hours)
		for rid in sp.rooms:
			keep[rid] = true
			if f < 0.5 and inp <= 0.0:
				fumes.erase(rid)
			else:
				fumes[rid] = clampf(f, 0.0, 100.0)
	for rid in fumes.keys():
		if not keep.has(rid):
			fumes.erase(rid)


## Помещение, где без вентиляции не обойтись: есть сварка, покраска или печь.
func needs_vent(r: Rooms.Room) -> bool:
	for tid in r.things:
		var m: Thing = sim.things.get(tid)
		if m and m.kind() == "machine" and m.process() in ["welding", "paint", "heat", "casting"]:
			return true
	return false


## Множитель скорости работы от дыма.
func speed_k(w: Worker) -> float:
	return 0.9 if exposure(w) >= SMOKY else 1.0


# ================================================================ сжатый воздух

func _air_topology() -> void:
	var sig := "%d|%d" % [sim.world.air_rev, sim.thing_rev]
	if sig == _asig:
		return
	_asig = sig
	var w := sim.world
	if w.air.size() != w.w * w.h:
		w.air.resize(w.w * w.h)
		w.air.fill(0)
	anet_of.resize(w.w * w.h)
	anet_of.fill(-1)
	anets = _flood(w.air, anet_of)
	thing_anet.clear()
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var comp := t.kind() == "compressor"
		if not comp and air_mode(t) == "":
			continue
		for c in _touch(t, comp):
			var ni := _net_at(anet_of, c)
			if ni >= 0:
				thing_anet[t.id] = ni
				if comp:
					anets[ni].srcs.append(t.id)
				else:
					anets[ni].users.append(t.id)
				break


## Пневматика станка: "need" — без воздуха медленно (покраска), "boost" — с воздухом быстрее (сборка).
func air_mode(m: Thing) -> String:
	return str(m.machine_def().get("air", "")) if m.kind() == "machine" else ""


func _air_update() -> void:
	_air_topology()
	for net in anets:
		net.cap = 0.0
		net.demand = 0.0
		for cid in net.srcs:
			var c: Thing = sim.things.get(cid)
			if c and c.enabled and not c.demolish and sim.power.powered(c):
				net.cap += float(c.def().get("air_cap", 4))
		for uid in net.users:
			var u: Thing = sim.things.get(uid)
			if u and u.working:
				net.demand += 1.0


func anet_of_thing(t: Thing) -> Net:
	var ni := int(thing_anet.get(t.id, -1))
	return anets[ni] if ni >= 0 and ni < anets.size() else null


## Давление у потребителя 0–1: нет сети или компрессора — 0, компрессор не успевает — меньше 1.
func pressure(m: Thing) -> float:
	var net := anet_of_thing(m)
	if net == null or net.cap <= 0.0:
		return 0.0
	return clampf(net.cap / maxf(1.0, net.demand), 0.0, 1.0)


## Множитель времени операции от сжатого воздуха.
func air_time_k(m: Thing) -> float:
	match air_mode(m):
		"need":
			return 1.6 - 0.6 * pressure(m)
		"boost":
			return 1.0 - 0.2 * pressure(m)
	return 1.0


## Нагрузка компрессора 0–1 (для электросети и шума): 15% на холостом ходу, если есть потребители.
func comp_load(c: Thing) -> float:
	var net := anet_of_thing(c)
	if net == null or net.cap <= 0.0:
		return 0.0
	if net.demand <= 0.0:
		return 0.15 if not net.users.is_empty() else 0.0
	return clampf(net.demand / net.cap, 0.2, 1.0)


func compressor_running(c: Thing) -> bool:
	return sim.power.powered(c) and c.enabled and comp_load(c) >= 0.2


# ================================================================ котельная

func boiler_ok(b: Thing) -> bool:
	return b.built and b.enabled and not b.demolish and sim.power.powered(b) and sim.water.has_water(b) and sim.rooms.thing_in(b, "boiler_room")


## Почему котёл не греет (пустая строка — греет).
func boiler_problem(b: Thing) -> String:
	if not sim.rooms.thing_in(b, "boiler_room"):
		return L.t("котёл стоит не в котельной (отдельное помещение, бетонный пол, назначение «Котельная»)")
	if not sim.water.has_water(b):
		return L.t("нет воды: протяните трубу от насоса")
	if not sim.power.powered(b):
		return L.t("нет тока: автоматика горелки без электричества не работает")
	if not b.enabled:
		return L.t("выключен")
	return ""


func _boiler_update() -> void:
	var sig := "%d|%d|%d|%d" % [sim.world.pipe_rev, sim.thing_rev, sim.rooms.rev, int(sim.minute / 30.0)]
	if sig == _bsig:
		return
	_bsig = sig
	boiler_rads.clear()
	sim.water.update()
	var rads := sim.things_of("radiator")
	for b in sim.things_of("boiler"):
		if not boiler_ok(b):
			continue
		var k := int(sim.water.thing_net.get(b.id, -1))
		if k < 0:
			continue
		var cap := int(b.def().get("boiler_cap", 16))
		var cand: Array = []
		for r in rads:
			if boiler_rads.has(r.id):
				continue
			for c in _touch(r, true):
				if sim.world.inb(c) and sim.water.net_of.size() > 0 and sim.water.net_of[sim.world.idx(c)] == k:
					cand.append(r)
					break
		cand.sort_custom(func(a: Thing, bb: Thing) -> bool: return Vector2(a.cell - b.cell).length() < Vector2(bb.cell - b.cell).length())
		for i in mini(cap, cand.size()):
			boiler_rads[(cand[i] as Thing).id] = b.id


## Греет ли батарея: от своего газового котла — всегда в сезон; иначе нужен электрокотёл
## у насосной под током (1.20), и на теплотрассе нет аварии.
func radiator_on(r: Thing) -> bool:
	if boiler_rads.has(r.id):
		return true
	return heater_ok() and not sim.story.has_mod("heat_off")


var _hok_key := -1
var _hok := false


## 1.20: работает ли электрокотёл у насосной (тогда батареи горячие).
func heater_ok() -> bool:
	var key := int(sim.minute / 5.0) * 100000 + sim.thing_rev
	if key == _hok_key:
		return _hok
	_hok_key = key
	_hok = false
	for h in sim.things_of("heater"):
		if heater_problem(h) == "":
			_hok = true
			break
	return _hok


## Почему электрокотёл не греет ("" — греет).
func heater_problem(h: Thing) -> String:
	if not h.built:
		return L.t("ещё не установлен")
	if not h.enabled:
		return L.t("выключен")
	if not sim.power.powered(h):
		return L.t("нет тока — протяните кабель от подстанции")
	var pump_ok := false
	for p in sim.things_of("pump"):
		if p.built and p.rect().grow(1).intersects(h.rect()):
			if sim.water.pump_running(p):
				pump_ok = true
	if not pump_ok:
		return L.t("рядом нет работающей насосной (нужна вплотную, под током)")
	return ""


func boiler_load(b: Thing) -> int:
	var n := 0
	for bid in boiler_rads.values():
		if int(bid) == b.id:
			n += 1
	return n


# ================================================================ СОУТ

## Факторы условий труда на рабочем месте сейчас: [[название, баллы, подробности]].
func factors(m: Thing) -> Array:
	var out: Array = []
	var sp: Array = m.spots()
	var c: Vector2i = sp[0]["cell"] if not sp.is_empty() else m.cell
	var r := sim.rooms.room_of_thing(m)
	var nz := sim.season.noise_at(c, true)
	if nz >= 86.0:
		out.append([L.t("шум"), 2, L.t("%d дБ") % int(nz)])
	elif nz >= 80.0:
		out.append([L.t("шум"), 1, L.t("%d дБ") % int(nz)])
	var fu := eq_fumes(r)
	if m.process() in ["welding", "paint"] and not bool(hooded.get(m.id, false)):
		fu += LOCAL
	if fu >= 60.0:
		out.append([L.t("аэрозоль и пары"), 2, "%d%%" % int(fu)])
	elif fu >= 30.0:
		out.append([L.t("аэрозоль и пары"), 1, "%d%%" % int(fu)])
	if m.process() == "heat":
		out.append([L.t("тепловое излучение"), 1, ""])
	if r == null:
		out.append([L.t("микроклимат"), 1, L.t("на улице")])
	else:
		var heated := false
		for tid in r.things:
			var th: Thing = sim.things.get(tid)
			if th and th.def_id == "radiator":
				heated = true
				break
		var tc := float(sim.season.room_temp.get(r.id, 18.0))
		if not heated and not needs_vent(r):
			out.append([L.t("микроклимат"), 1, L.t("нет отопления")])
		elif tc < 14.0 or tc > 28.0:
			out.append([L.t("микроклимат"), 1, "%+d °C" % int(round(tc))])
		if not r.powered:
			out.append([L.t("освещённость"), 1, L.t("нет электрического света")])
	return out


func class_now(m: Thing) -> int:
	var p := 0
	for f: Array in factors(m):
		p += int(f[1])
	return clampi(p, 0, 3)


func assessed(m: Thing) -> bool:
	return sout.has(str(m.id))


## Класс по последней СОУТ (-1 — не оценивали).
func class_of(m: Thing) -> int:
	return int((sout.get(str(m.id), {}) as Dictionary).get("cls", -1)) if m else -1


func workplaces() -> Array[Thing]:
	var out: Array[Thing] = []
	for m in sim.things_of("machine"):
		if not m.demolish:
			out.append(m)
	return out


func unassessed() -> int:
	var n := 0
	for m in workplaces():
		if not assessed(m):
			n += 1
	return n


func sout_busy() -> bool:
	return sout_until >= 0.0


func sout_price(all: bool) -> float:
	var n := 0
	for m in workplaces():
		if all or not assessed(m):
			n += 1
	return n * SOUT_COST


## Заказать замеры в аккредитованной лаборатории: все места или только новые.
func start_sout(all: bool) -> String:
	if sout_busy():
		return L.t("Лаборатория уже работает")
	var ids: Array = []
	for m in workplaces():
		if all or not assessed(m):
			ids.append(m.id)
	if ids.is_empty():
		return L.t("Все рабочие места уже оценены")
	var cost := ids.size() * SOUT_COST
	if not sim.can_afford(cost):
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(cost)
	sim.spend(cost, "СОУТ: замеры на %d %s" % [ids.size(), Defs.plural(ids.size(), "рабочем месте", "рабочих местах", "рабочих местах")])
	sout_ids = ids
	sout_until = sim.orders.deadline_after(SOUT_DAYS)
	sim.notify(L.t("Лаборатория начала спецоценку условий труда: %d %s. Результаты — к концу дня %d. Пока идут замеры, можно улучшить условия: вентиляция, свет, отопление.") % [ids.size(), Defs.plural(ids.size(), "место", "места", "мест"), int(sout_until / 1440.0) + 1], Sim.LVL_INFO)
	return ""


func _finish_sout() -> void:
	var n := [0, 0, 0, 0]
	for mid in sout_ids:
		var m: Thing = sim.things.get(int(mid))
		if m == null:
			continue
		var fs := factors(m)
		var names: Array = []
		var p := 0
		for f: Array in fs:
			p += int(f[1])
			names.append(str(f[0]))
		var cls := clampi(p, 0, 3)
		sout[str(m.id)] = {"cls": cls, "day": sim.day(), "f": names}
		n[cls] += 1
	sout_ids.clear()
	sout_until = -1.0
	sim.stats["sout_done"] = int(sim.stats.get("sout_done", 0)) + 1
	var harm := int(n[1]) + int(n[2]) + int(n[3])
	var txt := L.t("СОУТ завершена: допустимых мест %d, вредных %d.") % [n[0], harm]
	if harm > 0:
		txt += L.t(" На вредных местах положены доплата (4–12%% к ставке) и молоко — включите выдачу молока в «Люди → Охрана труда».")
	sim.notify(txt, Sim.LVL_GOOD if harm == 0 else Sim.LVL_INFO)
	sim.paper.add(L.t("Охрана труда"), L.t("Спецоценка: %d %s проверено") % [n[0] + harm, Defs.plural(n[0] + harm, "место", "места", "мест")],
		L.t("Лаборатория замерила шум, свет, микроклимат и воздух. Вредных мест — %d. %s") % [harm, L.t("Профком доволен.") if harm == 0 else L.t("Будет молоко и доплата.")])


## Класс вредности места, где работает человек (по СОУТ; без оценки — 0).
func worker_class(w: Worker) -> int:
	if w.is_itr() or w.workplace < 0:
		return 0
	var m: Thing = sim.things.get(w.workplace)
	return maxi(0, class_of(m))


func harm_bonus(w: Worker) -> float:
	return float(BONUS[worker_class(w)])


func entitled_milk(w: Worker) -> bool:
	return worker_class(w) >= 1


func entitled_count() -> int:
	var n := 0
	for w in sim.workers:
		if entitled_milk(w):
			n += 1
	return n


# ================================================================ СИЗ

func cabinets() -> Array[Thing]:
	return sim.things_of("ppe_cabinet").filter(func(t: Thing) -> bool: return not t.demolish)


func ppe_stock() -> int:
	return int(floor(float(sim.cons.get("ppe", 0.0))))


## Нужно взять новый комплект СИЗ и есть где.
func wants_ppe(w: Worker) -> bool:
	if w.is_itr() or w.visitor or w.ppe >= 15.0:
		return false
	return ppe_stock() >= 1 and not cabinets().is_empty()


func issue_ppe(w: Worker) -> bool:
	if ppe_stock() < 1:
		return false
	sim.use_cons("ppe", 1.0)
	w.ppe = 100.0
	Mood.add(sim, w, "new_ppe")
	sim.stats["ppe_issued"] = int(sim.stats.get("ppe_issued", 0)) + 1
	return true


func without_ppe() -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if not w.is_itr() and w.ppe <= 0.0 and w.days_worked > 0:
			out.append(w)
	return out


## Множитель травм: без СИЗ — в полтора раза чаще.
func injury_k(w: Worker) -> float:
	if w.is_itr():
		return 1.0
	return 1.5 if w.ppe <= 0.0 else 1.0


## Человек пришёл на смену: износ СИЗ, молоко, доплата за вредность (в ставке).
func on_spawn(w: Worker) -> void:
	if w.is_itr() or w.visitor:
		return
	w.ppe = maxf(0.0, w.ppe - PPE_WEAR)
	if w.ppe <= 0.0:
		if cabinets().is_empty():
			sim.notify_once("ppe_cab", L.t("%s без СИЗ (каска, очки, наушники): %s. Поставьте шкаф СИЗ (Объекты → Безопасность) и закупите комплекты — без них травм в полтора раза больше.") % [w.full_name(), L.t("новичкам их выдают на заводе") if w.days_worked <= 1 else L.t("старый комплект износился")], Sim.LVL_WARN, Vector2i(-1, -1), 2880.0)
		elif ppe_stock() < 1:
			sim.notify_once("ppe_stock", L.t("Закончились комплекты СИЗ в шкафу. Закажите в «Люди → Охрана труда» (или включите автозакупку)."), Sim.LVL_WARN, Vector2i(-1, -1), 720.0)
	if entitled_milk(w):
		if milk_on:
			milk_due += 1
			Mood.add(sim, w, "milk")
		else:
			Mood.add(sim, w, "no_milk")
		Mood.add(sim, w, "sout_harm")


# ================================================================ ход времени

func tick(dt: float) -> void:
	_t += dt
	if _t >= 5.0:
		var hours := _t / 60.0
		_t = 0.0
		_vent_update()
		_air_update()
		_boiler_update()
		_fumes_step(hours)
		_clean_air_check()
		_hints()
	_mood_t += dt
	if _mood_t >= 30.0:
		_mood_t = 0.0
		_thoughts()
	if sout_until >= 0.0 and sim.minute >= sout_until:
		_finish_sout()


func morning() -> void:
	var rab := 0
	for w in sim.workers:
		if not w.is_itr():
			rab += 1
	if rab >= 4 and unassessed() > 0 and not sout_busy():
		sim.notify_once("sout_hint", L.t("Рабочих уже %d, а СОУТ не проведена на %d %s. Трудовая инспекция за это штрафует — закажите замеры в «Люди → Охрана труда».") % [rab, unassessed(), Defs.plural(unassessed(), "месте", "местах", "местах")], Sim.LVL_INFO, Vector2i(-1, -1), 7.0 * 1440.0)
	if milk_due > 0:
		sim.spend(milk_due * MILK_COST, "Молоко за вредность: %d %s" % [milk_due, Defs.plural(milk_due, "бутылка", "бутылки", "бутылок")])
		milk_due = 0
	if sim.season.heating_season() and not boiler_rads.is_empty():
		sim.stats["boiler_days"] = int(sim.stats.get("boiler_days", 0)) + 1


## Подсказки игроку: дым без вентиляции, покраска без воздуха, котёл не греет.
func _hints() -> void:
	if not sim.is_work_time():
		return
	for r in sim.rooms.list:
		if fumes_of(r) >= STUFFY and vent_k(r) <= 0.0:
			sim.notify_once("fumes_%d" % r.id, L.t("В помещении «%s» дым и пары (%d%%): людям душно, работают медленнее. Поставьте вытяжной вентилятор и зонт над сварочным постом или камерой (Сети → Вентиляция).") % [r.title(), int(fumes_of(r))], Sim.LVL_WARN, r.cells[0], 1440.0)
			break
	for m in sim.things_of("machine"):
		if air_mode(m) == "need" and m.working and pressure(m) <= 0.0:
			sim.notify_once("noair", L.t("%s без сжатого воздуха: красят кистью, в полтора раза дольше. Поставьте компрессор и протяните пневмомагистраль (Сети → Сжатый воздух).") % m.title(), Sim.LVL_INFO, m.cell, 2880.0)
			break
	if sim.season.heating_season():
		for b in sim.things_of("boiler"):
			var bp := boiler_problem(b)
			if bp != "":
				sim.notify_once("boiler_%d" % b.id, L.t("Котёл не греет: %s.") % bp, Sim.LVL_WARN, b.cell, 1440.0)


## Сварочный пост под зонтом и с вентиляцией в помещении — достижение «Чистый воздух».
func _clean_air_check() -> void:
	if int(sim.stats.get("clean_air", 0)) > 0:
		return
	for m in sim.things_of("machine"):
		if m.process() == "welding" and m.working and bool(hooded.get(m.id, false)) and ventilated(sim.rooms.room_of_thing(m)):
			sim.stats["clean_air"] = 1
			return


func _thoughts() -> void:
	for w in sim.workers:
		if not w.present or w.hidden:
			continue
		var f := exposure(w)
		if f >= SMOKY:
			Mood.add(sim, w, "fumes")
		elif f >= STUFFY:
			Mood.add(sim, w, "stuffy")
		var muffs := w.dressed and w.ppe > 0.0 and not w.is_itr() and sim.season.noise_at(w.cell()) >= 80.0
		w.muffs = muffs
		if not w.is_itr() and w.dressed and w.ppe <= 0.0 and w.task and w.task.kind in ["operate", "build", "haul"]:
			Mood.add(sim, w, "no_ppe")


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"fumes": _keys_str(fumes), "sout": sout, "sout_until": sout_until, "sout_ids": sout_ids, "milk": milk_on, "milk_due": milk_due}


func _keys_str(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[str(k)] = d[k]
	return out


func from_dict(d: Dictionary) -> void:
	fumes.clear()
	var fd: Dictionary = d.get("fumes", {})
	for k in fd.keys():
		fumes[int(k)] = float(fd[k])
	sout = d.get("sout", {})
	for k2 in sout.keys():
		var e: Dictionary = sout[k2]
		e["cls"] = int(e.get("cls", 0))
		e["day"] = int(e.get("day", 0))
	sout_until = float(d.get("sout_until", -1.0))
	sout_ids = []
	for v in d.get("sout_ids", []):
		sout_ids.append(int(v))
	milk_on = bool(d.get("milk", false))
	milk_due = int(d.get("milk_due", 0))
