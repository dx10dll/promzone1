class_name Sim
extends RefCounted
## Корень симуляции: время, деньги, грузы, объекты, чертежи, фургоны, персонал.
## Не зависит от отображения — можно гонять без графики (тесты, ускорение).

signal notified(text: String, level: int, cell: Vector2i)
signal morning(day: int)
signal sfx(name: String, cell: Vector2i)   ## звуковой эффект для отображения (клетка −1 — без места)

const VERSION := 13
const MAP_W := 48
const MAP_H := 36
## 1.29: зачем нужна каждая зона — отказ, когда игрок стирает её последнюю клетку
const AREA_NEED := {
	1: "Зона разгрузки обязательна: сюда фургоны сгружают металл и ящики с оборудованием, без неё груз некуда класть. Сначала отметьте новую зону, потом стирайте старую.",
	2: "Зона отгрузки обязательна: сюда приносят готовый заказ, и только отсюда грузит машина клиента. Сначала отметьте новую зону, потом стирайте старую.",
}
const LVL_INFO := 0
const LVL_GOOD := 1
const LVL_WARN := 2
const LVL_BAD := 3
const WEEKDAYS := ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

var world := World.new()
var things: Dictionary = {}
var items: Dictionary = {}
var workers: Array[Worker] = []
var vehicles: Array[Vehicle] = []
var orders: OrderBook
var planner: Planner
var brain: Brain
var rooms: Rooms
var power: Power
var prod: Production
var office: Office
var dev: Develop
var bmats: BuildMats      ## 1.13: стройматериалы
var social: Social        ## 1.14: разговоры, ссоры, драки
var season: Season
var story: Story
var inspect: Inspections
var calls: Calls   ## 1.41: телефонные звонки (очередь)
var paper: Paper
var progress: Progress
var logi: Logistics
var water: Water
var grants: Grants
var statlog: StatLog   ## 1.54: дневная история для графиков
var sales: Sales
var training: Training
var career: Careers         ## 1.15: экзамены на разряд, индексация, стаж и пенсия, рацпредложения
var plan: Plan             ## 1.17: план-калька будущего завода
var faults: Faults         ## 1.18: аварии на сетях (обрыв провода, прорыв водопровода)
var upkeep: Upkeep
var eng: Eng
var crew: Crew
var market: Market
var town: Town
var crisis: Crisis   ## 1.20: последствия — зарплата в долг, увольнения, конец игры
var fauna: Fauna     ## 1.22: голуби, мыши
var areas: Areas     ## 1.40: свои зоны у людей, логистика быта (какой цех к какой бытовке и т. д.)
var visitors: Array[Worker] = []
var honor_log: Array = []   ## лучшие работники недели (для «Доски почёта»): [{id, first, last, prof, look, age, day, score, board}]
var traffic := PackedFloat32Array()  ## сколько раз проходили по клетке (оверлей потоков, затухает)  ## гости завода: инспекторы, губернатор, журналист
var cons: Dictionary = {}       ## расходники на складе: код -> единиц
var cons_supply: Array = []     ## заказанные расходники в пути [{cons, packs, eta}]
var area_refusal := ""        ## 1.29: почему не удалось стереть зону (последняя клетка)
var ppr := false                ## планово-предупредительный ремонт: обслуживать станки раньше
var minute := 0.0
var money := 0.0
var reputation := 50.0
var next_id := 1
var rng := RandomNumberGenerator.new()
var slot_items: Dictionary = {}   ## id объекта -> массив слотов -> массив id грузов
var veh_items: Dictionary = {}    ## id фургона -> массив id грузов
var ground_items: Array[int] = []
var ceil_at: Dictionary = {}      ## индекс клетки -> id светильника под потолком
var light := PackedByteArray()    ## освещённость клеток электричеством: 1 — светло от ламп
var bp_cells: Dictionary = {}     ## индекс клетки -> true
var bp_res: Dictionary = {}       ## индекс клетки -> id рабочего
var supply: Array = []            ## заказанный металл в пути
var candidates: Array = []        ## кандидаты на работу (словари Worker)
var customs: Array = []           ## 1.32: свои рабочие этой игры (записи из редактора меню, CustomPeople)
var custom_chance := 0.0          ## 1.32: шанс каждого прийти кандидатом при обновлении кандидатов
var ledger: Array = []
var events: Array = []
var stats: Dictionary = {"made": 0, "scrap": 0, "shipped": 0, "orders_done": 0, "orders_failed": 0, "earned": 0.0, "spent": 0.0}
var once: Dictionary = {}
var thing_rev := 0
var item_rev := 0
var power_kwh_day := 0.0
var gate_x := 22
var scenario := "garage"
var company: Dictionary = {}   ## 1.17: название и эмблема завода (Company)
var company_rev := 0
var bp_progress_at := 0.0       ## когда в последний раз достроили клетку чертежа
var build_priority := false     ## «стройка в приоритете»: все свободные руки — на стройку
var auto_supply := true         ## снабжение автоматическое (металл и расходники докупаются сами)
var supply_reserve := 1         ## запас металла сверх заказов: 0 — нет, 1 — небольшой, 2 — большой


func _init() -> void:
	Defs.load_all()
	orders = OrderBook.new(self)
	planner = Planner.new(self)
	brain = Brain.new(self)
	rooms = Rooms.new(self)
	power = Power.new(self)
	prod = Production.new(self)
	office = Office.new(self)
	dev = Develop.new(self)
	bmats = BuildMats.new(self)
	social = Social.new(self)
	season = Season.new(self)
	story = Story.new(self)
	inspect = Inspections.new(self)
	calls = Calls.new(self)
	paper = Paper.new(self)
	progress = Progress.new(self)
	logi = Logistics.new(self)
	water = Water.new(self)
	grants = Grants.new(self)
	statlog = StatLog.new(self)
	sales = Sales.new(self)
	training = Training.new(self)
	career = Careers.new(self)
	plan = Plan.new(self)
	faults = Faults.new(self)
	upkeep = Upkeep.new(self)
	eng = Eng.new(self)
	crew = Crew.new(self)
	market = Market.new(self)
	town = Town.new(self)
	crisis = Crisis.new(self)
	fauna = Fauna.new(self)
	areas = Areas.new(self)
	for c in Defs.consumables.keys():
		cons[c] = float(Defs.consumables[c].get("start", 0))
	rng.randomize()


# ---------------------------------------------------------------- время

## 1.26: перемешать своим генератором (Array.shuffle() берёт общий, со случайным зерном, — игра с одним зерном шла по-разному).
func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func day() -> int:
	return int(minute / 1440.0) + 1


## 1.44: счётчик тревожных уведомлений (не сохраняется) — по нему «пропуск до смены» понимает, что пора остановиться.
var bad_seq := 0


## 1.44: абсолютная минута начала ближайшей дневной смены (рабочий день), строго после текущей минуты.
func next_shift_start() -> float:
	var d := day()
	for i in 30:
		var dd := d + i
		if is_workday(dd):
			var m := float(dd - 1) * 1440.0 + Defs.b("shift_start")
			if m > minute:
				return m
	return minute + 1440.0


## 1.44: на заводе пусто и смены нет — можно пропустить время.
func can_skip_idle() -> bool:
	if is_work_time() or crisis.is_over():
		return false
	for w in workers:
		if w.present:
			return false
	return true


## 1.44: что прерывает пропуск: пусто — продолжаем. call0/bad0 — значения calls.seq и bad_seq на старте.
func skip_stop_reason(call0: int, bad0: int) -> String:
	if calls.seq != call0:
		return "Звонок"
	if bad_seq != bad0:
		return "Тревога"
	if inspect.busy():
		return "Проверка"
	for w in workers:
		if w.present:
			return "Пришли люди"
	return ""


func tod() -> float:
	return fmod(minute, 1440.0)


func hour() -> int:
	return int(tod() / 60.0)


func weekday(d: int = -1) -> int:
	var dd := day() if d < 0 else d
	return (dd - 1) % 7


func is_workday(d: int = -1) -> bool:
	var dd := day() if d < 0 else d
	return (dd - 1) % 7 < 5 and not (season and season.is_holiday_off(dd))


func weekday_name(d: int = -1) -> String:
	var dd := day() if d < 0 else d
	return WEEKDAYS[(dd - 1) % 7]


func time_str() -> String:
	var t := int(tod())
	return "%02d:%02d" % [int(t / 60), t % 60]


func is_work_time() -> bool:
	var t := tod()
	return is_workday() and t >= Defs.b("shift_start") and t < Defs.b("shift_end")


## Светлое время суток (окна дают свет).
func is_daylight() -> bool:
	var t := tod()
	if season:
		return t >= season.sunrise() + 60.0 and t < season.sunset()
	return t >= 450.0 and t < 1110.0


## Окно смены работника: (начало, конец) в абсолютных минутах — текущая смена
## (с запасом 2 часа на приход) или ближайшая следующая.
func shift_window(w: Worker, m: float = -1.0) -> Vector2:
	if m < 0.0:
		m = minute
	var start_off := Defs.b("shift_start") if w.shift == 0 else Defs.b("shift2_start")
	var ln := Defs.b("shift_len")
	if office and office.overtime_on() and not w.is_itr():
		ln += Defs.b("overtime_min")
	var s := floorf(m / 1440.0) * 1440.0 + start_off
	if m < s - 120.0:
		if m < s - 1440.0 + ln:
			s -= 1440.0
	elif m >= s + ln:
		s += 1440.0
	return Vector2(s, s + ln)


func shift_is_workday(win: Vector2) -> bool:
	return is_workday(int(win.x / 1440.0) + 1)


func date_str() -> String:
	return season.date_str()


## Переносит момент на рабочее время (будни 8:30–16:00).
func to_work_time(t: float) -> float:
	var d := int(t / 1440.0) + 1
	var m := fmod(t, 1440.0)
	var lo := Defs.b("shift_start") + 30.0
	var hi := Defs.b("shift_end") - 60.0
	if is_workday(d) and m >= lo and m <= hi:
		return t
	if m > hi or not is_workday(d):
		d += 1
	while not is_workday(d):
		d += 1
	return (d - 1) * 1440.0 + lo + rng.randf_range(0.0, 50.0)


func new_id() -> int:
	next_id += 1
	return next_id


# ---------------------------------------------------------------- уведомления и деньги

func notify(text: String, level: int = LVL_INFO, cell: Vector2i = Vector2i(-1, -1)) -> void:
	if level >= LVL_BAD:
		bad_seq += 1
	events.push_front({"day": day(), "time": time_str(), "text": text, "level": level})
	if events.size() > 120:
		events.resize(120)
	notified.emit(text, level, cell)


func notify_once(key: String, text: String, level: int = LVL_WARN, cell: Vector2i = Vector2i(-1, -1), cooldown: float = 360.0) -> void:
	if once.has(key) and minute - float(once[key]) < cooldown:
		return
	once[key] = minute
	notify(text, level, cell)


func spend(amount: float, reason: String) -> void:
	if amount == 0.0:
		return
	money -= amount
	stats["spent"] = float(stats["spent"]) + amount
	_ledger(reason, -amount)


func earn(amount: float, reason: String) -> void:
	if amount >= 5000.0 and reason.begins_with("Оплата"):
		sfx.emit("cash", Vector2i(-1, -1))
	if amount == 0.0:
		return
	money += amount
	stats["earned"] = float(stats["earned"]) + amount
	_ledger(reason, amount)


func _ledger(reason: String, v: float) -> void:
	if office:
		office.book(reason, v)
	# одинаковые операции в одну минуту склеиваем: «Стройка: Пол ×24»
	if not ledger.is_empty():
		var top: Dictionary = ledger[0]
		if str(top.get("base", top["text"])) == reason and int(top["day"]) == day() and str(top["time"]) == time_str() and signf(float(top["v"])) == signf(v):
			var n := int(top.get("n", 1)) + 1
			top["n"] = n
			top["base"] = reason
			top["v"] = float(top["v"]) + v
			top["text"] = "%s ×%d" % [L.tx(reason), n]
			return
	# 1.39: причина хранится по-русски (base — по ней статьи и склейка), text — на языке игры
	if L.is_en():
		ledger.push_front({"day": day(), "time": time_str(), "text": L.tx(reason), "base": reason, "v": v})
	else:
		ledger.push_front({"day": day(), "time": time_str(), "text": reason, "v": v})
	if ledger.size() > 300:
		ledger.resize(300)


func can_afford(a: float) -> bool:
	return money >= a


# ---------------------------------------------------------------- рабочие

## Сотрудник или гость завода по id.
func get_person(id: int) -> Worker:
	var w := get_worker(id)
	if w:
		return w
	for v in visitors:
		if v.id == id:
			return v
	return null


## 1.23: поиск по id через словарь (раньше — перебор всех людей; звался сотни раз за ход).
## Словарь пересобирается, когда меняется число людей или worker_rev (увольнение, уход).
var worker_rev := 0
var _widx: Dictionary = {}
var _widx_sig := Vector2i(-1, -1)


func get_worker(id: int) -> Worker:
	var sig := Vector2i(workers.size(), worker_rev)
	if sig != _widx_sig:
		_widx_sig = sig
		_widx.clear()
		for w in workers:
			_widx[w.id] = w
	var f: Variant = _widx.get(id)
	if f != null and (f as Worker).id == id:
		return f
	return null


func add_worker(w: Worker) -> void:
	w.id = new_id()
	w.hired_day = day()
	w.exit_cell = Vector2i(0, world.sidewalk_row) if rng.randf() < 0.5 else Vector2i(world.w - 1, world.sidewalk_row)
	w.arrive_at = Defs.b("shift_start") - rng.randf_range(10.0, 45.0)
	workers.append(w)
	if w.grade_n <= 0 and w.has_grade():
		w.grade_n = w.pot_grade()   # 1.15: разряд закрепляется при приёме, дальше — через экзамен
	Nicks.on_hire(self, w)
	Mood.refresh(self, w)


func refresh_candidates(only_prof: String = "") -> void:
	# 1.52: мастер из газетного объявления ждёт на собеседование, пока объявление не устарело
	var keep: Array = candidates.filter(func(c: Dictionary) -> bool: return int(c.get("ad_until", 0)) >= day())
	candidates.clear()
	candidates.append_array(keep)
	var profs: Array = ["turner", "laborer", "qc", "turner", "builder", "electrician", "laborer"]
	# под имеющееся оборудование чаще приходят нужные специальности
	for pr in prod.processes_available().keys():
		var pf := str(Defs.processes.get(pr, {}).get("prof", ""))
		if pf != "" and pf != "turner":
			profs.append(pf)
			profs.append(pf)
	profs.append("cleaner")
	if not things.values().filter(func(t: Thing) -> bool: return t.def_id == "workbench" and t.built).is_empty():
		profs.append("fitter")   # 1.15: есть слесарный верстак — приходят слесари
	if things_of("machine").size() >= 3:
		profs.append("setter")
	# 1.22: есть станки с ЧПУ — приходят операторы ЧПУ
	if things_of("machine").any(func(m: Thing) -> bool: return m.is_cnc()):
		profs.append("cnc_operator")
		profs.append("cnc_operator")
	if story.has_checkpoint() or workers.size() >= 10:
		profs.append("guard")
	if town.kitchen() and town.cooks().is_empty():
		profs.append("cook")
		profs.append("cook")
	if not town.medbays().is_empty() and town.nurses().is_empty():
		profs.append("nurse")
		profs.append("nurse")
	if randi_profs_extra():
		profs.append(["miller", "welder", "assembler"][rng.randi_range(0, 2)])
	for i in range(profs.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = profs[i]
		profs[i] = profs[j]
		profs[j] = tmp
	var n := office.candidates_n()
	if only_prof != "":
		profs = [only_prof]   # 1.19: объявление по профессии — все кандидаты этой профессии
	for i in n + town.extra_candidates():
		var w := People.make(rng, str(profs[i % profs.size()]))
		candidates.append(w.to_dict())
	# иногородние — если в общежитии есть свободные койки
	if only_prof == "":
		for j in town.away_candidates():
			var wa := People.make(rng, str(profs[(j * 3 + 1) % profs.size()]))
			wa.from_away = true
			wa.wage = int(round(wa.wage * 0.92 / 50.0) * 50.0)
			candidates.append(wa.to_dict())
	if not customs.is_empty():
		CustomPeople.roll(self, profs, only_prof)   # 1.32: может прийти и свой рабочий


func randi_profs_extra() -> bool:
	return rng.randf() < 0.35


## Цена объявления: с профессией дороже (три из четырёх кандидатов будут нужной профессии).
func ad_price(prof: String = "") -> float:
	return round(Defs.b("ad_cost") * (Defs.b("ad_prof_k") if prof != "" else 1.0) * office.ad_cost_k() / 100.0) * 100.0


## Объявление о вакансии: новые кандидаты сразу, за деньги. С профессией — дороже, но точнее.
func post_ad(prof: String = "") -> String:
	var cost := ad_price(prof)
	if not can_afford(cost):
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(cost)
	spend(cost, "Объявление о вакансиях" + ((": " + str(Worker.PROF_NAMES.get(prof, prof))) if prof != "" else ""))
	refresh_candidates(prof)
	notify(L.t("Объявление размещено: пришли новые кандидаты."), LVL_INFO)
	return ""


func hire(index: int) -> String:
	if index < 0 or index >= candidates.size():
		return L.t("Нет такого кандидата")
	var w := Worker.from_dict(candidates[index])
	var terr := town.can_hire(w)
	if terr != "":
		return terr
	w.present = false
	w.ppe = 0.0   # новичку СИЗ выдают со склада (шкаф СИЗ)
	add_worker(w)
	candidates.remove_at(index)
	w.add_history(day(), (L.t("Принята на работу: %s%s") if w.female else L.t("Принят на работу: %s%s")) % [w.prof_name(), (L.t(" (иногородняя, живёт в общежитии)") if w.female else L.t(" (иногородний, живёт в общежитии)")) if w.from_away else ""])
	town.on_hired(w)
	paper.on_hire(w)
	var when := L.t("к началу следующей смены")
	var win := shift_window(w)
	if shift_is_workday(win) and minute >= win.x - 60.0 and minute < win.y - 120.0:
		w.shift_anchor = win.x
		w.arrive_off = maxf(minute - win.x, -60.0) + rng.randf_range(30.0, 60.0)
		when = L.t("в течение часа")
	notify(Nicks.gendered(L.t("%s принят{|а} на работу, выйдет %s."), w.female) % [w.full_name(), when], LVL_GOOD)
	return ""


func fire(w: Worker, quit: bool = false, calm: bool = false) -> void:
	if w.is_director():
		return   # 1.40: директор — это игрок: его не увольняют, сам он не уходит
	brain.abort(w)
	office.on_quit(w)
	training.on_leave(w)
	career.on_leave(w)
	crew.on_fire(w, quit)
	crew.on_leave(w)
	var owed := float(w.get_meta("wage_due", 0.0))
	if owed > 0.0:
		spend(owed, "Расчёт при увольнении: " + w.full_name())
	workers.erase(w)
	worker_rev += 1
	paper.on_fire(w, quit)
	if not quit:
		stats["fired_week"] = int(stats.get("fired_week", 0)) + 1
	town.assign_beds()
	if quit:
		notify(Nicks.gendered(L.t("%s уволил{ся|ась} по собственному желанию: «Достало всё». Следите за настроением людей."), w.female) % w.full_name(), LVL_BAD)
	else:
		notify(Nicks.gendered(L.t("%s уволен{|а}."), w.female) % w.full_name(), LVL_WARN)
	if not calm:
		for o in workers:
			Mood.add(self, o, "coworker_fired")


## Изменить ставку на долю (0.1 = +10%).
func change_wage(w: Worker, pct: float) -> void:
	if w.is_director():
		return   # 1.40: у директора нет оклада
	var nw := int(round(w.wage * (1.0 + pct) / 50.0) * 50.0)
	nw = maxi(1000, nw)
	if nw == w.wage:
		return
	Mood.add(self, w, "raise" if nw > w.wage else "wage_cut")
	w.add_history(day(), L.t("Ставка изменена: %s → %s") % [Defs.money_str(w.wage), Defs.money_str(nw)])
	w.wage = nw
	Mood.refresh(self, w)


## Премия всему коллективу разом.
func bonus_all() -> String:
	if workers.is_empty():
		return L.t("Некому выдавать")
	var amount := Defs.b("bonus_amount") * workers.size()
	if not can_afford(amount):
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(amount)
	spend(amount, "Премия всем: %d чел." % workers.size())
	for w in workers:
		Mood.add(self, w, "bonus")
		Nicks.count(w, "bonus")
		w.add_history(day(), Nicks.gendered(L.t("Получил{|а} премию вместе со всеми"), w.female))
		Mood.refresh(self, w)
	notify(L.t("Премия всему коллективу: %s. Люди довольны.") % Defs.money_str(amount), LVL_GOOD)
	return ""


## Поднять ставки всем на pct (0.05 = +5%).
func raise_all(pct: float) -> void:
	for w in workers:
		change_wage(w, pct)
	notify(L.t("Ставки всем подняты на %d%%.") % int(round(pct * 100.0)), LVL_GOOD)


## Подтянуть ставки тех, кто получает ниже рынка. Возвращает, скольким подняли.
func wages_to_market() -> int:
	var n := 0
	for w in workers:
		var mw := Mood.market_wage(w)
		if w.wage < int(mw * 0.97):
			change_wage(w, float(mw) / float(w.wage) - 1.0)
			n += 1
	if n > 0:
		notify(L.t("Ставки подтянуты до рыночных: %d %s.") % [n, Defs.plural(n, "человек", "человека", "человек")], LVL_GOOD)
	return n


func give_bonus(w: Worker) -> String:
	var amount := Defs.b("bonus_amount")
	if not can_afford(amount):
		return L.t("Не хватает денег")
	spend(amount, "Премия: " + w.full_name())
	Mood.add(self, w, "bonus")
	Nicks.count(w, "bonus")
	w.add_history(day(), Nicks.gendered(L.t("Получил{|а} премию %s"), w.female) % Defs.money_str(amount))
	Mood.refresh(self, w)
	notify(Nicks.gendered(L.t("%s получил{|а} премию. Настроение — на высоте."), w.female) % w.full_name(), LVL_GOOD)
	return ""


## Перевод в другую смену. Если человек на работе — со следующей смены.
func set_shift(w: Worker, sh: int) -> void:
	if sh == w.shift and w.pending_shift < 0:
		return
	if w.present:
		w.pending_shift = sh
		notify(L.t("%s перейдёт в %s после этой смены.") % [w.full_name(), L.t("1-ю смену") if sh == 0 else L.t("2-ю смену")], LVL_INFO)
	else:
		w.shift = sh
		w.pending_shift = -1
		w.shift_anchor = -1.0
		Mood.refresh(self, w)


# ---------------------------------------------------------------- электрика

## 1.13: сети прокладывают рабочие. Щелчок кладёт чертёж (2), деньги — сразу;
## клетку прокладывают по одной (электрик — кабель, строитель или разнорабочий — остальное).
## instant — сразу проложить (сценарии, тесты, снимки).
const NET_NAMES := {"cable": "Электромонтаж: кабель", "pipe": "Сантехника: труба", "duct": "Вентиляция: воздуховод", "air": "Пневмомагистраль"}
const NET_COST_KEY := {"cable": "cable_cost", "pipe": "pipe_cost", "duct": "duct_cost", "air": "air_cost"}
var net_res: Dictionary = {}     ## "слой:индекс клетки" -> id рабочего, который тянет туда сеть


func net_cost(layer: String) -> float:
	return Defs.b(str(NET_COST_KEY.get(layer, "cable_cost")))


func place_net(layer: String, c: Vector2i, instant: bool = false) -> bool:
	if not world.in_plot(c) or world.net_at(layer, c) != 0:
		return false
	var cost := net_cost(layer)
	if not can_afford(cost):
		return false
	world.net_set(layer, world.idx(c), 1 if instant else 2)
	spend(cost, str(NET_NAMES.get(layer, "Сети")))
	return true


func place_cable(c: Vector2i, instant: bool = false) -> bool:
	return place_net("cable", c, instant)


func place_pipe(c: Vector2i, instant: bool = false) -> bool:
	return place_net("pipe", c, instant)


## Воздуховод вентиляции или пневмомагистраль: layer = "duct" | "air".
func place_line(layer: String, c: Vector2i, instant: bool = false) -> bool:
	return place_net(layer, c, instant)


## Убрать сеть из клетки: чертёж — отмена с полным возвратом, проложенную — демонтаж (30%).
func remove_net(layer: String, c: Vector2i) -> bool:
	var v := world.net_at(layer, c)
	if v == 0:
		return false
	var i := world.idx(c)
	world.net_set(layer, i, 0)
	if v == 2:
		var key := "%s:%d" % [layer, i]
		if net_res.has(key):
			var wk := get_worker(int(net_res[key]))
			net_res.erase(key)
			if wk:
				brain.abort(wk)
		if faults.list.has(key):
			faults.list.erase(key)   # оборванный кусок просто убрали — денег не возвращаем
			faults.rev += 1
		else:
			earn(net_cost(layer), "Отмена чертежа сети")
		return true
	earn(net_cost(layer) * 0.3, "Демонтаж: " + str(NET_NAMES.get(layer, "сеть")).get_slice(": ", 1))
	return true


func remove_line(layer: String, c: Vector2i) -> bool:
	return remove_net(layer, c)


func remove_pipe(c: Vector2i) -> bool:
	return remove_net("pipe", c)


func remove_cable(c: Vector2i) -> bool:
	return remove_net("cable", c)


## Чертежи сетей: [[слой, индекс клетки]] (для работы и подсказок).
var _plans_sig := ""
var _plans: Array = []


func net_plans() -> Array:
	var sig := "%d|%d|%d|%d" % [world.cable_rev, world.pipe_rev, world.duct_rev, world.air_rev]
	if sig == _plans_sig:
		return _plans
	_plans_sig = sig
	var out: Array = []
	var n := world.w * world.h
	for layer: String in ["cable", "pipe", "duct", "air"]:
		var arr := world.net_layer(layer)
		if arr.size() != n:
			continue
		for i in n:
			if arr[i] == 2:
				out.append([layer, i])
	_plans = out
	return out


func net_plan_count() -> int:
	return net_plans().size()


## Проложить клетку сети (рабочий закончил).
func complete_net(layer: String, i: int) -> void:
	if world.net_layer(layer)[i] != 2:
		return
	world.net_set(layer, i, 1)
	net_res.erase("%s:%d" % [layer, i])
	bp_progress_at = minute


# ---------------------------------------------------------------- грузы

func new_item(kind: String, def_id: String, q: String) -> Item:
	var it := Item.new()
	it.id = new_id()
	it.kind = kind
	it.def_id = def_id
	it.q = q
	it.loc = Item.Loc.GROUND
	it.holder = -2  # ещё нигде
	items[it.id] = it
	return it


func _detach(it: Item) -> void:
	match it.loc:
		Item.Loc.THING:
			if slot_items.has(it.holder):
				var slots: Array = slot_items[it.holder]
				if it.slot < slots.size():
					(slots[it.slot] as Array).erase(it.id)
		Item.Loc.GROUND:
			ground_items.erase(it.id)
		Item.Loc.VEHICLE:
			if veh_items.has(it.holder):
				(veh_items[it.holder] as Array).erase(it.id)
		Item.Loc.WORKER:
			var w := get_worker(it.holder)
			if w:
				if w.carrying == it.id:
					w.carrying = -1
				else:
					w.carry_extra.erase(it.id)
	item_rev += 1


func put_in_thing(it: Item, t: Thing, s: int) -> void:
	_detach(it)
	it.loc = Item.Loc.THING
	it.holder = t.id
	it.slot = s
	(_slots(t)[s] as Array).append(it.id)
	item_rev += 1


func put_on_ground(it: Item, c: Vector2i) -> void:
	_detach(it)
	it.loc = Item.Loc.GROUND
	it.holder = -1
	it.cell = c
	ground_items.append(it.id)
	item_rev += 1


func give_worker(it: Item, w: Worker, extra: bool = false) -> void:
	_detach(it)
	it.loc = Item.Loc.WORKER
	it.holder = w.id
	if extra:
		w.carry_extra.append(it.id)
	else:
		w.carrying = it.id
	item_rev += 1


func put_in_vehicle(it: Item, v: Vehicle) -> void:
	_detach(it)
	it.loc = Item.Loc.VEHICLE
	it.holder = v.id
	if not veh_items.has(v.id):
		veh_items[v.id] = []
	(veh_items[v.id] as Array).append(it.id)
	item_rev += 1


func delete_item(it: Item) -> void:
	_detach(it)
	items.erase(it.id)
	item_rev += 1


func _slots(t: Thing) -> Array:
	if not slot_items.has(t.id) or (slot_items[t.id] as Array).size() != t.slot_count():
		var arr: Array = []
		for i in t.slot_count():
			arr.append([])
		slot_items[t.id] = arr
	return slot_items[t.id]


func slot_ids(t: Thing, s: int) -> Array:
	var sl := _slots(t)
	if s < 0 or s >= sl.size():
		return []
	return sl[s]


func count_slot(t: Thing, s: int) -> int:
	return slot_ids(t, s).size()


func slot_key(t: Thing, s: int) -> String:
	var ids := slot_ids(t, s)
	if ids.is_empty():
		return ""
	var it: Item = items.get(ids[0])
	return it.stack_key() if it else ""


func free_space(t: Thing, s: int, key: String) -> int:
	t.ensure_incoming()
	var cnt := count_slot(t, s)
	# смешивать разные грузы нельзя только во входном лотке станка (кроме сборки — там комплект)
	if t.kind() == "machine" and s == 0 and not (t.job_step == 0 and Defs.is_assembly(t.product)):
		var cur := slot_key(t, s)
		if cnt > 0 and cur != key:
			return 0
		if cnt == 0 and int(t.incoming[s]) > 0 and str(t.incoming_key[s]) != key:
			return 0
	return t.slot_cap(s) - cnt - int(t.incoming[s])


func reserve_incoming(t: Thing, s: int, key: String) -> void:
	t.ensure_incoming()
	t.incoming[s] = int(t.incoming[s]) + 1
	t.incoming_key[s] = key


func release_incoming(t: Thing, s: int) -> void:
	t.ensure_incoming()
	t.incoming[s] = maxi(0, int(t.incoming[s]) - 1)
	if int(t.incoming[s]) == 0:
		t.incoming_key[s] = ""


## Ближайший склад, куда можно положить груз. Возвращает [Thing, слот] или [].
func find_storage(it: Item, near: Vector2i, skip_def: String = "") -> Array:
	var cat := it.cat()
	var key := it.stack_key()
	var best: Array = []
	var best_d := INF
	# 1.38.2: только склады (готовый список по виду, в том же порядке) — раньше перебор всех объектов завода на
	# каждый груз на полу: при сотне грузов поиск работы у каждого свободного рабочего стоил десятки мс
	for t: Thing in things_of("storage", false):
		if not t.built or t.demolish or not t.is_storage() or t.def_id == skip_def:
			continue
		for s in t.slot_count():
			if not t.slot_accepts(s, cat):
				continue
			if free_space(t, s, key) <= 0:
				continue
			var d := Vector2(t.cell - near).length()
			if slot_key(t, s) == key:
				d -= 4.0
			if rooms.thing_in(t, "storage"):
				d -= 6.0
			if t.def_id == Logistics.RAW_PALLET:
				d += 8.0   # 1.29: поддоны заготовок — для разгрузки фургона, хранить лучше на стеллажах
			if d < best_d:
				best_d = d
				best = [t, s]
	return best


func item_cell(it: Item) -> Vector2i:
	match it.loc:
		Item.Loc.GROUND:
			return it.cell
		Item.Loc.THING:
			var t: Thing = things.get(it.holder)
			return t.cell if t else Vector2i.ZERO
		Item.Loc.VEHICLE:
			var v := get_vehicle(it.holder)
			return v.access_cell(world.sidewalk_row) if v else Vector2i.ZERO
		Item.Loc.WORKER:
			var w := get_worker(it.holder)
			return w.cell() if w else Vector2i.ZERO
	return Vector2i.ZERO


## Свободный металл на складах/земле (не зарезервированный).
func free_material(mat: String) -> int:
	var n := 0
	for it: Item in items.values():
		if it.kind != "mat" or it.def_id != mat or it.reserved_by >= 0:
			continue
		if it.loc == Item.Loc.GROUND:
			n += 1
		elif it.loc == Item.Loc.THING:
			var t: Thing = things.get(it.holder)
			if t and t.is_storage():
				n += 1
	return n


func material_total(mat: String) -> int:
	var n := 0
	for it: Item in items.values():
		if it.kind == "mat" and it.def_id == mat:
			n += 1
	for s: Dictionary in supply:
		if str(s.get("mat", "")) == mat and not bool(s.get("done", false)):
			n += int(s["qty"])
	return n


# ---------------------------------------------------------------- расходники

func order_cons(c: String, packs: int) -> String:
	var cd: Dictionary = Defs.consumables.get(c, {})
	if cd.is_empty() or packs <= 0:
		return L.t("Нечего заказывать")
	var cost := float(cd["price"]) * packs
	if not can_afford(cost):
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(cost)
	spend(cost, "Расходники: %s × %d" % [str(cd["name"]), packs])
	var eta := to_work_time(minute + rng.randf_range(60.0, 150.0))
	cons_supply.append({"cons": c, "packs": packs, "eta": eta})
	notify(L.t("Заказано: %s × %d. Курьер привезёт %s.") % [L.dt("consumable.%s.pack" % c, str(cd["pack"])), packs, _eta_str(eta)], LVL_INFO)
	return ""


func cons_on_way(c: String) -> bool:
	for s: Dictionary in cons_supply:
		if str(s["cons"]) == c:
			return true
	return false


func use_cons(c: String, units: float) -> void:
	if c == "":
		return
	cons[c] = maxf(0.0, float(cons.get(c, 0.0)) - units)


func _tick_cons_supply() -> void:
	for i in range(cons_supply.size() - 1, -1, -1):
		var s: Dictionary = cons_supply[i]
		if minute >= float(s["eta"]):
			var c := str(s["cons"])
			var cd: Dictionary = Defs.consumables.get(c, {})
			cons[c] = float(cons.get(c, 0.0)) + float(cd.get("units", 0)) * int(s["packs"])
			notify(L.t("Привезли расходники: %s.") % L.dt("consumable.%s.name" % c, str(cd.get("name", c))), LVL_INFO)
			cons_supply.remove_at(i)


# ---------------------------------------------------------------- станки: печь, поломки

## Приход минус расход за сегодня (по журналу операций).
func today_net() -> float:
	var t := 0.0
	for e: Dictionary in ledger:
		if int(e["day"]) != day():
			break
		t += float(e["v"])
	return t


## Порог обслуживания станков: обычный или по ППР.
func service_at() -> float:
	return Defs.b("ppr_at") if ppr or office.active("engineer") else Brain.SERVICE_AT   # главный инженер ведёт ППР сам


## Печи работают без присмотра: партия греется, потом детали переходят на следующую операцию.
func _tick_machines(dt: float) -> void:
	# загрузка станков (для оверлея): только в рабочее время
	if is_work_time():
		var k := minf(1.0, dt / 240.0)
		for m0 in things_of("machine"):
			m0.util += ((1.0 if m0.working else 0.0) - m0.util) * k
	for m in things_of("machine"):
		if not m.is_batch() or not m.working:
			continue
		if not power.powered(m) or m.broken:
			continue
		var o := Defs.op(m.product, m.job_step)
		var dur := float(o.get("time", 120)) * float(m.machine_def().get("speed_k", 1.0))   # 1.16: ТВЧ и малые печи быстрее
		m.batch_t += dt / maxf(1.0, dur)
		m.progress = clampf(m.batch_t, 0.0, 1.0)
		m.condition = maxf(0.0, m.condition - Defs.b("machine_wear_per_min") * 0.3 * dt)
		if m.batch_t >= 1.0:
			_finish_batch(m)


func _finish_batch(m: Thing) -> void:
	var ids := slot_ids(m, 0).duplicate()
	var last := m.job_step + 1 >= Defs.route(m.product).size()
	for iid in ids:
		var it: Item = items.get(iid)
		if it == null:
			continue
		it.step = m.job_step + 1
		it.q = "machined" if last else "wip"
		if rng.randf() < 0.02:
			it.defect = true
		put_in_thing(it, m, 1)
	m.working = false
	m.batch_t = 0.0
	m.progress = 0.0
	m.parts_made += ids.size()
	item_rev += 1
	notify(L.t("%s: партия «%s» × %d готова.") % [m.title(), Defs.product_name(m.product), ids.size()], LVL_INFO, m.cell)


## Износ: ниже порога станок может сломаться на операции.
func roll_breakdown(m: Thing) -> void:
	var lim := Defs.b("breakdown_below")
	if m.condition >= lim:
		return
	var p := Defs.b("breakdown_chance") * (1.0 - m.condition / lim) * 2.0
	if rng.randf() < p:
		m.broken = true
		m.working = false
		sfx.emit("breakdown", m.cell)
		calls.on_breakdown(m.title())
		notify(L.t("%s сломался! Нужен ремонт (%s на запчасти). Чтобы станки не ломались, обслуживайте их вовремя — включите ППР в «Производство → Станки».") % [m.title(), Defs.money_str(Defs.b("repair_cost"))], LVL_BAD, m.cell)


## Готовые детали на складах и на полу (их можно отгружать).
func ok_in_storage(product: String) -> int:
	var n := 0
	for it: Item in items.values():
		if it.kind != "part" or it.def_id != product or it.q != "ok":
			continue
		if it.loc == Item.Loc.GROUND:
			n += 1
		elif it.loc == Item.Loc.THING:
			var t: Thing = things.get(it.holder)
			if t and t.is_storage():
				n += 1
	return n


# ---------------------------------------------------------------- объекты

func get_thing(id: int) -> Thing:
	return things.get(id)


func thing_at(c: Vector2i) -> Thing:
	if not world.inb(c):
		return null
	var id := world.occ[world.idx(c)]
	if id < 0:
		id = int(ceil_at.get(world.idx(c), -1))
	return things.get(id) if id >= 0 else null


## Светильник под потолком в клетке (или null).
func ceiling_at(c: Vector2i) -> Thing:
	if not world.inb(c):
		return null
	return things.get(int(ceil_at.get(world.idx(c), -1)))


## 1.23: списки по видам запоминаются до изменения объектов (thing_rev, число объектов) —
## раньше каждый вызов перебирал все объекты, а зовут его сотни раз за ход.
var _tof: Dictionary = {}
var _tof_sig := Vector2i(-1, -1)


func things_of(kind: String, only_built: bool = true) -> Array[Thing]:
	var sig := Vector2i(thing_rev, things.size())
	if sig != _tof_sig:
		_tof_sig = sig
		_tof.clear()
	var key := kind + ("|b" if only_built else "|a")
	var c: Variant = _tof.get(key)
	if c == null:
		var out: Array[Thing] = []
		for t: Thing in things.values():
			if t.kind() == kind and (t.built or not only_built):
				out.append(t)
		_tof[key] = out
		c = out
	return (c as Array[Thing]).duplicate()


## Построенные объекты, которыми можно пользоваться: стоят в своей зоне (1.13).
func usable_of(kind: String) -> Array[Thing]:
	# 1.26: из готового списка по виду и раз за шаг (раньше — перебор всех объектов на каждый вызов)
	if _uo_min != minute or _uo_rev != thing_rev:
		_uo_min = minute
		_uo_rev = thing_rev
		_uo.clear()
	var c: Variant = _uo.get(kind)
	if c == null:
		var out: Array[Thing] = []
		for t: Thing in things_of(kind):
			if rooms.zone_ok(t):
				out.append(t)
		_uo[kind] = out
		c = out
	return (c as Array[Thing]).duplicate()


var _uo := {}
var _uo_min := -1.0
var _uo_rev := -1


func can_place(def_id: String, c: Vector2i, rot: int = 0, ignore_id: int = -1) -> String:
	var err := _can_place_base(def_id, c, rot, ignore_id)
	if err == "" and ignore_id < 0 and _seals_passage(def_id, c, rot):
		return L.t("Перекроет единственный проход: оставьте людям обход вокруг")
	return err


## 1.47: высокий объект не должен отрезать людям путь: клетки вокруг, которые были связаны, остаются связаны.
func _seals_passage(def_id: String, c: Vector2i, rot: int) -> bool:
	var d: Dictionary = Defs.objects.get(def_id, {})
	if not bool(d.get("blocks", true)) or bool(d.get("low", false)) or bool(d.get("ceiling", false)) or str(d.get("kind", "")) == "checkpoint":
		return false
	var bs: Array = d.get("size", [1, 1])
	var sz := Thing.rot_size(Vector2i(int(bs[0]), int(bs[1])), rot)
	var foot := {}
	for y in sz.y:
		for x in sz.x:
			foot[c + Vector2i(x, y)] = true
	var ring: Array[Vector2i] = []
	for fc: Vector2i in foot.keys():
		for dd: Vector2i in Rooms.DIRS:
			var nb := fc + dd
			if not foot.has(nb) and world.passable(nb) and not ring.has(nb):
				ring.append(nb)
	if ring.size() < 2:
		return false
	var with := _flood(ring[0], foot, ring)
	if with.size() == ring.size():
		return false
	var without := _flood(ring[0], {}, ring)
	if without.size() <= with.size():
		return false
	# тупичок в пару клеток — не беда; перекрывать проход между большими частями нельзя
	if _comp_size(ring[0], foot, 6) < 6:
		return false
	for r in ring:
		if not with.has(r) and _comp_size(r, foot, 6) >= 6:
			return true
	return false


func _comp_size(start: Vector2i, banned: Dictionary, cap: int) -> int:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and seen.size() < cap:
		var cur: Vector2i = queue[head]
		head += 1
		for dd: Vector2i in Rooms.DIRS:
			var nb := cur + dd
			if seen.has(nb) or banned.has(nb) or not world.passable(nb):
				continue
			seen[nb] = true
			queue.append(nb)
	return seen.size()


## Какие клетки из targets достижимы от start (обход по проходимым, без клеток из banned); поиск ограничен.
func _flood(start: Vector2i, banned: Dictionary, targets: Array[Vector2i]) -> Array[Vector2i]:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var found: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and seen.size() < 6000:
		var cur: Vector2i = queue[head]
		head += 1
		for dd: Vector2i in Rooms.DIRS:
			var nb := cur + dd
			if seen.has(nb) or banned.has(nb) or not world.passable(nb):
				continue
			seen[nb] = true
			queue.append(nb)
			if targets.has(nb):
				found.append(nb)
				if found.size() == targets.size():
					return found
	if seen.size() >= 6000:
		return targets.duplicate()   # огромное открытое место — не перекроем
	return found


func _can_place_base(def_id: String, c: Vector2i, rot: int = 0, ignore_id: int = -1) -> String:
	var d: Dictionary = Defs.objects.get(def_id, {})
	if d.is_empty():
		return L.t("Неизвестный объект")
	var lock := progress.locked_reason(def_id)
	if lock != "":
		return lock
	var bs: Array = d.get("size", [1, 1])
	var s := Thing.rot_size(Vector2i(int(bs[0]), int(bs[1])), rot)
	if bool(d.get("span", false)):
		# кран-балка: в помещении, от стены до стены, одна на помещение
		if not world.in_plot(c):
			return L.t("Только внутри участка")
		var r := rooms.room_at(c)
		if r == null:
			return L.t("Кран-балку ставят в помещении: щёлкните внутри цеха")
		if r.srect.size.x > 26:
			return L.t("Пролёт %d клеток — для кран-балки слишком широко (до 26)") % r.srect.size.x
		for o: Thing in things.values():
			if o.id != ignore_id and o.def().get("span", false) and rooms.space_id_at(o.cell) == r.space:
				return L.t("В этом помещении уже есть кран-балка")
		if ceil_at.has(world.idx(c)) and int(ceil_at[world.idx(c)]) != ignore_id:
			return L.t("Здесь висит светильник")
		return ""
	if bool(d.get("ceiling", false)):
		if not world.in_plot(c):
			return L.t("Только внутри участка")
		var ci := world.idx(c)
		if Defs.wall_solid(world.wall[ci]) or world.bp_wall[ci] != World.BP_NONE:
			return L.t("Мешает стена")
		if ceil_at.has(ci) and int(ceil_at[ci]) != ignore_id:
			return L.t("Здесь под потолком уже что-то висит")
		return ""
	var on_fence := str(d.get("kind", "")) == "checkpoint" and fence_fit(c, s, ignore_id)   # 1.30: проходная — прямо в заборе
	for y in s.y:
		for x in s.x:
			var cc := c + Vector2i(x, y)
			if not on_fence and not world.in_plot(cc):
				return L.t("Только внутри участка")
			var i := world.idx(cc)
			if not on_fence and (world.wall[i] != World.W_NONE or world.bp_wall[i] != World.BP_NONE):
				return L.t("Мешает стена")
			if world.occ[i] >= 0 and world.occ[i] != ignore_id:
				return L.t("Место занято")
			if world.flora[i] != 0:
				return L.t("Мешает %s — спилите его (Снос)") % World.flora_name(world.flora[i])
			if bool(d.get("needs_floor", false)) and world.flr[i] == 0 and (world.bp_floor[i] == World.BP_NONE or world.bp_floor[i] == 0):
				return L.t("Нужен пол (только в помещении)")
			if bool(d.get("blocks", true)):
				for gid in ground_items:
					var gi: Item = items.get(gid)
					if gi and gi.cell == cc:
						return L.t("Мешают грузы на полу")
	# 1.20: насосная одна на завод — тянет все приборы
	if str(d.get("kind", "")) == "pump":
		for o: Thing in things.values():
			if o.id != ignore_id and o.kind() == "pump" and not o.demolish:
				return L.t("Насосная уже есть — одна даёт воду всему заводу")
	# 1.20: электрокотёл — вплотную к насосной
	if str(d.get("kind", "")) == "heater":
		var near := false
		for o: Thing in things.values():
			if o.kind() == "pump" and o.rect().grow(1).intersects(Rect2i(c, s)):
				near = true
				break
		if not near:
			return L.t("Электрокотёл ставят рядом с насосной станцией — не дальше одной клетки")
	if str(d.get("kind", "")) == "battery":
		# аккумуляторный шкаф — вплотную к подстанции, не больше девяти у одной (1.13)
		var host: Thing = null
		for o: Thing in things.values():
			if Power.boostable(o) and o.rect().grow(1).has_point(c):
				host = o
				break
		if host == null:
			return L.t("Аккумулятор ставят вплотную к подстанции — в пределах одной клетки, можно по углам")
		var nb := 0
		for b in power.batteries_of(host):
			if b.id != ignore_id:
				nb += 1
		if nb >= Power.BATT_MAX:
			return L.t("У подстанции уже %d аккумуляторов — больше не поместится") % Power.BATT_MAX
	return ""


## 1.30: проходная встаёт в наружный забор участка: все клетки — забор (или уже её проём),
## с одной стороны — свой участок. Ворота для машин не трогаем.
func fence_fit(c: Vector2i, s: Vector2i, ignore_id: int = -1) -> bool:
	if s.x > 1 and s.y > 1:
		return false
	for y in s.y:
		for x in s.x:
			var cc := c + Vector2i(x, y)
			if not world.inb(cc) or world.in_plot(cc):
				return false
			var i := world.idx(cc)
			var v := world.wall[i]
			if not ((v == World.W_FENCE and world.bp_wall[i] == World.BP_NONE) or (v == World.W_NONE and ignore_id >= 0 and world.occ[i] == ignore_id)):
				return false
			var side := [Vector2i(0, -1), Vector2i(0, 1)] if s.y == 1 else [Vector2i(-1, 0), Vector2i(1, 0)]
			if not (world.in_plot(cc + side[0]) or world.in_plot(cc + side[1])):
				return false
	return true


## 1.30: проходная из старого сохранения была 2×1 — теперь 4×1 (будка и два турникета). Если новые
## клетка занята, сдвигаем её на ближайшее свободное место рядом; некуда — разбираем с полным возвратом.
func _fit_old_checkpoint(t: Thing) -> void:
	var in_fence := true   # уже стоит в заборе (проём открыт): клетки ещё не помечены — проверяем сами
	for cc in t.cells():
		if not world.inb(cc) or world.in_plot(cc) or not (world.wall[world.idx(cc)] == World.W_NONE or world.wall[world.idx(cc)] == World.W_FENCE) \
				or (world.occ[world.idx(cc)] >= 0 and world.occ[world.idx(cc)] != t.id):
			in_fence = false
	if in_fence:
		return
	var all := progress.all_open
	progress.all_open = true
	if can_place(t.def_id, t.cell, t.rot, t.id) == "" or fence_fit(t.cell, t.size(), t.id):
		progress.all_open = all
		return
	var found := Vector2i(-1, -1)
	for r in range(0, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if found.x >= 0 or (absi(dx) != r and absi(dy) != r):
					continue
				var c := t.cell + Vector2i(dx, dy)
				if can_place(t.def_id, c, t.rot, t.id) == "":
					found = c
	progress.all_open = all
	if found.x >= 0:
		t.cell = found
		return
	things.erase(t.id)
	if t.built:
		earn(t.cost_paid if t.cost_paid > 0.0 else thing_cost(t.def_id), "Возврат: " + t.title_ru())
	notify(L.t("Проходная стала шире (будка и два турникета) и не поместилась на старом месте — её разобрали, деньги вернули. Поставьте новую у въезда."), LVL_WARN)


## 1.30: собранная проходная в заборе — забор под ней убираем (проём с турникетами).
func _open_fence(t: Thing) -> void:
	if t.kind() != "checkpoint":
		return
	for cc in t.cells():
		var i := world.idx(cc)
		if not world.in_plot(cc) and world.wall[i] == World.W_FENCE:
			world.wall[i] = World.W_NONE
			world.refresh_cell(cc)


## 1.30: проходную снесли — заделываем проём забором.
func _close_fence(t: Thing) -> void:
	if t.kind() != "checkpoint":
		return
	for cc in t.cells():
		var i := world.idx(cc)
		if world.inb(cc) and not world.in_plot(cc) and world.wall[i] == World.W_NONE and world.ground[i] != World.Ground.ROAD:
			world.wall[i] = World.W_FENCE
			world.refresh_cell(cc)


func place_thing(def_id: String, c: Vector2i, built: bool, pay: bool = true, rot: int = 0) -> Thing:
	var t := Thing.new()
	t.id = new_id()
	t.def_id = def_id
	t.cell = c
	t.rot = rot
	t.built = false
	t.ensure_incoming()
	things[t.id] = t
	if t.is_ceiling():
		ceil_at[world.idx(c)] = t.id
	else:
		for cc in t.cells():
			world.occ[world.idx(cc)] = t.id
	if pay and not built and logi.take_spare(def_id, t):
		notify(L.t("%s: возьмём со склада оборудования — платить не нужно.") % t.title(), LVL_GOOD, c)
	elif pay:
		var cost := thing_cost(def_id)
		if market.can_lease(def_id, cost):
			# лизинг: сейчас — аванс, остальное — платежами по понедельникам
			var adv := market.lease_buy(t, cost)
			spend(adv, "Лизинг: аванс за " + t.title_ru())
			cost = adv
		else:
			spend(cost, "Покупка: " + t.title_ru())
		t.cost_paid = cost
		story.on_bought(def_id)
		if not built:
			logi.order(t)
	if built:
		finish_thing(t)
	thing_rev += 1
	return t


## Цена объекта с учётом скидок (субсидии, торги).
func thing_cost(def_id: String) -> float:
	var k := story.price_k(def_id)
	if str(Defs.objects.get(def_id, {}).get("kind", "")) == "machine":
		k *= float(progress.pdef().get("machine_k", 1.0))
	return round(float(Defs.objects.get(def_id, {}).get("cost", 0)) * k)


## 1.47: объект встал на клетку: высокий — непроходим, низкий (поддон) — «перелезть» дорого.
func _occupy(t: Thing, cc: Vector2i) -> void:
	if t.is_low():
		world.climb[world.idx(cc)] = t.id
	else:
		world.block[world.idx(cc)] = t.id


func _vacate(t: Thing, i: int) -> void:
	if world.block[i] == t.id:
		world.block[i] = -1
	if int(world.climb.get(i, -1)) == t.id:
		world.climb.erase(i)


func finish_thing(t: Thing) -> void:
	t.built = true
	t.build_work = 0.0
	if t.kind() == "machine":
		paper.on_machine(t)
		for w in workers:
			Mood.add(self, w, "new_machine")
	_open_fence(t)
	if t.blocks():
		for cc in t.cells():
			if t.blocks_at(cc):
				_occupy(t, cc)
			world.refresh_cell(cc)
			nudge_from(cc)
	thing_rev += 1


## Отметить зону (v=1 — разгрузка, 2 — отгрузка) или снять (v=0) на прямоугольнике. Возвращает число клеток.
## 1.29: обе зоны обязательны — стереть (или закрасить другой зоной) последнюю клетку нельзя: вернёт -1,
## причина — в area_refusal.
func set_area(r: Rect2i, v: int) -> int:
	area_refusal = ""
	var lost := {Logistics.A_UNLOAD: 0, Logistics.A_SHIP: 0}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c0 := Vector2i(x, y)
			if not world.in_plot(c0):
				continue
			var a0 := int(world.area[world.idx(c0)])
			if a0 != v and lost.has(a0) and _area_ok(c0, v):
				lost[a0] = int(lost[a0]) + 1
	for zv: int in lost.keys():
		var have := logi.area_count(zv)
		if have > 0 and int(lost[zv]) >= have:
			area_refusal = L.t(str(AREA_NEED.get(zv, "")))
			return -1
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not world.in_plot(c):
				continue
			var i := world.idx(c)
			if not _area_ok(c, v):
				continue
			if world.area[i] != v:
				world.area[i] = v
				n += 1
	if n > 0:
		world.area_rev += 1
		world.rev += 1
	return n


func _area_ok(c: Vector2i, v: int) -> bool:
	var i := world.idx(c)
	return v == 0 or not (Defs.wall_solid(world.wall[i]) or WallKinds.is_door(world.wall[i]) or WallKinds.is_gate(world.wall[i]))


## Повернуть объект на месте (по часовой стрелке). Пустая строка — получилось.
func rotate_thing(t: Thing) -> String:
	var nr := Thing.next_rot(t.def_id, t.rot)
	if nr == t.rot:
		return L.t("Этот объект не поворачивается")
	if t.user >= 0 or not t.spot_users.is_empty():
		return L.t("Сейчас с ним работают — попробуйте позже")
	var err := can_place(t.def_id, t.cell, nr, t.id)
	if err != "" and not err.begins_with(L.t("Мешают грузы")):
		return L.t("Не помещается: ") + err.to_lower()
	for cc in t.cells():
		var i := world.idx(cc)
		world.occ[i] = -1
		_vacate(t, i)
		world.refresh_cell(cc)
	t.rot = nr
	for cc2 in t.cells():
		var i2 := world.idx(cc2)
		world.occ[i2] = t.id
		if t.built and t.blocks_at(cc2):
			_occupy(t, cc2)
			world.refresh_cell(cc2)
			nudge_from(cc2)
	thing_rev += 1
	return ""


func remove_thing(t: Thing, refund_rate: float) -> void:
	if t.user >= 0:
		var w := get_worker(t.user)
		if w:
			brain.abort(w)
	for wid in t.spot_users.values():
		var w2 := get_worker(int(wid))
		if w2:
			brain.abort(w2)
	# грузы из ячеек — на пол рядом
	var drop := t.cell + Vector2i(0, t.size().y)
	for s in t.slot_count():
		for iid in slot_ids(t, s).duplicate():
			var it: Item = items.get(iid)
			if it:
				put_on_ground(it, world.nearest_passable(drop))
	# снять резервирования грузов, которые несут сюда
	for w3 in workers:
		if w3.task:
			for pair in w3.task.res_incoming:
				if int(pair[0]) == t.id:
					brain.abort(w3)
					break
	if t.is_ceiling():
		ceil_at.erase(world.idx(t.cell))
	else:
		for cc in t.cells():
			var i := world.idx(cc)
			world.occ[i] = -1
			_vacate(t, i)
			world.refresh_cell(cc)
		_close_fence(t)
	things.erase(t.id)
	slot_items.erase(t.id)
	var refund := t.cost_paid * refund_rate
	if refund > 0.0:
		earn(refund, "Возврат: " + t.title_ru())
	thing_rev += 1


# ---------------------------------------------------------------- чертежи стен и полов

func floor_cost(fid: int) -> float:
	return float(Defs.floor_by_id.get(fid, {}).get("cost", 0))


func wall_cost(wid: int) -> float:
	return float(Defs.wall_by_id.get(wid, {}).get("cost", 0))


func place_floor_bp(c: Vector2i, fid: int) -> bool:
	if not world.in_plot(c):
		return false
	var i := world.idx(c)
	if world.flr[i] == fid or world.bp_floor[i] == fid:
		return false
	var cost := floor_cost(fid)
	if not can_afford(cost):
		return false
	if world.bp_floor[i] != World.BP_NONE:
		cancel_floor_bp(c)
	if bp_cells.is_empty():
		bp_progress_at = minute
	world.bp_floor[i] = fid
	bp_cells[i] = true
	spend(cost, "Стройка: " + str(Defs.floor_by_id[fid]["name"]))
	world.rev += 1
	return true


func place_wall_bp(c: Vector2i, wid: int) -> bool:
	if not world.in_plot(c):
		return false
	var i := world.idx(c)
	if world.wall[i] == wid or world.bp_wall[i] == wid:
		return false
	if world.occ[i] >= 0:
		return false
	var cost := wall_cost(wid)
	if not can_afford(cost):
		return false
	if world.bp_wall[i] != World.BP_NONE:
		cancel_wall_bp(c)
	if bp_cells.is_empty():
		bp_progress_at = minute
	world.bp_wall[i] = wid
	bp_cells[i] = true
	spend(cost, "Стройка: " + str(Defs.wall_by_id[wid]["name"]))
	world.rev += 1
	return true


## Помещение одной рамкой: пол по всему прямоугольнику, кирпичные стены по контуру
## (общие стены с соседями не трогаем) и дверь посередине нижней стены. "" — получилось.
func place_room_bp(r: Rect2i, fid: int) -> String:
	if r.size.x < 3 or r.size.y < 3:
		return L.t("Помещение — минимум 3×3 клетки (стены по краю, внутри пол).")
	var cost := room_bp_cost(r, fid)
	if not can_afford(cost):
		return L.t("Не хватает денег: помещение обойдётся в %s.") % Defs.money_str(cost)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if world.in_plot(c):
				place_floor_bp(c, fid)
	for c2 in room_wall_cells(r):
		if world.in_plot(c2):
			place_wall_bp(c2, World.W_BRICK)
	var door := room_door_cell(r)
	if not world.is_door(door):
		place_wall_bp(door, World.W_DOOR)
	return ""


static func room_wall_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1:
				out.append(Vector2i(x, y))
	return out


## Дверь новой рамки: посередине нижней стены, а если там нельзя — посередине правой.
func room_door_cell(r: Rect2i) -> Vector2i:
	var d := Vector2i(r.position.x + r.size.x / 2, r.end.y - 1)
	if not world.in_plot(d + Vector2i(0, 1)) or world.occ[world.idx(d)] >= 0:
		d = Vector2i(r.end.x - 1, r.position.y + r.size.y / 2)
	return d


func room_bp_cost(r: Rect2i, fid: int) -> float:
	var cost := 0.0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not world.in_plot(c):
				continue
			var i := world.idx(c)
			if world.flr[i] != fid and world.bp_floor[i] != fid:
				cost += floor_cost(fid)
	for c2 in room_wall_cells(r):
		if not world.in_plot(c2):
			continue
		var j := world.idx(c2)
		if world.wall[j] == World.W_NONE and world.bp_wall[j] == World.BP_NONE:
			cost += wall_cost(World.W_BRICK)
	return cost + wall_cost(World.W_DOOR) - wall_cost(World.W_BRICK)


## Снос: стена, затем пол, затем объект.
func place_demolish(c: Vector2i) -> bool:
	if not world.in_plot(c) and not world.inner_fence(c):
		return false
	var i := world.idx(c)
	var lamp := ceiling_at(c)
	var floor_t: Thing = things.get(world.occ[i]) if world.occ[i] >= 0 else null
	var any := false
	for t: Thing in [lamp, floor_t]:
		if t == null:
			continue
		any = true
		if not t.built:
			cancel_thing(t)
		else:
			t.demolish = true
			thing_rev += 1
	if any:
		return true
	if world.flora[i] != 0 and world.wall[i] == World.W_NONE:
		# дерево или куст: спилят и выкорчуют (чертёж «снос пола» на голой земле)
		world.bp_floor[i] = 0
		bp_cells[i] = true
		world.rev += 1
		return true
	if world.wall[i] != World.W_NONE and (bool(Defs.wall_by_id.get(world.wall[i], {}).get("buildable", false)) or world.inner_fence(c)):
		world.bp_wall[i] = 0
		bp_cells[i] = true
		world.rev += 1
		return true
	if world.flr[i] != 0:
		world.bp_floor[i] = 0
		bp_cells[i] = true
		world.rev += 1
		return true
	return false


# ---------------------------------------------------------------- земля (1.13)

## Купить соседний участок k (вызывает «Развитие → Земля» по готовности).
func buy_lot(k: int) -> bool:
	if k < 0 or k >= world.lots.size() or world.lot_bought(k):
		return false
	var r := world.lot_rect(k)
	var side := world.lot_side(k)
	world.own_lot(k)
	# 1.26: на участке — старое здание прежних хозяев (склад, пилорама, гаражи)
	var ob := OldBuild.place(self, k)
	world.flora_rev += 1
	world.refresh_all()
	notify(L.t("Участок %s куплен: ещё %d×%d клеток%s. Старый забор между участками снесите (Снос), деревья спилят строители.") % [side, r.size.x, r.size.y,
		(L.t(", на нём %s — стены и ворота целы, нужны свет, проводка и уборка") % ob) if ob != "" else ""], LVL_GOOD, r.get_center())
	return true


## Перенести построенную карту в середину большей (1.13, соседние участки со всех сторон):
## всё, что стоит, лежит и ходит, сдвигается на (ox, oy).
func embed(ox: int, oy: int, nw: int, nh: int) -> void:
	var off := Vector2i(ox, oy)
	var ow := world.w
	world.embed(ox, oy, nw, nh)
	for t: Thing in things.values():
		t.cell += off
	ceil_at.clear()
	for t2: Thing in things.values():
		if t2.is_ceiling():
			ceil_at[world.idx(t2.cell)] = t2.id
	for it: Item in items.values():
		if it.loc == Item.Loc.GROUND:
			it.cell += off
	for wk in workers + visitors:
		wk.pos += Vector2(off)
		wk.exit_cell += off
		wk.path.clear()
		wk.path_target = Vector2i(-999, -999)
	gate_x += ox
	for v in vehicles:
		v.x += ox
		v.park_x += ox
	var remap := func(d: Dictionary) -> Dictionary:
		var out := {}
		for k in d.keys():
			var c := Vector2i(int(k) % ow, int(int(k) / ow)) + off
			out[world.idx(c)] = d[k]
		return out
	bp_cells = remap.call(bp_cells)
	bp_res = remap.call(bp_res)
	net_res.clear()
	logi.cell_res.clear()
	light = PackedByteArray()
	traffic = PackedFloat32Array()
	season.setup_map()
	upkeep.dirt = PackedByteArray()
	for dg: Dictionary in progress.dogs:
		dg["x"] = float(dg["x"]) + ox
		dg["y"] = float(dg["y"]) + oy
		dg["tx"] = float(dg.get("tx", dg["x"])) + ox
		dg["ty"] = float(dg.get("ty", dg["y"])) + oy
	if town and town.cat:
		town.cat.pos += Vector2(off)
	thing_rev += 1
	item_rev += 1
	world.refresh_all()
	rooms.rebuild()
	rooms.update()


## Следующий участок, который можно купить (-1 — все куплены или их нет).
func next_lot() -> int:
	for k in world.lots.size():
		if not world.lot_bought(k):
			return k
	return -1


func cancel_floor_bp(c: Vector2i) -> void:
	var i := world.idx(c)
	var v := world.bp_floor[i]
	if v == World.BP_NONE:
		return
	if v > 0:
		earn(floor_cost(v), "Отмена чертежа")
	world.bp_floor[i] = World.BP_NONE
	_bp_cleanup(i)


func cancel_wall_bp(c: Vector2i) -> void:
	var i := world.idx(c)
	var v := world.bp_wall[i]
	if v == World.BP_NONE:
		return
	if v > 0:
		earn(wall_cost(v), "Отмена чертежа")
	world.bp_wall[i] = World.BP_NONE
	_bp_cleanup(i)


func cancel_thing(t: Thing) -> void:
	if t.built:
		t.demolish = false
		thing_rev += 1
		return
	# уже принесённые ящики возвращаются на землю — их уберут на склад оборудования
	for k in t.crates_in:
		var it := new_item("crate", t.def_id, "loose" if Logistics.is_hand(t.def_id) else "crate")
		it.step = k
		put_on_ground(it, world.nearest_passable(t.cell))
	var not_sent := logi.on_cancelled(t)
	if not_sent:
		market.cancel_lease(t.id)
	if t.cost_paid > 0.0 and not_sent:
		earn(t.cost_paid, "Отмена покупки: " + t.title_ru())
	elif t.cost_paid > 0.0:
		notify(L.t("%s уже везут — ящики сложат на склад оборудования, их можно поставить позже или продать (Производство → Склад оборудования).") % t.title(), LVL_INFO, t.cell)
	t.cost_paid = 0.0
	remove_thing(t, 0.0)


func cancel_all_at(c: Vector2i) -> void:
	cancel_wall_bp(c)
	cancel_floor_bp(c)
	var t := thing_at(c)
	if t and (not t.built or t.demolish):
		cancel_thing(t)


func _bp_cleanup(i: int) -> void:
	if world.bp_floor[i] == World.BP_NONE and world.bp_wall[i] == World.BP_NONE:
		bp_cells.erase(i)
	if bp_res.has(i):
		var w := get_worker(int(bp_res[i]))
		if w:
			brain.abort(w)
		bp_res.erase(i)
	world.rev += 1


## Можно ли сейчас строить чертёж в клетке (не мешают ли люди/грузы).
func bp_ready(i: int) -> bool:
	var c := world.cell_of(i)
	var wv := world.bp_wall[i]
	if wv != World.BP_NONE and Defs.wall_solid(wv):
		for gid in ground_items:
			var gi: Item = items.get(gid)
			if gi and gi.cell == c:
				return false
	return true


func bp_work_time(i: int) -> float:
	var wv := world.bp_wall[i]
	if wv != World.BP_NONE:
		if wv == 0:
			return 10.0
		return float(Defs.wall_by_id[wv].get("build_time", 10))
	var fv := world.bp_floor[i]
	var tree := 0.0
	if world.flora[i] != 0:
		tree = 14.0 if world.flora[i] <= 3 else 6.0   # сначала спилить дерево или выкорчевать куст
	if fv == 0:
		return 5.0 + tree if world.flr[i] != 0 else maxf(tree, 3.0)
	return float(Defs.floor_by_id.get(fv, {}).get("build_time", 5)) + tree


func complete_bp(i: int) -> void:
	bp_progress_at = minute
	var c := world.cell_of(i)
	var wv := world.bp_wall[i]
	if wv != World.BP_NONE:
		if wv == 0:
			var old := world.wall[i]
			earn(wall_cost(old) * Defs.b("refund_rate"), "Снос: возврат материалов")
		world.wall[i] = wv
		world.bp_wall[i] = World.BP_NONE
		if world.flora[i] != 0 and wv != 0:
			world.flora[i] = 0
			world.flora_rev += 1
		# стена ставится на пол: под стеной пол не нужен, но оставим как есть
		if wv != 0 and Defs.wall_solid(wv):
			nudge_from(c)
	else:
		var fv := world.bp_floor[i]
		if fv != World.BP_NONE:
			if fv == 0 and world.flr[i] != 0:
				earn(floor_cost(world.flr[i]) * Defs.b("refund_rate"), "Снос: возврат материалов")
			world.flr[i] = fv
			world.bp_floor[i] = World.BP_NONE
		if world.flora[i] != 0:
			world.flora[i] = 0
			world.flora_rev += 1
	if world.bp_floor[i] == World.BP_NONE and world.bp_wall[i] == World.BP_NONE:
		bp_cells.erase(i)
	bp_res.erase(i)
	world.refresh_cell(c)


## Вытолкнуть людей и грузы из клетки, ставшей непроходимой.
func nudge_from(c: Vector2i) -> void:
	if world.passable(c):
		return
	var target := world.nearest_passable(c)
	if target.x < 0:
		return
	for w in workers:
		if w.present and w.cell() == c:
			w.pos = Vector2(target) + Vector2(0.5, 0.5)
			w.path.clear()
			w.path_target = Vector2i(-999, -999)
	for gid in ground_items.duplicate():
		var gi: Item = items.get(gid)
		if gi and gi.cell == c:
			put_on_ground(gi, target)


# ---------------------------------------------------------------- фургоны и снабжение

func get_vehicle(id: int) -> Vehicle:
	for v in vehicles:
		if v.id == id:
			return v
	return null


func spawn_vehicle(kind: String) -> Vehicle:
	var v := Vehicle.new()
	v.id = new_id()
	v.kind = kind
	v.state = "queued"
	v.x = -6.0
	v.park_x = float(gate_x)
	v.color = 0 if kind == "delivery" else rng.randi_range(1, 3)
	vehicles.append(v)
	return v


func order_material(mat: String, qty: int, auto: bool = false) -> String:
	if qty <= 0:
		return L.t("Укажите количество")
	var price := material_price(mat)
	var cost := price * qty
	var sd := office.supplier_def()
	if auto and not can_afford(cost):
		# 1.20: снабжение само в долг не закупает — решает директор (Производство → Металл)
		notify_once("auto_supply_debt", L.t("Снабжение: на металл нет денег — само в долг не закупает. Купить в долг можно вручную: «Производство → Металл и расходники»."), LVL_WARN, Vector2i(-1, -1), 720.0)
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(cost)
	if not can_afford(cost):
		# товарный кредит: под принятые заказы поставщик отгружает с отсрочкой платежа
		if trade_credit_left() < cost:
			return L.t("Не хватает денег: нужно %s") % Defs.money_str(cost)
		office.add_debt(cost * 1.05, 2, "Отсрочка платежа за металл")
		notify(L.t("Денег на металл не хватило — %s отгрузил %s × %d в долг: %s вернуть за две недели (+5%%).") % [office.supplier_name(), Defs.material_name(mat), qty, Defs.money_str(cost * 1.05)], LVL_WARN)
	else:
		spend(cost, "Металл: %s × %d (%s)" % [Defs.material_name(mat), qty, office.supplier_name()])
	var dl: Array = sd.get("delay", [Defs.b("supply_delay_min"), Defs.b("supply_delay_max")])
	var delay := rng.randf_range(float(dl[0]), float(dl[1]))
	if rng.randf() < float(sd.get("risk", 0.0)):
		delay += 1440.0
		notify_once("sup_late", L.t("Поставщик %s предупредил: машина задержится на сутки.") % office.supplier_name(), LVL_WARN, Vector2i(-1, -1), 600.0)
	if story.has_mod("roads"):
		delay += 1440.0
	var eta := to_work_time(minute + delay)
	supply.append({"id": new_id(), "mat": mat, "qty": qty, "eta": eta, "spawned": false, "done": false})
	var when := _eta_str(eta)
	notify(L.t("Заказан металл: %s × %d. Привезут %s.") % [Defs.material_name(mat), qty, when], LVL_INFO)
	return ""


## Сколько ещё поставщики готовы отгрузить в долг (лимит растёт с этапом, при плохой репутации — меньше).
func trade_credit_left() -> float:
	var limit := (120000.0 + 60000.0 * float(progress.stage - 1)) * clampf(reputation / 50.0, 0.3, 1.5)
	var used := 0.0
	for l: Dictionary in office.loans:
		if str(l.get("title", "")).begins_with("Отсрочка"):
			used += float(l["payment"]) * int(l["left"])
	return maxf(0.0, limit - used)


## Цена металла за штуку у текущего поставщика.
func material_price(mat: String) -> float:
	return round(float(Defs.materials.get(mat, {}).get("price", 0)) * office.material_k() * story.mod("metal_price") * story.mod("metal_sale") * (market.metal if market else 1.0))


func _eta_str(eta: float) -> String:
	var d := int(eta / 1440.0) + 1
	var m := int(fmod(eta, 1440.0))
	var hm := "%02d:%02d" % [int(m / 60), m % 60]
	if d == day():
		return L.t("сегодня к ") + hm
	if d == day() + 1:
		return L.t("завтра к ") + hm
	return L.t("в день %d к %s") % [d, hm]


func _tick_supply() -> void:
	for s: Dictionary in supply:
		if not bool(s["spawned"]) and minute >= float(s["eta"]):
			var v := spawn_vehicle("delivery")
			v.supply_id = int(s["id"])
			v.cargo_desc = "%s × %d" % [Defs.material_name(str(s["mat"])), int(s["qty"])]
			if int(s["qty"]) >= 18:
				v.body = "truck"   # большую партию металла везёт грузовик с бортами
			else:
				v.body = "flatbed"   # 1.30: прутки видно на бортовой платформе
			s["spawned"] = true


func _tick_vehicles(dt: float) -> void:
	var active: Vehicle = null
	for v in vehicles:
		if (v.state == "arriving" or v.state == "parked") and v.lane == 0:
			active = v
			break
	if active == null:
		for v in vehicles:
			if v.state == "queued" and v.lane == 0:
				v.state = "arriving"
				break
	var speed := Defs.b("van_speed")
	for v in vehicles:
		var sp := speed * (2.0 if v.kind == "fire" else 1.0)   # 1.30: пожарные — с сиреной, без очереди
		match v.state:
			"queued":
				if v.lane == 1:
					v.state = "arriving"   # встречная полоса: к воротам не встаёт
			"arriving":
				v.x += sp * dt * v.dir()
				if (v.x - v.park_x) * v.dir() >= 0.0:
					v.x = v.park_x
					v.state = "parked"
					v.parked_time = 0.0
					_on_park(v)
			"parked":
				v.parked_time += dt
				if v.hold:
					pass   # 1.30: уедет, когда отпустят (пожарный расчёт, ломовоз — FireBrigade/Upkeep)
				elif v.kind == "visit":
					if v.parked_time > 25.0:
						v.state = "leaving"   # ломовоз забрал металлолом и уехал
				elif v.kind == "delivery":
					var cargo: Array = veh_items.get(v.id, [])
					# водитель ждёт разгрузки до конца смены (и не больше 5 часов)
					var late := tod() >= Defs.b("shift_end") or not is_workday()
					if (v.parked_time > 300.0 or (late and v.parked_time > 30.0)) and not cargo.is_empty():
						_dump_cargo(v)
					if cargo.is_empty():
						v.state = "leaving"
				elif v.kind != "pickup":
					if v.parked_time > 30.0:
						v.state = "leaving"   # 1.30: ломовоз или пожарные без своей службы — постоят и уедут
				else:
					if v.loaded >= v.need:
						v.state = "leaving"
						orders.on_pickup_done(v)
					elif v.parked_time > 150.0 and v.reserved_load == 0:
						# грузить нечего: детали кончились — водитель уезжает с тем, что есть
						var o := orders.get_order(v.order_id)
						var p := str(o.get("product", ""))
						if o.is_empty() or ok_in_storage(p) == 0:
							v.state = "leaving"
							orders.on_partial_pickup(v)
			"leaving":
				v.x += sp * dt * v.dir()
				if v.x > world.w + 10 or v.x < -14.0:
					v.state = "gone"
	for k in range(vehicles.size() - 1, -1, -1):
		if vehicles[k].state == "gone":
			veh_items.erase(vehicles[k].id)
			vehicles.remove_at(k)


## Водитель устал ждать: сгружает всё у ворот и уезжает.
func _dump_cargo(v: Vehicle) -> void:
	var dumped := 0
	var gate := Vector2i(gate_x, world.plot.end.y - 1)
	for iid in (veh_items.get(v.id, []) as Array).duplicate():
		var it: Item = items.get(iid)
		if it == null or it.reserved_by >= 0:
			continue
		# 1.18: не рядком до края карты, а штабелями — в зону разгрузки или на поддоны у ворот
		var c := Vector2i(-1, -1)
		if logi.has_zone():
			c = logi.free_cell(logi.zone_cells(), it, gate)
		if c.x < 0:
			c = bmats.yard_cell(it, gate)
		put_on_ground(it, c)
		dumped += 1
	if dumped > 0:
		notify(L.t("Водитель не дождался разгрузки и оставил груз у ворот — занесут, когда освободятся руки."), LVL_INFO, Vector2i(gate_x, world.plot.end.y - 1))


func dispose() -> void:
	orders.sim = null
	planner.sim = null
	brain.sim = null


## 1.38.2: разорвать ВСЕ обратные ссылки подсистем на завод (season.sim, story.brigade.sim, town.cat.sim…), чтобы
## RefCounted-завод освободился целиком. dispose() рвёт только три — остальные кольца держали бы весь мир в памяти.
## После release() заводом пользоваться нельзя (фон меню сменяет миры каждые сутки — см. MenuScenes.restore).
func release() -> void:
	dispose()
	var seen := {}
	_unlink(self, seen, 0)


func _unlink(o: Object, seen: Dictionary, depth: int) -> void:
	for p: Dictionary in o.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or int(p["type"]) != TYPE_OBJECT:
			continue
		var v: Variant = o.get(str(p["name"]))
		if not (v is RefCounted) or v is Sim or v is Resource:
			continue
		var id := (v as Object).get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		if "sim" in v:
			(v as Object).set("sim", null)
		if depth < 2:
			_unlink(v as Object, seen, depth + 1)


func _on_park(v: Vehicle) -> void:
	var cell := Vector2i(int(v.park_x), world.sidewalk_row)
	if v.kind == "fire":
		story.brigade.on_park(v)   # 1.30: пожарный расчёт выходит из машины
		return
	sfx.emit("van_horn", cell)
	if v.kind == "scrap":
		upkeep.on_truck_park(v)    # 1.30: водитель ломовоза идёт за стружкой и браком
		return
	if v.kind == "delivery" and v.bmat_order >= 0:
		bmats.on_park(v)
	elif v.kind == "delivery" and not v.equip.is_empty():
		logi.on_park(v)
	elif v.kind == "delivery":
		for s: Dictionary in supply:
			if int(s["id"]) == v.supply_id:
				for n in int(s["qty"]):
					var it := new_item("mat", str(s["mat"]), "raw")
					put_in_vehicle(it, v)
				s["done"] = true
				notify(L.t("Привезли металл: %s. Разгружаем.") % v.cargo_desc, LVL_INFO, cell)
		supply = supply.filter(func(x: Dictionary) -> bool: return not bool(x["done"]))
	else:
		var o := orders.get_order(v.order_id)
		if not o.is_empty():
			notify(L.t("Приехали за заказом: %s. Грузим.") % orders.short(o), LVL_INFO, cell)


# ---------------------------------------------------------------- тик

func tick(dt: float) -> void:
	if crisis.is_over():
		return   # 1.20: завод закрыт — мир стоит
	var prev_day := day()
	var prev_tod := tod()
	minute += dt
	var now_tod := tod()
	if day() != prev_day:
		_on_new_day()
		prev_tod = -1.0
	_timed(prev_tod, now_tod)
	_tick_supply()
	logi.tick()
	logi.tick_crews(dt)   # 1.56: грузчики машин
	bmats.tick_trucks()
	grants.tick(dt)
	_tick_vehicles(dt)
	rooms.update()
	season.tick(dt)
	power.tick(dt)
	_tick_cons_supply()
	_tick_machines(dt)
	office.tick(dt)
	dev.tick(dt)
	bmats.tick(dt)
	social.tick(dt)
	story.tick(dt)
	brain.tick(dt)
	inspect.tick(dt)
	progress.tick(dt)
	planner.tick(dt)
	orders.tick(dt)
	sales.tick(dt)
	training.tick(dt)
	town.tick(dt)
	fauna.tick(dt)
	upkeep.tick(dt)
	eng.tick(dt)
	plan.tick(dt)
	faults.tick()


func _crossed(prev: float, now: float, t: float) -> bool:
	return prev < t and now >= t


func _timed(prev: float, now: float) -> void:
	if _crossed(prev, now, 360.0):
		market.morning()
		orders.morning()
		if weekday() == 0 or candidates.is_empty():
			refresh_candidates()
		if weekday() == 0:
			_honor_board()
			office.on_monday()
		paper.morning()
		office.morning()
		story.morning()
		inspect.morning()
		calls.morning()
		progress.morning()
		training.morning()
		town.morning()
		eng.morning()
		crew.morning()
		crisis.morning()
		Workplace.auto_assign(self)   # 1.15: у каждого рабочего места — хозяин
		career.morning()
		crew.hints()
		Nicks.daily(self)
		if weekday() == 0:
			paper.publish()
		morning.emit(day())
	if is_workday() and _crossed(prev, now, Defs.b("shift_end") + 30.0) and weekday() == 4:
		_pay_wages()
	# заводской гудок: начало и конец первой смены
	if is_workday() and (_crossed(prev, now, Defs.b("shift_start")) or _crossed(prev, now, Defs.b("shift_end"))):
		sfx.emit("factory_horn", Vector2i(-1, -1))


func _on_new_day() -> void:
	season.on_new_day()
	var rent := Defs.b("rent_per_day")
	spend(rent, "Аренда бокса")
	power.close_day()   # 1.53: электричество двумя строками — день и ночь
	power.on_new_day()
	statlog.record()
	if money < 0.0:
		notify_once("cash", L.t("Кассовый разрыв! Денег нет — срочно выполняйте заказы."), LVL_BAD, Vector2i(-1, -1), 1440.0)


func _pay_wages() -> void:
	var total := 0.0
	for w in workers:
		total += float(w.get_meta("wage_due", 0.0))
	if total > 0.0:
		var paid := crisis.pay_wages(total)
		for w0 in workers:
			w0.set_meta("wage_due", 0.0)
		if paid:
			spend(total, "Зарплата за неделю")
			notify(L.t("Выдана зарплата за неделю: %s.") % Defs.money_str(total), LVL_INFO)
			for w2 in workers:
				Mood.add(self, w2, "payday")
	office.on_payday()
	crew.week_end()


## Доска почёта: по понедельникам — фото лучшего работника прошлой недели.
func _honor_board() -> void:
	var has_board := false
	for t: Thing in things.values():
		if t.built and t.def_id == "honor_board":
			has_board = true
			break
	var best: Worker = null
	for w in workers:
		if best == null or w.week_score > best.week_score:
			best = w
	if best and best.week_score > 0:
		honor_log.push_front({"id": best.id, "first": best.first, "last": best.last, "prof": best.prof_name(), "look": best.look.duplicate(),
			"age": best.age, "day": day(), "score": best.week_score, "board": has_board})
		if honor_log.size() > 12:
			honor_log.resize(12)
	if has_board and best and best.week_score > 0:
		Mood.add(self, best, "honor_board")
		best.add_history(day(), L.t("Фото повесили на доску почёта"))
		notify(L.t("На доску почёта повесили фото: %s, %s. Лучший работник недели!") % [best.full_name(), best.prof_lc()], LVL_GOOD)
	for w in workers:
		w.week_score = 0


# ---------------------------------------------------------------- сохранение

func to_dict() -> Dictionary:
	var th: Array = []
	for t: Thing in things.values():
		th.append(t.to_dict())
	var its: Array = []
	for it: Item in items.values():
		its.append(it.to_dict())
	var ws: Array = []
	for w in workers:
		var d := w.to_dict()
		d["wage_due"] = float(w.get_meta("wage_due", 0.0))
		d["arrears"] = float(w.get_meta("arrears", 0.0))
		for mk in ["absences", "caught_theft"]:
			if int(w.get_meta(mk, 0)) > 0:
				d[mk] = int(w.get_meta(mk, 0))
		ws.append(d)
	var vs: Array = []
	for v in vehicles:
		vs.append(v.to_dict())
	return {
		"version": VERSION, "scenario": scenario, "minute": minute, "money": money,
		"reputation": reputation, "next_id": next_id, "world": world.to_dict(),
		"things": th, "items": its, "workers": ws, "vehicles": vs,
		"orders": orders.list, "supply": supply, "candidates": candidates, "customs": customs, "cust_k": custom_chance,
		"stats": stats, "ledger": ledger.slice(0, 100), "log": events.slice(0, 60), "honor": honor_log,
		"power": power_kwh_day, "gate_x": gate_x, "rng": rng.state, "bp_at": bp_progress_at, "build_priority": build_priority,
		"grid": power.to_dict(), "reserve": supply_reserve, "cons": cons, "cons_supply": cons_supply, "ppr": ppr,
		"office": office.to_dict(),
		"season": season.to_dict(), "story": story.to_dict(), "inspect": inspect.to_dict(), "calls": calls.to_dict(), "paper": paper.to_dict(),
		"progress": progress.to_dict(), "logi": logi.to_dict(), "grants": grants.to_dict(), "statlog": statlog.to_dict(),
		"sales": sales.to_dict(), "training": training.to_dict(), "career": career.to_dict(), "upkeep": upkeep.to_dict(), "eng": eng.to_dict(), "crew": crew.to_dict(), "market": market.to_dict(), "town": town.to_dict(), "crisis": crisis.to_dict(), "fauna": fauna.to_dict(), "dev": dev.to_dict(), "bmats": bmats.to_dict(), "legacy": {"zone": rooms.legacy.keys(), "water": water.bonus},
		"company": company, "plan": plan.to_dict(), "faults": faults.to_dict(),
		"areas": areas.to_dict(),
	}


static func from_dict(d: Dictionary) -> Sim:
	var s := Sim.new()
	s.scenario = str(d.get("scenario", "garage"))
	s.minute = float(d["minute"])
	s.money = float(d["money"])
	s.reputation = float(d.get("reputation", 50.0))
	s.next_id = int(d["next_id"])
	s.world.from_dict(d["world"])
	s.gate_x = int(d.get("gate_x", 22))
	s.power_kwh_day = float(d.get("power", 0.0))
	s.bp_progress_at = float(d.get("bp_at", s.minute))
	s.build_priority = bool(d.get("build_priority", false))
	s.power.from_dict(d.get("grid", {}))
	if not (d.get("grid", {}) as Dictionary).has("kd"):
		s.power.kwh_day = s.power_kwh_day   # сохранение до 1.53: недосчитанные кВт·ч — по дневному тарифу
	s.supply_reserve = int(d.get("reserve", 1))
	if d.has("cons"):
		var cd: Dictionary = d["cons"]
		for k in cd.keys():
			s.cons[k] = float(cd[k])
	s.cons_supply = d.get("cons_supply", [])
	s.ppr = bool(d.get("ppr", false))
	s.office.from_dict(d.get("office", {}))
	s.season.from_dict(d.get("season", {}))
	s.story.from_dict(d.get("story", {}))
	s.inspect.from_dict(d.get("inspect", {}))
	s.calls.from_dict(d.get("calls", {}))
	s.paper.from_dict(d.get("paper", {}))
	s.progress.from_dict(d.get("progress", {}))
	s.logi.from_dict(d.get("logi", {}))
	s.grants.from_dict(d.get("grants", {}))
	s.sales.from_dict(d.get("sales", {}))
	s.training.from_dict(d.get("training", {}))
	s.career.from_dict(d.get("career", {}))
	s.plan.from_dict(d.get("plan", {}))
	var cdata: Variant = d.get("company", {})
	s.company = cdata if cdata is Dictionary and not (cdata as Dictionary).is_empty() else Company.default_data()
	s.upkeep.from_dict(d.get("upkeep", {}))
	s.eng.from_dict(d.get("eng", {}))
	s.crew.from_dict(d.get("crew", {}))
	s.market.from_dict(d.get("market", {}))
	s.town.from_dict(d.get("town", {}))
	s.crisis.from_dict(d.get("crisis", {}))
	s.fauna.from_dict(d.get("fauna", {}))
	s.dev.from_dict(d.get("dev", {}))
	s.bmats.from_dict(d.get("bmats", {}))
	s.areas.from_dict(d.get("areas", {}))
	var lg: Dictionary = d.get("legacy", {})
	for lid in lg.get("zone", []):
		s.rooms.legacy[int(lid)] = true
	s.water.bonus = int(lg.get("water", 0))
	s.stats = d.get("stats", s.stats)
	s.statlog.from_dict(d.get("statlog", {}))
	s.ledger = d.get("ledger", [])
	s.honor_log = d.get("honor", [])
	s.events = d.get("log", [])
	s.supply = d.get("supply", [])
	s.candidates = d.get("candidates", [])
	s.customs = d.get("customs", [])
	s.custom_chance = float(d.get("cust_k", 0.0))
	s.orders.list = d.get("orders", [])
	if d.has("rng"):
		s.rng.state = int(d["rng"])
	var late_cp: Array[Thing] = []
	for td: Dictionary in d["things"]:
		var t := Thing.from_dict(td)
		s.things[t.id] = t
		if t.is_ceiling():
			s.ceil_at[s.world.idx(t.cell)] = t.id
			continue
		if t.kind() == "checkpoint":
			late_cp.append(t)   # 1.30: проходная стала 4×1 — ставим после остальных, чтобы видеть соседей
			continue
		for cc in t.cells():
			s.world.occ[s.world.idx(cc)] = t.id
			if t.built and t.blocks_at(cc):
				s._occupy(t, cc)
	for t: Thing in late_cp:
		s._fit_old_checkpoint(t)
		if not s.things.has(t.id):
			continue
		for cc in t.cells():
			s.world.occ[s.world.idx(cc)] = t.id
			if t.built and t.blocks_at(cc):
				s._occupy(t, cc)
	for wd: Dictionary in d["workers"]:
		var w := Worker.from_dict(wd)
		w.set_meta("wage_due", float(wd.get("wage_due", 0.0)))
		if float(wd.get("arrears", 0.0)) > 0.0:
			w.set_meta("arrears", float(wd.get("arrears", 0.0)))
		for mk in ["absences", "caught_theft"]:
			if int(wd.get(mk, 0)) > 0:
				w.set_meta(mk, int(wd.get(mk, 0)))
		s.workers.append(w)
	for vd: Dictionary in d["vehicles"]:
		s.vehicles.append(Vehicle.from_dict(vd))
	for idd: Dictionary in d["items"]:
		var it := Item.from_dict(idd)
		s.items[it.id] = it
		match it.loc:
			Item.Loc.THING:
				var t2: Thing = s.things.get(it.holder)
				if t2 and it.slot < t2.slot_count():
					(s._slots(t2)[it.slot] as Array).append(it.id)
				else:
					it.loc = Item.Loc.GROUND
					s.ground_items.append(it.id)
			Item.Loc.GROUND:
				s.ground_items.append(it.id)
			Item.Loc.VEHICLE:
				if not s.veh_items.has(it.holder):
					s.veh_items[it.holder] = []
				(s.veh_items[it.holder] as Array).append(it.id)
			Item.Loc.WORKER:
				# незавершённые задачи не сохраняются: груз кладём на пол рядом с рабочим
				var w2 := s.get_worker(it.holder)
				it.loc = Item.Loc.GROUND
				it.cell = w2.cell() if w2 else Vector2i(24, 24)
				it.holder = -1
				s.ground_items.append(it.id)
	for i in s.world.w * s.world.h:
		if s.world.bp_floor[i] != World.BP_NONE or s.world.bp_wall[i] != World.BP_NONE:
			s.bp_cells[i] = true
	s.world.refresh_all()
	if int(d.get("version", 1)) < 2:
		Scenario.migrate_v1(s)
	if int(d.get("version", 1)) < 6:
		s.rooms.update()
		s.progress.migrate()
	if int(d.get("version", 1)) < 7:
		Scenario.migrate_v7(s)
	if int(d.get("version", 1)) < 8:
		Rooms.migrate_zones_v8(s)
		s.rooms.update()
	if int(d.get("version", 1)) < 9:
		Rooms.migrate_zones_v9(s)
	if int(d.get("version", 1)) < 10:
		Scenario.migrate_v10(s)
	if int(d.get("version", 1)) < 11:
		Scenario.migrate_v11(s)
	if int(d.get("version", 1)) < 12:
		Scenario.migrate_v12(s)
	if int(d.get("version", 1)) < 13:
		Scenario.migrate_v13(s)   # 1.29: обязательные зоны разгрузки и отгрузки
	s.faults.from_dict(d.get("faults", {}))
	if not d.has("areas"):
		Director.ensure(s)   # 1.40: в сохранениях до 1.40 директора не было — он появляется
	# 1.18: сразу после загрузки — сеть, вода и помещения посчитаны (насосная качает до первого тика)
	s.rooms.update()
	s.power.tick(0.0)
	s.rooms.update()
	return s
