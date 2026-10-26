class_name Power
extends RefCounted
## Электросеть: кабели, источники (подстанция), потребители (станки, техника, свет).
## 1.18: источник один — трансформаторная подстанция 2×2 в техпомещении; аккумуляторные шкафы вплотную
## к ней добавляют мощность (до 9 шкафов). Сеть — связная группа клеток с кабелем. Станок или прибор
## подключён, только если кабель заведён в его клетку подключения (розетку); подстанция — если кабель
## заходит в одну из её клеток. Светильник подключается сам, если кабель проходит не дальше трёх клеток.
## При перегрузе дольше нескольких минут выбивает автомат.


class Net:
	var id := 0
	var cells: Array[Vector2i] = []
	var sources: Array[int] = []
	var consumers: Array[int] = []
	var rooms: Array[int] = []
	var capacity := 0.0
	var load := 0.0
	var tripped := false
	var over_time := 0.0
	var batts: Array[int] = []     ## 1.13: аккумуляторные шкафы у подстанций этой сети
	var batt_out := 0.0            ## сколько кВт сейчас отдают аккумуляторы (+) или берут на зарядку (−)

	func ok() -> bool:
		return capacity > 0.0 and not tripped

	## Нагрузка больше, чем дают источники (даже если пока выручают аккумуляторы).
	func over() -> bool:
		return capacity > 0.0 and load > capacity + 0.01


const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var sim: Sim
var net_of := PackedInt32Array()
var nets: Array[Net] = []
var thing_net: Dictionary = {}     ## id объекта -> индекс сети
var room_net: Dictionary = {}      ## id помещения -> индекс сети
var tripped_sources: Dictionary = {}  ## id источника -> true (сохраняется)
var grid_level := 0                ## старые сохранения: мощность по договору с сетевой компанией (досталась первому трансформатору)
var total_load := 0.0
var _sig := ""
var light_link: Dictionary = {}    ## id светильника -> клетка кабеля, к которой он подключён
var lamp_on: Dictionary = {}       ## id светильника -> горит ли
var _light_sig := ""


func _init(s: Sim) -> void:
	sim = s


func grid_kw() -> float:
	var lv: Array = Defs.barr("grid_levels")
	if lv.is_empty():
		return 15.0
	return float(lv[clampi(grid_level, 0, lv.size() - 1)])


## ---- 1.53: увеличение мощности по договору (заявка в сетевую компанию)

func max_contract() -> int:
	return Defs.barr("contract_kw").size() - 1


func contract_kw() -> float:
	var a: Array = Defs.barr("contract_kw")
	return float(a[clampi(contract_steps, 0, a.size() - 1)]) if not a.is_empty() else 0.0


## Следующий шаг: {"step", "kw" (прибавка), "cost", "days"}; пусто — выше некуда.
func next_upgrade() -> Dictionary:
	if contract_steps >= max_contract():
		return {}
	var st := contract_steps + 1
	var kw: Array = Defs.barr("contract_kw")
	var cost: Array = Defs.barr("contract_cost")
	var days: Array = Defs.barr("contract_days")
	return {"step": st, "kw": float(kw[st]) - float(kw[st - 1]), "cost": float(cost[st]), "days": int(days[st])}


## Почему нельзя заказать (пусто — можно).
func upgrade_block() -> String:
	if not upgrade.is_empty():
		return L.t("Заявка уже в работе: сетевая компания подключит мощность через %d дн.") % maxi(0, int(upgrade["due"]) - sim.day())
	var nu := next_upgrade()
	if nu.is_empty():
		return L.t("Больше мощности по договору не выдают.")
	if grid_input_id() < 0:
		return L.t("Нужна подстанция в техпомещении.")
	if sim.money < float(nu["cost"]):
		return L.t("Не хватает денег: нужно %s.") % Defs.money_str(float(nu["cost"]))
	return ""


func order_upgrade() -> String:
	var why := upgrade_block()
	if why != "":
		return why
	var nu := next_upgrade()
	sim.spend(float(nu["cost"]), "Техприсоединение: +%d кВт" % int(nu["kw"]))
	upgrade = {"step": int(nu["step"]), "due": sim.day() + int(nu["days"]), "cost": float(nu["cost"])}
	sim.notify(L.t("Заявка в сетевую компанию отправлена: +%d кВт к лимиту через %d дн.") % [int(nu["kw"]), int(nu["days"])], Sim.LVL_INFO)
	return ""


## Утро: заявка могла дойти; закрываем сутки (пик, расход).
func on_new_day() -> void:
	if not upgrade.is_empty() and sim.day() >= int(upgrade["due"]):
		contract_steps = maxi(contract_steps, int(upgrade["step"]))
		upgrade = {}
		_acc = 1.0
		sim.notify(L.t("Сетевая компания подключила дополнительную мощность: лимит подстанции теперь %d кВт.") % int(total_kw()), Sim.LVL_GOOD)


## Тариф: ночью (с 23:00 до 7:00) электричество дешевле.
func night_now() -> bool:
	return is_night_at(sim.minute)


static func is_night_at(minute: float) -> bool:
	var h := fposmod(minute, 1440.0) / 60.0
	return h >= Defs.b("tariff_night_from") or h < Defs.b("tariff_night_to")


func price_now() -> float:
	return Defs.b("power_price_kwh") * (Defs.b("tariff_night_k") if night_now() else 1.0)


## Стоимость накопленных за сутки кВт·ч: [день ₽, ночь ₽].
func cost_today() -> Array:
	var p := Defs.b("power_price_kwh")
	return [kwh_day * p, kwh_night * p * Defs.b("tariff_night_k")]


## Закрыть сутки: списать за электричество (две строки — день и ночь) и записать в историю.
func close_day() -> void:
	var c := cost_today()
	if kwh_day > 0.0:
		sim.spend(float(c[0]), "Электроэнергия, день: %d кВт·ч" % int(kwh_day))
	if kwh_night > 0.0:
		sim.spend(float(c[1]), "Электроэнергия, ночь: %d кВт·ч" % int(kwh_night))
	hist.push_front({"d": sim.day(), "kd": kwh_day, "kn": kwh_night, "cd": float(c[0]), "cn": float(c[1]), "peak": peak_day})
	if hist.size() > 14:
		hist.resize(14)
	peak_prev = peak_day
	peak_day = total_load
	kwh_day = 0.0
	kwh_night = 0.0
	trips_today = 0
	sim.power_kwh_day = 0.0


## За последние n суток: [кВт·ч день, кВт·ч ночь, ₽ день, ₽ ночь].
func week_sum(n: int = 7) -> Array:
	var r := [0.0, 0.0, 0.0, 0.0]
	for h: Dictionary in hist.slice(0, n):
		r[0] += float(h["kd"])
		r[1] += float(h["kn"])
		r[2] += float(h["cd"])
		r[3] += float(h["cn"])
	return r


func max_level() -> int:
	return Defs.barr("grid_levels").size() - 1


const BATT_MAX := 9


## Источник, к которому можно прижать аккумуляторы: подстанция 1.18 и старая КТП.
static func boostable(t: Thing) -> bool:
	return str(t.def().get("power_source", "")) in ["tp", "ktp"]


## Подстанция, к которой прижат аккумуляторный шкаф (в пределах одной клетки), или null.
func battery_host(b: Thing) -> Thing:
	var br := Rect2i(b.cell, Vector2i.ONE)
	for t: Thing in sim.things.values():
		if t.built and t.id != b.id and boostable(t) and t.rect().grow(1).intersects(br):
			return t
	return null


## 1.18: сколько кВт добавляют шкафы у подстанции (не больше девяти, только построенные и в техпомещении).
func battery_boost(src: Thing) -> float:
	var n := 0
	var kw := 0.0
	for b in batteries_of(src):
		if b.built and sim.rooms.zone_ok(b) and n < BATT_MAX:
			n += 1
			kw += float(b.def().get("boost_kw", 20.0))
	return kw


## Аккумуляторы у подстанции.
func batteries_of(src: Thing) -> Array[Thing]:
	var out: Array[Thing] = []
	var area := src.rect().grow(1)
	for t: Thing in sim.things.values():
		if t.kind() == "battery" and area.has_point(t.cell):
			out.append(t)
	return out


## Первый поставленный малый трансформатор: ему досталась мощность старого договора (сохранения до 1.15)
## и от него автопрокладка тянет кабели. -1 — нет ни одного.
func grid_input_id() -> int:
	var best := -1
	var best_rank := 99
	for t: Thing in sim.things.values():
		if not t.built or str(t.def().get("power_source", "")) == "":
			continue
		# 1.18: сначала подстанция, потом малый трансформатор старых сохранений, потом остальные
		var rank := 0 if t.def_id == "substation" else (1 if t.def_id == "cabinet" else 2)
		if best < 0 or rank < best_rank or (rank == best_rank and t.id < best):
			best = t.id
			best_rank = rank
	return best


func source_capacity(t: Thing) -> float:
	if sim.story and sim.story.outage():
		return 0.0
	if not sim.rooms.zone_ok(t):
		return 0.0   # подстанция вне техпомещения не работает (1.13)
	if str(t.def().get("power_source", "")) == "":
		return 0.0
	var cap := float(t.def().get("capacity_kw", 15.0))
	if grid_level > 0 and t.def_id == "cabinet" and t.id == grid_input_id():
		cap = maxf(cap, grid_kw())
	if boostable(t):
		cap += battery_boost(t)   # 1.18: аккумуляторы прибавляют мощность
	if contract_steps > 0 and t.id == grid_input_id():
		cap += contract_kw()   # 1.53: увеличение мощности по договору
	return cap


## Сколько всего дают поставленные трансформаторы и подстанции.
func total_kw() -> float:
	var s := 0.0
	for t: Thing in sim.things.values():
		if t.built and str(t.def().get("power_source", "")) != "":
			s += source_capacity(t)
	return s


## Клетки, через которые объект берёт ток. 1.18: у станков и приборов — только сама розетка,
## у источников — только клетки самого объекта: кабель нужно завести внутрь.
func _touch_cells(t: Thing) -> Array[Vector2i]:
	if str(t.def().get("power_source", "")) == "":
		var arr: Array[Vector2i] = [t.inlet_cell()]
		return arr
	return t.cells()


func _net_at(c: Vector2i) -> int:
	var w := sim.world
	if not w.inb(c) or net_of.size() != w.w * w.h:
		return -1
	return net_of[w.idx(c)]


func update_topology() -> void:
	var w := sim.world
	var n := w.w * w.h
	var old_tripped := tripped_sources.duplicate()
	net_of.resize(n)
	net_of.fill(-1)
	nets.clear()
	thing_net.clear()
	room_net.clear()
	for i in n:
		if w.cable[i] != 1 or net_of[i] >= 0:
			continue
		var net := Net.new()
		net.id = nets.size()
		var queue: Array[Vector2i] = [w.cell_of(i)]
		net_of[i] = net.id
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			net.cells.append(c)
			for d: Vector2i in DIRS:
				var nb := c + d
				if not w.inb(nb):
					continue
				var ni := w.idx(nb)
				if w.cable[ni] == 1 and net_of[ni] < 0:
					net_of[ni] = net.id
					queue.append(nb)
		nets.append(net)
	light_link.clear()
	var lr := int(Defs.b("light_link_r"))
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		if t.kind() == "light" or t.kind() == "camera" or t.kind() == "speaker":
			# светильник (и видеокамера): ближайший кабель в радиусе нескольких клеток
			var best := Vector2i(-1, -1)
			var bd := 999.0
			for dy in range(-lr, lr + 1):
				for dx in range(-lr, lr + 1):
					var cc := t.cell + Vector2i(dx, dy)
					if _net_at(cc) < 0:
						continue
					var dd := Vector2(dx, dy).length()
					if dd > lr + 0.25:
						continue
					if dd < bd:
						bd = dd
						best = cc
			if best.x >= 0:
				light_link[t.id] = best
				var nl := _net_at(best)
				thing_net[t.id] = nl
				nets[nl].consumers.append(t.id)
			continue
		var is_src := str(t.def().get("power_source", "")) != ""
		var draws := t.kind() == "machine" or float(t.def().get("power_kw", 0.0)) > 0.0
		if not is_src and not draws:
			continue
		var ni2 := -1
		for c in _touch_cells(t):
			ni2 = _net_at(c)
			if ni2 >= 0:
				break
		if ni2 < 0:
			continue
		thing_net[t.id] = ni2
		if is_src:
			nets[ni2].sources.append(t.id)
		else:
			nets[ni2].consumers.append(t.id)
	for r in sim.rooms.list:
		for c in r.cells:
			var ni3 := _net_at(c)
			if ni3 >= 0:
				room_net[r.id] = ni3
				nets[ni3].rooms.append(r.id)
				break
	# аккумуляторы: к сети той подстанции, к которой прижаты
	for net2 in nets:
		for sid0 in net2.sources:
			var st0: Thing = sim.things.get(sid0)
			if st0 == null:
				continue
			for bt in batteries_of(st0):
				if bt.built and not net2.batts.has(bt.id):
					net2.batts.append(bt.id)
					thing_net[bt.id] = net2.id
	tripped_sources.clear()
	for net in nets:
		for sid in net.sources:
			if old_tripped.has(sid):
				net.tripped = true
		if net.tripped:
			for sid2 in net.sources:
				tripped_sources[sid2] = true


func _sig_now() -> String:
	return "%d|%d|%d|%d" % [sim.world.cable_rev, sim.thing_rev, sim.rooms.rev, grid_level]


var _light_t := 0.0
var _light_key := ""

## 1.53: договор с сетевой компанией, пик нагрузки и тарифы.
var contract_steps := 0            ## сколько раз увеличивали мощность (0..max_contract())
var upgrade: Dictionary = {}       ## заявка в сетевую компанию: {"step", "due" (день), "cost"}; пусто — нет заявки
var peak_day := 0.0                ## пик нагрузки за текущие сутки, кВт
var peak_prev := 0.0               ## пик за вчера
var kwh_day := 0.0                 ## сегодня дневным тарифом, кВт·ч
var kwh_night := 0.0               ## сегодня ночным тарифом, кВт·ч
var trips_today := 0
var hist: Array = []               ## по суткам: {d, kd, kn, cd, cn, peak} — последние 14


var _acc := 0.0


func tick(dt0: float) -> void:
	var sig := _sig_now()
	var topo := sig != _sig
	if topo:
		_sig = sig
		update_topology()
	# 1.22: нагрузку сетей считаем раз в игровую минуту (или сразу после перестройки сети)
	_acc += dt0
	if _acc < 1.0 and not topo and dt0 > 0.0:
		return
	var dt := _acc
	_acc = 0.0
	var anyone := false
	for w in sim.workers:
		if w.present:
			anyone = true
			break
	var dark := not sim.is_daylight()
	total_load = 0.0
	for net in nets:
		net.capacity = 0.0
		for sid in net.sources:
			var st: Thing = sim.things.get(sid)
			if st:
				net.capacity += source_capacity(st)
		var load := 0.0
		for tid in net.consumers:
			var t: Thing = sim.things.get(tid)
			if t == null:
				continue
			if t.kind() == "machine":
				if t.working:
					load += float(t.machine_def().get("power_kw", 5.0))
			elif t.kind() == "light":
				if bool(lamp_on.get(t.id, false)):
					load += float(t.def().get("power_kw", 0.1))
			else:
				var kw := float(t.def().get("power_kw", 0.0))
				match t.kind():
					"compressor":
						kw *= sim.eng.comp_load(t) if t.enabled else 0.0
					"vent_fan":
						kw *= 1.0 if t.enabled else 0.0
					"boiler":
						kw *= 1.0 if t.enabled and sim.season.heating_season() else 0.1
					"heater":
						# 1.20: электрокотёл тянет ток в отопительный сезон, летом — только дежурный режим
						kw *= (1.0 if sim.season.heating_season() else 0.05) if t.enabled else 0.0
				load += kw
		net.load = load
		net.batt_out = 0.0
		if net.tripped:
			continue
		if net.capacity <= 0.0:
			continue
		total_load += load
		if load > net.capacity + 0.01:
			net.over_time += dt
			if net.over_time >= Defs.b("breaker_delay"):
				_trip(net)
		else:
			net.over_time = maxf(0.0, net.over_time - dt)
	var kwh := total_load * dt / 60.0
	sim.power_kwh_day += kwh
	if night_now():
		kwh_night += kwh
	else:
		kwh_day += kwh
	peak_day = maxf(peak_day, total_load)
	# 1.22: свет пересчитываем раз в игровую минуту (или сразу, если что-то построили/снесли)
	_light_t -= dt
	var lk := "%d|%d|%s|%s" % [sim.thing_rev, sim.rooms.rev, anyone, dark]
	if _light_t <= 0.0 or lk != _light_key:
		_light_t = 1.0
		_light_key = lk
		_update_lights(anyone, dark)


## Аккумуляторы сети: [прибавка кВт, шкафов].
func battery_state(net: Net) -> Array:
	var kw := 0.0
	var n := 0
	for sid in net.sources:
		var st: Thing = sim.things.get(sid)
		if st and boostable(st):
			kw += battery_boost(st)
			n += mini(BATT_MAX, batteries_of(st).size())
	return [kw, n]


## Какие светильники горят и какие клетки ими освещены; освещённость помещений.
func _update_lights(anyone: bool, dark: bool) -> void:
	var on_list: Array[int] = []
	for t: Thing in sim.things.values():
		if not t.built or t.kind() != "light":
			continue
		var r := sim.rooms.room_at(t.cell)
		var need := dark or (r != null and r.windows == 0)
		var on := powered(t) and need and (anyone or bool(t.def().get("outdoor", false)))
		lamp_on[t.id] = on
		if on:
			on_list.append(t.id)
	var sig := "%s|%d|%d|%s" % [str(on_list), sim.rooms.rev, sim.thing_rev, sim.is_daylight()]
	if sig == _light_sig:
		return
	_light_sig = sig
	var w := sim.world
	var n := w.w * w.h
	if sim.light.size() != n:
		sim.light.resize(n)
	sim.light.fill(0)
	var space_on := {}
	for tid in on_list:
		var t2: Thing = sim.things[tid]
		var rr := float(t2.def().get("light_r", 3.0))
		var home := sim.rooms.space_id_at(t2.cell)
		if home >= 0:
			space_on[home] = true
		var ri := int(ceil(rr))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if Vector2(dx, dy).length() > rr:
					continue
				var c := t2.cell + Vector2i(dx, dy)
				if not w.inb(c):
					continue
				# свет не проходит сквозь стены: только своё помещение (все его зоны) или улица для уличных
				if sim.rooms.space_id_at(c) != home:
					continue
				sim.light[w.idx(c)] = 1
	for r2 in sim.rooms.list:
		var lit_n := 0
		for c2 in r2.cells:
			if sim.light[w.idx(c2)] != 0:
				lit_n += 1
		r2.lights_on = space_on.has(r2.space)
		r2.powered = false
		for tid2 in light_link.keys():
			var lt: Thing = sim.things.get(tid2)
			if lt and sim.rooms.space_id_at(lt.cell) == r2.space and powered(lt):
				r2.powered = true
				break
		r2.lit = float(lit_n) >= r2.area() * 0.6 or (sim.is_daylight() and r2.windows > 0)


## Клетка освещена: лампой, или днём — светом из окон (в помещении) или солнцем (на улице).
func cell_lit(c: Vector2i) -> bool:
	var w := sim.world
	if not w.inb(c):
		return false
	if sim.light.size() == w.w * w.h and sim.light[w.idx(c)] != 0:
		return true
	var r := sim.rooms.room_at(c)
	if r:
		return sim.is_daylight() and r.windows > 0
	return sim.is_daylight()


func _trip(net: Net) -> void:
	net.tripped = true
	net.over_time = 0.0
	for sid in net.sources:
		tripped_sources[sid] = true
	for tid in net.consumers:
		var t: Thing = sim.things.get(tid)
		if t and t.kind() == "machine":
			t.working = false
	var cell := Vector2i(-1, -1)
	if not net.sources.is_empty():
		var st: Thing = sim.things.get(net.sources[0])
		if st:
			cell = st.cell
	sim.notify(L.t("Выбило автомат: перегрузка сети (%.1f из %d кВт). Его сбросят на подстанции, но перегруз повторится — выключите лишний станок в его карточке или прижмите к подстанции аккумуляторные шкафы (+20 кВт каждый).") % [net.load, int(net.capacity)], Sim.LVL_BAD, cell)
	sim.sfx.emit("breaker", cell)
	trips_today += 1
	# 1.53: тревога — окно с кнопкой «Включить» (игра встаёт на паузу), завод стоит, пока автомат не включат
	sim.story.letter("breaker", L.t("ТРЕВОГА: выбило вводной автомат"),
		L.t("Нагрузка %.1f кВт превысила лимит подстанции %d кВт — завод обесточен, станки стоят. Включить автомат можно сразу, но если не убрать лишнюю нагрузку или не заказать больше мощности у сетевой компании, он выбьет снова.") % [net.load, int(net.capacity)],
		"bolt_off", Sim.LVL_BAD,
		[{"text": L.t("Включить"), "hint": L.t("Автомат включён, станки продолжают работу")}, {"text": L.t("Позже"), "hint": L.t("Завод стоит, пока рабочие не сбросят автомат на подстанции")}],
		1, {"cx": cell.x, "cy": cell.y})
	sim.story.on_trip(cell)
	for w in sim.workers:
		if w.present:
			var r := sim.rooms.room_at(w.cell())
			if r and int(room_net.get(r.id, -1)) == net.id:
				Mood.add(sim, w, "breaker")


func reset_source(source_id: int) -> void:
	var ni := int(thing_net.get(source_id, -1))
	if ni < 0:
		tripped_sources.erase(source_id)
		return
	var net := nets[ni]
	net.tripped = false
	net.over_time = 0.0
	for sid in net.sources:
		tripped_sources.erase(sid)


## 1.53: ручное включение вводного автомата — сбрасывает все выбитые сети. Сколько сетей включили.
func reset_all() -> int:
	var n := 0
	for net in nets:
		if net.tripped:
			net.tripped = false
			net.over_time = 0.0
			n += 1
			for sid in net.sources:
				tripped_sources.erase(sid)
	if n > 0:
		_acc = 1.0
		sim.notify(L.t("Автомат включён: завод снова под током."), Sim.LVL_INFO)
	return n


func powered(t: Thing) -> bool:
	var ni := int(thing_net.get(t.id, -1))
	return ni >= 0 and nets[ni].ok()


func connected(t: Thing) -> bool:
	return thing_net.has(t.id)


## Сколько построенных станков не подключено к кабелю.
func unconnected_machines() -> int:
	var n := 0
	for t: Thing in sim.things.values():
		if t.built and t.kind() == "machine" and not thing_net.has(t.id):
			n += 1
	return n


func net_of_thing(t: Thing) -> Net:
	var ni := int(thing_net.get(t.id, -1))
	return nets[ni] if ni >= 0 else null


## Сети с выбитым автоматом: [[id источника, сеть]].
func tripped_list() -> Array:
	var out: Array = []
	for net in nets:
		if net.tripped and not net.sources.is_empty():
			out.append([net.sources[0], net])
	return out


func capacity_total() -> float:
	var c := 0.0
	for net in nets:
		if not net.tripped:
			c += net.capacity
	return c


func any_tripped() -> bool:
	for net in nets:
		if net.tripped:
			return true
	return false


func to_dict() -> Dictionary:
	return {"level": grid_level, "tripped": tripped_sources.keys(), "contract": contract_steps, "upgrade": upgrade,
		"peak": peak_day, "peak_prev": peak_prev, "kd": kwh_day, "kn": kwh_night, "trips": trips_today, "hist": hist}


func from_dict(d: Dictionary) -> void:
	grid_level = int(d.get("level", 0))
	if float(d.get("eta", -1.0)) >= 0.0:   # заявка из старого сохранения — считаем выполненной
		grid_level = mini(grid_level + 1, max_level())
	contract_steps = clampi(int(d.get("contract", 0)), 0, maxi(0, max_contract()))
	upgrade = d.get("upgrade", {})
	peak_day = float(d.get("peak", 0.0))
	peak_prev = float(d.get("peak_prev", 0.0))
	kwh_day = float(d.get("kd", 0.0))
	kwh_night = float(d.get("kn", 0.0))
	trips_today = int(d.get("trips", 0))
	hist = d.get("hist", [])
	tripped_sources.clear()
	for sid in d.get("tripped", []):
		tripped_sources[int(sid)] = true
