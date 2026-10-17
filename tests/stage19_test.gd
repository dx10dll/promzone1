extends SceneTree
## Тест версии 1.9 «Город»: общежитие и иногородние, кухня с поваром и горячие обеды, медпункт и грипп,
## детсад, ДК, заводское радио, кот, отношения с городом, сохранение.
## godot --headless --path . -s res://tests/stage19_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(sim: Sim, minutes: float) -> void:
	var end := sim.minute + minutes
	while sim.minute < end:
		sim.tick(0.5)


func _to(sim: Sim, tod: float) -> void:
	while not sim.is_workday() or sim.tod() < tod - 0.5 or sim.tod() > tod + 1.0:
		sim.tick(0.5)


func _has(w: Worker, id: String) -> bool:
	return w.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) == id)


func _init() -> void:
	Defs.load_all()
	var sim := Scenario.new_game("garage", "mech", "calm", 19)
	sim.story.enabled = false
	S.big_shop(sim)
	sim.office.all_depts = true   # с 1.11 соцсфера, иногородние и шефство — ступени развития (их проверяет stage111)
	var t := sim.town
	var tile := int(Defs.floors["tile"]["id"])
	var lino := int(Defs.floors["lino"]["id"])
	# 1.15: слева от бокса теперь пристройка (столовая, туалет, бытовка) — соцкорпус ниже, у забора
	S._box(sim, Rect2i(1, 20, 7, 6), tile, Vector2i(3, 25))      # столовая: дверь снизу
	S._box(sim, Rect2i(7, 20, 6, 6), lino, Vector2i(10, 25))     # общежитие
	S._box(sim, Rect2i(12, 20, 7, 6), tile, Vector2i(18, 22))    # медпункт: дверь справа
	sim.place_thing("dining_table", Vector2i(2, 23), true, false)
	sim.place_thing("chair", Vector2i(2, 24), true, false)
	sim.place_thing("chair", Vector2i(3, 24), true, false)
	sim.place_thing("chair", Vector2i(3, 22), true, false)
	sim.place_thing("fridge", Vector2i(6, 21), true, false)
	var stove := sim.place_thing("stove", Vector2i(4, 21), true, false)
	sim.place_thing("serving_line", Vector2i(4, 23), true, false)
	var bed1 := sim.place_thing("bunk_bed", Vector2i(8, 21), true, false)
	sim.place_thing("bunk_bed", Vector2i(8, 23), true, false)
	sim.place_thing("locker", Vector2i(11, 23), true, false)
	sim.place_thing("med_couch", Vector2i(13, 21), true, false)
	sim.place_thing("med_cabinet", Vector2i(16, 21), true, false)
	sim.place_thing("sink", Vector2i(17, 21), true, false)
	sim.place_thing("radio_station", Vector2i(2, 21), true, false)
	sim.place_thing("loudspeaker", Vector2i(3, 22), true, false)
	Scenario.autowire(sim)
	Scenario.autolight(sim, false)
	Scenario.autopipe(sim)
	sim.world.cable_rev += 1
	sim.rooms.update()
	sim.rooms.assign(sim.rooms.room_at(Vector2i(3, 22)), "canteen")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(9, 22)), "dorm")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(14, 22)), "medbay")
	sim.rooms.update()
	sim.power.tick(0.1)
	sim.rooms.update()   # 1.18: насосная под током — вода в медпункте

	print("— помещения")
	check(Rooms.TYPES.has("dorm") and Rooms.TYPES.has("medbay"), "новые типы помещений: общежитие и медпункт")
	check(not t.dorm_rooms().is_empty(), "общежитие оборудовано: " + Rooms.req_text("dorm"))
	check(not t.medbays().is_empty(), "медпункт оборудован: " + Rooms.req_text("medbay"))
	check(t.kitchen() == stove, "плита стоит в столовой")
	check(sim.power.powered(stove), "плита под током")

	print("— общежитие")
	check(t.dorm_capacity() == 4 and t.free_beds() == 4, "две двухъярусные кровати — четыре койки")
	check(t.away_candidates() >= 1, "есть свободные койки — приедут иногородние: %d" % t.away_candidates())
	sim.refresh_candidates()
	var away_idx := -1
	for i in sim.candidates.size():
		if bool(sim.candidates[i].get("faraway", false)):
			away_idx = i
	check(away_idx >= 0, "среди кандидатов есть иногородние")
	var m0 := sim.money
	check(sim.hire(away_idx) == "", "иногороднего наняли")
	var newb: Worker = sim.workers[sim.workers.size() - 1]
	check(newb.from_away and t.is_resident(newb), "иногородний живёт в общежитии")
	check(newb.exit_cell.distance_to(t.bed_of(newb).cell) <= 2.0, "домой ходит в общежитие, а не на улицу")
	check(sim.town.mood_parts(newb).any(func(p: Array) -> bool: return str(p[0]).to_lower().contains("общежити")), "мысль про общежитие в настроении")
	var mfee := sim.money
	t.morning()
	check(sim.money > mfee, "плата за койку: +%s" % Defs.money_str(sim.money - mfee))
	for k in 3:
		var wa := People.make(sim.rng, "laborer")
		wa.from_away = true
		sim.candidates.append(wa.to_dict())
		sim.hire(sim.candidates.size() - 1)
	check(t.free_beds() == 0, "общежитие заполнено")
	var wb := People.make(sim.rng, "laborer")
	wb.from_away = true
	sim.candidates.append(wb.to_dict())
	check(sim.hire(sim.candidates.size() - 1) != "", "мест нет — иногороднего не нанять")
	sim.candidates.pop_back()

	print("— кухня и повар")
	check(t.kitchen_ready(), "кухня готова: плита, ток, раздача")
	var cook := S.hire(sim, "cook", "cook", 6)
	check(cook.prof_name() == "Повар" and cook.skill("cook") == 6, "профессия «Повар», навык «Кулинария»")
	_to(sim, 8.0 * 60.0 + 30.0)
	# повар может отойти в туалет или на перекур — смотрим, что большую часть времени он у плиты
	var at_stove := 0
	for k2 in 180:
		sim.tick(0.5)
		if (cook.task != null and cook.task.kind == "cook") or cook.activity.contains("Готовит") or cook.activity.contains("раздач"):
			at_stove += 1
	check(t.portions > 0, "повар наготовил порций: %d" % t.portions)
	check(at_stove >= 30 or t.portions >= t.portions_needed(), "повар у плиты или на раздаче: %d шагов из 180" % at_stove)
	var p0 := t.portions
	var eater: Worker = sim.workers[0]
	check(t.take_portion() and t.portions == p0 - 1, "порцию взяли")
	_to(sim, 11.0 * 60.0 + 50.0)
	_run(sim, 150.0)
	var hot := 0
	for w in sim.workers:
		if _has(w, "ate_hot"):
			hot += 1
	check(hot >= 2, "горячий обед в столовой: %d человек" % hot)
	check(int(sim.stats.get("hot_meals", 0)) >= hot, "счётчик горячих обедов")

	print("— медпункт")
	var nurse := S.hire(sim, "nurse", "medicine", 6)
	_to(sim, 9.0 * 60.0 + 30.0)
	_run(sim, 30.0)
	check(nurse.present and t.medbay_ready(), "фельдшер на смене — медпункт работает")
	var inj: Worker = sim.workers[1]
	inj.sick_until = -1.0
	sim.story.enabled = true
	sim.story.injure(inj, "work")
	sim.story.enabled = false
	var sick_days := int(ceil((inj.sick_until - sim.minute) / 1440.0))
	check(_has(inj, "nurse_helped"), "фельдшер помог пострадавшему")
	var sd: Array = Defs.events.get("sick_days", [2, 6])
	check(sick_days <= int(ceil(float(sd[1]) * 0.6)) + 1, "больничный короче: ~%d дн. (без фельдшера — до %d)" % [sick_days, int(sd[1])])
	inj.sick_until = -1.0
	inj.away_why = ""
	check(t.vaccinate() == "" and t.vaccinated_until > sim.day(), "прививки от гриппа сделаны")

	print("— детсад")
	var mom := S.hire(sim, "qc", "qc", 5)
	mom.female = true
	mom.kids = 1
	check(t.parents().has(mom), "у работницы ребёнок")
	check(t.mood_parts(mom).any(func(p: Array) -> bool: return float(p[1]) < 0.0), "без садика — «не с кем оставить ребёнка»")
	var mk := sim.money
	check(t.kg_upgrade() == "" and t.kg_level == 1 and t.kg_places() == 6, "детсад «Шестерёнка» на 6 мест")
	check(sim.money < mk, "открытие групп стоит денег")
	check(t.has_kg_place(mom) and t.mood_parts(mom).any(func(p: Array) -> bool: return float(p[1]) > 0.0), "мама получила место: настроение лучше")
	check(not t.kid_absent(mom), "с садиком не сидит дома с ребёнком")

	print("— Дом культуры")
	sim.office.all_depts = false
	check(t.dk_buy() != "", "ДК — только со ступенью «Шефство»")
	sim.office.all_depts = true
	var r0 := t.rel
	check(t.dk_buy() == "" and t.dk and t.rel > r0, "ДК на балансе завода, город доволен")
	t._dk_week()
	var club := 0
	for w in sim.workers:
		if _has(w, "dk_club"):
			club += 1
	check(club >= 1, "кружки в ДК: ходят %d чел." % club)
	t.dk_concert()
	check(_has(sim.workers[0], "dk_concert"), "концерт к празднику")

	print("— заводское радио")
	sim.power.tick(0.1)
	check(t.radio_station() != null, "радиоузел под током")
	check(t.radio_rooms().size() == 1, "радио слышно в столовой")
	var lis: Worker = sim.workers[2]
	lis.present = true
	lis.pos = Vector2(5.5, 22.5)
	check(t.hears_radio(lis), "человек в столовой слышит радио")
	t._tick_radio(599.0, 600.5)
	check(_has(lis, "radio_gym"), "производственная гимнастика")
	t.radio["gym"] = false
	lis.thoughts = lis.thoughts.filter(func(x: Dictionary) -> bool: return str(x["id"]) != "radio_gym")
	t._tick_radio(599.0, 600.5)
	check(not _has(lis, "radio_gym"), "программу можно выключить")

	print("— кот")
	t.cat_offered = false
	sim.story.letters.clear()
	t._cat_offer(true)
	var cl := sim.story.get_letter_by_ev("cat")
	check(not cl.is_empty(), "на завод прибился кот — письмо")
	sim.story.resolve(int(cl["id"]), 0)
	var cat := t.cat
	check(cat != null and cat.name != "", "кота оставили: %s" % (cat.title() if cat else ""))
	check(int(sim.stats.get("cat", 0)) == 1, "достижение «Мурлыка в штате» засчитается")
	var cp0 := cat.pos
	for k3 in 200:
		cat.tick(0.5)
		sim.minute += 0.5
	check(cat.pos.distance_to(cp0) > 0.5 or cat.state != "walk", "кот гуляет и отдыхает: %s" % cat.activity)
	sim.place_thing("cat_bowl", Vector2i(6, 24), true, false)
	check(cat._bowl() != null, "миска поставлена")
	var pet: Worker = sim.workers[3]
	pet.present = true
	pet.pos = cat.pos
	pet.anim = "idle"
	pet.carrying = -1
	pet.task = null
	pet.remove_meta("cat_day")
	if (pet.id * 7 + 3) % 11 == 0:
		pet = sim.workers[4]
		pet.present = true
		pet.pos = cat.pos
		pet.anim = "idle"
		pet.carrying = -1
		pet.task = null
	t._pet_t = 0.0
	t._tick_cat(0.1)
	check(_has(pet, "cat_pet"), "погладили кота: +настроение")
	var cons0 := float(sim.cons.values()[0])
	for k4 in 20:
		t._rats_week()
	check(float(sim.cons.values()[0]) == cons0, "с котом крысы не портят расходники")
	sim.remove_thing(cat._bowl(), 0.0)
	for k5 in 4:
		t._cat_morning()
	check(t.cat == null and t.cat_gone, "без миски кот ушёл")

	print("— отношения с городом")
	t.rel = 74.0
	t._rel_week()
	check(t.rel >= 75.0, "соцсфера поднимает отношения: %d" % int(t.rel))
	var tax0 := Defs.b("tax_rate_acc") if sim.office.active("accounting") else Defs.b("tax_rate")
	check(absf(sim.office.tax_rate() - (tax0 - 0.01)) < 0.0001, "льгота: налог на 1% ниже")
	check(t.extra_candidates() >= 1, "город доволен — больше кандидатов")
	sim.stats["fired_week"] = 3
	var r1 := t.rel
	t._rel_week()
	check(t.rel < r1 + 5.0, "увольнения город не любит")

	print("— сохранение")
	var dd := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var dt2 := dd.town
	check(dt2.kg_level == 1 and dt2.dk and dt2.vaccinated_until == t.vaccinated_until, "детсад, ДК и прививки сохраняются")
	check(dt2.residents().size() == t.residents().size() and dd.get_worker(newb.id).from_away, "жильцы общежития сохраняются")
	check(dd.get_worker(mom.id).kids == 1, "дети сохраняются")
	check(dt2.cat_gone and absf(dt2.rel - t.rel) < 0.01, "кот и отношения с городом сохраняются")
	dd.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
