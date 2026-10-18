class_name GameWindow
extends PanelContainer
## Окно поверх игры: заголовок, кнопка закрытия, прокручиваемое содержимое.
## Содержимое перестраивается, только когда меняются данные (по «подписи»).

signal closed()

var sim: Sim
var hud: Node
var kind := ""
var content := VBoxContainer.new()
var tab := ""
var _sig := ""
var _t := 0.0
var scroll := ScrollContainer.new()
var header_extra := HBoxContainer.new()
static var ad_prof := "turner"  ## выбранная профессия для объявления (не сбрасывается при обновлении окна)
static var train_where := "class"  ## где учить: свой класс или учебный центр


## Окна объединены в группы с боковой навигацией (1.7.5): раздел = содержимое «старого» окна и его вкладка.
## [ключ раздела, название, значок, вид содержимого, вкладка содержимого]
const GROUPS := {
	"orders": {"title": "Заказы", "icon": "orders", "secs": [
		["active", "В работе", "orders", "orders", "active"], ["market", "Рынок", "chart_up", "orders", "market"],
		["contracts", "Контракты", "handshake", "orders", "contracts"], ["compet", "Конкуренты", "factory", "orders", "compet"],
		["plan", "План ПДО", "calendar", "orders", "plan"], ["done", "Архив", "log", "orders", "done"]]},
	"prod": {"title": "Производство", "icon": "shop", "secs": [
		["machines", "Станки", "shop", "shop", ""], ["supply", "Металл и расходники", "supply", "supply", "main"],
		["routes", "Маршруты изделий", "orders", "shop", "routes"], ["stash", "Склад оборудования", "objects", "supply", "stash"]]},
	"people": {"title": "Люди", "icon": "staff", "secs": [
		["staff", "Сотрудники", "staff", "staff", "staff"], ["hire", "Найм", "orders", "staff", "hire"],
		["train", "Обучение", "idea", "staff", "train"], ["safety", "Охрана труда", "injury", "staff", "safety"],
		["brig", "Бригады", "crew", "crew", "brig"], ["sched", "График смены", "clock", "crew", "sched"],
		["sec", "Охрана", "thief", "crew", "sec"], ["union", "Профсоюз", "handshake", "crew", "union"],
		["honor", "Доска почёта", "medal", "honor", ""]]},
	"finance": {"title": "Финансы", "icon": "finance", "secs": [
		["summary", "Сводка", "finance", "finance", "summary"], ["charts", "Графики", "chart_up", "finance", "charts"],
		["weeks", "По неделям", "log", "finance", "weeks"], ["loans", "Кредиты и лизинг", "money", "finance", "loans"],
		["insurance", "Страхование", "shield", "finance", "insurance"], ["grants", "Гранты", "medal", "finance", "grants"]]},
	"office": {"title": "Управление", "icon": "office", "secs": [
		["develop", "Развитие и отделы", "develop", "develop", ""], ["research", "Разработки", "research", "research", ""],
		["iso", "ISO 9001", "iso", "market", "iso"], ["advisor", "Главный инженер", "engineer", "market", "advisor"]]},
	"goals": {"title": "Цели", "icon": "goals", "secs": [
		["stage", "Этап роста", "stage_up", "goals", "stage"], ["rating", "Рейтинг", "star", "goals", "rating"],
		["scn", "Сценарий", "scn_garage", "goals", "scn"], ["ach", "Достижения", "medal", "goals", "ach"]]},
	"events": {"title": "События", "icon": "calendar", "secs": [
		["now", "Сейчас", "calendar", "events", "now"], ["insp", "Проверки", "inspect", "events", "insp"],
		["cal", "Календарь", "clock", "events", "cal"], ["hist", "Хроника", "log", "events", "hist"],
		["paper", "Многотиражка", "paper", "paper", ""], ["log", "Журнал", "letter", "log", ""]]},
	"town": {"title": "Город", "icon": "town", "secs": [
		["overview", "Обзор", "town", "town", "overview"], ["dorm", "Общежитие", "bed", "town", "dorm"],
		["canteen", "Столовая и медпункт", "med", "town", "canteen"], ["kg", "Детсад и ДК", "kid", "town", "kg"],
		["radio", "Заводское радио", "radio", "town", "radio"], ["cat", "Кот", "cat", "town", "cat"]]},
}
## Старые названия окон -> [группа, раздел].
const ALIASES := {"develop": ["office", "develop"], "staff": ["people", "staff"], "crew": ["people", "brig"], "shop": ["prod", "machines"], "supply": ["prod", "supply"],
	"research": ["office", "research"], "paper": ["events", "paper"], "log": ["events", "log"]}
## Старые ключи вкладок -> разделы.
const SEC_ALIASES := {"main": "supply", "stage": "stage"}
## Разделы, которые открывает специалист (1.10) или ступень развития (1.11, «dev:…»): раздел -> [отдел, что появится].
const SEC_GATES := {
	"weeks": ["accounting", "Движение денег по неделям и статьям, себестоимость и маржа заказов, прогноз кассы."],
	"insurance": ["dev:fin3", "Страховые полисы оформляет и ведёт бухгалтерия."],
	"contracts": ["dev:mkt3", "Долгие контракты с крупными заказчиками: поставки партиями по графику, цена выше рыночной. И экспортные заказы при репутации от 60."],
	"iso": ["dev:tech3", "Сертификация ISO 9001: аудитор проверяет ОТК, качество, техотдел, СОУТ и инструктажи. Сертификат даёт больше заявок и премиальные цены."],
	"compet": ["sales", "Таблица конкурентов: доли рынка, цены, войны цен. Ценовая политика — демпинг или премиум. На 10% больше заявок."],
	"plan": ["pdo", "План производства с прогнозом сроков, приоритеты заказов, вдвое меньше переналадок, оценка «успеваем?» на рынке."],
	"brig": ["foreman", "Бригады и бригадиры, участки, соцсоревнование между бригадами."],
	"sched": ["foreman", "Свой график смены по 15 минут: планёрка, обед, перерывы, уборка."],
	"honor": ["dev:prod3", "Доска почёта: лучшие рабочие месяца и соцсоревнование."],
	"advisor": ["engineer", "Советы главного инженера, ППР без вашего участия, сводка сетей: мощность, воздух, вода."],
}

var group := ""
var sec := ""
var _secs: Array = []
var sec_title: Label
var sec_info: Label
var help_btn: Label
var _rail: VBoxContainer
var _rail_btns: Dictionary = {}
var _badges: Dictionary = {}


static func resolve(k: String) -> Array:
	if ALIASES.has(k):
		return ALIASES[k]
	if GROUPS.has(k):
		return [k, ""]
	return [k, ""]


func setup(s: Sim, h: Node, k: String, first_sec: String = "", w: float = 1180.0) -> void:
	sim = s
	hud = h
	group = k
	add_theme_stylebox_override("panel", UITheme.sbs(UITheme.BG, UITheme.LINE2, 1, 12, 0, 0, 24, 0.55, 8))
	custom_minimum_size = Vector2(w, 0)
	var gd: Dictionary = GROUPS.get(group, {"title": group, "icon": "log", "secs": [[group, group, "log", group, ""]]})
	_secs = gd["secs"]
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# боковая навигация
	var railp := PanelContainer.new()
	railp.add_theme_stylebox_override("panel", _rail_sb())
	railp.custom_minimum_size = Vector2(212, 0)
	root.add_child(railp)
	_rail = UITheme.vbox(3)
	railp.add_child(_rail)
	# заголовок группы — эмалевая табличка, как на дверях цехов
	_rail.add_child(FactoryUI.plate(str(gd["title"]), str(gd["icon"])))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_rail.add_child(gap)
	for sdef: Array in _secs:
		_rail.add_child(_rail_item(sdef))
	# содержимое
	var main := MarginContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		main.add_theme_constant_override("margin_" + side, 18)
	main.add_theme_constant_override("margin_top", 14)
	main.add_theme_constant_override("margin_bottom", 14)
	root.add_child(main)
	var mv := UITheme.vbox(10)
	main.add_child(mv)
	var top := UITheme.hbox(10)
	sec_title = UITheme.title("", 20)
	top.add_child(sec_title)
	help_btn = UITheme.help("")
	help_btn.visible = false
	top.add_child(help_btn)
	sec_info = UITheme.label("", 13, UITheme.MUTED)
	sec_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(sec_info)
	top.add_child(header_extra)
	top.add_child(UITheme.spacer())
	var cb := UITheme.ghost("×", func() -> void: closed.emit(), "Закрыть (Esc)", UITheme.MUTED)
	cb.add_theme_font_size_override("font_size", 18)
	top.add_child(cb)
	mv.add_child(top)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	mv.add_child(scroll)
	var want := first_sec
	if SEC_ALIASES.has(want):
		want = str(SEC_ALIASES[want])
	if want == "" or not _has_sec(want):
		want = str(_secs[0][0])
	_open_sec(want)


func _rail_sb() -> StyleBoxFlat:
	var s := UITheme.sb(Color("#15171a"), Color(0, 0, 0, 0), 0, 0, 12, 14)
	s.corner_radius_top_left = 12
	s.corner_radius_bottom_left = 12
	return s


func _rail_item(sdef: Array) -> Button:
	var key := str(sdef[0])
	var b := Button.new()
	b.text = str(sdef[1])
	b.icon = Tex.ui(str(sdef[2]))
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 20)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 38)
	var n := UITheme.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 7, 10, 4)
	var hv := UITheme.sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 7, 10, 4)
	var pr := UITheme.sb(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.16), Color(0, 0, 0, 0), 0, 7, 10, 4)
	pr.border_width_left = 3
	pr.border_color = UITheme.ACCENT
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_color_override("font_color", UITheme.MUTED)
	b.add_theme_color_override("font_hover_color", UITheme.TEXT)
	b.add_theme_color_override("font_pressed_color", UITheme.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", UITheme.TEXT)
	b.add_theme_color_override("icon_normal_color", UITheme.MUTED)
	b.add_theme_color_override("icon_pressed_color", UITheme.ACCENT)
	b.add_theme_color_override("icon_hover_pressed_color", UITheme.ACCENT)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(func() -> void:
		_open_sec(key)
		Snd.play("ui_click", -10.0))
	var bd := UITheme.badge("")
	bd.visible = false
	# счётчик — у правого края пункта меню (якоря задаём явно: до раскладки ширина кнопки ещё 0)
	bd.anchor_left = 1.0
	bd.anchor_right = 1.0
	bd.anchor_top = 0.5
	bd.anchor_bottom = 0.5
	bd.offset_left = -30.0
	bd.offset_right = -8.0
	bd.offset_top = -9.0
	bd.offset_bottom = 9.0
	bd.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	b.add_child(bd)
	_badges[key] = bd
	_rail_btns[key] = b
	return b


func _has_sec(key: String) -> bool:
	for sdef: Array in _secs:
		if str(sdef[0]) == key:
			return true
	return false


func _open_sec(key: String) -> void:
	for sdef: Array in _secs:
		if str(sdef[0]) == key:
			sec = key
			kind = str(sdef[3])
			tab = str(sdef[4])
			sec_title.text = str(sdef[1])
	for k in _rail_btns.keys():
		(_rail_btns[k] as Button).set_pressed_no_signal(str(k) == sec)
	scroll.scroll_vertical = 0
	rebuild(true)
	if hud and hud.has_method("_sync_bottom"):
		hud._sync_bottom()


## Подсказка к разделу: объяснение прячется под значок «?» рядом с заголовком.
func _intro(text: String) -> void:
	help_btn.tooltip_text = text
	help_btn.visible = true


## Короткая строка состояния рядом с заголовком раздела.
func _info(text: String) -> void:
	sec_info.text = text


var _tab_group: ButtonGroup = null


var _tab_btns: Dictionary = {}


## Переключить раздел снаружи (по старому ключу вкладки или ключу раздела).
func select_tab(key: String) -> void:
	var k := str(SEC_ALIASES.get(key, key))
	if _has_sec(k):
		_open_sec(k)
		return
	# вкладка внутри содержимого (старые окна без разделов)
	tab = key
	rebuild(true)


## Старый API вкладок: больше не рисует кнопки в заголовке — навигация слева.
func _tabs(_list: Array, _append: bool = false) -> void:
	pass


func set_badge(key: String, n: int) -> void:
	if not _badges.has(key):
		return
	var b: Label = _badges[key]
	b.visible = n > 0
	b.text = str(n)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		# пока открыт выпадающий список (например, выбор профессии) — окно не перестраиваем,
		# иначе список закрывается сам собой
		if _popup_open():
			return
		rebuild(false)


func _popup_open() -> bool:
	for n in find_children("*", "OptionButton", true, false):
		var ob := n as OptionButton
		if ob and ob.get_popup().visible:
			return true
	for n2 in find_children("*", "MenuButton", true, false):
		var mb := n2 as MenuButton
		if mb and mb.get_popup().visible:
			return true
	return false


func rebuild(force: bool) -> void:
	var sig := _signature() + _gate_sig()
	if not force and sig == _sig:
		return
	_sig = sig
	UITheme.clear(content)
	UITheme.clear(header_extra)
	if help_btn:
		help_btn.visible = false
		sec_info.text = ""
	_mark_locks()
	var gate: Array = SEC_GATES.get(sec, [])
	if not gate.is_empty() and _locked(str(gate[0]), str(gate[1])):
		return
	match kind:
		"orders":
			_orders()
		"supply":
			_supply()
		"staff":
			_staff()
		"finance":
			_finance()
		"log":
			_log()
		"shop":
			_shop()
		"office":
			_office()
		"research":
			_research()
		"develop":
			DevTree.build(self)
		"events":
			_events()
		"paper":
			_paper()
		"goals":
			_goals()
		"crew":
			CrewUI.build(self)
		"honor":
			_honor()
		"town":
			TownUI.build(self)
		"market":
			if tab == "iso":
				_iso()
			else:
				_advisor()


## Открыт ли замок раздела: отдел работает или ступень развития открыта.
func _gate_open(g: String) -> bool:
	if g.begins_with("dev:"):
		return sim.dev.on(g.substr(4))
	return sim.office.active(g)


## Состояние отделов (чтобы окно перестроилось, когда отдел заработал).
func _gate_sig() -> String:
	var parts: Array[String] = []
	for k in SEC_GATES.keys():
		parts.append("1" if _gate_open(str(SEC_GATES[k][0])) else "0")
	return "|" + "".join(parts) + sim.dev.cur


## Закрытые разделы в меню слева — приглушённые, с замком.
func _mark_locks() -> void:
	for k in _rail_btns.keys():
		var b := _rail_btns[k] as Button
		var gate: Array = SEC_GATES.get(str(k), [])
		var locked := not gate.is_empty() and not _gate_open(str(gate[0]))
		b.modulate = Color(1, 1, 1, 0.55) if locked else Color(1, 1, 1, 1)
		var g0 := str(gate[0]) if not gate.is_empty() else ""
		if not locked:
			b.tooltip_text = ""
		elif g0.begins_with("dev:"):
			b.tooltip_text = "Нужна ступень развития «%s»" % str(Develop.step_def(g0.substr(4)).get("name", ""))
		else:
			b.tooltip_text = "Нужен отдел «%s»" % str(Defs.departments.get(g0, {}).get("name", ""))


## Раздел закрыт, пока нет специалиста: кого нанять, что построить и что откроется.
func _locked(d: String, what: String) -> bool:
	if _gate_open(d):
		return false
	if d.begins_with("dev:"):
		content.add_child(_dev_lock_card(d.substr(4), what))
	else:
		content.add_child(_lock_card(d, what))
	return true


## Раздел закрыт ступенью развития: что откроется, что для неё нужно, кнопка в «Развитие».
func _dev_lock_card(id: String, what: String) -> PanelContainer:
	var sd := Develop.step_def(id)
	var c := UITheme.card(18, Color("#1c1f24"), UITheme.LINE)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.vbox(10)
	c.add_child(v)
	var hh := UITheme.hbox(10)
	hh.add_child(_icon(Tex.ui("lock"), 30))
	var tv := UITheme.vbox(0)
	tv.add_child(UITheme.label("Нужна ступень развития «%s»" % str(sd.get("name", id)), 17, UITheme.TEXT, UITheme.f_semi))
	tv.add_child(UITheme.label("ветка «%s» · %s · %d %s" % [str(Develop.branch_of(id).get("name", "")), Defs.money_str(float(sd.get("cost", 0.0))), int(sd.get("days", 1)), Defs.plural(int(sd.get("days", 1)), "день", "дня", "дней")], 12, UITheme.MUTED))
	hh.add_child(tv)
	v.add_child(hh)
	v.add_child(UITheme.para("Откроется: " + what, 13))
	var st := sim.dev.status(id)
	if st == "idle":
		var holder := str(sd.get("holder", ""))
		v.add_child(_cl("Ступень открыта, но не работает: нет человека в отделе «%s»." % str(Defs.departments.get(holder, {}).get("name", holder)), 13, UITheme.WARN))
	elif st == "busy":
		v.add_child(_cl("Директор уже занимается: осталось %.1f дн." % sim.dev.days_left(), 13, UITheme.ACCENT))
	else:
		var why := sim.dev.block_reason(id)
		v.add_child(_cl(("Можно начать." if why == "" else why), 13, UITheme.GOOD if why == "" else UITheme.WARN))
	v.add_child(UITheme.primary("Открыть «Развитие»", func() -> void:
		if _has_sec("develop"):
			_open_sec("develop")
			return
		hud.open_window("office")
		if hud.win:
			hud.win.select_tab("develop"), "Управление → Развитие"))
	return c


func _lock_card(d: String, what: String, compact: bool = false) -> PanelContainer:
	var dd: Dictionary = Defs.departments.get(d, {})
	var c := UITheme.card(10 if compact else 18, Color("#1c1f24"), UITheme.LINE)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.vbox(6 if compact else 10)
	c.add_child(v)
	var hh := UITheme.hbox(10)
	hh.add_child(_icon(Tex.ui("lock"), 22 if compact else 30))
	var tv := UITheme.vbox(0)
	tv.add_child(UITheme.label(("Нужен отдел «%s»" % str(dd.get("name", d))), 14 if compact else 17, UITheme.TEXT, UITheme.f_semi))
	var prof := str(dd.get("prof", ""))
	tv.add_child(UITheme.label("специалист: %s" % Worker.lc(str(Worker.PROF_NAMES.get(prof, prof))), 12, UITheme.MUTED))
	hh.add_child(tv)
	v.add_child(hh)
	var p := UITheme.para("Откроется: " + what, 13 if not compact else 12)
	v.add_child(p)
	if not sim.progress.dept_open(d):
		v.add_child(UITheme.label(sim.progress.dept_lock_text(d), 13, UITheme.WARN))
		return c
	var rs := sim.office.room_status(d)
	v.add_child(_cl("Кабинет: " + str(rs[1]), 12, [UITheme.BAD, UITheme.WARN, UITheme.GOOD][int(rs[0]) + 1]))
	var staff := sim.office.staff(d)
	v.add_child(_cl(("Сотрудник: ✓ " + staff[0].full_name() + ("" if sim.office.desk_k(staff[0]) > 0.0 else " — нет своего стола")) if not staff.is_empty() else "Сотрудник: × нет", 12, UITheme.GOOD if not staff.is_empty() else UITheme.BAD))
	var row := UITheme.hbox(8)
	if staff.is_empty():
		row.add_child(UITheme.primary("Найти: %s · %s" % [Worker.lc(str(Worker.PROF_NAMES.get(prof, prof))), Defs.money_str(sim.ad_price(prof))], func() -> void:
			var err := sim.post_ad(prof)
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
				return
			hud.open_window("staff")
			if hud.win:
				hud.win.select_tab("hire"), "Объявление по профессии — откроется найм"))
	if int(rs[0]) < 1:
		var room := str(dd.get("room", ""))
		row.add_child(UITheme.button("Построить кабинет", func() -> void:
			closed.emit()
			hud.open_rooms_type(room), "Откроется каталог помещений с этим типом"))
	if row.get_child_count() > 0:
		v.add_child(row)
	return c


func _signature() -> String:
	match kind:
		"orders":
			var parts: Array[String] = [tab]
			for o: Dictionary in sim.orders.list:
				parts.append("%d%s%d%d" % [int(o["id"]), str(o["status"]), int(o["shipped"]), int(o.get("prio", 0))])
			for p in Defs.products.keys():
				parts.append(str(sim.ok_in_storage(p)))
			parts.append("%d|%d|%d|%d|%d|%d" % [sim.sales.log.size(), sim.sales.risk, sim.sales.margin_i, sim.sales.off.size(), sim.day(), sim.sales.queue.size()])
			parts.append(sim.market.policy + str(int(sim.market.share * 1000.0)) + str(sim.market.alive_comps().size()))
			for c: Dictionary in sim.sales.contracts:
				parts.append("%d%s%d%d" % [int(c["id"]), str(c["status"]), int(c["done_w"]), int(c["fails"])])
			return ",".join(parts)
		"supply":
			var s2: Array[String] = []
			for m in Defs.materials.keys():
				s2.append("%d/%d" % [sim.free_material(m), sim.material_total(m)])
			s2.append(str(sim.supply.size()))
			s2.append(str(sim.cons_supply.size()))
			for c in Defs.consumables.keys():
				s2.append(str(int(float(sim.cons.get(c, 0.0)))))
			s2.append(str(int(sim.money / 1000)))
			s2.append(sim.office.supplier)
			s2.append(str(sim.supply_reserve))
			s2.append(str(sim.logi.equip.size()))
			s2.append(str(sim.item_rev))
			return ",".join(s2)
		"shop":
			var s5: Array[String] = [str(sim.ppr), str(sim.thing_rev)]
			for m in sim.things_of("machine"):
				s5.append("%d%s%d%d%s%s%d" % [m.id, m.product, m.job_step, int(m.condition), str(m.broken), str(m.enabled), int(m.working)])
			for c in Defs.consumables.keys():
				s5.append(str(int(float(sim.cons.get(c, 0.0)))))
			s5.append(str(sim.cons_supply.size()))
			s5.append(str(sim.item_rev / 10))
			return ",".join(s5)
		"staff":
			var s3: Array[String] = [tab, str(sim.candidates.size()), str(sim.candidates.hash()), train_where]
			var tr := sim.training
			s3.append("%d|%d|%d|%s|%d|%d|%d" % [tr.courses.size(), tr.class_seats(), tr.tb_day, str(tr.tb_active()), int(tr.ptu), tr.practicants().size(), int(sim.money / 1000.0)])
			for c: Dictionary in tr.courses:
				s3.append("%d:%d" % [int(c["wid"]), int(float(c["done"]) / 30.0)])
			var eg := sim.eng
			s3.append("%s|%d|%d|%d|%s" % [str(eg.sout_busy()), eg.sout.size(), eg.ppe_stock(), eg.cabinets().size(), str(eg.milk_on)])
			s3.append("%d|%d|%s" % [sim.crew.cases.size(), sim.crew.safe_days(), str(sim.crew.cases.slice(0, 3))])
			for w in sim.workers:
				s3.append("%d%s%d%d%d%d%d%d" % [w.id, w.activity if tab != "train" and tab != "safety" else "", int(w.mood), w.shift, w.mentor, w.skill(w.main_skill()), int(w.ppe / 10.0), w.workplace])
			return ",".join(s3)
		"finance":
			var gs := ""
			if tab == "grants":
				for a: Dictionary in sim.grants.active:
					for goal: Dictionary in Grants.def(str(a["id"])).get("goals", []):
						gs += "1" if sim.grants.goal_ok(goal, a) else "0"
				gs += "|%d|%d|%d" % [sim.grants.active.size(), sim.grants.done.size(), sim.day()]
			return "%s|%d|%d|%d|%s|%s|%d|%s|%d" % [tab, sim.ledger.size(), int(sim.money), sim.office.loans.size(), gs, str(sim.market.insurance), sim.market.leases.size(), str(sim.market.leasing_on), sim.market.hist.size()]
		"office":
			var s6: Array[String] = [str(sim.office.policies), sim.office.supplier, str(sim.rooms.list.size()), str(sim.thing_rev)]
			for w in sim.workers:
				if w.is_itr():
					s6.append("%d%d%s" % [w.id, w.desk_id, w.activity])
			return ",".join(s6)
		"research":
			return "%s|%s|%d|%s|%s|%d" % [sim.office.research_cur, str(sim.office.research_done), int(float(sim.office.research_pts.get(sim.office.research_cur, 0.0)) * 10.0), str(sim.office.active("tech")), ResearchTree.sel, sim.office.staff("tech").size()]
		"develop":
			var dsig: Array[String] = [DevTree.sel, sim.dev.cur, str(sim.dev.done), str(int(sim.dev.progress01() * 100.0)), str(int(sim.money / 20000.0)), str(sim.progress.stage), str(sim.rooms.list.size()), str(sim.workers.size()), sim.office.research_cur, str(sim.office.research_done.size())]
			for dk in Defs.departments.keys():
				dsig.append("1" if sim.office.active(str(dk)) else "0")
			return ",".join(dsig)
		"log":
			return str(sim.events.size()) + (str(sim.events[0]) if not sim.events.is_empty() else "")
		"events":
			var st := sim.story
			return "%s|%d|%s|%d|%d|%d|%d|%d|%d|%d|%s" % [tab, st.letters.size(), str(st.strike.get("active", false)), st.fires.size(), sim.inspect.queue.size(),
				sim.inspect.marks.size(), int(sim.minute / 60.0), st.mods.size(), st.archive.size(), int(sim.inspect.busy()), str(sim.season.sanding) + str(st.guard) + st.mode]
		"paper":
			return "%s|%d" % [tab, sim.paper.issues.size()]
		"crew":
			return CrewUI.sig(self)
		"town":
			return TownUI.sig(self)
		"market":
			var mk := sim.market
			var ms: Array[String] = [tab, str(mk.iso), str(mk.memo_on), str(sim.day()), str(int(sim.minute / 240.0)), str(sim.money > 120000.0)]
			for r: Array in mk.iso_reqs():
				ms.append(str(r[1]))
			return ",".join(ms)
		"honor":
			var hs: Array[String] = [str(sim.honor_log.size()), str(sim.day())]
			for w in sim.workers:
				hs.append("%d:%d" % [w.id, w.week_score])
			return ",".join(hs)
		"goals":
			var pg := sim.progress
			var gs: Array[String] = [tab, str(pg.stage), str(pg.stars), str(pg.ooo), str(pg.roof_leak), str(int(pg.arrears_total())), str(int(sim.minute / 120.0))]
			for g: Dictionary in pg.stage_goals() + pg.scenario_goals() + (pg.stage_choice().get("list", []) as Array):
				gs.append(str(pg.goal_state(g)))
			return ",".join(gs)
	return ""


func _row() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG2, UITheme.LINE, 1, 8, 12, 8))
	content.add_child(p)
	return p


## Заголовок таблицы: [[текст, ширина (-1 — растянуть)], …].
func _thead(cols: Array, parent: Control = null) -> void:
	var h := UITheme.hbox(10)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_child(h)
	for c: Array in cols:
		var l := UITheme.caption(str(c[0]))
		if float(c[1]) < 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size = Vector2(float(c[1]), 0)
		if c.size() > 2:
			l.horizontal_alignment = int(c[2])
		h.add_child(l)
	(parent if parent else content).add_child(m)


## Строка таблицы: ячейки [[Control, ширина]], щелчок по строке — cb (если задан).
func _trow(cells: Array, cb: Callable = Callable(), height: float = 40.0, tip: String = "", parent: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	var n := UITheme.sb(UITheme.BG2, Color(0, 0, 0, 0), 0, 7, 10, 3)
	p.add_theme_stylebox_override("panel", n)
	p.custom_minimum_size = Vector2(0, height)
	p.tooltip_text = tip
	if cb.is_valid():
		var hv := UITheme.sb(UITheme.BG3, UITheme.LINE2, 1, 7, 10, 3)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.mouse_entered.connect(func() -> void: p.add_theme_stylebox_override("panel", hv))
		p.mouse_exited.connect(func() -> void: p.add_theme_stylebox_override("panel", n))
		p.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				cb.call())
	var h := UITheme.hbox(10)
	p.add_child(h)
	for c: Array in cells:
		var ctl: Control = c[0]
		var w := float(c[1])
		if w < 0:
			ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			ctl.size_flags_horizontal = Control.SIZE_FILL
			ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, w)
		ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ctl)
	(parent if parent else content).add_child(p)
	return p


## Ячейка-текст: одна строка с обрезкой.
func _cl(text: String, size: int = 13, col: Color = UITheme.TEXT, font: Font = null, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UITheme.label(text, size, col, font)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.horizontal_alignment = align
	l.tooltip_text = text if text.length() > 24 else ""
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Две строки в одной ячейке: основная и пояснение.
func _cl2(main: String, sub: String, col: Color = UITheme.TEXT, sub_col: Color = UITheme.MUTED, main_size: int = 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -1)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 1.21: иначе в строке HBox подпись сжималась до нуля
	v.add_child(_cl(main, main_size, col, UITheme.f_semi))
	if sub != "":
		v.add_child(_cl(sub, 12, sub_col))
	return v


## Кнопка в заголовке раздела (справа от названия).
func _hbtn(text: String, cb: Callable, tip: String = "", primary: bool = false) -> Button:
	var b := UITheme.primary(text, cb, tip) if primary else UITheme.button(text, cb, tip)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_extra.add_child(b)
	return b


## Сетка карточек на всю ширину.
func _cards(cols: int = 2) -> GridContainer:
	var g := UITheme.grid(cols, 10, 10)
	content.add_child(g)
	return g


## Карточка в сетке: заголовок (+ значок «?»), внутри — вертикальный список.
func _card_in(parent: Control, title: String = "", help: String = "") -> VBoxContainer:
	var c := UITheme.card(12)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	var v := UITheme.vbox(6)
	c.add_child(v)
	if title != "":
		var h := UITheme.hbox(6)
		h.add_child(UITheme.label(title, 15, UITheme.TEXT, UITheme.f_semi))
		if help != "":
			h.add_child(UITheme.help(help))
		v.add_child(h)
	return v


func _icon(tex: Texture2D, sz: float = 40.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(sz, sz)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


# ---------------------------------------------------------------- заказы

func _orders() -> void:
	match tab:
		"active":
			_sales_head()
			var act := sim.orders.by_status(["active", "ready", "shipping"])
			if act.is_empty():
				content.add_child(UITheme.empty("Заказов в работе нет. Сбыт возьмёт подходящие завтра утром — или посмотрите в «Рынке», почему отказывает."))
				return
			_thead([["", 36], ["Заказ", -1], ["Готовность", 140], ["Срок", 190], ["Приоритет", 150], ["Сумма", 100, HORIZONTAL_ALIGNMENT_RIGHT], ["", 74]])
			for o2: Dictionary in act:
				_active_row(o2)
		"market":
			_market()
		"contracts":
			_contracts()
		"compet":
			_compet()
		"plan":
			_plan()
		"done":
			var done := sim.orders.by_status(["done", "failed"])
			done.reverse()
			var ok := 0
			for o0: Dictionary in done:
				if str(o0["status"]) == "done":
					ok += 1
			_info("выполнено %d · сорвано %d" % [ok, done.size() - ok])
			if done.is_empty():
				content.add_child(UITheme.empty("Пока пусто."))
			else:
				_thead([["", 32], ["Заказ", -1], ["Итог", 230], ["Оплата", 120, HORIZONTAL_ALIGNMENT_RIGHT]])
			for o3: Dictionary in done.slice(0, 40):
				# итог — штампом, как в журнале ОТК
				var stamp: Stamp
				if str(o3["status"]) == "done":
					var late := int(o3.get("late_days", 0))
					stamp = _stamp("ВЫПОЛНЕН" if late == 0 else "ОПОЗДАНИЕ %d ДН." % late, STAMP_INK if late == 0 else STAMP_RED, 140.0)
				else:
					stamp = _stamp("СОРВАН", STAMP_RED, 100.0)
				var sc := Control.new()
				sc.custom_minimum_size = Vector2(230, 26)
				sc.add_child(stamp)
				_trow([[_icon(Tex.item(str(o3["product"])), 26), 32], [_cl(sim.orders.short(o3), 13), -1], [sc, 230],
					[_cl(Defs.money_str(float(o3.get("paid", 0))) if str(o3["status"]) == "done" else "—", 13, UITheme.MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT), 120]], Callable(), 34.0)
			var lost := sim.sales.log.filter(func(e: Dictionary) -> bool: return not bool(e["ok"]))
			lost.reverse()
			content.add_child(UITheme.caption("Отказы сбыта за две недели"))
			if lost.is_empty():
				content.add_child(UITheme.label("Отказов не было.", 13, UITheme.MUTED))
			for e: Dictionary in lost.slice(0, 30):
				_trow([[_cl("день %d" % int(e["day"]), 12, UITheme.MUTED), 64], [_cl("%s × %d — %s" % [Defs.product_name(str(e["p"])), int(e["qty"]), str(e.get("client", ""))], 13), -1],
					[_cl(str(e["why"]), 12, UITheme.WARN), 320], [_cl(Defs.money_str(float(e["sum"])), 12, UITheme.MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT), 100]], Callable(), 30.0)


## Шапка «В работе»: стратегия сбыта и итоги недели — три карточки в ряд.
func _sales_head() -> void:
	var sl := sim.sales
	var s := sl.summary(7)
	var li := sim.office.load_info()
	_info("в работе %d из %d · загрузка ~%.1f раб. дн. · репутация %d" % [sim.orders.active_count(), sim.orders.max_active(), float(li[0]), int(sim.reputation)])
	_intro("Отдел сбыта сам берёт заказы, которые завод успеет сделать с выгодой, и сам закупает металл. Ваше дело — мощности, ассортимент и крупные контракты. Приоритет заказа: станки и рабочие сначала делают детали для срочных.")
	var g := _cards(3)
	var a := _card_in(g, "Стратегия сбыта", "С запасом — срывов почти нет, но и заказов меньше. Впритык — больше заказов, но любая поломка ведёт к просрочке (ступень «Впритык» в «Развитии»). Маржа — не брать заказы дешевле себестоимости плюс этот процент.")
	var rh := UITheme.hbox(6)
	rh.add_child(UITheme.label("Брать:", 12, UITheme.MUTED))
	var risk_items: Array = []
	for i in 3:
		risk_items.append([str(i), str(Sales.RISK_NAMES[i])])
	var seg := UITheme.segmented(risk_items, str(sl.risk), func(k: String) -> void:
		if k == "2" and not sim.dev.on("plan3"):
			hud.toast("«Впритык» открывает ступень развития «Впритык» (Управление → Развитие), её держит ПДО.", Sim.LVL_INFO)
			rebuild(true)
			return
		sl.risk = int(k)
		rebuild(true))
	rh.add_child(seg)
	a.add_child(rh)
	var mh := UITheme.hbox(6)
	mh.add_child(UITheme.label("Маржа от:", 12, UITheme.MUTED))
	var m_items: Array = []
	for j in Sales.MARGINS.size():
		m_items.append([str(j), "%d%%" % int(round(float(Sales.MARGINS[j]) * 100.0))])
	mh.add_child(UITheme.segmented(m_items, str(sl.margin_i), func(k: String) -> void:
		sl.margin_i = int(k)
		rebuild(true)))
	a.add_child(mh)
	# 1.20: можно запретить сбыту брать новые заказы (в долгах он и сам не берёт)
	var pz_h := UITheme.hbox(6)
	pz_h.add_child(UITheme.label("Новые заказы:", 12, UITheme.MUTED))
	pz_h.add_child(UITheme.segmented([["on", "Брать"], ["off", "Не брать"]], "off" if sl.paused else "on", func(k: String) -> void:
		sl.paused = k == "off"
		hud.toast("Сбыт не берёт новых заказов, пока не разрешите." if sl.paused else "Сбыт снова принимает заказы.", Sim.LVL_INFO, 3.0)
		rebuild(true)))
	a.add_child(pz_h)
	if sim.money < 0.0:
		a.add_child(UITheme.para("Завод в долгах — сбыт новых заказов не берёт, пока касса в минусе.", 12, UITheme.BAD))
	var b := _card_in(g, "За 7 дней")
	b.add_child(_cl("взято %d %s на %s" % [int(s["taken"]), Defs.plural(int(s["taken"]), "заказ", "заказа", "заказов"), Defs.money_str(float(s["taken_sum"]))], 13, UITheme.GOOD))
	b.add_child(_cl("отказано %d на %s" % [int(s["lost"]), Defs.money_str(float(s["lost_sum"]))], 13, UITheme.WARN if float(s["lost_sum"]) > 0.0 else UITheme.MUTED))
	if not sl.queue.is_empty():
		b.add_child(_cl("в рассмотрении %d на %s" % [sl.queue.size(), Defs.money_str(sl.queue_sum())], 13, UITheme.INFO))
	var c := _card_in(g, "Узкое место")
	if float(li[0]) >= 98.0:
		var an := sl.absent_note(str(li[1]))
		c.add_child(UITheme.para(an if an != "" else "некому работать на переделе «%s»" % Defs.process_name(str(li[1])), 13, UITheme.BAD))
	elif str(s["top"]) != "":
		var pr := str(s["top"])
		var no_eq := not sim.prod.processes_available().has(pr)
		c.add_child(UITheme.para("«%s» — %s, упущено %s" % [Defs.process_name(pr), "нет оборудования" if no_eq and pr != "qc" else "не успевает", Defs.money_str(float(s["top_sum"]))], 13, UITheme.WARN))
		c.add_child(UITheme.ghost("Подробнее в «Рынке» →", func() -> void: select_tab("market")))
	elif float(li[0]) > 0.3:
		c.add_child(UITheme.para(Defs.process_name(str(li[1])), 13, UITheme.TEXT))
	else:
		c.add_child(UITheme.label("нет — мощности свободны", 13, UITheme.GOOD))
	var pend := sim.orders.by_status(["offer"]).size() + sl.by_state(["offer"]).size()
	if pend > 0:
		var ph := UITheme.hbox(8)
		ph.add_child(UITheme.chip("ждут решения: %d" % pend, UITheme.ACCENT))
		ph.add_child(UITheme.ghost("Контракты и тендеры →", func() -> void: select_tab("contracts"), "", UITheme.ACCENT))
		content.add_child(ph)


func _market() -> void:
	var sl := sim.sales
	var s := sl.summary(7)
	_info("заявки за 7 дней · цены меняются по понедельникам")
	_intro("Заявки заказчиков за неделю по изделиям вашего профиля. Снимите изделие с ассортимента — сбыт перестанет его брать, и станки займутся выгодным. × — передел, для которого нет оборудования.")
	if float(s["lost_sum"]) > 0.0:
		var parts: Array[String] = []
		var procs: Array = (s["by_proc"] as Dictionary).keys()
		procs.sort_custom(func(a: String, b: String) -> bool: return float(s["by_proc"][a]) > float(s["by_proc"][b]))
		for pr in procs.slice(0, 3):
			parts.append("%s %s" % [Defs.process_name(str(pr)).to_lower(), Defs.money_str(float(s["by_proc"][pr]))])
		content.add_child(UITheme.para("Упущено за неделю: %s.%s" % [Defs.money_str(float(s["lost_sum"])), (" По переделам: " + ", ".join(parts) + ".") if not parts.is_empty() else ""], 13, UITheme.WARN))
	var avail := sim.prod.processes_available()
	var prods: Array = []
	for k in sim.progress.products():
		if Defs.products.has(str(k)):
			prods.append(str(k))
	prods.sort_custom(func(a: String, b: String) -> bool:
		var ma := sl.missing(a).is_empty()
		var mb := sl.missing(b).is_empty()
		if ma != mb:
			return ma
		return float(sl.demand(a)[1]) > float(sl.demand(b)[1]))
	_thead([["", 36], ["Изделие и маршрут", -1], ["Цена за шт.", 170], ["Спрос за неделю", 170], ["Мощность", 120], ["", 120]])
	for p: String in prods:
		var pd: Dictionary = Defs.products[p]
		var tr := sl.trend(p)
		var pr: Array = pd.get("price", [0, 0])
		var ix := sl.price_index(p) * (0.9 + sim.reputation / 500.0) * sim.progress.price_k()
		var seen := {}
		var todo: Array[String] = [p]
		var steps: Array[String] = []
		while not todo.is_empty():
			var q: String = todo.pop_front()
			for c in Defs.components(q).keys():
				todo.append(str(c))
			for o: Dictionary in Defs.route(q):
				var op := str(o["op"])
				if not seen.has(op):
					seen[op] = true
					steps.append(Defs.process_name(op) + ("" if avail.has(op) else " ×"))
		var miss := sl.missing(p)
		var sub := " → ".join(steps)
		if not sim.office.unlocked(pd):
			sub = "нужна разработка техотдела"
		var dm := sl.demand(p)
		var capw := sl.capacity_week(p) if miss.is_empty() else 0.0
		var price_txt := "%s–%s" % [Defs.money_str(float(pr[0]) * ix), Defs.money_str(float(pr[1]) * ix)]
		var trend_txt := ("▲ +%d%%" if tr > 0.0 else "▼ %d%%") % int(round(tr * 100.0)) if absf(tr) >= 0.01 else "без изменений"
		var on := sl.in_assortment(p)
		var tb := UITheme.small("в ассортименте" if on else "снято", func() -> void:
			if sl.off.has(p):
				sl.off.erase(p)
			else:
				sl.off[p] = true
			rebuild(true), "Снять с ассортимента или вернуть: сбыт берёт заказы только на изделия в ассортименте")
		if on:
			tb.add_theme_stylebox_override("normal", UITheme.sb(Color("#2b4130"), Color("#4f7a4a"), 1, 6, 8, 2))
			tb.add_theme_color_override("font_color", UITheme.GOOD)
		# РП-14: маржа — со ступенью «Себестоимость», «успеваем?» — с диспетчером ПДО
		var mg_txt := ""
		if sim.dev.on("fin2"):
			var mid := (float(pr[0]) + float(pr[1])) * 0.5 * ix
			var mg := sim.office.margin({"product": p, "price": mid})
			mg_txt = " · маржа %d%%" % int(round(mg * 100.0))
		var cap_sub := ""
		var cap_col := UITheme.MUTED
		if sim.office.active("pdo") and capw > 0.0:
			var qr: Array = pd.get("qty", [5, 15])
			var qty := int((int(qr[0]) + int(qr[1])) / 2)
			var lead := float(sim.orders.make_lead(p, qty))
			var ld := sim.office.load_days(p, qty)
			cap_sub = "успеваем" if ld <= lead * 0.75 else ("впритык" if ld <= lead else "не успеваем")
			cap_col = UITheme.GOOD if ld <= lead * 0.75 else (UITheme.WARN if ld <= lead else UITheme.BAD)
		_trow([[_icon(Tex.item(p), 30), 36], [_cl2(Defs.product_name(p), sub, UITheme.TEXT, UITheme.BAD if not miss.is_empty() else UITheme.INFO), -1],
			[_cl2(price_txt, trend_txt + mg_txt, UITheme.GOOD, UITheme.GOOD if tr > 0.0 else (UITheme.BAD if tr < 0.0 else UITheme.MUTED), 13), 170],
			[_cl2("%d шт. на %s" % [int(dm[0]), Defs.money_str(float(dm[1]))], ("взято %d шт." % int(dm[2])) if int(dm[0]) > 0 else "", UITheme.TEXT if int(dm[0]) > 0 else UITheme.MUTED, UITheme.MUTED, 13), 170],
			[_cl2(("~%d в нед." % int(capw)) if capw > 0.0 else ("нет людей" if miss.is_empty() else "нет станков"), cap_sub, UITheme.TEXT if capw > 0.0 else UITheme.MUTED, cap_col, 13), 120], [tb, 120]], Callable(), 46.0)


func _contracts() -> void:
	var sl := sim.sales
	var offers := sl.by_state(["offer"])
	var tenders := sim.orders.by_status(["offer"])
	_info("предложений %d · действующих контрактов %d из %d" % [offers.size() + tenders.size(), sl.by_state(["wait", "active"]).size(), sl.max_contracts()])
	_intro("Крупные клиенты предлагают контракт раз в одну-две недели (если репутация от 35). Одновременно — до %d %s, с ростом завода больше. С этапа «Среднее предприятие» приходят тендеры: экспорт и госзаказ." % [sl.max_contracts(), Defs.plural(sl.max_contracts(), "контракта", "контрактов", "контрактов")])
	if offers.is_empty() and tenders.is_empty():
		content.add_child(UITheme.empty("Новых предложений нет."))
	if not offers.is_empty() or not tenders.is_empty():
		content.add_child(UITheme.caption("Ждут решения"))
		var g := _cards(2)
		for c: Dictionary in offers:
			var v := _card_in(g)
			var th := UITheme.hbox(8)
			th.add_child(_icon(Tex.item(str(c["product"])), 36))
			th.add_child(_cl2("%s × %d в неделю" % [Defs.product_name(str(c["product"])), int(c["per_week"])], str(c["client"])))
			th.add_child(UITheme.chip("контракт", UITheme.INFO))
			v.add_child(th)
			v.add_child(_cl("%s за шт. (+%d%% к рынку) · %d %s · всего %s" % [Defs.money_str(float(c["price"])), int(round(float(c["prem"]) * 100.0)), int(c["weeks"]), Defs.plural(int(c["weeks"]), "неделя", "недели", "недель"), Defs.money_str(float(c["price"]) * int(c["per_week"]) * int(c["weeks"]))], 13, UITheme.GOOD))
			v.add_child(_cl("первая партия — в неделю со дня %d · ответить до дня %d" % [int(c["start"]), int(float(c["until"]) / 1440.0) + 1], 12, UITheme.MUTED))
			var ok := sl.missing(str(c["product"])).is_empty() and sl.capacity_week(str(c["product"])) >= float(int(c["per_week"]))
			v.add_child(UITheme.para(sl.assess(c), 12, UITheme.GOOD if ok else UITheme.WARN))
			var bh := UITheme.hbox(8)
			var cid := int(c["id"])
			bh.add_child(UITheme.primary("Подписать", func() -> void:
				var err := sl.sign(cid)
				if err != "":
					hud.toast(err, Sim.LVL_WARN)
				rebuild(true)))
			bh.add_child(UITheme.button("Отказаться", func() -> void:
				sl.decline(cid)
				rebuild(true)))
			v.add_child(bh)
		for o: Dictionary in tenders:
			_offer_row(o, g)
	var act := sl.by_state(["wait", "active"])
	if not act.is_empty():
		content.add_child(UITheme.caption("Действующие контракты"))
	for c2: Dictionary in act:
		var st := ""
		if str(c2["status"]) == "wait":
			st = "подписан, первая партия — в неделю со дня %d (через %d дн.)" % [int(c2["start"]), maxi(0, int(c2["start"]) - sim.day())]
		else:
			st = "партия %d из %d · сдано %d · сорвано %d" % [int(c2["week_i"]), int(c2["weeks"]), int(c2["done_w"]), int(c2["fails"])]
			var cur := sim.orders.get_order(int(c2["order"]))
			if not cur.is_empty() and ["active", "ready", "shipping"].has(str(cur["status"])):
				st += " · срок партии %s" % sim.orders.deadline_str(cur)
		_trow([[_icon(Tex.item(str(c2["product"])), 28), 34], [_cl2("%s × %d в неделю по %s" % [Defs.product_name(str(c2["product"])), int(c2["per_week"]), Defs.money_str(float(c2["price"]))], str(c2["client"])), 360],
			[_cl(st, 13, UITheme.BAD if int(c2["fails"]) > 0 else UITheme.INFO), -1]], Callable(), 44.0)
	var fin := sl.by_state(["done", "broken"])
	if not fin.is_empty():
		content.add_child(UITheme.caption("Завершённые"))
		for c3: Dictionary in fin:
			content.add_child(_cl("%s: %s — %s" % [str(c3["client"]), Defs.product_name(str(c3["product"])), "выполнен" if str(c3["status"]) == "done" else "расторгнут"], 13, UITheme.GOOD if str(c3["status"]) == "done" else UITheme.BAD))


func _offer_row(o: Dictionary, parent: Control = null) -> void:
	var host: Control = parent if parent else _cards(2)
	var v := _card_in(host)
	var p := str(o["product"])
	var th := UITheme.hbox(8)
	th.add_child(_icon(Tex.item(p), 36))
	th.add_child(_cl2("%s × %d" % [Defs.product_name(p), int(o["qty"])], str(o["client"])))
	var kind := str(o.get("kind", ""))
	if kind != "" or bool(o.get("hot", false)):
		th.add_child(UITheme.chip(str(OrderBook.KIND_NAMES.get(kind, "Горящий")).to_lower(), UITheme.BAD if kind == "state" else (UITheme.INFO if kind == "export" else UITheme.WARN)))
	v.add_child(th)
	if kind == "state":
		v.add_child(UITheme.para("Аванс 50% при принятии. Срыв срока — возврат аванса и неустойка. Сдача военной приёмке без брака.", 12, UITheme.WARN))
	elif kind == "export":
		v.add_child(UITheme.para("Экспорт: цена выше, но любой брак в партии вернётся рекламацией.", 12, UITheme.INFO))
	var total := float(o["price"]) * int(o["qty"])
	var lead := int(o.get("lead", 3))
	v.add_child(_cl("%s за шт. · всего %s · срок %d %s" % [Defs.money_str(float(o["price"])), Defs.money_str(total), lead, Defs.plural(lead, "рабочий день", "рабочих дня", "рабочих дней")], 13, UITheme.GOOD))
	if sim.dev.on("fin2"):
		var uc := sim.office.unit_cost(p)
		var mg := sim.office.margin(o)
		v.add_child(_cl("себестоимость ~%s/шт · маржа ~%d%%%s · %s" % [Defs.money_str(uc), int(round(mg * 100.0)), " — убыточный!" if mg < 0.0 else "", _inputs_text(p, int(o["qty"]))], 12, UITheme.GOOD if mg >= 0.25 else (UITheme.WARN if mg >= 0.08 else UITheme.BAD)))
	else:
		v.add_child(_cl("%s · маржа — ступень «Себестоимость»" % _inputs_text(p, int(o["qty"])), 12, UITheme.MUTED))
	var miss := _missing_processes(p)
	if miss.is_empty():
		var li := sim.office.load_info(p, int(o["qty"]))
		var dd := float(li[0])
		var fits := dd <= float(lead) * 0.85
		var tight := dd <= float(lead)
		v.add_child(_cl("загрузка ~%.1f раб. дн. (узкое место — %s): %s" % [dd, Defs.process_name(str(li[1])).to_lower(), "успеваем" if fits else ("впритык" if tight else "не успеем без найма")], 12, UITheme.GOOD if fits else (UITheme.WARN if tight else UITheme.BAD)))
	else:
		v.add_child(UITheme.para("Нет оборудования: " + ", ".join(miss) + " — принять можно, но сделать не получится", 12, UITheme.BAD))
	var bh := UITheme.hbox(8)
	bh.add_child(UITheme.primary("Принять", func() -> void:
		var err := sim.orders.accept(int(o["id"]), true)
		if err != "":
			hud.toast(err, Sim.LVL_WARN)
		rebuild(true)))
	bh.add_child(UITheme.button("Отказаться", func() -> void:
		sim.orders.decline(int(o["id"]))
		rebuild(true)))
	v.add_child(bh)


## Что нужно на заказ: металл или детали для сборки.
func _inputs_text(p: String, qty: int) -> String:
	if Defs.is_assembly(p):
		var parts: Array[String] = []
		var comps := Defs.components(p)
		for c in comps.keys():
			parts.append("%s ×%d" % [Defs.product_name(str(c)), int(comps[c]) * qty])
		return "Собирается из своих деталей: " + ", ".join(parts)
	var mat := str(Defs.products[p].get("material", ""))
	var mq := Defs.mat_qty(p)
	var mat_cost := float(Defs.materials.get(mat, {}).get("price", 0)) * qty * mq
	return "Металл: %s%s, ~%s · свободно на складе %d" % [Defs.material_name(mat), (" (%d шт. на изделие)" % mq) if mq > 1 else "", Defs.money_str(mat_cost), sim.free_material(mat)]


## Каких процессов не хватает на заводе для изделия (с учётом деталей для сборки).
func _missing_processes(p: String) -> Array[String]:
	var avail := sim.prod.processes_available()
	var out: Array[String] = []
	var todo: Array[String] = [p]
	while not todo.is_empty():
		var q: String = todo.pop_back()
		for o: Dictionary in Defs.route(q):
			var pr := str(o["op"])
			var nm := sim.prod.missing_name(p, pr, avail)
			if not Production.size_ok(q, pr, avail) and not out.has(nm):
				out.append(nm)
		for c in Defs.components(q).keys():
			todo.append(str(c))
	return out


func _active_row(o: Dictionary) -> void:
	var p := str(o["product"])
	var st := str(o["status"])
	var prog: Control
	match st:
		"active":
			var ok := mini(sim.ok_in_storage(p), sim.orders.remaining(o))
			prog = UITheme.meter(100.0 * ok / maxf(1.0, float(int(o["qty"]))), UITheme.INFO, 56, "%d из %d" % [ok, int(o["qty"])])
		"ready":
			prog = _cl("готов, ждём машину", 13, UITheme.GOOD)
		_:
			prog = _cl("отгрузка %d/%d" % [int(o["shipped"]), int(o["qty"])], 13, UITheme.GOOD)
	var late := sim.minute > float(o["deadline"])
	var left := (float(o["deadline"]) - sim.minute) / 1440.0
	var when := "просрочен" if late else ("через %d дн." % int(ceil(left)) if left >= 1.0 else "сегодня")
	if bool(o.get("trial", false)):
		when = "пробная · " + when
	elif bool(o.get("moved", false)):
		when = "перенесён · " + when
	var dl := _cl2(sim.season.short_date(int(float(o["deadline"]) / 1440.0) + 1), when, UITheme.BAD if late else UITheme.TEXT, UITheme.BAD if late else (UITheme.WARN if left < 2.0 else (UITheme.INFO if bool(o.get("trial", false)) else UITheme.MUTED)), 13)
	var pr_ctl: Control = _cl("—", 13, UITheme.MUTED)
	if st == "active":
		var prio := int(o.get("prio", 0))
		var oid := int(o["id"])
		pr_ctl = UITheme.segmented([["-1", "низк."], ["0", "обычн."], ["1", "срочн."]], str(clampi(prio, -1, 1)), func(k: String) -> void:
			var oo := sim.orders.get_order(oid)
			oo["prio"] = int(k)
			rebuild(true))
		pr_ctl.tooltip_text = "Станки и рабочие сначала делают детали для срочных заказов"
	var dl_cell: Control = dl
	if st == "active" and (late or left < 2.0) and sim.orders.postpone_block(o) == "":
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(dl)
		var oid2 := int(o["id"])
		var do_move := func() -> void:
			var err := sim.orders.postpone(oid2)
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			rebuild(true)
		var mv := UITheme.small("+%d дн." % OrderBook.MOVE_DAYS, do_move,
			"Позвонить заказчику: срок +%d рабочих дня, скидка %d%%, репутация −2. Один раз на заказ." % [OrderBook.MOVE_DAYS, int(OrderBook.MOVE_DISCOUNT * 100.0)])
		mv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(mv)
		dl_cell = hb
	var who := str(o["client"])
	var draw := UITheme.small("Чертёж", func() -> void: hud.show_drawing(o), "Рабочий чертёж детали по ЕСКД")
	_trow([[_icon(Tex.item(p), 30), 36], [_cl2("%s × %d" % [Defs.product_name(p), int(o["qty"])], who), -1], [prog, 140], [dl_cell, 190], [pr_ctl, 150],
		[_cl(Defs.money_str(float(o["price"]) * int(o["qty"])), 14, UITheme.GOOD, UITheme.f_semi, HORIZONTAL_ALIGNMENT_RIGHT), 100], [draw, 74]], Callable(), 46.0)


# ---------------------------------------------------------------- снабжение

func _supply() -> void:
	if tab == "stash":
		_stash()
		return
	_intro("Снабжение работает само: металл и расходники докупаются под принятые заказы (с запасом на брак) и приезжают фургоном в рабочее время. Оборудование заказывается, когда вы ставите объект. Цены на металл гуляют: индекс меняется каждый день, иногда — скачком.")
	var mk := sim.market
	var tr := mk.metal_trend()
	_info("индекс цены металла %.2f%s" % [mk.metal, " · %s%d%% за неделю" % ["+" if tr > 0 else "−", int(roundf(absf(tr) * 100.0))] if absf(tr) >= 0.01 else ""])
	var top := _cards(3)
	var a := _card_in(top, "Поставщик металла")
	if sim.office.active("supply"):
		var items: Array = []
		for sk in Defs.suppliers.keys():
			var sd: Dictionary = Defs.suppliers[sk]
			items.append([str(sk), "%s %s%d%%" % [str(sd["name"]), "+" if float(sd["k"]) >= 1.0 else "−", int(round(absf(float(sd["k"]) - 1.0) * 100.0))], str(sd.get("desc", ""))])
		a.add_child(UITheme.segmented(items, sim.office.supplier, func(k: String) -> void:
			sim.office.supplier = k
			rebuild(true)))
	else:
		var sd2 := sim.office.supplier_def()
		a.add_child(UITheme.para("%s — розница, +%d%% к цене. Снабженец в отделе снабжения найдёт опт дешевле." % [str(sd2["name"]), int(round((float(sd2["k"]) - 1.0) * 100.0))]))
	a.add_child(UITheme.caption("Запас сверх заказов"))
	a.add_child(UITheme.segmented([["0", "Только под заказы", "Покупать ровно под принятые заказы — дешевле, но если ОТК забракует, ждать новый металл."],
		["1", "Небольшой", "Сверх заказов держать ещё ~20% (не меньше 8 шт.) основного металла профиля."],
		["2", "Большой", "Сверх заказов держать ещё ~50% (не меньше 24 шт.) — новые заказы стартуют сразу, но деньги лежат на складе."]],
		str(sim.supply_reserve), func(k: String) -> void:
			sim.supply_reserve = int(k)
			rebuild(true)))
	var b := _card_in(top, "В пути")
	var any := false
	for s2: Dictionary in sim.supply:
		any = true
		b.add_child(_cl("%s × %d — %s" % [Defs.material_name(str(s2["mat"])), int(s2["qty"]), sim._eta_str(float(s2["eta"]))], 13))
	for s3: Dictionary in sim.cons_supply:
		any = true
		var cd2: Dictionary = Defs.consumables.get(str(s3["cons"]), {})
		b.add_child(_cl("%s × %d уп. — %s" % [str(cd2.get("name", "")), int(s3["packs"]), sim._eta_str(float(s3["eta"]))], 13))
	for e: Dictionary in sim.logi.equip:
		any = true
		b.add_child(_cl("Оборудование: %s — %s" % [str(Defs.objects.get(str(e["def"]), {}).get("name", "")), "едет" if bool(e["spawned"]) else sim._eta_str(float(e["eta"]))], 13))
	if not any:
		b.add_child(UITheme.label("Ничего не едет.", 13, UITheme.MUTED))
	var mc := _card_in(top, "Индекс цены металла", "1.00 — обычная цена. Дёшево — закупайте впрок (запас «Большой»), дорого — только под заказы.")
	var mh := UITheme.hbox(8)
	mh.add_child(UITheme.label("%.2f" % mk.metal, 22, UITheme.GOOD if mk.metal < 0.95 else (UITheme.BAD if mk.metal > 1.08 else UITheme.TEXT), UITheme.f_semi))
	var tl := UITheme.label(("дешевле обычного" if mk.metal < 0.95 else ("дороже обычного" if mk.metal > 1.08 else "обычная цена")), 12, UITheme.MUTED)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh.add_child(tl)
	mc.add_child(mh)
	var sup := sim.office.active("supply")
	if sup:
		var h := _hist()
		var cv := ChartView.new().setup([{"name": "Индекс", "color": UITheme.WARN, "values": h.map(func(e: Dictionary) -> float: return float(e["metal"])), "fill": true}], _hist_labels(h), "idx", false)
		cv.custom_minimum_size = Vector2(200, 90)
		mc.add_child(cv)
		var trw := mk.metal_trend()
		mc.add_child(_cl("Снабженец: " + ("металл дешевеет — можно подождать" if trw < -0.02 else ("металл дорожает — выгодно закупить впрок" if trw > 0.02 else "цена стоит")), 12, UITheme.INFO))
	else:
		mc.add_child(_cl("График и прогноз цены ведёт снабженец (Управление → Отделы).", 12, UITheme.MUTED))
	content.add_child(UITheme.caption("Металл"))
	var cols: Array = [["", 28], ["Марка", -1], ["На складе", 100, HORIZONTAL_ALIGNMENT_RIGHT], ["Под заказы", 110, HORIZONTAL_ALIGNMENT_RIGHT], ["В пути", 90, HORIZONTAL_ALIGNMENT_RIGHT], ["Цена", 110, HORIZONTAL_ALIGNMENT_RIGHT]]
	if sup:
		cols.append(["Впрок", 90])
	_thead(cols)
	for m in Defs.materials.keys():
		var md: Dictionary = Defs.materials[m]
		var need := 0
		for p in Defs.products.keys():
			var ps := str(p)
			if not Defs.is_assembly(ps) and sim.planner.material_of(ps) == str(m):
				need += maxi(0, sim.planner.need(ps)) * Defs.mat_qty(ps)
		var way := 0
		for s4: Dictionary in sim.supply:
			if str(s4["mat"]) == str(m):
				way += int(s4["qty"])
		var free := sim.free_material(m)
		var col := UITheme.TEXT if need <= free + way else UITheme.WARN
		var cells: Array = [[_icon(Tex.item(m), 22), 28], [_cl(str(md["name"]), 13), -1], [_cl(str(free), 13, UITheme.TEXT, UITheme.f_semi, HORIZONTAL_ALIGNMENT_RIGHT), 100],
			[_cl(str(need) if need > 0 else "—", 13, col, null, HORIZONTAL_ALIGNMENT_RIGHT), 110], [_cl(str(way) if way > 0 else "—", 13, UITheme.INFO if way > 0 else UITheme.MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT), 90],
			[_cl(Defs.money_str(sim.material_price(m)) + "/шт", 13, UITheme.MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT), 110]]
		if sup:
			var mk2 := str(m)
			var buy := func() -> void:
				var err := sim.order_material(mk2, 20)
				if err != "":
					hud.toast(err, Sim.LVL_WARN)
				rebuild(true)
			cells.append([UITheme.small("+20 шт.", buy, "Закупить 20 штук впрок по сегодняшней цене: %s" % Defs.money_str(sim.material_price(mk2) * 20.0)), 90])
		_trow(cells, Callable(), 32.0)
	content.add_child(UITheme.caption("Расходники — докупаются сами, когда остаётся четверть упаковки"))
	var cg := _cards(4)
	for c in Defs.consumables.keys():
		var cd: Dictionary = Defs.consumables[c]
		var stock := float(sim.cons.get(c, 0.0))
		var units := float(cd["units"])
		var low := stock <= units * 0.25
		var t := UITheme.stat(str(cd["name"]), "%.0f ед." % stock, UITheme.WARN if low else UITheme.TEXT, ("едет" if sim.cons_on_way(str(c)) else "упаковка — %d ед. за %s" % [int(units), Defs.money_str(float(cd["price"]))]),
			UITheme.INFO if sim.cons_on_way(str(c)) else UITheme.MUTED)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cg.add_child(t)


## Расходники: сколько на складе (снабжение докупает само).
func _cons_rows() -> void:
	for c in Defs.consumables.keys():
		var cd: Dictionary = Defs.consumables[c]
		var stock := float(sim.cons.get(c, 0.0))
		var line := "%s: на складе %.0f ед.%s — докупается автоматически" % [str(cd["name"]), stock, " · едет" if sim.cons_on_way(str(c)) else ""]
		content.add_child(UITheme.label(line, 14, UITheme.TEXT if stock > float(cd["units"]) * 0.25 else UITheme.WARN))


func _stash() -> void:
	_intro("Демонтированное и неустановленное оборудование лежит в ящиках в помещении «Склад» (или в зоне разгрузки). Поставите такой же объект — возьмут отсюда бесплатно. Ненужное можно продать за полцены.")
	var sets := sim.logi.spare_sets()
	var g := _cards(2)
	var any := false
	for def_id in sets.keys():
		var n := int((sets[def_id] as Array).size() / maxi(1, Logistics.crates_for(str(def_id))))
		if n <= 0:
			continue
		any = true
		var card := UITheme.card(10)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(card)
		var h := UITheme.hbox(12)
		card.add_child(h)
		h.add_child(_icon(Tex.obj(str(Thing.sprite_for(str(def_id), 0)[0])), 48))
		h.add_child(_cl2("%s × %d" % [str(Defs.objects.get(def_id, {}).get("name", def_id)), n], "ящиков на комплект: %d" % Logistics.crates_for(str(def_id))))
		var price: float = round(float(Defs.objects.get(def_id, {}).get("cost", 0)) * Defs.b("refund_rate"))
		var dd: String = def_id
		var sb := UITheme.small("Продать · %s" % Defs.money_str(price), func() -> void:
			var err := sim.logi.sell_spare(dd)
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			rebuild(true))
		h.add_child(sb)
	if not any:
		content.add_child(UITheme.empty("Склад оборудования пуст."))
	if sim.rooms.of_type("storage").is_empty():
		content.add_child(UITheme.para("Совет: назначьте помещение «Склад» — ящики будут лежать там, а не в зоне разгрузки.", 13, UITheme.INFO))


# ---------------------------------------------------------------- персонал

func _traits_line(w: Worker) -> HFlowContainer:
	var tr := HFlowContainer.new()
	tr.add_theme_constant_override("h_separation", 6)
	for t in w.traits:
		var d: Dictionary = Defs.traits.get(t, {})
		var chip := UITheme.label(str(d.get("name", t)), 12, UITheme.TEXT)
		chip.add_theme_stylebox_override("normal", UITheme.sb(UITheme.BG3, UITheme.LINE, 1, 9, 7, 1))
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.tooltip_text = str(d.get("desc", ""))
		tr.add_child(chip)
	return tr


func _staff() -> void:
	if tab == "train":
		_training()
		return
	if tab == "safety":
		_safety()
		return
	if tab == "staff":
		_staff_list()
	else:
		_hire()


static var staff_filter := "all"
static var staff_sort := "prof"


## Сотрудники: плотная таблица; щелчок по строке — показать человека на заводе.
func _staff_list() -> void:
	var pay := 0.0
	var by_shift := [0, 0]
	var here := 0
	for w in sim.workers:
		pay += w.wage * (1.0 + (Defs.b("night_bonus") if w.shift == 1 else 0.0))
		by_shift[w.shift] += 1
		if w.present:
			here += 1
	_info("%d чел. · на заводе %d · фонд оплаты ~%s в неделю" % [sim.workers.size(), here, Defs.money_str(pay * 5.0)])
	_intro("Зарплата выдаётся по пятницам. Щёлкните по строке — камера покажет человека и откроется его карточка (мысли, навыки, история, действия).")
	if not sim.workers.is_empty():
		var under := 0
		for w0 in sim.workers:
			if w0.wage < int(Mood.market_wage(w0) * 0.97):
				under += 1
		_hbtn("Премия всем · %s" % Defs.money_str(Defs.b("bonus_amount") * sim.workers.size()), func() -> void:
			var err := sim.bonus_all()
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			rebuild(true), "По %s каждому: хорошее настроение на три дня" % Defs.money_str(Defs.b("bonus_amount")))
		_hbtn("Ставки +5%", func() -> void:
			sim.raise_all(0.05)
			rebuild(true), "Повысить ставку всем на 5%%: +%s в неделю" % Defs.money_str(pay * 5.0 * 0.05))
		var mk := _hbtn("По рынку (%d)" % under, func() -> void:
			sim.wages_to_market()
			rebuild(true), "Поднять до рыночной ставку тем, кто получает меньше: иначе они недовольны и уходят")
		mk.disabled = under == 0
	if sim.workers.is_empty():
		content.add_child(UITheme.empty("Пока никого нет. Наймите людей в разделе «Найм»."))
		return
	var bar := UITheme.hbox(10)
	bar.add_child(UITheme.segmented([["all", "Все %d" % sim.workers.size()], ["s0", "1-я смена %d" % by_shift[0]], ["s1", "2-я смена %d" % by_shift[1]], ["itr", "ИТР"], ["low", "Недовольные"]], staff_filter, func(k: String) -> void:
		staff_filter = k
		rebuild(true)))
	bar.add_child(UITheme.spacer())
	bar.add_child(UITheme.label("Сортировка:", 12, UITheme.MUTED))
	bar.add_child(UITheme.segmented([["prof", "профессия"], ["mood", "настроение"], ["grade", "разряд"], ["wage", "ставка"]], staff_sort, func(k: String) -> void:
		staff_sort = k
		rebuild(true)))
	content.add_child(bar)
	var list: Array = sim.workers.filter(func(w: Worker) -> bool:
		match staff_filter:
			"s0":
				return w.shift == 0
			"s1":
				return w.shift == 1
			"itr":
				return w.is_itr()
			"low":
				return w.mood < 35.0
		return true)
	match staff_sort:
		"mood":
			list.sort_custom(func(a: Worker, b: Worker) -> bool: return a.mood < b.mood)
		"grade":
			list.sort_custom(func(a: Worker, b: Worker) -> bool: return a.grade() > b.grade())
		"wage":
			list.sort_custom(func(a: Worker, b: Worker) -> bool: return a.wage > b.wage)
		_:
			list.sort_custom(func(a: Worker, b: Worker) -> bool: return a.prof_name() < b.prof_name() if a.prof != b.prof else a.grade() > b.grade())
	_thead([["", 40], ["Сотрудник", 220], ["Профессия", 190], ["Смена", 70], ["Ставка", 90], ["Настроение", 150], ["Сейчас", -1]])
	for w: Worker in list:
		var por := Portrait.new()
		por.set_look(w.look, 0.6, {"age": w.age, "mood": w.mood})
		var traits: Array[String] = []
		for t in w.traits:
			traits.append(str(Defs.traits.get(t, {}).get("name", t)))
		var mood := UITheme.meter(w.mood, Mood.color(w.mood), 70, ("%d %s" % [int(w.mood), Mood.label(w.mood).to_lower()]) if sim.office.active("hr") else Mood.label(w.mood).to_lower())
		var act := w.activity if w.present else ("не вышел" if w.skip_shift else ("в отпуске" if w.away_why == "в отпуске" else ("на больничном" if w.sick_until > sim.minute else "дома")))
		var wid := w.id
		_trow([[por, 40], [_cl2(w.formal_name(), ", ".join(traits)), 220], [_cl2(w.prof_name(), w.rank_text()), 190],
			[_cl("2-я" if w.shift == 1 else "1-я", 13, UITheme.MUTED), 70], [_cl(Defs.money_str(w.wage), 13), 90], [mood, 150],
			[_cl(act, 13, UITheme.INFO if w.present else UITheme.MUTED), -1]],
			func() -> void:
				hud.select_worker(wid)
				closed.emit(), 54.0, "Показать на заводе и открыть карточку")


## Найм: кандидаты карточками в две колонки, объявления — в шапке.
## 1.19: найм — сначала «кого ищем» (профессии группами с поиском), потом кандидаты этой профессии.
const HIRE_GROUPS := [["У станков", ["turner", "miller", "cnc_operator", "setter", "qc"]],
	["Рабочие", ["laborer", "builder", "electrician", "welder", "fitter", "assembler", "painter", "heat_treater", "cleaner"]],
	["Быт и охрана", ["guard", "cook", "nurse"]],
	["ИТР и офис", ["foreman", "chief", "technologist", "dispatcher", "accountant", "buyer", "hr", "sales_manager", "safety_engineer", "chief_engineer", "lawyer"]]]
static var hire_q := ""          ## строка поиска профессии
static var hire_all := true      ## показать всех кандидатов (пока профессию не выбрали)


func _hire() -> void:
	_info("Кандидатов: %d · новые приходят сами по понедельникам" % sim.candidates.size())
	_intro("Выберите профессию — внизу кандидаты этой профессии. Нет подходящих — «Найти»: придут кандидаты только этой профессии. Черты характера видны не все: остальное откроется на работе (отдел кадров узнаёт сразу).")
	var counts := {}
	for cd: Dictionary in sim.candidates:
		var pk := str(cd.get("prof", ""))
		counts[pk] = int(counts.get(pk, 0)) + 1
	# --- кого ищем
	var box := UITheme.card(12)
	var bv := UITheme.vbox(8)
	box.add_child(bv)
	var srow := UITheme.hbox(10)
	srow.add_child(_cl("Кого ищем?", 15, UITheme.TEXT, UITheme.f_semi))
	var le := LineEdit.new()
	le.placeholder_text = "Поиск профессии: токарь, сварщик, повар…"
	le.text = hire_q
	le.clear_button_enabled = true
	le.custom_minimum_size = Vector2(320, 0)
	srow.add_child(le)
	bv.add_child(srow)
	var chips := VBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	bv.add_child(chips)
	var fill := func() -> void:
		UITheme.clear(chips)
		var q := hire_q.strip_edges().to_lower()
		var any := false
		for grp: Array in HIRE_GROUPS:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var gl := _cl(str(grp[0]), 12, UITheme.MUTED)
			gl.custom_minimum_size = Vector2(104, 30)
			gl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			gl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(gl)
			var fl := HFlowContainer.new()
			fl.add_theme_constant_override("h_separation", 6)
			fl.add_theme_constant_override("v_separation", 6)
			fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var n_in := 0
			for pk2: String in grp[1]:
				var nm := str(Worker.PROF_NAMES.get(pk2, pk2))
				if q != "" and not nm.to_lower().contains(q):
					continue
				var cnt := int(counts.get(pk2, 0))
				var txt := nm + ("  · %d" % cnt if cnt > 0 else "")
				var key := pk2
				var cb := func() -> void:
					ad_prof = key
					hire_all = false
					rebuild(true)
				var bt: Button = UITheme.primary(txt, cb) if (pk2 == ad_prof and not hire_all) else UITheme.button(txt, cb)
				bt.tooltip_text = "Кандидатов сейчас: %d" % cnt if cnt > 0 else "Сейчас таких кандидатов нет — выберите и нажмите «Найти»"
				if cnt == 0 and (pk2 != ad_prof or hire_all):
					bt.modulate = Color(1, 1, 1, 0.72)
				fl.add_child(bt)
				n_in += 1
			if n_in > 0:
				row.add_child(fl)
				chips.add_child(row)
				any = true
		if not any:
			chips.add_child(_cl("Такой профессии нет — попробуйте иначе: «слесарь», «мастер», «инженер».", 13, UITheme.WARN))
	fill.call()
	le.text_changed.connect(func(t: String) -> void:
		hire_q = t
		fill.call())
	# --- действие
	var arow := UITheme.hbox(10)
	var pname := str(Worker.PROF_NAMES.get(ad_prof, ad_prof))
	arow.add_child(UITheme.primary("Найти: %s · %s" % [pname, Defs.money_str(sim.ad_price(ad_prof))], func() -> void:
		var err2 := sim.post_ad(ad_prof)
		if err2 != "":
			hud.toast(err2, Sim.LVL_WARN)
		hire_all = false
		rebuild(true), "Объявление по профессии: придут несколько кандидатов — все «%s»" % pname))
	arow.add_child(UITheme.spacer())
	if not sim.candidates.is_empty():
		arow.add_child(UITheme.ghost("Показать всех кандидатов (%d)" % sim.candidates.size() if not hire_all else "Только «%s»" % pname, func() -> void:
			hire_all = not hire_all
			rebuild(true)))
	bv.add_child(arow)
	content.add_child(box)
	# --- кандидаты
	var idxs: Array[int] = []
	for i in sim.candidates.size():
		if hire_all or str(sim.candidates[i].get("prof", "")) == ad_prof:
			idxs.append(i)
	if sim.candidates.is_empty():
		content.add_child(UITheme.empty("Кандидатов пока нет. Выберите профессию и нажмите «Найти» — или дождитесь понедельника."))
		return
	if idxs.is_empty():
		content.add_child(UITheme.empty("Среди кандидатов нет профессии «%s». Нажмите «Найти» — или посмотрите всех кандидатов (%d)." % [pname, sim.candidates.size()]))
		return
	content.add_child(_cl(("Все кандидаты" if hire_all else "Кандидаты: %s" % pname) + " — %d" % idxs.size(), 14, UITheme.MUTED, UITheme.f_semi))
	var g := _cards(2)
	for i: int in idxs:
		var c := Worker.from_dict(sim.candidates[i])
		var card := UITheme.card(10)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(card)
		var h := UITheme.hbox(12)
		card.add_child(h)
		var por := Portrait.new()
		por.set_look(c.look, 1.12, {"age": c.age, "mood": 60.0, "wide": true, "doc": true})
		por.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # не тянуть фото по высоте карточки
		h.add_child(por)
		var v := UITheme.vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_cl("%s, %d %s" % [c.formal_name(), c.age, Defs.plural(c.age, "год", "года", "лет")], 15, UITheme.TEXT, UITheme.f_semi))
		v.add_child(_cl("%s · %s за смену" % [c.title(), Defs.money_str(c.wage)], 13, UITheme.INFO))
		v.add_child(_cl(_skills_text(c), 12, UITheme.MUTED))
		var tl := HFlowContainer.new()
		tl.add_theme_constant_override("h_separation", 4)
		tl.add_theme_constant_override("v_separation", 3)
		var shown: Array = c.traits if sim.office.active("hr") else c.traits.slice(0, 1)
		for t in shown:
			var d: Dictionary = Defs.traits.get(t, {})
			tl.add_child(UITheme.chip(str(d.get("name", t)), UITheme.TEXT, str(d.get("desc", ""))))
		if shown.size() < c.traits.size():
			tl.add_child(UITheme.chip("+ ещё ?", UITheme.MUTED, "Остальные черты откроются на работе; отдел кадров узнаёт сразу"))
		if c.from_away:
			tl.add_child(UITheme.chip(("иногородняя" if c.female else "иногородний") + " · нужна койка", UITheme.INFO, "Приедет, если в общежитии есть свободная койка. Живёт рядом — не опаздывает"))
		if c.kids > 0:
			tl.add_child(UITheme.chip("дети: %d" % c.kids, UITheme.MUTED, "Нужен садик — иначе иногда будет сидеть с ребёнком"))
		v.add_child(tl)
		h.add_child(v)
		var idx := i
		var hb := UITheme.primary("Нанять", func() -> void:
			var err := sim.hire(idx)
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			rebuild(true))
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(hb)


# ---------------------------------------------------------------- обучение

func _training() -> void:
	var tr := sim.training
	var learners := 0
	var mentors := 0
	for w0 in sim.workers:
		if not tr.course_of(w0).is_empty():
			learners += 1
		if tr.mentor_of(w0):
			mentors += 1
	_info("на курсах %d · с наставником %d · практикантов %d" % [learners, mentors, tr.practicants().size()])
	_intro("Курсы повышения разряда дают +2 к навыку, курсы смежной профессии — допуск к другим станкам (навык до 3). Наставник утраивает рост ученика у станка, но сам работает на 8% медленнее; он должен быть опытнее на 2 и работать в ту же смену.")
	_hbtn("Подобрать наставников", func() -> void:
		var n := tr.auto_mentors()
		hud.toast("Назначено наставников: %d" % n if n > 0 else "Подходящих пар нет: наставник должен быть опытнее ученика на 2 и работать в ту же смену.", Sim.LVL_INFO)
		rebuild(true), "Каждому, кто до 3-го разряда, — опытного наставника из той же смены")
	var g := _cards(3)
	# учебный класс
	var seats := tr.class_seats()
	var a := _card_in(g, "Учебный класс", "Помещение с линолеумом, две парты и доска (Объекты → Офис), назначенное «Учебным классом». Курсы в нём вдвое-втрое дешевле учебного центра, и человек не пропадает на несколько дней.")
	if tr.classrooms().is_empty():
		a.add_child(UITheme.label("нет класса", 18, UITheme.WARN, UITheme.f_semi))
		a.add_child(UITheme.para("Парты + доска в комнате → «Учебный класс».", 12))
	else:
		a.add_child(UITheme.label("%d из %d мест" % [tr.class_busy(), seats], 18, UITheme.TEXT, UITheme.f_semi))
		a.add_child(UITheme.para("занято за партами", 12))
	var wh := UITheme.segmented([["class", "В классе", "Дешевле, человек остаётся на заводе"], ["center", "Учебный центр", "С выездом на несколько дней, дороже"]], train_where, func(k: String) -> void:
		train_where = k
		rebuild(true))
	a.add_child(wh)
	# инструктаж
	var b := _card_in(g, "Инструктаж по ОТ", "Все, кто на смене, по очереди слушают инженера по охране труда (полчаса). Действует %d дней: травм на 30%% меньше. Без него трудовая инспекция штрафует, если рабочих 6 и больше." % Training.TB_DAYS)
	if tr.tb_active():
		b.add_child(UITheme.label("идёт", 18, UITheme.INFO, UITheme.f_semi))
		b.add_child(UITheme.para("осталось %d чел." % tr.tb_wait.size(), 12))
	elif tr.tb_valid():
		b.add_child(UITheme.label("действует", 18, UITheme.GOOD, UITheme.f_semi))
		b.add_child(UITheme.para("до дня %d · травм на 30%% меньше" % (tr.tb_day + Training.TB_DAYS), 12))
	else:
		b.add_child(UITheme.label("просрочен" if tr.tb_day >= 0 else "не проводился", 18, UITheme.WARN, UITheme.f_semi))
		b.add_child(UITheme.para("травм больше, возможен штраф", 12))
	var tbb := UITheme.small("Провести · %s" % Defs.money_str(Training.TB_COST), func() -> void:
		var err := tr.start_tb()
		if err != "":
			hud.toast(err, Sim.LVL_WARN)
		rebuild(true))
	tbb.disabled = tr.tb_active()
	tbb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_child(tbb)
	# ПТУ
	var c := _card_in(g, "Практиканты ПТУ", "По понедельникам приходит практикант (до %d одновременно) на %d дней. Стипендия %s за смену, учится вдвое быстрее; в конце практики — решите, брать ли в штат." % [tr.ptu_cap(), Training.PTU_DAYS, Defs.money_str(Training.PTU_WAGE)])
	if tr.ptu:
		c.add_child(UITheme.label("договор есть", 18, UITheme.GOOD, UITheme.f_semi))
		c.add_child(UITheme.para("сейчас %d из %d мест" % [tr.practicants().size(), tr.ptu_cap()], 12))
		c.add_child(UITheme.small("Расторгнуть", func() -> void:
			tr.ptu_cancel()
			rebuild(true)))
	else:
		c.add_child(UITheme.label("нет договора", 18, UITheme.MUTED, UITheme.f_semi))
		c.add_child(UITheme.para("молодые руки, стипендия %s" % Defs.money_str(Training.PTU_WAGE), 12))
		c.add_child(UITheme.small("Заключить · %s" % Defs.money_str(Training.PTU_COST), func() -> void:
			var err := tr.ptu_sign()
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			rebuild(true)))
	for cc in [a, b, c]:
		for ch in (cc as Control).get_children():
			if ch is Button:
				(ch as Button).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# люди
	var list: Array = sim.workers.filter(func(w: Worker) -> bool: return not w.is_itr())
	if list.is_empty():
		content.add_child(UITheme.empty("Рабочих пока нет."))
		return
	list.sort_custom(func(x: Worker, y: Worker) -> bool: return x.prof_name() < y.prof_name() if x.prof != y.prof else x.grade() < y.grade())
	_thead([["", 40], ["Сотрудник", 230], ["Навыки", 230], ["Учёба и наставник", -1], ["", 214]])
	for w: Worker in list:
		var por := Portrait.new()
		por.set_look(w.look, 0.6, {"age": w.age, "mood": w.mood})
		var nm := w.formal_name()
		var sub := w.prof_rank()
		if w.practice_until >= 0:
			sub = "практикант до дня %d" % w.practice_until
		var cr := tr.course_of(w)
		var m := tr.mentor_of(w)
		var aps := tr.apprentices(w)
		var study: Control
		if not cr.is_empty():
			var skn := str(Worker.SKILL_NAMES.get(str(cr["skill"]), "")).to_lower()
			study = UITheme.meter(tr.progress(w) * 100.0, UITheme.INFO, 90, "%s %d → %d · %s" % [skn, int(cr["from"]), int(cr["to"]), "в классе" if str(cr["where"]) == "class" else "в центре"])
		else:
			var ms: Array[String] = []
			if m:
				ms.append("наставник " + m.call_name() + ("" if m.shift == w.shift else " (другая смена!)"))
			if not aps.is_empty():
				var names: Array[String] = []
				for ap in aps:
					names.append(ap.call_name())
				ms.append("ученики: " + ", ".join(names))
			study = _cl("—" if ms.is_empty() else " · ".join(ms), 13, UITheme.MUTED if ms.is_empty() else (UITheme.BAD if m and m.shift != w.shift else UITheme.GOOD))
		var acts := UITheme.hbox(6)
		var wid := w.id
		if cr.is_empty():
			var keys: Array[String] = []
			var labels: Array[String] = []
			for sk in Training.SKILLS:
				var o := tr.offer(w, sk)
				if str(o["why"]) != "" or int(o["from"]) >= 10:
					continue
				var cost := float(o["cls"] if train_where == "class" else o["ctr"])
				labels.append("%s %d → %d%s · %s" % [Worker.SKILL_NAMES[sk], int(o["from"]), int(o["to"]), " (смежная)" if str(o["kind"]) == "new" else "", Defs.money_str(cost)])
				keys.append(sk)
			acts.add_child(_menu("Курсы ▾", labels, func(i: int) -> void:
				var ww := sim.get_worker(wid)
				if ww == null or i < 0 or i >= keys.size():
					return
				var err := tr.start_course(ww, keys[i], train_where)
				if err != "":
					hud.toast(err, Sim.LVL_WARN)
				rebuild(true), "Нет доступных курсов" if labels.is_empty() else "Записать на курсы (%s)" % ("в своём классе" if train_where == "class" else "в учебном центре")))
		else:
			acts.add_child(UITheme.small("Отменить", func() -> void:
				var ww2 := sim.get_worker(wid)
				if ww2:
					tr.cancel_course(ww2)
				rebuild(true), "Отменить курсы (деньги не вернут)"))
		var cands := tr.mentor_candidates(w)
		var cids: Array[int] = []
		var mlabels: Array[String] = []
		if m:
			mlabels.append("Снять наставника")
			cids.append(-1)
		for o2 in cands:
			mlabels.append("%s — %s %d%s" % [o2.full_name(), str(Worker.SKILL_NAMES.get(w.main_skill(), "")).to_lower(), o2.skill(w.main_skill()), "" if o2.shift == w.shift else " (другая смена)"])
			cids.append(o2.id)
		acts.add_child(_menu("Наставник ▾", mlabels, func(i: int) -> void:
			var ww3 := sim.get_worker(wid)
			if ww3 == null or i < 0 or i >= cids.size():
				return
			var err2 := tr.set_mentor(ww3, sim.get_worker(cids[i]) if cids[i] >= 0 else null)
			if err2 != "":
				hud.toast(err2, Sim.LVL_WARN)
			rebuild(true), "Нет подходящего: нужен опытнее на 2 (навык от 6), у кого меньше двух учеников" if cids.is_empty() else "Назначить наставника"))
		_trow([[por, 40], [_cl2(nm, sub, UITheme.TEXT, UITheme.INFO if w.practice_until >= 0 else UITheme.MUTED), 230], [_cl(_skills_text(w), 12, UITheme.MUTED), 230], [study, -1], [acts, 214]], Callable(), 54.0)


## Маленькое выпадающее меню действий (для строк таблиц).
func _menu(text: String, items: Array[String], cb: Callable, tip: String = "") -> MenuButton:
	var mb := MenuButton.new()
	mb.text = text
	mb.flat = false
	mb.focus_mode = Control.FOCUS_NONE
	mb.tooltip_text = tip
	mb.add_theme_font_size_override("font_size", 12)
	mb.add_theme_stylebox_override("normal", UITheme.sb(UITheme.BG3, UITheme.LINE2, 1, 6, 8, 2))
	mb.add_theme_stylebox_override("hover", UITheme.sb(UITheme.BG4, Color("#5b6570"), 1, 6, 8, 2))
	mb.add_theme_stylebox_override("pressed", UITheme.sb(UITheme.BG4, UITheme.ACCENT, 1, 6, 8, 2))
	mb.add_theme_stylebox_override("disabled", UITheme.sb(Color("#202328"), Color("#2c3138"), 1, 6, 8, 2))
	mb.add_theme_color_override("font_pressed_color", UITheme.TEXT)
	mb.add_theme_color_override("font_hover_pressed_color", UITheme.TEXT)
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pm := mb.get_popup()
	for it in items:
		pm.add_item(it)
	pm.id_pressed.connect(func(i: int) -> void: cb.call(i))
	mb.disabled = items.is_empty()
	return mb


## Охрана труда: СОУТ, СИЗ, молоко за вредность, акты Н-1.
func _safety() -> void:
	var eng := sim.eng
	var places := eng.workplaces()
	var n := [0, 0, 0, 0]
	for m in places:
		var c := eng.class_of(m)
		if c >= 0:
			n[c] += 1
	var un := eng.unassessed()
	var cabs := eng.cabinets().size()
	var bare := eng.without_ppe()
	var ent := eng.entitled_count()
	var sd := sim.crew.safe_days()
	_info("дней без травм: %d" % sd)
	var g := _cards(3)
	# СОУТ
	var a := _card_in(g, "Спецоценка (СОУТ)", "Лаборатория замеряет шум, воздух (сварочный аэрозоль, пары краски), микроклимат и свет. На вредных местах положены доплата к ставке (3.1 — 4%, 3.2 — 8%, 3.3 — 12%) и молоко. Трудовая инспекция штрафует, если СОУТ не проведена (при 4 рабочих и больше). Улучшили условия — закажите замеры заново, класс снизится.")
	if eng.sout_busy():
		a.add_child(UITheme.label("идут замеры", 18, UITheme.INFO, UITheme.f_semi))
		a.add_child(UITheme.para("%d мест · итог к концу дня %d" % [eng.sout_ids.size(), int(eng.sout_until / 1440.0) + 1], 12))
	elif places.is_empty():
		a.add_child(UITheme.label("нет мест", 18, UITheme.MUTED, UITheme.f_semi))
		a.add_child(UITheme.para("станков пока нет", 12))
	else:
		a.add_child(UITheme.label("не оценено: %d" % un if un > 0 else "все оценены", 18, UITheme.WARN if un > 0 else UITheme.GOOD, UITheme.f_semi))
		a.add_child(UITheme.para("мест %d · допустимых %d · вредных %d" % [places.size(), n[0], n[1] + n[2] + n[3]], 12))
	var ab := UITheme.hbox(6)
	var b1 := UITheme.small("Новые · %s" % Defs.money_str(eng.sout_price(false)), func() -> void:
		var err := eng.start_sout(false)
		if err != "":
			hud.toast(err, Sim.LVL_WARN)
		rebuild(true), "Замеры только там, где СОУТ ещё не проводилась (%s за место)" % Defs.money_str(Eng.SOUT_COST))
	b1.disabled = eng.sout_busy() or un == 0
	ab.add_child(b1)
	var b2 := UITheme.small("Все заново · %s" % Defs.money_str(eng.sout_price(true)), func() -> void:
		var err2 := eng.start_sout(true)
		if err2 != "":
			hud.toast(err2, Sim.LVL_WARN)
		rebuild(true), "Повторные замеры на всех местах — после того, как улучшили вентиляцию, свет или отопление")
	b2.disabled = eng.sout_busy() or places.is_empty()
	ab.add_child(b2)
	a.add_child(ab)
	# СИЗ
	var b := _card_in(g, "СИЗ", "Комплект (каска, очки, наушники, перчатки, респиратор) служит около 20 смен. Без СИЗ травм в полтора раза больше; в наушниках шум не раздражает, в респираторе дым — меньше. Шкаф СИЗ (Объекты → Безопасность): рабочие сами берут новый комплект, когда старый износится. Новички приходят без СИЗ.")
	if cabs == 0:
		b.add_child(UITheme.label("нет шкафа", 18, UITheme.WARN, UITheme.f_semi))
		b.add_child(UITheme.para("Объекты → Безопасность → шкаф СИЗ", 12))
	else:
		b.add_child(UITheme.label("без СИЗ: %d" % bare.size() if bare.size() > 0 else "все в СИЗ", 18, UITheme.WARN if bare.size() > 0 else UITheme.GOOD, UITheme.f_semi))
		b.add_child(UITheme.para("шкафов %d · комплектов на складе %d" % [cabs, eng.ppe_stock()], 12))
	var bh := UITheme.hbox(6)
	var cd: Dictionary = Defs.consumables.get("ppe", {})
	bh.add_child(UITheme.small("Купить 5 · %s" % Defs.money_str(float(cd.get("price", 7500))), func() -> void:
		var err3 := sim.order_cons("ppe", 1)
		if err3 != "":
			hud.toast(err3, Sim.LVL_WARN)
		rebuild(true), "Курьер привезёт в течение пары часов. При автозакупке снабжение докупает само."))
	if sim.cons_on_way("ppe"):
		bh.add_child(UITheme.chip("везут", UITheme.INFO))
	b.add_child(bh)
	# молоко
	var c2 := _card_in(g, "Молоко за вредность", "Положено тем, кто работает на местах класса 3.x по СОУТ. Людям обидно без молока, а трудовая инспекция за это штрафует.")
	c2.add_child(UITheme.label("положено %d чел." % ent, 18, UITheme.TEXT, UITheme.f_semi))
	c2.add_child(UITheme.para("%s на человека за смену" % Defs.money_str(Eng.MILK_COST), 12, UITheme.WARN if ent > 0 and not eng.milk_on else UITheme.MUTED))
	var cb := CheckBox.new()
	cb.text = "Выдавать молоко"
	cb.button_pressed = eng.milk_on
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on: bool) -> void:
		eng.milk_on = on
		rebuild(true))
	c2.add_child(cb)
	# рабочие места и акты Н-1 — две колонки
	var cols := _cards(2)
	var pl := _card_in(cols, "Рабочие места", "Класс условий труда по последним замерам и что вредит сейчас.")
	if not sim.office.active("safety"):
		pl.add_child(_lock_card("safety", "карта опасных мест: что вредит на каждом рабочем месте. Травм на 15% меньше, штраф по акту Н-1 вдвое меньше.", true))
		places = []
	elif places.is_empty():
		pl.add_child(UITheme.para("Станков пока нет.", 13))
	for m in places:
		var h := UITheme.hbox(8)
		h.add_child(_icon(Tex.obj(m.def_id), 28.0))
		var rm := sim.rooms.room_of_thing(m)
		var fs := eng.factors(m)
		var fn: Array[String] = []
		for f: Array in fs:
			fn.append(str(f[0]) + ("" if str(f[2]) == "" else " " + str(f[2])))
		var cell := _cl2("%s%s" % [m.title(), (" · " + rm.title()) if rm else ""], "в норме" if fn.is_empty() else ", ".join(fn), UITheme.TEXT, UITheme.MUTED if fn.is_empty() else UITheme.WARN, 13)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cell)
		var c3 := eng.class_of(m)
		h.add_child(UITheme.chip("не оценено" if c3 < 0 else Eng.CLASS_NAMES[c3], UITheme.MUTED if c3 < 0 else (UITheme.GOOD if c3 == 0 else (UITheme.WARN if c3 == 1 else UITheme.BAD))))
		pl.add_child(h)
	CrewUI.n1_section(self, cols)


func _skills_text(c: Worker) -> String:
	var list: Array = []
	for k in Worker.SKILL_NAMES.keys():
		var v := c.skill(str(k))
		if v > 0:
			list.append([str(Worker.SKILL_NAMES[k]), v])
	list.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var parts: Array[String] = []
	for e: Array in list.slice(0, 5):
		parts.append("%s %d" % [str(e[0]), int(e[1])])
	return " · ".join(parts)


# ---------------------------------------------------------------- цех: станки, ППР, маршруты

func _machine_state(m: Thing) -> Array:
	if m.broken:
		return ["Сломан — ждёт ремонта", UITheme.BAD]
	if not m.enabled:
		return ["Выключен", UITheme.MUTED]
	if not sim.power.connected(m):
		return ["Не подключён к сети", UITheme.BAD]
	if not sim.power.powered(m):
		return ["Нет тока", UITheme.BAD]
	if m.working:
		return ["Работает", UITheme.GOOD]
	if m.product != "":
		return ["Ждёт заготовок или рабочего", UITheme.WARN]
	if not sim.planner.staffed(m):
		return ["Некому работать", UITheme.WARN]
	return ["Простаивает: нет работы", UITheme.MUTED]


func _shop() -> void:
	if tab == "routes":
		_routes()
		return
	var ms := sim.things_of("machine")
	var work := 0
	var broken := 0
	for m0 in ms:
		if m0.working:
			work += 1
		if m0.broken:
			broken += 1
	_info("%d %s · работают %d%s" % [ms.size(), Defs.plural(ms.size(), "станок", "станка", "станков"), work, (" · сломано %d" % broken) if broken > 0 else ""])
	_intro("Щёлкните по строке — камера покажет станок и откроется его карточка. Состояние падает от работы; ниже %d%% станок могут остановить на ремонт." % int(Defs.b("breakdown_below")))
	var ppr := CheckBox.new()
	ppr.text = "ППР"
	ppr.button_pressed = sim.ppr
	ppr.focus_mode = Control.FOCUS_NONE
	ppr.tooltip_text = "Планово-предупредительный ремонт: слесари обслуживают станки уже при износе ниже %d%% (обычно — ниже %d%%).\nОбслуживание чаще и дороже, зато станки почти не ломаются.\nРемонт сломанного станка — %s и полдня простоя." % [int(Defs.b("ppr_at")), int(Brain.SERVICE_AT), Defs.money_str(Defs.b("repair_cost"))]
	ppr.toggled.connect(func(v: bool) -> void:
		sim.ppr = v
		rebuild(true))
	ppr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_extra.add_child(ppr)
	var has_tr := not sim.rooms.of_type("toolroom").is_empty()
	header_extra.add_child(UITheme.chip("кладовая инструмента: " + ("есть" if has_tr else "нет"), UITheme.GOOD if has_tr else UITheme.MUTED,
		"Инструментальная кладовая: режущего инструмента уходит на четверть меньше"))
	if ms.is_empty():
		content.add_child(UITheme.empty("Станков пока нет. Поставьте их через «Объекты» (O)."))
		return
	_thead([["", 44], ["Станок", 230], ["Задание", -1], ["Работает", 150], ["Состояние", 130], ["Операций", 70], ["", 92]])
	for m in ms:
		var st := _machine_state(m)
		var job := "нет задания"
		if m.product != "":
			var rt := Defs.route(m.product)
			job = "%s · оп. %d из %d" % [Defs.product_name(m.product), m.job_step + 1, rt.size()]
			if m.is_batch():
				job += " · в печи %d" % sim.count_slot(m, 0)
		var who := "—"
		if m.user >= 0:
			var w := sim.get_worker(m.user)
			if w:
				who = w.call_name()
		var ccol := UITheme.GOOD if m.condition >= 60.0 else (UITheme.WARN if m.condition >= Defs.b("breakdown_below") else UITheme.BAD)
		var mid := m.id
		var tb := UITheme.small("Выключить" if m.enabled else "Включить", func() -> void:
			var t: Thing = sim.things.get(mid)
			if t:
				t.enabled = not t.enabled
			rebuild(true))
		_trow([[_icon(Tex.obj(m.def_id), 40), 44], [_cl2(m.title(), str(st[0]), UITheme.TEXT, st[1]), 230], [_cl(job, 13, UITheme.INFO if m.product != "" else UITheme.MUTED), -1],
			[_cl(who, 13), 150], [UITheme.meter(m.condition, ccol, 70, "%d%%" % int(m.condition)), 130], [_cl(str(m.parts_made), 13, UITheme.MUTED), 70], [tb, 92]],
			func() -> void:
				hud.select_thing(mid)
				closed.emit(), 48.0, "Показать станок на заводе")


## Маршруты изделий: операции по переделам, НЗП, чего не хватает.
func _routes() -> void:
	_intro("Маршрут — последовательность операций по переделам. В скобках — сколько деталей ждут следующей операции (незавершённое производство).")
	_thead([["", 36], ["Изделие", 200], ["Маршрут", -1], ["Спрос", 170]])
	var prods: Array = Defs.products.keys()
	prods = prods.filter(func(p: String) -> bool: return sim.progress.products().has(p) or sim.planner.demand(p) > 0)
	for p in prods:
		var ps := str(p)
		var rt2 := Defs.route(ps)
		var steps: Array[String] = []
		for i in rt2.size():
			var nm := Defs.process_name(str(rt2[i]["op"]))
			var waiting := sim.planner.wip_available(ps, i) if i > 0 else 0
			steps.append(nm + ((" (%d)" % waiting) if waiting > 0 else ""))
		var miss := _missing_processes(ps)
		var sub := ("нет оборудования: " + ", ".join(miss)) if not miss.is_empty() else (_inputs_text(ps, 1) if Defs.is_assembly(ps) else "")
		var need := sim.planner.need(ps)
		var dem := sim.planner.demand(ps)
		_trow([[_icon(Tex.item(ps), 30), 36], [_cl2(Defs.product_name(ps), "размер: " + ["мелкий", "средний", "крупный"][Defs.product_rank(ps)], UITheme.TEXT, UITheme.MUTED, 14), 200],
			[_cl2(" → ".join(steps), sub, UITheme.INFO, UITheme.BAD if not miss.is_empty() else UITheme.MUTED, 13), -1],
			[_cl(("нужно %d · в работе %d" % [dem, sim.planner.pipeline(ps)]) if dem > 0 else "—", 13, (UITheme.WARN if need > 0 else UITheme.GOOD) if dem > 0 else UITheme.MUTED), 170]], Callable(), 44.0)


# ---------------------------------------------------------------- финансы и журнал

func _finance() -> void:
	match tab:
		"weeks":
			_finance_weeks()
			return
		"charts":
			_finance_charts()
			return
		"insurance":
			_finance_insurance()
			return
		"loans":
			_finance_loans()
			return
		"grants":
			_finance_grants()
			return
	var st := sim.stats
	_info("налог с выручки %d%% · долг по кредитам %s" % [int(round(sim.office.tax_rate() * 100.0)), Defs.money_str(sim.office.debt())])
	_crisis_card()
	if not sim.office.active("accounting"):
		# без бухгалтера — только остаток и последние операции (1.10)
		var g0 := _cards(3)
		for t0 in [UITheme.stat("Деньги", Defs.money_str(sim.money), UITheme.BAD if sim.money < 0 else UITheme.TEXT),
				UITheme.stat("Сегодня", ("+" if sim.today_net() >= 0.0 else "") + Defs.money_str(sim.today_net()), UITheme.GOOD if sim.today_net() >= 0.0 else UITheme.BAD, "приход минус расход"),
				UITheme.stat("Репутация", "%d из 100" % int(sim.reputation), UITheme.ramp(sim.reputation / 100.0))]:
			t0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g0.add_child(t0)
		content.add_child(_lock_card("accounting", "заработано и потрачено за всё время, отчёт по неделям и статьям, налог 5% вместо 6%, кредит под 17%. Дальше в «Развитии» — себестоимость и прогноз кассы, банк, лизинг и страхование.", true))
		content.add_child(UITheme.caption("Последние операции"))
		for e0: Dictionary in sim.ledger.slice(0, 12):
			var v0 := float(e0["v"])
			_trow([[_cl("день %d, %s" % [int(e0["day"]), str(e0["time"])], 12, UITheme.MUTED), 110], [_cl(str(e0["text"]), 13), -1],
				[_cl(("+" if v0 > 0 else "") + Defs.money_str(v0), 13, UITheme.GOOD if v0 > 0 else UITheme.BAD, UITheme.f_semi, HORIZONTAL_ALIGNMENT_RIGHT), 130]], Callable(), 28.0)
		return
	var fc := cash_forecast()
	var g := _cards(4)
	for t in [UITheme.stat("Деньги", Defs.money_str(sim.money), UITheme.BAD if sim.money < 0 else UITheme.TEXT),
			(UITheme.stat("Через 2 недели", "≈ " + Defs.money_str(float(fc["end"])), UITheme.BAD if float(fc["end"]) < 0.0 else UITheme.GOOD, "прогноз бухгалтера: %s" % str(fc["text"])) if sim.dev.on("fin2")
				else UITheme.stat("Через 2 недели", "—", UITheme.MUTED, "прогноз кассы — ступень «Себестоимость» (Управление → Развитие)")),
			UITheme.stat("Заработано", Defs.money_str(float(st["earned"])), UITheme.GOOD, "за всё время"),
			UITheme.stat("Потрачено", Defs.money_str(float(st["spent"])), UITheme.BAD, "за всё время"),
			UITheme.stat("Репутация", "%d из 100" % int(sim.reputation), UITheme.ramp(sim.reputation / 100.0)),
			UITheme.stat("Сделано деталей", str(st["made"]), UITheme.TEXT, "брак, пойманный ОТК: %s" % str(st["scrap"])),
			UITheme.stat("Отгружено", str(st["shipped"]), UITheme.TEXT, "деталей клиентам"),
			UITheme.stat("Заказы", "%d / %d" % [int(st["orders_done"]), int(st["orders_failed"])], UITheme.TEXT, "выполнено / сорвано"),
			UITheme.stat("Долг", Defs.money_str(sim.office.debt()), UITheme.WARN if sim.office.debt() > 0.0 else UITheme.MUTED, "по кредитам")]:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(t)
	content.add_child(UITheme.caption("Движение денег"))
	for e: Dictionary in sim.ledger.slice(0, 50):
		var v := float(e["v"])
		_trow([[_cl("день %d, %s" % [int(e["day"]), str(e["time"])], 12, UITheme.MUTED), 110], [_cl(str(e["text"]), 13), -1],
			[_cl(("+" if v > 0 else "") + Defs.money_str(v), 13, UITheme.GOOD if v > 0 else UITheme.BAD, UITheme.f_semi, HORIZONTAL_ALIGNMENT_RIGHT), 130]], Callable(), 28.0)


## 1.20: беды с деньгами — сверху «Финансов»: долг по зарплате, зарплата в долг, касса в минусе.
func _crisis_card() -> void:
	var cr := sim.crisis
	var arr := sim.progress.arrears_total()
	if arr <= 0.0 and sim.money >= 0.0 and cr.can_credit_wages():
		return
	var bad := arr > 0.0 or sim.money < 0.0
	var c := UITheme.card(12, Color(0.16, 0.08, 0.07) if bad else UITheme.BG2, UITheme.BAD if bad else UITheme.LINE)
	var v := UITheme.vbox(6)
	c.add_child(v)
	if arr > 0.0:
		var days := (sim.day() - cr.unpaid_since) if cr.unpaid_since >= 0 else 0
		v.add_child(UITheme.label("Долг по зарплате: %s — задерживают %d дн." % [Defs.money_str(arr), days], 15, UITheme.BAD, UITheme.f_semi))
		v.add_child(UITheme.para("Люди жалуются и уходят — первым тот, у кого настроение хуже. Трое за две недели (уже %d) — трудовая инспекция закроет завод." % cr.arrears_quits.size(), 13, UITheme.TEXT))
		var h := UITheme.hbox(8)
		var pb := UITheme.primary("Выплатить долги по зарплате · %s" % Defs.money_str(arr), func() -> void:
			var err := sim.progress.pay_arrears()
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			else:
				cr.unpaid_since = -1
				hud.toast("Долги по зарплате выплачены — люди успокоились.", Sim.LVL_GOOD)
			rebuild(true))
		pb.disabled = not sim.can_afford(arr)
		if pb.disabled:
			pb.tooltip_text = "Не хватает денег: сдайте готовые заказы, продайте лишнее или возьмите кредит"
		h.add_child(pb)
		h.add_child(UITheme.button("Кредиты", func() -> void: select_tab("loans")))
		v.add_child(h)
	if sim.money < 0.0:
		v.add_child(UITheme.para("Касса в минусе %d дн.: репутация падает каждый день, сбыт не берёт новых заказов, снабжение не покупает металл в долг." % cr.debt_days, 13, UITheme.WARN))
	v.add_child(UITheme.para("Зарплату в долг (когда денег не хватает): " + ("можно — один раз, потом через 3 месяца." if cr.can_credit_wages() else "уже выдавали, снова можно через %d дн. До тех пор нехватка денег = задержка зарплаты." % cr.credit_left_days()), 12, UITheme.MUTED))
	content.add_child(c)


func _log() -> void:
	_info("последние %d событий" % sim.events.size())
	for e: Dictionary in sim.events:
		var lvl := int(e["level"])
		var col: Color = [UITheme.INFO, UITheme.GOOD, UITheme.WARN, UITheme.BAD][clampi(lvl, 0, 3)]
		var dot := ColorRect.new()
		dot.color = col
		dot.custom_minimum_size = Vector2(6, 6)
		var t := _cl(str(e["text"]), 13, UITheme.TEXT)
		t.tooltip_text = str(e["text"])
		var tg := Links.target(str(e["text"]), "")
		var cb := Callable()
		if tg != "" and not tg.begins_with("events:log"):
			cb = func() -> void: hud.call_deferred("open_window", tg)
		_trow([[dot, 6], [_cl("день %d, %s" % [int(e["day"]), str(e["time"])], 12, UITheme.MUTED), 110], [t, -1]], cb, 28.0, str(e["text"]) + ("\nНажмите — открыть, где с этим разбираться" if tg != "" else ""))


func _finance_weeks() -> void:
	if not sim.office.active("accounting"):
		content.add_child(UITheme.empty("Отчёт по статьям ведёт бухгалтерия. Постройте помещение «Бухгалтерия» (стол ИТР, сейф, линолеум) и наймите бухгалтера — появится движение денег по неделям и статьям."))
		return
	var weeks := sim.office.weeks.slice(0, 6)
	if weeks.is_empty():
		content.add_child(UITheme.empty("Данных пока нет."))
		return
	_info("последние %d %s, по статьям" % [weeks.size(), Defs.plural(weeks.size(), "неделя", "недели", "недель")])
	var cols: Array = [["Статья", -1]]
	for wd: Dictionary in weeks:
		cols.append(["Неделя %d" % int(wd["week"]), 110, HORIZONTAL_ALIGNMENT_RIGHT])
	_thead(cols)
	for c in Office.CAT_ORDER:
		var any := false
		for wd2: Dictionary in weeks:
			if (wd2["cats"] as Dictionary).has(c):
				any = true
		if not any:
			continue
		var cells: Array = [[_cl(str(Office.CATS[c]), 13), -1]]
		for wd3: Dictionary in weeks:
			var v := float((wd3["cats"] as Dictionary).get(c, 0.0))
			cells.append([_cl(Defs.money_str(v) if v != 0.0 else "—", 13, UITheme.GOOD if v > 0 else (UITheme.BAD if v < 0 else UITheme.MUTED), null, HORIZONTAL_ALIGNMENT_RIGHT), 110])
		_trow(cells, Callable(), 30.0)
	var tot: Array = [[_cl("Операционный итог", 14, UITheme.TEXT, UITheme.f_semi), -1]]
	var tot2: Array = [[_cl("С учётом стройки и кредитов", 12, UITheme.MUTED), -1]]
	for wd4: Dictionary in weeks:
		var t := sim.office.week_total(wd4)
		tot.append([_cl(Defs.money_str(t), 14, UITheme.GOOD if t >= 0 else UITheme.BAD, UITheme.f_semi, HORIZONTAL_ALIGNMENT_RIGHT), 110])
		tot2.append([_cl(Defs.money_str(sim.office.week_total(wd4, true)), 12, UITheme.MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT), 110])
	_trow(tot, Callable(), 34.0)
	_trow(tot2, Callable(), 28.0)


func _finance_grants() -> void:
	var gr := sim.grants
	_info("в работе %d из %d" % [gr.active.size(), gr.max_active()])
	_intro("Программы поддержки: оформите программу, выполните условия до срока — фонд возместит затраты. Деньги приходят только после выполнения. Одновременно — не больше %d программ." % gr.max_active())
	if not gr.active.is_empty():
		content.add_child(UITheme.caption("В работе"))
		var ga := _cards(2)
		for a: Dictionary in gr.active:
			var g := Grants.def(str(a["id"]))
			var v := _card_in(ga)
			var hh := UITheme.hbox(8)
			var t1 := _cl2(str(g.get("title", "")), str(g.get("org", "")))
			t1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hh.add_child(t1)
			hh.add_child(UITheme.label(Defs.money_str(float(g.get("reward", 0))), 15, UITheme.GOOD, UITheme.f_semi))
			v.add_child(hh)
			var left := int(a["until"]) - sim.day()
			v.add_child(_cl("срок до %s (%s)" % [sim.season.date_str(int(a["until"])), "сегодня последний день" if left <= 0 else "осталось %d %s" % [left, Defs.plural(left, "день", "дня", "дней")]], 12, UITheme.WARN if left <= 2 else UITheme.MUTED))
			for goal: Dictionary in g.get("goals", []):
				var ok := gr.goal_ok(goal, a)
				v.add_child(_cl(("✓ " if ok else "○ ") + str(goal.get("text", "")), 13, UITheme.GOOD if ok else UITheme.TEXT))
	var offers := gr.offers()
	content.add_child(UITheme.caption("Можно оформить"))
	if offers.is_empty():
		content.add_child(UITheme.para("Сейчас подходящих программ нет. Они появляются по ситуации: когда растёт штат, не хватает бытовки или столовой, цех стал тесным, касса ушла в минус — и на следующих этапах роста.", 13))
	var go := _cards(2)
	for g2: Dictionary in offers:
		var v2 := _card_in(go)
		var hh2 := UITheme.hbox(8)
		var t2 := _cl2(str(g2["title"]), str(g2["org"]))
		t2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh2.add_child(t2)
		hh2.add_child(UITheme.label(Defs.money_str(float(g2["reward"])), 15, UITheme.GOOD, UITheme.f_semi))
		v2.add_child(hh2)
		v2.add_child(UITheme.para(str(g2.get("desc", "")), 12))
		var goals: Array[String] = []
		for goal2: Dictionary in g2.get("goals", []):
			goals.append(str(goal2.get("text", "")))
		v2.add_child(UITheme.para("Условия: %s · срок %d дн." % [", ".join(goals), int(g2.get("days", 14))], 12, UITheme.INFO))
		var gid := str(g2["id"])
		v2.add_child(UITheme.primary("Оформить", func() -> void:
			var err := sim.grants.take(gid)
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			rebuild(true)))
	if not gr.done.is_empty():
		var names: Array[String] = []
		for id in gr.done:
			names.append(str(Grants.def(str(id)).get("title", id)))
		content.add_child(UITheme.para("Выполнено: " + ", ".join(names), 13, UITheme.GOOD))


func _finance_loans() -> void:
	var rate := sim.office.loan_rate()
	_info("банк «Заводской кредит» · ставка %d%% годовых%s" % [int(round(rate * 100.0)), " (льготная)" if sim.office.active("accounting") else ""])
	_intro("Платёж — каждый понедельник, равными долями (аннуитет). Не больше двух кредитов одновременно. С бухгалтерией ставка ниже, после ступени «Банк и лизинг» — ещё ниже, и банк даёт до 3 млн ₽. Кредиты открываются на этапе «Мастерская».")
	if sim.progress.stage < 2:
		content.add_child(UITheme.para("Банки кредитуют предприятия, которые уже работают: кредиты откроются на этапе «Мастерская». Пока поддержку дают гранты и программы.", 13, UITheme.WARN))
	var g := _cards(3)
	for opt: Array in sim.office.loan_options():
		var amount := float(opt[0])
		var n := int(opt[1])
		var pay := sim.office.loan_payment(amount, n, rate)
		var v := _card_in(g)
		v.add_child(UITheme.label(Defs.money_str(amount), 20, UITheme.TEXT, UITheme.f_semi))
		v.add_child(_cl("на %d недель · платёж %s в неделю" % [n, Defs.money_str(pay)], 13, UITheme.MUTED))
		v.add_child(_cl("переплата %s" % Defs.money_str(pay * n - amount), 12, UITheme.WARN))
		var b := UITheme.button("Взять кредит", func() -> void:
			var err := sim.office.take_loan(amount, n)
			if sim.progress.stage < 2:
				err = "Кредиты — с этапа «Мастерская»"
			if err != "":
				hud.toast(err, Sim.LVL_WARN)
			rebuild(true))
		b.disabled = sim.progress.stage < 2 or not sim.office.loan_ok(amount)
		v.add_child(b)
		if not sim.office.loan_ok(amount):
			v.add_child(_cl("нужна ступень развития «Банк и лизинг»", 12, UITheme.WARN))
	# лизинг
	var mk := sim.market
	var lc := UITheme.card(12)
	content.add_child(lc)
	var lh := UITheme.hbox(12)
	lc.add_child(lh)
	var lv := UITheme.vbox(2)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(UITheme.label("Лизинг станков", 15, UITheme.TEXT, UITheme.f_semi))
	lv.add_child(UITheme.para("Станок от %s — %d%% сразу, остальное с удорожанием %d%% равными платежами %d недель по понедельникам. Деньги на развитие остаются в кассе." % [Defs.money_str(Market.LEASE_MIN), int(Market.LEASE_ADV * 100.0), int(Market.LEASE_UP * 100.0), Market.LEASE_WEEKS], 12))
	lh.add_child(lv)
	var lcb := CheckButton.new()
	lcb.text = "Покупать станки в лизинг"
	lcb.button_pressed = mk.leasing_on
	lcb.disabled = not sim.dev.on("fin3")
	lcb.tooltip_text = "Лизинг открывает ступень «Банк и лизинг» (Управление → Развитие), её держит бухгалтер" if lcb.disabled else "Касается новых покупок станков (Объекты → Станки и др.)"
	lcb.focus_mode = Control.FOCUS_NONE
	lcb.toggled.connect(func(on: bool) -> void:
		mk.leasing_on = on
		rebuild(true))
	lcb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(lcb)
	if not mk.leases.is_empty():
		content.add_child(UITheme.caption("Лизинг · %s в неделю, осталось %s" % [Defs.money_str(mk.lease_week()), Defs.money_str(mk.lease_debt())]))
		for le: Dictionary in mk.leases:
			_trow([[_cl(str(le["title"]), 14, UITheme.TEXT, UITheme.f_semi), -1], [_cl("осталось %d платежей по %s" % [int(le["left"]), Defs.money_str(float(le["payment"]))], 13), 300],
				[_cl("всего %s" % Defs.money_str(float(le["total"])), 13, UITheme.MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT), 140]], Callable(), 34.0)
	if not sim.office.loans.is_empty():
		content.add_child(UITheme.caption("Текущие кредиты"))
		for ln: Dictionary in sim.office.loans:
			_trow([[_cl(Defs.money_str(float(ln["amount"])), 14, UITheme.TEXT, UITheme.f_semi), 160], [_cl("осталось %d платежей по %s" % [int(ln["left"]), Defs.money_str(float(ln["payment"]))], 13), -1],
				[_cl("%d%% годовых" % int(round(float(ln["rate"]) * 100.0)), 13, UITheme.MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT), 120]], Callable(), 34.0)


# ---------------------------------------------------------------- план производства (ПДО)

func _plan() -> void:
	if not sim.office.active("pdo"):
		content.add_child(UITheme.empty("План производства ведёт ПДО. Постройте помещение «ПДО» (стол ИТР, доска планирования, линолеум) или общую контору и наймите диспетчера: появятся план с прогнозом сроков, приоритеты заказов и автоприём."))
		return
	var li := sim.office.load_info()
	var ld := float(li[0])
	var bott := (" · узкое место — %s" % Defs.process_name(str(li[1])).to_lower()) if ld > 0.3 and str(li[1]) != "" else ""
	_info("загрузка ~%.1f раб. дн.%s" % [ld, bott])
	_intro("Зелёное — сделано, тёмно-зелёное — прогноз до готовности, жёлтая черта — срок. Шкала — две недели от сегодняшнего дня.")
	var act := sim.orders.by_status(["active", "ready", "shipping"])
	act.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["deadline"]) - float(a.get("prio", 0)) * 4320.0 < float(b["deadline"]) - float(b.get("prio", 0)) * 4320.0)
	if act.is_empty():
		content.add_child(UITheme.label("Заказов в работе нет.", 15, UITheme.MUTED))
		return
	var day0 := sim.day()
	var horizon := 14.0
	var cum := 0.0
	var ops := maxf(1.0, sim.office.load_ops()) * 380.0
	for o: Dictionary in act:
		var p := str(o["product"])
		var r := _row()
		var v := UITheme.vbox(4)
		r.add_child(v)
		var hh := UITheme.hbox(10)
		hh.add_child(_icon(Tex.item(p), 24))
		hh.add_child(UITheme.label(sim.orders.short(o), 14, UITheme.TEXT, UITheme.f_semi))
		hh.add_child(UITheme.spacer())
		var left := maxi(0, sim.orders.remaining(o) - sim.ok_in_storage(p))
		cum += left * sim.orders.route_minutes(p) / ops
		var eta_day := day0 + int(ceil(cum * 7.0 / 5.0))
		var dl_day := int(float(o["deadline"]) / 1440.0) + 1
		var late := eta_day > dl_day and str(o["status"]) == "active"
		hh.add_child(UITheme.label(("прогноз: день %d" % eta_day) if str(o["status"]) == "active" else "готов", 13, UITheme.BAD if late else UITheme.GOOD))
		hh.add_child(UITheme.label("срок: день %d" % dl_day, 13, UITheme.MUTED))
		v.add_child(hh)
		# полоса: от сегодня до горизонта, отметки прогноза и срока
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(0, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var eta_f := clampf(float(eta_day - day0) / horizon, 0.0, 1.0)
		var dl_f := clampf(float(dl_day - day0) / horizon, 0.0, 1.0)
		var done_f := 1.0 - float(left) / maxf(1.0, float(int(o["qty"])))
		bar.draw.connect(func() -> void:
			var w := bar.size.x
			bar.draw_rect(Rect2(0, 3, w, 10), Color("#2f343a"))
			bar.draw_rect(Rect2(0, 3, w * eta_f, 10), Color("#d8644e") if late else Color("#4a6a3e"))
			bar.draw_rect(Rect2(0, 3, w * eta_f * done_f, 10), Color("#8fcf78"))
			bar.draw_line(Vector2(w * dl_f, 0), Vector2(w * dl_f, 16), Color("#e0aa48"), 2.0))
		v.add_child(bar)
		var steps: Array[String] = []
		var rt := Defs.route(p)
		for i in rt.size():
			var n := sim.planner.wip_available(p, i) if i > 0 else 0
			steps.append(Defs.process_name(str(rt[i]["op"])) + ((" (ждут %d)" % n) if n > 0 else ""))
		v.add_child(UITheme.label(" → ".join(steps) + " · готово %d из %d" % [int(o["qty"]) - left, int(o["qty"])], 12, UITheme.INFO))


# ---------------------------------------------------------------- управление: ИТР-отделы и политики

func _office() -> void:
	var working := 0
	for d0 in Defs.departments.keys():
		if sim.office.eff(str(d0)) > 0.0:
			working += 1
	_info("работают %d из %d отделов" % [working, Defs.departments.size()])
	_intro("Каждый отдел открывает новые возможности, как бюрократия: нужен кабинет со столом ИТР и сотрудник. Пока завод маленький, всех можно посадить в общую «Контору» — но там они работают на 30% хуже.")
	var g := _cards(2)
	for d in Defs.departments.keys():
		var dd: Dictionary = Defs.departments[d]
		var v := _card_in(g)
		var hh := UITheme.hbox(8)
		hh.add_child(UITheme.label(str(dd["name"]), 15, UITheme.TEXT, UITheme.f_semi))
		var e := sim.office.eff(str(d))
		if not sim.progress.dept_open(str(d)):
			hh.add_child(UITheme.chip("закрыто", UITheme.MUTED, sim.progress.dept_lock_text(str(d))))
		else:
			hh.add_child(UITheme.chip(("работает · %d%%" % int(round(e * 100.0))) if e > 0.0 else "не работает", UITheme.GOOD if e > 0.0 else UITheme.MUTED))
		hh.add_child(UITheme.spacer())
		hh.add_child(UITheme.help("Даёт: " + "; ".join(PackedStringArray(dd.get("gives", []))) + "."))
		v.add_child(hh)
		var rs := sim.office.room_status(str(d))
		v.add_child(_cl("Кабинет: " + str(rs[1]), 12, [UITheme.BAD, UITheme.WARN, UITheme.GOOD][int(rs[0]) + 1]))
		var names: Array[String] = []
		for w in sim.office.staff(str(d)):
			var dk := sim.office.desk_k(w)
			names.append(w.full_name() + ("" if dk > 0.0 else " — нет стола!"))
		var prof := str(dd["prof"])
		var sh := UITheme.hbox(8)
		sh.add_child(_cl(("Сотрудник: " + ", ".join(names)) if not names.is_empty() else "Сотрудника нет", 12, UITheme.TEXT if not names.is_empty() else UITheme.MUTED))
		if names.is_empty():
			var pk: String = prof
			sh.add_child(UITheme.small("Найти: %s · %s" % [Worker.lc(str(Worker.PROF_NAMES[prof])), Defs.money_str(sim.ad_price(prof))], func() -> void:
				var err := sim.post_ad(pk)
				if err != "":
					hud.toast(err, Sim.LVL_WARN)
					return
				hud.open_window("staff")
				if hud.win:
					hud.win.select_tab("hire"), "Объявление по профессии — откроется найм"))
		v.add_child(sh)
		match str(d):
			"chief":
				v.add_child(_policy("rush", "Аврал: +25% к скорости, но брака больше", e > 0.0))
				v.add_child(_policy("overtime", "Сверхурочные: +2 часа за полуторную оплату", e > 0.0))
			"hr":
				var pol_hr := _policy("auto_hire", "Кадровик сам нанимает замену уволившимся", sim.dev.on("hr3"))
				if not sim.dev.on("hr3"):
					pol_hr.text = "Кадровик сам нанимает замену уволившимся (ступень «Кадровый резерв»)"
				v.add_child(pol_hr)


func _policy(key: String, text: String, enabled: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text + ("" if enabled else " (нужен отдел)")
	cb.button_pressed = bool(sim.office.policies.get(key, false))
	cb.disabled = not enabled
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(v: bool) -> void:
		sim.office.policies[key] = v
		if key == "rush" and v:
			sim.notify("Объявлен аврал! Рабочие ускорились, но брака станет больше.", Sim.LVL_WARN)
		elif key == "overtime" and v:
			sim.notify("Введены сверхурочные: смена длиннее на 2 часа, оплата за них полуторная.", Sim.LVL_INFO))
	return cb


# ---------------------------------------------------------------- исследования (техотдел)

## Разработки технолога внутри ветки «Техника»: компактно, со статусом и выбором.
func _dev_research() -> PanelContainer:
	var of := sim.office
	var c := UITheme.card(8, Color("#1a1e22"), UITheme.LINE)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.vbox(6)
	c.add_child(v)
	var hh := UITheme.hbox(8)
	hh.add_child(UITheme.label("Разработки технолога", 13, UITheme.TEXT, UITheme.f_semi))
	var rate := of.research_rate()
	hh.add_child(UITheme.label(("~%.1f очка за смену" % rate) if rate > 0.0 else "техотдел не работает — наймите технолога", 12, UITheme.MUTED if rate > 0.0 else UITheme.WARN))
	hh.add_child(UITheme.spacer())
	hh.add_child(UITheme.label("изучено %d из %d" % [of.research_done.size(), Defs.research.size()], 12, UITheme.MUTED))
	hh.add_child(UITheme.small("Все разработки", func() -> void:
		_open_sec("research"), "Управление → Разработки"))
	v.add_child(hh)
	if sim.office.research_cur != "":
		var rdc: Dictionary = Defs.research[sim.office.research_cur]
		v.add_child(_cl("Сейчас: «%s» · %d%%" % [str(rdc["name"]), int(float(of.research_pts.get(sim.office.research_cur, 0.0)) / float(rdc["cost"]) * 100.0)], 12, UITheme.ACCENT))
	v.add_child(_cl("Разработки теперь деревом: «Все разработки» — ветки, зависимости, что открывает каждая.", 12, UITheme.MUTED))
	return c


func _research() -> void:
	ResearchTree.build(self)   # 1.15: деревом, открывается с технологом


# ---------------------------------------------------------------- события, погода, проверки

func _section(text: String) -> void:
	content.add_child(UITheme.caption(text))


func _achievements() -> void:
	Achievements.load_all()
	_info("получено %d из %d" % [Achievements.got_count(), Achievements.defs.size()])
	_intro("Достижения общие для всех партий." + ("" if Achievements.counts(sim) else " В песочнице они не засчитываются."))
	var g := _cards(3)
	for a: Dictionary in Achievements.defs:
		var id := str(a["id"])
		var has := Achievements.got.has(id)
		var card := UITheme.card(10, Color("#262319") if has else UITheme.BG2, UITheme.ACCENT_D if has else UITheme.LINE)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = str(a["desc"])
		g.add_child(card)
		var h := UITheme.hbox(10)
		card.add_child(h)
		var ic := _icon(Tex.ui("medal" if has else "medal_off"), 30)
		ic.modulate = Color(1, 1, 1, 1.0 if has else 0.5)
		h.add_child(ic)
		var v := UITheme.vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_cl(str(a["name"]), 13, UITheme.TEXT if has else UITheme.MUTED, UITheme.f_semi))
		if has:
			v.add_child(_cl("получено " + str(Achievements.got[id]), 11, UITheme.ACCENT))
		else:
			var n := float(a.get("n", 1))
			var cur := clampf(Achievements.value(sim, a), 0.0, n)
			if n > 1.0:
				var txt := ("%s / %s" % [Defs.money_str(cur), Defs.money_str(n)]) if str(a.get("type", "")) == "money" else ("%d / %d" % [int(cur), int(n)])
				v.add_child(UITheme.meter(cur / n * 100.0, UITheme.INFO, 70, txt))
			else:
				v.add_child(_cl(str(a["desc"]), 11, UITheme.DIM))
		h.add_child(v)


func _wl(text: String, size: int = 14, col: Color = UITheme.TEXT) -> Label:
	var l := UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _events() -> void:
	match tab:
		"now":
			_events_now()
		"insp":
			_events_insp()
		"cal":
			_events_cal()
		"hist":
			_events_hist()


func _events_now() -> void:
	var st := sim.story
	var se := sim.season
	_info("%s · %s" % [se.season_name(), se.long_date()])
	var cols := _cards(2)
	var left := UITheme.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := UITheme.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	cols.add_child(right)
	# решения и тревоги
	var a := _card_in(left, "Ждут решения" if not st.letters.is_empty() else "Решений не ждёт ничего")
	for l: Dictionary in st.letters:
		var h := UITheme.hbox(8)
		h.add_child(_icon(Tex.ui(str(l.get("icon", "letter"))), 22))
		h.add_child(_cl(str(l["title"]), 13))
		var lc: Dictionary = l
		h.add_child(UITheme.small("Решить", func() -> void: hud.show_letter(lc)))
		a.add_child(h)
	if not st.fires.is_empty():
		var hf := UITheme.hbox(8)
		hf.add_child(_icon(Tex.ui("fire"), 22))
		hf.add_child(UITheme.para("ПОЖАР! Горит клеток: %d, идёт %d мин." % [st.fires.size(), int(sim.minute - st.fire_start)], 13, UITheme.BAD))
		var fc := sim.world.cell_of(int(st.fires.keys()[0]))
		hf.add_child(UITheme.small("Показать", func() -> void: hud.g.cam.focus_cell(fc)))
		a.add_child(hf)
	if st.strike.get("active", false):
		a.add_child(UITheme.para("Забастовка, %d-й день. Требование: %s." % [int(st.strike.get("days", 0)) + 1, st.demand_text(str(st.strike.get("demand", ""))).to_lower()], 13, UITheme.BAD))
	elif float(st.strike.get("promise_until", -1.0)) > sim.minute:
		a.add_child(UITheme.para("Обещано забастовщикам: %s — до %s." % [st.demand_text(str(st.strike.get("demand", ""))).to_lower(), sim.season.date_str(int(float(st.strike["promise_until"]) / 1440.0) + 1)], 13, UITheme.WARN))
	if st.low_mood_days > 0:
		a.add_child(UITheme.para("Рабочие недовольны уже %d %s подряд — дело идёт к забастовке." % [st.low_mood_days, Defs.plural(st.low_mood_days, "день", "дня", "дней")], 13, UITheme.WARN))
	# план месяца
	if not st.plan.is_empty():
		var got := int(sim.stats.get("shipped", 0)) - int(st.plan.get("base", 0))
		var tgt := maxi(1, int(st.plan.get("target", 1)))
		var pm := _card_in(left, "План месяца")
		pm.add_child(_cl("%s: отгружено %d из %d, осталось %d %s" % [Season.MONTHS[se.month()], got, tgt, se.dpm() - se.dom() + 1, Defs.plural(se.dpm() - se.dom() + 1, "день", "дня", "дней")], 13))
		var pb := UITheme.bar(minf(100.0, got * 100.0 / tgt), UITheme.GOOD if got >= tgt else UITheme.INFO, 300, 8)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pm.add_child(pb)
	# модификаторы
	var active: Array = []
	for m: Dictionary in st.mods:
		if float(m["until"]) > sim.minute and str(m.get("text", "")) != "":
			active.append(m)
	if not active.is_empty() or not st.perks.is_empty() or not st.receivables.is_empty():
		var md := _card_in(left, "Действует сейчас")
		for m2: Dictionary in active:
			var lh := (float(m2["until"]) - sim.minute) / 60.0
			var lt := ("%d ч" % int(ceil(lh))) if lh < 48.0 else ("%d дн." % int(ceil(lh / 24.0)))
			md.add_child(_cl("• %s — ещё %s" % [str(m2["text"]), lt], 13))
		for r: Dictionary in st.receivables:
			md.add_child(_cl("• Должник: %s — %s, срок %s" % [str(r["client"]), Defs.money_str(float(r["amount"])), sim.season.date_str(int(float(r["due"]) / 1440.0) + 1)], 13, UITheme.WARN))
		var pk := {"wear_k": "износ станков", "setup_k": "время переналадки", "defect_k": "брак", "haul_k": "скорость переноски"}
		for k in st.perks.keys():
			if pk.has(k):
				md.add_child(_cl("• Рацпредложения: %s ×%.2f" % [str(pk[k]), float(st.perks[k])], 13, UITheme.GOOD))
	var stc := _card_in(left, "Статистика")
	stc.add_child(_cl("травм за месяц: %d · пожаров всего: %d · забастовок: %d" % [st.injuries_month(), st.fires_total, st.strikes_total], 13, UITheme.MUTED))
	stc.add_child(_cl("проверок без замечаний: %d из %d" % [sim.inspect.clean, sim.inspect.total], 13, UITheme.MUTED))
	# погода
	var t := se.outside_temp()
	var w := _card_in(right, "Погода и отопление")
	var wtxt := "На улице %+d °C (днём около %+d)." % [int(round(t)), int(round(se.temp_day))]
	if se.is_snowing():
		wtxt += " Идёт снег."
	if se.snow_avg > 10.0:
		wtxt += " Снега на дорожках: %d%%." % int(se.snow_avg / 2.55)
	if se.ice:
		wtxt += " Гололёд!"
	w.add_child(UITheme.para(wtxt, 13, UITheme.TEXT))
	w.add_child(UITheme.para("Отопительный сезон: %s · батарей %d, каждая греет ~%d клеток." % ["идёт" if se.heating_season() else "нет", se.radiators, int(Defs.sea("radiator_cells"))], 12))
	var g := UITheme.grid(4, 14, 2)
	for rm in sim.rooms.list:
		if rm.type == "":
			continue
		var tc := float(se.room_temp.get(rm.id, t))
		var col := UITheme.TEXT
		if tc < Defs.sea("freezing_below"):
			col = Color("#9cd0f0")
		elif tc < Defs.sea("cold_below"):
			col = Color("#b8d8e8")
		elif tc > Defs.sea("hot_above"):
			col = UITheme.WARN
		g.add_child(_cl(rm.title(), 12, UITheme.MUTED))
		g.add_child(UITheme.label("%+d °C" % int(round(tc)), 12, col, UITheme.f_semi))
	w.add_child(g)
	if se.heating_season() and not se.cold_rooms().is_empty():
		w.add_child(UITheme.para("Холодно — поставьте батареи (Объекты → Быт). Ниже +%d °C люди мёрзнут и работают медленнее." % int(Defs.sea("cold_below")), 12, UITheme.WARN))
	var sand := CheckBox.new()
	sand.text = "Посыпать дорожки песком (%s в день, когда нужно)" % Defs.money_str(Defs.sea("sanding_cost_day"))
	sand.tooltip_text = "Подрядчик посыпает песком и чистит снег — меньше травм на льду"
	sand.button_pressed = se.sanding
	sand.focus_mode = Control.FOCUS_NONE
	sand.toggled.connect(func(v: bool) -> void: sim.season.sanding = v)
	w.add_child(sand)
	# рассказчик
	var n := _card_in(right, "Рассказчик", "Как часто и насколько тяжёлые события случаются на заводе")
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	for i in Story.MODES.size():
		ob.add_item(st.mode_name(Story.MODES[i]))
		if Story.MODES[i] == st.mode:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void:
		sim.story.mode = Story.MODES[i]
		rebuild(true))
	n.add_child(ob)
	n.add_child(UITheme.para(str(st.mdef().get("desc", "")), 12))


func _events_insp() -> void:
	var ins := sim.inspect
	_info("проверок без замечаний: %d из %d" % [ins.clean, ins.total])
	_intro("Плановые проверки объявляют за три дня, внезапные — не объявляют. Инспектор обходит завод: пока он идёт, нарушения можно успеть исправить. Повторное нарушение по предписанию — двойной штраф и остановка участка.")
	if ins.busy():
		var v := ins.visitor()
		var c := UITheme.card(10, Color("#2a2418"), UITheme.ACCENT_D)
		content.add_child(c)
		var h0 := UITheme.hbox(10)
		c.add_child(h0)
		h0.add_child(_icon(Tex.ui("inspect"), 28))
		h0.add_child(UITheme.para("Сейчас на заводе: %s. %s. Найдено нарушений: %d." % [ins.type_name(str(ins.visit["type"])), v.activity if v else "", (ins.visit.get("found", []) as Array).size()], 13, UITheme.WARN))
		if v:
			var vid := v.id
			h0.add_child(UITheme.small("Показать", func() -> void:
				hud.g.tool.select_worker(vid)
				hud.g.cam.focus_cell(v.cell())))
	var top := _cards(2)
	var a := _card_in(top, "Ближайшие проверки")
	if ins.queue.is_empty():
		a.add_child(UITheme.label("Пока не объявлено.", 13, UITheme.MUTED))
	for q: Dictionary in ins.queue:
		var t := str(q["type"])
		var when := sim.season.date_str(int(float(q["at"]) / 1440.0) + 1) if bool(q.get("announced", false)) or Inspections.VISIT_KINDS.has(t) else "дата неизвестна"
		a.add_child(_cl2(ins.type_name(t), when + ((" · %s" % str(q["why"])) if str(q.get("why", "")) != "" else ""), UITheme.TEXT, UITheme.WARN, 13))
	for p0: Dictionary in ins.prescriptions:
		a.add_child(_cl2("Предписание: " + ins.type_name(str(p0["type"])), "устранить до %s, потом повторная проверка" % sim.season.date_str(int(p0["due"])), UITheme.WARN, UITheme.MUTED, 13))
	var b := _card_in(top, "История")
	if ins.history.is_empty():
		b.add_child(UITheme.label("Проверок ещё не было.", 13, UITheme.MUTED))
	for hh: Dictionary in ins.history.slice(0, 6):
		var ok := int(hh["n"]) == 0
		var hr := UITheme.hbox(8)
		var cell := _cl2(ins.type_name(str(hh["type"])), sim.season.date_str(int(hh["day"])) + ("" if ok else " · %d наруш., штраф %s" % [int(hh["n"]), Defs.money_str(float(hh["fine"]))]), UITheme.TEXT, UITheme.MUTED if ok else UITheme.BAD, 13)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(cell)
		var sc := Control.new()
		sc.custom_minimum_size = Vector2(112, 28)
		sc.add_child(_stamp("ПРОВЕРЕНО" if ok else "ШТРАФ", STAMP_INK if ok else STAMP_RED, 104.0))
		hr.add_child(sc)
		b.add_child(hr)
	content.add_child(UITheme.caption("Что проверят прямо сейчас"))
	var g := _cards(2)
	for t2 in Defs.inspections.get("types", {}).keys():
		var tt := str(t2)
		if tt == "iso":
			continue
		var v3 := _card_in(g, ins.type_name(tt), "Требования:\n• " + "\n• ".join(PackedStringArray(ins.checklist(tt))))
		_insp_check(v3, tt)


## Текущее состояние по проверке: ✓ — всё в порядке, × — что сейчас нарушено.
func _insp_check(v: VBoxContainer, t: String) -> void:
	if t == "tax":
		v.add_child(_cl("Бухгалтерия: " + ("работает ✓" if sim.office.active("accounting") else "нет — риск штрафа высокий"), 12, UITheme.GOOD if sim.office.active("accounting") else UITheme.WARN))
		return
	var cur := sim.inspect.violations(t)
	if cur.is_empty():
		v.add_child(_cl("✓ нарушений нет", 12, UITheme.GOOD))
	for vi: Dictionary in cur.slice(0, 5):
		var c: Array = vi.get("cell", [-1, -1])
		v.add_child(fix_line("× %s · ~%s" % [str(vi["text"]), Defs.money_str(float(vi["fine"]) * sim.inspect.fine_k())], str(vi["text"]), str(vi.get("fix", "")), Vector2i(int(c[0]), int(c[1]))))
	if cur.size() > 5:
		v.add_child(_cl("…и ещё %d" % (cur.size() - 5), 12, UITheme.BAD))


## 1.20: красная строка «что не так» — наведите, чтобы прочитать, как исправить; нажмите — подробнее и место.
func fix_line(text: String, what: String, fix: String, cell: Vector2i = Vector2i(-1, -1), size: int = 12) -> Control:
	var l := UITheme.para(text + ("   → как исправить?" if fix != "" else ""), size, UITheme.BAD)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if fix == "" and cell.x < 0:
		return l
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	l.tooltip_text = ("Как исправить: " + fix if fix != "" else "") + "\nНажмите — подробнее" + (" и показать место" if cell.x >= 0 else "")
	l.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			hud.show_fix(what, fix, cell))
	return l


func _events_cal() -> void:
	var se := sim.season
	_info("сейчас: " + se.long_date())
	_intro("Игровой месяц — две недели, год — 168 дней. В конце каждого месяца подводится план: выполнили — репутация и настроение растут. Если план горит, можно объявить аврал (штурмовщина).")
	var grid := _cards(4)
	var temps: Array = Defs.seasons.get("month_temp", [])
	for m in 12:
		var cur := m == se.month()
		var p := UITheme.card(10, UITheme.BG3 if cur else UITheme.BG2, UITheme.ACCENT if cur else UITheme.LINE)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UITheme.vbox(1)
		p.add_child(v)
		var hh := UITheme.hbox(6)
		hh.add_child(UITheme.label(Season.MONTHS[m], 14, UITheme.ACCENT if cur else UITheme.TEXT, UITheme.f_semi))
		hh.add_child(UITheme.label("~%+d °C" % (int(temps[m]) if temps.size() == 12 else 0), 12, UITheme.MUTED))
		v.add_child(hh)
		for h: Dictionary in Defs.seasons.get("holidays", []):
			if int(h["month"]) == m:
				v.add_child(_cl("★ %s" % str(h["name"]), 12, UITheme.GOOD if bool(h.get("off", false)) else UITheme.INFO))
		var extra := ""
		match m:
			11, 0, 1:
				extra = "морозы, снег, отопление"
			2:
				extra = "таяние, гололёд"
			3:
				extra = "паводок, субботник"
			6:
				extra = "сезон отпусков"
			5, 7:
				extra = "жара в горячих цехах"
			10:
				extra = "заказчики закрывают год"
		if extra != "":
			v.add_child(_cl(extra, 11, UITheme.MUTED))
		grid.add_child(p)


func _events_hist() -> void:
	var ar: Array = sim.story.archive
	_info("%d %s" % [ar.size(), Defs.plural(ar.size(), "запись", "записи", "записей")])
	if ar.is_empty():
		content.add_child(UITheme.empty("Пока ничего не случилось. Это ненадолго."))
	for e: Dictionary in ar:
		var ic := _icon(Tex.ui(str(e.get("icon", "letter"))), 22)
		ic.modulate = [UITheme.INFO, UITheme.GOOD, UITheme.WARN, UITheme.BAD][clampi(int(e.get("level", 0)), 0, 3)]
		var txt := _cl(str(e["text"]).replace("\n", " "), 12, UITheme.MUTED)
		txt.tooltip_text = str(e["text"])
		_trow([[ic, 26], [_cl(str(e.get("date", "")), 12, UITheme.MUTED), 150], [_cl(str(e["title"]), 13, UITheme.TEXT, UITheme.f_semi), 300], [txt, -1]], Callable(), 32.0, str(e["text"]))


# ---------------------------------------------------------------- многотиражка

const PAPER_BG := Color("#efe8d4")
const PAPER_INK := Color("#2a2620")
const PAPER_RED := Color("#a8322a")


func _paper() -> void:
	var pp := sim.paper
	if pp.issues.is_empty():
		content.add_child(_wl("Первый номер выйдет в понедельник. Редакция собирает новости: передовиков, происшествия, итоги недели и, конечно, объявления.", 15, UITheme.MUTED))
		return
	var idx := clampi(int(tab), 0, pp.issues.size() - 1)
	var issue: Dictionary = pp.issues[idx]
	# выбор номера
	var nav := UITheme.hbox(8)
	nav.add_child(UITheme.label("Номер:", 14, UITheme.MUTED))
	for i in mini(pp.issues.size(), 8):
		var b := Button.new()
		b.text = "№ %d" % int(pp.issues[i]["no"])
		b.toggle_mode = true
		b.button_pressed = i == idx
		b.focus_mode = Control.FOCUS_NONE
		var ii := i
		b.pressed.connect(func() -> void:
			tab = str(ii)
			rebuild(true))
		nav.add_child(b)
	content.add_child(nav)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UITheme.sb(PAPER_BG, Color("#c9bf9f"), 1, 2, 26, 20))
	content.add_child(sheet)
	var v := UITheme.vbox(8)
	sheet.add_child(v)
	# 1.17: шапка газеты — эмблема завода с двух сторон от названия, под ним — чья газета
	var mh := UITheme.hbox(16)
	mh.alignment = BoxContainer.ALIGNMENT_CENTER
	mh.add_child(Emblem.View.new(Company.emblem_of(sim), 54.0))
	var mast := UITheme.label(str(Defs.paper.get("title", "")).to_upper(), 40, PAPER_RED, UITheme.f_semi)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh.add_child(mast)
	mh.add_child(Emblem.View.new(Company.emblem_of(sim), 54.0))
	v.add_child(mh)
	var sub := UITheme.label("Газета коллектива %s · выходит по понедельникам · № %d · %s" % [Company.title(sim), int(issue["no"]), str(issue["date"])], 13, PAPER_INK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var line := ColorRect.new()
	line.color = PAPER_INK
	line.custom_minimum_size = Vector2(0, 3)
	v.add_child(line)
	var items: Array = issue["items"]
	var lead: Dictionary = {}
	for it: Dictionary in items:
		if bool(it.get("lead", false)):
			lead = it
			break
	if not lead.is_empty():
		v.add_child(_paper_text(str(lead["rubric"]).to_upper(), 12, PAPER_RED))
		v.add_child(_paper_text(str(lead["title"]), 26, PAPER_INK, true))
		v.add_child(_paper_text(str(lead["text"]), 15, PAPER_INK))
		var l2 := ColorRect.new()
		l2.color = Color(PAPER_INK, 0.4)
		l2.custom_minimum_size = Vector2(0, 1)
		v.add_child(l2)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	v.add_child(cols)
	var c1 := UITheme.vbox(10)
	var c2 := UITheme.vbox(10)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c1)
	var sep := ColorRect.new()
	sep.color = Color(PAPER_INK, 0.3)
	sep.custom_minimum_size = Vector2(1, 0)
	cols.add_child(sep)
	cols.add_child(c2)
	var n := 0
	for it2: Dictionary in items:
		if it2 == lead:
			continue
		var col := c1 if n % 2 == 0 else c2
		n += 1
		var box := UITheme.vbox(2)
		box.add_child(_paper_text(str(it2.get("rubric", "")).to_upper(), 11, PAPER_RED))
		if str(it2.get("title", "")) != "":
			box.add_child(_paper_text(str(it2["title"]), 17, PAPER_INK, true))
		box.add_child(_paper_text(str(it2.get("text", "")), 14, PAPER_INK))
		col.add_child(box)


func _paper_text(t: String, size: int, col: Color, bold: bool = false) -> Label:
	var l := UITheme.label(t, size, col, UITheme.f_semi if bold else null)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(300, 0)
	return l



# ---------------------------------------------------------------- цели и рост завода

func _goal_rows(goals: Array, parent: Control = null, routes: bool = false) -> void:
	var pg := sim.progress
	var host: Control = parent if parent else content
	for g: Dictionary in goals:
		var st: Array = pg.goal_state(g)
		var ok := bool(st[0])
		var h := UITheme.hbox(8)
		var mark := UITheme.label("✓" if ok else ("◇" if routes else "○"), 16, UITheme.GOOD if ok else UITheme.MUTED, UITheme.f_semi)
		mark.custom_minimum_size = Vector2(18, 0)
		h.add_child(mark)
		if routes:
			var rl := UITheme.chip(str(g.get("route", "")), UITheme.INFO)
			rl.custom_minimum_size = Vector2(78, 0)
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(rl)
		h.add_child(UITheme.para(str(g.get("text", "")), 13, UITheme.GOOD if ok else UITheme.TEXT))
		h.add_child(UITheme.label(str(st[1]), 12, UITheme.MUTED))
		match str(g.get("type", "")):
			"ooo":
				if not ok:
					h.add_child(UITheme.small("Оформить · 50 000 ₽", func() -> void:
						var err := sim.progress.register_ooo()
						if err != "":
							hud.toast(err, Sim.LVL_WARN)
						rebuild(true)))
			"roof":
				if not ok and sim.progress.roof_fix_at < 0.0:
					h.add_child(UITheme.small("Ремонт · 180 000 ₽", func() -> void:
						var err2 := sim.progress.repair_roof()
						if err2 != "":
							hud.toast(err2, Sim.LVL_WARN)
						rebuild(true)))
			"arrears":
				if not ok:
					h.add_child(UITheme.small("Выплатить всё", func() -> void:
						var err3 := sim.progress.pay_arrears()
						if err3 != "":
							hud.toast(err3, Sim.LVL_WARN)
						rebuild(true)))
		host.add_child(h)


func _goals() -> void:
	var pg := sim.progress
	if tab == "ach":
		_achievements()
		return
	match tab:
		"stage":
			_info("этап %d из %d · %s" % [pg.stage, Progress.STAGE_COUNT, str(Defs.profiles.get(pg.profile, {}).get("name", ""))])
			var cols := _cards(2)
			var a := _card_in(cols)
			a.add_child(UITheme.caption("Сейчас", UITheme.ACCENT))
			a.add_child(UITheme.label("«%s»" % pg.stage_name(), 20, UITheme.TEXT, UITheme.f_semi))
			a.add_child(UITheme.para(str(Defs.profiles.get(pg.profile, {}).get("mechanic", "")), 12, UITheme.INFO))
			if pg.all_open:
				a.add_child(UITheme.para("Песочница: всё открыто сразу.", 12))
			if pg.stage < Progress.STAGE_COUNT:
				a.add_child(UITheme.caption("Чтобы стать «%s»" % pg.stage_name(pg.stage + 1)))
				_goal_rows(pg.stage_goals(), a)
				if pg.choice_need() > 0:
					a.add_child(UITheme.caption("И любые %d на выбор · выполнено %d" % [pg.choice_need(), pg.choice_done()], UITheme.ACCENT if pg.choice_done() >= pg.choice_need() else UITheme.MUTED))
					_goal_rows(pg.stage_choice().get("list", []), a, true)
				a.add_child(UITheme.para("Откроется: " + str(pg.stage_def(pg.stage + 1).get("opens", "")) + ".", 12, UITheme.INFO))
			else:
				a.add_child(UITheme.para("Вы — градообразующее предприятие. Дальше — бесконечная игра: растите, сколько хватит места.", 13, UITheme.GOOD))
			var b := _card_in(cols, "Путь завода")
			for i in range(1, Progress.STAGE_COUNT + 1):
				var sd: Dictionary = pg.stage_def(i)
				var cur := i == pg.stage
				var col := UITheme.GOOD if i < pg.stage else (UITheme.ACCENT if cur else UITheme.MUTED)
				var h := UITheme.hbox(10)
				var num := UITheme.label("✓" if i < pg.stage else str(i), 13, UITheme.ACCENT_T if cur else col, UITheme.f_semi)
				num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				num.custom_minimum_size = Vector2(24, 24)
				num.add_theme_stylebox_override("normal", UITheme.sb(UITheme.ACCENT if cur else Color(col.r, col.g, col.b, 0.15), Color(0, 0, 0, 0), 0, 12, 0, 2))
				num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
				h.add_child(num)
				var vv := UITheme.vbox(0)
				vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				vv.add_child(_cl("%s · %s чел." % [str(sd.get("name", "")), str(sd.get("people", ""))], 13, UITheme.TEXT if cur else col, UITheme.f_semi))
				vv.add_child(UITheme.para(str(sd.get("opens", "")), 11, UITheme.MUTED))
				h.add_child(vv)
				b.add_child(h)
		"rating":
			_info("рейтинг завода " + pg.stars_text())
			_intro("Звёзды складываются из пяти показателей и пересчитываются каждое утро. Сценарии и этапы требуют определённого числа звёзд.")
			var tips := {"output": "Сдавайте заказы в срок и выполняйте месячный план.", "quality": "Меньше брака: опытные люди, исправные станки, мастер, ОТК.",
				"safety": "Без травм и пожаров, без нарушений после проверок. Аптечки, огнетушители, отдых.", "people": "Настроение: столовая, бытовка, зарплата, отопление.",
				"finance": "Деньги на счёте растут, долги под контролем."}
			var big := UITheme.label(pg.stars_text(), 34, UITheme.ACCENT, UITheme.f_semi)
			content.add_child(big)
			var g := _cards(5)
			for k in Progress.RATING_NAMES.keys():
				var val := float(pg.rating.get(k, 0.5))
				var col2 := UITheme.ramp(val)
				var v := _card_in(g)
				v.add_child(UITheme.caption(str(Progress.RATING_NAMES[k])))
				v.add_child(UITheme.label("%d%%" % int(round(val * 100.0)), 22, col2, UITheme.f_semi))
				var pb := UITheme.bar(val * 100.0, col2, 100, 6)
				pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				v.add_child(pb)
				v.add_child(UITheme.para(str(tips[k]), 11))
		"scn":
			var sd2 := pg.sdef()
			_info("«%s»" % str(sd2.get("name", "")))
			var c := _card_in(content)
			c.add_child(UITheme.label("Сценарий «%s»" % str(sd2.get("name", "")), 18, UITheme.TEXT, UITheme.f_semi))
			c.add_child(UITheme.para(str(sd2.get("desc", "")), 13))
			if pg.scn_done:
				c.add_child(UITheme.label("★ Сценарий пройден! Можно продолжать без ограничений.", 14, UITheme.GOOD, UITheme.f_semi))
			var goals: Array = pg.scenario_goals()
			if goals.is_empty():
				c.add_child(UITheme.para("Целей нет — свободная игра.", 13))
			else:
				c.add_child(UITheme.caption("Цели сценария"))
				_goal_rows(goals, c)
			if pg.roof_leak and not goals.any(func(g2: Dictionary) -> bool: return str(g2.get("type", "")) == "roof"):
				_goal_rows([{"type": "roof", "text": "Отремонтировать крышу"}], c)
			if not pg.dogs.is_empty():
				c.add_child(UITheme.para("На территории %d %s — %s." % [pg.dogs.size(), Defs.plural(pg.dogs.size(), "собака", "собаки", "собак"), "заводские, охраняют склад" if pg.dogs_tame else "бродячие, людям неуютно"], 13, UITheme.INFO))




# ---------------------------------------------------------------- доска почёта

## Доска почёта: лидеры недели, лучшие по заслугам и победители прошлых недель — фото на красном бархате.
func _honor() -> void:
	var has_board := false
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "honor_board":
			has_board = true
			break
	_info("лучший работник недели — каждый понедельник")
	_intro("Очки недели: операции у станков, перевозки, пойманные несуны. По понедельникам лучший попадает на доску почёта. Если на заводе висит настоящая доска почёта (Объекты → Декор), человеку приятно, а остальным есть к чему стремиться.")
	if not has_board:
		var hb := UITheme.chip("на заводе нет доски — Объекты → Декор", UITheme.WARN, "Без доски фото «вешают» только здесь: настроения не прибавляет")
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header_extra.add_child(hb)
	var board := PanelContainer.new()
	var bsb := UITheme.sbs(FactoryUI.HONOR_RED, FactoryUI.GOLD.darkened(0.2), 3, 6, 22, 14, 10, 0.5, 4)
	board.add_theme_stylebox_override("panel", bsb)
	content.add_child(board)
	var v := UITheme.vbox(10)
	board.add_child(v)
	var t1 := UITheme.label("ДОСКА ПОЧЁТА", 26, FactoryUI.GOLD, UITheme.f_caps)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t1)
	var t2 := UITheme.label("лучшие люди нашего завода", 13, FactoryUI.CREAM.darkened(0.15))
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t2)
	var row := UITheme.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	# лидеры недели
	var staff: Array = sim.workers.filter(func(w: Worker) -> bool: return not w.is_itr())
	var lead: Array = staff.filter(func(w: Worker) -> bool: return w.week_score > 0)
	lead.sort_custom(func(a: Worker, b: Worker) -> bool: return a.week_score > b.week_score)
	var lv := UITheme.vbox(6)
	lv.add_child(_honor_cap("Лидеры этой недели"))
	var lh := UITheme.hbox(10)
	lv.add_child(lh)
	if lead.is_empty():
		var e := UITheme.label("Неделя только началась —\nочков ещё ни у кого нет.", 13, FactoryUI.CREAM.darkened(0.25))
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.custom_minimum_size = Vector2(300, 150)
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lh.add_child(e)
	for i in mini(3, lead.size()):
		var w: Worker = lead[i]
		lh.add_child(_honor_cell(w, ["1-е место", "2-е место", "3-е место"][i] + " · %d оч." % w.week_score, i == 0))
	row.add_child(lv)
	row.add_child(_honor_sep())
	# по заслугам
	var mv := UITheme.vbox(6)
	mv.add_child(_honor_cap("По заслугам"))
	var mh := UITheme.hbox(10)
	mv.add_child(mh)
	var picks: Array = []
	var vet: Worker = null
	var gold: Worker = null
	var men: Worker = null
	var men_n := 0
	for w2: Worker in staff:
		if w2.days_worked > 0 and (vet == null or w2.days_worked > vet.days_worked):
			vet = w2
		if gold == null or w2.skill(w2.main_skill()) > gold.skill(gold.main_skill()):
			gold = w2
		var n := sim.training.apprentices(w2).size()
		if n > men_n:
			men_n = n
			men = w2
	if vet:
		picks.append([vet, "ветеран завода · %d %s" % [vet.days_worked, Defs.plural(vet.days_worked, "смена", "смены", "смен")]])
	if gold and gold != vet:
		picks.append([gold, "золотые руки · %s %d" % [str(Worker.SKILL_NAMES.get(gold.main_skill(), "")).to_lower(), gold.skill(gold.main_skill())]])
	if men and men != vet and men != gold:
		picks.append([men, "лучший наставник · %d %s" % [men_n, Defs.plural(men_n, "ученик", "ученика", "учеников")]])
	if picks.is_empty():
		var e2 := UITheme.label("Наберите людей —\nи будет кого отметить.", 13, FactoryUI.CREAM.darkened(0.25))
		e2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e2.custom_minimum_size = Vector2(260, 150)
		e2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mh.add_child(e2)
	for pk: Array in picks:
		mh.add_child(_honor_cell(pk[0], str(pk[1]), false))
	row.add_child(mv)
	# прошлые недели
	v.add_child(_honor_rule())
	v.add_child(_honor_cap("Лучшие прошлых недель"))
	var ph := UITheme.hbox(12)
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(ph)
	if sim.honor_log.is_empty():
		var e3 := UITheme.label("Первое фото повесят в понедельник.", 13, FactoryUI.CREAM.darkened(0.25))
		e3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.add_child(e3)
	for hd: Dictionary in sim.honor_log.slice(0, 7):
		var cell := FactoryUI.honor_photo(hd.get("look", {}), int(hd.get("age", 35)), 70.0, str(hd.get("last", "")), str(hd.get("first", "")), "%s · день %d" % [str(hd.get("prof", "")).to_lower(), int(hd.get("day", 0))], false)
		cell.modulate = Color(1, 1, 1, 1) if sim.get_worker(int(hd.get("id", -1))) else Color(0.8, 0.8, 0.8, 0.85)
		ph.add_child(cell)


func _honor_cell(w: Worker, why: String, big: bool) -> Control:
	var c := FactoryUI.honor_photo(w.look, w.age, maxf(w.mood, 62.0), w.last, w.first, why, big)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.tooltip_text = "%s, %s. Показать на заводе" % [w.full_name(), w.title_lc()]
	var wid := w.id
	c.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			hud.select_worker(wid)
			closed.emit())
	return c


func _honor_cap(text: String) -> Label:
	var l := UITheme.label(text.to_upper(), 12, FactoryUI.GOLD, UITheme.f_caps)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _honor_sep() -> Control:
	var r := ColorRect.new()
	r.color = Color(FactoryUI.GOLD, 0.35)
	r.custom_minimum_size = Vector2(1, 0)
	return r


func _honor_rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(FactoryUI.GOLD, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	return r


const STAMP_INK := Color("#7a74e8")   ## фиолетовые чернила (на тёмном фоне — посветлее)
const STAMP_RED := Color("#e0574a")


## Небольшой прямоугольный штамп для строк таблиц.
func _stamp(text: String, col: Color, w: float) -> Stamp:
	var st := Stamp.box_stamp(PackedStringArray([text]), col, minf(w, Stamp.fit_w(text, 11)), 24.0, -3.0 + float(text.hash() % 5) * 0.8)
	st.position = Vector2(2, 1)
	return st


# ---------------------------------------------------------------- рынок 1.8: конкуренты, графики, страхование, ISO, главный инженер

static var chart_range := 28


## Заказы → Конкуренты: наша доля рынка, ценовая политика и заводы региона.
func _compet() -> void:
	var mk := sim.market
	_info("наша доля рынка %d%% · заявок ×%.2f" % [int(roundf(mk.share * 100.0)), mk.inquiry_k()])
	_intro("Заказчики выбирают между нами и соседними заводами. Нашу долю определяют мощность (станочники), качество, доля заказов, сданных вовремя, репутация, цены и сертификат ISO 9001. Чем выше конкурентоспособность — тем больше заявок каждое утро.")
	var g := _cards(3)
	var a := _card_in(g, "Наша доля рынка")
	var prev := float(mk.share_hist[mk.share_hist.size() - 1]["ours"]) if not mk.share_hist.is_empty() else mk.share
	var dlt := mk.share - prev
	var sh := UITheme.hbox(8)
	sh.add_child(UITheme.label("%d%%" % int(roundf(mk.share * 100.0)), 30, UITheme.ACCENT, UITheme.f_semi))
	if absf(dlt) >= 0.005:
		var dl := UITheme.label("%s%d%% за неделю" % ["+" if dlt > 0 else "−", int(roundf(absf(dlt) * 100.0))], 13, UITheme.GOOD if dlt > 0 else UITheme.BAD)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sh.add_child(dl)
	a.add_child(sh)
	var mb := UITheme.bar(mk.share * 100.0, UITheme.ACCENT, 100, 6)
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_child(mb)
	a.add_child(UITheme.para("заводов в районе: %d" % (mk.alive_comps().size() + 1), 12))
	var b := _card_in(g, "Ценовая политика", "Демпинг — цены −10%: заявок на треть больше, но маржа тоньше и соседи могут начать войну цен. Премиум — цены +12%: заявок меньше; с сертификатом ISO 9001 заказчики почти не уходят.")
	b.add_child(UITheme.segmented([["dump", "Демпинг", str(Market.POLICIES["dump"]["desc"])], ["market", "По рынку", ""], ["premium", "Премиум", str(Market.POLICIES["premium"]["desc"])]], mk.policy, func(k: String) -> void:
		mk.policy = k
		rebuild(true)))
	b.add_child(UITheme.para(str(mk.pol()["desc"]), 12))
	if mk.war_active():
		b.add_child(UITheme.chip("у соседей война цен", UITheme.BAD, "Заявок −15%, пока она идёт (если мы не демпингуем)"))
	var c := _card_in(g, "Конкурентоспособность", "Множитель числа заявок: качество из рейтинга, доля заказов, сданных вовремя, ценовая политика и сертификат.")
	var q := float(sim.progress.rating.get("quality", 0.5))
	for row: Array in [["Качество", "%d%%" % int(roundf(q * 100.0)), UITheme.ramp(q)], ["Сдано вовремя", "%d%%" % int(roundf(mk.ontime() * 100.0)), UITheme.ramp(mk.ontime())],
			["ISO 9001", "есть" if mk.iso_ok() else "нет", UITheme.GOOD if mk.iso_ok() else UITheme.MUTED], ["Заявок", "×%.2f" % mk.inquiry_k(), UITheme.ACCENT]]:
		var rh := UITheme.hbox(8)
		var rl := UITheme.label(str(row[0]), 13, UITheme.MUTED)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh.add_child(rl)
		rh.add_child(UITheme.label(str(row[1]), 13, row[2], UITheme.f_semi))
		c.add_child(rh)
	_thead([["", 14], ["Завод", -1], ["Специализация", 250], ["Цены", 110], ["Качество", 90], ["Доля рынка", 170]])
	var rows: Array = mk.alive_comps()
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["share"]) > float(y["share"]))
	var me := ColorRect.new()
	me.color = UITheme.ACCENT
	me.custom_minimum_size = Vector2(10, 10)
	_trow([[me, 14], [_cl2("Наш завод", sim.progress.stage_name(), UITheme.ACCENT), -1], [_cl(", ".join(PackedStringArray(_our_procs())), 12, UITheme.MUTED), 250],
		[_cl(str(mk.pol()["name"]).to_lower(), 13, UITheme.TEXT), 110], [_cl("%d%%" % int(roundf(q * 100.0)), 13), 90],
		[UITheme.meter(mk.share * 100.0, UITheme.ACCENT, 90, "%d%%" % int(roundf(mk.share * 100.0))), 170]], Callable(), 40.0)
	for cp: Dictionary in rows:
		var sw := ColorRect.new()
		sw.color = mk.comp_color(str(cp["id"]))
		sw.custom_minimum_size = Vector2(10, 10)
		var war := int(cp["war_until"]) >= sim.day()
		var pr := float(cp["price"])
		var ptxt := "война цен" if war else ("ниже рынка" if pr < 0.97 else ("выше рынка" if pr > 1.03 else "по рынку"))
		_trow([[sw, 14], [_cl2(str(cp["name"]), "~%d станков" % int(roundf(float(cp["size"]) * 3.0)), UITheme.TEXT), -1], [_cl(mk._spec_text(cp), 12, UITheme.MUTED), 250],
			[_cl(ptxt, 13, UITheme.BAD if war else UITheme.TEXT), 110], [_cl("%d%%" % int(roundf(float(cp["quality"]) * 100.0)), 13), 90],
			[UITheme.meter(float(cp["share"]) * 100.0, mk.comp_color(str(cp["id"])), 90, "%d%%" % int(roundf(float(cp["share"]) * 100.0))), 170]], Callable(), 40.0)
	var cc := _card_in(content, "Доля рынка по дням")
	cc.add_child(_share_chart(150.0))


## Легенда графика: цветная метка и название серии.
func _legend(ser: Array) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 12)
	f.add_theme_constant_override("v_separation", 2)
	for s0: Dictionary in ser:
		var h := UITheme.hbox(5)
		var sw := ColorRect.new()
		sw.color = s0["color"]
		sw.custom_minimum_size = Vector2(10, 3 if str(s0.get("kind", "line")) == "line" else 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		h.add_child(UITheme.label(str(s0["name"]), 11, UITheme.MUTED))
		f.add_child(h)
	return f


func _our_procs() -> Array[String]:
	var out: Array[String] = []
	for pr in sim.prod.processes_available():
		out.append(Defs.process_name(str(pr)).to_lower())
	return out


## Последние N дней статистики (N = chart_range; 0 — всё).
func _hist() -> Array:
	var h: Array = sim.market.hist
	if chart_range > 0 and h.size() > chart_range:
		return h.slice(h.size() - chart_range)
	return h


func _hist_labels(h: Array) -> Array:
	return h.map(func(e: Dictionary) -> String: return "день %d" % int(e["d"]))


func _share_chart(hgt: float) -> ChartView:
	var h := _hist()
	var ser: Array = [{"name": "Наш завод", "color": UITheme.ACCENT, "values": h.map(func(e: Dictionary) -> float: return float(e["share"])), "width": 3.0, "fill": true}]
	for cp: Dictionary in sim.market.comps:
		var id := str(cp["id"])
		var vals := h.map(func(e: Dictionary) -> float: return float((e.get("cs", {}) as Dictionary).get(id, 0.0)))
		if vals.any(func(v: float) -> bool: return v > 0.0):
			ser.append({"name": str(cp["name"]), "color": sim.market.comp_color(id), "values": vals, "width": 1.5})
	var cv := ChartView.new().setup(ser, _hist_labels(h), "pct")
	cv.custom_minimum_size.y = hgt
	return cv


## Финансы → Графики: деньги, выручка и расходы, доля рынка, настроение и репутация.
func _finance_charts() -> void:
	_info("каждая точка — день")
	_intro("Наведите мышь на график — увидите значения за день. Статистика копится с начала игры (до года).")
	header_extra.add_child(UITheme.segmented([["14", "2 недели"], ["28", "4 недели"], ["84", "12 недель"], ["0", "всё"]], str(chart_range), func(k: String) -> void:
		chart_range = int(k)
		rebuild(true)))
	var h := _hist()
	var lab := _hist_labels(h)
	var g := _cards(2)
	var a := _card_in(g, "Деньги на счёте")
	var cv := ChartView.new().setup([{"name": "Деньги", "color": UITheme.ACCENT, "values": h.map(func(e: Dictionary) -> float: return float(e["money"])), "fill": true, "width": 2.5}], lab, "money", false)
	cv.custom_minimum_size.y = 230
	a.add_child(cv)
	var b := _card_in(g, "Выручка и расходы по дням", "Поступления (оплата заказов, гранты) и все расходы за день. Кредиты не учитываются.")
	if not sim.office.active("accounting"):
		b.add_child(_lock_card("accounting", "выручка и расходы по дням.", true))
	else:
		var cv2 := ChartView.new().setup([{"name": "Пришло", "color": UITheme.GOOD, "values": h.map(func(e: Dictionary) -> float: return float(e["rev"])), "kind": "bar"},
			{"name": "Ушло", "color": UITheme.BAD, "values": h.map(func(e: Dictionary) -> float: return float(e["exp"])), "kind": "bar"}], lab, "money")
		cv2.custom_minimum_size.y = 230
		b.add_child(_legend(cv2.series))
		b.add_child(cv2)
	var c := _card_in(g, "Доля рынка")
	if sim.office.active("sales"):
		var sc := _share_chart(230.0)
		c.add_child(_legend(sc.series))
		c.add_child(sc)
	else:
		c.add_child(_lock_card("sales", "доли рынка — наша и конкурентов — по неделям.", true))
	var d := _card_in(g, "Люди и репутация", "Среднее настроение рабочих и репутация завода, 0–100.")
	if not sim.office.active("hr"):
		d.add_child(_lock_card("hr", "среднее настроение коллектива по дням.", true))
		return
	var cv3 := ChartView.new().setup([{"name": "Настроение", "color": UITheme.GOOD, "values": h.map(func(e: Dictionary) -> float: return float(e["mood"]))},
		{"name": "Репутация", "color": UITheme.INFO, "values": h.map(func(e: Dictionary) -> float: return float(e["rep"]))}], lab, "num")
	cv3.custom_minimum_size.y = 230
	d.add_child(_legend(cv3.series))
	d.add_child(cv3)


## Прогноз кассы на две недели (бухгалтер): оплаты заказов к сроку минус зарплаты, аренда,
## платежи по кредитам и лизингу, страховка.
func cash_forecast() -> Dictionary:
	var inflow := 0.0
	for o: Dictionary in sim.orders.by_status(["active", "ready", "shipping"]):
		if float(o["deadline"]) - sim.minute <= 14.0 * 1440.0:
			inflow += float(o["price"]) * sim.orders.remaining(o)
	var wages := 0.0
	for w in sim.workers:
		wages += float(w.wage) * 10.0
	var rent := Defs.b("rent_per_day") * 14.0
	var fin := 0.0
	for l: Dictionary in sim.office.loans:
		fin += float(l["payment"]) * 2.0
	for le: Dictionary in sim.market.leases:
		fin += float(le["payment"]) * 2.0
	for k in sim.market.insurance.keys():
		fin += sim.market.premium(str(k)) * 2.0
	var end := sim.money + inflow - wages - rent - fin
	return {"end": end, "text": "заказы +%s, зарплаты −%s, аренда −%s, кредиты и полисы −%s" % [Defs.money_str(inflow), Defs.money_str(wages), Defs.money_str(rent), Defs.money_str(fin)]}


## Финансы → Страхование: три полиса, взнос по понедельникам.
func _finance_insurance() -> void:
	var mk := sim.market
	var week := 0.0
	for k in mk.insurance.keys():
		week += mk.premium(str(k))
	var paid := 0.0
	for k2 in mk.paid_claims.keys():
		paid += float(mk.paid_claims[k2])
	_info("полисов %d · взносы %s в неделю · выплачено %s" % [mk.insurance.size(), Defs.money_str(week), Defs.money_str(paid)])
	_intro("Страховая компания «Заводская защита». Взнос — по понедельникам, полис начинает действовать со следующего дня. Штрафы проверок не страхуются — по закону их платит сам завод.")
	var g := _cards(3)
	for kind in Market.INSURANCE.keys():
		var d: Dictionary = Market.INSURANCE[kind]
		var on := mk.insurance.has(kind)
		var v := _card_in(g)
		var h := UITheme.hbox(8)
		h.add_child(_icon(Tex.ui(str(d["icon"])), 22))
		h.add_child(UITheme.label(str(d["name"]), 15, UITheme.TEXT, UITheme.f_semi))
		v.add_child(h)
		v.add_child(UITheme.para(str(d["desc"]), 12))
		v.add_child(UITheme.label("%s в неделю" % Defs.money_str(mk.premium(str(kind))), 18, UITheme.ACCENT if not on else UITheme.TEXT, UITheme.f_semi))
		var pc := float(mk.paid_claims.get(kind, 0.0))
		v.add_child(UITheme.label("выплачено: %s" % Defs.money_str(pc) if pc > 0.0 else ("действует с дня %d" % (int((mk.insurance[kind] as Dictionary).get("since", 0)) + 1) if on else "не оформлен"), 12, UITheme.GOOD if pc > 0.0 or on else UITheme.MUTED))
		var kk := str(kind)
		var bt: Button
		if not on:
			bt = UITheme.primary("Оформить", func() -> void:
				mk.toggle_insurance(kk, true)
				rebuild(true))
		else:
			bt = UITheme.ghost("Расторгнуть полис", func() -> void:
				mk.toggle_insurance(kk, false)
				rebuild(true), "", UITheme.BAD)
		bt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(bt)


## Управление → ISO 9001.
func _iso() -> void:
	var mk := sim.market
	var st := str(mk.iso.get("status", "none"))
	_info("сертификат: " + mk.iso_text())
	_intro("ISO 9001 — международный стандарт системы менеджмента качества. Сертификат даёт +12% к заявкам, премиальные цены без потери заказчиков, контракты чаще, экспорт — уже с этапа «Малое предприятие». Две рекламации за срок действия — сертификат приостановят.")
	var g := _cards(2)
	var a := _card_in(g)
	var top := UITheme.hbox(14)
	var sc := Control.new()
	sc.custom_minimum_size = Vector2(110, 110)
	var ok := st == "ok"
	sc.add_child(Stamp.round_stamp("ISO 9001 • СЕРТИФИЦИРОВАНО • " if ok else "ISO 9001 • СИСТЕМА КАЧЕСТВА • ", PackedStringArray(["ДО ДНЯ", str(int(mk.iso.get("until", 0)))] if ok else ["НЕТ", "СЕРТ."]), Color("#7a74e8") if ok else Color("#6f7780"), 108.0, -10.0))
	top.add_child(sc)
	var tv := UITheme.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UITheme.label({"ok": "Сертификат действует", "audit": "Аудит назначен", "remarks": "Есть несоответствия", "suspended": "Приостановлен", "expired": "Истёк"}.get(st, "Сертификата нет"), 20, UITheme.GOOD if ok else (UITheme.INFO if st == "audit" else (UITheme.BAD if st in ["remarks", "suspended"] else UITheme.TEXT)), UITheme.f_semi))
	var it := mk.iso_text()
	tv.add_child(UITheme.para(it.substr(0, 1).to_upper() + it.substr(1) + ".", 13))
	if ok:
		tv.add_child(UITheme.para("Рекламаций за срок: %d из 2 допустимых." % int(mk.iso.get("reclam", 0)), 12, UITheme.WARN if int(mk.iso.get("reclam", 0)) > 0 else UITheme.MUTED))
	var cost := Market.ISO_RENEW if ok else Market.ISO_COST
	var btxt := "Надзорный аудит · %s" % Defs.money_str(cost) if ok or st == "expired" else "Заказать аудит · %s" % Defs.money_str(cost)
	var bt := UITheme.primary(btxt, func() -> void:
		var err := mk.iso_apply()
		if err != "":
			hud.toast(err, Sim.LVL_WARN)
		rebuild(true), "Аудитор приедет через три дня и проверит требования на тот момент")
	bt.disabled = st == "audit" or (ok and int(mk.iso.get("until", 0)) - sim.day() > 14)
	bt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tv.add_child(bt)
	top.add_child(tv)
	a.add_child(top)
	var b := _card_in(g, "Требования (%d из 6)" % mk.iso_ready(), "Аудитор проверяет их в день аудита. Выполните всё заранее.")
	for r: Array in mk.iso_reqs():
		var rh := UITheme.hbox(8)
		var okr := bool(r[1])
		rh.add_child(UITheme.label("✓" if okr else "×", 15, UITheme.GOOD if okr else UITheme.BAD, UITheme.f_semi))
		rh.add_child(UITheme.label(str(r[0]), 13, UITheme.TEXT if okr else UITheme.MUTED))
		b.add_child(rh)


## Управление → Главный инженер: советы по заводу, самые важные — первыми.
func _advisor() -> void:
	var mk := sim.market
	var adv := mk.advice()
	_info("советов: %d" % adv.size())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	content.add_child(cols)
	var lc := UITheme.card(14)
	lc.custom_minimum_size = Vector2(260, 0)
	lc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cols.add_child(lc)
	var lv := UITheme.vbox(6)
	lc.add_child(lv)
	var ph := PanelContainer.new()
	ph.add_theme_stylebox_override("panel", UITheme.sb(Color(0, 0, 0, 0), UITheme.LINE2, 1, 2, 3, 3))
	ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var por := Portrait.new()
	var ce := sim.office.staff("engineer")
	var ew: Worker = ce[0] if not ce.is_empty() else null
	if ew:
		por.set_look(ew.look, 1.7, {"age": ew.age, "mood": ew.mood, "wide": true, "doc": true})
	else:
		por.set_look(Market.engineer_look(), 1.7, {"age": 58, "mood": 60.0, "wide": true, "doc": true})
	ph.add_child(por)
	lv.add_child(ph)
	var nl := UITheme.label(ew.last.to_upper() if ew else "САМОЙЛОВ", 18, UITheme.TEXT, UITheme.f_caps)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(nl)
	var fl := UITheme.label(("%s, главный инженер" % ew.first) if ew else "Пётр, главный инженер", 13, UITheme.MUTED)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(fl)
	var quote: String = ["«Завод — не станки. Завод — это порядок».", "«Сначала узкое место, потом всё остальное».", "«Брак дешевле поймать в цеху, чем у заказчика».", "«Станок любит смазку, а человек — уважение»."][sim.day() % 4]
	var ql := UITheme.para(quote, 13, UITheme.INFO)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(ql)
	var cb := CheckBox.new()
	cb.text = "Записка по понедельникам"
	cb.button_pressed = mk.memo_on
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "Каждый понедельник — напоминание о главном совете"
	cb.toggled.connect(func(on: bool) -> void: mk.memo_on = on)
	lv.add_child(cb)
	var rv := UITheme.vbox(8)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rv)
	# сводка сетей (1.10): мощность, сжатый воздух, вода
	var nc := UITheme.card(10)
	var nv := UITheme.hbox(14)
	nc.add_child(nv)
	var cap := sim.power.capacity_total()
	var pl := sim.power.total_load
	nv.add_child(UITheme.stat("Электросеть", "%.0f / %d кВт" % [pl, int(cap)], UITheme.BAD if pl > cap * 0.9 else (UITheme.WARN if pl > cap * 0.7 else UITheme.GOOD), "запас %d%%" % int(maxf(0.0, 100.0 - pl / maxf(1.0, cap) * 100.0))))
	var comps := sim.things_of("compressor").size()
	var pneu := sim.things.values().filter(func(t: Thing) -> bool: return t.built and str(t.machine_def().get("air", "")) != "").size()
	nv.add_child(UITheme.stat("Сжатый воздух", "%d компр." % comps if comps > 0 else "нет", UITheme.TEXT if comps > 0 or pneu == 0 else UITheme.WARN, "потребителей: %d" % pneu))
	nv.add_child(UITheme.stat("Вода", "есть насос" if sim.water.has_source() else "нет насоса", UITheme.GOOD if sim.water.has_source() else UITheme.WARN, "ППР станков: " + ("ведёт сам" if sim.office.active("engineer") else ("включён" if sim.ppr else "выключен"))))
	for t0 in nv.get_children():
		(t0 as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(nc)
	if adv.is_empty():
		var e := UITheme.card(16)
		e.add_child(UITheme.para("«Претензий нет. Завод работает как часы — так держать». Новые советы появятся, когда что-то пойдёт не так.", 14, UITheme.GOOD))
		rv.add_child(e)
		return
	for i in adv.size():
		var a: Dictionary = adv[i]
		var c := UITheme.card(12, UITheme.BG2, UITheme.ACCENT_D if i == 0 else UITheme.LINE)
		rv.add_child(c)
		var h := UITheme.hbox(10)
		c.add_child(h)
		var num := UITheme.label(str(i + 1), 18, UITheme.ACCENT if i == 0 else UITheme.MUTED, UITheme.f_semi)
		num.custom_minimum_size = Vector2(22, 0)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(num)
		var v := UITheme.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UITheme.label(str(a["title"]), 15, UITheme.TEXT, UITheme.f_semi))
		v.add_child(UITheme.para(str(a["text"]), 13))
		h.add_child(v)
		var op := str(a.get("open", ""))
		var sc := str(a.get("sec", ""))
		if op != "":
			var ob := UITheme.small("Открыть →", func() -> void:
				hud.open_window(op)
				if hud.win and sc != "":
					hud.win.select_tab(sc))
			h.add_child(ob)
		else:
			h.add_child(UITheme.small("Помещения →", func() -> void:
				closed.emit()
				hud.open_rooms()))
