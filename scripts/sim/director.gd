class_name Director
extends RefCounted
## 1.40: директор завода — это игрок. Он на заводе с первого дня, и у него есть кабинет: небольшая отдельная
## контора с дверью, линолеумом и зоной «Кабинет директора» (в гараже — справа от бокса, в поле и песочнице — у дороги).
## Развитие идёт через него: пока исследуется ступень, директор сидит за своим столом и «ведёт» её
## (подпись, пузырь с идеей), раз в смену обходит цех. Оклада у директора нет (он хозяин),
## его не увольняют, он не прогуливает и не уходит на пенсию.
## Создаётся своим генератором — кубик игры не трогается.

const OFFICE_FLOOR := 3   ## линолеум (кабинет директора: линолеум или паркет)
const DESK := "director_desk"
## Гараж: контора директора ставится на свободную землю справа от бокса (стена бокса — x = 29).
const GARAGE_ANCHOR := Vector2i(31, 9)


static func of(sim: Sim) -> Worker:
	for w in sim.workers:
		if w.is_director():
			return w
	return null


## Стол директора в оборудованном кабинете директора (или любой построенный стол директора).
static func desk(sim: Sim) -> Thing:
	var any: Thing = null
	for t: Thing in sim.things.values():
		if t.def_id != DESK or not t.built or t.demolish:
			continue
		if sim.rooms.thing_in(t, "director_office"):
			return t
		if any == null or t.id < any.id:
			any = t
	return any


# ================================================================ человек

static func make_person(sim: Sim, rng: RandomNumberGenerator) -> Worker:
	var w := People.make(rng, "director", 0.2)
	w.age = rng.randi_range(38, 54)
	w.wage = 0
	var lk := w.look
	lk["age"] = w.age
	lk["outfit"] = "suit"
	lk["outfit_col"] = str(People.pick(rng, ["#2e3440", "#3b4252", "#3d4a5c", "#44475a"]))
	lk["hat"] = ""
	lk["hat_col"] = "#efefe9"
	lk["phones"] = false
	lk["resp"] = false
	lk["glasses"] = rng.randf() < 0.35
	lk["street"] = "coat"
	lk["street_col"] = str(People.pick(rng, ["#2a2c30", "#3b3f44", "#4a4f5a"]))
	w.kids = 0
	w.skills["manage"] = maxi(w.skill("manage"), 6)
	return w


static func _add(sim: Sim, w: Worker, rng: RandomNumberGenerator) -> void:
	w.id = sim.new_id()
	w.hired_day = sim.day()
	w.exit_cell = Vector2i(0, sim.world.sidewalk_row) if rng.randf() < 0.5 else Vector2i(sim.world.w - 1, sim.world.sidewalk_row)
	w.arrive_at = Defs.b("shift_start") - rng.randf_range(20.0, 45.0)
	w.shift = 0
	sim.workers.append(w)
	sim.worker_rev += 1
	Mood.refresh(sim, w)


## Новая игра: кабинет и сам директор.
static func setup(sim: Sim, seed_value: int) -> void:
	if of(sim) != null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 4049
	build_office(sim)
	var w := make_person(sim, rng)
	_add(sim, w, rng)
	w.add_history(sim.day(), L.t("Открыл своё дело. Директор завода — это вы."))


## Старое сохранение: директора не было — он приходит (кабинет строит игрок).
static func ensure(sim: Sim) -> void:
	if of(sim) != null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.next_id * 13 + 7
	var w := make_person(sim, rng)
	_add(sim, w, rng)
	w.add_history(sim.day(), L.t("Директор завода — это вы."))
	if desk(sim) == null:
		sim.notify(L.t("На заводе появился директор — это вы. Ему нужен кабинет: помещение с линолеумом или паркетом, стол директора (Объекты → Офис), зона «Кабинет директора»."), Sim.LVL_INFO)


# ================================================================ кабинет

## Тесты со своей стройкой на месте конторы могут её отключить.
static var skip_office := false

static func build_office(sim: Sim) -> bool:
	if skip_office:
		return false
	if desk(sim) != null:
		return true
	if sim.scenario == "garage":
		return _detached(sim, GARAGE_ANCHOR)   # справа от бокса, подальше от ворот и проезда
	return _detached(sim, Vector2i(sim.gate_x - 10, sim.world.plot.end.y - 6))


## Чистая земля под кабинет: участок, своя земля, без построек, зон, проездов.
static func _ground_free(sim: Sim, c: Vector2i) -> bool:
	var w := sim.world
	if not w.in_plot(c):
		return false
	var i := w.idx(c)
	if w.flr[i] > 0 or w.wall[i] != World.W_NONE or w.occ[i] >= 0 or w.area[i] != 0:
		return false
	if w.bp_floor[i] != World.BP_NONE or w.bp_wall[i] != World.BP_NONE:
		return false
	if w.owned.size() == w.w * w.h and w.owned[i] == 0:
		return false
	return true


## Отдельная контора 6×4 (внутри 4×2): дверью вниз, окном наверх, на свободной земле ближе к anchor.
static func _detached(sim: Sim, anchor: Vector2i) -> bool:
	var w := sim.world
	var size := Vector2i(6, 4)
	var best := Vector2i(-1, -1)
	var bs := INF
	for y in range(w.plot.position.y + 1, w.plot.end.y - size.y - 1):
		for x in range(w.plot.position.x + 1, w.plot.end.x - size.x - 1):
			if x + size.x >= sim.gate_x - 3 and x <= sim.gate_x + 6:
				continue   # проезд к воротам не загораживаем
			var sc := absf(float(x - anchor.x)) + absf(float(y - anchor.y)) * 1.5
			if sc >= bs:
				continue
			var ok := true
			for yy in range(y - 1, y + size.y + 1):
				for xx in range(x - 1, x + size.x + 1):
					if not _ground_free(sim, Vector2i(xx, yy)):
						ok = false
						break
				if not ok:
					break
			if ok:
				bs = sc
				best = Vector2i(x, y)
	if best.x < 0:
		return false
	var rr := Rect2i(best, size)
	for yy2 in range(rr.position.y, rr.end.y):
		for xx2 in range(rr.position.x, rr.end.x):
			w.flora[w.idx(Vector2i(xx2, yy2))] = 0
	w.flora_rev += 1
	var door := Vector2i(rr.end.x - 2, rr.end.y - 1)
	Scenario.box(sim, rr, OFFICE_FLOOR, [door], [Vector2i(rr.position.x + 2, rr.position.y)])
	w.refresh_all()
	sim.rooms.update()
	var inner := rr.position + Vector2i(1, 1)
	Scenario.assign_at(sim, inner, "director_office")
	Scenario.put(sim, DESK, inner)
	Scenario.put(sim, "plant", inner + Vector2i(3, 0))
	Scenario.put(sim, "extinguisher", inner + Vector2i(2, 0))   # не у двери: проход к столу свободен
	sim.rooms.update()
	return desk(sim) != null


## Отдельная контора директора (поле, песочница): [стен, объектов] — для проверок «пустого участка».
static func office_counts(sim: Sim) -> Vector2i:
	var d := desk(sim)
	if d == null:
		return Vector2i.ZERO
	var si := sim.rooms.space_of_thing(d)
	if si < 0 or sim.rooms.space_rooms(si).size() != 1:
		return Vector2i.ZERO   # кабинет внутри другого помещения — своих стен нет
	var sp: Rooms.Space = sim.rooms.spaces[si]
	var r := sp.rect.grow(1)
	var walls := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if WallKinds.is_room_wall(sim.world.wall[sim.world.idx(Vector2i(x, y))]):
				walls += 1
	return Vector2i(walls, sp.things.size())


# ================================================================ работа

## Чем директор занят за столом (как и все подписи задач — на языке игры; на ход сима не влияет).
static func desk_label(sim: Sim, k: int) -> String:
	if sim.dev.cur != "":
		return L.t("Ведёт развитие: «%s»") % Develop.sname(Develop.step_def(sim.dev.cur))
	return L.t(str(["Руководит заводом", "Подписывает договоры", "Звонит заказчикам", "Смотрит отчёты за неделю"][k % 4]))


## Развитие началось — директор садится за стол и берётся за него.
static func on_develop(sim: Sim) -> void:
	var w := of(sim)
	if w == null or not w.present or w.task == null:
		return
	if w.task.kind in ["office", "wander", "patrol"]:
		sim.brain.abort(w)
