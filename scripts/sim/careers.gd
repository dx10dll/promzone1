class_name Careers
extends RefCounted
## 1.15 «Люди»: карьера и стаж.
## РП-9 — ожидания по зарплате: раз в квартал цены растут, люди ждут индексации; сдал на разряд — просит прибавку.
## РП-10 — разряд через экзамен: пробная деталь на своём станке, мастер принимает.
## РП-11 — стаж и возраст: раз в год все становятся старше, за год на заводе — «ветеран завода»,
##         пенсионный возраст (мужчины 60, женщины 55), с годами быстрее устают.
## Н-1 — рацпредложения под конкретный станок и изделие.

const PENSION_M := 60
const PENSION_F := 55
const INDEX_K := 1.04          ## рост цен за квартал
const EXAM_TIME := 30.0        ## минут на пробную деталь
const EXAM_CD_DAYS := 7        ## пересдача не раньше чем через неделю

var sim: Sim
var exams: Dictionary = {}     ## id работника -> день заявки (сдаёт на следующий разряд)
var wage_index := 1.0          ## рыночные ставки растут с ценами (зеркало People.wage_index)
var last_quarter := -1
var last_year := -1
var veterans: Dictionary = {}  ## id -> день, когда стал ветераном завода


func _init(s: Sim) -> void:
	sim = s
	People.wage_index = 1.0


## Новая игра: от какого квартала и года считать (без писем в первый же день).
func init_calendar() -> void:
	last_quarter = int(sim.season.month_abs() / 3)
	last_year = sim.season.year()


# ================================================================ РП-10: экзамен на разряд

## Почему нельзя сдавать сейчас ("" — можно).
func exam_block(w: Worker) -> String:
	if not w.has_grade():
		return "У этой профессии нет разрядов"
	if w.grade() >= 6:
		return "Высший, 6-й разряд уже есть"
	if w.pot_grade() <= w.grade():
		return "Навыка пока мало: нужно «%s» от %d" % [str(Worker.SKILL_NAMES.get(w.main_skill(), "")).to_lower(), 2 * w.grade()]
	if exams.has(w.id):
		return "Уже сдаёт — сделает пробную деталь на смене"
	if w.exam_cd > sim.day():
		return "Пересдача — с дня %d" % w.exam_cd
	return ""


func request_exam(w: Worker) -> String:
	var why := exam_block(w)
	if why != "":
		return why
	exams[w.id] = sim.day()
	sim.notify(Nicks.gendered("%s сдаёт на %d-й разряд: на смене сделает пробную деталь, мастер примет.", w.female) % [w.full_name(), w.grade() + 1], Sim.LVL_INFO, w.cell())
	return ""


func exam_pending(w: Worker) -> bool:
	return exams.has(w.id)


## Где сдавать: своё рабочее место или любое подходящее, свободное и рабочее.
func exam_place(w: Worker) -> Thing:
	var best: Thing = null
	var bs := -INF
	for t: Thing in sim.things.values():
		if not t.built or t.demolish or not Workplace.is_place(t) or t.user >= 0 or t.broken:
			continue
		if not Workplace.fits(sim, w, t):
			continue
		if t.kind() == "machine" and (not t.enabled or not sim.power.powered(t) or not sim.rooms.zone_ok(t)):
			continue
		var sc := (50.0 if t.owner == w.id else 0.0) - Vector2(t.cell - w.cell()).length()
		if sc > bs:
			bs = sc
			best = t
	return best


func foreman() -> Worker:
	for o in sim.workers:
		if o.prof in ["foreman", "chief"] and o.present and o.sick_until <= sim.minute:
			return o
	return null


## Экзамен закончен: пробную деталь приняли или нет.
func finish_exam(w: Worker) -> void:
	if not exams.has(w.id):
		return
	exams.erase(w.id)
	var to := w.grade() + 1
	var need := 2 * (to - 1)
	var fm := foreman()
	var p := clampf(0.55 + 0.12 * float(w.skill(w.main_skill()) - need) + (0.1 if fm else 0.0) + (w.mood - 50.0) / 400.0, 0.15, 0.95)
	var who := ("мастер %s" % fm.full_name()) if fm else "контролёр ОТК"
	if sim.rng.randf() < p:
		w.grade_n = to
		w.add_history(sim.day(), "Сдал{|а} экзамен на %d-й разряд".replace("{|а}", "а" if w.female else "") % to)
		Mood.add(sim, w, "grade_up")
		sim.stats["exams"] = int(sim.stats.get("exams", 0)) + 1
		sim.notify(Nicks.gendered("%s сдал{|а} на %d-й разряд — пробную деталь принял %s.", w.female) % [w.full_name(), to, who], Sim.LVL_GOOD, w.cell())
		_ask_raise(w)
	else:
		w.exam_cd = sim.day() + EXAM_CD_DAYS
		Mood.add(sim, w, "exam_failed")
		sim.notify(Nicks.gendered("%s не сдал{|а} на %d-й разряд: %s забраковал пробную деталь. Пересдача через неделю.", w.female) % [w.full_name(), to, who], Sim.LVL_WARN, w.cell())


# ================================================================ РП-9: зарплата

## Сдал на разряд — просит ставку по новому разряду.
func _ask_raise(w: Worker) -> void:
	var want := People.wage_for(w)
	if want <= w.wage:
		return
	var half := int(round((w.wage + want) * 0.5 / 10.0)) * 10
	sim.story.letter("raise_ask", "Просит прибавку", "%s сдал%s на %d-й разряд и просит ставку по разряду: %s вместо %s за смену." % [w.full_name(), "а" if w.female else "", w.grade(), Defs.money_str(want), Defs.money_str(w.wage)], "money", Sim.LVL_INFO,
		[{"text": "Ставка по разряду: %s" % Defs.money_str(want), "hint": "Человек доволен"},
		 {"text": "Половину: %s" % Defs.money_str(half), "hint": "Без восторга, но и без обиды"},
		 {"text": "Отказать", "hint": "Обидится; может начать искать другое место"}], 0, {"w": w.id, "want": want, "half": half})


func on_letter(ev: String, d: Dictionary, choice: int) -> void:
	match ev:
		"raise_ask":
			var w := sim.get_worker(int(d.get("w", -1)))
			if w == null:
				return
			match choice:
				0:
					w.wage = int(d["want"])
					Mood.add(sim, w, "raise")
				1:
					w.wage = int(d["half"])
				_:
					Mood.add(sim, w, "raise_refused")
					w.add_history(sim.day(), "Отказали в прибавке за разряд")
		"indexation":
			var k := float(d.get("k", INDEX_K))
			for w2 in sim.workers:
				var gets := choice == 0 or (choice == 1 and not w2.is_itr())
				if gets:
					w2.wage = int(round(w2.wage * k / 10.0)) * 10
					Mood.add(sim, w2, "indexed")
				else:
					Mood.add(sim, w2, "no_index")
			if choice == 0:
				sim.notify("Зарплаты проиндексированы на %d%%." % int(round((k - 1.0) * 100.0)), Sim.LVL_GOOD)
		"rational2":
			_res_rational(d, choice)


## Раз в квартал цены растут: рыночные ставки поднимаются, люди ждут индексации.
func _quarter() -> void:
	var q := int(sim.season.month_abs() / 3)
	if last_quarter < 0:
		last_quarter = q
		return
	if q == last_quarter:
		return
	last_quarter = q
	wage_index *= INDEX_K
	People.wage_index = wage_index
	if sim.workers.is_empty():
		return
	var week := 0.0
	for w in sim.workers:
		week += float(w.wage) * (INDEX_K - 1.0) * 5.0
	var itr_n := sim.workers.filter(func(x: Worker) -> bool: return x.is_itr()).size()
	sim.story.letter("indexation", "Индексация зарплат", "Цены за квартал выросли примерно на %d%%: на рынке ставки уже подняли. Люди ждут индексации — иначе начнут считать, что платят меньше, чем везде." % int(round((INDEX_K - 1.0) * 100.0)), "money", Sim.LVL_INFO,
		[{"text": "Проиндексировать всем на %d%%" % int(round((INDEX_K - 1.0) * 100.0)), "hint": "≈ %s в неделю" % Defs.money_str(week)},
		 {"text": "Только рабочим", "hint": "ИТР (%d чел.) обидятся" % itr_n},
		 {"text": "Не индексировать", "hint": "Все расстроятся; ставка отстанет от рынка"}], 2, {"k": INDEX_K})


# ================================================================ РП-11: стаж, возраст, пенсия

func pension_age(w: Worker) -> int:
	return PENSION_F if w.female else PENSION_M


func pensioner(w: Worker) -> bool:
	return w.age >= pension_age(w)


## С годами устают быстрее.
func rest_k(w: Worker) -> float:
	if w.age >= 60:
		return 1.25
	if w.age >= 55:
		return 1.15
	if w.age >= 50:
		return 1.07
	return 1.0


func _year() -> void:
	var y := sim.season.year()
	if last_year < 0:
		last_year = y
		return
	if y == last_year:
		return
	last_year = y
	var reached: Array[String] = []
	for w in sim.workers:
		w.age += 1
		if w.age == pension_age(w):
			reached.append(w.full_name())
	sim.notify("Новый год — все стали на год старше.%s" % ((" Пенсионного возраста достигли: " + ", ".join(reached) + ".") if not reached.is_empty() else ""), Sim.LVL_INFO)


func _veterans() -> void:
	var dpy := sim.season.days_per_year()
	for w in sim.workers:
		if veterans.has(w.id) or w.visitor:
			continue
		if sim.day() - w.hired_day >= dpy:
			veterans[w.id] = sim.day()
			w.add_history(sim.day(), "Ветеран завода — год на предприятии")
			Mood.add(sim, w, "veteran_honor")
			sim.notify("%s — год на заводе! Теперь ветеран завода: уважают, учит молодых охотнее." % w.full_name(), Sim.LVL_GOOD, w.cell())
			sim.paper.add("Наши ветераны", "Год на заводе: " + w.full_name(), "Спасибо за верность заводу! Молодёжь, берите пример.")


func is_veteran(w: Worker) -> bool:
	return veterans.has(w.id)


func morning() -> void:
	_quarter()
	_year()
	_veterans()
	for w in sim.workers:
		if exam_block(w) == "":
			sim.notify_once("examready%d" % w.id, "%s готов%s сдавать на %d-й разряд — в карточке кнопка «Экзамен»." % [w.full_name(), "а" if w.female else "", w.grade() + 1], Sim.LVL_INFO, Vector2i(-1, -1), 1440.0 * 7.0)


func on_leave(w: Worker) -> void:
	exams.erase(w.id)
	veterans.erase(w.id)


# ================================================================ Н-1: рацпредложения под станок и изделие

## Предложение под конкретный станок: [ключ перка, множитель, что, эффект, автор, премия] или [].
func rational_specific() -> Array:
	var cands: Array = []
	for m in sim.things_of("machine"):
		if not m.built or m.product == "" or m.demolish:
			continue
		for w in sim.workers:
			if w.is_itr() or not Workplace.fits(sim, w, m):
				continue
			var sk := w.skill(str(Defs.processes.get(m.process(), {}).get("skill", "turning")))
			if sk < 5 and not Mood.has_trait(w, "rationalizer"):
				continue
			var wt := float(sk) + (6.0 if m.owner == w.id else 0.0) + (5.0 if Mood.has_trait(w, "rationalizer") else 0.0)
			cands.append([wt, w, m])
	if cands.is_empty():
		return []
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var pick: Array = cands[sim.rng.randi_range(0, mini(2, cands.size() - 1))]
	var w2: Worker = pick[1]
	var m2: Thing = pick[2]
	var pn := Defs.product_name(m2.product)
	var opts: Array = []
	var k_op := "op:%s:%s" % [m2.def_id, m2.product]
	if sim.story.perk(k_op) > 0.75:
		opts.append([k_op, 0.88, "приспособление для «%s» на станке «%s»" % [pn, m2.title()], "операция на 12% быстрее", 12000.0])
	var k_df := "df:" + m2.product
	if sim.story.perk(k_df) > 0.65:
		opts.append([k_df, 0.8, "шаблон для контроля «%s»" % pn, "брака по этой детали на 20% меньше", 9000.0])
	var k_wr := "wr:%d" % m2.id
	if sim.story.perk(k_wr) > 0.6:
		opts.append([k_wr, 0.75, "свою схему смазки и ухода за станком «%s» (инв. № %05d)" % [m2.title(), (m2.id * 7919) % 99000 + 1000], "этот станок изнашивается на 25% медленнее", 8000.0])
	if opts.is_empty():
		return []
	var o: Array = opts[sim.rng.randi_range(0, opts.size() - 1)]
	return [o[0], o[1], o[2], o[3], w2, o[4], m2]


func propose_rational() -> bool:
	var r := rational_specific()
	if r.is_empty():
		return false
	var w: Worker = r[4]
	var m: Thing = r[6]
	sim.story.letter("rational2", "Рацпредложение", "%s предлагает %s: %s. Автор просит вознаграждение %s." % [w.full_name(), str(r[2]), str(r[3]), Defs.money_str(float(r[5]))], "idea", Sim.LVL_GOOD,
		[{"text": "Внедрить и заплатить %s" % Defs.money_str(float(r[5])), "hint": "Улучшение навсегда"}, {"text": "Отклонить", "hint": "Автор обидится"}], 1,
		{"w": w.id, "key": str(r[0]), "v": float(r[1]), "what": str(r[2]), "pay": float(r[5]), "cx": m.cell.x, "cy": m.cell.y})
	return true


func _res_rational(d: Dictionary, choice: int) -> void:
	var w := sim.get_worker(int(d.get("w", -1)))
	if choice == 0:
		sim.spend(float(d.get("pay", 10000.0)), "Премия: рацпредложение")
		var key := str(d["key"])
		sim.story.perks[key] = sim.story.perk(key) * float(d["v"])
		sim.stats["rational"] = int(sim.stats.get("rational", 0)) + 1
		if w:
			Mood.add(sim, w, "rational_paid")
			w.add_history(sim.day(), "Рацпредложение внедрено: " + str(d["what"]))
			sim.paper.add("Новаторы", "Рацпредложение: " + str(d["what"]), "Автор — %s. Внедрено в производство, автору выплачено вознаграждение." % w.full_name())
	elif w:
		Mood.add(sim, w, "rational_ignored")


func to_dict() -> Dictionary:
	return {"exams": exams, "wi": wage_index, "lq": last_quarter, "ly": last_year, "vet": veterans}


func from_dict(d: Dictionary) -> void:
	exams.clear()
	for k in (d.get("exams", {}) as Dictionary).keys():
		exams[int(k)] = int(d["exams"][k])
	wage_index = float(d.get("wi", 1.0))
	People.wage_index = wage_index
	last_quarter = int(d.get("lq", -1))
	last_year = int(d.get("ly", -1))
	veterans.clear()
	for k2 in (d.get("vet", {}) as Dictionary).keys():
		veterans[int(k2)] = int(d["vet"][k2])
