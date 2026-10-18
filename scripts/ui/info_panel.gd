class_name InfoPanel
extends PanelContainer
## Карточка выбранного: рабочего (портрет, настроение, мысли, черты, смена, ставка),
## объекта (состояние, питание, вкл/выкл) или помещения (назначение, требования).
## Шапка и кнопки действий всегда наверху и не прокручиваются — «Демонтаж», «Уволить» и т.п.
## видны сразу. Прокручивается только тело карточки, если оно не влезает в экран.

signal focus_request(cell: Vector2i)
signal close_request()
signal control_request(w: Worker, on: bool)   ## 1.19: «Взять под управление» / «Отпустить»

const FORM_RED := Color("#c25a48")     ## красная линовка бланков
const INK := Color("#5a56c8")          ## фиолетовые чернила печатей
static var w_tab := "main"             ## открытая вкладка личной карточки

var sim: Sim
var kind := ""
var id := -1
var root := VBoxContainer.new()
var head := VBoxContainer.new()      ## заголовок — не прокручивается
var actions := HBoxContainer.new()   ## кнопки действий — не прокручиваются
var scroll := ScrollContainer.new()
var box := VBoxContainer.new()       ## тело карточки
var dyn: Dictionary = {}
var _t := 0.0
var card_w := 340.0
var near_screen := Vector2(-1, -1)  ## куда щёлкнули на экране: карточка появится рядом (1.12)


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.sbs(UITheme.BG, UITheme.LINE, 1, 9, 12, 10, 14, 0.45, 5))
	root.add_theme_constant_override("separation", 6)
	head.add_theme_constant_override("separation", 2)
	actions.add_theme_constant_override("separation", 6)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	root.add_child(head)
	root.add_child(actions)
	root.add_child(scroll)
	add_child(root)
	visible = false


func _begin(k: String, new_id: int, w: float) -> void:
	kind = k
	id = new_id
	card_w = w
	UITheme.clear(head)
	UITheme.clear(actions)
	UITheme.clear(box)
	dyn.clear()
	actions.visible = true
	root.move_child(actions, 1)


func _fit() -> void:
	# высота по содержимому, но не выше экрана (между верхней и нижней панелью)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var hh := head.get_combined_minimum_size().y + (actions.get_combined_minimum_size().y + 6.0 if actions.visible else 0.0) + 6.0
	var h := box.get_combined_minimum_size().y
	if kind == "worker":
		h = maxf(h, 236.0)   # вкладки одной высоты — карточка не прыгает
	var max_h := get_viewport_rect().size.y - 64.0 - 90.0 - 24.0 - hh
	scroll.custom_minimum_size = Vector2(card_w, clampf(h, 0.0, maxf(max_h, 120.0)))
	scroll.visible = h > 1.0
	_pin_right()


## Карточка объекта, стены, пола или зоны — рядом с тем местом, куда щёлкнули (1.12); карточка человека
## и выбранное из окон — прижаты к правому краю под верхней панелью.
func _pin_right() -> void:
	var ms := get_combined_minimum_size()
	if near_screen.x >= 0.0 and kind != "worker" and kind != "visitor":
		var vp := get_viewport_rect().size
		var x := near_screen.x + 22.0
		if x + ms.x > vp.x - 58.0:
			x = near_screen.x - 22.0 - ms.x
		var y := clampf(near_screen.y - 28.0, 60.0, maxf(60.0, vp.y - 100.0 - ms.y))
		x = clampf(x, 8.0, maxf(8.0, vp.x - 58.0 - ms.x))
		anchor_left = 0.0
		anchor_right = 0.0
		anchor_top = 0.0
		anchor_bottom = 0.0
		offset_left = x
		offset_right = x + ms.x
		offset_top = y
		offset_bottom = y + ms.y
		return
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -58.0   # левее панели слоёв (1.12)
	offset_left = -58.0 - ms.x
	offset_top = 64.0
	offset_bottom = 64.0 + ms.y


func _wrap(text: String, size_px: int, col: Color, w: float = -1.0) -> Label:
	var l := UITheme.label(text, size_px, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(card_w - 4.0 if w < 0.0 else w, 0)
	return l


## Компактная кнопка действия: мелкий шрифт, небольшие поля.
func _act(text: String, cb: Callable, tip: String = "", icon: String = "", col: Color = UITheme.TEXT) -> Button:
	var b := UITheme.button(text, cb, tip)
	b.add_theme_font_size_override("font_size", 13)
	var edge := Color("#465059") if col == UITheme.TEXT else Color(col.r, col.g, col.b, 0.55)
	var edge_h := Color("#66717c") if col == UITheme.TEXT else col
	b.add_theme_stylebox_override("normal", UITheme.sbs(UITheme.BG3, edge, 1, 6, 9, 3, 2, 0.35, 1))
	b.add_theme_stylebox_override("hover", UITheme.sbs(Color("#3b434c"), edge_h, 1, 6, 9, 3, 3, 0.4, 2))
	b.add_theme_stylebox_override("pressed", UITheme.sb(UITheme.ACCENT, UITheme.ACCENT, 1, 6, 9, 3))
	b.add_theme_color_override("font_pressed_color", UITheme.ACCENT_T)
	b.add_theme_stylebox_override("disabled", UITheme.sb(UITheme.BG2, Color("#30353b"), 1, 6, 9, 3))
	if icon != "":
		b.icon = Tex.ui(icon)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 16)
		b.add_theme_constant_override("h_separation", 5)
	if col != UITheme.TEXT:
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("icon_normal_color", col)
	return b


## Цветная плашка состояния в заголовке («Работает», «Сломан»…).
func _chip(text: String, col: Color) -> Label:
	var l := UITheme.label(text, 12, col, UITheme.f_med)
	var bg := Color(col.r, col.g, col.b, 0.14)
	l.add_theme_stylebox_override("normal", UITheme.sb(bg, Color(col.r, col.g, col.b, 0.5), 1, 9, 8, 1))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Строка «подпись — полоса — число».
func _bar_row(caption: String, col: Color, key: String) -> void:
	var row := UITheme.hbox(8)
	var l := UITheme.label(caption, 13, UITheme.MUTED)
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	var b := UITheme.bar(0, col, 190, 9)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	var v := UITheme.label("", 12, UITheme.MUTED)
	row.add_child(v)
	box.add_child(row)
	dyn[key] = b
	dyn[key + "_l"] = v


# ---------------------------------------------------------------- рабочий

## Личная карточка работника: шапка как на бланке отдела кадров — фото для пропуска, фамилия,
## табельный номер, печать; ниже вкладки «Обзор», «Навыки», «Отношения», «История».
func show_worker(s: Sim, w: Worker) -> void:
	sim = s
	_begin("worker", w.id, 470.0)
	root.move_child(actions, 2)
	# бланк
	var form := UITheme.hbox(8)
	form.add_child(UITheme.label("ЛИЧНАЯ КАРТОЧКА РАБОТНИКА", 11, FORM_RED, UITheme.f_caps))
	form.add_child(UITheme.spacer())
	form.add_child(UITheme.label("ТАБ. № %s" % tab_no(w), 11, UITheme.MUTED, UITheme.f_caps))
	var cx := UITheme.ghost("×", func() -> void: close_request.emit(), "Закрыть (Esc)", UITheme.MUTED)
	cx.add_theme_font_size_override("font_size", 14)
	form.add_child(cx)
	head.add_child(form)
	head.add_child(form_rule())
	var top := UITheme.hbox(14)
	# фото с печатью
	var por := Portrait.new()
	por.set_look(w.look, 1.25, {"age": w.age, "mood": w.mood, "wide": true, "doc": true})
	var ph := Control.new()
	ph.custom_minimum_size = por.custom_minimum_size + Vector2(10, 6)
	ph.add_child(por)
	var st := Stamp.round_stamp("ОТДЕЛ КАДРОВ • ПРИНЯТ • ", PackedStringArray(["день", str(w.hired_day)]), INK, 54.0, -14.0)
	st.position = por.custom_minimum_size - Vector2(38, 42)
	ph.add_child(st)
	ph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(ph)
	var col := UITheme.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sur := UITheme.label(w.last.to_upper(), 20, UITheme.TEXT, UITheme.f_semi)
	col.add_child(sur)
	var nm := UITheme.label(w.first + ("  «%s»" % w.nick if w.nick != "" else ""), 15, UITheme.TEXT)
	if w.nick_why != "":
		nm.tooltip_text = "Почему «%s»: %s" % [w.nick, w.nick_why]
		nm.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(nm)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 5)
	chips.add_theme_constant_override("v_separation", 4)
	chips.add_child(UITheme.chip(w.prof_name() + (" · " + w.rank_text() if w.rank_text() != "" else ""), UITheme.ACCENT, _rank_tip(w), true))
	chips.add_child(UITheme.chip(str(Worker.SHIFT_NAMES[w.shift]).split(" ")[0] + " смена", UITheme.INFO if w.shift == 0 else Color("#a58ad8")))
	if w.brigade >= 0 and not sim.crew.brigade(w.brigade).is_empty():
		var lead := sim.crew.lead_of(w.brigade) == w
		chips.add_child(UITheme.chip(("★ бригадир · " if lead else "") + str(sim.crew.brigade(w.brigade)["name"]), sim.crew.color(w.brigade).lightened(0.25)))
	if w.is_itr():
		chips.add_child(UITheme.chip(str(Defs.departments.get(w.dept(), {}).get("name", "ИТР")), UITheme.INFO))
	if w.practice_until >= 0:
		chips.add_child(UITheme.chip("практикант", UITheme.GOOD, "Практика до дня %d" % w.practice_until))
	if sim.crew.union_on() and int(sim.crew.union.get("lead", -1)) == w.id:
		chips.add_child(UITheme.chip("председатель профкома", UITheme.BAD))
	if sim.town.is_resident(w):
		chips.add_child(UITheme.chip("живёт в общежитии", UITheme.INFO, ("Не опаздывает. Иногородняя" if w.female else "Не опаздывает. Иногородний") if w.from_away else "Не опаздывает"))
	elif w.from_away:
		chips.add_child(UITheme.chip("негде жить", UITheme.BAD, ("Иногородняя без койки в общежитии — снимает угол, недовольна" if w.female else "Иногородний без койки в общежитии — снимает угол, недоволен")))
	var places := Workplace.places_of(sim, w)
	if not places.is_empty():
		var pn: Array[String] = []
		for pl in places:
			pn.append(pl.title())
		chips.add_child(UITheme.chip("рабочее место: " + ", ".join(pn), Color("#b8c48a"), "Закреплено за человеком: работает здесь первым. Если не может — на больничном, занят другим делом, не на смене — встаёт любой, кто умеет. Сменить — в карточке станка."))
	if w.kids > 0:
		chips.add_child(UITheme.chip("дети: %d%s" % [w.kids, " · в садике" if sim.town.has_kg_place(w) else ""], UITheme.GOOD if sim.town.has_kg_place(w) else UITheme.MUTED))
	col.add_child(chips)
	col.add_child(UITheme.label("%d %s · %s · на заводе с дня %d" % [w.age, Defs.plural(w.age, "год", "года", "лет"), People.body_name(w).to_lower(), w.hired_day], 12, UITheme.MUTED))
	var act := UITheme.label("", 13, UITheme.INFO)
	act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	act.custom_minimum_size = Vector2(300, 0)
	col.add_child(act)
	dyn["act"] = act
	if not w.is_itr() and not w.visitor:
		# 1.19: управление — заметная кнопка, а не подсказка мелким шрифтом
		var cb: Button
		if w.controlled:
			cb = UITheme.button("Отпустить — пусть работает сам", func() -> void: control_request.emit(w, false), "Вернуть к обычной работе (Esc)")
		else:
			cb = UITheme.primary("Взять под управление", func() -> void: control_request.emit(w, true),
				"Человек бросит своё и будет ждать ваших команд: щёлкните по стройке, станку, грузу или месту — и выберите «Сделать сейчас»")
		cb.icon = Tex.ui("control")
		cb.add_theme_constant_override("icon_max_width", 20)
		cb.custom_minimum_size = Vector2(0, 34)
		col.add_child(cb)
		dyn["order_hint"] = cb
	var mrow := UITheme.hbox(8)
	mrow.add_child(UITheme.label("Настроение", 12, UITheme.MUTED))
	var mb := UITheme.bar(50, UITheme.GOOD, 170, 8)
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(mb)
	var mlab := UITheme.label("", 12, UITheme.TEXT, UITheme.f_semi)
	mrow.add_child(mlab)
	col.add_child(mrow)
	dyn["mood_bar"] = mb
	dyn["mood_lab"] = mlab
	if not w.traits.is_empty():
		var tr := HFlowContainer.new()
		tr.add_theme_constant_override("h_separation", 4)
		tr.add_theme_constant_override("v_separation", 3)
		for t in w.traits:
			var d: Dictionary = Defs.traits.get(t, {})
			var good := float(d.get("mood", 0.0)) >= 0.0 if d.has("mood") else true
			tr.add_child(UITheme.chip(str(d.get("name", t)), UITheme.TEXT if good else UITheme.WARN, str(d.get("desc", ""))))
		col.add_child(tr)
	top.add_child(col)
	head.add_child(top)
	# вкладки
	var tabs := UITheme.segmented([["main", "Обзор"], ["skills", "Навыки"], ["rel", "Отношения"], ["hist", "История"]], w_tab, func(k: String) -> void:
		w_tab = k
		_worker_tab()
		refresh()
		_fit())
	head.add_child(tabs)
	# действия — внизу карточки
	var on_down := func() -> void:
		sim.change_wage(w, -0.1)
		refresh()
	var on_upw := func() -> void:
		sim.change_wage(w, 0.1)
		refresh()
	var on_bonus := func() -> void:
		var err := sim.give_bonus(w)
		if err != "":
			sim.notify(err, Sim.LVL_WARN)
		refresh()
	actions.add_child(_act("−10%", on_down, "Урезать ставку: сэкономите, но человек обидится"))
	actions.add_child(_act("+10%", on_upw, "Поднять ставку: настроение вверх"))
	actions.add_child(_act("Премия %s" % Defs.money_str(Defs.b("bonus_amount")), on_bonus, "Разовая премия: хорошее настроение на три дня", "money"))
	if not w.is_itr():
		actions.add_child(_act("Учить…", _open_training, "Курсы, наставник, инструктаж (Люди → Обучение)", "research"))
	actions.add_child(UITheme.spacer())
	if not w.order.is_empty():
		actions.add_child(_act("Отменить приказ", func() -> void:
			sim.brain.abort(w)
			sim.brain.end_order(w, "приказ отменён")
			show_worker(sim, w), "Вернуть к обычной работе сейчас", "cancel"))
	if w.has_grade():
		# 1.15 (РП-10): разряд — только через экзамен с пробной деталью
		var why := sim.career.exam_block(w)
		var ex := _act("Экзамен на %d-й разряд" % mini(6, w.grade() + 1), func() -> void:
			var err := sim.career.request_exam(w)
			if err != "":
				sim.notify(err, Sim.LVL_WARN)
			show_worker(sim, w), ("На смене сделает пробную деталь, мастер примет. Сдал — разряд и просьба о прибавке; не сдал — пересдача через неделю." if why == "" else why), "medal")
		ex.disabled = why != ""
		actions.add_child(ex)
	actions.add_child(_act("Показать", func() -> void: focus_request.emit(w.cell()), "Перевести камеру на человека", "inspect"))
	actions.add_child(_act("Уволить", func() -> void: _confirm_fire(w), "Уволить с выплатой расчёта", "", UITheme.BAD))
	_worker_tab()
	visible = true
	refresh()
	_fit()


## Подсказка к званию: разряд, категория или должность (1.15).
static func _rank_tip(w: Worker) -> String:
	match w.rank_kind():
		"grade":
			if w.pot_grade() > w.grade():
				return "Разряд подтверждён экзаменом. Руки уже тянут на %d-й — скоро сдаст пробную деталь мастеру." % w.pot_grade()
			return "Разряд подтверждают экзаменом: пробная деталь мастеру, когда навык подрастёт."
		"category":
			if w.prof == "nurse":
				return "Медицинская категория растёт с опытом: вторая — с навыком 4, первая — с 6, высшая — с 8."
			return "Категория растёт с опытом: II — с навыком 4, I — с 6, ведущий — с 8."
		"position":
			return "Руководитель: у должности нет разрядов."
	return "Простая работа — без разрядов."


## Шапка-бланк карточки: красная надпись капсом, номер справа, крестик, двойная линовка.
func _form_head(title: String, no: String) -> VBoxContainer:
	var v := UITheme.vbox(3)
	var form := UITheme.hbox(8)
	form.add_child(UITheme.label(title.to_upper(), 11, FORM_RED, UITheme.f_caps))
	form.add_child(UITheme.spacer())
	form.add_child(UITheme.label(no.to_upper(), 11, UITheme.MUTED, UITheme.f_caps))
	var cx := UITheme.ghost("×", func() -> void: close_request.emit(), "Закрыть (Esc)", UITheme.MUTED)
	cx.add_theme_font_size_override("font_size", 14)
	form.add_child(cx)
	v.add_child(form)
	v.add_child(form_rule())
	return v


## Табельный номер: четыре цифры, постоянный для человека.
static func tab_no(w: Worker) -> String:
	return "%04d" % (100 + (w.id * 37) % 9800)


## Двойная красная линовка, как на бланках.
static func form_rule() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var a := ColorRect.new()
	a.color = Color(FORM_RED, 0.75)
	a.custom_minimum_size = Vector2(0, 2)
	var b := ColorRect.new()
	b.color = Color(FORM_RED, 0.4)
	b.custom_minimum_size = Vector2(0, 1)
	v.add_child(a)
	v.add_child(b)
	return v


## Содержимое выбранной вкладки личной карточки.
func _worker_tab() -> void:
	var w := sim.get_worker(id)
	if w == null:
		return
	UITheme.clear(box)
	for k in dyn.keys():
		if str(k).begins_with("t_"):
			dyn.erase(k)
	match w_tab:
		"skills":
			_wt_skills(w)
		"rel":
			_wt_rel(w)
		"hist":
			_wt_hist(w)
		_:
			_wt_main(w)


func _wt_main(w: Worker) -> void:
	var cols := UITheme.hbox(18)
	var left := UITheme.vbox(4)
	left.custom_minimum_size = Vector2(236, 0)
	left.add_child(UITheme.caption("Потребности"))
	for pair in [["food", "Сытость"], ["bladder", "Туалет"], ["rest", "Бодрость"]]:
		var row := UITheme.hbox(6)
		var l := UITheme.label(pair[1], 12)
		l.custom_minimum_size = Vector2(70, 0)
		row.add_child(l)
		var b := UITheme.bar(100, UITheme.GOOD, 120, 7)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		var vl := UITheme.label("", 12, UITheme.MUTED)
		row.add_child(vl)
		left.add_child(row)
		dyn["t_need_" + pair[0]] = b
		dyn["t_needl_" + pair[0]] = vl
	left.add_child(UITheme.caption("Работа"))
	var g := UITheme.grid(2, 6, 6)
	for k in ["days", "ops", "speed", "ppe"]:
		var tile := UITheme.card(8)
		var tv := UITheme.vbox(0)
		tile.add_child(tv)
		var cap := UITheme.label({"days": "смен", "ops": "операций", "speed": "скорость", "ppe": "СИЗ" if not w.is_itr() else "рабочее место"}[k], 11, UITheme.MUTED)
		tv.add_child(cap)
		var val := UITheme.label("", 16, UITheme.TEXT, UITheme.f_semi)
		tv.add_child(val)
		dyn["t_st_" + k] = val
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(tile)
	left.add_child(g)
	cols.add_child(left)
	var right := UITheme.vbox(2)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not w.visitor:
		# 1.15 (РП-8): пять жизненных потребностей
		right.add_child(UITheme.caption("Что важно"))
		var lg := UITheme.grid(3, 6, 2)
		for lfg in Mood.LIFE:
			var gl := UITheme.label(str(lfg[1]), 12)
			gl.custom_minimum_size = Vector2(74, 0)
			gl.mouse_filter = Control.MOUSE_FILTER_STOP
			lg.add_child(gl)
			var gb := UITheme.bar(50, UITheme.GOOD, 110, 7)
			gb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			gb.mouse_filter = Control.MOUSE_FILTER_STOP
			lg.add_child(gb)
			var gv := UITheme.label("", 11, UITheme.MUTED)
			lg.add_child(gv)
			dyn["t_life_l_" + str(lfg[0])] = gl
			dyn["t_life_b_" + str(lfg[0])] = gb
			dyn["t_life_v_" + str(lfg[0])] = gv
		right.add_child(lg)
		var hint := _wrap("", 12, UITheme.WARN, 300.0)
		right.add_child(hint)
		dyn["t_life_hint"] = hint
	right.add_child(UITheme.caption("О чём думает"))
	var thoughts := UITheme.vbox(1)
	right.add_child(thoughts)
	dyn["t_thoughts"] = thoughts
	dyn["t_thoughts_sig"] = ""
	cols.add_child(right)
	box.add_child(cols)
	var stats := _wrap("", 12, UITheme.MUTED)
	box.add_child(stats)
	dyn["t_stats"] = stats
	# ставка и смена
	var wc := UITheme.card(10)
	var wr := UITheme.hbox(10)
	wc.add_child(wr)
	var wl := UITheme.vbox(0)
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wage_v := UITheme.label("", 16, UITheme.TEXT, UITheme.f_semi)
	var wage_s := UITheme.label("", 12, UITheme.MUTED)
	wl.add_child(wage_v)
	wl.add_child(wage_s)
	wr.add_child(wl)
	dyn["t_wage"] = wage_v
	dyn["t_wage_s"] = wage_s
	wr.add_child(UITheme.label("Смена", 12, UITheme.MUTED))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", 13)
	for n in Worker.SHIFT_NAMES:
		ob.add_item(n)
	ob.select(w.pending_shift if w.pending_shift >= 0 else w.shift)
	ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wid := w.id
	ob.item_selected.connect(func(i: int) -> void:
		var ww := sim.get_worker(wid)
		if ww:
			sim.set_shift(ww, i)
		refresh())
	wr.add_child(ob)
	box.add_child(wc)


func _wt_skills(w: Worker) -> void:
	var keys: Array[String] = []
	for sk in Worker.SKILL_NAMES.keys():
		if w.skill(str(sk)) > 0 or str(sk) == w.main_skill():
			keys.append(str(sk))
	keys.sort_custom(func(a: String, b: String) -> bool: return w.skill(a) > w.skill(b) if a != w.main_skill() and b != w.main_skill() else a == w.main_skill())
	var g := UITheme.grid(2, 18, 6)
	for k in keys:
		var row := UITheme.hbox(8)
		var main := k == w.main_skill()
		var nl := UITheme.label(str(Worker.SKILL_NAMES[k]), 13, UITheme.ACCENT if main else UITheme.TEXT, UITheme.f_semi if main else null)
		nl.custom_minimum_size = Vector2(128, 0)
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.tooltip_text = "Основной навык профессии" if main else str(Worker.SKILL_NAMES[k])
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(nl)
		row.add_child(_pips(w.skill(k), UITheme.ACCENT if main else UITheme.INFO))
		row.add_child(UITheme.label(str(w.skill(k)), 12, UITheme.MUTED))
		g.add_child(row)
	box.add_child(g)
	box.add_child(UITheme.caption("Обучение"))
	var tr := sim.training
	var c := tr.course_of(w)
	if not c.is_empty():
		box.add_child(UITheme.meter(tr.progress(w) * 100.0, UITheme.INFO, 160, "на курсах: %s %d → %d" % [str(Worker.SKILL_NAMES.get(str(c["skill"]), "")).to_lower(), int(c["from"]), int(c["to"])]))
	var m := tr.mentor_of(w)
	var lines: Array[String] = []
	if m:
		lines.append("Наставник: %s%s" % [m.full_name(), "" if m.shift == w.shift else " (другая смена — не учит!)"])
	var ap: Array[String] = []
	for a in tr.apprentices(w):
		ap.append(a.full_name())
	if not ap.is_empty():
		lines.append("Ученики: " + ", ".join(ap))
	if c.is_empty() and lines.is_empty():
		lines.append("Не учится. Курсы дают +2 к навыку, наставник утраивает рост у станка.")
	for l in lines:
		box.add_child(_wrap(l, 12, UITheme.TEXT))
	if not w.is_itr():
		var b := _act("Курсы и наставник…", _open_training, "Люди → Обучение", "research")
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(b)


## Десять делений навыка.
static func _pips(n: int, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 10:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(8, 8)
		r.color = col if i < n else Color(1, 1, 1, 0.08)
		h.add_child(r)
	return h


func _wt_rel(w: Worker) -> void:
	var tr := sim.training
	if w.brigade >= 0:
		var b := sim.crew.brigade(w.brigade)
		if not b.is_empty():
			var ld := sim.crew.lead_of(w.brigade)
			var h := UITheme.hbox(8)
			var sw := ColorRect.new()
			sw.color = sim.crew.color(w.brigade)
			sw.custom_minimum_size = Vector2(5, 18)
			h.add_child(sw)
			h.add_child(UITheme.label("«%s» — %d чел.%s" % [str(b["name"]), sim.crew.members(w.brigade).size(), (" · бригадир: " + ld.full_name()) if ld and ld != w else (" · бригадир (+10% к ставке)" if ld == w else "")], 13, UITheme.TEXT))
			box.add_child(h)
	else:
		box.add_child(UITheme.label("Не в бригаде", 13, UITheme.MUTED))
	var others: Array = []
	for o in sim.workers:
		if o != w and absf(tr.rel(w, o)) >= 8.0:
			others.append(o)
	others.sort_custom(func(a: Worker, b2: Worker) -> bool: return absf(tr.rel(w, a)) > absf(tr.rel(w, b2)))
	box.add_child(UITheme.caption("Отношения в коллективе"))
	if others.is_empty():
		box.add_child(_wrap("Пока ни с кем не сблизился и не поссорился. Отношения складываются, когда люди работают в одном помещении.", 12, UITheme.MUTED))
		return
	var g := UITheme.grid(2, 12, 6)
	for o: Worker in others.slice(0, 10):
		var v := tr.rel(w, o)
		var h2 := UITheme.hbox(7)
		var por := Portrait.new()
		por.set_look(o.look, 0.6, {"age": o.age, "mood": o.mood})
		h2.add_child(por)
		var vv := UITheme.vbox(1)
		vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := UITheme.label(o.full_name(), 13, UITheme.TEXT, UITheme.f_semi)
		nl.clip_text = true
		nl.custom_minimum_size = Vector2(120, 0)
		vv.add_child(nl)
		var word := "друг" if v >= 25.0 else ("приятель" if v > 0.0 else ("не ладят" if v <= -25.0 else "недолюбливает"))
		var cc := UITheme.GOOD if v > 0.0 else UITheme.BAD
		vv.add_child(UITheme.meter(absf(v), cc, 60, "%s %+d" % [word, int(round(v))]))
		h2.add_child(vv)
		g.add_child(h2)
	box.add_child(g)


func _wt_hist(w: Worker) -> void:
	var facts: Array[String] = []
	facts.append("На заводе с дня %d · отработал смен: %d · операций: %d" % [w.hired_day, w.days_worked, w.parts_made])
	if w.nick != "":
		facts.append("Прозвище «%s»%s" % [w.nick, (": " + w.nick_why) if w.nick_why != "" else ""])
	for f in facts:
		box.add_child(_wrap(f, 12, UITheme.INFO))
	if not w.tally.is_empty():
		var names := {"fire": "тушил пожары", "injury": "травмы", "breaker": "поднимал автоматы", "smoke": "перекуры", "repair": "ремонты", "theft": "попадался на выносе"}
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 4)
		for k in w.tally.keys():
			fl.add_child(UITheme.chip("%s: %d" % [str(names.get(k, k)), int(w.tally[k])], UITheme.MUTED))
		box.add_child(fl)
	box.add_child(UITheme.caption("Записи в карточке"))
	if w.history.is_empty():
		box.add_child(_wrap("Записей пока нет.", 12, UITheme.MUTED))
	for line in w.history.slice(0, 14):
		var t := str(line)
		var h := UITheme.hbox(8)
		var i := t.find(":")
		var dl := UITheme.label(t.substr(0, i) if i > 0 else "", 12, UITheme.DIM)
		dl.custom_minimum_size = Vector2(62, 0)
		dl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(dl)
		h.add_child(_wrap(t.substr(i + 1).strip_edges() if i > 0 else t, 12, UITheme.TEXT, card_w - 80.0))
		box.add_child(h)


## Гость завода: инспектор, губернатор, журналист.
func show_visitor(s: Sim, v: Worker) -> void:
	sim = s
	_begin("visitor", v.id, 340.0)
	actions.visible = false
	var top := UITheme.hbox(12)
	var por := Portrait.new()
	por.set_look(v.look, 1.2, {"age": v.age, "mood": 50.0})
	top.add_child(por)
	var col := UITheme.vbox(2)
	col.add_child(UITheme.title(v.formal_name(), 16))
	var t := str(sim.inspect.visit.get("type", ""))
	col.add_child(UITheme.label(str(sim.inspect.tdef(t).get("who", "Гость завода")), 13, UITheme.MUTED))
	var act := UITheme.label("", 13, UITheme.INFO)
	act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	act.custom_minimum_size = Vector2(200, 0)
	col.add_child(act)
	dyn["act"] = act
	top.add_child(col)
	head.add_child(top)
	var found := _wrap("", 13, UITheme.WARN)
	box.add_child(found)
	dyn["found"] = found
	if not Inspections.VISIT_KINDS.has(t):
		box.add_child(UITheme.label("Что проверяет:", 13, UITheme.MUTED, UITheme.f_med))
		for line in sim.inspect.checklist(t):
			box.add_child(_wrap("• " + str(line), 12, UITheme.TEXT))
		box.add_child(_wrap("Нарушения записываются, когда инспектор заходит в помещение. Успеете исправить до его прихода — не запишет.", 12, UITheme.MUTED))
	else:
		box.add_child(_wrap("Оценивает порядок: грузы на полу, сломанные станки, оборудованные помещения, настроение людей, снег на дорожках, нарушения.", 12, UITheme.MUTED))
	visible = true
	refresh()
	_fit()


## Выбор хозяина рабочего места: список тех, кто умеет здесь работать.
func _pick_owner(t: Thing, anchor: Control) -> void:
	var pm := PopupMenu.new()
	add_child(pm)
	var list := Workplace.candidates(sim, t)
	pm.add_item("Не закреплять", 0)
	var ids: Array[int] = [-1]
	for w in list:
		var places := Workplace.places_of(sim, w).filter(func(x: Thing) -> bool: return x.id != t.id)
		var extra: String = (" · уже: " + (places[0] as Thing).title()) if not places.is_empty() else ""
		pm.add_item("%s%s — %s%s" % ["✓ " if w.id == t.owner else "", w.full_name(), w.title_lc(), extra], ids.size())
		ids.append(w.id)
	pm.id_pressed.connect(func(ix: int) -> void:
		Workplace.assign(sim, t, sim.get_worker(ids[ix]) if ids[ix] >= 0 else null)
		show_thing(sim, t))
	pm.popup_hide.connect(pm.queue_free)
	pm.position = Vector2i(anchor.get_screen_position() + Vector2(0, anchor.size.y))
	pm.popup()


func _confirm_fire(w: Worker) -> void:
	var hud := get_parent() as Hud
	if hud:
		hud.show_fire_dialog(w, func() -> void: visible = false)


# ---------------------------------------------------------------- объект

func show_thing(s: Sim, t: Thing) -> void:
	sim = s
	_begin("thing", t.id, 360.0)
	head.add_child(_form_head("Паспорт станка" if t.kind() == "machine" else "Объект", "инв. № %05d" % ((t.id * 7919) % 99000 + 1000)))
	var top := UITheme.hbox(10)
	var oic := TextureRect.new()
	oic.texture = Tex.obj(t.def_id if t.def_id != "chair" else "chair_down")
	oic.custom_minimum_size = Vector2(40, 40)
	oic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	oic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(oic)
	var tl := UITheme.title(t.title(), 16)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(200, 0)
	top.add_child(tl)
	var chip := _chip("", UITheme.MUTED)
	top.add_child(chip)
	dyn["chip"] = chip
	head.add_child(top)
	var desc := str(t.def().get("desc", ""))
	if desc != "":
		var dl := _wrap(desc, 12, UITheme.MUTED)
		dl.max_lines_visible = 2
		dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		dl.tooltip_text = desc
		dl.mouse_filter = Control.MOUSE_FILTER_STOP
		head.add_child(dl)
	if t.kind() == "machine":
		head.add_child(_wrap(Defs.machine_spec(t.def_id), 12, UITheme.INFO))   # 1.16: размер деталей, скорость, брак
	# 1.13: зона обязательна — вне своей зоны объектом не пользуются
	if t.built and not sim.rooms.zone_ok(t):
		var zw := UITheme.hbox(6)
		var zl := _wrap("Не работает: стоит вне зоны %s. Разметьте зону там, где он стоит." % Rooms.zone_names(t.def_id), 12, UITheme.WARN, card_w - 110.0)
		zl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zw.add_child(zl)
		var ztype := str(Rooms.zone_req(t.def_id)[0])
		zw.add_child(_act("Разметить", func() -> void:
			var hd: Node = get_parent()
			while hd and not (hd is Hud):
				hd = hd.get_parent()
			if hd:
				(hd as Hud).open_rooms_type(ztype), "Откроется меню «Зоны» с нужной зоной", "", UITheme.WARN))
		head.add_child(zw)
	# 1.15: рабочее место закреплено за человеком
	if t.built and Workplace.is_place(t):
		var orow := UITheme.hbox(6)
		var ow := Workplace.owner_of(sim, t)
		var otxt := "Закреплён за: " + (ow.full_name() + " (" + ow.title_lc() + ")" if ow else "никем — работает любой, кто умеет")
		var ol := _wrap(otxt, 12, UITheme.TEXT if ow else UITheme.MUTED, card_w - 120.0)
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ol.tooltip_text = "Хозяин работает на своём месте первым. Если он не может — на больничном, в отпуске, занят другим делом или не на смене — встаёт любой, кто умеет. Освободился — сменщик доделает деталь и уступит."
		ol.mouse_filter = Control.MOUSE_FILTER_STOP
		orow.add_child(ol)
		var ob := _act("Сменить…", func() -> void: pass, "Закрепить место за другим человеком", "staff")
		ob.pressed.connect(func() -> void: _pick_owner(t, ob))
		orow.add_child(ob)
		head.add_child(orow)
	# действия
	if (t.kind() == "machine" or t.kind() in ["vent_fan", "compressor", "boiler"]) and t.built:
		var tg := _act("", func() -> void: pass)
		var upd := func() -> void:
			tg.text = "Выключить" if t.enabled else "Включить"
			tg.icon = Tex.ui("power_off" if t.enabled else "power")
		var on_toggle := func() -> void:
			t.enabled = not t.enabled
			sim.thing_rev += 1
			upd.call()
			refresh()
		tg.pressed.connect(on_toggle)
		tg.expand_icon = false
		tg.add_theme_constant_override("icon_max_width", 16)
		upd.call()
		tg.tooltip_text = "Выключенный станок не работает и не берёт нагрузку сети. Металл с него вернут на склад." if t.kind() == "machine" else "Выключенный агрегат не работает и не берёт нагрузку сети."
		actions.add_child(tg)
	if Thing.rotations(t.def_id) > 1:
		var on_rot := func() -> void:
			var err := sim.rotate_thing(t)
			if err != "":
				sim.notify(err, Sim.LVL_WARN)
			else:
				Snd.play("place", -8.0)
		actions.add_child(_act("Повернуть", on_rot, "Повернуть объект на месте на 90° (клавиша R при установке)"))
	if str(t.def().get("power_source", "")) != "" and t.built:
		actions.add_child(_act("Сеть…", _open_power, "Меню «Сети»: кабель, подстанция, мощность", "power"))
	if t.kind() == "ppe_cabinet" and t.built:
		actions.add_child(_act("Охрана труда…", _open_safety, "СОУТ, СИЗ и молоко за вредность"))
	actions.add_child(UITheme.spacer())
	if not t.built:
		var on_cancel := func() -> void:
			sim.cancel_thing(t)
			visible = false
		actions.add_child(_act("Отменить заказ", on_cancel, "Отменить установку; деньги за ещё не привезённое вернут", "cancel", UITheme.BAD))
	elif t.demolish:
		var on_keep := func() -> void:
			sim.cancel_thing(t)
			show_thing(sim, t)
		actions.add_child(_act("Не сносить", on_keep, "Снять пометку о демонтаже", "cancel"))
	else:
		var on_dem := func() -> void:
			t.demolish = true
			sim.thing_rev += 1
			show_thing(sim, t)
		actions.add_child(_act("Демонтаж", on_dem, "Рабочие разберут объект и унесут в ящиках на склад оборудования (помещение «Склад» или зона разгрузки). Поставить снова — бесплатно, продать — за полцены (Производство → Склад оборудования).", "demolish", UITheme.BAD))
	# тело
	if t.kind() == "machine" and t.built:
		_bar_row("Состояние", UITheme.GOOD, "cond")
		_bar_row("Операция", UITheme.INFO, "prog")
	var st := _wrap("", 13, UITheme.TEXT)
	box.add_child(st)
	dyn["state"] = st
	visible = true
	refresh()
	_fit()


func _open_training() -> void:
	var hud := get_parent() as Hud
	if hud:
		hud.open_window("staff")
		if hud.win:
			hud.win.select_tab("train")


func _open_safety() -> void:
	var hud := get_parent() as Hud
	if hud:
		hud.open_window("staff")
		if hud.win:
			hud.win.select_tab("safety")


func _open_power() -> void:
	var hud := get_parent() as Hud
	if hud:
		hud.toggle_sub("power")


## Короткое состояние объекта для плашки в заголовке.
func _thing_status(t: Thing) -> Array:
	if not t.built:
		return ["Монтаж" if t.order_eta < 0.0 else "Заказан", UITheme.INFO]
	if t.demolish:
		return ["Под снос", UITheme.WARN]
	if t.kind() == "saw":
		if not sim.power.powered(t):
			return ["Нет тока", UITheme.BAD]
		return ["Режет", UITheme.GOOD] if t.working else ["Ждёт", UITheme.WARN]
	if t.kind() != "machine":
		if t.kind() in ["vent_fan", "compressor", "boiler"] and not t.enabled:
			return ["Выключен", UITheme.MUTED]
		if t.def().has("power_kw") and not sim.power.powered(t):
			return ["Нет тока", UITheme.BAD]
		match t.kind():
			"vent_fan":
				return ["Тянет", UITheme.GOOD]
			"vent_hood":
				return ["Тянет", UITheme.GOOD] if sim.eng.hood_ok(t) else ["Не подключён", UITheme.WARN]
			"compressor":
				return ["Работает", UITheme.GOOD] if sim.eng.compressor_running(t) else ["Ждёт", UITheme.WARN]
			"heater":
				if sim.eng.heater_problem(t) != "":
					return ["Не греет", UITheme.BAD]
				return ["Греет", UITheme.GOOD] if sim.season.heating_season() else ["Не сезон", UITheme.MUTED]
			"boiler":
				var bp := sim.eng.boiler_problem(t)
				if bp != "":
					return ["Не греет", UITheme.BAD]
				return ["Греет", UITheme.GOOD] if sim.season.heating_season() else ["Не сезон", UITheme.MUTED]
		return ["", UITheme.MUTED]
	if t.broken:
		return ["Сломан", UITheme.BAD]
	if not t.enabled:
		return ["Выключен", UITheme.MUTED]
	if not sim.power.powered(t):
		return ["Нет тока", UITheme.BAD]
	if t.working:
		return ["Работает", UITheme.GOOD]
	return ["Простаивает", UITheme.WARN]


# ---------------------------------------------------------------- помещение

## Карточка клетки (1.12): стена, окно, дверь, ворота, забор или пол без помещения.
func show_cell(s: Sim, c: Vector2i) -> void:
	sim = s
	var w := sim.world
	if not w.inb(c):
		visible = false
		return
	var i := w.idx(c)
	_begin("cell", i, 320.0)
	dyn["anchor"] = c
	if sim.faults.at("cable", c) or sim.faults.at("pipe", c):
		_fault_card(c, i)
		return
	var pile := sim.logi.ground_on(c)
	if not pile.is_empty():
		_pile_card(c, pile)
		return
	if w.flora[i] != 0 and w.wall[i] == World.W_NONE and w.flr[i] == 0:
		_flora_card(c, i)
		return
	var wall := int(w.wall[i])
	var bpw := int(w.bp_wall[i])
	var is_wall := wall != World.W_NONE or (bpw != World.BP_NONE and bpw > 0)
	var d: Dictionary = Defs.wall_by_id.get(wall if wall != World.W_NONE else bpw, {}) if is_wall else Defs.floor_by_id.get(int(w.flr[i]) if w.flr[i] > 0 else int(w.bp_floor[i]), {})
	head.add_child(_form_head("Конструкция", "клетка %d·%d" % [c.x, c.y]))
	var top := UITheme.hbox(8)
	var tl := UITheme.title(str(d.get("name", "Клетка")), 16)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	var pending := (is_wall and bpw != World.BP_NONE) or (not is_wall and int(w.bp_floor[i]) != World.BP_NONE)
	var demol := (is_wall and bpw == 0) or (not is_wall and int(w.bp_floor[i]) == 0)
	top.add_child(_chip("под снос" if demol else ("чертёж" if pending else "построено"), UITheme.BAD if demol else (UITheme.INFO if pending else UITheme.GOOD)))
	head.add_child(top)
	var desc := str(d.get("desc", ""))
	if desc != "":
		head.add_child(_wrap(desc, 12, UITheme.MUTED))
	var info := ""
	if float(d.get("cost", 0)) > 0.0:
		info = "Стоимость клетки %s, стройка ~%d мин." % [Defs.money_str(float(d["cost"])), int(d.get("build_time", 0))]
	var r := sim.rooms.room_at(c + Vector2i(0, 1)) if is_wall else null
	if r == null and is_wall:
		r = sim.rooms.room_at(c + Vector2i(0, -1))
	if r:
		info += ("\n" if info != "" else "") + "Стена помещения «%s»." % r.title()
	if pending and not demol:
		var mat := sim.bmats.mat_for(i)
		if mat != "":
			var st := "на участке — строят по очереди" if sim.bmats.free_on_ground(mat) > 0 or int(sim.bmats.have().get(mat, 0)) > 0 else ("едет машиной" if sim.bmats.coming().has(mat) else "заказывается у поставщика")
			info += ("\n" if info != "" else "") + "Материал: %s — %s." % [BuildMats.mat_name(mat).to_lower(), st]
	if info != "":
		box.add_child(_wrap(info, 12, UITheme.TEXT))
	actions.add_child(UITheme.spacer())
	if pending:
		actions.add_child(_act("Отменить чертёж", func() -> void:
			sim.cancel_all_at(c)
			show_cell(sim, c), "Деньги за чертёж вернутся", "cancel", UITheme.BAD))
	elif (bool(d.get("buildable", true)) or w.inner_fence(c)) and (is_wall or w.flr[i] > 0):
		actions.add_child(_act("Снести", func() -> void:
			if sim.place_demolish(c):
				Snd.play("place", -8.0)
			show_cell(sim, c), "Рабочие разберут, клетка освободится", "demolish", UITheme.BAD))
	else:
		var nl := sim.next_lot()
		actions.add_child(UITheme.label("Граница участка — не сносится" + (" (соседний участок покупают: Развитие → Земля)" if nl >= 0 and WallKinds.is_fence(wall) else ""), 12, UITheme.MUTED))
	visible = true
	_fit()


## 1.18: груз на земле — штабель или пачка. Что лежит, сколько, кто уже несёт.
func _pile_card(c: Vector2i, pile: Array[Item]) -> void:
	var first: Item = pile[0]
	head.add_child(_form_head("Груз на земле", "клетка %d·%d" % [c.x, c.y]))
	var top := UITheme.hbox(10)
	var ic := TextureRect.new()
	ic.texture = Tex.for_item(first) if first.kind != "bmat" else Tex.item("%s_p3" % first.def_id)
	ic.custom_minimum_size = Vector2(40, 40)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(ic)
	var groups := {}
	var order: Array[String] = []
	var busy := 0
	for it in pile:
		var nm := it.display_name()
		if not groups.has(nm):
			groups[nm] = 0
			order.append(nm)
		groups[nm] = int(groups[nm]) + 1
		if it.reserved_by >= 0:
			busy += 1
	var title := first.display_name() if order.size() == 1 else "Груз"
	var tl := UITheme.title("%s — %d шт." % [title, pile.size()], 16)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(180, 0)
	top.add_child(tl)
	if busy > 0:
		top.add_child(_chip("несут %d" % busy, UITheme.INFO))
	head.add_child(top)
	var lines: Array[String] = []
	if order.size() > 1:
		for nm2 in order:
			lines.append("• %s — %d шт." % [nm2, int(groups[nm2])])
	var txt := ""
	match first.kind:
		"bmat":
			txt = "Поддон: %d из %d. Строители берут отсюда материал на ближайшую стройку." % [pile.size(), BuildMats.pallet(first.def_id)]
		"crate":
			txt = "Ящик с оборудованием ждёт установки или места на складе оборудования."
		"mat":
			txt = "Металл занесут на стеллаж, когда освободятся руки." if not sim.logi.in_zone(c) else "Лежит в зоне разгрузки — отсюда металл берут прямо к станкам."
		_:
			txt = "Детали отнесут дальше по маршруту или на склад."
	if not lines.is_empty():
		box.add_child(_wrap("\n".join(lines), 12, UITheme.TEXT))
	box.add_child(_wrap(txt, 12, UITheme.MUTED))
	actions.visible = false
	visible = true
	_fit()


## 1.18: авария на сети — обрыв провода или прорыв трубы.
func _fault_card(c: Vector2i, i: int) -> void:
	var layer := "cable" if sim.faults.at("cable", c) else "pipe"
	var f: Dictionary = sim.faults.list[Faults.key(layer, i)]
	head.add_child(_form_head("Авария", "клетка %d·%d" % [c.x, c.y]))
	var top := UITheme.hbox(8)
	var tl := UITheme.title(str(Faults.LAYERS[layer]), 16)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	var crew := float(f["fix_at"]) >= 0.0
	var fixing := sim.net_res.has(Faults.key(layer, i))
	top.add_child(_chip("бригада едет" if crew else ("чинят" if fixing else "ждёт ремонта"), UITheme.INFO if crew or fixing else UITheme.BAD))
	head.add_child(top)
	var txt := "Перебит кабель: дальше по линии тока нет — станки и свет за обрывом стоят." if layer == "cable" \
		else "Лопнула труба: дальше по ней воды нет — туалеты и раковины за прорывом сухие, на полу лужа."
	txt += " Любой свободный рабочий заменит кусок, как при прокладке сети."
	head.add_child(_wrap(txt, 12, UITheme.MUTED))
	actions.add_child(UITheme.spacer())
	if not crew:
		var cost := float(Faults.CREW_COST[layer])
		actions.add_child(_act("Аварийная бригада (%s)" % Defs.money_str(cost), func() -> void:
			if sim.can_afford(cost):
				sim.faults.call_crew(layer, i)
			show_cell(sim, c), "Починят за час, своих людей не отвлекать", "wrench", UITheme.TEXT))
	visible = true
	_fit()


## Дерево или куст (1.13): на своём участке — спилить, на чужом — подсказка, как купить землю.
func _flora_card(c: Vector2i, i: int) -> void:
	var w := sim.world
	var v := int(w.flora[i])
	var tree := v <= 3
	head.add_child(_form_head("Дерево" if tree else "Куст", "клетка %d·%d" % [c.x, c.y]))
	var top := UITheme.hbox(8)
	var tl := UITheme.title(World.flora_name(v).capitalize(), 16)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	var marked := int(w.bp_floor[i]) == 0
	if marked:
		top.add_child(_chip("спилят", UITheme.BAD))
	head.add_child(top)
	var own := w.in_plot(c)
	var txt := "Растёт на участке и мешает строить: на этой клетке нельзя поставить объект. Пол и стену можно — строитель сначала спилит дерево." if own \
		else "Это чужая земля. Соседние участки покупают через «Развитие → Земля»."
	if c.y > w.sidewalk_row:
		txt = "Городская аллея вдоль дороги."
	head.add_child(_wrap(txt, 12, UITheme.MUTED))
	actions.add_child(UITheme.spacer())
	if own and marked:
		actions.add_child(_act("Оставить", func() -> void:
			sim.cancel_all_at(c)
			show_cell(sim, c), "Пусть растёт", "cancel", UITheme.BAD))
	elif own:
		actions.add_child(_act("Спилить" if tree else "Выкорчевать", func() -> void:
			if sim.place_demolish(c):
				Snd.play("place", -8.0)
			show_cell(sim, c), "Рабочий уберёт за %d мин." % (14 if tree else 6), "demolish", UITheme.BAD))
	visible = true
	_fit()


func show_room(s: Sim, room_id: int) -> void:
	sim = s
	_begin("room", room_id, 340.0)
	if room_id < 0 or room_id >= sim.rooms.list.size():
		visible = false
		return
	var r: Rooms.Room = sim.rooms.list[room_id]
	dyn["anchor"] = r.cells[0]
	head.add_child(_form_head("Зона" if r.type != "" else "Помещение", "№ %d" % (room_id + 1)))
	var top := UITheme.hbox(8)
	var tl := UITheme.title(r.title(), 16)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	dyn["title"] = tl
	var chip := _chip("", UITheme.MUTED)
	top.add_child(chip)
	dyn["chip"] = chip
	head.add_child(top)
	var sp_n := sim.rooms.space_rooms(r.space).size()
	head.add_child(UITheme.label("Площадь %d кл. · окон %d · дверей %d%s" % [r.area(), r.windows, r.doors, (" · в зале ещё %d %s" % [sp_n - 1, Defs.plural(sp_n - 1, "зона", "зоны", "зон")]) if sp_n > 1 else ""], 12, UITheme.MUTED))
	# назначение — выпадающий список вместо сетки из 15 кнопок
	actions.add_child(UITheme.label("Назначение", 13, UITheme.MUTED))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", 13)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_item("— не назначено —")
	ob.set_item_metadata(0, "")
	var sel := 0
	for type in Rooms.UI_ORDER:
		var d: Dictionary = Defs.rooms[type]
		ob.add_icon_item(_swatch(Color(str(d.get("color", "#888")))), str(d["name"]))
		var i := ob.item_count - 1
		ob.set_item_metadata(i, type)
		var reqs: Array[String] = []
		for n: Dictionary in d.get("needs", []):
			reqs.append(str(n.get("text", "")))
		var mdt := Rooms.min_dims(type)
		ob.set_item_tooltip(i, "%s\nНужно: %s; помещение от %d×%d клеток внутри." % [str(d.get("desc", "")), ", ".join(reqs), mdt.x, mdt.y])
		if r.type == type:
			sel = i
	ob.select(sel)
	var on_pick := func(i: int) -> void:
		var rr := _current_room()
		if rr:
			sim.rooms.assign(rr, str(ob.get_item_metadata(i)))
			show_room(sim, rr.id)
	ob.item_selected.connect(on_pick)
	actions.add_child(ob)
	var st := _wrap("", 13, UITheme.TEXT)
	box.add_child(st)
	dyn["state"] = st
	visible = true
	refresh()
	_fit()


static var _swatches: Dictionary = {}


static func _swatch(c: Color) -> Texture2D:
	var key := c.to_html()
	if _swatches.has(key):
		return _swatches[key]
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(c)
	var tex := ImageTexture.create_from_image(img)
	_swatches[key] = tex
	return tex


func _current_room() -> Rooms.Room:
	if not dyn.has("anchor"):
		return null
	return sim.rooms.room_at(dyn["anchor"])


func _room_state(r: Rooms.Room) -> String:
	var lines: Array[String] = []
	if r.type == "":
		lines.append("Выберите назначение — от него зависит, как люди используют помещение и что они о нём думают.")
	else:
		var d: Dictionary = Defs.rooms.get(r.type, {})
		lines.append(str(d.get("desc", "")))
		lines.append("Требования:")
		var min_area := int(d.get("min_area", 1))
		var md := Rooms.min_dims(r.type)
		lines.append(("  ✓ " if r.area() >= min_area else "  × ") + "помещение от %d×%d клеток внутри (у вас %d×%d)" % [md.x, md.y, r.rect.size.x, r.rect.size.y])
		var floors: Array = d.get("floors", [])
		if not floors.is_empty():
			var fname := str(Defs.floor_by_id.get(int(floors[0]), {}).get("name", "пол")).to_lower()
			var has_floor := not r.missing.any(func(m: String) -> bool: return m.contains(fname))
			lines.append(("  ✓ " if has_floor else "  × ") + fname)
		for n: Dictionary in d.get("needs", []):
			var txt := str(n.get("text", ""))
			lines.append(("  × " if r.missing.has(txt) else "  ✓ ") + txt)
		var lv := sim.upkeep.level(r)
		var pp: Array[String] = []
		for p: Array in sim.upkeep.level_parts(r):
			pp.append("%s %s" % [str(p[0]), ("%+.1f" % float(p[1])).replace(".0", "")])
		lines.append("Обустройство: %s %d из 5%s" % ["★".repeat(lv) + "☆".repeat(5 - lv), lv, (" (" + ", ".join(pp) + ")") if not pp.is_empty() else ""])
		if lv < 5:
			lines.append("Выше уровень — лучше настроение: окна, хороший пол, электрический свет, растения и декор (Объекты → Декор), чистота.")
	lines.append("Чистота: %d%%%s" % [sim.upkeep.cleanliness(r), " — нужна уборка" if sim.upkeep.room_dirt(r) > Upkeep.DIRTY else ""])
	var fu := sim.eng.fumes_of(r)
	var vk := sim.eng.vent_k(r)
	if fu >= 3.0 or vk > 0.0 or sim.eng.needs_vent(r):
		lines.append("Воздух: %s · %s" % ["чисто" if fu < 15.0 else ("душно, %d%%" % int(fu) if fu < Eng.SMOKY else "дым, %d%%" % int(fu)),
			("вентиляция ×%.1f" % vk) if vk > 0.0 else ("нужна вентиляция (Сети → Вентиляция)" if sim.eng.needs_vent(r) else "без вентиляции")])
	if r.lit:
		lines.append("Свет: есть" + (" (электричество)" if r.powered else " (дневной, из окон)"))
	else:
		lines.append("Свет: нет — проложите кабель от подстанции в помещение")
	return "\n".join(lines)


# ---------------------------------------------------------------- обновление

func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		refresh()


func _set_chip(text: String, col: Color) -> void:
	var chip: Label = dyn.get("chip")
	if chip == null:
		return
	chip.visible = text != ""
	if chip.text == text:
		return
	chip.text = text
	# 1.20: красная плашка подсказывает, что сделать
	var fixes := {"Нет тока": "Как исправить: протяните кабель от щитка к этому объекту («Сети», E). Если кабель есть — проверьте, не выбит ли автомат, и хватает ли мощности подстанции.",
		"Сломан": "Как исправить: отправьте в ремонт кнопкой ниже — придёт слесарь или станочник. Чтобы ломалось реже, включите ППР (Производство → Станки).",
		"Не греет": "Как исправить: котлу нужен ток, вода (труба от водомера) и топливо. Подробности — в строке состояния ниже.",
		"Простаивает": "Нет работы или некому работать: проверьте заказы, металл на стеллаже и есть ли станочник нужной профессии.",
		"Не подключён": "Как исправить: протяните воздуховод от вытяжного вентилятора к зонту («Сети» → «Вентиляция»)."}
	chip.tooltip_text = str(fixes.get(text, ""))
	chip.mouse_filter = Control.MOUSE_FILTER_STOP if chip.tooltip_text != "" else Control.MOUSE_FILTER_IGNORE
	chip.add_theme_color_override("font_color", col)
	chip.add_theme_stylebox_override("normal", UITheme.sb(Color(col.r, col.g, col.b, 0.14), Color(col.r, col.g, col.b, 0.5), 1, 9, 8, 1))


func refresh() -> void:
	if sim == null:
		return
	match kind:
		"worker":
			_refresh_worker()
		"visitor":
			var v := sim.get_person(id)
			if v == null or sim.inspect.visit.is_empty():
				visible = false
				return
			(dyn["act"] as Label).text = "Сейчас: " + v.activity
			var f: Array = sim.inspect.visit.get("found", [])
			var txt := "Записано нарушений: %d" % f.size()
			for vi: Dictionary in f:
				txt += "\n• " + str(vi["text"])
			(dyn["found"] as Label).text = txt if not Inspections.VISIT_KINDS.has(str(sim.inspect.visit.get("type", ""))) else "Ходит по заводу и смотрит, как всё устроено."
		"thing":
			var t: Thing = sim.things.get(id)
			if t == null:
				visible = false
				return
			(dyn["state"] as Label).text = _thing_state(t)
			var stt := _thing_status(t)
			_set_chip(str(stt[0]), stt[1])
			if dyn.has("cond"):
				(dyn["cond"] as ProgressBar).value = t.condition
				(dyn["cond_l"] as Label).text = "%d%%" % int(t.condition)
				(dyn["prog"] as ProgressBar).value = t.progress * 100.0
				(dyn["prog_l"] as Label).text = "%d%%" % int(t.progress * 100.0)
		"room":
			var r := _current_room()
			if r == null:
				visible = false
				return
			(dyn["state"] as Label).text = _room_state(r)
			(dyn["title"] as Label).text = r.title()
			if r.type == "":
				_set_chip("", UITheme.MUTED)
			elif r.valid:
				var lv2 := sim.upkeep.level(r)
				_set_chip("★".repeat(lv2), UITheme.GOOD if lv2 >= 3 else UITheme.WARN)
			else:
				_set_chip("Не оборудовано", UITheme.WARN)


func _refresh_worker() -> void:
	var w := sim.get_worker(id)
	if w == null:
		visible = false
		return
	var act := w.activity if w.present else ("Не вышел на работу" if w.skip_shift else "Дома · %s" % Worker.SHIFT_NAMES[w.shift])
	if w.sick_until > sim.minute and w.away_why != "":
		act = "%s до %s" % [w.away_why.capitalize(), sim.season.date_str(int(w.sick_until / 1440.0) + 1)]
	if not w.order.is_empty() and w.present:
		act += " · ⚑ приказ до %02d:%02d" % [int(fmod(float(w.order.get("until", 0.0)), 1440.0) / 60.0), int(fmod(float(w.order.get("until", 0.0)), 60.0))]
	(dyn["act"] as Label).text = ("● " + act) if w.present else "○ " + act
	(dyn["act"] as Label).add_theme_color_override("font_color", (Color("#f0c060") if not w.order.is_empty() else UITheme.INFO) if w.present else UITheme.MUTED)
	var mb: ProgressBar = dyn["mood_bar"]
	mb.value = w.mood
	var mc := Mood.color(w.mood)
	mb.add_theme_stylebox_override("fill", UITheme.sb(mc, mc, 0, 3, 0, 0))
	var hr_on := sim.office.active("hr")
	var risk := sim.dev.on("hr3") and not w.is_itr() and (w.low_mood_days > 0 or w.mood < Defs.b("quit_mood") + 8.0)   # «Кадровый резерв»
	(dyn["mood_lab"] as Label).text = ("%d · %s" % [int(w.mood), Mood.label(w.mood).to_lower()] if hr_on else Mood.label(w.mood).to_lower()) + (" · риск ухода!" if risk else "")
	(dyn["mood_lab"] as Label).add_theme_color_override("font_color", UITheme.BAD if risk else mc)
	if dyn.has("t_thoughts"):
		var parts := Mood.breakdown(sim, w)
		var sig := str(parts) + str(hr_on)
		if sig != str(dyn["t_thoughts_sig"]):
			dyn["t_thoughts_sig"] = sig
			var tv: VBoxContainer = dyn["t_thoughts"]
			UITheme.clear(tv)
			var shown := parts.filter(func(p: Array) -> bool: return absf(float(p[1])) >= 0.5)
			if shown.is_empty():
				tv.add_child(UITheme.label("Ничего особенного", 12, UITheme.MUTED))
			shown.sort_custom(func(a: Array, b: Array) -> bool: return absf(float(a[1])) > absf(float(b[1])))
			var cap := 8 if hr_on else 3
			for i in mini(shown.size(), cap):
				var p: Array = shown[i]
				var v := float(p[1])
				var row := UITheme.hbox(5)
				var vl := UITheme.label(("%+d" % int(round(v))) if hr_on else ("▲" if v > 0 else "▼"), 12, UITheme.GOOD if v > 0 else UITheme.BAD, UITheme.f_semi)
				vl.custom_minimum_size = Vector2(26, 0)
				vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				row.add_child(vl)
				var tl := UITheme.label(str(p[0]), 12, UITheme.TEXT)
				tl.clip_text = true
				tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				tl.custom_minimum_size = Vector2(150, 0)
				tl.tooltip_text = str(p[0])
				tl.mouse_filter = Control.MOUSE_FILTER_STOP
				row.add_child(tl)
				tv.add_child(row)
			if shown.size() > cap:
				tv.add_child(UITheme.label(("…и ещё %d" % (shown.size() - cap)) if hr_on else "…остальное и цифры — у кадровика (отдел кадров)", 12, UITheme.MUTED))
			_fit()
	if dyn.has("t_life_hint"):
		var lf := Mood.life(sim, w)
		for g in Mood.LIFE:
			var gk := str(g[0])
			var lv := float(lf[gk]["v"])
			var gb: ProgressBar = dyn["t_life_b_" + gk]
			gb.value = lv
			var gc := UITheme.GOOD if lv >= 70.0 else (Color("#8fa6bb") if lv >= 45.0 else (UITheme.WARN if lv >= 30.0 else UITheme.BAD))
			gb.add_theme_stylebox_override("fill", UITheme.sb(gc, gc, 0, 3, 0, 0))
			(dyn["t_life_v_" + gk] as Label).text = "хорошо" if lv >= 70.0 else ("норма" if lv >= 45.0 else ("терпимо" if lv >= 30.0 else "плохо"))
			(dyn["t_life_v_" + gk] as Label).add_theme_color_override("font_color", gc if lv < 45.0 or lv >= 70.0 else UITheme.MUTED)
			var tip: Array[String] = []
			for pp: Array in lf[gk]["parts"]:
				if absf(float(pp[1])) >= 0.5:
					tip.append(("%+d  " % int(round(float(pp[1])))) + str(pp[0]))
			var ttxt := str(g[1]) + ": " + (("\n" + "\n".join(tip)) if not tip.is_empty() else "ничего особенного") + "\n\nЧто помогает: " + str(Mood.LIFE_HINT[gk])
			gb.tooltip_text = ttxt
			(dyn["t_life_l_" + gk] as Label).tooltip_text = ttxt
		var worst := Mood.life_worst(sim, w)
		var hl: Label = dyn["t_life_hint"]
		hl.text = ("Проседает «%s»: %s" % [str(worst[1]).to_lower(), str(worst[2]).to_lower()]) if not worst.is_empty() else ""
		hl.visible = not worst.is_empty()
	if dyn.has("t_need_food"):
		for k in ["food", "bladder", "rest"]:
			var b: ProgressBar = dyn["t_need_" + k]
			var v2 := float(w.needs[k])
			b.value = v2
			var c := UITheme.GOOD if v2 > 50.0 else (UITheme.WARN if v2 > 20.0 else UITheme.BAD)
			b.add_theme_stylebox_override("fill", UITheme.sb(c, c, 0, 3, 0, 0))
			(dyn["t_needl_" + k] as Label).text = "%d%%" % int(v2)
	if dyn.has("t_st_days"):
		(dyn["t_st_days"] as Label).text = str(w.days_worked)
		(dyn["t_st_ops"] as Label).text = str(w.parts_made)
		var spd := Mood.productivity(w) * sim.office.speed_k(w) * sim.season.work_k(w) * sim.training.speed_k(w) * sim.eng.speed_k(w)
		(dyn["t_st_speed"] as Label).text = "×%.2f" % spd
		(dyn["t_st_speed"] as Label).add_theme_color_override("font_color", UITheme.GOOD if spd >= 1.0 else UITheme.WARN)
		if w.is_itr():
			var dk := sim.office.desk_k(w)
			(dyn["t_st_ppe"] as Label).text = "кабинет" if dk >= 1.0 else ("контора" if dk > 0.0 else "нет!")
			(dyn["t_st_ppe"] as Label).add_theme_color_override("font_color", UITheme.TEXT if dk >= 1.0 else (UITheme.WARN if dk > 0.0 else UITheme.BAD))
		else:
			(dyn["t_st_ppe"] as Label).text = "нет!" if w.ppe <= 0.0 else "%d%%" % int(w.ppe)
			(dyn["t_st_ppe"] as Label).add_theme_color_override("font_color", UITheme.BAD if w.ppe <= 0.0 else UITheme.TEXT)
	if dyn.has("t_stats"):
		var parts2: Array[String] = []
		if w.is_itr():
			var dk2 := sim.office.desk_k(w)
			parts2.append("Отдел: %s" % str(Defs.departments.get(w.dept(), {}).get("name", "")))
			if dk2 <= 0.0:
				parts2.append("НЕТ РАБОЧЕГО МЕСТА — поставьте стол ИТР в кабинет")
			elif dk2 < 1.0:
				parts2.append("работает в общей конторе (−30%)")
		else:
			if w.present:
				parts2.append("на месте %+d °C" % int(round(sim.season.temp_at(w.cell()))))
			var hc := sim.eng.worker_class(w)
			if hc > 0:
				parts2.append("вредность %s: +%d%% к ставке%s" % [Eng.CLASS_NAMES[hc], int(Eng.BONUS[hc] * 100.0), ", молоко" if sim.eng.milk_on else ", молоко не дают"])
		var lab: Label = dyn["t_stats"]
		lab.text = " · ".join(parts2)
		lab.visible = not parts2.is_empty()
	if dyn.has("t_wage"):
		var market := Mood.market_wage(w)
		(dyn["t_wage"] as Label).text = "%s за смену" % Defs.money_str(w.wage)
		var sub := "на рынке ~%s" % Defs.money_str(market)
		if w.wage < int(market * 0.97):
			sub += " — недоплачиваете"
		if w.shift == 1:
			sub += " · ночные +%d%%" % int(Defs.b("night_bonus") * 100.0)
		if w.pending_shift >= 0:
			sub += " · переходит в %s" % ("1-ю смену" if w.pending_shift == 0 else "2-ю смену")
		(dyn["t_wage_s"] as Label).text = sub
		(dyn["t_wage_s"] as Label).add_theme_color_override("font_color", UITheme.WARN if w.wage < int(market * 0.97) else UITheme.MUTED)


## Курсы, наставник, ученики, друзья и недруги — одной-двумя строками.
func _people_line(w: Worker) -> String:
	var tr := sim.training
	var parts: Array[String] = []
	if w.brigade >= 0:
		var b := sim.crew.brigade(w.brigade)
		if not b.is_empty():
			var ld := sim.crew.lead_of(w.brigade)
			parts.append("«%s»%s" % [str(b["name"]), (", бригадир (+10% к ставке)" if ld == w else (", бригадир — " + ld.call_name()) if ld else "")])
	if sim.crew.union_on() and int(sim.crew.union.get("lead", -1)) == w.id:
		parts.append("председатель профкома")
	var c := tr.course_of(w)
	if not c.is_empty():
		parts.append("на курсах: %s, %d%%" % [str(Worker.SKILL_NAMES.get(str(c["skill"]), "")).to_lower(), int(tr.progress(w) * 100.0)])
	var m := tr.mentor_of(w)
	if m:
		parts.append("наставник: " + m.full_name())
	var ap: Array[String] = []
	for a in tr.apprentices(w):
		ap.append(a.call_name())
	if not ap.is_empty():
		parts.append("ученики: " + ", ".join(ap))
	if w.practice_until >= 0:
		parts.append("практика до дня %d" % w.practice_until)
	var fr: Array[String] = []
	for f in tr.friends(w):
		fr.append(f.call_name())
	if not fr.is_empty():
		parts.append("дружит: " + ", ".join(fr.slice(0, 3)))
	var fo: Array[String] = []
	for f2 in tr.foes(w):
		fo.append(f2.call_name())
	if not fo.is_empty():
		parts.append("не ладит: " + ", ".join(fo.slice(0, 3)))
	return "" if parts.is_empty() else "\n" + " · ".join(parts)


func _thing_state(t: Thing) -> String:
	if not t.built:
		if t.order_eta >= 0.0:
			return "Заказано у поставщика. Фургон с оборудованием приедет %s, ящики разгрузят и принесут сюда." % sim._eta_str(t.order_eta)
		if t.crates_in < t.crates_need:
			return "Привезли. Ящики несут к месту установки: %d из %d.%s" % [t.crates_in, t.crates_need, "" if sim.logi.has_zone() else "\nСовет: отметьте зону разгрузки у ворот (Стройка → Зоны на улице)."]
		return "Всё на месте — ждёт монтажа. Прогресс: %d%%" % int(t.progress * 100.0)
	if t.demolish:
		return "Помечен под снос: рабочие разберут его, когда освободятся."
	var lines: Array[String] = []
	var src := str(t.def().get("power_source", ""))
	if src != "":
		var net := sim.power.net_of_thing(t)
		var cap := sim.power.source_capacity(t)
		lines.append("Мощность: %d кВт" % int(cap))
		if net == null:
			lines.append("Кабель не подведён — тяните кабель от подстанции прямо в клетки розеток станков и приборов.")
		else:
			lines.append("Сеть: нагрузка %.1f из %d кВт · потребителей %d · помещений %d" % [net.load, int(net.capacity), net.consumers.size(), net.rooms.size()])
			if net.tripped:
				lines.append("АВТОМАТ ВЫБИТ — ждём электрика или рабочего.")
			elif net.over():
				lines.append("ПЕРЕГРУЗ: станки тянут больше, чем даёт подстанция. Скоро выбьет автомат — поставьте вплотную аккумуляторные шкафы.")
		if Power.boostable(t):
			var bl := sim.power.batteries_of(t)
			var base := float(t.def().get("capacity_kw", 40.0))
			if bl.is_empty():
				lines.append("Своих %d кВт. Аккумуляторов нет: вплотную к подстанции (и по углам) можно поставить до %d шкафов — каждый +%d кВт (Объекты → Электрика)." % [int(base), Power.BATT_MAX, 20])
			else:
				lines.append("Своих %d кВт + аккумуляторы: %d из %d шкафов, +%d кВт." % [int(base), mini(bl.size(), Power.BATT_MAX), Power.BATT_MAX, int(sim.power.battery_boost(t))])
		elif net and net.over():
			lines.append("Мощности мало — прижмите к подстанции аккумуляторные шкафы (+20 кВт каждый) или выключите лишний станок.")
		return "\n".join(lines)
	match t.def_id:
		"days_board":
			lines.append("Дней без травм: %d. В помещении с табло травм на 5%% меньше." % sim.crew.safe_days())
		"union_board":
			lines.append("Профком: " + ("председатель — %s" % sim.crew.union_lead().full_name() if sim.crew.union_lead() else ("есть" if sim.crew.union_on() else "профсоюза пока нет")))
	match t.kind():
		"battery":
			var host := sim.power.battery_host(t)
			lines.append("Подстанция: " + ("рядом — шкаф добавляет ей %d кВт мощности" % int(t.def().get("boost_kw", 20)) if host else "НЕТ — поставьте шкаф вплотную к подстанции"))
		"pump":
			sim.water.update()
			var k := int(sim.water.thing_net.get(t.id, -1))
			if k < 0:
				lines.append("Не подключена к водопроводу — протяните трубу.")
			else:
				lines.append("Приборов в сети: %d · напора хватает на %d" % [sim.water.net_fix[k], sim.water.net_cap[k]])
			lines.append("Работает" if sim.water.pump_running(t) else ("Нет тока" if not sim.power.powered(t) else "Не работает"))
		"machine":
			var pr := t.process()
			var prd: Dictionary = Defs.processes.get(pr, {})
			var prof_nm := str(Worker.PROF_NAMES.get(str(prd.get("prof", "")), "станочник")).to_lower()
			if t.broken:
				lines.append("Ремонт: %s запчастей и полдня работы слесаря или станочника." % Defs.money_str(Defs.b("repair_cost")))
			elif not t.enabled:
				pass
			elif not sim.power.connected(t):
				lines.append("Нет питания: заведите кабель от подстанции в клетку розетки станка.")
			elif not sim.power.powered(t):
				lines.append("Нет тока: выбит автомат или сеть без источника.")
			elif not sim.planner.staffed(t) and t.user < 0:
				lines.append("Некому работать: нужен %s — наймите в разделе «Люди → Найм»." % prof_nm)
			elif t.product == "":
				lines.append("Нет работы: нет заказа, металла или деталей с прошлой операции.")
			else:
				var rt := Defs.route(t.product)
				lines.append("Задание: %s · операция %d из %d" % [Defs.product_name(t.product), t.job_step + 1, rt.size()])
				var miss := sim.prod.missing_inputs(t)
				if not miss.is_empty() and not t.working:
					var ms: Array[String] = []
					for k in miss.keys():
						var nm2 := Defs.material_name(str(k)) if Defs.materials.has(k) else Defs.product_name(str(k))
						ms.append("%s ×%d" % [nm2, int(miss[k])])
					lines.append("Ждёт: " + ", ".join(ms))
				if not sim.prod.has_cons(t):
					lines.append("Нет расходников (%s) — снабжение уже везёт." % str(Defs.consumables.get(str(prd.get("cons", "")), {}).get("short", "")))
				var ck := sim.prod.crane_k(t)
				if ck < 1.0:
					lines.append("Тяжёлая деталь без кран-балки: на %d%% медленнее." % int(round((1.0 / ck - 1.0) * 100.0)))
			if t.is_batch():
				lines.append("Печь: партия до %d деталей, греется сама." % t.slot_cap(0))
			if not t.broken and t.condition < sim.service_at():
				lines.append("Изношен — ждёт обслуживания (%s)." % Defs.money_str(Defs.b("service_cost")))
			elif not t.broken and t.condition < Defs.b("breakdown_below"):
				lines.append("Сильно изношен — может сломаться!")
			var am := sim.eng.air_mode(t)
			if am != "":
				var pz := sim.eng.pressure(t)
				if am == "need":
					lines.append("Сжатый воздух: " + ("есть — краскопульт" if pz >= 0.99 else ("мало давления — медленнее" if pz > 0.0 else "НЕТ — красят кистью, в 1,5 раза дольше (Сети → Сжатый воздух)")))
				else:
					lines.append("Сжатый воздух: " + ("есть — пневмогайковёрт, на 20% быстрее" if pz >= 0.99 else ("мало давления" if pz > 0.0 else "нет (с ним на 20% быстрее)")))
			var cls := sim.eng.class_of(t)
			var fs := sim.eng.factors(t)
			var fnames: Array[String] = []
			for f: Array in fs:
				fnames.append(str(f[0]) + ("" if str(f[2]) == "" else " " + str(f[2])))
			var now_cls := sim.eng.class_now(t)
			var ctext := "СОУТ: не проводилась" if cls < 0 else "СОУТ: класс %s (%s)" % [Eng.CLASS_NAMES[cls], Eng.CLASS_TEXT[cls]]
			ctext += " · сейчас " + ("допустимо" if fnames.is_empty() else "вредно: " + ", ".join(fnames))
			if cls >= 0 and now_cls < cls:
				ctext += " — переоценка снизит класс"
			lines.append(ctext)
			if t.process() in ["welding", "paint", "heat", "casting"]:
				lines.append("Вытяжной зонт: " + ("работает" if bool(sim.eng.hooded.get(t.id, false)) else "нет — дым идёт в помещение"))
			var op := sim.get_worker(t.user)
			lines.append("Работает: %s · нужен %s" % [op.full_name() if op else "—", prof_nm])
			lines.append("Вход %d · выход %d · операций %d · %.1f кВт" % [sim.count_slot(t, 0), sim.count_slot(t, 1), t.parts_made, float(t.machine_def().get("power_kw", 0.0))])
		"storage", "qc":
			var counts := {}
			for s in t.slot_count():
				for iid in sim.slot_ids(t, s):
					var it: Item = sim.items.get(iid)
					if it:
						var n := it.display_name()
						counts[n] = int(counts.get(n, 0)) + 1
			var total := 0
			var cap2 := 0
			for s in t.slot_count():
				total += sim.count_slot(t, s)
				cap2 += t.slot_cap(s)
			lines.append("Заполнено: %d из %d" % [total, cap2])
			var keys := counts.keys()
			for i in mini(keys.size(), 6):
				lines.append("· %s — %d шт." % [keys[i], counts[keys[i]]])
			if keys.size() > 6:
				lines.append("· …и ещё %d наименований" % (keys.size() - 6))
			if t.kind() == "qc":
				var q := sim.get_worker(t.user)
				lines.append("Контролёр: " + (q.full_name() if q else "—"))
		"locker":
			var owners: Array[String] = []
			for w in sim.workers:
				if w.locker_id == t.id:
					owners.append(w.full_name())
			var seats := maxi(1, int(t.def().get("seats", 1)))
			if seats > 1:
				lines.append("Мест: %d · занято %d" % [seats, owners.size()])
			lines.append("Закреплён за: " + (", ".join(owners) if not owners.is_empty() else "свободен"))
			lines.append("В бытовке" if sim.rooms.thing_in(t, "locker") else "Стоит не в бытовке — переодеваться здесь не так приятно.")
		"toilet", "chair", "rest":
			lines.append("Занято" if not t.spot_users.is_empty() else "Свободно")
		"desk":
			var owner2: Worker = null
			for w2 in sim.workers:
				if w2.desk_id == t.id:
					owner2 = w2
			lines.append("Рабочее место: " + ((owner2.full_name() + ", " + owner2.prof_lc()) if owner2 else "свободно"))
			var rr := sim.rooms.room_of_thing(t)
			if rr == null or not Rooms.OFFICE_TYPES.has(rr.type) or not rr.valid:
				lines.append("Стоит не в кабинете: обнесите стенами, постелите линолеум и назначьте помещение (контора, бухгалтерия, ПДО…).")
		"appliance":
			lines.append("Потребляет %.1f кВт · %s" % [float(t.def().get("power_kw", 0.0)), "питание есть" if sim.power.powered(t) else "НЕТ ПИТАНИЯ"])
		"chip_bin":
			lines.append("Стружки: %d из %d кг" % [int(float(sim.upkeep.bin_kg.get(t.id, 0.0))), int(Upkeep.BIN_CAP)])
			lines.append("Во всех контейнерах: %d кг ≈ %s. Ломовоз приезжает по пятницам, забирает стружку и брак из тары." % [int(sim.upkeep.bin_total()), Defs.money_str(sim.upkeep.bin_total() * Upkeep.CHIP_PRICE)])
			if sim.upkeep.pickups > 0:
				lines.append("Сдано в металлолом за всё время: %s" % Defs.money_str(sim.upkeep.scrap_earned))
		"vent_fan":
			var vn := sim.eng.vnet_of_thing(t)
			lines.append("Производительность: до %d клеток площади · %.1f кВт" % [int(t.def().get("vent_cap", 80)), float(t.def().get("power_kw", 0.0))])
			if vn:
				var rn: Array[String] = []
				for rid in vn.rooms:
					if rid >= 0 and rid < sim.rooms.list.size():
						rn.append(sim.rooms.list[rid].title())
				lines.append("Тянет из: " + (", ".join(rn) if not rn.is_empty() else "ниоткуда — поставьте в помещение или подведите воздуховод"))
				if vn.area > 0:
					lines.append("Площадь сети %d кл., вентиляторов %d: кратность ×%.1f" % [vn.area, vn.srcs.size(), vn.cap / float(vn.area) if vn.cap > 0.0 else 0.0])
			if not sim.power.powered(t):
				lines.append("Нет тока — подведите кабель к розетке.")
		"vent_hood":
			lines.append("Подключён к вентилятору" if sim.eng.hood_ok(t) else "Не тянет: подведите воздуховод к сети с работающим вентилятором.")
			var hm: Array[String] = []
			for m2 in sim.things_of("machine"):
				if m2.rect().grow(1).has_point(t.cell):
					hm.append(m2.title())
			lines.append("Над: " + (", ".join(hm) if not hm.is_empty() else "станков рядом нет — зонт вешают над станком или вплотную"))
		"compressor":
			var an := sim.eng.anet_of_thing(t)
			lines.append("Держит %d потребителей · %.1f кВт под нагрузкой" % [int(t.def().get("air_cap", 4)), float(t.def().get("power_kw", 0.0))])
			if an == null:
				lines.append("Пневмомагистраль не подведена (Сети → Сжатый воздух).")
			else:
				lines.append("Подключено потребителей: %d · работают сейчас: %d" % [an.users.size(), int(an.demand)])
			lines.append("В компрессорной — тихо" if sim.rooms.thing_in(t, "compressor_room") else "Шумит под 90 дБ: лучше в отдельной компрессорной.")
		"boiler":
			var bp2 := sim.eng.boiler_problem(t)
			if bp2 != "":
				lines.append("Не греет: " + bp2)
			else:
				lines.append("Греет батарей: %d из %d (подключённых трубой к его водопроводу)" % [sim.eng.boiler_load(t), int(t.def().get("boiler_cap", 16))])
			lines.append("Газ — %d%% от цены городского тепла. Аварии на теплотрассе не страшны." % int(round(Eng.BOILER_K * 100.0)))
		"radiator":
			if sim.eng.boiler_rads.has(t.id):
				lines.append("Тепло: от своего газового котла")
			elif not sim.eng.heater_ok():
				lines.append("Батарея холодная: нет работающего электрокотла. Поставьте его вплотную к насосной станции (Объекты → Водопровод) и подведите ток.")
			else:
				lines.append("Тепло: от электрокотла у насосной" + ("" if sim.eng.radiator_on(t) else " — АВАРИЯ, батарея холодная"))
		"heater":
			var hp := sim.eng.heater_problem(t)
			lines.append("Не греет: " + hp if hp != "" else "Греет воду для всех батарей завода (%d шт.) · %.1f кВт" % [sim.season.radiators, float(t.def().get("power_kw", 0.0))])
		"camera":
			var rr := sim.rooms.room_at(t.cell)
			lines.append(("Смотрит за помещением «%s»" % rr.title()) if rr else "Висит не в помещении — смотреть не за чем")
			lines.append("Записывает" if sim.crew.cam_ok(t) else "Нет тока: подведите кабель не дальше 3 клеток")
		"ppe_cabinet":
			lines.append("Комплектов СИЗ на складе: %d" % sim.eng.ppe_stock())
			var bare := sim.eng.without_ppe().size()
			lines.append("Без СИЗ сейчас: %d чел." % bare if bare > 0 else "У всех рабочих СИЗ в порядке.")
		"saw":
			var bl: Array[String] = []
			for mk in sim.upkeep.blanks.keys():
				if int(sim.upkeep.blanks[mk]) > 0:
					bl.append("%s ×%d" % [Defs.material_name(str(mk)), int(sim.upkeep.blanks[mk])])
			lines.append("Нарезано заготовок: " + (", ".join(bl) if not bl.is_empty() else "нет"))
			lines.append("Первая операция из заготовки на %d%% быстрее. Запас — до %d на материал." % [int(round((1.0 - Upkeep.BLANK_K) * 100.0)), Upkeep.BLANKS_MAX])
			var so := sim.get_worker(t.user)
			lines.append("Режет: " + (so.full_name() if so else "—") + (" · нет питания" if not sim.power.powered(t) else ""))
		_:
			lines.append("Стоимость: " + Defs.money_str(float(t.def().get("cost", 0))))
	var r := sim.rooms.room_of_thing(t)
	if r:
		lines.append("Помещение: " + r.title() + ("" if r.valid or r.type == "" else " (не оборудовано)"))
	return "\n".join(lines)
