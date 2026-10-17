class_name Cat
extends RefCounted
## Заводской кот (1.9): гуляет по цехам, спит в тёплых местах, ест из миски, клянчит в столовой
## и ловит крыс. Люди, которые проходят рядом в перерыв, гладят его — настроение лучше.

const NAMES := ["Васька", "Мурзик", "Барсик", "Тихон", "Пират", "Шпиндель", "Болтик", "Кузя", "Рыжик", "Маркиз"]
const NAMES_F := ["Мурка", "Муська", "Дуся", "Зося", "Фрезочка", "Плюшка"]
const FURS := {"ginger": ["рыжий", "#e2954e"], "gray": ["серый", "#9aa1a8"], "black": ["чёрный", "#4a4a50"],
	"white": ["белый", "#f4f1ea"], "tabby": ["полосатый", "#b08a5e"], "smoke": ["дымчатый", "#7d8590"]}
const SPEED := 2.2   ## клеток в минуту — кот никуда не спешит

var sim: Sim
var name := "Васька"
var female := false
var fur := "ginger"
var pos := Vector2(20.5, 15.5)
var dir := 1                ## 1 — смотрит вправо, -1 — влево
var state := "sit"          ## walk | sit | sleep | eat | beg
var target := Vector2i(-1, -1)
var path: Array[Vector2i] = []
var path_i := 0
var until := 0.0            ## до какой минуты длится текущее занятие
var next_state := "sit"
var fed_day := -1
var fed_times := 0
var since := 1              ## день, когда прибился
var mice := 0
var activity := "Осматривается"
var prey: Dictionary = {}     ## 1.22: за кем охотится (голубь или мышь из sim.fauna)


func _init(s: Sim) -> void:
	sim = s


static func make(s: Sim) -> Cat:
	var c := Cat.new(s)
	c.female = s.rng.randf() < 0.4
	var pool: Array = NAMES_F if c.female else NAMES
	c.name = str(pool[s.rng.randi_range(0, pool.size() - 1)])
	var keys := FURS.keys()
	c.fur = str(keys[s.rng.randi_range(0, keys.size() - 1)])
	c.since = s.day()
	return c


func fur_color() -> Color:
	return Color(str(FURS.get(fur, FURS["ginger"])[1]))


func fur_name() -> String:
	var s := str(FURS.get(fur, FURS["ginger"])[0])
	return s.left(-2) + "ая" if female else s


func title() -> String:
	return ("Кошка " if female else "Кот ") + name


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


# ---------------------------------------------------------------- поведение

func tick(dt: float) -> void:
	if state == "walk":
		_walk(dt)
		# 1.22: добыча ушла — бросить охоту
		if next_state == "hunt" and prey.is_empty():
			next_state = "sit"
		return
	if state == "pounce":
		if sim.minute >= until:
			if sim.fauna:
				sim.fauna.pounce(self)
			state = "sit"
			until = sim.minute + 3.0
		return
	if sim.minute >= until:
		_decide()


## 1.22: подкрасться к добыче (клетка рядом с ней) и прыгнуть.
func hunt(c: Vector2i, kind: String) -> bool:
	var dst := c
	if not sim.world.passable(dst):
		return false
	if _go(dst, "hunt", "Охотится на мышь" if kind == "mouse" else "Подкрадывается к голубю"):
		return true
	return false


func _walk(dt: float) -> void:
	if path.is_empty() or path_i >= path.size():
		_arrive()
		return
	var step := SPEED * dt
	var guard := 0
	while step > 0.0 and guard < 8 and path_i < path.size():
		guard += 1
		var nxt := path[path_i]
		if not sim.world.passable(nxt):
			path.clear()
			_arrive()
			return
		var dest := Vector2(nxt) + Vector2(0.5, 0.5)
		var v := dest - pos
		var ln := v.length()
		if absf(v.x) > 0.05:
			dir = 1 if v.x > 0.0 else -1
		if ln <= step:
			pos = dest
			step -= ln
			path_i += 1
		else:
			pos += v / ln * step
			step = 0.0
	if path_i >= path.size():
		_arrive()


func _go(c: Vector2i, then: String, label: String) -> bool:
	if c.x < 0 or not sim.world.passable(c):
		return false
	var p := sim.world.find_path(cell(), c)
	if p.is_empty():
		return false
	path = p
	path_i = 1
	target = c
	next_state = then
	state = "walk"
	activity = label
	return true


func _arrive() -> void:
	state = next_state
	match state:
		"hunt":
			state = "pounce"
			until = sim.minute + 0.5
			activity = "Прыжок!"
		"sleep":
			until = sim.minute + sim.rng.randf_range(60.0, 160.0) * (1.6 if _night() else 1.0)
			activity = "Спит" + (" у тёплого места" if _warm_near(cell()) else "")
		"eat":
			until = sim.minute + 8.0
			activity = "Ест из миски"
			if sim.day() != fed_day:
				fed_day = sim.day()
				fed_times = 0
			fed_times += 1
		"beg":
			until = sim.minute + sim.rng.randf_range(10.0, 25.0)
			activity = "Клянчит у обедающих"
		_:
			state = "sit"
			until = sim.minute + sim.rng.randf_range(4.0, 18.0)
			activity = ["Умывается", "Смотрит на станок", "Сидит и наблюдает", "Ловит солнечного зайчика"][sim.rng.randi_range(0, 3)]


func _night() -> bool:
	var t := sim.tod()
	return t < 360.0 or t > 1320.0


## Решить, чем заняться дальше.
func _decide() -> void:
	var t := sim.tod()
	var bowl := _bowl()
	# поесть утром и вечером
	if bowl and (t >= 420.0 and t < 600.0 or t >= 1080.0 and t < 1260.0) and (fed_day != sim.day() or fed_times < (1 if t < 600.0 else 2)):
		if _go(_access(bowl), "eat", "Идёт к миске"):
			return
	# в обед — в столовую, клянчить
	if sim.rng.randf() < 0.6:
		var eater := _lunch_eater()
		if eater and _go(_near(eater.cell()), "beg", "Бежит в столовую"):
			return
	# спать: ночью почти всегда, днём — часто
	if sim.rng.randf() < (0.8 if _night() else 0.35):
		var sp := _sleep_spot()
		if sp.x >= 0 and _go(sp, "sleep", "Ищет, где поспать"):
			return
	# погулять
	for k in 8:
		var c := _random_cell()
		if c.x >= 0 and _go(c, "sit", "Гуляет по заводу"):
			return
	state = "sit"
	until = sim.minute + 10.0


func _bowl() -> Thing:
	for th in sim.things_of("cat_bowl"):
		if th.built:
			return th
	return null


func _access(th: Thing) -> Vector2i:
	for d: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 0)]:
		var c := th.cell + d
		if sim.world.in_plot(c) and sim.world.passable(c):
			return c
	return Vector2i(-1, -1)


func _near(c: Vector2i) -> Vector2i:
	for k in 10:
		var n := c + Vector2i(sim.rng.randi_range(-1, 1), sim.rng.randi_range(-1, 1))
		if n != c and sim.world.in_plot(n) and sim.world.passable(n) and sim.world.occ[sim.world.idx(n)] < 0:
			return n
	return Vector2i(-1, -1)


func _lunch_eater() -> Worker:
	for w in sim.workers:
		if w.present and w.task and w.task.kind == "eat" and w.anim == "sit":
			return w
	return null


func _warm_near(c: Vector2i) -> bool:
	for th: Thing in sim.things.values():
		if not th.built:
			continue
		if th.kind() in ["radiator", "boiler"] or th.def_id in ["stove", "sofa"] or (th.kind() == "machine" and th.process() == "heat"):
			if Vector2(th.cell).distance_to(Vector2(c)) <= 2.5:
				return true
	return false


func _sleep_spot() -> Vector2i:
	var cands: Array[Vector2i] = []
	for th: Thing in sim.things.values():
		if th.built and (th.kind() in ["radiator", "boiler", "rest"] or th.def_id in ["stove", "sofa"] or (th.kind() == "machine" and th.process() == "heat")):
			var a := _near(th.cell)
			if a.x >= 0:
				cands.append(a)
	if cands.is_empty():
		return _random_cell()
	return cands[sim.rng.randi_range(0, cands.size() - 1)]


func _random_cell() -> Vector2i:
	var rooms := sim.rooms.list
	if not rooms.is_empty() and sim.rng.randf() < 0.85:
		var r: Rooms.Room = rooms[sim.rng.randi_range(0, rooms.size() - 1)]
		if not r.cells.is_empty():
			var c: Vector2i = r.cells[sim.rng.randi_range(0, r.cells.size() - 1)]
			if sim.world.passable(c) and sim.world.occ[sim.world.idx(c)] < 0:
				return c
	var pr := sim.world.plot
	var c2 := Vector2i(sim.rng.randi_range(pr.position.x + 1, pr.end.x - 2), sim.rng.randi_range(pr.position.y + 1, pr.end.y - 2))
	return c2 if sim.world.passable(c2) else Vector2i(-1, -1)


# ---------------------------------------------------------------- сохранение

func to_dict() -> Dictionary:
	return {"name": name, "female": female, "fur": fur, "x": pos.x, "y": pos.y, "since": since, "mice": mice, "fed": fed_day}


static func from_dict(s: Sim, d: Dictionary) -> Cat:
	var c := Cat.new(s)
	c.name = str(d.get("name", "Васька"))
	c.female = bool(d.get("female", false))
	c.fur = str(d.get("fur", "ginger"))
	c.pos = Vector2(float(d.get("x", 20.5)), float(d.get("y", 15.5)))
	c.since = int(d.get("since", 1))
	c.mice = int(d.get("mice", 0))
	c.fed_day = int(d.get("fed", -1))
	c.until = s.minute
	return c
