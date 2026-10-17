class_name Production
extends RefCounted
## Правила маршрутов: что станок принимает на вход, что расходует на операцию,
## куда идёт деталь после операции. Общие для планировщика и поведения рабочих.

var sim: Sim


func _init(s: Sim) -> void:
	sim = s


## Можно ли положить груз во вход станка под его текущее задание.
func input_ok(it: Item, m: Thing) -> bool:
	if m.product == "":
		return false
	var p := m.product
	if m.job_step == 0:
		if Defs.is_assembly(p):
			return it.kind == "part" and it.q == "ok" and Defs.components(p).has(it.def_id)
		return it.kind == "mat" and it.def_id == str(Defs.products[p].get("material", ""))
	return it.kind == "part" and it.q == "wip" and it.def_id == p and it.step == m.job_step


## Каких входов не хватает станку на одну операцию: {ключ: сколько} (ключ — id материала или изделия).
func missing_inputs(m: Thing) -> Dictionary:
	var out := {}
	if m.product == "":
		return out
	var p := m.product
	var have := {}
	for iid in sim.slot_ids(m, 0):
		var it: Item = sim.items.get(iid)
		if it:
			have[it.def_id] = int(have.get(it.def_id, 0)) + 1
	if m.job_step == 0:
		if Defs.is_assembly(p):
			var comps := Defs.components(p)
			for c in comps.keys():
				var need := int(comps[c]) - int(have.get(c, 0))
				if need > 0:
					out[c] = need
		else:
			var mat := str(Defs.products[p].get("material", ""))
			var need2 := Defs.mat_qty(p) - int(have.get(mat, 0))
			if need2 > 0:
				out[mat] = need2
	else:
		if int(have.get(p, 0)) < 1:
			out[p] = 1
	return out


## Хватает ли входов для запуска операции (печь — хотя бы одна деталь).
func can_start(m: Thing) -> bool:
	if m.product == "":
		return false
	if m.is_batch():
		return sim.count_slot(m, 0) > 0
	return missing_inputs(m).is_empty()


## Забрать из входа станка то, что расходуется на одну операцию. Возвращает изъятые грузы.
func take_inputs(m: Thing) -> Array[Item]:
	var out: Array[Item] = []
	var p := m.product
	var want := {}
	if m.job_step == 0:
		if Defs.is_assembly(p):
			want = Defs.components(p).duplicate()
		else:
			want[str(Defs.products[p].get("material", ""))] = Defs.mat_qty(p)
	else:
		want[p] = 1
	for iid in sim.slot_ids(m, 0).duplicate():
		var it: Item = sim.items.get(iid)
		if it == null:
			continue
		var k := it.def_id
		if int(want.get(k, 0)) > 0:
			want[k] = int(want[k]) - 1
			out.append(it)
	return out


## Сколько расходника уйдёт на операцию.
func cons_need(m: Thing) -> Array:
	var pr: Dictionary = Defs.processes.get(m.process(), {})
	var cname := str(pr.get("cons", ""))
	if cname == "":
		return ["", 0.0]
	var use := float(pr.get("cons_use", 1.0))
	var o := Defs.op(m.product, m.job_step)
	if o.has("cons"):
		use = float(o["cons"])
	if cname == "tools" and not sim.rooms.of_type("toolroom").is_empty():
		use *= Defs.b("toolroom_k")
	use *= float(m.machine_def().get("cons_k", 1.0))   # 1.16: порошковая камера экономит краску
	return [cname, use]


func has_cons(m: Thing) -> bool:
	var c := cons_need(m)
	if str(c[0]) == "":
		return true
	return float(sim.cons.get(c[0], 0.0)) >= float(c[1]) - 0.001


## Изделие тяжёлое и в помещении станка нет кран-балки — работа медленнее.
func crane_k(m: Thing) -> float:
	if m.product == "" or not bool(Defs.products.get(m.product, {}).get("heavy", false)):
		return 1.0
	var r := sim.rooms.room_of_thing(m)
	if r and crane_in(r) != null:
		return 1.0
	return Defs.b("crane_heavy_k")


## Кран-балка, которая обслуживает помещение (или null).
func crane_in(r: Rooms.Room) -> Thing:
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "crane" and r and sim.rooms.space_id_at(t.cell) == r.space:
			return t   # кран-балка обслуживает весь зал, во всех его зонах
	return null


## Кран-балка над клеткой (тот же зал) или null (1.14).
func crane_at(c: Vector2i) -> Thing:
	var sid := sim.rooms.space_id_at(c)
	if sid < 0:
		return null
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "crane" and sim.rooms.space_id_at(t.cell) == sid:
			return t
	return null


static func is_heavy(it: Item) -> bool:
	return it != null and it.kind == "part" and bool(Defs.products.get(it.def_id, {}).get("heavy", false))


## Станок готов принять этот груз прямо сейчас (задание совпадает, есть место, для сборки — нужен этот компонент).
func wants(m: Thing, it: Item) -> bool:
	if m.demolish or m.broken or not m.enabled or not input_ok(it, m):
		return false
	m.ensure_incoming()
	var room := m.slot_cap(0) - sim.count_slot(m, 0) - int(m.incoming[0])
	if room <= 0:
		return false
	if m.job_step == 0 and Defs.is_assembly(m.product):
		var have := 0
		for iid in sim.slot_ids(m, 0):
			var o: Item = sim.items.get(iid)
			if o and o.def_id == it.def_id:
				have += 1
		# не больше, чем на два узла, и не больше, чем ещё нужно собрать
		var units := clampi(sim.planner.need(m.product), 1, 2)
		return have + int(m.incoming[0]) < int(Defs.components(m.product).get(it.def_id, 0)) * units
	return true


## Ближайший станок, который ждёт такую деталь.
func machine_for(it: Item) -> Thing:
	var best: Thing = null
	var bd := INF
	for m in sim.things_of("machine"):
		if not wants(m, it):
			continue
		var d := Vector2(m.cell - sim.item_cell(it)).length()
		if d < bd:
			bd = d
			best = m
	return best


## Процессы, для которых на заводе есть хотя бы один станок: {передел: до какого размера деталей (0..2)}.
func processes_available() -> Dictionary:
	var out := {}
	for m in sim.things_of("machine"):
		var pr := m.process()
		out[pr] = maxi(int(out.get(pr, -1)), m.part_rank())
	return out


## 1.16: есть ли станок этого передела под размер изделия.
static func size_ok(p: String, pr: String, avail: Dictionary) -> bool:
	return avail.has(pr) and int(avail[pr]) >= Defs.product_rank(p)


## Какой размер деталей нужен переделу для изделия (с деталями для сборки); -1 — передел не нужен.
static func need_rank(p: String, pr: String) -> int:
	var r := -1
	for o: Dictionary in Defs.route(p):
		if str(o["op"]) == pr:
			r = maxi(r, Defs.product_rank(p))
	for c in Defs.components(p).keys():
		r = maxi(r, need_rank(str(c), pr))
	return r


## Название передела для списка «чего не хватает»: «токарная» или «токарная (для крупных деталей)».
func missing_name(p: String, pr: String, avail: Dictionary) -> String:
	var nm := Defs.process_name(pr).to_lower()
	if avail.has(pr):
		nm += " (для %s деталей)" % Defs.SIZE_GEN[clampi(need_rank(p, pr), 0, 2)]
	return nm


## Можно ли сделать изделие на имеющемся оборудовании (включая детали для сборки и размеры).
func can_make(p: String, avail: Dictionary = {}) -> bool:
	if avail.is_empty():
		avail = processes_available()
	for o: Dictionary in Defs.route(p):
		if not size_ok(p, str(o["op"]), avail):
			return false
	for c in Defs.components(p).keys():
		if not can_make(str(c), avail):
			return false
	return true


## Кто может работать на станке этого процесса.
func can_operate(w: Worker, m: Thing) -> bool:
	var pr: Dictionary = Defs.processes.get(m.process(), {})
	var sk := op_skill(w, m)
	if w.is_itr():
		return false
	var need := int(m.machine_def().get("min_skill", 1))
	if m.product != "":
		need = maxi(need, int(Defs.op(m.product, m.job_step).get("skill", 1)))
	if w.skill(sk) < need:
		return false
	return w.prof == str(pr.get("prof", "")) or w.skill(sk) >= 3 or (sk == "cnc" and w.prof == "cnc_operator")


## 1.22: каким навыком работает человек на этом станке: оператор ЧПУ на станке с ЧПУ — «Работа на ЧПУ».
static func op_skill(w: Worker, m: Thing) -> String:
	if w != null and w.prof == "cnc_operator" and m.is_cnc():
		return "cnc"
	return str(Defs.processes.get(m.process(), {}).get("skill", "turning"))


func is_operator_for(w: Worker, process: String) -> bool:
	if w.is_itr():
		return false
	var pr: Dictionary = Defs.processes.get(process, {})
	var sk := str(pr.get("skill", "turning"))
	return w.prof == str(pr.get("prof", "")) or w.skill(sk) >= 3
