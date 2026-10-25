class_name Story
extends RefCounted
## Рассказчик: ритм событий, решения игрока («письма» с вариантами),
## аварии (пожар, травмы), забастовки, праздники, месячный план, временные модификаторы.
## Большинство бед вытекает из симуляции, рассказчик добавляет внешние события и держит темп.

const MODES := ["calm", "market", "wild"]

var sim: Sim
var mode := "market"
var enabled := true                  ## выключается только в тестах механик
var tension := 0.0
var last_event_day := 0
var cooldowns: Dictionary = {}       ## событие -> день, раньше которого не повторять
var letters: Array = []              ## ждут решения игрока
var archive: Array = []              ## прошедшие события [{day, title, text, icon, level}]
var mods: Array = []                 ## временные модификаторы [{key, v, until, text}]
var perks: Dictionary = {}           ## постоянные улучшения от рацпредложений: ключ -> множитель
var strike: Dictionary = {}          ## {active, demand, leader, since, days, promise_until}
var fires: Dictionary = {}           ## индекс клетки -> сила огня 0–1
var soot: Dictionary = {}            ## индекс клетки -> true (следы пожара)
var fire_start := -1.0
var brigade_at := -1.0               ## когда вызвали пожарных (−1 — не вызывали)
var brigade: FireBrigade             ## 1.30: пожарный расчёт — машина и пожарные на карте
var receivables: Array = []          ## долги клиентов [{amount, due, client, risk}]
var departures: Array = []           ## уход людей с задержкой [{wid, at, why}]
var scheduled: Array = []            ## события на сегодня [{ev, at}]
var injuries: Array = []             ## дни травм
var plan: Dictionary = {}            ## месячный план {m, target, base}
var guard := false                   ## досмотр на проходной
var low_mood_days := 0
var done_holidays: Dictionary = {}
var fires_total := 0
var strikes_total := 0
var _next_letter_id := 1
var _mach_t := 0.0


func _init(s: Sim) -> void:
	sim = s
	brigade = FireBrigade.new(s)


func mdef() -> Dictionary:
	return Defs.events.get("modes", {}).get(mode, {})


func mode_name(m: String = "") -> String:
	return str(Defs.events.get("modes", {}).get(m if m != "" else mode, {}).get("name", m))


func injury_mode_k() -> float:
	return float(mdef().get("injury_k", 1.0))


# ================================================================ модификаторы

func add_mod(key: String, v: float, minutes: float, text: String) -> void:
	for m: Dictionary in mods:
		if str(m["key"]) == key:
			m["v"] = v
			m["until"] = sim.minute + minutes
			m["text"] = text
			return
	mods.append({"key": key, "v": v, "until": sim.minute + minutes, "text": text})


func mod(key: String, default: float = 1.0) -> float:
	for m: Dictionary in mods:
		if str(m["key"]) == key and float(m["until"]) > sim.minute:
			return float(m["v"])
	return default


func has_mod(key: String) -> bool:
	for m: Dictionary in mods:
		if str(m["key"]) == key and float(m["until"]) > sim.minute:
			return true
	return false


func remove_mod(key: String) -> void:
	for i in range(mods.size() - 1, -1, -1):
		if str(mods[i]["key"]) == key:
			mods.remove_at(i)


func perk(key: String) -> float:
	return float(perks.get(key, 1.0))


func outage() -> bool:
	return has_mod("outage")


## Цена объекта с учётом скидок (субсидия на станки, торги конкурента).
func price_k(def_id: String) -> float:
	var k := 1.0
	if has_mod("voucher:" + def_id):
		k = minf(k, mod("voucher:" + def_id))
	if str(Defs.objects.get(def_id, {}).get("kind", "")) == "machine" and has_mod("machine_subsidy"):
		k = minf(k, mod("machine_subsidy"))
	return k


## Объект куплен — одноразовая скидка израсходована.
func on_bought(def_id: String) -> void:
	if has_mod("voucher:" + def_id):
		remove_mod("voucher:" + def_id)
	elif str(Defs.objects.get(def_id, {}).get("kind", "")) == "machine" and has_mod("machine_subsidy"):
		remove_mod("machine_subsidy")


# ================================================================ письма (решения)

func letter(ev: String, title: String, text: String, icon: String, level: int, choices: Array, def: int = 0, data: Dictionary = {}) -> Dictionary:
	var l := {"id": _next_letter_id, "ev": ev, "title": title, "text": text, "icon": icon, "level": level,
		"choices": choices, "def": def, "data": data, "day": sim.day(),
		"deadline": sim.minute + Defs.ev("decision_hours") * 60.0}
	_next_letter_id += 1
	letters.append(l)
	_archive(title, text, icon, level)
	sim.notify(_join(title, _first_sentence(text)), level, Vector2i(int(data.get("cx", -1)), int(data.get("cy", -1))))
	return l


## Событие без выбора: в журнал, ленту и (если важное) — письмом с одной кнопкой.
func info(title: String, text: String, icon: String, level: int, cell: Vector2i = Vector2i(-1, -1), popup: bool = false) -> void:
	if popup:
		var l := {"id": _next_letter_id, "ev": "info", "title": title, "text": text, "icon": icon, "level": level,
			"choices": [{"text": L.t("Понятно")}], "def": 0, "data": {"cx": cell.x, "cy": cell.y}, "day": sim.day(),
			"deadline": sim.minute + Defs.ev("decision_hours") * 60.0}
		_next_letter_id += 1
		letters.append(l)
	_archive(title, text, icon, level)
	sim.notify(_join(title, _first_sentence(text)), level, cell)


func _join(title: String, rest: String) -> String:
	if title.ends_with("!") or title.ends_with("?") or title.ends_with("."):
		return title + " " + rest
	return title + ". " + rest


func _first_sentence(t: String) -> String:
	var nl := t.find("\n")
	if nl > 0:
		t = t.substr(0, nl).trim_suffix(":") + "."
	var i := t.find(". ")
	if i > 0 and i < 160:
		return t.substr(0, i + 1)
	return t if t.length() < 160 else t.substr(0, 157) + "…"


func _archive(title: String, text: String, icon: String, level: int) -> void:
	archive.push_front({"day": sim.day(), "date": sim.date_str(), "title": title, "text": text, "icon": icon, "level": level})
	if archive.size() > 80:
		archive.resize(80)


func get_letter(id: int) -> Dictionary:
	for l: Dictionary in letters:
		if int(l["id"]) == id:
			return l
	return {}


## Игрок выбрал вариант (или истёк срок — вариант по умолчанию).
func resolve(id: int, choice: int) -> void:
	var l := get_letter(id)
	if l.is_empty():
		return
	letters.erase(l)
	var ch: Array = l["choices"]
	choice = clampi(choice, 0, ch.size() - 1)
	var d: Dictionary = l["data"]
	match str(l["ev"]):
		"bad_metal":
			_res_bad_metal(d, choice)
		"pipe_burst":
			_res_pipe(d, choice)
		"wire_break", "leak":
			if choice == 0:
				sim.faults.call_crew(str(d.get("layer", "cable")), int(d.get("i", -1)))
		"hot_order":
			var o := sim.orders.get_order(int(d.get("order", -1)))
			if not o.is_empty() and str(o["status"]) == "offer":
				if choice == 0:
					o["prio"] = 1
					var err := sim.orders.accept(int(o["id"]), true)
					if err != "":
						sim.notify(L.t("«Горящий» заказ не принят: ") + err, Sim.LVL_WARN)
				else:
					sim.orders.decline(int(o["id"]))
		"contract":
			var cid := int(d.get("contract", -1))
			if choice == 0:
				var err2 := sim.sales.sign(cid)
				if err2 != "":
					sim.notify(err2, Sim.LVL_WARN)
			elif choice == 1:
				sim.sales.decline(cid)
		"thief", "union_form", "union_warn", "n1":
			sim.crew.on_letter(str(l["ev"]), d, choice)
		"price_war", "auction", "poach", "iso_audit":
			sim.market.on_letter(str(l["ev"]), d, choice)
		"cat", "kittens":
			sim.town.on_letter(str(l["ev"]), d, choice)
		"theft":
			if choice == 0 and has_checkpoint():
				guard = true
				sim.notify(L.t("На проходной ввели досмотр: охрана %s в день.") % Defs.money_str(Defs.ev("guard_cost_day")), Sim.LVL_INFO)
		"drinking":
			_res_drinking(d, choice)
		"fight":
			_res_fight(d, choice)
		"rumor":
			_res_rumor(choice)
		"shift_conflict":
			if choice == 0:
				_pay_or_warn(5000.0, L.t("Журнал передачи смены"))
				perks["shift_log"] = 1.0
				for w in sim.workers:
					_remove_thought(w, "shift_mess")
		"retire":
			_res_retire(d, choice)
		"poach":
			_res_poach(d, choice)
		"wedding", "baby":
			_res_gift(d, choice)
		"rational":
			_res_rational(d, choice)
		"raise_ask", "indexation", "rational2":
			sim.career.on_letter(str(l["ev"]), d, choice)
		"grant":
			_res_grant(d, choice)
		"competitor_sale":
			_res_sale(d, choice)
		"raid":
			_res_raid(choice)
		"barter":
			_res_barter(d, choice)
		"strike":
			_res_strike(choice)
		"holiday":
			_res_holiday(d, choice)
		"month_end":
			if choice == 0:
				var left := float(sim.season.dpm() - sim.season.dom() + 1) * 1440.0
				add_mod("rush", 1.0, left, L.t("Аврал до конца месяца"))
				sim.notify(L.t("Объявлен аврал до конца месяца: работа быстрее, но брака и усталости больше."), Sim.LVL_WARN)
		"vacation":
			_res_vacation(d, choice)
		"inspection_act":
			sim.inspect.on_act_choice(d, choice)
		"reclamation":
			_res_reclamation(d, choice)
		"dogs":
			match choice:
				0:
					sim.spend(20000.0, "Отлов бродячих собак")
					sim.progress.dogs.clear()
					sim.notify(L.t("Собак увезли. На территории стало тихо — и как-то пусто."), Sim.LVL_INFO)
				1:
					sim.progress.dogs_tame = true
					sim.notify(L.t("У проходной поставили будки. Собаки теперь заводские: лают на чужих."), Sim.LVL_GOOD)
		"feud":
			sim.training.resolve_feud(d, choice)
		"practice_end":
			sim.training.resolve_practice(d, choice)
		"crisis_client", "crisis_tools", "crisis_wages":
			sim.crisis.on_letter(str(l["ev"]), d, choice)
		"roof":
			if choice == 0:
				var err := sim.progress.repair_roof()
				if err != "":
					sim.notify(err, Sim.LVL_WARN)
	for w in sim.workers:
		Mood.refresh(sim, w)


func _pay_or_warn(amount: float, reason: String) -> void:
	sim.spend(amount, reason)


func _remove_thought(w: Worker, id: String) -> void:
	for i in range(w.thoughts.size() - 1, -1, -1):
		if str(w.thoughts[i]["id"]) == id:
			w.thoughts.remove_at(i)


# ================================================================ ход времени

func tick(dt: float) -> void:
	# просроченные решения
	for l: Dictionary in letters.duplicate():
		if sim.minute >= float(l["deadline"]):
			resolve(int(l["id"]), int(l["def"]))
	# запланированные на сегодня события
	for s: Dictionary in scheduled.duplicate():
		if sim.minute >= float(s["at"]):
			scheduled.erase(s)
			if str(s["ev"]) == "reclamation":
				_ev_reclamation(s.get("data", {}))
			else:
				_start(str(s["ev"]), true)
	# уходы (пенсия, переманили)
	for dp: Dictionary in departures.duplicate():
		if sim.minute >= float(dp["at"]):
			departures.erase(dp)
			var w := sim.get_worker(int(dp["wid"]))
			if w:
				_leave(w, str(dp["why"]))
	# долги клиентов
	for r: Dictionary in receivables.duplicate():
		if sim.minute >= float(r["due"]):
			receivables.erase(r)
			_collect(r)
	# модификаторы: убрать истёкшие
	for i in range(mods.size() - 1, -1, -1):
		if float(mods[i]["until"]) <= sim.minute:
			var key := str(mods[i]["key"])
			mods.remove_at(i)
			_mod_ended(key)
	brigade.tick(dt)
	_tick_fire(dt)
	_mach_t -= dt
	if _mach_t <= 0.0:
		_mach_t = 10.0
		_machine_fire_risk()


func _mod_ended(key: String) -> void:
	match key:
		"outage":
			sim.notify(L.t("Электричество дали: горсети устранили аварию."), Sim.LVL_GOOD)
		"metal_price":
			sim.notify(L.t("Цены на металл вернулись к обычным."), Sim.LVL_INFO)


## Утро (6:00): праздники, план, забастовка, бросок рассказчика на день.
func morning() -> void:
	if not enabled:
		return
	var d := sim.day()
	if guard and has_checkpoint() and sim.crew.guards().is_empty():
		guard = false   # 1.30: досматривать некому — без охранника досмотр не работает
		sim.notify(L.t("Досмотр на проходной отменён: нет охранника. Наймите охранника (Люди → Найм) и включите досмотр снова."), Sim.LVL_WARN)
	if guard and has_checkpoint():
		sim.spend(Defs.ev("guard_cost_day"), "Охрана на проходной")
		if sim.is_workday():
			for w in sim.workers:
				if not w.is_itr():
					Mood.add(sim, w, "searched")
	elif guard:
		guard = false
	if sim.weekday() == 0 and sim.progress.dogs_tame and not sim.progress.dogs.is_empty():
		sim.spend(1500.0, "Корм для заводских собак")
	_holidays()
	_month_plan()
	_check_strike_mood()
	if strike.get("active", false):
		strike["days"] = int(strike.get("days", 0)) + 1
		sim.reputation = maxf(0.0, sim.reputation - 1.0)
		if get_letter_by_ev("strike").is_empty() and sim.is_workday():
			_strike_letter(false)
	if not sim.is_workday():
		return
	var grace := int(mdef().get("grace_days", 3))
	if d <= grace:
		return
	tension = minf(100.0, tension + float(mdef().get("tension_rate", 9.0)))
	var chance := float(mdef().get("day_chance", 0.5))
	if d - last_event_day >= 4:
		chance += 0.15
	if not letters.is_empty():
		chance *= 0.5
	if sim.rng.randf() >= chance:
		return
	var good := sim.rng.randf() < float(mdef().get("good_share", 0.42))
	var ev := _pick(good)
	if ev == "" and not good:
		ev = _pick(true)
	if ev == "":
		return
	last_event_day = d
	var edef: Dictionary = Defs.events["events"][ev]
	cooldowns[ev] = d + int(edef.get("cd", 7))
	tension = maxf(0.0, tension - float(edef.get("sev", 0)))
	if ev in ["fire", "injury", "outage", "drinking", "theft"]:
		# эти случаются посреди смены
		scheduled.append({"ev": ev, "at": float(d - 1) * 1440.0 + sim.rng.randf_range(560.0, 960.0)})
	else:
		_start(ev, false)


func get_letter_by_ev(ev: String) -> Dictionary:
	for l: Dictionary in letters:
		if str(l["ev"]) == ev:
			return l
	return {}


func _pick(good: bool) -> String:
	var all: Dictionary = Defs.events.get("events", {})
	var pool: Array = []
	var total := 0.0
	var d := sim.day()
	var calm_k := 1.5 if mode == "calm" else 1.0
	for k in all.keys():
		var e: Dictionary = all[k]
		var kind := str(e.get("kind", "bad"))
		if good and kind == "bad":
			continue
		if not good and kind != "bad":
			continue
		var w := float(e.get("w", 1)) * float(e.get("modes", {}).get(mode, 1.0))
		if str(k) == "grant":
			w *= float(sim.progress.pdef().get("grant_k", 1.0))
		if str(k) == "rational" and sim.dev.on("prod3"):
			w *= 2.0   # Развитие → «Соцсоревнование»
		if w <= 0.0:
			continue
		if d < int(float(e.get("min_day", 0)) * calm_k) or d < int(cooldowns.get(k, 0)):
			continue
		if not good and float(e.get("sev", 0)) > tension + 5.0:
			continue
		if e.has("season") and str(e["season"]) != sim.season.season_id():
			continue
		if not _can(str(k)):
			continue
		pool.append([str(k), w])
		total += w
	if pool.is_empty():
		return ""
	var r := sim.rng.randf() * total
	for p in pool:
		r -= float(p[1])
		if r <= 0.0:
			return str(p[0])
	return str(pool[-1][0])


func _staff(non_itr: bool = true) -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if non_itr and w.is_itr():
			continue
		out.append(w)
	return out


func _present_staff() -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if w.present and not w.is_itr() and not w.hidden:
			out.append(w)
	return out


func _can(ev: String) -> bool:
	match ev:
		"fire":
			return _fire_spot().x >= 0
		"injury":
			return not _staff().is_empty()
		"bad_metal":
			return _materials().size() >= 6
		"outage":
			return not sim.things_of("power").is_empty()
		"pipe_burst":
			return sim.season.heating_season() and sim.season.radiators > 0
		"wire_break":
			return sim.faults.count("cable") == 0 and not sim.faults.candidates("cable").is_empty()
		"leak":
			return sim.faults.count("pipe") == 0 and not sim.faults.candidates("pipe").is_empty()
		"heat_off":
			return sim.season.heating_season() and sim.season.radiators > sim.eng.boiler_rads.size()
		"supply_delay":
			return not sim.supply.is_empty()
		"theft":
			return _materials().size() >= 4
		"drinking":
			return _staff().size() >= 3 and sim.rng.randf() < sim.crew.booze_k()
		"rumor":
			return sim.workers.size() >= 4
		"shift_conflict":
			var a := false
			var b := false
			for w in sim.workers:
				if w.shift == 0:
					a = true
				else:
					b = true
			return a and b and not perks.has("shift_log")
		"retire":
			return _retiree() != null
		"poach":
			return _poach_target() != null
		"wedding", "baby":
			return _young() != null
		"rational":
			return _rational_author() != null
		"governor", "journalist":
			return sim.workers.size() >= 5 and not sim.inspect.busy()
		"competitor_sale":
			return sim.money > 60000.0
		"hot_order":
			return sim.orders.active_count() < sim.orders.max_active()
		"barter", "raid":
			return sim.money > 150000.0
	return true


func _start(ev: String, delayed: bool) -> void:
	match ev:
		"fire":
			var c := _fire_spot()
			if c.x >= 0:
				ignite(c, L.t("Загорелась проводка"))
		"injury":
			var ps := _present_staff()
			if not ps.is_empty():
				injure(ps[sim.rng.randi_range(0, ps.size() - 1)], "event")
		"bad_metal":
			_ev_bad_metal()
		"metal_up":
			var k := sim.rng.randf_range(1.2, 1.35) if mode != "wild" else sim.rng.randf_range(1.3, 1.6)
			add_mod("metal_price", k, sim.rng.randf_range(9.0, 14.0) * 1440.0, L.t("Металл подорожал на %d%%") % int(round((k - 1.0) * 100.0)))
			info(L.t("Металл подорожал"), L.t("Металлобазы подняли цены на %d%%: виноваты курс и «сложная ситуация на рынке». Дорого продержится недели две. Покупайте только под заказы.") % int(round((k - 1.0) * 100.0)), "chart_up", Sim.LVL_WARN)
			sim.paper.add(L.t("Экономика"), L.t("Металл подорожал на %d%%") % int(round((k - 1.0) * 100.0)), L.t("Снабженцы хватаются за голову: прутки дорожают. Бухгалтерия просит не точить лишнего."))
		"metal_down":
			add_mod("metal_price", 0.85, 10.0 * 1440.0, L.t("Металл подешевел на 15%"))
			info(L.t("Металл подешевел"), L.t("На рынке избыток проката: металлобазы снизили цены на 15% на ближайшие полторы недели. Хорошее время запастись."), "chart_down", Sim.LVL_GOOD)
		"outage":
			var mins := sim.rng.randf_range(90.0, 240.0)
			add_mod("outage", 1.0, mins, L.t("Авария в городской сети"))
			info(L.t("Авария в горсетях"), L.t("Электричество пропало по всему району. Обещают дать через %d ч. Станки стоят, свет только из окон.") % int(ceil(mins / 60.0)), "bolt_off", Sim.LVL_BAD)
			sim.paper.add(L.t("Происшествия"), L.t("Свет отключили всему району"), L.t("Станки стоят, чайник холодный. Энергетики горсетей ищут виноватого экскаваторщика."))
		"pipe_burst":
			_ev_pipe()
		"wire_break":
			_ev_fault("cable")
		"leak":
			_ev_fault("pipe")
		"heat_off":
			var hm := sim.rng.randf_range(1.0, 2.0) * 1440.0
			add_mod("heat_off", 1.0, hm, L.t("Авария на теплотрассе: батареи от теплосети холодные"))
			var own := sim.eng.boiler_rads.size()
			info(L.t("Авария на теплотрассе"), L.t("Городская теплосеть отключила район на %d %s: батареи от неё холодные. %s") % [int(ceil(hm / 1440.0)), Defs.plural(int(ceil(hm / 1440.0)), "день", "дня", "дней"),
				(L.t("Своя котельная греет %d %s как ни в чём не бывало.") % [own, Defs.plural(own, "батарею", "батареи", "батарей")]) if own > 0 else L.t("Своя котельная (газовый котёл) от таких аварий не зависит.")], "heat", Sim.LVL_BAD)
			sim.paper.add(L.t("Происшествия"), L.t("Район без тепла"), L.t("Теплосеть меняет трубу на перекрёстке. Мастера советуют поддеть тёплое под спецовку."))
		"cold_snap":
			sim.season.snap = -sim.rng.randf_range(12.0, 18.0)
			sim.season.snap_until = sim.minute + sim.rng.randf_range(2.0, 4.0) * 1440.0
			var t := int(round(sim.season.outside_temp()))
			info(L.t("Ударили морозы"), L.t("Синоптики обещают до %d °C на несколько дней. Счёт за отопление вырастет, в неотапливаемых помещениях работать невозможно.") % mini(t, -25), "snow", Sim.LVL_WARN)
			sim.paper.add(L.t("Погода"), L.t("Мороз и солнце"), L.t("До %d °C! Не забудьте шапку-ушанку и тёплые портянки.") % mini(t, -25))
		"heatwave":
			sim.season.snap = sim.rng.randf_range(7.0, 10.0)
			sim.season.snap_until = sim.minute + sim.rng.randf_range(2.0, 4.0) * 1440.0
			info(L.t("Жара"), L.t("На улице за +30. В горячих цехах тяжело: помогут окна и кулер с водой."), "thermo", Sim.LVL_WARN)
			sim.paper.add(L.t("Погода"), L.t("Жара!"), L.t("Термисты просят выдать им мороженое за вредность. Профсоюз изучает вопрос."))
		"flood":
			for s: Dictionary in sim.supply:
				s["eta"] = float(s["eta"]) + 1440.0
			add_mod("roads", 1.0, 3.0 * 1440.0, L.t("Паводок размыл дорогу"))
			info(L.t("Паводок"), L.t("Талые воды размыли подъездную дорогу: поставки задержатся на сутки, новые — тоже, пока не просохнет."), "supply", Sim.LVL_WARN)
		"supply_delay":
			var extra := sim.rng.randf_range(1.0, 2.0) * 1440.0
			for s2: Dictionary in sim.supply:
				s2["eta"] = float(s2["eta"]) + extra
			info(L.t("Поставка задерживается"), L.t("Машина с металлом сломалась под Тверью. Поставка опоздает на %d %s.") % [int(round(extra / 1440.0)), Defs.plural(int(round(extra / 1440.0)), "день", "дня", "дней")], "supply", Sim.LVL_WARN)
		"hot_order":
			_ev_hot_order()
		"theft":
			_ev_theft()
		"drinking":
			_ev_drinking()
		"rumor":
			for w in sim.workers:
				Mood.add(sim, w, "layoff_rumor")
			letter("rumor", L.t("Слухи о сокращении"), L.t("В курилке говорят, что завод закрывают, а всех сократят. Люди нервничают и работают спустя рукава."), "staff", Sim.LVL_WARN,
				[{"text": L.t("Собрать коллектив и всё объяснить"), "hint": L.t("Слухи развеются")}, {"text": L.t("Не обращать внимания"), "hint": L.t("Настроение будет плохим ещё три дня")}], 1)
		"shift_conflict":
			for w2 in sim.workers:
				if w2.shift == 0:
					Mood.add(sim, w2, "shift_mess")
			letter("shift_conflict", L.t("Конфликт смен"), L.t("Первая смена жалуется: вторая оставляет станки грязными, а заготовки — где попало. Дело идёт к скандалу."), "staff", Sim.LVL_WARN,
				[{"text": L.t("Завести журнал передачи смены (5 000 ₽)"), "hint": L.t("Конфликты прекратятся")}, {"text": L.t("Пусть разбираются сами"), "hint": L.t("Может повториться")}], 1)
		"retire":
			_ev_retire()
		"poach":
			_ev_poach()
		"wedding":
			_ev_gift("wedding")
		"baby":
			_ev_gift("baby")
		"rational":
			_ev_rational()
		"governor":
			sim.inspect.announce_visit("governor")
		"journalist":
			sim.inspect.announce_visit("press")
		"grant":
			letter("grant", L.t("Фонд «Промразвитие»"), L.t("Областной фонд поддержки промышленности предлагает помощь молодым производствам. Можно выбрать одно."), "money", Sim.LVL_GOOD,
				[{"text": L.t("Льготный заём 1 500 000 ₽ под 5% на 26 недель"), "hint": L.t("Платёж каждый понедельник")},
				 {"text": L.t("Субсидия 30% на следующий станок"), "hint": L.t("Действует месяц")},
				 {"text": L.t("Отказаться"), "hint": ""}], 2)
		"competitor_sale":
			_ev_sale()
		"raid":
			letter("raid", L.t("Рейдерская попытка"), L.t("Неизвестные принесли в налоговую поддельный протокол собрания учредителей и пытаются переоформить завод на себя. Нужно отбиваться."), "court", Sim.LVL_BAD,
				[{"text": L.t("Нанять юристов (80 000 ₽, шанс 85%)"), "hint": ""},
				 {"text": L.t("Отбиваться самим (шанс 40%)"), "hint": L.t("При неудаче — потеря четверти денег")},
				 {"text": L.t("Откупиться (20% денег на счёте)"), "hint": L.t("Наверняка")}], 0)


# ================================================================ пожар

func hot_machines() -> Array[Thing]:
	var out: Array[Thing] = []
	for m in sim.things_of("machine"):
		if m.process() in ["heat", "paint", "welding", "casting"]:
			out.append(m)
	return out


func _fire_spot() -> Vector2i:
	var cands: Array[Thing] = hot_machines()
	if cands.is_empty():
		cands = sim.things_of("machine")
	if cands.is_empty():
		for t: Thing in sim.things.values():
			if t.built and float(t.def().get("power_kw", 0.0)) > 0.0:
				cands.append(t)
	if cands.is_empty():
		return Vector2i(-1, -1)
	var t2: Thing = cands[sim.rng.randi_range(0, cands.size() - 1)]
	var acc := sim.brain.best_access(t2, t2.cell)
	return acc if acc.x >= 0 else t2.cell


func _flammable(c: Vector2i) -> bool:
	var w := sim.world
	if not w.inb(c) or not w.in_plot(c):
		return false
	var i := w.idx(c)
	if Defs.wall_solid(w.wall[i]):
		return false
	return w.flr[i] > 0 or w.occ[i] >= 0


func ignite(c: Vector2i, why: String) -> void:
	var w := sim.world
	if not _flammable(c):
		return
	var i := w.idx(c)
	if fires.has(i):
		return
	var first := fires.is_empty()
	fires[i] = 0.35
	if first:
		sim.sfx.emit("breaker", c)
		fire_start = sim.minute
		brigade_at = -1.0
		fires_total += 1
		var r := sim.rooms.room_at(c)
		var where := r.title() if r else L.t("на территории")
		info(L.t("Пожар!"), L.t("%s: огонь %s. Все свободные бегут тушить. С огнетушителем — в разы быстрее; если огонь разойдётся, приедут пожарные — и будет проверка.") % [why, (L.t("в помещении «%s»") % where) if r else where], "fire", Sim.LVL_BAD, c, true)
		sim.paper.add(L.t("Происшествия"), L.t("Пожар на заводе"), L.t("%s. Коллектив бросился тушить, кто с огнетушителем, кто с ведром.") % why)


func extinguish(i: int, amount: float) -> void:
	if not fires.has(i):
		return
	var v := float(fires[i]) - amount
	if v <= 0.0:
		fires.erase(i)
		soot[i] = true
		if fires.is_empty():
			_fire_out(brigade.deployed())   # 1.30: расчёт уже на месте — тушили пожарные
	else:
		fires[i] = v


func _fire_out(brigade: bool) -> void:
	var dur := int(sim.minute - fire_start)
	sim.market.claim("property", 25000.0 + soot.size() * 1500.0, "ущерб от пожара")
	fire_start = -1.0
	brigade_at = -1.0
	for w in sim.workers:
		if w.present:
			Mood.add(sim, w, "fire_scare")
	sim.sfx.emit("extinguish", Vector2i(-1, -1))
	if brigade:
		sim.reputation = maxf(0.0, sim.reputation - 3.0)
		info(L.t("Пожар потушен пожарными"), L.t("Расчёт пожарной охраны потушил огонь, пожар шёл %d мин. Будет внеплановая проверка пожарного надзора.") % maxi(1, dur), "fire", Sim.LVL_WARN)
		sim.inspect.schedule("fire", sim.minute + sim.rng.randf_range(1.0, 2.0) * 1440.0, false, L.t("после пожара"))
	else:
		info(L.t("Пожар потушен"), L.t("Огонь потушили своими силами за %d мин.") % maxi(1, dur), "fire", Sim.LVL_GOOD)
		sim.paper.add(L.t("Герои"), L.t("Потушили сами"), L.t("Пожар потушили за %d минут без пожарных. Коллектив молодец, огнетушители — тоже.") % maxi(1, dur))
	add_mod("fire_recent", 1.0, 10.0 * 1440.0, L.t("Недавний пожар"))
	if sim.rng.randf() < 0.5 and not brigade:
		sim.inspect.schedule("fire", sim.minute + sim.rng.randf_range(2.0, 4.0) * 1440.0, true, L.t("после пожара"))
	while soot.size() > 300:
		soot.erase(soot.keys()[0])


func _ext_in_room(r: Rooms.Room) -> int:
	if r == null:
		return 0
	return sim.rooms.space_count(r.space, "extinguisher")   # огнетушитель на всё помещение


func _tick_fire(dt: float) -> void:
	if fires.is_empty():
		return
	var w := sim.world
	var grow := Defs.ev("fire_grow") * dt
	var spread := Defs.ev("fire_spread") * dt
	var newf: Array[int] = []
	for i: int in fires.keys():
		var v := minf(1.0, float(fires[i]) + grow)
		fires[i] = v
		var c := w.cell_of(i)
		# объекты горят
		var oid := w.occ[i]
		if oid >= 0:
			var t: Thing = sim.things.get(oid)
			if t and t.built:
				t.condition = maxf(0.0, t.condition - 0.8 * dt * v)
				if t.kind() == "machine" and t.condition < 8.0 and not t.broken:
					t.broken = true
					t.working = false
					sim.notify(L.t("Огонь повредил станок «%s» — нужен ремонт.") % t.title(), Sim.LVL_BAD, t.cell)
		# грузы на полу сгорают
		if sim.rng.randf() < 0.02 * dt * v:
			for gid in sim.ground_items.duplicate():
				var it: Item = sim.items.get(gid)
				if it and it.cell == c:
					sim.delete_item(it)
					break
		if v > 0.5:
			var r := sim.rooms.room_at(c)
			var k := 0.6 if _ext_in_room(r) > 0 else 1.0
			for d: Vector2i in Rooms.DIRS:
				var n: Vector2i = c + d
				if _flammable(n) and not fires.has(w.idx(n)) and sim.rng.randf() < spread * v * k:
					newf.append(w.idx(n))
	for ni in newf:
		if fires.size() < 80:
			fires[ni] = 0.2
	# люди в огне
	for wk in sim.workers:
		if wk.present and fires.has(w.idx(wk.cell())) and sim.rng.randf() < 0.01 * dt:
			injure(wk, "burn")
	# пожарная охрана
	# пожарная охрана (1.30: приезжает машина, пожарные тушат сами — FireBrigade)
	if brigade_at < 0.0 and (fires.size() >= int(Defs.ev("fire_brigade_cells")) or sim.minute - fire_start >= Defs.ev("fire_brigade_after")):
		brigade_at = sim.minute
		brigade.request()


## Риск возгорания от горячих станков (печь, покраска, сварка), особенно изношенных и без огнетушителя.
func _machine_fire_risk() -> void:
	if not fires.is_empty() or not enabled:
		return
	var base := Defs.ev("fire_base") * float(mdef().get("fire_k", 1.0)) * 10.0
	for m in hot_machines():
		if not m.working:
			continue
		var k := 1.0
		if m.condition < 30.0:
			k *= 3.0
		if _ext_in_room(sim.rooms.room_of_thing(m)) == 0:
			k *= 1.5
		if sim.rng.randf() < base * k:
			var acc := sim.brain.best_access(m, m.cell)
			ignite(acc if acc.x >= 0 else m.cell, L.t("Загорелось у станка «%s»") % m.title())
			return


## Выбило автомат: иногда загорается проводка у щита.
func on_trip(cell: Vector2i) -> void:
	if cell.x >= 0 and sim.rng.randf() < 0.06 * float(mdef().get("fire_k", 1.0)):
		var c := sim.world.nearest_passable(cell + Vector2i(0, 1))
		ignite(c, L.t("Перегруз: загорелась проводка у подстанции"))


# ================================================================ травмы и больничные

func injure(w: Worker, cause: String) -> void:
	if sim.get_worker(w.id) != w or w.sick_until > sim.minute:
		return
	var sd: Array = Defs.events.get("sick_days", [2, 6])
	var days := sim.rng.randi_range(int(sd[0]), int(sd[1]))
	var aid := _aid_near(w.cell())
	if aid:
		days = maxi(1, int(round(days * 0.6)))
	if cause == "slip":
		days = maxi(1, days - 1)
	var nurse := sim.town.medbay_ready()
	if nurse:
		days = maxi(1, int(round(days * 0.6)))
	var texts := {"event": L.t("получил{|а} травму у станка"), "work": L.t("травмировал{|а} руку на работе"), "slip": L.t("поскользнул{ся|ась} на льду"),
		"burn": L.t("получил{|а} ожог на пожаре"), "fight": L.t("пострадал{|а} в драке")}
	var what := Nicks.gendered(str(texts.get(cause, L.t("получил{|а} травму"))), w.female)
	w.sick_until = float(sim.day() + days - 1) * 1440.0 + 1200.0
	w.away_why = "на больничном"
	w.add_history(sim.day(), L.t("Травма: %s. Больничный %d дн.") % [what, days])
	Nicks.count(w, "injury")
	Mood.add(sim, w, "injured")
	injuries.append(sim.day())
	while injuries.size() > 30:
		injuries.pop_front()
	for o in sim.workers:
		if o != w and o.present:
			Mood.add(sim, o, "coworker_injured")
	var cell := w.cell()
	sim.sfx.emit("injury", cell)
	sim.brain.send_home(w, L.t("Идёт в травмпункт") if not nurse else L.t("Фельдшер перевязал — домой"))
	if nurse:
		Mood.add(sim, w, "nurse_helped")
	w.bubble = "injury"
	info(L.t("Травма на производстве"), L.t("%s %s. Больничный — %d %s%s.") % [w.full_name(), what, days, Defs.plural(days, "день", "дня", "дней"), L.t(" (аптечка рядом помогла)") if aid else L.t(". С аптечкой рядом было бы легче")], "injury", Sim.LVL_BAD, cell)
	sim.paper.add(L.t("Охрана труда"), L.t("Травма: ") + w.full_name(), L.t("Напоминаем: спешка, усталость и изношенный станок — главные враги. Берегите себя."))
	sim.crew.on_injury(w, cause)
	var lc := 0.4 * float(Defs.inspections.get("freq_k", {}).get(mode, 1.0))
	if sim.rng.randf() < lc:
		sim.inspect.schedule("labor", sim.minute + sim.rng.randf_range(2.0, 5.0) * 1440.0, false, L.t("после травмы"))


func _aid_near(c: Vector2i) -> bool:
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "first_aid" and absi(t.cell.x - c.x) + absi(t.cell.y - c.y) <= 14:
			return true
	return false


## Шанс травмы за минуту работы.
func injury_chance(w: Worker, m: Thing) -> float:
	if not enabled:
		return 0.0
	var k := Defs.ev("injury_base") * injury_mode_k()
	if float(w.needs["rest"]) < 25.0:
		k *= 2.5
	if sim.office.rush_on():
		k *= 2.0
	if not w.dressed:
		k *= 1.6
	if m and m.condition < 30.0:
		k *= 2.0
	if not sim.rooms.is_lit(w.cell()):
		k *= 1.5
	if sim.season.work_k(w) < 0.9:
		k *= 1.3
	if w.skill(w.main_skill()) >= 8:
		k *= 0.7
	k *= sim.training.injury_k() * sim.upkeep.injury_k(w) * sim.eng.injury_k(w) * sim.crew.injury_k(w)
	if sim.office.active("safety"):
		k *= 0.85   # инженер по охране труда
	return k * Mood.trait_val(w, "defect_k", 1.0)


func injuries_month() -> int:
	var n := 0
	for d in injuries:
		if sim.day() - int(d) <= sim.season.dpm() * 2:
			n += 1
	return n


func _leave(w: Worker, why: String) -> void:
	sim.brain.abort(w)
	sim.office.on_quit(w)
	var owed := float(w.get_meta("wage_due", 0.0))
	if owed > 0.0:
		sim.spend(owed, "Расчёт при увольнении: " + w.full_name())
	sim.training.on_leave(w)
	sim.crew.on_leave(w)
	sim.workers.erase(w)
	sim.worker_rev += 1
	sim.notify("%s %s." % [w.full_name(), why], Sim.LVL_WARN)


# ================================================================ производственные события

func _materials() -> Array[Item]:
	var out: Array[Item] = []
	for it: Item in sim.items.values():
		if it.kind == "mat" and it.loc == Item.Loc.THING and it.reserved_by < 0:
			out.append(it)
	return out


func _ev_bad_metal() -> void:
	var mats := _materials()
	var by: Dictionary = {}
	for it in mats:
		if not by.has(it.def_id):
			by[it.def_id] = []
		(by[it.def_id] as Array).append(it.id)
	var best := ""
	for k in by.keys():
		if best == "" or (by[k] as Array).size() > (by[best] as Array).size():
			best = str(k)
	var ids: Array = by[best]
	var bad: Array = []
	for iid in ids:
		if sim.rng.randf() < 0.45:
			var it2: Item = sim.items.get(iid)
			if it2:
				it2.defect = true
				bad.append(iid)
	if bad.is_empty():
		return
	var refund := sim.material_price(best) * bad.size()
	letter("bad_metal", L.t("Бракованная партия металла"), L.t("ОТК обнаружило: в партии «%s» от поставщика %d прутков с трещинами и раковинами. Детали из них пойдут в брак.") % [Defs.material_name(best), bad.size()], "inspect", Sim.LVL_WARN,
		[{"text": L.t("Вернуть брак поставщику"), "hint": L.t("Прутки уберут со склада, деньги (%s) вернут через 3 дня") % Defs.money_str(refund)},
		 {"text": L.t("Пустить в работу"), "hint": L.t("Много брака на ОТК")}], 0, {"items": bad, "refund": refund, "mat": best})


func _res_bad_metal(d: Dictionary, choice: int) -> void:
	if choice != 0:
		return
	var n := 0
	for iid in d.get("items", []):
		var it: Item = sim.items.get(int(iid))
		if it and it.defect and it.loc != Item.Loc.WORKER:
			sim.delete_item(it)
			n += 1
	if n > 0:
		receivables.append({"amount": float(d.get("refund", 0.0)) * n / maxf(1.0, (d.get("items", []) as Array).size()), "due": sim.minute + 3.0 * 1440.0, "client": L.t("Поставщик (возврат за брак)"), "risk": 0.0})
		sim.notify(L.t("%d бракованных прутков отправили обратно поставщику.") % n, Sim.LVL_INFO)


func _ev_pipe() -> void:
	var rooms_r: Array = []
	for r in sim.rooms.list:
		for tid in r.things:
			var t: Thing = sim.things.get(tid)
			if t and t.built and t.def_id == "radiator":
				rooms_r.append(r)
				break
	if rooms_r.is_empty():
		return
	var r2: Rooms.Room = rooms_r[sim.rng.randi_range(0, rooms_r.size() - 1)]
	sim.season.burst_cell = r2.cells[0]
	sim.season.burst_until = sim.minute + 2.0 * 1440.0
	letter("pipe_burst", L.t("Прорвало трубу отопления"), L.t("В помещении «%s» прорвало трубу: батареи холодные, на полу лужа. Без ремонта там будет мороз.") % r2.title(), "heat", Sim.LVL_WARN,
		[{"text": L.t("Вызвать аварийную службу (18 000 ₽)"), "hint": L.t("Починят за 3 часа")}, {"text": L.t("Чинить своими силами"), "hint": L.t("Бесплатно, но сутки без тепла")}], 1,
		{"cx": r2.cells[0].x, "cy": r2.cells[0].y})


## 1.18: обрыв провода или прорыв водопровода — клетка сети разорвана, дальше ток (вода) не идёт.
func _ev_fault(layer: String) -> void:
	var c := sim.faults.spot(layer)
	if c.x < 0 or not sim.faults.make(layer, c):
		return
	var i := sim.world.idx(c)
	var cost := int(Faults.CREW_COST.get(layer, 10000.0))
	if layer == "cable":
		letter("wire_break", L.t("Обрыв провода"), L.t("Перебило кабель — искрит, дальше по линии тока нет: станки и свет за обрывом стоят. Электрик или любой рабочий заменит кусок кабеля, как при прокладке."), "uncable", Sim.LVL_WARN,
			[{"text": L.t("Вызвать аварийную бригаду (%s)") % Defs.money_str(cost), "hint": L.t("Починят за час")}, {"text": L.t("Чинить своими силами"), "hint": L.t("Бесплатно: кусок кабеля появится в чертежах, его проложат рабочие")}], 1,
			{"cx": c.x, "cy": c.y, "layer": layer, "i": i})
	else:
		letter("leak", L.t("Прорвало водопровод"), L.t("Лопнула труба — на полу лужа, дальше по трубе воды нет: туалеты и раковины за прорывом сухие. Рабочие заменят кусок трубы, как при прокладке."), "ov_water", Sim.LVL_WARN,
			[{"text": L.t("Вызвать аварийную бригаду (%s)") % Defs.money_str(cost), "hint": L.t("Починят за час")}, {"text": L.t("Чинить своими силами"), "hint": L.t("Бесплатно: кусок трубы появится в чертежах, его проложат рабочие")}], 1,
			{"cx": c.x, "cy": c.y, "layer": layer, "i": i})


func _res_pipe(_d: Dictionary, choice: int) -> void:
	if choice == 0:
		sim.spend(18000.0, "Ремонт: аварийная служба теплосети")
		sim.season.burst_until = sim.minute + 180.0
	else:
		sim.season.burst_until = sim.minute + 1440.0


func _ev_hot_order() -> void:
	if sim.progress.quiet():
		return
	var o := sim.orders.make_offer()
	if o.is_empty():
		return
	o["qty"] = int(ceil(int(o["qty"]) * 1.5))
	o["price"] = int(round(float(o["price"]) * 1.45 / 10.0) * 10)
	o["lead"] = maxi(2, int(o["lead"]) - 1)
	o["hot"] = true
	o["expires"] = sim.minute + 1440.0
	o["deadline"] = sim.orders.deadline_after(int(o["lead"]))
	sim.orders.list.append(o)
	# отдел сбыта оценивает, успеваем ли; решение — за директором
	var v := sim.sales.verdict(o)
	var why := str(v[0])
	var opinion := L.t("Сбыт: успеваем, можно брать.") if why == "" else L.t("Сбыт против: %s.") % L.tx(why)
	letter("hot_order", L.t("«Горящий» заказ"), L.t("%s срочно нужно %d шт. «%s» за %d %s. Платят на 45%% дороже обычного — %s.\n%s") % [str(o["client"]), int(o["qty"]), Defs.product_name(str(o["product"])), int(o["lead"]), Defs.plural(int(o["lead"]), "рабочий день", "рабочих дня", "рабочих дней"), Defs.money_str(float(o["price"]) * int(o["qty"])), opinion], "orders", Sim.LVL_GOOD,
		[{"text": L.t("Взять заказ"), "hint": L.t("Поставит его первым в очередь") if why == "" else L.t("Рискованно: можно не успеть")}, {"text": L.t("Отказаться"), "hint": ""}], 0 if why == "" else 1, {"order": int(o["id"])})


## Клиент нашёл пропущенный ОТК брак — рекламация придёт через 2–4 дня.
func scheduled_reclamation(o: Dictionary, bad: int, comp: float) -> void:
	scheduled.append({"ev": "reclamation", "at": sim.minute + sim.rng.randf_range(2.0, 4.0) * 1440.0,
		"data": {"client": str(o["client"]), "product": str(o["product"]), "bad": bad, "comp": comp}})


func _ev_reclamation(d: Dictionary) -> void:
	sim.market.on_reclamation()
	var p := str(d.get("product", ""))
	var bad := int(d.get("bad", 1))
	var have := sim.ok_in_storage(p) - sim.orders.allocated(p)
	var ch: Array = [{"text": L.t("Выплатить компенсацию (%s)") % Defs.money_str(float(d.get("comp", 0.0))), "hint": L.t("Репутация почти не пострадает")},
		{"text": L.t("Отказать: «Брак не наш»"), "hint": L.t("Репутация −6")}]
	if sim.office.active("legal"):
		ch.append({"text": L.t("Оспорить через юриста"), "hint": L.t("Экспертиза: шанс 50% снизить компенсацию вдвое, репутация −2")})
	if have >= bad:
		ch.insert(0, {"text": L.t("Заменить детали со склада (%d шт.)") % bad, "hint": L.t("Готовые детали уйдут клиенту")})
	letter("reclamation", L.t("Рекламация"), L.t("%s прислал рекламацию: в партии «%s» нашли %d %s с браком, пропущенных ОТК. Требуют решить вопрос.") % [str(d.get("client", L.t("Клиент"))), Defs.product_name(p), bad, Defs.plural(bad, "деталь", "детали", "деталей")], "orders", Sim.LVL_WARN,
		ch, 0, {"client": d.get("client", ""), "product": p, "bad": bad, "comp": d.get("comp", 0.0), "swap": have >= bad})
	sim.paper.add(L.t("Качество"), L.t("Рекламация от клиента"), L.t("Брак дошёл до заказчика. ОТК, это камень в ваш огород!"))


func _res_reclamation(d: Dictionary, choice: int) -> void:
	var swap := bool(d.get("swap", false))
	var opt := choice if swap else choice + 1
	match opt:
		0:
			var p := str(d["product"])
			var left := int(d["bad"])
			for it: Item in sim.items.values().duplicate():
				if left <= 0:
					break
				if it.kind == "part" and it.def_id == p and it.q == "ok" and it.reserved_by < 0 and it.loc == Item.Loc.THING:
					sim.delete_item(it)
					left -= 1
			sim.notify(L.t("Бракованные детали заменили со склада. Клиент доволен."), Sim.LVL_INFO)
		1:
			sim.spend(float(d.get("comp", 0.0)), "Штраф: компенсация по рекламации")
			sim.market.claim("liability", float(d.get("comp", 0.0)), "компенсация по рекламации")
			sim.reputation = maxf(0.0, sim.reputation - 1.0)
		2:
			sim.reputation = maxf(0.0, sim.reputation - 6.0)
			sim.notify(L.t("%s обиделся и рассказал всем, что у вас брак. Репутация упала.") % str(d.get("client", L.t("Клиент"))), Sim.LVL_BAD)
		3:
			var comp := float(d.get("comp", 0.0))
			sim.reputation = maxf(0.0, sim.reputation - 2.0)
			if sim.rng.randf() < 0.5:
				comp *= 0.5
				sim.notify(L.t("Юрист добился экспертизы: часть брака — от неправильного монтажа у заказчика. Компенсация вдвое меньше: %s.") % Defs.money_str(comp), Sim.LVL_GOOD)
			else:
				sim.notify(L.t("Экспертиза подтвердила брак: компенсацию пришлось выплатить полностью (%s).") % Defs.money_str(comp), Sim.LVL_WARN)
			sim.spend(comp, "Штраф: компенсация по рекламации")


func has_checkpoint() -> bool:
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "checkpoint":
			return true
	return false


func _ev_theft() -> void:
	if sim.crew.stop_outside_theft():
		return
	if sim.progress.dogs_tame and not sim.progress.dogs.is_empty() and sim.rng.randf() < 0.7:
		info(L.t("Собаки подняли лай"), L.t("Ночью кто-то лез через забор к складу, но заводские собаки подняли такой лай, что вор сбежал без металла."), "thief", Sim.LVL_GOOD)
		sim.paper.add(L.t("Бдительность"), L.t("Жучка на страже"), L.t("Заводские собаки отогнали несуна от склада. Профком выделил им по косточке."))
		return
	if sim.crew.search_on() and sim.rng.randf() < 0.85:
		info(L.t("Вахта задержала несуна"), L.t("Охранник на проходной нашёл в сумке у рабочего три прутка. Металл вернули на склад."), "thief", Sim.LVL_GOOD)
		sim.paper.add(L.t("Бдительность"), L.t("Вахта не дремлет"), L.t("Охрана на проходной снова на посту: несун задержан, металл возвращён. Спасибо за бдительность!"))
		return
	var mats := _materials()
	var n := mini(mats.size(), sim.rng.randi_range(2, 6))
	var mat_name := ""
	for i in n:
		var it: Item = mats[sim.rng.randi_range(0, mats.size() - 1)]
		mats.erase(it)
		mat_name = Defs.material_name(it.def_id)
		sim.delete_item(it)
	var cp := has_checkpoint()
	var txt := L.t("Со склада пропало %d прутков («%s»). Кто-то вынес через забор или проходную.") % [n, mat_name]
	if cp:
		letter("theft", L.t("Кража на складе"), txt, "thief", Sim.LVL_WARN,
			[{"text": L.t("Ввести досмотр на проходной (%s в день)") % Defs.money_str(Defs.ev("guard_cost_day")), "hint": L.t("Людям не нравится, но кражи почти прекратятся. Досматривает охранник — без него досмотра нет")}, {"text": L.t("Ничего не делать"), "hint": ""}], 1)
	else:
		info(L.t("Кража на складе"), txt + L.t(" Поставьте у въезда проходную с турникетами (Объекты → Безопасность) и наймите охранника — тогда можно ввести досмотр."), "thief", Sim.LVL_WARN, Vector2i(-1, -1), true)
	sim.paper.add(L.t("Происшествия"), L.t("Несуны снова в деле"), L.t("Со склада ушло %d прутков. Товарищи, металл — народное достояние, а не дачный забор!") % n)


func _ev_drinking() -> void:
	var st := _staff()
	st.sort_custom(func(a: Worker, b: Worker) -> bool: return Mood.has_trait(a, "drinker") and not Mood.has_trait(b, "drinker"))
	var a: Worker = st[0]
	var b: Worker = st[1] if st.size() > 1 else null
	if b == null:
		return
	Mood.add(sim, a, "fight")
	Mood.add(sim, b, "fight")
	if b.present and sim.rng.randf() < 0.5:
		injure(b, "fight")
	letter("drinking", L.t("Пьянка и драка"), L.t("%s и %s после обеда «отметили» что-то в бытовке и подрались. Мастера в ступоре, остальные смотрят, что будет.") % [a.full_name(), b.full_name()], "staff", Sim.LVL_WARN,
		[{"text": L.t("Объявить выговор обоим"), "hint": L.t("Настроение у них упадёт, но порядок будет")},
		 {"text": L.t("Уволить зачинщика (%s)") % a.full_name(), "hint": L.t("Остальные запомнят")},
		 {"text": L.t("Замять"), "hint": L.t("Коллектив решит, что можно всё")}], 0, {"a": a.id, "b": b.id})


func _res_drinking(d: Dictionary, choice: int) -> void:
	var a := sim.get_worker(int(d.get("a", -1)))
	var b := sim.get_worker(int(d.get("b", -1)))
	match choice:
		0:
			for w in [a, b]:
				if w:
					Mood.add(sim, w, "reprimand")
					w.add_history(sim.day(), L.t("Выговор за пьянку на работе"))
		1:
			if a:
				sim.fire(a, false)
		2:
			for w2 in sim.workers:
				Mood.add(sim, w2, "chaos")


## Драка в цеху (1.14): выговор, увольнение зачинщика или развести по сменам.
func _res_fight(d: Dictionary, choice: int) -> void:
	var a := sim.get_worker(int(d.get("a", -1)))
	var b := sim.get_worker(int(d.get("b", -1)))
	match choice:
		0:
			for w in [a, b]:
				if w:
					Mood.add(sim, w, "reprimand")
					w.add_history(sim.day(), L.t("Выговор за драку на работе"))
		1:
			if a:
				sim.fire(a, false)
		2:
			if a and b and a.shift == b.shift:
				sim.set_shift(b, 1 - b.shift)


func _res_rumor(choice: int) -> void:
	if choice == 0:
		for w in sim.workers:
			_remove_thought(w, "layoff_rumor")
			Mood.add(sim, w, "rumor_cleared")
		sim.notify(L.t("Собрание прошло: слухи развеяны, люди успокоились."), Sim.LVL_GOOD)


func _retiree() -> Worker:
	var best: Worker = null
	for w in sim.workers:
		if sim.career.pensioner(w) and not departures.any(func(x: Dictionary) -> bool: return int(x["wid"]) == w.id):
			if best == null or w.age > best.age:
				best = w
	return best


func _ev_retire() -> void:
	var w := _retiree()
	if w == null:
		return
	var student := _student_for(w)
	var st_txt := (L.t(" Опыт можно передать ученику — %s.") % student.full_name()) if student else ""
	letter("retire", L.t("Уход на пенсию"), L.t("%s, %s, %d лет, собирается на пенсию: «Хватит, внуки ждут». Уйдёт через два дня.%s") % [w.full_name(), w.prof_lc(), w.age, st_txt], "staff", Sim.LVL_INFO,
		[{"text": L.t("Уговорить остаться (премия 30 000 ₽)"), "hint": L.t("Поработает ещё год")},
		 {"text": L.t("Проводить с почётом (10 000 ₽ на подарок)"), "hint": L.t("Наставник передаст опыт ученику") if student else L.t("Коллективу будет приятно")},
		 {"text": L.t("Просто проводить"), "hint": ""}], 2, {"w": w.id, "s": student.id if student else -1})


func _student_for(w: Worker) -> Worker:
	var best: Worker = null
	for o in sim.workers:
		if o == w or o.prof != w.prof:
			continue
		if best == null or o.skill(o.main_skill()) < best.skill(best.main_skill()):
			best = o
	return best


func _res_retire(d: Dictionary, choice: int) -> void:
	var w := sim.get_worker(int(d.get("w", -1)))
	if w == null:
		return
	match choice:
		0:
			sim.spend(30000.0, "Премия: " + w.full_name())
			w.age -= 1
			Mood.add(sim, w, "bonus")
			w.add_history(sim.day(), L.t("Уговорили не уходить на пенсию"))
		1:
			sim.spend(10000.0, "Премия: подарок к пенсии")
			var s := sim.get_worker(int(d.get("s", -1)))
			if s:
				var sk := s.main_skill()
				s.skills[sk] = mini(10, s.skill(sk) + 2)
				s.add_history(sim.day(), L.t("Наставник %s передал опыт перед пенсией") % w.full_name())
			for o in sim.workers:
				if o != w:
					Mood.add(sim, o, "retire_party")
			departures.append({"wid": w.id, "at": sim.minute + 2880.0, "why": Nicks.gendered(L.t("{ушёл|ушла} на заслуженный отдых. Проводили всем коллективом"), w.female)})
			sim.paper.add(L.t("Наши ветераны"), L.t("Проводили на пенсию: ") + w.full_name(), L.t("%d лет у станка. Спасибо за труд! Ученики обещают не подвести.") % maxi(10, w.age - 20))
		2:
			departures.append({"wid": w.id, "at": sim.minute + 2880.0, "why": Nicks.gendered(L.t("{ушёл|ушла} на пенсию"), w.female)})


func _poach_target() -> Worker:
	var best: Worker = null
	for w in sim.workers:
		if w.has_grade() and w.grade() >= 4 and float(w.wage) < Mood.market_wage(w) * 1.25:
			if best == null or w.skill(w.main_skill()) > best.skill(best.main_skill()):
				best = w
	return best


func _ev_poach() -> void:
	var w := _poach_target()
	if w == null:
		return
	letter("poach", L.t("Переманивают конкуренты"), L.t("%s, %s, получил предложение от «Металлист-Т» — на четверть больше денег. Просит прибавку, иначе уйдёт через день.") % [w.full_name(), w.title_lc()], "staff", Sim.LVL_WARN,
		[{"text": L.t("Поднять ставку на 20%"), "hint": L.t("%s → %s за смену") % [Defs.money_str(w.wage), Defs.money_str(w.wage * 1.2)]}, {"text": L.t("Отпустить"), "hint": L.t("Уйдёт к конкуренту")}], 0, {"w": w.id})


func _res_poach(d: Dictionary, choice: int) -> void:
	var w := sim.get_worker(int(d.get("w", -1)))
	if w == null:
		return
	if choice == 0:
		sim.change_wage(w, 0.2)
		Mood.add(sim, w, "raise_kept")
	else:
		departures.append({"wid": w.id, "at": sim.minute + 1440.0, "why": Nicks.gendered(L.t("{ушёл|ушла} к конкурентам за длинным рублём"), w.female)})


func _young() -> Worker:
	var c: Array[Worker] = []
	for w in sim.workers:
		if w.age >= 22 and w.age <= 40:
			c.append(w)
	return c[sim.rng.randi_range(0, c.size() - 1)] if not c.is_empty() else null


func _ev_gift(kind: String) -> void:
	var w := _young()
	if w == null:
		return
	var txt := Nicks.gendered(L.t("%s {женится|выходит замуж}! Коллектив собирает на подарок."), w.female) % w.full_name() if kind == "wedding" else L.t("У %s родился ребёнок! В курилке уже выбирают имя.") % w.full_name()
	letter(kind, L.t("Свадьба") if kind == "wedding" else L.t("Пополнение в семье"), txt, "party", Sim.LVL_GOOD,
		[{"text": L.t("Подарок от завода (5 000 ₽)"), "hint": L.t("Человек будет очень рад")}, {"text": L.t("Ограничиться поздравлением"), "hint": ""}], 1, {"w": w.id, "kind": kind})
	sim.paper.add(L.t("Поздравляем!"), (L.t("Свадьба: %s") if kind == "wedding" else L.t("Родился малыш у %s")) % w.full_name(), L.t("Совет да любовь! Коллектив поздравляет и желает счастья.") if kind == "wedding" else L.t("Растёт смена! Поздравляем счастливых родителей."))


func _res_gift(d: Dictionary, choice: int) -> void:
	var w := sim.get_worker(int(d.get("w", -1)))
	if w == null:
		return
	if choice == 0:
		sim.spend(5000.0, "Премия: подарок " + w.full_name())
		Mood.add(sim, w, "gift_given")
		w.add_history(sim.day(), L.t("Завод поздравил: %s") % (L.t("свадьба") if str(d.get("kind")) == "wedding" else L.t("рождение ребёнка")))
	else:
		Mood.add(sim, w, "gift_none")


func _rational_author() -> Worker:
	var rat := sim.workers.filter(func(x: Worker) -> bool: return Mood.has_trait(x, "rationalizer"))
	if not rat.is_empty() and sim.rng.randf() < 0.75:
		return rat[sim.rng.randi_range(0, rat.size() - 1)]
	var c: Array[Worker] = []
	for w in sim.workers:
		if w.skill(w.main_skill()) >= 4 or w.prof == "technologist":
			c.append(w)
	return c[sim.rng.randi_range(0, c.size() - 1)] if not c.is_empty() else null


const RATIONAL := [
	["wear_k", 0.9, "приспособление для смазки направляющих", "станки изнашиваются на 10% медленнее"],
	["setup_k", 0.85, "быстросменные кулачки патрона", "переналадка на 15% быстрее"],
	["defect_k", 0.92, "шаблон для контроля фасок", "брака на 8% меньше"],
	["haul_k", 1.1, "разметка проходов и тележка «по уму»", "носят на 10% быстрее"],
]


func _ev_rational() -> void:
	# 1.15 (Н-1): чаще — предложение под конкретный станок и деталь
	if sim.rng.randf() < 0.75 and sim.career.propose_rational():
		return
	var w := _rational_author()
	if w == null:
		return
	var opts: Array = []
	for r in RATIONAL:
		var cur := perk(str(r[0]))
		if (float(r[1]) < 1.0 and cur > 0.7) or (float(r[1]) > 1.0 and cur < 1.3):
			opts.append(r)
	if opts.is_empty():
		return
	var p: Array = opts[sim.rng.randi_range(0, opts.size() - 1)]
	letter("rational", L.t("Рацпредложение"), L.t("%s предлагает %s: %s. Автор просит вознаграждение.") % [w.full_name(), L.t(str(p[2])), L.t(str(p[3]))], "idea", Sim.LVL_GOOD,
		[{"text": L.t("Внедрить и заплатить автору 12 000 ₽"), "hint": L.t("Улучшение навсегда")}, {"text": L.t("Отклонить"), "hint": L.t("Автор обидится")}], 1, {"w": w.id, "key": str(p[0]), "v": float(p[1]), "what": L.t(str(p[2]))})


func _res_rational(d: Dictionary, choice: int) -> void:
	var w := sim.get_worker(int(d.get("w", -1)))
	if choice == 0:
		sim.spend(12000.0, "Премия: рацпредложение")
		var key := str(d["key"])
		perks[key] = perk(key) * float(d["v"])
		if w:
			Mood.add(sim, w, "rational_paid")
			w.add_history(sim.day(), L.t("Рацпредложение внедрено: ") + str(d["what"]))
			sim.paper.add(L.t("Новаторы"), L.t("Рацпредложение: ") + str(d["what"]), L.t("Автор — %s. Внедрено в производство, автору выплачено вознаграждение.") % w.full_name())
	elif w:
		Mood.add(sim, w, "rational_ignored")


func _res_grant(_d: Dictionary, choice: int) -> void:
	match choice:
		0:
			sim.office.add_loan(1500000.0, 26, 0.05, "Заём фонда «Промразвитие»")
		1:
			add_mod("machine_subsidy", 0.7, float(sim.season.dpm()) * 1440.0, L.t("Субсидия 30% на станок"))
			sim.notify(L.t("Субсидия оформлена: следующий станок обойдётся на 30% дешевле (месяц)."), Sim.LVL_GOOD)


func _ev_sale() -> void:
	var opts: Array = []
	for k in ["lathe", "mill", "drill", "weld_post", "assembly_table", "furnace", "cnc_lathe"]:
		if Defs.objects.has(k) and sim.progress.locked_reason(k) == "":
			opts.append(k)
	if opts.is_empty():
		return
	var k2: String = opts[sim.rng.randi_range(0, opts.size() - 1)]
	var price := float(Defs.objects[k2]["cost"]) * 0.4
	letter("competitor_sale", L.t("Торги конкурента"), L.t("Обанкротился «Металлист-Т». На торгах его оборудование: «%s» всего за 40%% цены (%s). Предложение — на неделю.") % [Defs.obj_name(k2), Defs.money_str(price)], "shop", Sim.LVL_GOOD,
		[{"text": L.t("Выкупить право (оплата при установке)"), "hint": L.t("Ставьте станок из меню «Объекты» — цена будет 40%")}, {"text": L.t("Не нужно"), "hint": ""}], 1, {"def": k2})


func _res_sale(d: Dictionary, choice: int) -> void:
	if choice == 0:
		var k := str(d["def"])
		add_mod("voucher:" + k, 0.4, 7.0 * 1440.0, L.t("Станок с торгов за 40%%: %s") % Defs.obj_name(k))
		sim.notify(L.t("Выкуплено право на «%s» с торгов. Поставьте его из «Объектов» в течение недели — цена 40%%.") % Defs.obj_name(k), Sim.LVL_GOOD)


func _res_raid(choice: int) -> void:
	var ok := false
	match choice:
		0:
			sim.spend(80000.0, "Юристы: защита от рейдеров")
			ok = sim.rng.randf() < 0.85
		1:
			ok = sim.rng.randf() < 0.4
		2:
			sim.spend(maxf(0.0, sim.money) * 0.2, "Отступные рейдерам")
			ok = true
	if ok:
		info(L.t("Рейдеры отступили"), L.t("Попытка захвата провалилась, документы признаны поддельными."), "court", Sim.LVL_GOOD)
	else:
		var loss := maxf(50000.0, maxf(0.0, sim.money) * 0.25)
		sim.spend(loss, "Штраф и судебные издержки: рейдеры")
		sim.reputation = maxf(0.0, sim.reputation - 10.0)
		info(L.t("Рейдеры отсудили своё"), L.t("Пока шли суды, счета были арестованы, часть денег списали по поддельным документам: %s. Репутация пострадала.") % Defs.money_str(loss), "court", Sim.LVL_BAD, Vector2i(-1, -1), true)


# ================================================================ оплаты (лихие девяностые)

## Клиент забрал заказ: в «Лихих девяностых» он может заплатить позже или бартером.
func defer_payment(amount: float, client: String, title: String) -> bool:
	if mode != "wild" or amount <= 0.0 or sim.rng.randf() >= Defs.ev("wild_defer_chance"):
		return false
	if sim.rng.randf() < 0.45:
		letter("barter", L.t("Бартер вместо денег"), L.t("%s говорит, что денег нет, и предлагает вместо %s за «%s» вагон сахара на 120%% суммы. Сахар можно продать — за неделю, если повезёт.") % [client, Defs.money_str(amount), title], "handshake", Sim.LVL_WARN,
			[{"text": L.t("Взять сахаром (≈%s через неделю)") % Defs.money_str(amount * 1.2), "hint": L.t("Есть риск продать дешевле")}, {"text": L.t("Требовать деньги"), "hint": L.t("Оплата задержится на 5–10 дней")}], 1,
			{"amount": amount, "client": client})
	else:
		var days := sim.rng.randi_range(3, 9)
		receivables.append({"amount": amount, "due": sim.minute + days * 1440.0, "client": client, "risk": 0.12})
		info(L.t("Задержка оплаты"), L.t("%s забрал заказ, но заплатит только через %d %s: «Денег нет, но вы держитесь».") % [client, days, Defs.plural(days, "день", "дня", "дней")], "money", Sim.LVL_WARN)
	return true


func _res_barter(d: Dictionary, choice: int) -> void:
	var a := float(d.get("amount", 0.0))
	if choice == 0:
		receivables.append({"amount": a * 1.2, "due": sim.minute + 7.0 * 1440.0, "client": L.t("Продажа сахара"), "risk": 0.25, "barter": true})
	else:
		receivables.append({"amount": a, "due": sim.minute + sim.rng.randf_range(5.0, 10.0) * 1440.0, "client": str(d.get("client", L.t("Клиент"))), "risk": 0.15})


func _collect(r: Dictionary) -> void:
	var a := float(r["amount"])
	var who := str(r["client"])
	if sim.rng.randf() < float(r.get("risk", 0.0)):
		if bool(r.get("barter", false)):
			a *= 0.6
			sim.earn(a, "Оплата: бартер продан с убытком")
			info(L.t("Сахар ушёл дёшево"), L.t("Рынок завален сахаром, продали только за %s.") % Defs.money_str(a), "money", Sim.LVL_WARN)
		elif int(r.get("delays", 0)) < 1:
			r["due"] = sim.minute + sim.rng.randf_range(3.0, 6.0) * 1440.0
			r["delays"] = int(r.get("delays", 0)) + 1
			receivables.append(r)
			sim.notify(L.t("%s снова переносит оплату (%s). «В понедельник, точно!»") % [who, Defs.money_str(a)], Sim.LVL_WARN)
		else:
			a *= 0.5
			sim.earn(a, "Оплата через суд: " + who)
			info(L.t("Половина долга через суд"), L.t("%s обанкротился, по суду удалось взыскать только %s.") % [who, Defs.money_str(a)], "court", Sim.LVL_BAD)
		return
	sim.earn(a, "Оплата (долг): " + who)
	sim.notify(L.t("%s наконец заплатил: %s.") % [who, Defs.money_str(a)], Sim.LVL_GOOD)


func receivable_total() -> float:
	var t := 0.0
	for r: Dictionary in receivables:
		t += float(r["amount"])
	return t


# ================================================================ забастовка

func _check_strike_mood() -> void:
	if strike.get("active", false) or not sim.is_workday():
		return
	var st := _staff()
	if st.size() < 4:
		low_mood_days = 0
		return
	var s := 0.0
	for w in st:
		s += w.mood
	var avg := s / st.size()
	if avg < Defs.ev("strike_mood"):
		low_mood_days += 1
	else:
		low_mood_days = 0
	var promise := float(strike.get("promise_until", -1.0))
	var broken := promise > 0.0 and sim.minute > promise and not _demand_met(str(strike.get("demand", "")))
	if broken:
		strike["promise_until"] = -1.0
	var need := int(Defs.ev("strike_days")) + sim.crew.strike_patience()
	if not broken and low_mood_days == need - 1 and sim.day() >= int(cooldowns.get("strike", 0)):
		sim.crew.strike_warning(avg)
	if (low_mood_days >= need and sim.day() >= int(cooldowns.get("strike", 0))) or broken:
		_start_strike(broken)


func _demand_met(dm: String) -> bool:
	match dm:
		"canteen":
			return not sim.rooms.of_type("canteen").is_empty()
		"locker":
			return not sim.rooms.of_type("locker").is_empty()
		"arrears":
			return sim.progress.arrears_total() <= 0.0
	return true


func _start_strike(broken_promise: bool) -> void:
	var st := _staff()
	var leader: Worker = st[0]
	for w in st:
		if w.mood < leader.mood or (Mood.has_trait(w, "grumpy") and not Mood.has_trait(leader, "grumpy")):
			leader = w
	var demand := "bonus"
	var wage_low := 0
	for w2 in st:
		if float(w2.wage) < Mood.market_wage(w2) * 0.95:
			wage_low += 1
	if broken_promise:
		demand = str(strike.get("demand", "bonus"))
	elif sim.progress.arrears_total() > 0.0:
		demand = "arrears"   # 1.20: не платят зарплату — первым делом требуют долги
	elif sim.rooms.of_type("canteen").is_empty() and st.size() >= 6:
		demand = "canteen"
	elif sim.rooms.of_type("locker").is_empty():
		demand = "locker"
	elif sim.office.rush_on() or sim.office.overtime_on() or has_mod("rush"):
		demand = "rush"
	elif wage_low * 2 >= st.size():
		demand = "wage"
	strike = {"active": true, "demand": demand, "leader": leader.id, "since": sim.minute, "days": 0, "offers": 0}
	strikes_total += 1
	low_mood_days = 0
	_strike_letter(broken_promise)
	sim.paper.add(L.t("Профсоюзная жизнь"), L.t("Коллектив объявил забастовку"), L.t("Требование: %s. Администрация обещает разобраться.") % demand_text(demand).to_lower())


func demand_text(dm: String) -> String:
	match dm:
		"canteen":
			return L.t("Построить нормальную столовую")
		"locker":
			return L.t("Сделать бытовку для переодевания")
		"rush":
			return L.t("Отменить аврал и сверхурочные")
		"wage":
			return L.t("Поднять зарплату на 10%")
		"bonus":
			return L.t("Выплатить всем премию по 5 000 ₽")
		"arrears":
			return L.t("Выплатить долги по зарплате")
	return dm


func _strike_letter(broken: bool) -> void:
	var dm := str(strike.get("demand", "bonus"))
	var leader := sim.get_worker(int(strike.get("leader", -1)))
	var lname := leader.full_name() if leader else L.t("профорг")
	var txt := L.t("Рабочие бросили станки и вышли к проходной с плакатами. Требование: %s. Во главе — %s.") % [demand_text(dm).to_lower(), lname]
	if broken:
		txt = L.t("Обещание не выполнено — рабочие снова бастуют. Требование прежнее: %s.") % demand_text(dm).to_lower()
	if int(strike.get("days", 0)) > 0:
		txt = L.t("Забастовка идёт %d-й день. Требование: %s. Каждый день простоя бьёт по репутации.") % [int(strike["days"]) + 1, demand_text(dm).to_lower()]
	var ch: Array = [
		{"text": L.t("Выполнить требование"), "hint": _demand_cost(dm)},
		{"text": L.t("Предложить компромисс"), "hint": L.t("Могут не согласиться")},
		{"text": L.t("Уволить зачинщика (%s)") % lname, "hint": L.t("Жёстко. Остальные испугаются — или разозлятся")},
		{"text": L.t("Ждать"), "hint": L.t("Через несколько дней сдадутся сами, но обиду запомнят")}]
	letter("strike", L.t("Забастовка!"), txt, "strike", Sim.LVL_BAD, ch, 3)


func _demand_cost(dm: String) -> String:
	var n := _staff().size()
	match dm:
		"canteen", "locker":
			return L.t("Стройте в течение 5 дней, иначе снова забастуют")
		"rush":
			return L.t("Аврал и сверхурочные отключатся")
		"wage":
			return L.t("+10% к ставке всем рабочим")
		"bonus":
			return L.t("%s сразу") % Defs.money_str(5000.0 * n)
		"arrears":
			return L.t("%s сразу") % Defs.money_str(sim.progress.arrears_total())
	return ""


func _res_strike(choice: int) -> void:
	if not strike.get("active", false):
		return
	var dm := str(strike.get("demand", "bonus"))
	match choice:
		0:
			_apply_demand(dm, 1.0)
			_end_strike("strike_won", L.t("Требования выполнены, рабочие вернулись к станкам."))
		1:
			var acc := 0.55 - int(strike.get("offers", 0)) * 0.15 + (0.1 if int(strike.get("days", 0)) >= 2 else 0.0)
			strike["offers"] = int(strike.get("offers", 0)) + 1
			if sim.rng.randf() < acc:
				_apply_demand(dm, 0.5)
				_end_strike("strike_half", L.t("Договорились на компромиссе. Рабочие вернулись к станкам."))
			else:
				for w in _staff():
					Mood.add(sim, w, "chaos")
				sim.notify(L.t("Компромисс отвергли: «Подачки нам не нужны!» Забастовка продолжается."), Sim.LVL_BAD)
		2:
			var leader := sim.get_worker(int(strike.get("leader", -1)))
			if leader:
				sim.fire(leader, false)
			sim.reputation = maxf(0.0, sim.reputation - 3.0)
			if sim.rng.randf() < 0.55:
				_end_strike("strike_crushed", L.t("Зачинщика уволили. Остальные молча вернулись к станкам."))
			else:
				sim.notify(L.t("Увольнение зачинщика только разозлило людей. Забастовка продолжается."), Sim.LVL_BAD)
				for w2 in _staff():
					Mood.add(sim, w2, "strike_crushed")
		3:
			if int(strike.get("days", 0)) >= int(Defs.ev("strike_days")):
				for w3 in _staff():
					if w3.mood < 20.0 and sim.rng.randf() < 0.3:
						departures.append({"wid": w3.id, "at": sim.minute + 600.0, "why": Nicks.gendered(L.t("уволил{ся|ась} после проигранной забастовки"), w3.female)})
				_end_strike("strike_lost", L.t("Забастовка выдохлась: люди вернулись к станкам, но обиду затаили."))


func _apply_demand(dm: String, k: float) -> void:
	var st := _staff()
	match dm:
		"wage":
			for w in st:
				sim.change_wage(w, 0.1 * k)
		"bonus":
			sim.spend(5000.0 * k * st.size(), "Премия: всем рабочим по требованию забастовщиков")
			for w2 in st:
				Mood.add(sim, w2, "bonus")
		"rush":
			sim.office.policies["rush"] = false
			sim.office.policies["overtime"] = false
			remove_mod("rush")
		"arrears":
			if k >= 1.0:
				var err := sim.progress.pay_arrears()
				if err != "":
					sim.notify(L.t("Долги по зарплате погасить не вышло: %s. Забастовка вернётся.") % err, Sim.LVL_BAD)
					strike["promise_until"] = sim.minute + 3.0 * 1440.0
			else:
				strike["promise_until"] = sim.minute + 5.0 * 1440.0
				sim.notify(L.t("Пообещали погасить долги по зарплате за 5 дней. Не забудьте!"), Sim.LVL_WARN)
		"canteen", "locker":
			strike["promise_until"] = sim.minute + (5.0 if k >= 1.0 else 10.0) * 1440.0
			sim.notify(L.t("Пообещали: %s в течение %d дней. Не забудьте!") % [demand_text(dm).to_lower(), 5 if k >= 1.0 else 10], Sim.LVL_WARN)


func _end_strike(thought: String, text: String) -> void:
	var promise := float(strike.get("promise_until", -1.0))
	var dm := str(strike.get("demand", ""))
	strike = {"active": false, "demand": dm, "promise_until": promise}
	cooldowns["strike"] = sim.day() + int(Defs.events["events"]["strike"].get("cd", 20))
	for w in _staff():
		Mood.add(sim, w, thought)
		_remove_thought(w, "chaos")
	info(L.t("Забастовка окончена"), text, "strike", Sim.LVL_INFO)


## Участвует ли рабочий в забастовке прямо сейчас.
func striking(w: Worker) -> bool:
	return bool(strike.get("active", false)) and not w.is_itr()


## Место митинга у проходной.
func rally_cell(w: Worker) -> Vector2i:
	var wd := sim.world
	var base := Vector2i(sim.gate_x, wd.plot.end.y - 3)
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "checkpoint":
			base = t.cell + Vector2i(0, -2)
			break
	var k := absi(w.id * 7919) % 15
	var c := base + Vector2i(k % 5 - 2, -int(k / 5))
	return wd.nearest_passable(c)


# ================================================================ праздники и календарь

func _holidays() -> void:
	var h := sim.season.holiday()
	if h.is_empty():
		return
	var key := "%s:%d" % [str(h["id"]), sim.season.year()]
	if done_holidays.has(key):
		return
	done_holidays[key] = true
	var n := sim.workers.size()
	match str(h["id"]):
		"new_year":
			letter("holiday", L.t("Новый год на носу"), L.t("Последний рабочий день года. Коллектив ждёт корпоратив и премию. Ёлку в бытовке уже нарядили сами."), "party", Sim.LVL_GOOD,
				[{"text": L.t("Корпоратив и премия (%s)") % Defs.money_str(n * 7000.0), "hint": L.t("Настроение — на все праздники")},
				 {"text": L.t("Только корпоратив (%s)") % Defs.money_str(n * 2500.0), "hint": ""},
				 {"text": L.t("Обойдёмся"), "hint": L.t("Обидятся")}], 1, {"h": "new_year"})
		"ny_off":
			for w in sim.workers:
				Mood.add(sim, w, "nye_off")
			info(L.t("Новогодние каникулы"), L.t("Три дня отдыха: завод стоит, люди с семьями. С Новым годом!"), "party", Sim.LVL_GOOD)
			sim.paper.add(L.t("С Новым годом!"), L.t("С Новым годом, товарищи!"), L.t("Пусть станки не ломаются, заказы не горят, а компот в столовой не кончается!"))
		"feb23":
			letter("holiday", L.t("23 февраля"), L.t("Женская часть коллектива спрашивает, будет ли завод поздравлять мужчин."), "party", Sim.LVL_INFO,
				[{"text": L.t("Подарки мужчинам (%s)") % Defs.money_str(_count_sex(false) * 1500.0), "hint": ""}, {"text": L.t("Только открытка"), "hint": ""}], 1, {"h": "feb23"})
		"mar8":
			letter("holiday", L.t("8 марта"), L.t("Мужчины уже скинулись на тюльпаны. А что от завода?"), "party", Sim.LVL_INFO,
				[{"text": L.t("Цветы и премия женщинам (%s)") % Defs.money_str(_count_sex(true) * 2000.0), "hint": ""}, {"text": L.t("Только открытка"), "hint": L.t("Женщинам будет обидно")}], 1, {"h": "mar8"})
		"may_off":
			info(L.t("Праздник весны и труда"), L.t("Выходной день. Мир, труд, май!"), "party", Sim.LVL_GOOD)
		"subbotnik":
			letter("holiday", L.t("Субботник"), L.t("Весна, снег сошёл — территория в мусоре. Профком предлагает завтра выйти на субботник."), "party", Sim.LVL_INFO,
				[{"text": L.t("Провести субботник"), "hint": L.t("Территорию уберут, коллектив сплотится")}, {"text": L.t("Не надо"), "hint": ""}], 0, {"h": "subbotnik"})
		"machine_day":
			letter("holiday", L.t("День машиностроителя"), L.t("Профессиональный праздник! Можно провести торжественное собрание и вручить грамоты лучшим."), "party", Sim.LVL_GOOD,
				[{"text": L.t("Собрание, грамоты и премии (%s)") % Defs.money_str(20000.0 + n * 1500.0), "hint": L.t("+репутация, +настроение")}, {"text": L.t("Просто поздравить"), "hint": ""}], 1, {"h": "machine_day"})


func _count_sex(female: bool) -> int:
	var n := 0
	for w in sim.workers:
		if w.female == female:
			n += 1
	return n


func _res_holiday(d: Dictionary, choice: int) -> void:
	var n := sim.workers.size()
	match str(d.get("h", "")):
		"new_year":
			if choice <= 1:
				sim.spend(n * 2500.0, "Премия: новогодний корпоратив")
				for w in sim.workers:
					Mood.add(sim, w, "corporate")
				sim.paper.add(L.t("Праздник"), L.t("Корпоратив удался"), L.t("Песни под баян, оливье и конкурс «Кто быстрее наточит». Победила дружба."))
				sim.town.dk_concert()
			if choice == 0:
				sim.spend(n * 4500.0, "Премия: новогодняя")
				for w2 in sim.workers:
					Mood.add(sim, w2, "ny_bonus")
			if choice == 2:
				for w3 in sim.workers:
					Mood.add(sim, w3, "no_party")
		"feb23", "mar8":
			var fem := str(d["h"]) == "mar8"
			for w in sim.workers:
				if w.female != fem:
					continue
				Mood.add(sim, w, "holiday_gift" if choice == 0 else ("holiday_forgot" if fem else "holiday_gift"))
			if choice == 0:
				sim.spend(_count_sex(fem) * (2000.0 if fem else 1500.0), "Премия: подарки к празднику")
		"subbotnik":
			if choice == 0:
				for gid in sim.ground_items.duplicate():
					var it: Item = sim.items.get(gid)
					if it and it.kind == "part" and it.q == "scrap":
						sim.delete_item(it)
				for w in sim.workers:
					Mood.add(sim, w, "subbotnik")
				sim.reputation = minf(100.0, sim.reputation + 2.0)
				var s := sim.season
				for i in s.snow.size():
					s.snow[i] = 0
				s.snow_rev += 1
				sim.paper.add(L.t("Субботник"), L.t("Всем коллективом — на уборку"), L.t("Вымели территорию, покрасили бордюры, посадили берёзку у проходной."))
		"machine_day":
			if choice == 0:
				sim.spend(20000.0 + n * 1500.0, "Премия: День машиностроителя")
				sim.reputation = minf(100.0, sim.reputation + 3.0)
				for w in sim.workers:
					Mood.add(sim, w, "machine_day")
				sim.paper.add(L.t("Праздник"), L.t("С Днём машиностроителя!"), L.t("На торжественном собрании вручили грамоты лучшим. Директор пообещал новые станки."))
				sim.town.dk_concert()


## Месячный план: в начале месяца — цель по отгрузкам, в конце — итог и, если горит, аврал.
func _month_plan() -> void:
	var s := sim.season
	var ma := s.month_abs()
	var shipped := int(sim.stats.get("shipped", 0))
	if int(plan.get("m", -1)) != ma:
		if not plan.is_empty():
			var got := shipped - int(plan.get("base", 0))
			var tgt := int(plan.get("target", 0))
			var mname := _month_lc(int(plan["m"]) % 12)
			if tgt > 0 and got >= tgt:
				sim.reputation = minf(100.0, sim.reputation + 2.0)
				for w in sim.workers:
					Mood.add(sim, w, "plan_done")
				info(L.t("План выполнен"), L.t("Итоги месяца (%s): отгружено %d из %d по плану. Репутация растёт, люди довольны.") % [mname, got, tgt], "goals", Sim.LVL_GOOD)
				sim.paper.add(L.t("Итоги месяца"), L.t("План за %s выполнен!") % mname, L.t("Отгружено %d изделий при плане %d. Так держать!") % [got, tgt])
				sim.stats["plans_done"] = int(sim.stats.get("plans_done", 0)) + 1
			elif tgt > 0:
				sim.paper.add(L.t("Итоги месяца"), L.t("План за %s не выполнен") % mname, L.t("Отгружено %d из %d. Есть над чем поработать.") % [got, tgt])
		var made_last := shipped - int(plan.get("base", shipped))
		var target := 0
		if plan.is_empty() or made_last <= 0:
			# первый месяц: по числу станков
			target = maxi(12, sim.things_of("machine").size() * 24)
		else:
			# план растёт на 10% от достигнутого — как положено
			target = maxi(12, int(round(made_last * 1.1)))
		plan = {"m": ma, "target": target, "base": shipped, "warned": false}
		return
	# конец месяца: «план горит»
	var got2 := shipped - int(plan.get("base", 0))
	if s.dom() == s.dpm() - 4 and not bool(plan.get("warned", false)) and sim.is_workday():
		plan["warned"] = true
		if got2 < int(plan.get("target", 0)) * 0.75:
			letter("month_end", L.t("План горит!"), L.t("Конец месяца, а отгружено %d из %d. Можно объявить аврал до конца месяца: работа быстрее на четверть, но брака и усталости больше.") % [got2, int(plan["target"])], "goals", Sim.LVL_WARN,
				[{"text": L.t("Объявить аврал до конца месяца"), "hint": L.t("Штурмовщина, как положено")}, {"text": L.t("Работать спокойно"), "hint": ""}], 1)
	# летние отпуска
	if s.month() == 6 and s.dom() == 1 and sim.workers.size() >= 4:
		letter("vacation", L.t("Сезон отпусков"), L.t("Лето! Люди просятся в отпуск. Можно отпустить по очереди — часть людей не будет неделю, зато вернутся отдохнувшими."), "calendar", Sim.LVL_INFO,
			[{"text": L.t("Отпустить по очереди (четверть людей на неделю)"), "hint": L.t("Отпускные — средняя ставка за 5 смен")}, {"text": L.t("Отказать — план важнее"), "hint": L.t("Настроение упадёт")}], 0)


## Месяц для «План за сентябрь»: по-русски — строчными, по-английски — с заглавной.
func _month_lc(i: int) -> String:
	return Season.MONTHS_EN[i] if L.is_en() else Season.MONTHS[i].to_lower()


func _res_vacation(_d: Dictionary, choice: int) -> void:
	if choice == 1:
		for w in sim.workers:
			Mood.add(sim, w, "no_vacation")
		return
	var st := sim.workers.duplicate()
	sim.shuffle(st)
	var n := maxi(1, int(st.size() / 4))
	for i in n:
		var w2: Worker = st[i]
		w2.sick_until = float(sim.day() + 6) * 1440.0 + 1200.0
		w2.away_why = "в отпуске"
		if w2.present:
			sim.brain.send_home(w2, L.t("Уходит в отпуск"))
		Mood.add(sim, w2, "vacation")
		sim.spend(float(w2.wage) * 5.0, "Зарплата: отпускные " + w2.full_name())
		w2.add_history(sim.day(), Nicks.gendered(L.t("{Ушёл|Ушла} в отпуск на неделю"), w2.female))
	sim.notify(L.t("В отпуск ушли %d %s.") % [n, Defs.plural(n, "человек", "человека", "человек")], Sim.LVL_INFO)


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {
		"mode": mode, "tension": tension, "last": last_event_day, "cd": cooldowns, "letters": letters,
		"archive": archive.slice(0, 50), "mods": mods, "perks": perks, "strike": strike, "fires": _keys_to_str(fires),
		"soot": soot.keys(), "fire_start": fire_start, "brigade": brigade_at, "brig": brigade.to_dict(), "recv": receivables, "dep": departures,
		"sched": scheduled, "inj": injuries, "plan": plan, "guard": guard, "lowd": low_mood_days, "hol": done_holidays,
		"fires_n": fires_total, "strikes_n": strikes_total, "lid": _next_letter_id,
	}


func _keys_to_str(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d.keys():
		o[str(k)] = d[k]
	return o


func from_dict(d: Dictionary) -> void:
	mode = str(d.get("mode", "market"))
	tension = float(d.get("tension", 0.0))
	last_event_day = int(d.get("last", 0))
	cooldowns = d.get("cd", {})
	for k in cooldowns.keys():
		cooldowns[k] = int(cooldowns[k])
	letters = d.get("letters", [])
	archive = d.get("archive", [])
	mods = d.get("mods", [])
	perks = d.get("perks", {})
	strike = d.get("strike", {})
	fires.clear()
	var fd: Dictionary = d.get("fires", {})
	for k2 in fd.keys():
		fires[int(k2)] = float(fd[k2])
	soot.clear()
	for k3 in d.get("soot", []):
		soot[int(k3)] = true
	fire_start = float(d.get("fire_start", -1.0))
	brigade_at = float(d.get("brigade", -1.0))
	brigade.from_dict(d.get("brig", {}))
	if not d.has("brig") and brigade_at >= 0.0 and not fires.is_empty():
		brigade.dispatch_at = sim.minute   # старое сохранение: пожарных уже вызвали — выезжают
	receivables = d.get("recv", [])
	departures = d.get("dep", [])
	scheduled = d.get("sched", [])
	injuries = d.get("inj", [])
	plan = d.get("plan", {})
	guard = bool(d.get("guard", false))
	low_mood_days = int(d.get("lowd", 0))
	done_holidays = d.get("hol", {})
	fires_total = int(d.get("fires_n", 0))
	strikes_total = int(d.get("strikes_n", 0))
	_next_letter_id = int(d.get("lid", 1))
	for l: Dictionary in letters:
		l["id"] = int(l["id"])
		l["def"] = int(l["def"])
		_next_letter_id = maxi(_next_letter_id, int(l["id"]) + 1)
