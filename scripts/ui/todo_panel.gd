class_name TodoPanel
extends PanelContainer
## Список дел в левом верхнем углу (как в Prison Architect): письма-решения, тревоги,
## заказы и цели этапа. Сворачивается щелчком по заголовку. Каждая строка — ссылка.

static var collapsed := false

var hud: Hud
var sim: Sim
var _body: VBoxContainer
var _head: Button
var _sig := ""
var _t := 0.0


func setup(h: Hud) -> void:
	hud = h
	sim = h.sim
	add_theme_stylebox_override("panel", UITheme.sbs(Color(0.106, 0.108, 0.112, 0.9), UITheme.LINE, 1, 10, 10, 8, 12, 0.4, 3))
	custom_minimum_size = Vector2(380, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UITheme.vbox(4)
	add_child(v)
	_head = Button.new()
	_head.flat = true
	_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.focus_mode = Control.FOCUS_NONE
	_head.add_theme_font_override("font", UITheme.f_semi)
	_head.add_theme_font_size_override("font_size", 13)
	_head.add_theme_color_override("font_color", UITheme.MUTED)
	_head.add_theme_color_override("font_hover_color", UITheme.TEXT)
	# 1.30: значок «Задачи» из набора владельца
	_head.icon = UITheme.micon("tasks")
	_head.expand_icon = false
	_head.add_theme_constant_override("icon_max_width", 20)
	UITheme.micon_colors(_head)
	var e := UITheme.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 2, 0)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		_head.add_theme_stylebox_override(st, e)
	_head.pressed.connect(func() -> void:
		collapsed = not collapsed
		_sig = ""
		_refresh())
	v.add_child(_head)
	_body = UITheme.vbox(4)
	v.add_child(_body)
	_refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	_refresh()


func _items() -> Array:
	var out: Array = []   # [icon, text, value, color, action:Callable, (необяз.) "cta" — крупная кнопка под строкой]
	# 1.17: неделя стройки — заказов нет; кнопка «Начать производство»
	if sim.progress.quiet():
		var ql := sim.progress.quiet_left()
		out.append(["build", "Неделя стройки: заказов не будет ещё %d %s" % [ql, Defs.plural(ql, "день", "дня", "дней")], "", UITheme.INFO, func() -> void: hud.confirm_start_early(), "cta"])
	# 1.17: нарисован план — напомнить утвердить; утверждённое ждёт стен
	if not sim.plan.pending_empty() and not hud.g.tool.plan_mode:
		out.append(["plan", "План стройки: ≈ %s" % Defs.money_str(sim.plan.cost()), "открыть", UITheme.INFO, func() -> void: hud.toggle_plan()])
	elif not sim.plan.ok_zones.is_empty() or sim.plan.objs.any(func(o: Dictionary) -> bool: return bool(o.get("ok", false))):
		out.append(["plan", "По плану ждут стен: зоны и объекты", "", UITheme.MUTED, func() -> void: hud.toggle_plan()])
	# решения
	for l: Dictionary in sim.story.letters.slice(0, 3):
		var ll := l
		out.append(["letter", str(l["title"]), "решить", UITheme.ACCENT, func() -> void: hud.show_letter(ll)])
	if sim.story.letters.size() > 3:
		out.append(["letter", "Ещё писем: %d" % (sim.story.letters.size() - 3), "", UITheme.ACCENT, func() -> void: hud.open_window("events")])
	# тревоги
	if not sim.story.fires.is_empty():
		var fc: Vector2i = sim.world.cell_of(int(sim.story.fires.keys()[0]))
		out.append(["fire", "Пожар! Люди тушат", "", UITheme.BAD, func() -> void: hud.g.cam.focus_cell(fc)])
	if sim.story.strike.get("active", false):
		out.append(["strike", "Забастовка: %s" % sim.story.demand_text(str(sim.story.strike.get("demand", ""))).to_lower(), "", UITheme.BAD, func() -> void: hud.open_window("events")])
	# 1.20: долг по зарплате — люди уходят, трое за 2 недели — завод закроют
	var arr := sim.progress.arrears_total()
	if arr > 0.0:
		out.append(["strike", "Долг по зарплате — люди уходят (%d из %d)" % [sim.crisis.arrears_quits.size(), Crisis.QUITS_TO_CLOSE], Defs.money_str(arr), UITheme.BAD, func() -> void: hud.open_window("finance")])
	if not sim.crisis.tools_short.is_empty():
		out.append(["wrench", "Нечем работать: нет инструмента и денег", "", UITheme.BAD, func() -> void: hud.open_window("supply")])
	if sim.money < 0.0:
		out.append(["money", "Кассовый разрыв — денег нет", Defs.money_str(sim.money), UITheme.BAD, func() -> void: hud.open_window("finance")])
	if sim.power.any_tripped():
		out.append(["bolt_off", "Выбит автомат — часть завода без тока", "", UITheme.BAD, func() -> void: hud.toggle_sub("power")])
	if sim.inspect.busy():
		out.append(["inspect", "Идёт проверка: %s" % sim.inspect.type_name(str(sim.inspect.visit.get("type", ""))).to_lower(), "", UITheme.WARN, func() -> void:
			hud.open_window("events")
			if hud.win:
				hud.win.select_tab("insp")])
	elif not sim.inspect.queue.is_empty():
		var q: Dictionary = sim.inspect.queue[0]
		if bool(q.get("announced", false)):
			out.append(["inspect", "Скоро проверка: %s" % sim.inspect.type_name(str(q["type"])).to_lower(), sim.season.short_date(int(float(q["at"]) / 1440.0) + 1), UITheme.WARN, func() -> void:
				hud.open_window("events")
				if hud.win:
					hud.win.select_tab("insp")])
	# заказы
	var act := sim.orders.by_status(["active", "ready", "shipping"])
	if not act.is_empty():
		var late := 0
		var nearest := INF
		for o: Dictionary in act:
			if sim.minute > float(o["deadline"]):
				late += 1
			nearest = minf(nearest, float(o["deadline"]))
		var txt := "Заказы в работе: %d" % act.size()
		var val := "срок %s" % sim.season.short_date(int(nearest / 1440.0) + 1).split(",")[0] if nearest < INF else ""
		if late > 0:
			txt += ", просрочено %d" % late
		out.append(["orders", txt, val, UITheme.BAD if late > 0 else UITheme.TEXT, func() -> void: hud.open_window("orders")])
	else:
		out.append(["orders", "Заказов в работе нет", "", UITheme.MUTED, func() -> void: hud.open_window("orders")])
	# следующий отдел (РП-26): что даст следующий рубль
	var nd := next_dept()
	if nd != "":
		var rs := sim.office.room_status(nd)
		var has_staff := not sim.office.staff(nd).is_empty()
		var chk := "нанять человека" if not has_staff else ("нужен кабинет" if int(rs[0]) < 1 else "")
		out.append(["office", "Нужен отдел: %s" % str(Defs.departments[nd]["name"]), chk, UITheme.INFO, func() -> void: hud.open_window("office")])
	# развитие: что исследует директор или что можно открыть
	var dv := sim.dev
	if dv.cur != "":
		out.append(["develop", "Развитие: «%s»" % str(Develop.step_def(dv.cur)["name"]), "%.1f дн." % dv.days_left(), UITheme.ACCENT, func() -> void: hud.open_window("develop")])
	elif sim.progress.stage >= 2 and not dv.root_ok():
		out.append(["develop", "Постройте кабинет директора", "откроет «Развитие»", UITheme.WARN, func() -> void: hud.open_window("develop")])
	else:
		var nr := dv.next_ready()
		if nr != "":
			out.append(["develop", "Можно открыть: «%s»" % str(Develop.step_def(nr)["name"]), "%d тыс." % int(float(Develop.step_def(nr).get("cost", 0.0)) / 1000.0), UITheme.INFO, func() -> void: hud.open_window("develop")])
	# гранты и программы поддержки: условия и срок
	for a: Dictionary in sim.grants.active:
		var gd0 := Grants.def(str(a["id"]))
		var goals0: Array = gd0.get("goals", [])
		var ok0 := 0
		for g0: Dictionary in goals0:
			if sim.grants.goal_ok(g0, a):
				ok0 += 1
		var left := int(a["until"]) - sim.day()
		out.append(["medal", "Грант: %s" % str(gd0.get("title", "")), "%d/%d · %d дн." % [ok0, goals0.size(), maxi(0, left)], UITheme.BAD if left <= 2 and ok0 < goals0.size() else UITheme.TEXT, func() -> void:
			hud.open_window("finance")
			if hud.win:
				hud.win.select_tab("grants")])
		var shown0 := 0
		for g1: Dictionary in goals0:
			if shown0 >= 2 or sim.grants.goal_ok(g1, a):
				continue
			shown0 += 1
			out.append(["", "· " + str(g1.get("text", "")), "", UITheme.MUTED, func() -> void:
				hud.open_window("finance")
				if hud.win:
					hud.win.select_tab("grants")])
	# главный советник: самый важный совет (если есть главный инженер)
	if sim.day() >= 3 and sim.office.active("engineer"):
		var adv: Array = sim.market.advice()
		if not adv.is_empty() and int(adv[0]["prio"]) >= 60:
			out.append(["engineer", str(adv[0]["title"]), "совет", UITheme.INFO, func() -> void:
				hud.open_window("office")
				if hud.win:
					hud.win.select_tab("advisor")])
	# цели этапа
	var pg := sim.progress
	if pg.stage < Progress.STAGE_COUNT:
		var goals := pg.stage_goals()
		var sp := pg.stage_progress()
		out.append(["goals", "Цели этапа: выполнено %d из %d" % [int(sp[0]), int(sp[1])], "", UITheme.TEXT, func() -> void: hud.open_window("goals")])
		var shown := 0
		for gd2: Dictionary in goals:
			var gs: Array = pg.goal_state(gd2)
			if bool(gs[0]) or shown >= 3:
				continue
			shown += 1
			out.append(["", "· " + str(gd2.get("text", "")), str(gs[1]), UITheme.MUTED, func() -> void: hud.open_window("goals")])
		if pg.choice_need() > 0 and pg.choice_done() < pg.choice_need():
			out.append(["", "· на выбор: ещё %d из %d дорог" % [pg.choice_need() - pg.choice_done(), (pg.stage_choice().get("list", []) as Array).size()], "", UITheme.MUTED, func() -> void: hud.open_window("goals")])
	return out


## Какой отдел открыть следующим: первый по порядку, который уже доступен по этапу и ещё не работает.
## 1.30: строки списка дел, у которых есть цветной значок из набора владельца.
const TODO_ICONS := {"build": "construction", "plan": "blueprint", "orders": "orders", "goals": "goals",
	"office": "management", "money": "money"}
const DEPT_ORDER := ["accounting", "hr", "foreman", "supply", "sales", "safety", "pdo", "chief", "tech", "engineer", "legal"]


func next_dept() -> String:
	if sim.progress.stage < 2 and sim.workers.size() < 6:
		return ""
	for d: String in DEPT_ORDER:
		if Defs.departments.has(d) and sim.progress.dept_open(d) and not sim.office.active(d):
			return d
	return ""


func _refresh() -> void:
	var items := _items()
	var sig := str(collapsed) + str(items.map(func(a: Array) -> String: return str(a[1]) + str(a[2])))
	if sig == _sig:
		return
	_sig = sig
	var urgent := 0
	for it: Array in items:
		if (it[3] as Color) == UITheme.BAD or (it[3] as Color) == UITheme.ACCENT:
			urgent += 1
	_head.text = ("▸ " if collapsed else "▾ ") + "ЧТО ДЕЛАТЬ" + ("  · срочно: %d" % urgent if urgent > 0 else "")
	_head.add_theme_color_override("font_color", UITheme.ACCENT if urgent > 0 else UITheme.TEXT)
	UITheme.clear(_body)
	_body.visible = not collapsed
	if collapsed:
		return
	for it2: Array in items:
		_body.add_child(_line(it2))
		if it2.size() > 5 and str(it2[5]) == "cta":
			var cb2: Callable = it2[4]
			var cta := UITheme.primary("▶  Начать производство раньше", func() -> void: cb2.call(), "Сбыт начнёт принимать заявки уже сегодня")
			cta.custom_minimum_size = Vector2(0, 30)
			_body.add_child(cta)


## 1.19: задачи — заметные карточки: цветная полоска слева (красная — срочно, янтарная — решить,
## синяя — совет), значок, текст, значение-пилюля и стрелка «›» — видно, что по строке можно щёлкнуть.
## Подпункты («· …») — мелко, с отступом, под своей задачей.
func _line(it: Array) -> Button:
	var sub := str(it[0]) == ""
	var col: Color = it[3]
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 22 if sub else 34)
	var accent := col
	if col == UITheme.TEXT:
		accent = UITheme.LINE2
	elif col == UITheme.MUTED:
		accent = UITheme.LINE
	var n: StyleBoxFlat
	var hv: StyleBoxFlat
	if sub:
		n = UITheme.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 4, 0)
		hv = UITheme.sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 4, 4, 0)
	else:
		n = UITheme.sb(Color(accent.r, accent.g, accent.b, 0.13 if col != UITheme.MUTED else 0.05), Color(0, 0, 0, 0), 0, 6, 6, 2)
		n.border_width_left = 4
		n.border_color = accent
		hv = n.duplicate()
		hv.bg_color = Color(accent.r, accent.g, accent.b, 0.24)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	var h := UITheme.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 30 if sub else 10
	h.offset_right = -6
	b.add_child(h)
	if not sub:
		var ic := TextureRect.new()
		var mt := UITheme.micon(str(TODO_ICONS.get(str(it[0]), "")))
		ic.texture = mt if mt != null else Tex.ui(str(it[0]))
		ic.custom_minimum_size = Vector2(22, 22) if mt != null else Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# цветной значок не перекрашиваем: срочность видна по цветной планке слева и тексту
		ic.modulate = Color.WHITE if mt != null else col
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var txt := str(it[1])
	if sub and txt.begins_with("· "):
		txt = "○  " + txt.substr(2)
	var l := UITheme.label(txt, 12 if sub else 14, (UITheme.MUTED if sub else (UITheme.TEXT if col == UITheme.ACCENT or col == UITheme.INFO else col)), null if sub else UITheme.f_semi)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	if str(it[2]) != "":
		if sub:
			var vl := UITheme.label(str(it[2]), 11, UITheme.MUTED, UITheme.f_semi)
			vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(vl)
		else:
			var pill := UITheme.chip(str(it[2]), col if col != UITheme.TEXT and col != UITheme.MUTED else UITheme.MUTED)
			pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pill)
	if not sub:
		var ar := UITheme.label("›", 18, UITheme.MUTED, UITheme.f_semi)
		ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ar)
	var cb: Callable = it[4]
	b.pressed.connect(func() -> void:
		Snd.play("ui_click", -8.0)
		cb.call())
	b.tooltip_text = str(it[1]) + "\nЩёлкните — откроется, где это сделать"
	return b
