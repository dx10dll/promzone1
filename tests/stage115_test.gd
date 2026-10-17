extends SceneTree
## Тест версии 1.15 «Люди»: правки из документа — ток от трансформатора и вода от насоса без городских
## сетей, укомплектованный быт на старте, шкафчик на двоих, вместительные поддоны, слесари у верстака,
## закреплённые рабочие места, разработки деревом.
## godot --headless --path . -s res://tests/stage115_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func run(sim: Sim, minutes: float, until: Callable = Callable()) -> float:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5
		if until.is_valid() and bool(until.call()):
			break
	return t


func _init() -> void:
	Defs.load_all()

	print("— ток и вода без городских сетей")
	var g := Scenario.new_game("garage", "mech", "calm", 151)
	g.story.enabled = false
	g.power.update_topology()
	g.power.tick(0.1)
	check(not g.power.has_method("request_upgrade"), "заявок в сетевую компанию больше нет")
	check(absf(g.power.total_kw() - 40.0) < 0.01, "в гараже подстанция: %d кВт" % int(g.power.total_kw()))
	var lathe: Thing = g.things_of("machine")[0]
	check(g.power.powered(lathe), "станок под током от подстанции")
	check(Thing.rotations("cabinet") == 1 and Thing.rotations("toilet") == 4, "трансформатор не крутится, у кабинки четыре стороны входа")
	var toilet: Thing = g.things_of("toilet")[0]
	check(g.water.has_water(toilet), "в туалете вода от насосной — сразу с начала игры")
	var cab: Thing = g.things.get(g.power.grid_input_id())
	check(cab != null and cab.def_id == "substation", "ввод — подстанция 2×2")
	var tr2: Thing = null
	for d in [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 0)]:
		if tr2 == null and g.can_place("battery", cab.cell + d) == "":
			tr2 = g.place_thing("battery", cab.cell + d, true, false)
	g.rooms.update()
	g.power.update_topology()
	g.power.tick(0.1)
	check(tr2 != null and absf(g.power.total_kw() - 60.0) < 0.01 and absf(g.power.net_of_thing(lathe).capacity - 60.0) < 0.01, "аккумулятор у подстанции — мощность выросла: %d кВт" % int(g.power.net_of_thing(lathe).capacity))
	var sb := Scenario.new_game("sandbox", "mech", "calm", 152, {"money": 1000000, "all_open": true})
	sb.power.update_topology()
	check(sb.power.total_kw() >= 40.0 and sb.things.size() <= 3, "песочница: подстанция, насосная и электрокотёл, %d кВт" % int(sb.power.total_kw()))

	print("— быт на старте укомплектован")
	g.rooms.update()
	var types := {}
	var bad: Array[String] = []
	for r in g.rooms.list:
		types[r.type] = true
		if r.type != "" and not r.valid:
			bad.append("%s: %s" % [r.type, ", ".join(r.missing)])
	check(types.has("canteen") and types.has("wc") and types.has("locker"), "гараж: столовая, туалет и бытовка — отдельными комнатками")
	check(bad.is_empty(), "гараж: недоукомплектованных зон нет %s" % str(bad))
	var cwc := g.rooms.room_of_thing(toilet)
	check(cwc != null and cwc.type == "wc" and g.rooms.room_of_thing(g.things_of("table")[0]) != cwc, "туалет — не в столовой")
	var f := Scenario.new_game("field", "mech", "calm", 153)
	f.rooms.update()
	var fbad: Array[String] = []
	var ftypes := {}
	for r2 in f.rooms.list:
		ftypes[r2.type] = true
		if r2.type != "" and not r2.valid:
			fbad.append("%s: %s" % [r2.type, ", ".join(r2.missing)])
	check(ftypes.has("canteen") and ftypes.has("wc") and ftypes.has("locker") and fbad.is_empty(), "чистое поле: раздевалка, туалет и бытовка, всё укомплектовано %s" % str(fbad))
	var viol: Array = f.inspect.violations("fire")
	check(not viol.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_ext"), "пожарный надзор: огнетушители есть, туалету не нужен")

	print("— шкафчик на двоих")
	var lk2: Thing = null
	for t: Thing in g.things.values():
		if t.def_id == "locker2":
			lk2 = t
			break
	check(lk2 != null and int(lk2.def().get("seats", 1)) == 2, "в бытовке гаража шкафчики на двоих")
	var seen := {}
	for w in g.workers:
		var l: Thing = g.brain._locker_for(w)
		if l:
			seen[l.id] = int(seen.get(l.id, 0)) + 1
	var shared := false
	for k in seen.keys():
		if int(seen[k]) == 2:
			shared = true
	check(shared, "двое закреплены за одним шкафчиком на двоих: %s" % str(seen))

	print("— стройматериалы: вместительные поддоны")
	check(BuildMats.pallet("bm_brick") >= 16 and BuildMats.pallet("bm_cement") >= 24, "кирпича на поддоне %d, цемента %d" % [BuildMats.pallet("bm_brick"), BuildMats.pallet("bm_cement")])
	f.money += 500000.0
	var nw := 0
	for x in range(30, 40):
		f.place_wall_bp(Vector2i(x, 12), World.W_BRICK)
		nw += 1
	f.bmats._t = 0.0
	f.bmats.tick(1.0)
	var ordered := 0
	for o: Dictionary in f.bmats.orders:
		ordered += int((o["mats"] as Dictionary).get("bm_brick", 0))
	check(ordered == nw, "заказали ровно сколько нужно: %d кирпича на %d клеток" % [ordered, nw])

	print("— слесарь: доработка брака у верстака")
	var fit := S.hire(g, "fitter", "fitting", 10)
	check(fit.prof_name() == "Слесарь" and fit.main_skill() == "fitting", "новая профессия: слесарь, навык «Слесарное дело»")
	var bin: Thing = null
	for t2: Thing in g.things_of("storage"):
		if t2.def_id == "scrap_bin":
			bin = t2
	var junk: Array[Item] = []
	for k2 in 3:
		var it := g.new_item("part", "bushing", "scrap")
		it.step = 1
		it.defect = true
		g.put_in_thing(it, bin, 0)
		junk.append(it)
	g.minute = 1440.0 + 8.0 * 60.0 + 30.0
	for w2 in g.workers:
		w2.present = true
		w2.dressed = true
		w2.pos = Vector2(20.5, 12.5)
	run(g, 300.0, func() -> bool: return junk.all(func(i: Item) -> bool: return not g.items.has(i.id) or i.rw))
	var tried := junk.filter(func(i: Item) -> bool: return g.items.has(i.id) and i.rw).size()
	var saved := int(g.stats.get("reworked", 0))
	check(tried == 3, "слесарь попробовал доработать весь брак: %d из 3" % tried)
	check(saved >= 1, "часть брака спасена и ушла на ОТК: %d" % saved)

	print("— закреплённые рабочие места")
	Workplace.auto_assign(g)
	var gromov := g.workers[0]
	check(lathe.owner == gromov.id, "токарный закреплён за токарем: %s" % (Workplace.owner_of(g, lathe).full_name() if lathe.owner >= 0 else "никто"))
	var bench: Thing = null
	for t3: Thing in g.things.values():
		if t3.def_id == "workbench":
			bench = t3
	check(bench != null and bench.owner == fit.id, "слесарный верстак закреплён за слесарем")
	var t2w := S.hire(g, "turner", "turning", 5)
	gromov.present = true
	gromov.sick_until = -1.0
	gromov.away_why = ""
	gromov.task = null
	check(not Workplace.may_use(g, t2w, lathe) and Workplace.may_use(g, gromov, lathe), "хозяин свободен — чужой за его станок не встаёт")
	gromov.sick_until = g.minute + 2880.0
	gromov.away_why = "на больничном"
	check(Workplace.may_use(g, t2w, lathe), "хозяин на больничном — работает любой, кто умеет")
	gromov.sick_until = -1.0
	gromov.away_why = ""
	var busy := Task.new()
	busy.kind = "haul"
	gromov.task = busy
	check(Workplace.may_use(g, t2w, lathe), "хозяин занят другим делом — тоже можно")
	gromov.task = null
	check(Workplace.owner_waiting(g, lathe, t2w), "хозяин освободился — сменщик уступит после детали")
	Workplace.assign(g, lathe, t2w)
	check(lathe.owner == t2w.id and Workplace.places_of(g, t2w).has(lathe), "место можно перезакрепить")
	var d := g.to_dict()
	var g2 := Sim.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(g2.things[lathe.id].owner == t2w.id, "закрепление сохраняется")
	g2.dispose()

	print("— разработки деревом")
	var lay := Office.research_layout()
	var widest := 0
	for b: Array in lay:
		for row: Array in b[1]:
			widest = maxi(widest, row.size())
	check(lay.size() >= 6 and widest <= 2, "веток %d, в ярусе не больше двух разработок" % lay.size())
	check(Defs.research.has("rework_cards") and Defs.research.has("fit_jigs"), "у слесарей свои разработки")
	check(not g.office.research_open(), "без технолога дерево закрыто")
	S.hire(g, "technologist", "engineering", 6)
	check(g.office.research_open() and g.office.research_status("fast_cutting") == "ready", "с технологом — открыто, можно начинать")

	print("— РП-8: пять жизненных потребностей")
	var h := Scenario.new_game("garage", "mech", "calm", 155)
	h.story.enabled = false
	var vk := h.workers[0]
	var lf0 := Mood.life(h, vk)
	check(lf0.size() == 5 and lf0.values().all(func(x: Dictionary) -> bool: return float(x["v"]) >= 0.0 and float(x["v"]) <= 100.0), "быт, деньги, работа, коллектив, дом — от 0 до 100")
	var m0 := float(lf0["money"]["v"])
	Mood.add(h, vk, "wage_cut")
	check(float(Mood.life(h, vk)["money"]["v"]) < m0, "урезали ставку — просели «деньги»")
	for k3 in 3:
		Mood.add(h, vk, "fight")
		Mood.add(h, vk, "argued")
	var worst := Mood.life_worst(h, vk)
	check(not worst.is_empty() and str(worst[2]) != "", "проседающая потребность с подсказкой: %s" % (str(worst[1]) if not worst.is_empty() else "—"))

	print("— РП-10: экзамен на разряд")
	var tu := S.hire(h, "turner", "turning", 9)
	tu.grade_n = 3
	tu.wage = 2000
	check(h.career.exam_block(tu) == "", "токарь с навыком 9 и 3-м разрядом может сдавать")
	check(h.career.request_exam(tu) == "" and h.career.exam_pending(tu), "подал на экзамен")
	h.minute = 1440.0 + 8.0 * 60.0 + 30.0
	for w3 in h.workers:
		w3.present = true
		w3.dressed = true
		w3.pos = Vector2(20.5, 12.5)
	run(h, 240.0, func() -> bool: return not h.career.exam_pending(tu))
	check(not h.career.exam_pending(tu), "сделал пробную деталь, экзамен закончен")
	check(tu.grade_n == 4 or tu.exam_cd > h.day(), "сдал на 4-й или ждёт пересдачи: разряд %d" % tu.grade_n)
	if tu.grade_n == 4:
		check(h.story.letters.any(func(l: Dictionary) -> bool: return str(l["ev"]) == "raise_ask"), "сдал — просит прибавку по разряду")
		var la: Dictionary = h.story.letters.filter(func(l: Dictionary) -> bool: return str(l["ev"]) == "raise_ask")[0]
		h.story.resolve(int(la["id"]), 0)
		check(tu.wage > 2000, "прибавили до ставки по разряду: %d" % tu.wage)
	var lab := S.hire(h, "laborer", "haul", 6)
	check(h.career.exam_block(lab) != "", "у разнорабочего разрядов нет")

	print("— РП-9: индексация")
	h.career.last_quarter -= 1
	var wsum := 0
	for w4 in h.workers:
		wsum += w4.wage
	h.career.morning()
	check(absf(People.wage_index - Careers.INDEX_K) < 0.001, "рыночные ставки выросли на 4%")
	var il: Array = h.story.letters.filter(func(l: Dictionary) -> bool: return str(l["ev"]) == "indexation")
	check(not il.is_empty(), "письмо: люди ждут индексации")
	if not il.is_empty():
		h.story.resolve(int(il[0]["id"]), 0)
		var wsum2 := 0
		for w5 in h.workers:
			wsum2 += w5.wage
		check(wsum2 > wsum, "проиндексировали всем: %d → %d ₽ в смену" % [wsum, wsum2])

	print("— РП-11: возраст, ветераны, пенсия")
	var ages := h.workers.map(func(x: Worker) -> int: return x.age)
	h.career.last_year -= 1
	h.career.morning()
	check(h.workers.map(func(x: Worker) -> int: return x.age) == ages.map(func(a: int) -> int: return a + 1), "новый год — все на год старше")
	var olga := h.workers[1]
	olga.hired_day = h.day() - h.season.days_per_year()
	h.career.morning()
	check(h.career.is_veteran(olga) and Mood.veteran(h, olga), "год на заводе — ветеран завода")
	var fw := People.make(h.rng, "qc")
	fw.female = true
	fw.age = 56
	var mw := People.make(h.rng, "turner")
	mw.female = false
	mw.age = 56
	check(h.career.pensioner(fw) and not h.career.pensioner(mw), "пенсия: женщинам с 55, мужчинам с 60")
	check(h.career.rest_k(fw) > 1.0 and h.career.rest_k(lab) <= h.career.rest_k(fw), "с годами устают быстрее")

	print("— Н-1: рацпредложение под станок и деталь")
	var rs := h.career.rational_specific()
	check(not rs.is_empty() and str(rs[0]).contains(":"), "предложение под конкретный станок или деталь: %s" % (str(rs[2]) if not rs.is_empty() else "—"))
	if h.career.propose_rational():
		var rl: Dictionary = h.story.letters.filter(func(l: Dictionary) -> bool: return str(l["ev"]) == "rational2")[-1]
		var key := str(rl["data"]["key"])
		h.story.resolve(int(rl["id"]), 0)
		check(h.story.perk(key) < 1.0, "внедрили: %s ×%.2f" % [key, h.story.perk(key)])

	print("— приказы: работать здесь или идти туда, потом сам возвращается")
	var gl := h.things_of("machine")[0]
	var gt := h.workers[0]
	for w6 in h.workers:
		h.brain.abort(w6)
		if w6 != gt:
			w6.present = false
	gl.owner = -1
	var msg := h.brain.give_order(gt, gl.cell)
	check(not gt.order.is_empty() and int(gt.order["thing"]) == gl.id, "приказ: «%s»" % msg)
	var so := {"seen": false}
	run(h, 60.0, func() -> bool:
		if gt.task and gt.task.label.contains("по приказу"):
			so["seen"] = true
		return bool(so["seen"]))
	check(bool(so["seen"]), "работает по приказу: %s" % gt.activity)
	var cell := Vector2i(24, 15)
	gt.task = null
	h.brain.give_order(gt, cell)
	check(not gt.order.is_empty() and int(gt.order["thing"]) == -1, "приказ идти в клетку")
	run(h, 90.0, func() -> bool: return gt.order.is_empty())
	check(gt.order.is_empty(), "постоял, где велели, и сам вернулся к работе")
	var itr := S.hire(h, "accountant", "office", 5)
	itr.present = true
	check(h.brain.give_order(itr, cell) != "" and itr.order.is_empty(), "ИТР приказы не принимают")

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
