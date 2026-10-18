class_name Scenario
extends RefCounted
## Стартовые сценарии. Этап 1: «Гараж» — бокс в промзоне, старый станок, три человека.

const GARAGE := Rect2i(14, 8, 16, 12)  ## стены бокса (включая контур)
const ANNEX := Rect2i(7, 11, 8, 9)     ## 1.15: пристройка слева — столовая, туалет, бытовка (x=14 — общая стена)
const TECH := Rect2i(1, 15, 7, 5)      ## 1.18: техпомещение за туалетом (x=7 — общая стена): подстанция и насосная


## Новая игра: сценарий, профиль завода, рассказчик. opts — для песочницы и обучения.
static func new_game(scn: String, profile: String, story_mode: String, seed_value: int = 0, opts: Dictionary = {}) -> Sim:
	var sim: Sim
	flora_inside = bool(opts.get("flora", false))
	match scn:
		"field":
			sim = _new_field(seed_value, story_mode, profile)
		"sandbox":
			sim = _new_sandbox(seed_value, story_mode, profile, opts)
		_:
			sim = new_garage(seed_value, story_mode, profile)
			if bool(opts.get("tutorial", false)):
				sim.progress.tutorial = 0
	if bool(opts.get("lots", false)):
		add_lots(sim)
	if flora_inside:
		plant_inside(sim)
	flora_inside = false
	sim.world.refresh_all()
	# 1.17: название и эмблема завода — из окна «Ваш завод»; без него — случайные (свой генератор, не трогаем rng игры)
	var cd: Variant = opts.get("company", {})
	if cd is Dictionary and not (cd as Dictionary).is_empty():
		Company.set_data(sim, str(cd.get("name", "")), cd.get("emblem", Company.default_emblem()))
	else:
		var crng := RandomNumberGenerator.new()
		crng.seed = seed_value * 7 + 11
		Company.set_data(sim, Company.random_name(crng), Company.random_emblem(crng, sim.progress.profile))
	sim.progress.start_staff = sim.workers.size()
	sim.progress.start_day = sim.day()
	sim.progress.morning()
	Workplace.auto_assign(sim)   # 1.15: станок и верстак сразу закреплены за своими людьми
	sim.career.init_calendar()
	# 1.18: сразу считаем сеть, воду и помещения — насосная качает, туалет в порядке с первой минуты
	sim.rooms.update()
	sim.power.update_topology()
	sim.power.tick(0.0)
	sim.rooms.update()
	return sim


## Общая заготовка: симуляция, участок w×h с забором, тротуаром и дорогой внизу.
static func _base(seed_value: int, scn: String, profile: String, story_mode: String, mw: int, mh: int) -> Sim:
	var sim := Sim.new()
	if seed_value != 0:
		sim.rng.seed = seed_value
		sim.social.rng.seed = seed_value + 7177   # 1.26: разговоры тоже от зерна игры (раньше — от случайного)
	sim.scenario = scn
	sim.story.mode = story_mode if Story.MODES.has(story_mode) else "market"
	sim.progress.profile = profile if Defs.profiles.has(profile) and not bool(Defs.profiles[profile].get("locked", false)) else "mech"
	var sd: Dictionary = Defs.scenarios.get(scn, {})
	sim.money = float(sd.get("money", Defs.b("start_money")))
	sim.reputation = float(sd.get("reputation", Defs.b("start_reputation")))
	sim.progress.stage = int(sd.get("stage", 1))
	sim.minute = 7.0 * 60.0
	var w := sim.world
	w.setup(mw, mh)
	sim.season.setup_map()
	w.plot = Rect2i(1, 1, mw - 2, mh - 8)
	w.sidewalk_row = mh - 6
	w.road_row = mh - 4
	sim.gate_x = int(mw / 2) - 2
	return sim


static func new_garage(seed_value: int = 0, story_mode: String = "market", profile: String = "mech") -> Sim:
	var sim := _base(seed_value, "garage", profile, story_mode, Sim.MAP_W, Sim.MAP_H)
	var w := sim.world
	sim.gate_x = 22
	_lay_ground(sim, Rect2i(TECH.position.x, GARAGE.position.y, GARAGE.end.x - TECH.position.x, GARAGE.size.y))
	_build_garage(sim)
	_build_annex(sim)
	_build_tech(sim, TECH, Vector2i(4, 19))
	_furnish(sim)
	_furnish_annex(sim)
	_light_and_water_garage(sim)
	_hire_crew(sim)
	_start_orders(sim)
	sim.refresh_candidates()
	w.refresh_all()
	sim.rooms.update()
	var gr := sim.rooms.room_at(Vector2i(20, 12))
	if gr:
		sim.rooms.assign(gr, "workshop")
	# 1.15: быт — в пристройке, каждая комнатка своей зоной и полностью укомплектована
	assign_at(sim, Vector2i(12, 12), "canteen")
	assign_at(sim, Vector2i(9, 17), "wc")
	assign_at(sim, Vector2i(12, 17), "locker")
	assign_at(sim, TECH.position + Vector2i(3, 3), "tech_room")
	sim.power.update_topology()
	add_yard_zones(sim)   # 1.29: обязательные зоны у ворот, поддоны заготовок
	sim.events.clear()
	sim.notify("Добро пожаловать в «Промзону»! У вас бокс в промзоне, старый токарный станок и трое работников.", Sim.LVL_GOOD)
	sim.notify("Первый заказ уже принят: 12 втулок для ИП Сидоренко. Металл лежит на стеллаже.", Sim.LVL_INFO)
	sim.notify("У ворот отмечены зона разгрузки (сюда фургоны сгружают металл — на поддоны заготовок) и зона отгрузки (сюда несут готовый заказ, отсюда его грузит машина клиента).", Sim.LVL_INFO)
	return sim


static func _lay_ground(sim: Sim, keep_clear: Rect2i = GARAGE, drive: Rect2i = Rect2i(19, 20, 8, 10), grass_n: int = 34) -> void:
	var w := sim.world
	var fence_y := w.plot.end.y
	for y in w.h:
		for x in w.w:
			var i := w.idx(Vector2i(x, y))
			if y <= fence_y:
				w.ground[i] = World.Ground.DIRT
			elif y == w.sidewalk_row:
				w.ground[i] = World.Ground.SIDEWALK
			elif y <= w.sidewalk_row + 4:
				w.ground[i] = World.Ground.ROAD
			else:
				w.ground[i] = World.Ground.GRASS
	# пятна травы
	for k in grass_n:
		var cx := sim.rng.randi_range(1, w.plot.end.x - 1)
		var cy := sim.rng.randi_range(1, fence_y - 1)
		var r := sim.rng.randi_range(1, 3)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(cx + dx, cy + dy)
				if not w.in_plot(c) or Vector2(dx, dy).length() > r + 0.3:
					continue
				if keep_clear.grow(1).has_point(c):
					continue
				w.ground[w.idx(c)] = World.Ground.GRASS
	# заасфальтированный подъезд от ворот участка
	for y in range(drive.position.y, fence_y + 1):
		for x in range(drive.position.x, drive.end.x):
			if w.inb(Vector2i(x, y)):
				w.ground[w.idx(Vector2i(x, y))] = World.Ground.ASPHALT
	if keep_clear.size.x > 0:
		for x in range(keep_clear.position.x - 1, keep_clear.end.x + 1):
			if w.in_plot(Vector2i(x, keep_clear.end.y)):
				w.ground[w.idx(Vector2i(x, keep_clear.end.y))] = World.Ground.ASPHALT
	# забор по краю участка
	for x in w.w:
		w.wall[w.idx(Vector2i(x, 0))] = World.W_FENCE
		w.wall[w.idx(Vector2i(x, fence_y))] = World.W_FENCE
	for y in fence_y + 1:
		w.wall[w.idx(Vector2i(0, y))] = World.W_FENCE
		w.wall[w.idx(Vector2i(w.w - 1, y))] = World.W_FENCE
	for x in range(sim.gate_x, sim.gate_x + 4):
		w.wall[w.idx(Vector2i(x, fence_y))] = World.W_FENCE_GATE
		w.ground[w.idx(Vector2i(x, fence_y))] = World.Ground.ASPHALT
	_plant(sim, keep_clear, drive)


## Деревья и кусты (1.13): аллея вдоль дороги, заросли на соседних участках. На своём
## участке — только в новой игре из меню (opts.flora), и подальше от построек и подъезда.
static var flora_inside := false


static func _plant(sim: Sim, _keep_clear: Rect2i, _drive: Rect2i) -> void:
	var w := sim.world
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.rng.seed + 1307
	var fence_y := w.plot.end.y
	# аллея по ту сторону дороги
	var y_alley := w.sidewalk_row + 5
	if y_alley < w.h:
		var x := rng.randi_range(0, 2)
		while x < w.w:
			w.flora[w.idx(Vector2i(x, y_alley))] = rng.randi_range(1, 3)
			if x + 2 < w.w and rng.randf() < 0.5:
				w.flora[w.idx(Vector2i(x + 2, y_alley))] = rng.randi_range(4, 5)
			x += rng.randi_range(4, 6)


## Свой участок (новая игра из меню): редкие деревья и кусты на траве — подальше от построек,
## асфальта, сетей и ворот. Сажаем, когда сценарий уже построен.
static func plant_inside(sim: Sim) -> void:
	var w := sim.world
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.rng.seed + 2711
	var fence_y := w.plot.end.y
	var gate := Rect2i(sim.gate_x - 3, fence_y - 5, 10, 6)
	for y in range(w.plot.position.y + 1, fence_y - 1):
		for x in range(w.plot.position.x + 1, w.plot.end.x - 1):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			if w.ground[i] != World.Ground.GRASS or gate.has_point(c) or not w.in_plot(c):
				continue
			var busy := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var n := c + Vector2i(dx, dy)
					if not w.inb(n):
						continue
					var j := w.idx(n)
					if w.flr[j] != 0 or (w.wall[j] != World.W_NONE and not WallKinds.is_fence(w.wall[j])) or w.occ[j] >= 0 or w.ground[j] == World.Ground.ASPHALT \
							or w.cable[j] != 0 or w.pipe[j] != 0 or w.flora[j] != 0:
						busy = true
						break
				if busy:
					break
			if busy:
				continue
			var p := rng.randf()
			if p < 0.06:
				w.flora[i] = rng.randi_range(1, 3)
			elif p < 0.10:
				w.flora[i] = rng.randi_range(4, 5)
	w.flora_rev += 1


## Соседние участки (1.13): слева, справа и сзади (сверху) — пустыри в разы шире прежнего,
## заросшие деревьями. Построенный сценарий переносится в середину большой карты.
## Порядок покупки: справа, слева, сзади (Развитие → Земля).
static func add_lots(sim: Sim) -> void:
	var w := sim.world
	var mw := w.w
	var fy := w.plot.end.y                       # ряд забора у дороги
	var side := clampi(int(round(mw * 0.42)), 16, 28)
	var top := clampi(int(round(fy * 0.5)), 10, 18)
	var ox := side + 1
	var oy := top + 1
	sim.embed(ox, oy, mw + 2 * ox, w.h + oy)
	w = sim.world
	var fy2 := fy + oy
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.rng.seed + 4049
	# земля новых участков и продолжение тротуара, дороги и газона
	for y in w.h:
		for x in w.w:
			var inside := x >= ox and x < ox + mw and y >= oy
			if inside:
				continue
			var i := w.idx(Vector2i(x, y))
			if y <= fy2:
				w.ground[i] = World.Ground.GRASS
			elif y == w.sidewalk_row:
				w.ground[i] = World.Ground.SIDEWALK
			elif y <= w.sidewalk_row + 4:
				w.ground[i] = World.Ground.ROAD
			else:
				w.ground[i] = World.Ground.GRASS
	var own := w.plot
	var lots: Array[Rect2i] = [
		Rect2i(own.end.x + 1, own.position.y, w.w - 2 - own.end.x, own.size.y),   # справа
		Rect2i(1, own.position.y, own.position.x - 2, own.size.y),                  # слева
		Rect2i(1, 1, w.w - 2, own.position.y - 2)]                                  # сзади
	var per_cell := Defs.b("lot_price_cell")
	if per_cell <= 0.0:
		per_cell = 1200.0
	w.lots.clear()
	for r: Rect2i in lots:
		w.lots.append({"rect": [r.position.x, r.position.y, r.size.x, r.size.y], "price": roundf(float(r.size.x * r.size.y) * per_cell / 10000.0) * 10000.0, "bought": false})
		# проплешины утоптанной земли
		for k in int(r.get_area() / 90):
			var cx := rng.randi_range(r.position.x, r.end.x - 1)
			var cy := rng.randi_range(r.position.y, r.end.y - 1)
			var rr := rng.randi_range(1, 2)
			for dy in range(-rr, rr + 1):
				for dx in range(-rr, rr + 1):
					var c := Vector2i(cx + dx, cy + dy)
					if r.has_point(c) and Vector2(dx, dy).length() <= rr + 0.3:
						w.ground[w.idx(c)] = World.Ground.DIRT
		# заросли: у забора гуще
		for y2 in range(r.position.y, r.end.y):
			for x2 in range(r.position.x, r.end.x):
				var c2 := Vector2i(x2, y2)
				var edge := x2 <= r.position.x + 1 or x2 >= r.end.x - 2 or y2 <= r.position.y + 1
				var p := rng.randf()
				# 1.18: реже — чужая земля не забита лесом (и карта легче)
				if p < (0.08 if edge else 0.025):
					w.flora[w.idx(c2)] = rng.randi_range(1, 3)
				elif p < (0.13 if edge else 0.05):
					w.flora[w.idx(c2)] = rng.randi_range(4, 5)
	# заборы: по краю карты, между участками и у дороги
	for x3 in w.w:
		w.wall[w.idx(Vector2i(x3, 0))] = World.W_FENCE
		if x3 < ox or x3 >= ox + mw:
			w.wall[w.idx(Vector2i(x3, oy))] = World.W_FENCE   # между задним участком и боковыми
		if w.wall[w.idx(Vector2i(x3, fy2))] == World.W_NONE:
			w.wall[w.idx(Vector2i(x3, fy2))] = World.W_FENCE
	for y3 in fy2 + 1:
		w.wall[w.idx(Vector2i(0, y3))] = World.W_FENCE
		w.wall[w.idx(Vector2i(w.w - 1, y3))] = World.W_FENCE
	# у дороги вдоль соседних участков деревья не сажаем — чтобы табличку было видно
	for x4 in w.w:
		for y4 in range(fy2 - 2, fy2):
			if not own.has_point(Vector2i(x4, y4)):
				w.flora[w.idx(Vector2i(x4, y4))] = 0
	w.flora_rev += 1
	w.refresh_all()
	sim.rooms.update()


static func _build_garage(sim: Sim) -> void:
	var w := sim.world
	var g := GARAGE
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			var edge := x == g.position.x or x == g.end.x - 1 or y == g.position.y or y == g.end.y - 1
			w.flr[i] = 1
			if edge:
				w.wall[i] = World.W_BRICK
	var bottom := g.end.y - 1
	for x in [20, 21, 22]:
		w.wall[w.idx(Vector2i(x, bottom))] = World.W_GATE
	w.wall[w.idx(Vector2i(26, bottom))] = World.W_DOOR
	for x in [17, 21, 25]:
		w.wall[w.idx(Vector2i(x, g.position.y))] = World.W_WINDOW
	w.wall[w.idx(Vector2i(g.position.x, 13))] = World.W_WINDOW


## Пристройка к боксу (1.15): сверху столовая, снизу туалет и бытовка за перегородкой.
## Столовая и бытовка открываются в бокс, туалет — из бытовки.
static func _build_annex(sim: Sim) -> void:
	var w := sim.world
	var a := ANNEX
	box(sim, Rect2i(a.position.x, a.position.y, a.size.x, 5), 3, [], [Vector2i(7, 13), Vector2i(10, 11)])
	box(sim, Rect2i(a.position.x, a.position.y + 4, 4, 5), 5)
	box(sim, Rect2i(a.position.x + 3, a.position.y + 4, 5, 5), 3)
	for x in range(8, 14):
		w.wall[w.idx(Vector2i(x, 15))] = World.W_PARTITION
	for y in range(16, 19):
		w.wall[w.idx(Vector2i(10, y))] = World.W_PARTITION
	w.wall[w.idx(Vector2i(14, 13))] = World.W_DOOR   # столовая ↔ бокс (было окно)
	w.wall[w.idx(Vector2i(14, 17))] = World.W_DOOR   # бытовка ↔ бокс
	w.wall[w.idx(Vector2i(10, 17))] = World.W_DOOR   # туалет ↔ бытовка


## 1.18: техпомещение 5×3 внутри: трансформаторная подстанция, насосная станция, лампа, огнетушитель.
static func _build_tech(sim: Sim, r: Rect2i, door: Vector2i) -> void:
	box(sim, r, 1, [door])
	sim.world.wall[sim.world.idx(door)] = World.W_METAL_DOOR
	var o := r.position
	put(sim, "substation", o + Vector2i(1, 1))
	put(sim, "pump_house", o + Vector2i(4, 1))
	put(sim, "water_heater", o + Vector2i(4, 3))   # 1.20: электрокотёл отопления у насосной
	put(sim, "lamp_bulb", o + Vector2i(3, 1))
	put(sim, "extinguisher", o + Vector2i(5, 3))


static func _furnish_annex(sim: Sim) -> void:
	# столовая: холодильник, чайник, стол на четверых, огнетушитель
	sim.place_thing("fridge", Vector2i(8, 12), true, false)
	sim.place_thing("kettle", Vector2i(9, 12), true, false)
	sim.place_thing("dining_table", Vector2i(10, 13), true, false)
	for c in [Vector2i(10, 12), Vector2i(11, 12), Vector2i(10, 14), Vector2i(11, 14)]:
		sim.place_thing("chair", c, true, false)
	sim.place_thing("plant", Vector2i(8, 14), true, false)
	sim.place_thing("extinguisher", Vector2i(13, 14), true, false)
	# туалет: кабинка входом вниз и раковина
	sim.place_thing("toilet", Vector2i(8, 16), true, false)
	sim.place_thing("sink", Vector2i(9, 16), true, false)
	# бытовка: два шкафчика на двоих, скамейка, огнетушитель
	sim.place_thing("locker2", Vector2i(11, 16), true, false)
	sim.place_thing("locker2", Vector2i(12, 16), true, false)
	sim.place_thing("extinguisher", Vector2i(13, 16), true, false)
	sim.place_thing("bench", Vector2i(11, 18), true, false)


static func _furnish(sim: Sim) -> void:
	var lathe := sim.place_thing("lathe", Vector2i(16, 9), true, false)
	lathe.condition = 78.0
	sim.place_thing("workbench", Vector2i(21, 9), true, false)
	var rack := sim.place_thing("rack", Vector2i(15, 14), true, false)
	sim.place_thing("rack", Vector2i(15, 15), true, false)
	sim.place_thing("qc_table", Vector2i(23, 13), true, false)
	sim.place_thing("pallet", Vector2i(27, 13), true, false)
	sim.place_thing("pallet", Vector2i(27, 14), true, false)
	sim.place_thing("scrap_bin", Vector2i(27, 16), true, false)
	sim.place_thing("extinguisher", Vector2i(15, 11), true, false)
	sim.place_thing("plant", Vector2i(28, 18), true, false)
	sim.place_thing("bench", Vector2i(23, 21), true, false)
	sim.place_thing("urn", Vector2i(27, 21), true, false)
	for n in 18:
		var it := sim.new_item("mat", "bar45", "raw")
		sim.put_in_thing(it, rack, 0 if n < 12 else 1)


static func _hire_crew(sim: Sim) -> void:
	var a := People.make(sim.rng, "turner")
	a.first = "Виктор"
	a.nick = "Батя"
	a.nick_why = "Сорок лет у станка, всех молодых учил — на старом заводе иначе и не звали."
	a.last = "Громов"
	a.female = false
	a.age = 58
	a.skills = {"turning": 6, "qc": 3, "build": 3, "haul": 3, "electric": 3}
	a.traits = ["veteran", "smoker"]
	a.look = {"skin": 2, "hair": "buzz", "hair_col": "#a3a39c", "beard": "mustache", "glasses": false,
		"phones": false, "bulk": 1.0, "body": "stout", "h": 1.0, "hat": "cap", "hat_col": "#26324a", "outfit": "overall", "outfit_col": "#3d5a7a",
		"street": "jacket", "street_col": "#3b3f44"}
	a.wage = People.wage_for(a)
	sim.add_worker(a)
	a.add_history(sim.day(), "Сорок лет у станка. Пришёл, потому что «без дела скучно».")

	var b := People.make(sim.rng, "qc")
	b.first = "Ольга"
	b.last = "Савина"
	b.female = true
	b.age = 44
	b.skills = {"turning": 1, "qc": 6, "build": 1, "haul": 3, "electric": 0}
	b.traits = ["neat"]
	b.look = {"skin": 0, "hair": "bun", "hair_col": "#3a2418", "beard": "", "glasses": true,
		"phones": false, "bulk": 1.0, "body": "normal", "fem": true, "h": 0.96, "hat": "", "hat_col": "#ffffff", "outfit": "coat", "outfit_col": "#e9ecec",
		"street": "coat", "street_col": "#6a3a3a"}
	b.wage = People.wage_for(b)
	sim.add_worker(b)
	b.add_history(sim.day(), "Двадцать лет в ОТК на моторном заводе.")

	var c := People.make(sim.rng, "laborer")
	c.first = "Денис"
	c.last = "Королёв"
	c.female = false
	c.age = 23
	c.skills = {"turning": 1, "qc": 1, "build": 6, "haul": 7, "electric": 1}
	c.traits = ["handy", "night_owl"]
	c.look = {"skin": 1, "hair": "short", "hair_col": "#6b4428", "beard": "", "glasses": false,
		"phones": true, "bulk": 1.0, "body": "thin", "h": 1.04, "hat": "cap", "hat_col": "#26324a", "outfit": "shirt", "outfit_col": "#8a3e3a",
		"street": "jacket", "street_col": "#2f3a4a"}
	c.wage = People.wage_for(c)
	sim.add_worker(c)
	c.add_history(sim.day(), "После армии. Руки растут откуда надо.")


static func _start_orders(sim: Sim) -> void:
	sim.orders.morning()
	var o := sim.orders.make_offer("bushing")
	o["client"] = "ИП Сидоренко"
	o["qty"] = 12
	o["price"] = 1400
	o["deadline"] = 3.0 * 1440.0 + Defs.b("shift_end")
	o["lead"] = 3
	o["status"] = "active"
	o["accepted"] = sim.minute
	sim.orders.list.push_front(o)


## Светильники ЛПО под потолком гаража, лампочки в пристройке; насос за пристройкой и трубы к туалету.
static func _light_and_water_garage(sim: Sim) -> void:
	for c in [Vector2i(18, 11), Vector2i(25, 11), Vector2i(19, 16), Vector2i(25, 13)]:
		sim.place_thing("lamp_tube", c, true, false)
	for c3 in [Vector2i(12, 13), Vector2i(9, 18), Vector2i(13, 18)]:
		sim.place_thing("lamp_bulb", c3, true, false)
	sim.world.refresh_all()
	autowire(sim)
	autopipe(sim)


## Проводка гаража: от трансформатора вдоль стены к станку и под пол к чайнику.
static func _wire_garage(sim: Sim) -> void:
	var w := sim.world
	for x in range(16, 28):
		w.cable[w.idx(Vector2i(x, 10))] = 1
	for y in range(10, 17):
		w.cable[w.idx(Vector2i(16, y))] = 1
	w.cable_rev += 1


## Проложить кабели от трансформатора ко всем потребителям: к розеткам станков и приборов
## и к светильникам (кратчайшими путями).
static func autowire(sim: Sim) -> void:
	var w := sim.world
	var src_id := sim.power.grid_input_id()
	var src: Thing = sim.things.get(src_id)
	if src == null:
		return
	var targets: Array = []
	for t: Thing in sim.things.values():
		if not t.built or str(t.def().get("power_source", "")) != "":
			continue
		if t.kind() == "machine" or float(t.def().get("power_kw", 0.0)) > 0.0:
			targets.append([t.inlet_cell()] if t.kind() != "light" else [t.cell])
	var has_any := false
	for i in w.w * w.h:
		if w.cable[i] != 0:
			has_any = true
			break
	if not has_any:
		for c in src.cells():
			w.cable[w.idx(c)] = 1
	else:
		_route(sim, src.cells())   # 1.18: кабель должен зайти в клетку подстанции
	for tg: Array in targets:
		_route(sim, tg)
	w.cable_rev += 1


static func _route(sim: Sim, target_cells: Array) -> void:
	_route_layer(sim, "cable", target_cells)


## Трубы от ввода водопровода ко всем приборам, которым нужна вода.
static func autopipe(sim: Sim) -> void:
	var w := sim.world
	var srcs := sim.things_of("pump") + sim.things_of("water_source")
	if srcs.is_empty():
		return
	var any := false
	for i in w.w * w.h:
		if w.pipe[i] != 0:
			any = true
			break
	var s0: Thing = srcs[0]
	if not any:
		w.pipe[w.idx(s0.cells()[0])] = 1   # 1.18: труба начинается в клетке насоса
	else:
		_route_layer(sim, "pipe", s0.cells())
	for t: Thing in sim.things.values():
		if t.built and t.needs_water():
			_route_layer(sim, "pipe", [t.inlet_cell()])
	w.pipe_rev += 1


## Линия (воздуховод или пневмомагистраль) от источника к целям: для тестов и снимков.
static func autoline(sim: Sim, layer: String, from_cell: Vector2i, targets: Array) -> void:
	var w := sim.world
	var arr: PackedByteArray = w.duct if layer == "duct" else w.air
	var any := false
	for i in w.w * w.h:
		if arr[i] != 0:
			any = true
			break
	if not any:
		if layer == "duct":
			w.duct[w.idx(from_cell)] = 1
		else:
			w.air[w.idx(from_cell)] = 1
	for c: Vector2i in targets:
		_route_layer(sim, layer, [c])
	if layer == "duct":
		w.duct_rev += 1
	else:
		w.air_rev += 1


## Светильники в помещениях без своего света (старые сохранения): ЛПО сеткой ~5 клеток.
static func autolight(sim: Sim, only_powered: bool = true) -> int:
	sim.rooms.rebuild()
	sim.power.update_topology()
	var n := 0
	for r in sim.rooms.list:
		var has_lamp := false
		for c in r.cells:
			var ct := sim.ceiling_at(c)
			if ct and ct.kind() == "light":
				has_lamp = true
				break
		if has_lamp:
			continue
		if only_powered and not sim.power.room_net.has(r.id):
			continue
		var nx := maxi(1, int(round(r.rect.size.x / 6.0)))
		var ny := maxi(1, int(round(r.rect.size.y / 6.0)))
		for iy in ny:
			for ix in nx:
				var p := Vector2(r.rect.position) + Vector2((ix + 0.5) * r.rect.size.x / nx, (iy + 0.5) * r.rect.size.y / ny)
				var cell := Vector2i(floori(p.x), floori(p.y))
				if sim.rooms.room_at(cell) != r or sim.can_place("lamp_tube", cell) != "":
					continue
				sim.place_thing("lamp_tube", cell, true, false)
				n += 1
	autowire(sim)
	return n


## Кратчайший путь по слою (кабель или труба) от уже проложенного к цели.
static func _route_layer(sim: Sim, layer: String, target_cells: Array) -> void:
	var w := sim.world
	var arr: PackedByteArray = w.pipe
	match layer:
		"cable":
			arr = w.cable
		"duct":
			arr = w.duct
		"air":
			arr = w.air
	var goal := {}
	for c: Vector2i in target_cells:
		goal[w.idx(c)] = true   # 1.18: сеть заводят прямо в клетку прибора
	for k in goal.keys():
		if arr[k] != 0:
			return
	var prev := {}
	var queue: Array[int] = []
	for i in w.w * w.h:
		if arr[i] != 0:
			prev[i] = -1
			queue.append(i)
	var head := 0
	var found := -1
	while head < queue.size():
		var i2: int = queue[head]
		head += 1
		if goal.has(i2):
			found = i2
			break
		var c2 := w.cell_of(i2)
		for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n2: Vector2i = c2 + d2
			if not w.in_plot(n2):
				continue
			var ni := w.idx(n2)
			if not prev.has(ni):
				prev[ni] = i2
				queue.append(ni)
	while found >= 0:
		match layer:
			"cable":
				w.cable[found] = 1
			"duct":
				w.duct[found] = 1
			"air":
				w.air[found] = 1
			_:
				w.pipe[found] = 1
		found = int(prev.get(found, -1))


## 1.18: сети подключаются только в клетку прибора. В старых сохранениях кабель и трубы часто
## подходили к соседней клетке — дотянуть их на одну клетку внутрь, чтобы ничего не отключилось.
static func migrate_v10(sim: Sim) -> void:
	var w := sim.world
	var n := 0
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var k := t.kind()
		var src_pw := str(t.def().get("power_source", "")) != ""
		var jobs: Array = []   # [слой, клетки, в которые можно завести]
		if src_pw:
			jobs.append(["cable", t.cells()])
		elif k != "light" and k != "camera" and k != "speaker" and (k == "machine" or float(t.def().get("power_kw", 0.0)) > 0.0):
			jobs.append(["cable", [t.inlet_cell()]])
		if k == "water_source" or k == "pump" or k == "radiator" or k == "boiler":
			jobs.append(["pipe", t.cells()])
		elif t.needs_water():
			jobs.append(["pipe", [t.inlet_cell()]])
		if k == "vent_fan" or k == "vent_hood":
			jobs.append(["duct", t.cells()])
		if k == "compressor":
			jobs.append(["air", t.cells()])
		elif k == "machine" and str(t.machine_def().get("air", "")) != "":
			jobs.append(["air", [t.inlet_cell()]])
		for jb: Array in jobs:
			var layer := str(jb[0])
			var cells: Array = jb[1]
			var has := false
			for c: Vector2i in cells:
				if w.inb(c) and w.net_at(layer, c) == 1:
					has = true
					break
			if has:
				continue
			for c2: Vector2i in cells:
				if has or not w.inb(c2):
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if w.inb(c2 + d) and w.net_at(layer, c2 + d) == 1:
						w.net_set(layer, w.idx(c2), 1)
						has = true
						n += 1
						break
	if n > 0:
		w.cable_rev += 1
		w.pipe_rev += 1
		w.duct_rev += 1
		w.air_rev += 1
		sim.notify("Сохранение обновлено до 1.18: кабели и трубы теперь заводят прямо в клетку прибора — %d подключений дотянуто автоматически." % n, Sim.LVL_INFO)
	# 1.18: на некупленных участках деревьев вдвое меньше — карта легче
	var thin := 0
	for k2 in w.lots.size():
		if w.lot_bought(k2):
			continue
		var lr := w.lot_rect(k2)
		for y in range(lr.position.y, lr.end.y):
			for x in range(lr.position.x, lr.end.x):
				var i := w.idx(Vector2i(x, y))
				if w.flora[i] != 0 and absi((x * 73856093) ^ (y * 19349663)) % 2 == 0:
					w.flora[i] = 0
					thin += 1
	if thin > 0:
		w.flora_rev += 1


## 1.19: «Сайдвей» стал фрезерным — токарная работа с него снимается, заготовки ложатся рядом.
static func migrate_v11(sim: Sim) -> void:
	var n := 0
	for t: Thing in sim.things.values():
		if t.def_id != "cnc_sidway":
			continue
		var free_c := t.cell + Vector2i(0, t.size().y)
		for iid in sim.slot_ids(t, 0).duplicate():
			var it: Item = sim.items.get(iid)
			if it:
				sim.put_on_ground(it, free_c)
		t.product = ""
		t.job_step = 0
		t.progress = 0.0
		t.working = false
		t.setup_key = ""
		n += 1
	if n > 0:
		sim.notify("Сохранение обновлено до 1.19: «Сайдвей ВМ-2215» теперь фрезерный станок — заготовки с него сложены рядом.", Sim.LVL_INFO)


## 1.20: батареям нужен электрокотёл у насосной — ставим его бесплатно и дотягиваем кабель.
static func migrate_v12(sim: Sim) -> void:
	if sim.things_of("radiator", false).is_empty() and sim.things_of("pump", false).is_empty():
		return
	if not sim.things_of("heater", false).is_empty():
		return
	var h := add_heater(sim)
	if h:
		sim.notify("Сохранение обновлено до 1.20: батареи теперь греет электрокотёл у насосной — поставили его бесплатно и подключили.", Sim.LVL_INFO, h.cell)
	elif not sim.things_of("radiator", false).is_empty():
		sim.notify("Обновление 1.20: батареям нужен электрокотёл вплотную к насосной станции (Объекты → Водопровод). Рядом с насосной нет места — освободите клетку и поставьте его.", Sim.LVL_WARN)


## Поставить готовый электрокотёл вплотную к насосной и протянуть к нему кабель от соседней клетки.
static func add_heater(sim: Sim) -> Thing:
	for p in sim.things_of("pump"):
		var gr := p.rect().grow(1)
		var cands: Array[Vector2i] = []
		for y in range(gr.position.y, gr.end.y):
			for x in range(gr.position.x, gr.end.x):
				var c := Vector2i(x, y)
				if not p.rect().has_point(c):
					cands.append(c)
		# сначала — клетки, где рядом уже есть кабель
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _cable_near(sim, a) and not _cable_near(sim, b))
		for c2 in cands:
			if sim.can_place("water_heater", c2) != "":
				continue
			var t := sim.place_thing("water_heater", c2, true, false)
			if t == null:
				continue
			if p.id in sim.rooms.legacy:
				sim.rooms.legacy[t.id] = true
			var w := sim.world
			if w.net_at("cable", c2) != 1:
				w.net_set("cable", w.idx(c2), 1)
				if not _cable_near(sim, c2):
					# дотянуть до ближайшего кабеля по прямой не пытаемся — кабель в клетку насосной
					for pc in p.cells():
						w.net_set("cable", w.idx(pc), 1)
				w.cable_rev += 1
			return t
	return null


static func _cable_near(sim: Sim, c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if sim.world.inb(c + d) and sim.world.net_at("cable", c + d) == 1:
			return true
	return false


## Старые сохранения (до 0.8): розетки станков, светильники, водопровод.
static func migrate_v7(sim: Sim) -> void:
	sim.rooms.rebuild()
	sim.power.update_topology()
	var lamps := autolight(sim, true)
	if not sim.things.values().filter(func(t: Thing) -> bool: return t.built and t.needs_water()).is_empty() and sim.things_of("water_source").is_empty():
		var cab: Thing = sim.things.get(sim.power.grid_input_id())
		var near := cab.cell if cab else Vector2i(sim.gate_x - 2, sim.world.plot.end.y - 2)
		var spot := Vector2i(-1, -1)
		for r in range(1, 8):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var c := near + Vector2i(dx, dy)
					if spot.x < 0 and sim.can_place("water_inlet", c) == "" and sim.rooms.room_at(c) == null:
						spot = c
		if spot.x >= 0:
			sim.place_thing("water_inlet", spot, true, false)
			autopipe(sim)
	autowire(sim)
	sim.world.cable_rev += 1
	sim.notify("Сохранение обновлено до 0.8: в помещения повешено светильников — %d, проложен водопровод к туалетам и раковинам, станки подключены к своим розеткам." % lamps, Sim.LVL_INFO)


## Старые сохранения (этап 1): проводка, назначение цеха, черты характера.
static func migrate_v1(sim: Sim) -> void:
	autowire(sim)
	sim.rooms.rebuild()
	for r in sim.rooms.list:
		for tid in r.things:
			var t: Thing = sim.things.get(tid)
			if t and t.kind() == "machine":
				sim.rooms.assign(r, "workshop")
				break
	for wk in sim.workers:
		if wk.traits.is_empty():
			wk.traits = People.random_traits(sim.rng, wk)
		if not wk.skills.has("electric"):
			wk.skills["electric"] = sim.rng.randi_range(0, 3)
		if not wk.look.has("street"):
			wk.look["street"] = "jacket"
			wk.look["street_col"] = People.pick(sim.rng, People.STREET_COLS)
		wk.dressed = wk.present
	for i in sim.candidates.size():
		var cd: Dictionary = sim.candidates[i]
		if not cd.has("traits"):
			var cw := Worker.from_dict(cd)
			cw.traits = People.random_traits(sim.rng, cw)
			sim.candidates[i] = cw.to_dict()
	sim.notify("Сохранение из прошлой версии обновлено: проложена проводка, гараж назначен цехом.", Sim.LVL_INFO)



# ================================================================ общие заготовки

## Кирпичная коробка с полом; двери, ворота и окна — списками клеток стены.
static func box(sim: Sim, r: Rect2i, floor_id: int, doors: Array = [], windows: Array = [], gates: Array = []) -> void:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = floor_id
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	for c in doors:
		w.wall[w.idx(c)] = World.W_DOOR
	for c2 in windows:
		w.wall[w.idx(c2)] = World.W_WINDOW
	for c3 in gates:
		w.wall[w.idx(c3)] = World.W_GATE


static func put(sim: Sim, def_id: String, c: Vector2i) -> Thing:
	if sim.can_place(def_id, c) != "" and not sim.progress.all_open:
		# этап может ещё не открыть объект — в сценарии он уже стоит
		var old := sim.progress.all_open
		sim.progress.all_open = true
		var err := sim.can_place(def_id, c)
		sim.progress.all_open = old
		if err != "":
			return null
	elif sim.can_place(def_id, c) != "":
		return null
	return sim.place_thing(def_id, c, true, false)


## Ряд объектов слева направо с промежутком; возвращает следующий x.
static func row(sim: Sim, ids: Array, x0: int, y: int, x_max: int, gap: int = 1) -> int:
	var x := x0
	for id in ids:
		var sz: Array = Defs.objects.get(str(id), {}).get("size", [1, 1])
		if x + int(sz[0]) > x_max:
			break
		put(sim, str(id), Vector2i(x, y))
		x += int(sz[0]) + gap
	return x


static func assign_at(sim: Sim, c: Vector2i, type: String) -> void:
	sim.rooms.update()
	var r := sim.rooms.room_at(c)
	if r:
		sim.rooms.assign(r, type)


static func materials(sim: Sim, rack: Thing, mat: String, n: int) -> void:
	if rack == null:
		return
	for k in n:
		var it := sim.new_item("mat", mat, "raw")
		var slot := 0 if sim.count_slot(rack, 0) < rack.slot_cap(0) else 1
		if slot >= rack.slot_count() or sim.count_slot(rack, slot) >= rack.slot_cap(slot):
			sim.delete_item(it)
			return
		sim.put_in_thing(it, rack, slot)


## Основной металл профиля — то, что нужно первым изделиям.
static func main_material(sim: Sim) -> String:
	for p in sim.progress.products():
		var m := str(Defs.products.get(str(p), {}).get("material", ""))
		if m != "":
			return m
	return "bar45"


## Процессы, нужные изделиям профиля (вместе с деталями для сборки).
static func profile_processes(sim: Sim) -> Array:
	var out: Array = []
	var stack: Array = sim.progress.products().duplicate()
	var seen := {}
	while not stack.is_empty():
		var p := str(stack.pop_back())
		if seen.has(p) or not Defs.products.has(p):
			continue
		seen[p] = true
		for o: Dictionary in Defs.route(p):
			if not out.has(str(o["op"])):
				out.append(str(o["op"]))
		for c in Defs.components(p).keys():
			stack.append(str(c))
	return out


const PROC_MACHINE := {"turning": "lathe", "milling": "mill", "drilling": "drill", "welding": "weld_post",
	"heat": "furnace", "paint": "paint_booth", "assembly": "assembly_table", "test": "test_stand", "casting": "cast_ist", "stamping": "press_kd"}
const PROC_PROF := {"turning": "turner", "milling": "miller", "drilling": "miller", "welding": "welder",
	"heat": "heat_treater", "paint": "painter", "assembly": "assembler", "test": "qc", "casting": "caster", "stamping": "presser"}


static func hire_prof(sim: Sim, prof: String, lvl_min: int = 3, lvl_max: int = 6) -> Worker:
	var w := People.make(sim.rng, prof)
	var sk := w.main_skill()
	w.skills[sk] = sim.rng.randi_range(lvl_min, lvl_max)
	w.wage = People.wage_for(w)
	sim.add_worker(w)
	w.add_history(sim.day(), Nicks.gendered("Принят{|а} на работу", w.female))
	return w


## Трансформатор у забора и автоматическая проводка ко всему, что есть.
## level 1 — два ТМ-25 рядом (30 кВт), level 2 — ТМ-25 и ТМ-63 (65 кВт).
static func power(sim: Sim, cabinet_cell: Vector2i, level: int = 0) -> void:
	put(sim, "cabinet", cabinet_cell)
	if level >= 1:
		var extra := "tr_63" if level >= 2 else "cabinet"
		var wide := extra == "tr_63"
		var placed := false
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-2 if wide else -1, 0), Vector2i(0, -1), Vector2i(-1 if wide else 0, -1), Vector2i(0, 1)]:
			if put(sim, extra, cabinet_cell + off) != null:
				placed = true
				break
		if not placed:
			sim.power.grid_level = level   # некуда поставить второй — мощность первому
	sim.world.refresh_all()
	sim.rooms.update()
	autowire(sim)


# ================================================================ «Чистое поле»

static func _new_field(seed_value: int, story_mode: String, profile: String) -> Sim:
	var sim := _base(seed_value, "field", profile, story_mode, 64, 44)
	var w := sim.world
	sim.gate_x = 30
	_lay_ground(sim, Rect2i(4, 26, 20, 7), Rect2i(28, 30, 8, 7), 38)
	sim.progress.ooo = true
	# 1.15: три блок-контейнера бок о бок — раздевалка, туалет и бытовка-столовая, у каждого своя дверь
	box(sim, Rect2i(4, 26, 6, 7), 3, [Vector2i(7, 32)], [Vector2i(4, 29)])
	box(sim, Rect2i(9, 26, 4, 7), 2, [Vector2i(10, 32)])
	box(sim, Rect2i(12, 26, 5, 7), 3, [Vector2i(15, 32)], [Vector2i(16, 29), Vector2i(14, 26)])
	_build_tech(sim, Rect2i(17, 27, 7, 5), Vector2i(20, 31))   # 1.18: подстанция и насосная
	w.refresh_all()
	# раздевалка: шкафчики на двоих, скамейки
	for c in [Vector2i(5, 27), Vector2i(6, 27), Vector2i(7, 27)]:
		put(sim, "locker2", c)
	put(sim, "bench", Vector2i(5, 30))
	put(sim, "extinguisher", Vector2i(8, 27))
	put(sim, "lamp_bulb", Vector2i(7, 29))
	# туалет: две кабинки входом вниз и раковина
	put(sim, "toilet", Vector2i(10, 27))
	put(sim, "toilet", Vector2i(11, 27))
	put(sim, "sink", Vector2i(11, 29))
	put(sim, "lamp_bulb", Vector2i(10, 30))
	# бытовка-столовая: холодильник, чайник, стол, стулья
	put(sim, "fridge", Vector2i(15, 27))
	put(sim, "kettle", Vector2i(13, 31))
	put(sim, "dining_table", Vector2i(13, 29))
	for c2 in [Vector2i(13, 28), Vector2i(14, 28), Vector2i(13, 30), Vector2i(14, 30)]:
		put(sim, "chair", c2)
	put(sim, "lamp_bulb", Vector2i(15, 29))
	put(sim, "extinguisher", Vector2i(14, 31))
	w.refresh_all()
	assign_at(sim, Vector2i(6, 29), "locker")
	assign_at(sim, Vector2i(10, 29), "wc")
	assign_at(sim, Vector2i(15, 30), "canteen")
	assign_at(sim, Vector2i(20, 30), "tech_room")
	autowire(sim)
	autopipe(sim)
	# 1.17: на участке только бытовка — склад, цех и всё остальное игрок строит сам
	put(sim, "urn", Vector2i(15, 33))
	# люди: только бригада строителей — станочников нанимают, когда будет где работать
	add_yard_zones(sim)   # 1.29: обязательные зоны у ворот
	hire_builders(sim, 3)
	sim.refresh_candidates()
	sim.progress.quiet_until = sim.day() + Progress.QUIET_DAYS   # 1.17: неделя на стройку без заказов
	sim.orders.morning()
	sim.events.clear()
	sim.notify("«Чистое поле»: участок у трассы, вагончик и бригада из трёх строителей. Оформите программу «Цех с нуля» (Финансы → Гранты), стройте цех, потом нанимайте станочников.", Sim.LVL_GOOD)
	sim.notify("Начните с пола и стен будущего цеха (Стройка, B). Ток и вода — из техпомещения: тяните кабель и трубы оттуда (Сети, E).", Sim.LVL_INFO)
	sim.notify("Первая неделя — на стройку: заказов не будет. Готовы раньше — кнопка «Начать производство» в задачах слева.", Sim.LVL_INFO)
	return sim


# ================================================================ «Песочница»

static func _new_sandbox(seed_value: int, story_mode: String, profile: String, opts: Dictionary) -> Sim:
	var big := str(opts.get("map", "large")) == "large"
	var sim := _base(seed_value, "sandbox", profile, story_mode, 64 if big else 48, 44 if big else 36)
	sim.gate_x = int(sim.world.plot.get_center().x) - 2
	_lay_ground(sim, Rect2i(0, 0, 0, 0), Rect2i(sim.gate_x - 2, sim.world.plot.end.y - 6, 8, 7), 50 if big else 34)
	# пустой участок: у ворот только техпомещение — подстанция и насосная под крышей (1.29: раньше стояли под открытым небом)
	var tr := Rect2i(sim.gate_x - 11, sim.world.plot.end.y - 6, 7, 5)
	_build_tech(sim, tr, Vector2i(tr.end.x - 1, tr.position.y + 2))   # дверь — к воротам
	sim.world.refresh_all()
	sim.rooms.update()
	var trm := sim.rooms.room_at(tr.position + Vector2i(2, 2))
	if trm:
		sim.rooms.assign(trm, "tech_room")
	autowire(sim)
	add_yard_zones(sim)   # 1.29: обязательные зоны у ворот
	hire_builders(sim, 3)
	sim.refresh_candidates()
	sim.progress.quiet_until = sim.day() + Progress.QUIET_DAYS
	sim.orders.morning()
	sim.events.clear()
	sim.money = float(opts.get("money", 1000000))
	sim.progress.all_open = bool(opts.get("all_open", true))
	sim.progress.stage = 3 if sim.progress.all_open else 1
	sim.progress.ooo = sim.progress.all_open
	sim.notify("Песочница: пустой участок и бригада строителей. Целей нет — всё на ваше усмотрение.", Sim.LVL_GOOD)
	sim.notify("Первая неделя — на стройку: заказов не будет. Готовы раньше — кнопка «Начать производство» в задачах слева.", Sim.LVL_INFO)
	return sim


## Бригада строителей для старта с нуля.
static func hire_builders(sim: Sim, n: int) -> void:
	for k in n:
		var b := hire_prof(sim, "builder", 4, 7)
		b.skills["haul"] = maxi(b.skill("haul"), 5)


# ================================================================ 1.29: обязательные зоны у ворот

## Зона разгрузки (с поддонами заготовок) и зона отгрузки на свободной земле у ворот, плюс поддоны
## готовой продукции, если их нет. Чего уже хватает — не трогает. Возвращает, что добавлено.
static func add_yard_zones(sim: Sim, with_pallets: bool = true) -> Array[String]:
	var out: Array[String] = []
	var w := sim.world
	var gy := w.plot.end.y - 2
	var lane := Rect2i(sim.gate_x - 1, w.plot.position.y, 6, w.plot.size.y)   # проезд от ворот — свободен
	var avoid: Array[Rect2i] = [lane]
	if sim.logi.has_zone():
		avoid.append(_cells_rect(sim.logi.zone_cells()).grow(1))
	else:
		var r := _yard_rect(sim, Vector2i(4, 3), Vector2(sim.gate_x + 7, gy), avoid)
		if r.size.x > 0 and sim.set_area(r, Logistics.A_UNLOAD) > 0:
			out.append("unload")
			avoid.append(r.grow(1))
			if with_pallets:
				for k in 2:
					if put(sim, Logistics.RAW_PALLET, Vector2i(r.end.x - 1 - k, r.position.y)):
						out.append(Logistics.RAW_PALLET)
	var sr := Rect2i()
	if sim.logi.has_ship():
		sr = _cells_rect(sim.logi.ship_cells())
	else:
		sr = _yard_rect(sim, Vector2i(3, 3), Vector2(sim.gate_x + 12, gy), avoid)
		if sr.size.x > 0 and sim.set_area(sr, Logistics.A_SHIP) > 0:
			out.append("ship")
		else:
			sr = Rect2i()
	if with_pallets and sr.size.x > 0:
		var have := false
		for t: Thing in sim.things.values():
			if t.def_id == "pallet":
				have = true
				break
		if not have:
			# склад готовой продукции — у зоны отгрузки, чтобы носить недалеко
			for k2 in 2:
				var c := Vector2i(sr.position.x + k2, sr.position.y - 1)
				if sim.world.area[sim.world.idx(c)] == 0 and put(sim, "pallet", c):
					out.append("pallet")
	return out


static func _cells_rect(cells: Array[Vector2i]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var r := Rect2i(cells[0], Vector2i.ONE)
	for c in cells:
		r = r.expand(c).merge(Rect2i(c, Vector2i.ONE))
	return r


## Свободный прямоугольник size на участке, ближайший центром к anchor: без стен, объектов, чертежей и зон.
static func _yard_rect(sim: Sim, size: Vector2i, anchor: Vector2, avoid: Array[Rect2i]) -> Rect2i:
	var w := sim.world
	var best := Rect2i()
	var bd := INF
	for y in range(w.plot.position.y, w.plot.end.y - size.y + 1):
		for x in range(w.plot.position.x, w.plot.end.x - size.x + 1):
			var r := Rect2i(x, y, size.x, size.y)
			var d := (Vector2(r.position) + Vector2(size) * 0.5 - anchor).length_squared()
			if d >= bd:
				continue
			var bad := false
			for a in avoid:
				if a.intersects(r):
					bad = true
					break
			if bad or not _yard_free(sim, r):
				continue
			bd = d
			best = r
	return best


static func _yard_free(sim: Sim, r: Rect2i) -> bool:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			if not w.in_plot(c) or w.wall[i] != World.W_NONE or w.occ[i] >= 0 or w.area[i] != 0:
				return false
			if not w.passable(c) or sim.bp_cells.has(i) or w.flora[i] != 0:
				return false
			if w.bp_floor[i] != World.BP_NONE or w.bp_wall[i] != World.BP_NONE:
				return false
	return true


## Миграция (1.29): в старом сохранении нет обязательных зон — отмечаем их у ворот, если есть место.
static func migrate_v13(sim: Sim) -> void:
	if sim.logi.has_zone() and sim.logi.has_ship():
		return
	var added := add_yard_zones(sim)
	var names: Array[String] = []
	if added.has("unload"):
		names.append("разгрузки")
	if added.has("ship"):
		names.append("отгрузки")
	if not names.is_empty():
		var extra := " и поддоны заготовок" if added.has(Logistics.RAW_PALLET) else ""
		sim.notify("Обновление 1.29: зоны разгрузки и отгрузки теперь обязательны — у ворот отмечена зона %s%s. Фургоны сгружают металл на поддоны заготовок, а машина клиента грузит заказ только из зоны отгрузки. Зоны можно расширить или перенести (Стройка → Зоны на улице)." % [" и ".join(names), extra], Sim.LVL_INFO)
	if not sim.logi.has_zone() or not sim.logi.has_ship():
		sim.notify("Обновление 1.29: у ворот нет свободного места под зону %s. Освободите место и отметьте её (Стройка → Зоны на улице)." % ("разгрузки" if not sim.logi.has_zone() else "отгрузки"), Sim.LVL_WARN)
