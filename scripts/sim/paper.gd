class_name Paper
extends RefCounted
## Заводская многотиражка: новости копятся за неделю из событий симуляции,
## по понедельникам выходит номер — с передовицей, итогами недели и мелочами для души.

var sim: Sim
var pending: Array = []      ## новости за неделю [{rubric, title, text, day}]
var issues: Array = []       ## вышедшие номера, свежие первыми
var unread := false
var number := 0
var made0 := 0              ## счётчики на момент прошлого номера — для итогов недели
var scrap0 := 0
var ads: Array = []          ## 1.52: объявления с кнопкой [{id, kind, title, text, until, ...}]
var ad_next := 0             ## не раньше этого дня выйдет следующее предложение
var ad_seq := 0
var flags: Dictionary = {}   ## 1.52: о чём газета уже писала один раз (столовая и т. п.)
var flags_init := true       ## в старом сейве флаги неизвестны — первый обход их только запоминает
var hired_w := 0             ## 1.52: принято / уволено с прошлого номера
var fired_w := 0
const AD_GAP := [6, 12]      ## дней между предложениями
const BIG_ORDER := 150000.0  ## с какой суммы заказ «крупный»


func _init(s: Sim) -> void:
	sim = s


func add(rubric: String, title: String, text: String) -> void:
	for p: Dictionary in pending:
		if str(p["title"]) == title:
			return
	pending.append({"rubric": rubric, "title": title, "text": text, "day": sim.day()})
	if pending.size() > 20:
		pending.pop_front()


## 1.52: заметка из шаблона data/paper.json → events → id (варианты по кругу), подстановка args.
## Четвёртый элемент шаблона — профессия: пишем только если такой человек есть на заводе (правило 1.44).
func event(id: String, args: Array = []) -> void:
	var tpls: Array = (Defs.paper.get("events", {}) as Dictionary).get(id, [])
	if tpls.is_empty():
		return
	var start := (sim.day() + number + id.length()) % tpls.size()
	for k in tpls.size():
		var i := (start + k) % tpls.size()
		var f: Array = tpls[i]
		var need := str(f[3]) if f.size() > 3 else ""
		if need != "" and not has_prof(need):
			continue
		var base := "paper.ev.%s.%d." % [id, i]
		var title := L.dt(base + "title", str(f[1]))
		var text := L.dt(base + "text", str(f[2]))
		for ai in args.size():
			title = title.replace("{%d}" % ai, str(args[ai]))
			text = text.replace("{%d}" % ai, str(args[ai]))
		add(L.dt(base + "rubric", str(f[0])), title, text)
		pending[-1]["pri"] = true
		return


# ---------------------------------------------------------------- 1.52: решения игрока → заметки

func on_order_taken(o: Dictionary) -> void:
	var sum := float(o["price"]) * int(o["qty"])
	if str(o.get("kind", "")) == "state":
		event("state_order", [sim.orders.short(o), Defs.money_str(sum)])
	elif sum >= BIG_ORDER and str(o.get("kind", "")) != "contract":
		event("big_order", [sim.orders.short(o), Defs.money_str(sum)])


func on_order_failed(o: Dictionary) -> void:
	event("order_failed", [sim.orders.short(o)])


func on_hire(_w: Worker) -> void:
	hired_w += 1


func on_fire(_w: Worker, _quit: bool) -> void:
	fired_w += 1


func on_crew_plan(crew_name: String, pct: int) -> void:
	if pct >= 110:
		event("crew_overplan", [crew_name, pct])


func on_iso() -> void:
	event("iso")


func on_machine(m: Thing) -> void:
	if sim.day() > 3 and sim.workers.size() > 0:
		event("machine_new", [m.title()])


## Раз в неделю перед выпуском: что накопилось из решений и перемен.
func _weekly_events() -> void:
	if hired_w >= 3:
		event("mass_hire", [hired_w])
	if fired_w >= 2:
		event("mass_fire", [fired_w])
	hired_w = 0
	fired_w = 0
	var canteen := not sim.rooms.of_type("canteen").is_empty()
	if canteen and not flags.get("canteen", false):
		flags["canteen"] = true
		if not flags_init:
			event("canteen")
	if not canteen:
		flags["canteen"] = false
	flags_init = false


## Понедельник, утро: выпуск номера.
func publish(force: bool = false) -> void:
	if sim.day() < 7 and not force:
		return
	number += 1
	var items: Array = []
	# передовица: лучший работник недели
	var best: Worker = null
	for w in sim.workers:
		if best == null or w.week_score > best.week_score:
			best = w
	if best and best.week_score > 0:
		var pct := 100 + mini(80, best.week_score * 2)
		items.append({"rubric": L.t("Передовик"), "title": Nicks.gendered(L.t("%s %s выполнил{|а} норму на %d%%!"), best.female) % [best.prof_name(), L.name(best.last), pct],
			"text": L.t("%s, %d лет. «Главное — не торопиться и не опаздывать», — делится секретом передовик.") % [best.formal_name(), best.age], "lead": true})
	# итоги недели
	var sales := 0.0
	for wk: Dictionary in sim.office.weeks:
		if int(wk["week"]) == sim.office.week_no() - 1:
			sales = float(wk["cats"].get("sales", 0.0))
	var made := int(sim.stats.get("made", 0)) - made0
	var scrap := int(sim.stats.get("scrap", 0)) - scrap0
	made0 = int(sim.stats.get("made", 0))
	scrap0 = int(sim.stats.get("scrap", 0))
	if sales > 0.0 or made > 0:
		items.append({"rubric": L.t("Итоги недели"), "title": L.t("Выручка недели — %s") % Defs.money_str(sales),
			"text": L.t("За неделю выпущено %d %s, в брак ушло %d. Заказов в работе: %d.") % [made, Defs.plural(made, "изделие", "изделия", "изделий"), scrap, sim.orders.active_count()]})
	# новости недели: сначала то, что связано с решениями игрока, потом свежие по порядку
	_weekly_events()
	var news := pending.duplicate()
	news.reverse()
	var picked: Array = []
	for n: Dictionary in news:
		if bool(n.get("pri", false)) and picked.size() < 3:
			picked.append(n)
	for n2: Dictionary in news:
		if picked.size() >= 6:
			break
		if not picked.has(n2):
			picked.append(n2)
	news = news.filter(func(x: Dictionary) -> bool: return picked.has(x))
	for n3: Dictionary in news:
		items.append(n3)
	pending.clear()
	# объявления с кнопкой действия
	_make_ad()
	for ad: Dictionary in active_ads():
		items.append({"rubric": L.t("Объявления"), "title": str(ad["title"]), "text": str(ad["text"]) + " " + L.t("Действует до: %s.") % sim.season.date_str(int(ad["until"])), "ad": int(ad["id"])})
	# быт: столовая, туалеты, отопление
	items.append(_life_item())
	# погода и сезон
	items.append(_weather_item())
	# мелочи
	var fillers: Array = Defs.paper.get("fillers", [])
	if not fillers.is_empty():
		var fi := (number * 7 + sim.day()) % fillers.size()
		# 1.44: заметка про должность выходит, только если такой человек есть; иначе — следующая подходящая
		for _k in fillers.size():
			var need := str((fillers[fi] as Array)[2]) if (fillers[fi] as Array).size() > 2 else ""
			if need == "" or has_prof(need):
				break
			fi = (fi + 1) % fillers.size()
		var f: Array = fillers[fi]
		items.append({"rubric": L.dt("paper.filler.%d.rubric" % fi, str(f[0])), "title": "", "text": L.dt("paper.filler.%d.text" % fi, str(f[1]))})
	issues.push_front({"no": number, "day": sim.day(), "date": sim.season.long_date(), "items": items})
	if issues.size() > 12:
		issues.resize(12)
	unread = true
	sim.notify(L.t("Вышел свежий номер многотиражки «%s» № %d — газета коллектива %s.") % [title_str(), number, Company.title(sim)], Sim.LVL_INFO)

# ---------------------------------------------------------------- 1.52: объявления с кнопкой

## Предложения живые: пока не истёк срок (до конца дня until включительно).
func active_ads() -> Array:
	return ads.filter(func(a: Dictionary) -> bool: return int(a["until"]) >= sim.day() and not bool(a.get("taken", false)))


## Вместе с уже принятыми — для показа в газете (кнопка становится «Принято»).
func live_ads() -> Array:
	return ads.filter(func(a: Dictionary) -> bool: return int(a["until"]) >= sim.day())


func ad_by_id(id: int) -> Dictionary:
	for a: Dictionary in ads:
		if int(a["id"]) == id:
			return a
	return {}


## Утро: просроченные объявления снимаются.
func morning() -> void:
	ads = ads.filter(func(a: Dictionary) -> bool: return int(a["until"]) >= sim.day())


## Раз в несколько дней (ad_next) и не при каждом выпуске: б/у станок с торгов, опытный мастер или распродажа металла.
func _make_ad(force_kind: String = "") -> Dictionary:
	if force_kind == "":
		if sim.day() < ad_next or sim.day() < 10 or not active_ads().is_empty():
			return {}
		var r := RandomNumberGenerator.new()
		r.seed = hash(sim.day() * 7919 + number * 31 + sim.workers.size())
		if r.randf() > 0.6:
			return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sim.day() * 104729 + number * 17 + ad_seq)
	var kinds: Array = ["machine", "master", "metal"]
	var kind := force_kind if force_kind != "" else str(kinds[rng.randi_range(0, kinds.size() - 1)])
	ad_seq += 1
	var ad := {"id": ad_seq, "kind": kind, "until": sim.day() + rng.randi_range(5, 7), "day": sim.day()}
	match kind:
		"machine":
			var opts: Array = []
			for k in ["lathe", "mill", "drill", "weld_post", "assembly_table", "furnace", "cnc_lathe"]:
				if Defs.objects.has(k) and sim.progress.locked_reason(k) == "":
					opts.append(k)
			if opts.is_empty():
				return _make_ad("metal")
			var def := str(opts[rng.randi_range(0, opts.size() - 1)])
			var off: int = [35, 40, 45, 50][rng.randi_range(0, 3)]
			ad["def"] = def
			ad["off"] = off
			var price: float = sim.thing_cost(def) * (100 - off) / 100.0
			ad["title"] = L.t("Продаётся б/у станок: %s") % Defs.obj_name(def)
			ad["text"] = L.t("С аукциона разорившегося завода: «%s», скидка %d%% (около %s). Выкупите право — поставите из «Объектов» в течение недели.") % [Defs.obj_name(def), off, Defs.money_str(price)]
			ad["btn"] = L.t("Выкупить с аукциона")
		"master":
			var prof := "turner"
			var pr: Array = []
			for proc in sim.prod.processes_available().keys():
				var pf := str(Defs.processes.get(proc, {}).get("prof", ""))
				if pf != "" and not Worker.ITR.has(pf):
					pr.append(pf)
			if not pr.is_empty():
				prof = str(pr[rng.randi_range(0, pr.size() - 1)])
			var w := People.make(rng, prof, 0.15)
			w.age = rng.randi_range(40, 56)
			var ms := w.main_skill()
			if ms != "":
				w.skills[ms] = rng.randi_range(8, 9)
			w.wage = People.wage_for(w)
			var cd := w.to_dict()
			cd["ad_until"] = int(ad["until"]) + 7
			ad["cand"] = cd
			ad["title"] = L.t("Опытный мастер ищет работу")
			ad["text"] = L.t("%s, %d лет, %s. Тридцать лет у станка, золотые руки. Ставка %s за смену. Звоните, пока не переманили.") % [w.formal_name(), w.age, w.prof_lc(), Defs.money_str(w.wage)]
			ad["btn"] = L.t("Пригласить на собеседование")
		_:
			var pct: int = [15, 20, 25, 30][rng.randi_range(0, 3)]
			var days: int = rng.randi_range(4, 6)
			ad["pct"] = pct
			ad["days"] = days
			ad["title"] = L.t("Распродажа металла!")
			ad["text"] = L.t("Склад металлобазы «Крепкосталь» распродаёт остатки: скидка %d%% на закупку на %d %s с момента заявки.") % [pct, days, Defs.plural(days, "день", "дня", "дней")]
			ad["btn"] = L.t("Воспользоваться скидкой")
	ads.append(ad)
	if ads.size() > 6:
		ads.pop_front()
	ad_next = sim.day() + rng.randi_range(int(AD_GAP[0]), int(AD_GAP[1]))
	sim.notify(L.t("В газете новое объявление: %s") % str(ad["title"]), Sim.LVL_INFO)
	return ad


## Принять предложение (кнопка в газете). Возвращает текст ошибки или "".
func accept_ad(id: int) -> String:
	var ad := ad_by_id(id)
	if ad.is_empty() or int(ad["until"]) < sim.day():
		return L.t("Предложение уже недействительно")
	if bool(ad.get("taken", false)):
		return L.t("Вы уже воспользовались этим предложением")
	match str(ad["kind"]):
		"machine":
			var def := str(ad["def"])
			sim.story.add_mod("voucher:" + def, float(100 - int(ad["off"])) / 100.0, 7.0 * 1440.0, L.t("Станок с аукциона со скидкой %d%%: %s") % [int(ad["off"]), Defs.obj_name(def)])
			sim.notify(L.t("Право на «%s» со скидкой %d%% выкуплено. Поставьте станок из «Объектов» в течение недели.") % [Defs.obj_name(def), int(ad["off"])], Sim.LVL_GOOD)
		"master":
			var cd: Dictionary = (ad["cand"] as Dictionary).duplicate(true)
			sim.candidates.push_front(cd)
			var w := Worker.from_dict(cd)
			sim.notify(L.t("%s пришёл на собеседование — он среди кандидатов (Люди → Найм).") % w.full_name(), Sim.LVL_GOOD)
		_:
			sim.story.add_mod("metal_sale", 1.0 - float(ad["pct"]) / 100.0, float(ad["days"]) * 1440.0, L.t("Распродажа металла −%d%%") % int(ad["pct"]))
			sim.notify(L.t("Скидка на металл %d%% действует %d %s.") % [int(ad["pct"]), int(ad["days"]), Defs.plural(int(ad["days"]), "день", "дня", "дней")], Sim.LVL_GOOD)
	ad["taken"] = true
	return ""



## Название газеты и подзаголовок (data/paper.json) — на языке игры.
static func title_str() -> String:
	return L.dt("paper.title", str(Defs.paper.get("title", "Трудовая смена")))


static func subtitle_str() -> String:
	return L.dt("paper.subtitle", str(Defs.paper.get("subtitle", "")))


## 1.44: есть ли на заводе работник такой профессии (газета не пишет про тех, кого нет).
func has_prof(p: String) -> bool:
	for w in sim.workers:
		if w.prof == p:
			return true
	return false


func _life_item() -> Dictionary:
	if sim.rooms.of_type("canteen").is_empty():
		return {"rubric": L.t("Письма читателей"), "title": L.t("Когда будет столовая?"), "text": L.t("«Обедаем на скамейке, бутерброды в промасленной газете. Нельзя ли по-человечески?» — пишет группа рабочих.")}
	var lines := [L.t("Столовая просит не уносить ложки. Ложек осталось одиннадцать.")]
	if has_prof("cook"):
		lines = [L.t("В столовой снова закончился компот. Буфетчица обещает разобраться."), L.t("Новое блюдо в столовой — котлета по-заводски. Отзывы сдержанно положительные."), lines[0]]
	else:
		lines.append(L.t("В столовой снова закончился компот. Администрация обещает разобраться."))
	return {"rubric": L.t("Столовая"), "title": "", "text": lines[number % lines.size()]}


func _weather_item() -> Dictionary:
	var s := sim.season
	var t := int(round(s.temp_day))
	var txt := L.t("%s. Днём около %+d °C.") % [s.season_name(), t]
	if s.season_id() == "winter":
		var cold := s.cold_rooms()
		if not cold.is_empty():
			txt += L.t(" В помещении «%s» холодно — администрация, где батареи?") % (cold[0] as Rooms.Room).title()
		else:
			txt += L.t(" В цехах тепло — спасибо отоплению.")
	elif s.season_id() == "summer":
		txt += L.t(" Пейте воду и не стойте на солнцепёке.")
	return {"rubric": L.t("Погода"), "title": "", "text": txt}


func to_dict() -> Dictionary:
	return {"pending": pending, "issues": issues, "unread": unread, "no": number, "m0": made0, "s0": scrap0,
		"ads": ads, "ad_next": ad_next, "ad_seq": ad_seq, "flags": flags, "hired_w": hired_w, "fired_w": fired_w}


func from_dict(d: Dictionary) -> void:
	pending = d.get("pending", [])
	issues = d.get("issues", [])
	unread = bool(d.get("unread", false))
	number = int(d.get("no", 0))
	made0 = int(d.get("m0", 0))
	scrap0 = int(d.get("s0", 0))
	ads = d.get("ads", [])
	ad_next = int(d.get("ad_next", 0))
	ad_seq = int(d.get("ad_seq", 0))
	flags = d.get("flags", {})
	flags_init = not d.has("flags")   # старый сейв: что уже есть на заводе, газета «не заметит»
	hired_w = int(d.get("hired_w", 0))
	fired_w = int(d.get("fired_w", 0))
