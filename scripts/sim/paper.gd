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


func _init(s: Sim) -> void:
	sim = s


func add(rubric: String, title: String, text: String) -> void:
	for p: Dictionary in pending:
		if str(p["title"]) == title:
			return
	pending.append({"rubric": rubric, "title": title, "text": text, "day": sim.day()})
	if pending.size() > 14:
		pending.pop_front()


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
	# новости недели
	var news := pending.duplicate()
	news.reverse()
	for n: Dictionary in news.slice(0, 5):
		items.append(n)
	pending.clear()
	# быт: столовая, туалеты, отопление
	items.append(_life_item())
	# погода и сезон
	items.append(_weather_item())
	# мелочи
	var fillers: Array = Defs.paper.get("fillers", [])
	if not fillers.is_empty():
		var fi := (number * 7 + sim.day()) % fillers.size()
		var f: Array = fillers[fi]
		items.append({"rubric": L.dt("paper.filler.%d.rubric" % fi, str(f[0])), "title": "", "text": L.dt("paper.filler.%d.text" % fi, str(f[1]))})
	issues.push_front({"no": number, "day": sim.day(), "date": sim.season.long_date(), "items": items})
	if issues.size() > 12:
		issues.resize(12)
	unread = true
	sim.notify(L.t("Вышел свежий номер многотиражки «%s» № %d — газета коллектива %s.") % [title_str(), number, Company.title(sim)], Sim.LVL_INFO)


## Название газеты и подзаголовок (data/paper.json) — на языке игры.
static func title_str() -> String:
	return L.dt("paper.title", str(Defs.paper.get("title", "Трудовая смена")))


static func subtitle_str() -> String:
	return L.dt("paper.subtitle", str(Defs.paper.get("subtitle", "")))


func _life_item() -> Dictionary:
	if sim.rooms.of_type("canteen").is_empty():
		return {"rubric": L.t("Письма читателей"), "title": L.t("Когда будет столовая?"), "text": L.t("«Обедаем на скамейке, бутерброды в промасленной газете. Нельзя ли по-человечески?» — пишет группа рабочих.")}
	var lines := [L.t("В столовой снова закончился компот. Буфетчица обещает разобраться."), L.t("Новое блюдо в столовой — котлета по-заводски. Отзывы сдержанно положительные."),
		L.t("Столовая просит не уносить ложки. Ложек осталось одиннадцать.")]
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
	return {"pending": pending, "issues": issues, "unread": unread, "no": number, "m0": made0, "s0": scrap0}


func from_dict(d: Dictionary) -> void:
	pending = d.get("pending", [])
	issues = d.get("issues", [])
	unread = bool(d.get("unread", false))
	number = int(d.get("no", 0))
	made0 = int(d.get("m0", 0))
	scrap0 = int(d.get("s0", 0))
