class_name Town
extends RefCounted
## «Город» (1.9): социальная сфера завода. Общежитие для иногородних, столовая с поваром и горячими
## обедами, медпункт с фельдшером, заводской детсад, Дом культуры, заводское радио, кот
## и отношения с городом.

const DORM_FEE := 100.0          ## плата за койку в день
const MEAL_COST := 85.0          ## продукты на порцию горячего обеда
const KG_LEVELS := [             ## [мест, разово, в неделю]
	[0, 0.0, 0.0], [6, 250000.0, 12000.0], [12, 450000.0, 20000.0], [24, 800000.0, 34000.0]]
const DK_COST := 600000.0
const DK_WEEK := 15000.0
const VACCINE := 600.0           ## прививка от гриппа на человека
const RADIO_PROGRAMS := {
	"news": {"name": "Утренние новости", "time": 495.0, "desc": "В 8:15 — новости завода: заказы, передовики, планы. Людям приятно быть в курсе."},
	"gym": {"name": "Производственная гимнастика", "time": 600.0, "desc": "В 10:00 — пять минут разминки под радио: меньше устают, бодрее до обеда."},
	"music": {"name": "Музыка в обед", "time": -1.0, "desc": "В обеденный перерыв — эстрада и песни: обедается веселее."},
}

var sim: Sim
var rel := 40.0                  ## отношения с городом, 0–100
var beds: Dictionary = {}        ## id кровати (строкой) -> [id жильцов]
var invite_away := true          ## приглашать иногородних, если есть свободные койки
var portions := 0                ## готовые порции горячего обеда
var meals_today := 0
var meals_total := 0
var kg_level := 0
var dk := false
var dk_since := -1
var radio: Dictionary = {"news": true, "gym": true, "music": true}
var vaccinated_until := -1
var cat: Cat = null
var cat_offered := false
var cat_gone := false
var flu_cases := 0
var _pet_t := 0.0
var _last_tod := -1.0


func _init(s: Sim) -> void:
	sim = s


# ================================================================ общежитие

func dorm_rooms() -> Array:
	return sim.rooms.list.filter(func(r: Rooms.Room) -> bool: return r.type == "dorm" and r.valid)


## Кровати в оборудованных общежитиях.
func dorm_beds() -> Array[Thing]:
	var out: Array[Thing] = []
	for r: Rooms.Room in dorm_rooms():
		for tid in r.things:
			var t: Thing = sim.things.get(tid)
			if t and t.built and t.kind() == "bed":
				out.append(t)
	return out


func dorm_capacity() -> int:
	return dorm_beds().size() * 2


func residents() -> Array[Worker]:
	var out: Array[Worker] = []
	for k in beds.keys():
		for wid in beds[k]:
			var w := sim.get_worker(int(wid))
			if w:
				out.append(w)
	return out


func is_resident(w: Worker) -> bool:
	return bed_of(w) != null


func bed_of(w: Worker) -> Thing:
	for k in beds.keys():
		if (beds[k] as Array).has(w.id):
			return sim.things.get(int(k))
	return null


func free_beds() -> int:
	return maxi(0, dorm_capacity() - residents().size())


## Разложить жильцов по кроватям: иногородние — в первую очередь; убрать выбывших.
func assign_beds() -> void:
	var valid := {}
	for b in dorm_beds():
		valid[str(b.id)] = true
	var keep: Array[int] = []
	for k in beds.keys():
		for wid in beds[k]:
			if valid.has(k) and sim.get_worker(int(wid)) != null:
				keep.append(int(wid))
	beds.clear()
	for b2 in dorm_beds():
		beds[str(b2.id)] = []
	var want: Array[int] = keep.duplicate()
	for w in sim.workers:
		if w.from_away and not want.has(w.id):
			want.append(w.id)
	for wid2 in want:
		for k2 in beds.keys():
			if (beds[k2] as Array).size() < 2:
				(beds[k2] as Array).append(wid2)
				break
	# дорога домой: жильцы уходят в общежитие, остальные — на улицу
	for w2 in sim.workers:
		var bed := bed_of(w2)
		if bed:
			w2.exit_cell = _bed_cell(bed)
		elif sim.world.passable(w2.exit_cell) == false or _is_bed_cell(w2.exit_cell):
			w2.exit_cell = Vector2i(0, sim.world.sidewalk_row) if (w2.id % 2) == 0 else Vector2i(sim.world.w - 1, sim.world.sidewalk_row)


func _bed_cell(b: Thing) -> Vector2i:
	var c := b.cell + Vector2i(0, 1)
	if sim.world.inb(c) and sim.world.passable(c):
		return c
	for d: Vector2i in Rooms.DIRS:
		var c2 := b.cell + d
		if sim.world.inb(c2) and sim.world.passable(c2):
			return c2
	return b.cell


func _is_bed_cell(c: Vector2i) -> bool:
	for b in sim.things_of("bed"):
		if c == b.cell + Vector2i(0, 1) or c.distance_to(b.cell) <= 1.5:
			return true
	return false


## Иногородний кандидат: без места в общежитии не приедет.
func can_hire(c: Worker) -> String:
	if c.from_away and free_beds() <= 0:
		return L.t("Иногороднему нужна койка в общежитии — свободных мест нет")
	return ""


func on_hired(w: Worker) -> void:
	if w.from_away:
		assign_beds()


# ================================================================ столовая с поваром

func kitchen() -> Thing:
	for st in sim.things_of("stove"):
		if st.built and sim.rooms.thing_in(st, "canteen"):
			return st
	return null


func has_serving() -> bool:
	for sv in sim.things_of("serving"):
		if sv.built and sim.rooms.thing_in(sv, "canteen"):
			return true
	return false


func cooks() -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if w.prof == "cook":
			out.append(w)
	return out


func kitchen_ready() -> bool:
	var k := kitchen()
	return k != null and has_serving() and sim.power.powered(k)


## Сколько порций стоит наготовить: на всех, кто сегодня обедает.
func portions_needed() -> int:
	var n := 0
	for w in sim.workers:
		if not w.ate_today and (w.present or w.shift == 1):
			n += 1
	return n + 2


func take_portion() -> bool:
	if portions <= 0:
		return false
	portions -= 1
	meals_today += 1
	meals_total += 1
	return true


## Повар отстоял у плиты: готовы новые порции.
func on_cooked(w: Worker) -> void:
	var n := 6 + int(w.skill("cook") / 2)
	n = mini(n, maxi(0, portions_needed() - portions))
	if n <= 0:
		return
	portions += n
	sim.spend(MEAL_COST * n, "Продукты для столовой: %d %s" % [n, Defs.plural(n, "порция", "порции", "порций")])


# ================================================================ медпункт

func medbays() -> Array:
	return sim.rooms.list.filter(func(r: Rooms.Room) -> bool: return r.type == "medbay" and r.valid)


func nurses(on_shift: bool = false) -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if w.prof == "nurse" and (not on_shift or w.present):
			out.append(w)
	return out


## Медпункт работает: оборудован и фельдшер на смене.
func medbay_ready() -> bool:
	return not medbays().is_empty() and not nurses(true).is_empty()


func vaccinate() -> String:
	if sim.workers.is_empty():
		return L.t("Прививать некого")
	if vaccinated_until >= sim.day() + 30:
		return L.t("Коллектив уже привит")
	var cost := VACCINE * sim.workers.size() * (0.7 if medbay_ready() or not nurses().is_empty() else 1.0)
	if sim.money < cost:
		return L.t("Не хватает денег: %s") % Defs.money_str(cost)
	sim.spend(cost, "Медицина: прививки от гриппа")
	vaccinated_until = sim.day() + 84
	sim.notify(L.t("Всем сделали прививку от гриппа: зимой болеть будут в четыре раза реже."), Sim.LVL_GOOD)
	return ""


func flu_season() -> bool:
	var m := sim.season.month()
	return m >= 10 or m <= 1


func _flu_morning() -> void:
	if not sim.story.enabled or not flu_season() or not sim.is_workday():
		return
	var ch := 0.006 * (0.25 if vaccinated_until >= sim.day() else 1.0) * (0.6 if medbay_ready() else 1.0)
	for w in sim.workers:
		if w.sick_until > sim.minute or sim.rng.randf() >= ch:
			continue
		var days := sim.rng.randi_range(2, 5) - (1 if not medbays().is_empty() and not nurses().is_empty() else 0)
		w.sick_until = float(sim.day() + days - 1) * 1440.0 + 1200.0
		w.away_why = "на больничном"
		w.add_history(sim.day(), L.t("Грипп. Больничный %d дн.") % days)
		flu_cases += 1
		sim.notify_once("flu", L.t("Грипп: %s на больничном. Прививка всему коллективу — в «Город → Столовая и медпункт».") % w.full_name(), Sim.LVL_WARN, Vector2i(-1, -1), 1440.0)


# ================================================================ детсад

func kids_of(w: Worker) -> int:
	return w.kids


func parents() -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if w.kids > 0:
			out.append(w)
	return out


func kg_places() -> int:
	return int(KG_LEVELS[clampi(kg_level, 0, KG_LEVELS.size() - 1)][0])


## Кому достались места в садике: сначала мамы, потом по стажу.
func kg_kids() -> Array[Worker]:
	var ps := parents()
	ps.sort_custom(func(a: Worker, b: Worker) -> bool: return (a.female and not b.female) or (a.female == b.female and a.hired_day < b.hired_day))
	var out: Array[Worker] = []
	var left := kg_places()
	for w in ps:
		if left >= w.kids:
			out.append(w)
			left -= w.kids
	return out


## 1.23: кто попал в садик — запоминаем на минуту (раньше пересчитывали для каждого человека).
var _kg_cache: Dictionary = {}
var _kg_sig := ""


func has_kg_place(w: Worker) -> bool:
	var sig := "%d|%d|%d|%d" % [sim.minute, sim.workers.size(), sim.worker_rev, kg_level]
	if sig != _kg_sig:
		_kg_sig = sig
		_kg_cache.clear()
		for k in kg_kids():
			_kg_cache[k.id] = true
	return _kg_cache.has(w.id)


func kg_upgrade() -> String:
	if kg_level >= KG_LEVELS.size() - 1:
		return L.t("Садик уже самый большой")
	if not sim.dev.on("city3"):
		return L.t("Детсад открывает ступень «Шефство» (Управление → Развитие)")
	var cost := float(KG_LEVELS[kg_level + 1][1]) - float(KG_LEVELS[kg_level][1])
	if sim.money < cost:
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(cost)
	sim.spend(cost, "Город: детский сад «%s»" % kg_name())
	kg_level += 1
	rel = minf(100.0, rel + 6.0)
	sim.notify(L.t("Заводской детсад «%s»: теперь %d мест. Родители спокойнее, прогулов меньше.") % [kg_name(), kg_places()], Sim.LVL_GOOD)
	sim.paper.add(L.t("Город"), L.t("Детсад «%s» принимает малышей") % kg_name(), L.t("Завод открыл группы на %d мест. Мамы говорят спасибо!") % kg_places())
	return ""


func kg_name() -> String:
	return L.t("Шестерёнка")


## Нет садика — иногда приходится сидеть с ребёнком.
func kid_absent(w: Worker) -> bool:
	if w.kids <= 0 or has_kg_place(w):
		return false
	return sim.rng.randf() < (0.02 if w.female else 0.008) * w.kids


# ================================================================ Дом культуры

func dk_buy() -> String:
	if dk:
		return L.t("ДК уже на балансе завода")
	if not sim.dev.on("city3"):
		return L.t("Дом культуры берёт на баланс завод со ступенью «Шефство» (Управление → Развитие)")
	if sim.money < DK_COST:
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(DK_COST)
	sim.spend(DK_COST, "Город: Дом культуры «Машиностроитель»")
	dk = true
	dk_since = sim.day()
	rel = minf(100.0, rel + 12.0)
	sim.story.info(L.t("ДК «Машиностроитель»"), L.t("Завод взял на баланс Дом культуры: кружки, ансамбль, концерты к праздникам. Город доволен."), "culture", Sim.LVL_GOOD, Vector2i(-1, -1), true)
	return ""


func _dk_week() -> void:
	if not dk:
		return
	sim.spend(DK_WEEK, "Город: содержание ДК")
	var clubs := [L.t("хор ветеранов"), L.t("секция бокса"), L.t("кружок радиолюбителей"), L.t("ансамбль «Токарушка»"), L.t("шахматный клуб"), L.t("фотокружок")]
	var n := 0
	for w in sim.workers:
		if sim.rng.randf() < 0.3:
			Mood.add(sim, w, "dk_club")
			n += 1
	if n > 0 and sim.rng.randf() < 0.4:
		var c: String = clubs[sim.rng.randi_range(0, clubs.size() - 1)]
		sim.paper.add(L.t("Культура"), L.t("В ДК «Машиностроитель» — %s") % c, L.t("Записались %d наших работников. Приходите и вы!") % n)


## Праздник в ДК: вызывается из праздничных писем.
func dk_concert() -> void:
	if not dk:
		return
	for w in sim.workers:
		Mood.add(sim, w, "dk_concert")
	sim.reputation = minf(100.0, sim.reputation + 1.0)


# ================================================================ заводское радио

func radio_station() -> Thing:
	for t in sim.things_of("radio"):
		if t.built and sim.power.powered(t):
			return t
	return null


## Помещения, где слышно радио: есть громкоговоритель под током.
func radio_rooms() -> Array:
	var out: Array = []
	if radio_station() == null:
		return out
	for t in sim.things_of("speaker"):
		if not t.built or not sim.power.powered(t):
			continue
		var r := sim.rooms.room_at(t.cell)
		if r and not out.has(r):
			out.append(r)
	return out


func hears_radio(w: Worker) -> bool:
	var r := sim.rooms.room_at(w.cell())
	return r != null and radio_rooms().has(r)


func _tick_radio(prev: float, now: float) -> void:
	if radio_station() == null or not sim.is_workday():
		return
	for k in ["news", "gym"]:
		if not bool(radio.get(k, false)):
			continue
		var tt := float(RADIO_PROGRAMS[k]["time"])
		if prev < tt and now >= tt:
			for w in sim.workers:
				if w.present and hears_radio(w):
					Mood.add(sim, w, "radio_" + k)
					if k == "gym":
						w.needs["rest"] = minf(100.0, float(w.needs["rest"]) + 8.0)
	if bool(radio.get("music", false)):
		for w2 in sim.workers:
			if w2.present and w2.task and w2.task.kind == "eat" and hears_radio(w2) and not _had(w2, "radio_music"):
				Mood.add(sim, w2, "radio_music")


func _had(w: Worker, id: String) -> bool:
	return w.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) == id and float(t["until"]) > sim.minute)


# ================================================================ кот

## Прибился кот: предложение оставить (раз за игру, когда есть столовая и прошло несколько дней).
func _cat_offer(force: bool = false) -> void:
	if cat or cat_offered or (sim.day() < 4 and not force) or (not sim.story.enabled and not force):
		return
	var canteen := sim.rooms.list.any(func(r: Rooms.Room) -> bool: return r.type == "canteen")
	if not force and not canteen and sim.day() < 12:
		return
	if not force and sim.rng.randf() > 0.35:
		return
	cat_offered = true
	var c := Cat.make(sim)
	var t := Nicks.gendered(L.t("У проходной мяукает %s {кот|кошка} — %s, {тощий|тощая}, но с характером. Рабочие уже несут {ему|ей} колбасу из столовой."), c.female) % [c.fur_name(), c.shown_name()]
	sim.story.letter("cat", Nicks.gendered(L.t("На заводе прибил{ся|ась} {кот|кошка}"), c.female), t, "cat", Sim.LVL_GOOD,
		[{"text": L.t("Оставить: поставить миску (Объекты → Декор)"), "hint": L.t("Людям приятно погладить, крысы обходят склад стороной")},
		{"text": L.t("Отдать в добрые руки"), "hint": ""}], 0, {"name": c.name, "fur": c.fur, "female": c.female})


func on_letter(ev: String, d: Dictionary, choice: int) -> void:
	match ev:
		"cat":
			if choice == 0:
				var c := Cat.make(sim)
				c.name = str(d.get("name", c.name))
				c.fur = str(d.get("fur", c.fur))
				c.female = bool(d.get("female", c.female))
				c.pos = Vector2(_spawn_cell()) + Vector2(0.5, 0.5)
				c.until = sim.minute
				cat = c
				sim.stats["cat"] = 1
				sim.notify(Nicks.gendered(L.t("%s теперь живёт на заводе. Поставьте миску (Объекты → Декор) — без неё {он|она} уйдёт."), c.female) % c.title(), Sim.LVL_GOOD)
				var ct := c.title() if L.is_en() else c.title().to_lower()   # в английском кличка — с большой буквы
				sim.paper.add(L.t("Новости"), L.t("Пополнение: %s") % ct, Nicks.gendered(L.t("%s %s поселил{ся|ась} на заводе. Просим не кормить колбасой — только из миски!"), c.female) % [c.fur_name().capitalize(), ct])
		"kittens":
			if cat == null:
				return
			if choice == 0:
				var got := 0
				for w in sim.workers:
					if got < 3 and sim.rng.randf() < 0.4:
						Mood.add(sim, w, "kittens")
						w.add_history(sim.day(), Nicks.gendered(L.t("Взял{|а} котёнка у заводской кошки"), w.female))
						got += 1
				sim.notify(L.t("Котят разобрали по домам: %d счастливых %s.") % [maxi(1, got), Defs.plural(maxi(1, got), "семья", "семьи", "семей")], Sim.LVL_GOOD)


func _spawn_cell() -> Vector2i:
	for r: Rooms.Room in sim.rooms.list:
		if r.type == "canteen" and not r.cells.is_empty():
			for c in r.cells:
				if sim.world.passable(c) and sim.world.occ[sim.world.idx(c)] < 0:
					return c
	return Vector2i(sim.gate_x + 1, sim.world.sidewalk_row - 1)


func _tick_cat(dt: float) -> void:
	if cat == null:
		return
	cat.tick(dt)
	# погладить кота: те, кто рядом и не занят у станка
	_pet_t -= dt
	if _pet_t > 0.0:
		return
	_pet_t = 2.0
	for w in sim.workers:
		if not w.present or w.carrying >= 0:
			continue
		if w.pos.distance_to(cat.pos) > 1.6:
			continue
		if w.anim == "work" and not (w.task and w.task.kind in ["eat", "rest", "smoke", "wander"]):
			continue
		if int(w.get_meta("cat_day", -1)) == sim.day():
			continue
		w.set_meta("cat_day", sim.day())
		if (w.id * 7 + 3) % 11 == 0:
			continue   # не все любят кошек
		Mood.add(sim, w, "cat_pet")


func _cat_morning() -> void:
	if cat == null:
		_cat_offer()
		return
	var bowl := cat._bowl()
	if bowl:
		sim.spend(40.0, "Корм для кота")
		cat.set_meta("no_bowl", 0)
	else:
		var nb := int(cat.get_meta("no_bowl", 0)) + 1
		cat.set_meta("no_bowl", nb)
		if nb == 2:
			sim.notify(L.t("%s голодает: поставьте миску (Объекты → Декор), иначе уйдёт.") % cat.title(), Sim.LVL_WARN)
		if nb >= 4:
			sim.story.info(L.t("%s ушёл") % cat.title() if not cat.female else L.t("%s ушла") % cat.title(), Nicks.gendered(L.t("Без миски на заводе голодно — %s ушёл{|а} искать место посытнее."), cat.female) % cat.shown_name(), "cat", Sim.LVL_WARN)
			cat = null
			cat_gone = true
			return
	if cat.female and sim.day() - cat.since == 24:
		sim.story.letter("kittens", L.t("У %s котята!") % cat.shown_name(), L.t("%s принесла пятерых котят — в коробке за верстаком. Рабочие ходят смотреть по очереди.") % cat.shown_name(), "cat", Sim.LVL_GOOD,
			[{"text": L.t("Раздать работникам"), "hint": L.t("Кому-то достанется котёнок — радость")}, {"text": L.t("Отвезти в приют"), "hint": ""}], 0, {})


## Крысы на складе — если кота нет. Кот их ловит.
func _rats_week() -> void:
	if sim.day() < 10:
		return
	if cat:
		if sim.rng.randf() < 0.5:
			cat.mice += 1
			if cat.mice % 3 == 1:
				sim.paper.add(L.t("Новости"), L.t("%s на страже склада") % cat.title(), Nicks.gendered(L.t("Поймал{|а} уже %d %s. Крысы обходят завод стороной."), cat.female) % [cat.mice, Defs.plural(cat.mice, "крысу", "крысы", "крыс")])
		return
	var stor := sim.things_of("storage").size()
	if stor < 2 or sim.rng.randf() > 0.18:
		return
	var lost := 0
	for c in Defs.consumables.keys():
		var have := float(sim.cons.get(c, 0.0))
		if have >= 4.0:
			var l := floorf(have * 0.15)
			sim.cons[c] = have - l
			lost += int(l)
	for w in sim.workers:
		if w.present:
			Mood.add(sim, w, "rats")
	sim.story.info(L.t("Крысы на складе"), L.t("Погрызли упаковки: пропало расходников — %d ед. Кошка бы помогла.") % lost, "thief", Sim.LVL_WARN)


# ================================================================ отношения с городом

func _rel_week() -> void:
	var d := 0.0
	if not residents().is_empty():
		d += 1.5
	if kitchen_ready() and not cooks().is_empty():
		d += 1.5
	if not medbays().is_empty() and not nurses().is_empty():
		d += 1.5
	d += kg_level * 1.5
	if dk:
		d += 2.0
	if radio_station():
		d += 0.5
	d += minf(3.0, sim.workers.size() / 10.0)
	d -= 1.5   # город ждёт большего с каждым годом
	var fired := int(sim.stats.get("fired_week", 0))
	d -= fired * 3.0
	sim.stats["fired_week"] = 0
	var old := rel
	rel = clampf(rel + d, 0.0, 100.0)
	sim.stats["town_rel"] = maxi(int(sim.stats.get("town_rel", 0)), int(rel))
	if old < 60.0 and rel >= 60.0:
		sim.story.info(L.t("Город доволен заводом"), L.t("Администрация благодарит за рабочие места и заботу о людях. В отделе кадров теперь больше кандидатов."), "town", Sim.LVL_GOOD)
	elif old < 75.0 and rel >= 75.0:
		sim.story.info(L.t("Льгота от города"), L.t("Совет депутатов утвердил льготу по местным налогам для градообразующего предприятия: налог с выручки на 1% ниже."), "town", Sim.LVL_GOOD, Vector2i(-1, -1), true)


func rel_text() -> String:
	if rel >= 75.0:
		return L.t("гордится заводом")
	if rel >= 60.0:
		return L.t("доволен")
	if rel >= 35.0:
		return L.t("присматривается")
	return L.t("недоволен")


## Скидка налога для любимого городом завода.
func tax_break() -> float:
	return 0.01 if rel >= 75.0 else 0.0


## Сколько кандидатов прибавляется по понедельникам: иногородние в общежитие, местные — когда город доволен.
func extra_candidates() -> int:
	var n := 0
	if rel >= 60.0:
		n += 1
	return n


func away_candidates() -> int:
	if not invite_away or not sim.dev.on("hr2"):
		return 0
	return mini(3, int(free_beds() / 2))


# ================================================================ настроение

## Постоянные составляющие настроения (как черты): общежитие, детсад.
func mood_parts(w: Worker) -> Array:
	var out: Array = []
	var bed := bed_of(w)
	if bed:
		var r := sim.rooms.room_of_thing(bed)
		var lv := sim.upkeep.level(r) if r else 1
		if lv >= 3:
			out.append([L.t("Уютное общежитие"), 5.0, "dorm_cozy"])
		elif lv >= 2:
			out.append([L.t("Живу в заводском общежитии"), 3.0, "dorm"])
		else:
			out.append([L.t("Общежитие — голые стены"), -2.0, "dorm_bare"])
	elif w.from_away:
		out.append([L.t("Негде жить — снимаю угол"), -6.0, "nohome"])
	if w.kids > 0:
		if has_kg_place(w):
			out.append([L.t("Ребёнок в заводском садике"), 5.0, "kg"])
		elif sim.progress.stage >= 3:
			out.append([L.t("Не с кем оставить ребёнка"), -2.0, "nokg"])
	return out


# ================================================================ время

func tick(dt: float) -> void:
	var now := sim.tod()
	if _last_tod >= 0.0:
		_tick_radio(_last_tod if _last_tod <= now else -1.0, now)
	_last_tod = now
	_tick_cat(dt)


func morning() -> void:
	meals_today = 0
	portions = 0   # вчерашнее не подают
	assign_beds()
	var res := residents().size()
	if res > 0:
		sim.earn(DORM_FEE * res, "Плата за общежитие: %d %s" % [res, Defs.plural(res, "жилец", "жильца", "жильцов")])
	_flu_morning()
	_cat_morning()
	if sim.weekday() == 0:
		if kg_level > 0:
			sim.spend(float(KG_LEVELS[kg_level][2]), "Город: содержание детсада")
		_dk_week()
		_rats_week()
		_rel_week()


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"rel": rel, "beds": beds, "invite": invite_away, "kg": kg_level, "dk": dk, "dk_since": dk_since, "radio": radio,
		"vacc": vaccinated_until, "cat": cat.to_dict() if cat else {}, "cat_offered": cat_offered, "cat_gone": cat_gone,
		"meals": meals_total, "flu": flu_cases}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	rel = float(d.get("rel", 40.0))
	beds = d.get("beds", {})
	invite_away = bool(d.get("invite", true))
	kg_level = int(d.get("kg", 0))
	dk = bool(d.get("dk", false))
	dk_since = int(d.get("dk_since", -1))
	radio = d.get("radio", radio)
	vaccinated_until = int(d.get("vacc", -1))
	var cd: Dictionary = d.get("cat", {})
	cat = Cat.from_dict(sim, cd) if not cd.is_empty() else null
	cat_offered = bool(d.get("cat_offered", false))
	cat_gone = bool(d.get("cat_gone", false))
	meals_total = int(d.get("meals", 0))
	flu_cases = int(d.get("flu", 0))
