class_name Hud
extends Control
## Интерфейс игровой сцены: верхняя панель (деньги, время, скорость), нижняя панель
## (стройка, объекты, окна), подменю стройки, подсказка инструмента, карточка выделения,
## лента уведомлений, окна и меню паузы.

const LEVEL_COLORS := [Color("#8fb3c8"), Color("#8fcf78"), Color("#e0aa48"), Color("#d8644e")]
const OBJ_CATS := ["Станки", "ЧПУ", "Сварка и сборка", "Термо и покраска", "Склад", "Логистика", "ОТК", "Быт", "Освещение", "Офис", "Электрика", "Водопровод", "Инженерия", "Безопасность", "Декор"]

var g: GameMain
var sim: Sim
var money_l: Label
var rep_l: Label
var goal_l: Label
var date_l: Label
var shift_l: Label
var power_l: Label
var fast_l: Label
var speed_btns: Array[Button] = []
var bottom_btns: Dictionary = {}
var order_badge: Label
var events_badge: Label
var paper_badge: Label
var weather_l: Label
var weather_i: TextureRect
var money_d: Label
var stage_l: Label
var stars_l: Label
var people_l: Label
var people_s: Label
var time_l: Label
var power_bar: ProgressBar
var people_badge: Label
var todo: TodoPanel = null
var cal_sheet: FactoryUI.Sheet = null   ## листок отрывного календаря в верхней панели
var emblem_v: Emblem.View = null        ## 1.17: эмблема завода в шапке
var ov_panel: PanelContainer = null      ## панель слоёв справа (для подсветки в обучении)
var speed_box: HBoxContainer = null      ## кнопки скорости
var company_l: Label
var company_s: Label
var _company_rev := -1
var _chips: Dictionary = {}
var forced_overlay := ""          ## оверлей, выбранный игроком вручную
var ov_btns: Dictionary = {}      ## панель оверлеев справа: ключ -> кнопка
var legend_panel: PanelContainer
var legend_box: VBoxContainer
var _legend_sig := ""
const OVERLAYS := [["rooms", "Зоны", "Зоны и помещения: что где, чего не хватает"],
	["nets", "Коммуникации", "Все сети сразу: кабель, водопровод, сжатый воздух, вентиляция — и кому чего не хватает"],
	["light", "Освещение", "Где светло от ламп и окон, где темно"],
	["temp", "Температура", "Тепло и холод по помещениям, батареи"],
	["traffic", "Потоки людей", "Где чаще ходят — тропы и пробки"], ["load", "Загрузка станков", "Работает, простаивает, брак (нужен ПДО)"],
	["dirt", "Чистота", "Стружка и грязь, уровень обустройства"],
	["crew", "Бригады и охрана", "Участки бригад, камеры и посты"]]
var letter_box: Control = null     ## открытое письмо-событие
var tutorial: TutorialPanel = null
var letter_id := -1
var sub_panel: PanelContainer
var sub_root: VBoxContainer
var sub_kind := ""
var obj_cat := "Станки"
var net_kind := "power"   ## подменю «Сети»: "power" — электричество и свет, "water" — водопровод
var hint_panel: PanelContainer
var hint_l: Label
var info: InfoPanel
var toasts: VBoxContainer
var win: GameWindow = null
var modal: Control = null
var ctl: ControlUI = null        ## 1.19: плашка «Под управлением» и меню «Сделать сейчас»
var crisis_bar: PanelContainer = null  ## 1.20: красная плашка под верхней панелью — беда, которую надо решать
var _crisis_l: Label
var _crisis_target := ""
var fix_box: Control = null      ## 1.20: окошко «Как исправить»
var worker_pop: WorkerPop = null ## 1.21: меню над человеком
var _t := 0.0


func setup(game: GameMain) -> void:
	g = game
	sim = game.sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.build()
	_build_top()
	_build_bottom()
	_build_sub()
	_build_hint()
	_build_overlays()
	toasts = VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	toasts.alignment = BoxContainer.ALIGNMENT_END
	_anchor(toasts, 1, 1, 1, 1, -458, -96, -60, -96)
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(toasts)
	crisis_bar = PanelContainer.new()
	crisis_bar.add_theme_stylebox_override("panel", UITheme.sbs(Color(0.42, 0.1, 0.08, 0.96), UITheme.BAD, 1, 8, 14, 7, 10, 0.5, 3))
	crisis_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	crisis_bar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	crisis_bar.visible = false
	_crisis_l = UITheme.label("", 14, Color("#fff1e6"), UITheme.f_semi)
	_crisis_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crisis_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crisis_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crisis_bar.add_child(_crisis_l)
	crisis_bar.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and _crisis_target != "":
			open_window(_crisis_target))
	add_child(crisis_bar)
	todo = TodoPanel.new()
	add_child(todo)
	_anchor(todo, 0, 0, 0, 0, 12, 60, 392, 60)
	todo.setup(self)
	info = InfoPanel.new()
	add_child(info)
	_anchor(info, 1, 0, 1, 0, -58, 64, -58, 64)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.focus_request.connect(func(c: Vector2i) -> void: g.cam.focus_cell(c))
	info.close_request.connect(func() -> void:
		g.tool.clear_selection()
		info.visible = false)
	ctl = ControlUI.new()
	add_child(ctl)
	ctl.setup(self)
	worker_pop = WorkerPop.new()
	add_child(worker_pop)
	worker_pop.setup(self)
	info.control_request.connect(func(w: Worker, on: bool) -> void:
		if on:
			ctl.take(w)
		else:
			ctl.release()
		info.show_worker(sim, w))
	on_speed_changed()
	_refresh_top()
	# 1.17: обучение — поверх затемнения (своя прослойка над интерфейсом)
	var tut_layer := CanvasLayer.new()
	tut_layer.layer = 12
	add_child(tut_layer)
	tutorial = TutorialPanel.new()
	tutorial.theme = theme
	tut_layer.add_child(tutorial)
	tutorial.setup(self)


func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _center(c: Control) -> void:
	_anchor(c, 0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


# ---------------------------------------------------------------- верхняя панель

func _build_top() -> void:
	var p := PanelContainer.new()
	var st := UITheme.sb(Color(0.075, 0.083, 0.094, 0.96), Color(0, 0, 0, 0), 0, 0, 10, 4)
	st.border_width_bottom = 1
	st.border_color = UITheme.LINE
	st.shadow_size = 10
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_offset = Vector2(0, 3)
	p.add_theme_stylebox_override("panel", st)
	_anchor(p, 0, 0, 1, 0, 0, 0, 0, 50)
	add_child(p)
	var h := UITheme.hbox(4)
	p.add_child(h)
	# 1.17: эмблема и название завода — щелчок открывает паспорт завода
	var cc := _chip("goals", "company", show_passport)
	company_l = UITheme.label("", 14, UITheme.TEXT, UITheme.f_semi)
	company_s = UITheme.label("", 11, UITheme.MUTED)
	cc.add_child(company_l)
	cc.add_child(company_s)
	var cic: Control = (_chips["company"] as Control).get_meta("icon")
	emblem_v = Emblem.View.new(Company.emblem_of(sim), 36.0)
	emblem_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem_v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cic.get_parent().add_child(emblem_v)
	cic.get_parent().move_child(emblem_v, cic.get_index())
	cic.queue_free()
	h.add_child(_chips["company"])
	# деньги
	var mc := _chip("money", "money", func() -> void: open_window("finance"))
	money_l = UITheme.label("", 18, UITheme.TEXT, UITheme.f_semi)
	money_d = UITheme.label("", 11, UITheme.MUTED)
	mc.add_child(money_l)
	mc.add_child(money_d)
	h.add_child(_chips["money"])
	# этап и звёзды
	var gc := _chip("goals", "goals", func() -> void: open_window("goals"))
	stage_l = UITheme.label("", 14, UITheme.TEXT, UITheme.f_semi)
	stars_l = UITheme.label("", 12, UITheme.ACCENT)
	gc.add_child(stage_l)
	gc.add_child(stars_l)
	h.add_child(_chips["goals"])
	goal_l = stage_l
	# репутация
	var rc := _chip("star", "rep", func() -> void:
		open_window("goals")
		if win:
			win.select_tab("rating"))
	rep_l = UITheme.label("", 14, UITheme.TEXT, UITheme.f_semi)
	rc.add_child(UITheme.label("репутация", 11, UITheme.MUTED))
	rc.add_child(rep_l)
	h.add_child(_chips["rep"])
	# люди
	var pc := _chip("staff", "people", func() -> void: open_window("people"))
	people_l = UITheme.label("", 14, UITheme.TEXT, UITheme.f_semi)
	people_s = UITheme.label("", 11, UITheme.MUTED)
	pc.add_child(people_l)
	pc.add_child(people_s)
	h.add_child(_chips["people"])
	h.add_child(UITheme.spacer())
	# дата, время, что сейчас по графику
	var dc := _chip("clock", "date", func() -> void: open_window("events"))
	date_l = UITheme.label("", 14, UITheme.TEXT, UITheme.f_semi)
	time_l = UITheme.label("", 11, UITheme.MUTED)
	dc.add_child(date_l)
	dc.add_child(time_l)
	# вместо значка часов — листок отрывного календаря
	var dic: Control = (_chips["date"] as Control).get_meta("icon")
	cal_sheet = FactoryUI.Sheet.new()
	cal_sheet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dic.get_parent().add_child(cal_sheet)
	dic.get_parent().move_child(cal_sheet, dic.get_index())
	dic.queue_free()
	h.add_child(_chips["date"])
	shift_l = time_l
	var wc := _chip("thermo", "weather", func() -> void: open_window("events"))
	weather_l = UITheme.label("", 15, UITheme.TEXT, UITheme.f_semi)
	wc.add_child(weather_l)
	weather_i = (_chips["weather"] as Control).get_meta("icon")
	weather_l.set_meta("box", _chips["weather"])
	h.add_child(_chips["weather"])
	var ec := _chip("power", "power", func() -> void: toggle_sub("power"))
	power_l = UITheme.label("", 13, UITheme.TEXT, UITheme.f_semi)
	power_bar = UITheme.bar(0, UITheme.GOOD, 86, 5)
	ec.add_child(power_l)
	ec.add_child(power_bar)
	h.add_child(_chips["power"])
	h.add_child(UITheme.spacer())
	# скорость — сегментированный переключатель
	var sp := UITheme.hbox(0)
	speed_box = sp
	var g2 := ButtonGroup.new()
	var tips := ["Пауза (Пробел)", "Обычная скорость ×1 (клавиша 1)", "Быстро ×2 (клавиша 2)", "Очень быстро ×4 (клавиша 3)"]
	for i in 4:
		var b := Button.new()
		b.icon = Tex.ui(["pause", "play1", "play2", "play3"][i])
		b.toggle_mode = true
		b.button_group = g2
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tips[i]
		b.custom_minimum_size = Vector2(40, 34)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 20)
		for stn in ["normal", "hover", "pressed", "hover_pressed"]:
			var base: StyleBoxFlat = (UITheme.theme.get_stylebox(stn, "Button") as StyleBoxFlat).duplicate()
			base.corner_radius_top_left = 7 if i == 0 else 0
			base.corner_radius_bottom_left = 7 if i == 0 else 0
			base.corner_radius_top_right = 7 if i == 3 else 0
			base.corner_radius_bottom_right = 7 if i == 3 else 0
			b.add_theme_stylebox_override(stn, base)
		var idx := i
		b.pressed.connect(func() -> void: g.set_speed(idx))
		sp.add_child(b)
		speed_btns.append(b)
	sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sp)
	fast_l = UITheme.label("", 12, UITheme.INFO, UITheme.f_semi)
	fast_l.custom_minimum_size = Vector2(70, 0)
	fast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(fast_l)
	var lb := UITheme.icon_button("log", "", func() -> void: open_window("log"), "Журнал событий")
	lb.custom_minimum_size = Vector2(40, 34)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lb)
	var mbtn := UITheme.icon_button("menu", "", show_pause_menu, "Меню игры (Esc)")
	mbtn.custom_minimum_size = Vector2(40, 34)
	mbtn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mbtn)


## Панель оверлеев (1.12): столбик значков у правого края — всегда на виду; легенда — карточкой слева внизу.
func _build_overlays() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sbs(Color(0.075, 0.083, 0.094, 0.92), UITheme.LINE, 1, 10, 4, 6, 12, 0.4, 3))
	_anchor(p, 1, 0.5, 1, 0.5, -50, -250, -8, -250)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(p)
	ov_panel = p
	var v := UITheme.vbox(3)
	p.add_child(v)
	var cap := UITheme.label("СЛОИ", 9, UITheme.DIM, UITheme.f_semi)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	for o: Array in OVERLAYS:
		var key := str(o[0])
		var b := Button.new()
		b.icon = Tex.ui("ov_" + key)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(36, 34)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s\n%s" % [str(o[1]), str(o[2])]
		var n := UITheme.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 7, 5, 4)
		var hv := UITheme.sb(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 7, 5, 4)
		var on := UITheme.sb(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.22), UITheme.ACCENT, 1, 7, 5, 4)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_color_override("icon_normal_color", Color("#b9b5aa"))
		b.add_theme_color_override("icon_hover_color", Color.WHITE)
		b.add_theme_color_override("icon_pressed_color", UITheme.ACCENT)
		b.add_theme_color_override("icon_hover_pressed_color", UITheme.ACCENT)
		b.pressed.connect(func() -> void: set_overlay(key))
		v.add_child(b)
		ov_btns[key] = b
	legend_panel = PanelContainer.new()
	legend_panel.add_theme_stylebox_override("panel", UITheme.sbs(Color(0.075, 0.083, 0.094, 0.94), UITheme.LINE, 1, 10, 12, 10, 12, 0.4, 3))
	_anchor(legend_panel, 0, 1, 0, 1, 12, -96, 312, -96)
	legend_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_panel.visible = false
	add_child(legend_panel)
	legend_box = UITheme.vbox(4)
	legend_panel.add_child(legend_box)


## Включить оверлей (тот же ещё раз — выключить).
func set_overlay(key: String) -> void:
	if key == "load" and not sim.office.active("pdo"):
		toast("Загрузку станков считает диспетчер ПДО: наймите диспетчера (Управление → Отделы).", Sim.LVL_INFO)
		key = ""
	forced_overlay = "" if forced_overlay == key else key
	_sync_overlays()


func _sync_overlays() -> void:
	var cur := g.overlay.mode
	for k in ov_btns.keys():
		(ov_btns[k] as Button).set_pressed_no_signal(k == cur)
	# легенда: название и пояснение активного оверлея
	var lg: Array = g.overlay.legend
	var sig := cur + "|" + str(lg)
	if sig == _legend_sig:
		return
	_legend_sig = sig
	UITheme.clear(legend_box)
	legend_panel.visible = cur != ""
	if cur == "":
		return
	var title := cur
	for o: Array in OVERLAYS:
		if str(o[0]) == cur:
			title = str(o[1])
	var hh := UITheme.hbox(8)
	var ic := TextureRect.new()
	ic.texture = Tex.ui("ov_" + cur)
	ic.custom_minimum_size = Vector2(20, 20)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.modulate = UITheme.ACCENT
	hh.add_child(ic)
	hh.add_child(UITheme.label(title, 14, UITheme.TEXT, UITheme.f_semi))
	legend_box.add_child(hh)
	for ln: Array in lg:
		var l := UITheme.label(str(ln[0]), 12, ln[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(276, 0)
		legend_box.add_child(l)
	if forced_overlay == cur:
		legend_box.add_child(UITheme.label("Щёлкните по значку ещё раз, чтобы выключить", 11, UITheme.DIM))


## «Чип» верхней панели: значок и две строки, наведение подсвечивает, щелчок — действие.
func _chip(icon: String, key: String, cb: Callable) -> VBoxContainer:
	var p := PanelContainer.new()
	var n := UITheme.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 9, 2)
	var hv := UITheme.sb(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 8, 9, 2)
	p.add_theme_stylebox_override("panel", n)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func() -> void: p.add_theme_stylebox_override("panel", hv))
	p.mouse_exited.connect(func() -> void: p.add_theme_stylebox_override("panel", n))
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Snd.play("ui_click", -8.0)
			cb.call())
	var h := UITheme.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := _ticon(icon)
	ic.custom_minimum_size = Vector2(22, 22)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = Color(1, 1, 1, 0.75)
	h.add_child(ic)
	p.set_meta("icon", ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_chips[key] = p
	return v


func _short_money(v: float) -> String:
	if v >= 1000000.0:
		return "%.2f млн" % (v / 1000000.0)
	return "%d тыс." % int(v / 1000.0)


func _ticon(n: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Tex.ui(n)
	r.custom_minimum_size = Vector2(28, 28)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


func _refresh_top() -> void:
	money_l.text = Defs.money_str(sim.money)
	money_l.add_theme_color_override("font_color", UITheme.BAD if sim.money < 0 else UITheme.TEXT)
	var today := 0.0
	var d0 := sim.day()
	for e: Dictionary in sim.ledger:
		if int(e["day"]) != d0:
			break
		today += float(e["v"])
	money_d.text = "сегодня %s%s" % ["+" if today > 0 else "", Defs.money_str(today)] if absf(today) >= 1.0 else "сегодня без движения"
	money_d.add_theme_color_override("font_color", UITheme.GOOD if today > 0 else (UITheme.BAD if today < 0 else UITheme.MUTED))
	var mtip := "Деньги на счёте. Последние операции:\n"
	for e2: Dictionary in sim.ledger.slice(0, 6):
		var v := float(e2["v"])
		mtip += "%s%s — %s\n" % ["+" if v > 0 else "", Defs.money_str(v), str(e2["text"])]
	(_chips["money"] as Control).tooltip_text = mtip + "Нажмите — «Финансы» (F)."
	rep_l.text = "%d из 100" % int(sim.reputation)
	rep_l.add_theme_color_override("font_color", UITheme.ramp(sim.reputation / 100.0))
	(_chips["rep"] as Control).tooltip_text = "Репутация %d из 100. Растёт от заказов, сданных вовремя, и падает от опозданий и срывов.\nОт неё зависят цены и число заказов." % int(sim.reputation)
	if sim.company_rev != _company_rev or company_s.text != ("ООО" if sim.progress.ooo else "Мастерская"):
		_company_rev = sim.company_rev
		emblem_v.set_spec(Company.emblem_of(sim))
		company_l.text = Company.name_of(sim)
		company_s.text = "ООО" if sim.progress.ooo else "Мастерская"
		(_chips["company"] as Control).tooltip_text = "%s — паспорт завода: название и эмблема (нажмите, чтобы изменить)." % Company.title(sim)
	var pg := sim.progress
	stage_l.text = pg.stage_name()
	stars_l.text = pg.stars_text()
	var gtip := "Этап %d из %d: «%s». Рейтинг завода: %d из 5 звёзд.\n" % [pg.stage, Progress.STAGE_COUNT, pg.stage_name(), pg.stars]
	if pg.stage < Progress.STAGE_COUNT:
		gtip += "Чтобы перейти на следующий этап:\n"
		for g2: Dictionary in pg.stage_goals():
			var gs: Array = pg.goal_state(g2)
			gtip += "%s %s — %s\n" % ["✓" if bool(gs[0]) else "•", str(g2.get("text", "")), str(gs[1])]
		if pg.choice_need() > 0:
			gtip += "И любые %d на выбор (%d выполнено):\n" % [pg.choice_need(), pg.choice_done()]
			for g3: Dictionary in pg.stage_choice().get("list", []):
				var gs3: Array = pg.goal_state(g3)
				gtip += "%s %s: %s — %s\n" % ["✓" if bool(gs3[0]) else "◦", str(g3.get("route", "")), str(g3.get("text", "")), str(gs3[1])]
	gtip += "Нажмите, чтобы открыть «Цели» (G)."
	(_chips["goals"] as Control).tooltip_text = gtip
	# люди
	var tot := 0
	var here := 0
	var ms := 0.0
	for w in sim.workers:
		tot += 1
		ms += w.mood
		if w.present:
			here += 1
	var avg := ms / maxf(1.0, float(tot))
	people_l.text = "%d / %d на заводе" % [here, tot] if tot > 0 else "Нет людей"
	people_s.text = "настроение %d — %s" % [int(avg), Mood.label(avg).to_lower()] if tot > 0 else "наймите во вкладке «Найм»"
	people_s.add_theme_color_override("font_color", Mood.color(avg) if tot > 0 else UITheme.MUTED)
	(_chips["people"] as Control).tooltip_text = "Сейчас на заводе %d из %d. Среднее настроение %d.\nНажмите — «Люди» (L)." % [here, tot, int(avg)]
	date_l.text = sim.season.short_date()
	if cal_sheet:
		var dd := sim.season.dom()
		var mm: String = ["ЯНВ", "ФЕВ", "МАРТ", "АПР", "МАЙ", "ИЮНЬ", "ИЮЛЬ", "АВГ", "СЕНТ", "ОКТ", "НОЯБ", "ДЕК"][sim.season.month()]
		var hol := not sim.is_workday()
		if dd != cal_sheet.day or mm != cal_sheet.month or hol != cal_sheet.holiday:
			cal_sheet.day = dd
			cal_sheet.month = mm
			cal_sheet.holiday = hol
			cal_sheet.queue_redraw()
	var t := sim.tod()
	var s := ""
	var scol := UITheme.MUTED
	if not sim.is_workday():
		s = "выходной"
	elif t < Defs.b("shift_start"):
		s = "до смены"
	elif t < Defs.b("shift_end"):
		scol = UITheme.GOOD
		match sim.crew.shift_slot_now(0):
			"lunch":
				s = "обед"
				scol = UITheme.WARN
			"break":
				s = "перерыв на чай"
				scol = UITheme.INFO
			"meet":
				s = "планёрка"
				scol = UITheme.INFO
			"clean":
				s = "уборка, сдача смены"
				scol = UITheme.INFO
			_:
				s = "идёт смена"
	else:
		s = "смена окончена"
	time_l.text = "%s · %s" % [sim.time_str(), s]
	time_l.add_theme_color_override("font_color", scol)
	if g.menu_paused or g.speed == 0:
		fast_l.text = "ПАУЗА"
		fast_l.add_theme_color_override("font_color", UITheme.ACCENT)
	elif g.fast:
		fast_l.text = "ускорено"
		fast_l.tooltip_text = "На заводе никого — ночь и выходные проматываются быстро"
		fast_l.add_theme_color_override("font_color", UITheme.INFO)
	else:
		fast_l.text = ""
	var pw := sim.power
	var cap := pw.capacity_total()
	if pw.any_tripped():
		power_l.text = "АВТОМАТ ВЫБИТ"
		power_l.add_theme_color_override("font_color", UITheme.BAD)
		power_bar.value = 100
		power_bar.add_theme_stylebox_override("fill", UITheme.sb(UITheme.BAD, UITheme.BAD, 0, 3, 0, 0))
	else:
		power_l.text = "%.1f / %d кВт" % [pw.total_load, int(cap)]
		var frac := pw.total_load / maxf(1.0, cap)
		power_bar.value = frac * 100.0
		var pc := UITheme.BAD if frac > 0.95 else (UITheme.WARN if frac > 0.8 else UITheme.GOOD)
		power_bar.add_theme_stylebox_override("fill", UITheme.sb(pc, pc, 0, 3, 0, 0))
		power_l.add_theme_color_override("font_color", UITheme.TEXT)
	(_chips["power"] as Control).tooltip_text = "Электросеть: нагрузка %.1f из %d кВт.\nНажмите — меню «Сети» (E)." % [pw.total_load, int(cap)]
	var offers := sim.orders.by_status(["offer"]).size() + sim.sales.by_state(["offer"]).size()
	order_badge.text = str(offers)
	order_badge.visible = offers > 0
	var se := sim.season
	var tt := int(round(se.outside_temp()))
	weather_l.text = "%+d °C" % tt
	weather_l.add_theme_color_override("font_color", Color("#9cd0f0") if tt <= -10 else (UITheme.WARN if tt >= 28 else UITheme.TEXT))
	weather_i.texture = Tex.ui("snow" if se.is_snowing() or tt < 0 else "thermo")
	var wtip := "%s, %s. На улице %+d °C." % [se.season_name(), se.long_date(), tt]
	if se.is_snowing():
		wtip += " Идёт снег."
	if se.ice:
		wtip += " Гололёд!"
	if se.heating_season():
		wtip += "\nОтопительный сезон: батарей %d." % se.radiators
		var cold := se.cold_rooms()
		if not cold.is_empty():
			wtip += " Холодно: " + ", ".join(PackedStringArray(cold.map(func(r: Rooms.Room) -> String: return r.title()))) + "."
	wtip += "\nНажмите — «События» (C)."
	(_chips["weather"] as Control).tooltip_text = wtip
	(_chips["date"] as Control).tooltip_text = "%s, %s. %s\nНажмите — календарь и проверки (C)." % [se.long_date(), sim.time_str(), sim.crew.sched_text(sim.crew.sched_str(0), 0).capitalize() if sim.is_workday() else "Выходной"]
	_refresh_crisis()
	var alerts := sim.story.letters.size() + (1 if sim.story.strike.get("active", false) else 0) + (1 if not sim.story.fires.is_empty() else 0) + sim.inspect.queue.size() + (1 if sim.paper.unread else 0)
	events_badge.text = str(alerts)
	events_badge.visible = alerts > 0
	paper_badge.visible = false
	if sim.story.strike.get("active", false) or not sim.story.fires.is_empty():
		events_badge.add_theme_stylebox_override("normal", UITheme.sb(UITheme.BAD, UITheme.BAD, 0, 8, 5, 0))
	else:
		events_badge.add_theme_stylebox_override("normal", UITheme.sb(UITheme.ACCENT_D, UITheme.ACCENT_D, 0, 8, 5, 0))
	var cands := sim.candidates.size()
	people_badge.visible = false
	if win and win.group == "people":
		win.set_badge("hire", cands)
	if win and win.group == "events":
		win.set_badge("paper", 1 if sim.paper.unread else 0)
		win.set_badge("now", sim.story.letters.size())
	if win and win.group == "orders":
		win.set_badge("contracts", sim.sales.by_state(["offer"]).size())


## 1.20: самая серьёзная беда — красной плашкой сверху. Нажатие открывает, где её решать.
func _refresh_crisis() -> void:
	var txt := ""
	var tg := ""
	var arr := sim.progress.arrears_total()
	if arr > 0.0:
		txt = "Не платим зарплату: долг %s. Люди уходят (%d из %d) — потом завод закроют. Нажмите, чтобы выплатить" % [Defs.money_str(arr), sim.crisis.arrears_quits.size(), Crisis.QUITS_TO_CLOSE]
		tg = "finance"
	elif not sim.crisis.tools_short.is_empty():
		txt = "Нет инструмента и денег на него: станки стоят, люди грозят уволиться. Нажмите — снабжение"
		tg = "supply"
	elif sim.money < 0.0 and sim.crisis.debt_days >= 1:
		txt = "Завод в долгах (%s): репутация падает, новых заказов не берём. Нажмите — финансы" % Defs.money_str(sim.money)
		tg = "finance"
	crisis_bar.visible = txt != "" and not sim.crisis.is_over()
	if crisis_bar.visible:
		# между «Что делать» слева и панелью слоёв справа
		var vw := get_viewport_rect().size.x
		var left := 404.0
		var w := minf(640.0, vw - left - 80.0)
		_crisis_l.text = txt
		_crisis_l.custom_minimum_size = Vector2(w - 28.0, 0)
		crisis_bar.size = Vector2(w, 0)
		crisis_bar.reset_size()
		crisis_bar.position = Vector2(left + (vw - left - 70.0 - w) * 0.5, 60.0)
	_crisis_target = tg


func on_speed_changed() -> void:
	for i in speed_btns.size():
		speed_btns[i].set_pressed_no_signal(i == g.speed)


# ---------------------------------------------------------------- нижняя панель

func _build_bottom() -> void:
	var p := PanelContainer.new()
	var st := UITheme.sbs(Color(0.075, 0.083, 0.094, 0.96), UITheme.LINE, 1, 14, 10, 6, 16, 0.5, 4)
	p.add_theme_stylebox_override("panel", st)
	_anchor(p, 0.5, 1, 0.5, 1, 0, -76, 0, -8)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(p)
	var dv := UITheme.vbox(5)
	p.add_child(dv)
	# жёлто-чёрная полоса «осторожно» — как на кромке станка
	var hz := FactoryUI.Hazard.new()
	hz.custom_minimum_size = Vector2(0, 3)
	hz.alpha = 0.55
	dv.add_child(hz)
	var h := UITheme.hbox(2)
	dv.add_child(h)
	_bbtn(h, "build", "build", "Стройка", "Полы, стены, окна, двери, ворота (B)", func() -> void: toggle_sub("build"))
	_bbtn(h, "objects", "objects", "Объекты", "Станки, стеллажи, бытовка (O)", func() -> void: toggle_sub("objects"))
	_bbtn(h, "rooms", "rooms", "Зоны", "Зоны: цех, склад, бытовка, столовая, кабинеты… Рисуются клетками внутри помещений (R)", func() -> void: open_rooms())
	_bbtn(h, "plan", "plan", "План", "Планировка: нарисуйте будущий завод на кальке — стены, полы, зоны, станки. Бесплатно, рабочие план не трогают. Потом «Утвердить план» (V)", toggle_plan)
	_bbtn(h, "power", "power", "Сети", "Электричество, свет, водопровод, вентиляция, сжатый воздух (E)", func() -> void: toggle_sub("power"))
	_bbtn(h, "demolish", "demolish", "Снос", "Снести стены, полы, объекты (X)", func() -> void: set_tool("demolish"))
	_bbtn(h, "cancel", "cancel", "Отмена", "Отменить чертежи — деньги вернутся", func() -> void: set_tool("cancel"))
	h.add_child(_dock_sep())
	var ob := _bbtn(h, "orders", "orders", "Заказы", "Заказы в работе, рынок, контракты, план ПДО", func() -> void: open_window("orders"))
	order_badge = UITheme.badge("0", UITheme.BAD)
	order_badge.position = Vector2(48, 2)
	ob.add_child(order_badge)
	_bbtn(h, "prod", "shop", "Производство", "Станки и ППР, металл и расходники, склад оборудования (P)", func() -> void: open_window("prod"))
	var pb := _bbtn(h, "people", "staff", "Люди", "Сотрудники, найм, обучение, охрана труда, бригады, график, профсоюз (L)", func() -> void: open_window("people"))
	people_badge = UITheme.badge("", UITheme.INFO)
	people_badge.visible = false
	pb.add_child(people_badge)
	_bbtn(h, "finance", "finance", "Финансы", "Сводка, отчёты по неделям, кредиты, гранты (F)", func() -> void: open_window("finance"))
	_bbtn(h, "office", "office", "Управление", "ИТР-отделы, политики и разработки техотдела (M)", func() -> void: open_window("office"))
	h.add_child(_dock_sep())
	_bbtn(h, "goals", "goals", "Цели", "Этап роста завода, рейтинг в звёздах, цели сценария, достижения (G)", func() -> void: open_window("goals"))
	var eb := _bbtn(h, "events", "calendar", "События", "Письма, проверки, календарь, многотиражка, журнал (C)", func() -> void: open_window("events"))
	events_badge = UITheme.badge("0", UITheme.ACCENT_D)
	events_badge.position = Vector2(48, 2)
	eb.add_child(events_badge)
	paper_badge = UITheme.badge("!", UITheme.INFO)
	paper_badge.visible = false
	_bbtn(h, "town", "town", "Город", "Общежитие, столовая и медпункт, детсад и ДК, заводское радио, кот (H)", func() -> void: open_window("town"))


func _dock_sep() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(17, 0)
	var line := ColorRect.new()
	line.color = UITheme.LINE2
	line.position = Vector2(8, 10)
	line.size = Vector2(1, 40)
	c.add_child(line)
	return c


func _bbtn(parent: Control, key: String, icon: String, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = Tex.ui(icon)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 24)
	b.add_theme_constant_override("h_separation", 2)
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(76, 60)
	var n := UITheme.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 9, 6, 5)
	var hv := UITheme.sb(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 9, 6, 5)
	var on := UITheme.sb(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.18), Color(0, 0, 0, 0), 0, 9, 6, 5)
	on.border_width_bottom = 2
	on.border_color = UITheme.ACCENT
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_color", UITheme.MUTED)
	b.add_theme_color_override("font_hover_color", UITheme.TEXT)
	b.add_theme_color_override("font_pressed_color", UITheme.ACCENT)
	b.add_theme_color_override("font_hover_pressed_color", UITheme.ACCENT)
	b.add_theme_color_override("icon_normal_color", Color("#c9c5ba"))
	b.add_theme_color_override("icon_hover_color", Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", UITheme.ACCENT)
	b.add_theme_color_override("icon_hover_pressed_color", UITheme.ACCENT)
	b.toggle_mode = true
	b.pressed.connect(func() -> void:
		b.set_pressed_no_signal(false)
		Snd.play("ui_click", -6.0)
		cb.call()
		_sync_bottom())
	parent.add_child(b)
	bottom_btns[key] = b
	return b


func _sync_bottom() -> void:
	var m := g.tool.mode
	for k in bottom_btns.keys():
		var on := false
		match k:
			"build":
				on = sub_kind == "build" or ["floor", "wall", "door", "window", "gate", "zone", "template", "roomframe"].has(m)
			"objects":
				on = sub_kind == "objects" or m == "object"
			"demolish", "cancel":
				on = m == k
			"plan":
				on = g.tool.plan_mode
			"rooms":
				on = m == "room" or sub_kind == "rooms"
			"power":
				on = sub_kind == "power" or m in ["cable", "uncable", "pipe", "unpipe", "duct", "unduct", "air", "unair"]
			_:
				on = win != null and win.group == k
		(bottom_btns[k] as Button).set_pressed_no_signal(on)


# ---------------------------------------------------------------- подменю стройки

func _build_sub() -> void:
	sub_panel = PanelContainer.new()
	sub_panel.add_theme_stylebox_override("panel", UITheme.sbs(Color(0.075, 0.083, 0.094, 0.97), UITheme.LINE, 1, 10, 8, 6, 14, 0.5, 4))
	_anchor(sub_panel, 0.5, 1, 0.5, 1, 0, -96, 0, -96)
	sub_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sub_panel.visible = false
	add_child(sub_panel)
	sub_root = UITheme.vbox(4)
	sub_panel.add_child(sub_root)


## Открыть каталог помещений сразу с выбранным типом (из закрытого раздела окна).
func open_rooms_type(type: String) -> void:
	BuildMenu.zone_cat = str(Defs.rooms.get(type, {}).get("group", BuildMenu.zone_cat))
	if sub_kind != "rooms":
		open_rooms()
	g.tool.set_mode("room", type)
	_fill_sub()
	toast("Зона «%s»: протяните прямоугольник по полу помещения или щёлкните по помещению, чтобы залить его целиком." % str(Defs.rooms.get(type, {}).get("name", type)), Sim.LVL_INFO)


## Каталог помещений: все типы с требованиями видны заранее, ещё до постройки.
## Выбрали тип — щелчок по помещению сразу назначает его; без выбора — открывается карточка.
func open_rooms() -> void:
	if sub_kind == "rooms":
		close_sub()
		g.tool.set_mode("select")
		return
	sub_kind = "rooms"
	g.tool.set_mode("room")
	_fill_sub()
	sub_panel.visible = true
	_sync_bottom()


func toggle_sub(kind: String) -> void:
	if sub_kind == kind:
		close_sub()
		g.tool.set_mode("select")
		return
	sub_kind = kind
	_fill_sub()
	sub_panel.visible = true
	_sync_bottom()


func close_sub() -> void:
	sub_kind = ""
	sub_panel.visible = false
	_sync_bottom()


func _fill_sub() -> void:
	UITheme.clear(sub_root)
	# сбрасываем размер, чтобы панель ужалась под новое содержимое
	sub_panel.offset_top = sub_panel.offset_bottom
	sub_panel.offset_left = 0
	sub_panel.offset_right = 0
	BuildMenu.fill(self)


## Подпись карточки: длинное слово («Ленточнопильный») — кеглем помельче, чтобы не рвалось посередине.
static func _card_font(title: String, width: float) -> int:
	var f: Font = UITheme.f_reg
	if f == null:
		return 11
	for word in title.split(" "):
		if f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > width:
			return 10 if f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= width else 9
	return 11


# ---------------------------------------------------------------- 1.17: режим планировки

var plan_panel: PanelContainer = null
var _plan_sig := ""


func toggle_plan() -> void:
	var t := g.tool
	t.plan_mode = not t.plan_mode
	if t.plan_mode:
		PlanLayer.faded = false
		if sub_kind == "" or sub_kind == "power":
			toggle_sub("build")
		else:
			_fill_sub()
		toast("Планировка: рисуйте стены, полы, зоны и станки — это калька, бесплатно. Готово — «Утвердить план».", Sim.LVL_INFO, 5.0)
	else:
		if sub_kind != "":
			_fill_sub()
	t.queue_redraw()
	_plan_sig = ""
	_refresh_plan_panel()
	_sync_bottom()


func _refresh_plan_panel() -> void:
	var on := g.tool.plan_mode
	if plan_panel == null:
		plan_panel = PanelContainer.new()
		plan_panel.add_theme_stylebox_override("panel", UITheme.sbs(Color(0.07, 0.12, 0.2, 0.95), Color(0.36, 0.62, 1.0, 0.9), 1, 10, 14, 8, 12, 0.45, 3))
		_anchor(plan_panel, 0.5, 0, 0.5, 0, 0, 58, 0, 58)
		plan_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		add_child(plan_panel)
	plan_panel.visible = on
	if not on:
		return
	var pl := sim.plan
	var cn := pl.counts()
	var cost := pl.cost()
	var sig := "%s|%d|%s" % [str(cn), int(cost), PlanLayer.faded]
	if sig == _plan_sig:
		return
	_plan_sig = sig
	UITheme.clear(plan_panel)
	plan_panel.offset_left = 0
	plan_panel.offset_right = 0
	var h := UITheme.hbox(12)
	plan_panel.add_child(h)
	var ic := _ticon("plan")
	ic.custom_minimum_size = Vector2(26, 26)
	ic.modulate = Color(0.62, 0.8, 1.0)
	h.add_child(ic)
	var v := UITheme.vbox(0)
	v.add_child(UITheme.label("ПЛАНИРОВКА — ничего не строится и не стоит денег", 14, Color(0.78, 0.88, 1.0), UITheme.f_semi))
	var parts: Array[String] = []
	if int(cn["walls"]) > 0:
		parts.append("стен и проёмов %d" % int(cn["walls"]))
	if int(cn["floors"]) > 0:
		parts.append("пола %d кл." % int(cn["floors"]))
	if int(cn["zones"]) > 0:
		parts.append("зон %d" % int(cn["zones"]))
	if int(cn["objs"]) > 0:
		parts.append("объектов %d" % int(cn["objs"]))
	var txt := ("На плане: " + ", ".join(parts) + " · по смете ≈ " + Defs.money_str(cost)) if not parts.is_empty() else "Выберите стену, пол, зону или станок в меню снизу и рисуйте. Снос стирает план."
	v.add_child(UITheme.label(txt, 12, UITheme.MUTED))
	h.add_child(v)
	var ab := UITheme.primary("Утвердить план", func() -> void:
		var res := sim.plan.approve()
		var msg := "План утверждён: пол %d кл., стены %d, объектов заказано %d." % [int(res["floors"]), int(res["walls"]), int(res["objs"])]
		if int(res["wait"]) > 0:
			msg += " Ещё %d объектов ждут пола и стен — поставим сами, когда достроят." % int(res["wait"])
		if bool(res["broke"]):
			msg += " Денег хватило не на всё — остаток остался на плане."
		toast(msg, Sim.LVL_WARN if bool(res["broke"]) else Sim.LVL_GOOD, 6.0)
		_plan_sig = ""
		_refresh_plan_panel(), "Превратить план в чертежи: рабочие начнут строить, деньги спишутся по смете")
	ab.disabled = sim.plan.pending_empty()
	h.add_child(ab)
	h.add_child(UITheme.button("Стереть план", func() -> void:
		sim.plan.clear()
		_plan_sig = ""
		_refresh_plan_panel(), "Убрать всё, что нарисовано на плане"))
	h.add_child(UITheme.button("Готово", toggle_plan, "Выйти из планировки — план останется бледной калькой поверх завода (V)"))


func set_tool(mode: String) -> void:
	close_sub()
	if g.tool.mode == mode:
		g.tool.set_mode("select")
	else:
		g.tool.set_mode(mode)
	_sync_bottom()


func on_mode_changed() -> void:
	_sync_bottom()


# ---------------------------------------------------------------- подсказка инструмента

func _build_hint() -> void:
	hint_panel = PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.08, 0.09, 0.1, 0.9), UITheme.LINE, 1, 6, 12, 6))
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(hint_panel, 0.5, 1, 0.5, 1, 0, -96, 0, -96)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_l = UITheme.label("", 14)
	hint_panel.add_child(hint_l)
	hint_panel.visible = false
	add_child(hint_panel)


func _refresh_hint() -> void:
	var t := g.tool
	if t.mode == "select":
		hint_panel.visible = false
		return
	var txt := ""
	match t.mode:
		"floor":
			txt = "%s: зажмите ЛКМ и протяните прямоугольник" % str(Defs.floor_by_id[int(t.arg)]["name"])
		"wall":
			txt = "Стены: протяните контур будущего помещения"
		"door", "window", "gate":
			txt = "%s: протяните вдоль существующей стены или чертежа" % str(Defs.wall_by_id[int(t.arg)]["name"])
		"object":
			txt = "%s: щёлкните, чтобы поставить" % str(Defs.objects[str(t.arg)]["name"])
			if Thing.rotations(str(t.arg)) > 1:
				txt += " · R — повернуть"
		"template":
			var td: Dictionary = Templates.def(str(t.arg))
			txt = "%s: щёлкните — помещение встанет центром под курсором (внутри %d×%d)" % [str(td.get("name", "")), Templates.inner(str(t.arg)).x, Templates.inner(str(t.arg)).y]
		"demolish":
			txt = "Снос: выделите область. Объекты упакуют в ящики и унесут на склад оборудования"
		"cancel":
			txt = "Отмена чертежей: выделите область. Деньги вернутся полностью"
		"room":
			if t.arg is String and str(t.arg) == "_erase":
				txt = "Стереть разметку: протяните прямоугольник или щёлкните по зоне"
			elif t.arg is String and str(t.arg) != "":
				txt = "Зона «%s»: протяните прямоугольник или щёлкните по помещению — зальёт целиком" % str(Defs.rooms.get(str(t.arg), {}).get("name", ""))
			else:
				txt = "Зоны: выберите зону в меню или щёлкните по помещению — откроется его карточка"
		"cable":
			txt = "Кабель: протяните от подстанции прямо в клетку розетки станка или в помещение"
		"uncable":
			txt = "Снять кабель: выделите область"
		"pipe":
			txt = "Труба: протяните от насоса к туалету или раковине"
		"unpipe":
			txt = "Снять трубу: выделите область"
		"duct":
			txt = "Воздуховод: протяните от вентилятора по помещениям и к зонтам"
		"unduct":
			txt = "Снять воздуховод: выделите область"
		"air":
			txt = "Пневмомагистраль: протяните от компрессора к покрасочной камере и сборочным столам"
		"unair":
			txt = "Снять пневмомагистраль: выделите область"
		"zone":
			txt = ["Убрать зону на улице: выделите область", "Зона разгрузки: протяните прямоугольник у ворот", "Зона отгрузки: протяните прямоугольник у ворот"][clampi(int(t.arg), 0, 2)]
	if t.plan_mode:
		txt = "ПЛАН · " + txt
	elif t.preview_cost > 0.0:
		txt += " · " + Defs.money_str(t.preview_cost)
	txt += " · ПКМ или Esc — выйти"
	if hint_l.text != txt:
		hint_l.text = txt
		hint_panel.offset_left = 0
		hint_panel.offset_right = 0
	hint_panel.offset_bottom = -96.0 - (sub_panel.size.y + 8.0 if sub_panel.visible else 0.0)
	hint_panel.offset_top = hint_panel.offset_bottom
	hint_panel.visible = true


# ---------------------------------------------------------------- обновление

func _process(delta: float) -> void:
	if g == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		_refresh_top()
		_place_tutorial()
	_refresh_hint()
	if plan_panel and plan_panel.visible:
		_refresh_plan_panel()
	# слой, выбранный игроком на панели справа, главнее подсказки от открытого меню
	var om := ""
	if forced_overlay != "":
		om = forced_overlay
	elif g.tool.mode == "room":
		om = "rooms"
	elif g.tool.mode in ["pipe", "unpipe", "duct", "unduct", "air", "unair", "cable", "uncable"] or sub_kind == "power":
		om = "nets"
	elif g.tool.mode == "object" and str(Defs.objects.get(str(g.tool.arg), {}).get("cat", "")) in ["Электрика", "Освещение", "Водопровод"]:
		om = "nets"
	elif g.tool.mode == "object" and (str(Defs.objects.get(str(g.tool.arg), {}).get("net", "")) in ["vent", "air"] or bool(Defs.objects.get(str(g.tool.arg), {}).get("water", false))):
		om = "nets"
	elif g.tool.mode == "object" and str(g.tool.arg) == "radiator":
		om = "temp"
	g.overlay.set_mode(om)
	_sync_overlays()
	_check_letters()


func on_room_clicked(room_id: int) -> void:
	if room_id < 0:
		info.visible = false
		toast("Здесь нет помещения: нужен пол, обнесённый стенами с дверью.", Sim.LVL_INFO, 4.0)
		return
	info.show_room(sim, room_id)


# ---------------------------------------------------------------- уведомления

func on_notified(text: String, level: int, cell: Vector2i) -> void:
	toast(text, level, 9.0, cell, true)
	Snd.play(["n_info", "n_good", "n_warn", "n_bad"][clampi(level, 0, 3)], -4.0 if level == 0 else -1.0, 0.0, 0.7)


func toast(text: String, level: int, life: float = 7.0, cell: Vector2i = Vector2i(-1, -1), link: bool = false) -> void:
	var col: Color = LEVEL_COLORS[clampi(level, 0, 3)]
	var p := PanelContainer.new()
	var st := UITheme.sbs(Color(0.075, 0.083, 0.094, 0.95), col, 0, 9, 12, 8, 10, 0.4, 3)
	st.border_width_left = 3
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var th := UITheme.hbox(10)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(th)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(l)
	if cell.x >= 0:
		p.tooltip_text = "Нажмите, чтобы показать место"
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var target := Links.target(text, "events:log" if link else "") if cell.x < 0 else ""
	if target != "":
		p.tooltip_text = "Нажмите, чтобы открыть окно"
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			if cell.x >= 0:
				g.cam.focus_cell(cell)
			if target != "":
				open_window(target)
			p.queue_free())
	toasts.add_child(p)
	while toasts.get_child_count() > 6:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(life)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# ---------------------------------------------------------------- окна

func open_window(kind: String) -> void:
	var rs := GameWindow.resolve(kind)
	if kind.contains(":"):
		rs = Array(kind.split(":"))
	var grp := str(rs[0])
	var sec := str(rs[1])
	if win and win.group == grp:
		if sec == "" or sec == win.sec:
			close_window()
		else:
			win.select_tab(sec)
		return
	close_window()
	close_sub()
	win = GameWindow.new()
	add_child(win)
	var vh := get_viewport_rect().size.y
	var avail := vh - 50.0 - 92.0 - 20.0
	win.setup(sim, self, grp, sec)
	win.custom_minimum_size.y = clampf(avail, 520.0, 780.0)
	win.size = Vector2(win.custom_minimum_size.x, win.custom_minimum_size.y)
	win.set_anchors_preset(Control.PRESET_CENTER_TOP)
	win.position = Vector2((get_viewport_rect().size.x - win.size.x) * 0.5, 50.0 + 10.0 + (avail - win.size.y) * 0.5)
	if grp == "events":
		sim.paper.unread = false if win.sec == "paper" else sim.paper.unread
	win.closed.connect(close_window)
	if todo:
		todo.visible = false
	Snd.play("ui_open", -8.0)
	_sync_bottom()


## Обучение — слева посередине, но всегда ниже списка задач (они не должны налезать друг на друга).
func _place_tutorial() -> void:
	pass   # 1.17: обучение ставит себя само (TutorialPanel._place)


func close_window() -> void:
	if win:
		Snd.play("ui_close", -10.0)
		win.queue_free()
		win = null
	if todo:
		todo.visible = true
	_sync_bottom()


func select_worker(id: int) -> void:
	g.focus_worker(id)


func select_thing(id: int) -> void:
	g.focus_thing(id)


# ---------------------------------------------------------------- письма-события

## Новое событие с выбором — показать окно (и поставить паузу, если так в настройках).
func _check_letters() -> void:
	if letter_box != null:
		if sim.story.get_letter(letter_id).is_empty():
			_close_letter()
		return
	if modal != null or sim.story.letters.is_empty():
		return
	show_letter(sim.story.letters[0])


## Письмо-событие с выбором — оформлено как служебная записка: бланк, номер, варианты решения карточками.
func show_letter(l: Dictionary) -> void:
	_close_letter()
	letter_id = int(l["id"])
	Snd.play("letter", -3.0)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	letter_box = dim
	if bool(Game.settings.get("pause_on_event", true)):
		g.menu_paused = true
	var lvl := int(l.get("level", 0))
	var col: Color = LEVEL_COLORS[clampi(lvl, 0, 3)]
	var choices: Array = l["choices"]
	var p := PanelContainer.new()
	var st := UITheme.sbs(UITheme.BG, UITheme.LINE2, 1, 12, 24, 18, 24, 0.6, 8)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(600, 0)
	dim.add_child(p)
	_center(p)
	var v := UITheme.vbox(10)
	p.add_child(v)
	# бланк
	var form := UITheme.hbox(8)
	form.add_child(UITheme.label("СЛУЖЕБНАЯ ЗАПИСКА", 11, InfoPanel.FORM_RED, UITheme.f_caps))
	form.add_child(UITheme.spacer())
	form.add_child(UITheme.label("№ %03d · %s · %s" % [letter_id % 1000, sim.date_str(), sim.time_str()], 11, UITheme.MUTED, UITheme.f_caps))
	v.add_child(form)
	v.add_child(InfoPanel.form_rule())
	var head := UITheme.hbox(12)
	var icp := PanelContainer.new()
	icp.add_theme_stylebox_override("panel", UITheme.sb(Color(col.r, col.g, col.b, 0.16), Color(col.r, col.g, col.b, 0.5), 1, 10, 8, 8))
	var ic := TextureRect.new()
	ic.texture = Tex.ui(str(l.get("icon", "letter")))
	if ic.texture == null:
		ic.texture = Tex.ui("letter")
	ic.custom_minimum_size = Vector2(32, 32)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = col.lightened(0.25)
	icp.add_child(ic)
	icp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icp)
	var tl := UITheme.title(str(l["title"]), 22)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tl)
	if choices.size() > 1:
		var sc := Control.new()
		sc.custom_minimum_size = Vector2(Stamp.fit_w("К РЕШЕНИЮ", 13), 40)
		var stp := Stamp.box_stamp(PackedStringArray(["К РЕШЕНИЮ"]), Color("#e0574a"), Stamp.fit_w("К РЕШЕНИЮ", 13), 30.0, 6.0)
		sc.add_child(stp)
		head.add_child(sc)
	v.add_child(head)
	var txt := UITheme.label(str(l["text"]), 15)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(552, 0)
	v.add_child(txt)
	var d: Dictionary = l.get("data", {})
	var cell := Vector2i(int(d.get("cx", -1)), int(d.get("cy", -1)))
	if choices.size() > 1:
		v.add_child(UITheme.caption("Ваше решение"))
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var hint := str(ch.get("hint", ""))
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46 if hint != "" else 40)
		b.add_theme_stylebox_override("normal", UITheme.sb(UITheme.BG2, UITheme.LINE2, 1, 8, 14, 6))
		b.add_theme_stylebox_override("hover", UITheme.sb(UITheme.BG3, UITheme.ACCENT, 1, 8, 14, 6))
		b.add_theme_stylebox_override("pressed", UITheme.sb(UITheme.BG3, UITheme.ACCENT, 2, 8, 14, 6))
		var bv := UITheme.vbox(0)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bv.offset_left = 14
		bv.offset_right = -14
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		var bh := UITheme.hbox(8)
		bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var num := UITheme.label("%d" % (i + 1), 12, UITheme.ACCENT, UITheme.f_semi)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bh.add_child(num)
		var bt := UITheme.label(str(ch["text"]), 15, UITheme.TEXT, UITheme.f_med)
		bt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bt.clip_text = true
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(bt)
		if choices.size() > 1 and i == int(l["def"]):
			var dl := UITheme.chip("по умолчанию", UITheme.MUTED, "Будет выбрано само, если не решить вовремя")
			dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bh.add_child(dl)
		bv.add_child(bh)
		if hint != "":
			var hl := UITheme.label(hint, 12, UITheme.MUTED)
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hl.clip_text = true
			hl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			hl.custom_minimum_size = Vector2(500, 0)
			bv.add_child(hl)
			b.tooltip_text = hint
		b.add_child(bv)
		var idx := i
		var lid := letter_id
		var open := str(ch.get("open", ""))
		b.pressed.connect(func() -> void:
			sim.story.resolve(lid, idx)
			_close_letter()
			if open != "":
				open_window(open)
				if open == "orders" and win and win.kind == "orders":
					win.select_tab("contracts"))
		v.add_child(b)
	var foot := UITheme.hbox(10)
	if cell.x >= 0:
		var lid2 := letter_id
		var only_info := choices.size() == 1
		foot.add_child(UITheme.ghost("◎ Показать на карте", func() -> void:
			g.cam.focus_cell(cell)
			if only_info:
				sim.story.resolve(lid2, 0)
			_close_letter()))
	foot.add_child(UITheme.spacer())
	var rest := sim.story.letters.size() - 1
	if rest > 0:
		foot.add_child(UITheme.chip("ещё ждут решения: %d" % rest, UITheme.WARN))
	v.add_child(foot)
	if choices.size() > 1:
		v.add_child(UITheme.label("Если не решить за %d игровых часов, будет выбран вариант «%s»." % [int(Defs.ev("decision_hours")), str(choices[int(l["def"])]["text"])], 12, UITheme.DIM))


func _close_letter() -> void:
	if letter_box:
		letter_box.queue_free()
		letter_box = null
		letter_id = -1
		if modal == null:
			g.menu_paused = false


# ---------------------------------------------------------------- модальные окна

func modal_open() -> bool:
	return modal != null


func close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null
	g.menu_paused = false


func _open_modal(w: float = 420.0) -> VBoxContainer:
	close_modal()
	close_window()
	g.menu_paused = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	modal = dim
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sbs(UITheme.BG, UITheme.LINE2, 1, 12, 24, 20, 24, 0.6, 8))
	p.custom_minimum_size = Vector2(w, 0)
	dim.add_child(p)
	_center(p)
	var v := UITheme.vbox(10)
	p.add_child(v)
	return v


## Рабочий чертёж детали к заказу (по ЕСКД). Окно заказов закрывается, после — открывается снова.
func show_drawing(o: Dictionary) -> void:
	var v := _open_modal(880)
	var head := UITheme.hbox(10)
	head.add_child(UITheme.title("Чертёж: %s" % Defs.product_name(str(o.get("product", ""))), 20))
	head.add_child(UITheme.spacer())
	head.add_child(UITheme.button("×", func() -> void:
		close_modal()
		open_window("orders")))
	v.add_child(head)
	var dv := DrawingView.new()
	dv.setup(sim, o)
	v.add_child(dv)
	v.add_child(UITheme.label("Размеры у каждого заказа свои. Чертёж — для интереса: по нему ничего настраивать не нужно.", 12, UITheme.MUTED))


func _menu_button(v: Control, text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, cb)
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 16)
	v.add_child(b)
	return b


func show_pause_menu() -> void:
	var v := _open_modal(380)
	var pl := FactoryUI.plate("Пауза", "pause", 18)
	pl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pl)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	var cont := _menu_button(v, "Продолжить", close_modal)
	cont.add_theme_stylebox_override("normal", UITheme.sb(UITheme.ACCENT, UITheme.ACCENT, 1, UITheme.RADIUS - 1, 11, 5))
	cont.add_theme_stylebox_override("hover", UITheme.sb(Color("#ecb84c"), Color("#ecb84c"), 1, UITheme.RADIUS - 1, 11, 5))
	cont.add_theme_color_override("font_color", UITheme.ACCENT_T)
	cont.add_theme_color_override("font_hover_color", UITheme.ACCENT_T)
	cont.add_theme_font_override("font", UITheme.f_semi)
	_menu_button(v, "Сохранить игру", show_save_dialog)
	_menu_button(v, "Загрузить игру", show_load_dialog)
	_menu_button(v, "Настройки", show_settings)
	_menu_button(v, "Как играть", func() -> void: show_help(false))
	v.add_child(HSeparator.new())
	_menu_button(v, "Выйти в главное меню", func() -> void:
		Game.autosave(sim)
		Game.to_menu())
	var q := _menu_button(v, "Выйти из игры", func() -> void:
		Game.autosave(sim)
		get_tree().quit())
	q.add_theme_color_override("font_color", UITheme.BAD)
	q.add_theme_color_override("font_hover_color", UITheme.BAD.lightened(0.2))
	var note := UITheme.label("При выходе игра сохраняется автоматически.", 12, UITheme.DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


## 1.17: неделя стройки — открыть производство раньше.
func confirm_start_early() -> void:
	var v := _open_modal(520)
	v.add_child(UITheme.title("Начать производство раньше?", 22))
	var ql := sim.progress.quiet_left()
	var lines: Array[String] = ["До конца недели стройки ещё %d %s. Если цех готов, можно начать раньше: отдел сбыта примет первые заявки уже сегодня." % [ql, Defs.plural(ql, "день", "дня", "дней")]]
	var miss: Array[String] = []
	if sim.things_of("machine").filter(func(m: Thing) -> bool: return m.built).is_empty():
		miss.append("нет ни одного станка")
	elif sim.things_of("machine").filter(func(m2: Thing) -> bool: return m2.built and sim.power.powered(m2)).is_empty():
		miss.append("станки без тока — протяните кабель от подстанции в их розетки")
	if sim.workers.filter(func(w: Worker) -> bool: return not w.visitor and w.prof != "builder").is_empty():
		miss.append("нет станочников — наймите в «Людях»")
	if sim.things_of("storage").is_empty():
		miss.append("нет стеллажа под металл")
	v.add_child(UITheme.para(lines[0], 14, UITheme.TEXT))
	if not miss.is_empty():
		v.add_child(UITheme.para("Пока что: " + "; ".join(miss) + ". Заказы будут ждать, пока это не исправите.", 13, UITheme.WARN))
	var bh := UITheme.hbox(10)
	bh.add_child(UITheme.spacer())
	bh.add_child(UITheme.button("Ещё построю", close_modal))
	bh.add_child(UITheme.primary("Начать производство", func() -> void:
		sim.progress.start_early()
		close_modal()))
	v.add_child(bh)


## 1.17: паспорт завода — название, эмблема и пара строк о заводе.
func show_passport() -> void:
	var v := _open_modal(900)
	var head := UITheme.hbox(10)
	head.add_child(UITheme.title("Паспорт завода", 22))
	head.add_child(UITheme.spacer())
	head.add_child(UITheme.button("×", close_modal))
	v.add_child(head)
	var pg := sim.progress
	var info_t := "%s · этап «%s» %s · в штате %d · основан %s" % [Company.title(sim), pg.stage_name(), pg.stars_text(), sim.workers.filter(func(w: Worker) -> bool: return not w.visitor).size(), sim.season.short_date(maxi(0, pg.start_day)) if pg.start_day >= 0 else "—"]
	v.add_child(UITheme.label(info_t, 13, UITheme.MUTED))
	var data := {"name": Company.name_of(sim), "emblem": Company.emblem_of(sim).duplicate()}
	var ed := EmblemEditor.new(data, sim.progress.ooo, sim.progress.profile)
	v.add_child(ed)
	var bh := UITheme.hbox(10)
	bh.add_child(UITheme.spacer())
	bh.add_child(UITheme.button("Отмена", close_modal))
	bh.add_child(UITheme.primary("Сохранить", func() -> void:
		var old := Company.name_of(sim)
		Company.set_data(sim, str(data.get("name", "")), data["emblem"])
		DisplayServer.window_set_title("Промзона — %s" % Company.title(sim))
		close_modal()
		if Company.name_of(sim) != old:
			sim.notify("Завод переименован: теперь он называется %s. Новая вывеска уже у ворот." % Company.title(sim), Sim.LVL_GOOD)
		else:
			toast("Эмблема обновлена.", Sim.LVL_GOOD, 2.5)))
	v.add_child(bh)


func show_save_dialog() -> void:
	var v := _open_modal(560)
	v.add_child(UITheme.title("Сохранить игру", 22))
	var h := UITheme.hbox(8)
	var le := LineEdit.new()
	le.placeholder_text = "Название сохранения"
	le.text = "%s, %s" % [sim.date_str(), Defs.money_str(sim.money)]
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(le)
	h.add_child(UITheme.button("Сохранить", func() -> void:
		var err := Game.save_sim(sim, Game.new_slot_name(), le.text.strip_edges())
		close_modal()
		toast("Игра сохранена." if err == "" else err, Sim.LVL_GOOD if err == "" else Sim.LVL_BAD, 3.0)))
	v.add_child(h)
	var saves := Game.list_saves()
	if not saves.is_empty():
		v.add_child(UITheme.label("Или перезаписать:", 14, UITheme.MUTED))
		var list := _save_list(saves, true)
		v.add_child(list)
	_menu_button(v, "Назад", show_pause_menu)


func show_load_dialog() -> void:
	var v := _open_modal(560)
	v.add_child(UITheme.title("Загрузить игру", 22))
	var saves := Game.list_saves()
	if saves.is_empty():
		v.add_child(UITheme.label("Сохранений пока нет.", 15, UITheme.MUTED))
	else:
		v.add_child(_save_list(saves, false))
	_menu_button(v, "Назад", show_game_over if sim.crisis.is_over() else show_pause_menu)


func _save_list(saves: Array, overwrite: bool) -> Control:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, mini(360, saves.size() * 64 + 8))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lv := UITheme.vbox(6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lv)
	for s: Dictionary in saves:
		var slot := str(s["slot"])
		var row := UITheme.panel(UITheme.BG2)
		var h := UITheme.hbox(10)
		row.add_child(h)
		var em: Variant = s.get("emblem", {})
		if em is Dictionary and not (em as Dictionary).is_empty():
			h.add_child(Emblem.View.new(em, 40.0))
		var info_v := UITheme.vbox(0)
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.add_child(UITheme.label(str(s.get("title", slot)) + ((" · " + str(s["company"])) if s.has("company") else ""), 15, UITheme.TEXT, UITheme.f_med))
		info_v.add_child(UITheme.label("Сохранено %s · в игре %s %s · %s" % [Game.pc_time(str(s.get("saved_at", ""))), str(s.get("date", "")), str(s.get("time", "")), Defs.money_str(float(s.get("money", 0)))], 12, UITheme.MUTED))
		h.add_child(info_v)
		if overwrite:
			h.add_child(UITheme.button("Перезаписать", func() -> void:
				var err := Game.save_sim(sim, slot, str(s.get("title", slot)))
				close_modal()
				toast("Игра сохранена." if err == "" else err, Sim.LVL_GOOD if err == "" else Sim.LVL_BAD, 3.0)))
		else:
			var lb := UITheme.button("Загрузить", func() -> void: Game.start_load(slot))
			lb.disabled = bool(s.get("broken", false))
			h.add_child(lb)
			h.add_child(UITheme.button("×", func() -> void:
				Game.delete_save(slot)
				show_load_dialog(), "Удалить сохранение"))
		lv.add_child(row)
	return sc


func show_settings() -> void:
	var v := _open_modal(560)
	v.add_child(UITheme.title("Настройки", 22))
	SettingsUI.build(v, func(key: String, val: bool) -> void:
		if key == "edge_scroll":
			g.cam.edge_scroll = val)
	_menu_button(v, "Назад", show_pause_menu)


func show_help(first_time: bool) -> void:
	var v := _open_modal(760)
	v.add_child(UITheme.title("Добро пожаловать в «Промзону»" if first_time else "Как играть", 24))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(716, 560)
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.fit_content = true
	txt.scroll_active = false
	txt.custom_minimum_size = Vector2(700, 0)
	txt.add_theme_font_size_override("normal_font_size", 15)
	txt.add_theme_font_override("bold_font", UITheme.f_semi)
	txt.add_theme_font_size_override("bold_font_size", 15)
	txt.text = """Вы — владелец маленького токарного участка в гаражном боксе. Берите заказы, точите детали, сдавайте вовремя — и расширяйтесь.

[b]Как всё работает[/b]
• Заказы берёт [b]отдел сбыта[/b] сам: каждое утро приходят заявки, сбыт принимает те, что завод успеет сделать с выгодой (по самому загруженному переделу — токарке, фрезеровке, ОТК…), и сам закупает металл. Заявки, на которые сейчас нет мощности, ждут полтора дня — освободится станок, сбыт их возьмёт.
• Ваше дело — стратегия (окно [b]Заказы[/b]): насколько рисковать сроками, от какой маржи брать, что держать в ассортименте. Во вкладке «Рынок» видно, что просят заказчики, цены недели, вашу мощность и [b]упущенную выгоду[/b] — сколько денег вы теряете без нужного станка или человека. Это подсказка, что строить дальше.
• [b]Контракты[/b]: крупные клиенты раз в одну-две недели предлагают поставки на 4–8 недель с надбавкой 10–25%. Часто — на изделие, для которого ещё нет оборудования: до начала поставок есть неделя-другая, чтобы построить цех и купить станки. Сорвали недельную партию — штраф, две — контракт расторгнут. Тендеры (экспорт, госзаказ) и «горящие» заказы тоже решает директор.
• Не хватает денег на металл под принятый заказ — поставщик отгрузит в долг с отсрочкой на две недели (+5%), в пределах лимита.
• Фургон привезёт металл, рабочие разгрузят его на стеллаж. Токарь точит детали, контролёр ОТК проверяет их, годные уходят на поддон, брак — в тару.
• Когда партия готова, приедет машина клиента. Деньги — после погрузки. Опоздание — штраф 5% в день (не больше 30% суммы), через 3 дня заказ сорвётся.
• [b]Перенос срока[/b]: если заказ не успевает (срок сегодня-завтра или уже просрочен), в «Заказы → В работе» есть кнопка «+2 дн.» — звонок заказчику: срок на два рабочих дня позже за скидку 12% и чуть репутации. Один раз на заказ, госзаказ не переносится.
• [b]Пробная партия[/b]: первый заказ на новое сложное изделие (несколько операций или сборка) — маленький, с двойным сроком и без неустойки. Цех осваивает изделие без риска; сорванная пробная партия бьёт по репутации втрое мягче.
• Станки изнашиваются: изношенный станок обслуживает токарь или рукастый рабочий (резцы и запчасти стоят денег). Совсем изношенный может сломаться — ремонт дорогой. Включите [b]ППР[/b] в «Производстве → Станки», чтобы обслуживать раньше.

[b]Производство вглубь[/b] (окно «Производство», клавиша P)
• Сложные изделия идут по маршруту из нескольких операций: точение → фрезерование → сверление → термообработка или покраска. Между операциями детали — [b]незавершённое производство[/b] (НЗП): ставьте для них стеллаж НЗП.
• Фрезерный и сверлильный станки — для корпусов и кронштейнов, сварочный пост — для рам, камерная печь закаляет партию до 6 деталей сама, покрасочная камера красит. Сборочный верстак собирает узел из ваших же деталей.
• [b]Размер деталей[/b]: изделия бывают мелкие (пальцы, втулки, кронштейны), средние (валы, корпуса, шестерни) и крупные (вагонные оси, балки, фермы, насосы). Станок берёт детали до своего размера: на настольном ТВ-4 — только мелочь, на 1К62 и 16К20 — мелкие и средние, вагонную ось точат на тяжёлом 1М63. Размер станка — в его паспорте и в подсказке в меню «Объекты»; на крупном станке сначала делают крупное.
• На каждый передел — пять советских станков: малые дешёвые и экономные, средние, тяжёлые для крупных деталей. Муфельная печь быстро калит мелочь, установка ТВЧ — по две детали втрое быстрее, шахтная и выкатная печи — большие партии крупных деталей. Порошковая камера тратит на 40% меньше краски.
• [b]ЧПУ[/b] (отдельный раздел меню «Объекты»): токарный 16А20Ф3 и обрабатывающий центр 65А60 — свои; Сайдвей, Пантера, Ханган, Хартвуд и Мингер — импортные, по разработке «Импортное ЧПУ». Быстрее и точнее обычных станков, но нужен опытный оператор (навык от 4).
• Под каждый процесс нужен свой специалист: фрезеровщик, сварщик, термист, маляр, слесарь-сборщик. Объявление по профессии («Люди → Найм») приводит нужных людей.
• Расходники: режущий инструмент, сварочная проволока, краска — снабжение докупает их само. В инструментальной кладовой (помещение со шкафом для инструмента) резцы тратятся медленнее.
• Логистика: тележка и электропогрузчик возят больше за ходку, кран-балка в цеху ускоряет работу с тяжёлыми деталями.

[b]Люди[/b]
• Две смены: 1-я с 8:00 до 17:00, 2-я с 17:00 до 02:00 (ночные +20%). Смену, ставку и премию меняют в карточке человека.
• Приходят в своей одежде и переодеваются у шкафчика в спецовку. Обедают через 4 часа после начала смены, ходят в туалет, курильщики — на перекур.
• У каждого 1–2 черты характера и настроение. Его складывают мысли: где обедал, где переодевался, какой туалет, хватает ли света, какая зарплата. Хорошее настроение — работают быстрее, плохое — медленнее, прогуливают и в конце концов увольняются.
• [b]Обучение[/b] (Люди → Обучение): курсы повышения разряда (+2 к навыку) и смежной профессии (допуск к другим станкам). Учить можно в своём [b]учебном классе[/b] (линолеум, две парты, доска) — дёшево, человек учится в свою смену; или в учебном центре — дороже, и он уезжает на несколько дней.
• [b]Наставники[/b]: опытный рабочий утраивает рост ученика у станка, но сам работает чуть медленнее. Ученик дорос — наставничество кончается само.
• [b]Инструктаж по охране труда[/b] раз в два месяца: травм на 30% меньше, а трудовая инспекция проверяет журнал, если рабочих 6 и больше.
• [b]Отношения[/b]: кто работает рядом, дружит или не ладит. С другом в смене работается веселее, с недругом — хуже; ссорящихся можно развести по разным сменам.
• [b]ПТУ[/b]: по договору приходят практиканты — дешёвые, учатся вдвое быстрее; лучших берите в штат.
• [b]Что важно[/b] (карточка → «Обзор»): пять полосок — быт, деньги, работа, коллектив, дом. Наведите — видно, из чего сложилось; проседающая подсказывает, что поправить.
• [b]Разряд — через экзамен[/b]: курсы растят навык, а разряд даёт экзамен (карточка → «Экзамен»): на смене человек делает пробную деталь и несёт мастеру. Сдал — разряд и просьба о прибавке по разряду; не сдал — пересдача через неделю.
• [b]Индексация[/b]: раз в квартал цены растут, рыночные ставки поднимаются — люди ждут индексации. Не проиндексируете — «платят меньше, чем везде».
• [b]Стаж и возраст[/b]: раз в год все становятся старше, с годами устают быстрее. Год на заводе — «ветеран завода», уважают. Пенсия: женщинам с 55, мужчинам с 60 — можно уговорить остаться или проводить с почётом.
• [b]Рацпредложения[/b]: опытные рабочие предлагают улучшения под свой станок и деталь — операция быстрее, брака меньше, износ медленнее.
• [b]Рабочие места[/b]: станок, стол ОТК, пила и верстак закреплены за людьми (карточка объекта → «Сменить…»). Хозяин работает первым; если не может — не на смене, на больничном, занят — встаёт любой, кто умеет.
• [b]Приказы[/b]: выберите человека и щёлкните [b]правой кнопкой[/b] по станку — пойдёт работать туда; по клетке — пойдёт туда. Сделал или делать нечего — сам вернётся к обычной работе.
• [b]Слесари[/b]: у слесарного верстака дорабатывают брак (часть деталей спасают и несут на ОТК), режут заготовки ножовкой, пока нет ленточной пилы, быстро ремонтируют станки.

[b]Зоны[/b] (кнопка «Зоны», клавиша R)
• Помещение — пол, обнесённый стенами с дверью. Внутри помещения рисуют [b]зоны[/b]: выберите зону в меню и протяните прямоугольник — разметятся клетки; просто щёлкните — зальётся всё помещение. Соседние клетки одной зоны сливаются, в одном зале может быть несколько зон (цех и склад, контора и бухгалтерия).
• Название зоны тускло написано на полу, цвет — группа: оранжевый — производство, жёлтый — склад и отгрузка, зелёный — быт, синий — кабинеты, фиолетовый — учёба и профком. Чего не хватает — жёлтый треугольник в углу зоны.
• Тепло, свет, шум, вентиляция, кран-балка, камеры и огнетушитель — общие на весь зал, во всех его зонах.
• У каждой зоны свои требования (например, туалету нужны раковина и вода, столовой — холодильник или микроволновка). Оборудованные зоны поднимают настроение.
• [b]Зоны обязательны[/b]: станками работают только в зоне «Цех», туалетом пользуются в зоне «Туалет», шкафчиком — в бытовке, за обеденным столом едят в столовой, подстанция и насосная работают только в техпомещении. Объект вне своей зоны помечен треугольником, а в его карточке — кнопка «Разметить».
• На улице — [b]разгрузка[/b] (сюда привозят металл и ящики) и [b]отгрузка[/b] (сюда относят готовые заказы, пока едет машина клиента): Стройка → Зоны на улице.
• Щёлкните по любой постройке — станку, столу, стене, двери, полу: откроется карточка с описанием и кнопкой сноса.

[b]Обустройство и чистота[/b]
• У каждого помещения [b]уровень обустройства[/b] 1–5 (звёзды в карточке и в оверлее «Чистота»): окна, хороший пол, электрический свет, растения и декор (Объекты → Декор: пальма, аквариум, ковёр, книжный шкаф, телевизор, знамя, стенд по охране труда). Чем выше уровень, тем лучше настроение у тех, кто там работает и отдыхает; в большом цеху декора нужно больше.
• Станки сыплют [b]стружку[/b], люди разносят грязь. Грязно — настроение падает, на стружке скользят и режутся, санитарный надзор штрафует. Убирают [b]уборщицы[/b] (Люди → Найм), а если совсем грязно — и разнорабочие.
• Стружку сметают в [b]контейнеры для стружки[/b] (Объекты → Склад). По пятницам приезжает ломовоз: платит за стружку и за брак из тары.
• [b]Ленточнопильный станок[/b] режет пруток на заготовки впрок: первая операция из готовой заготовки на 20% быстрее. [b]Наладчик[/b] заранее налаживает станки под следующую операцию и обслуживает их — станочники не простаивают.
• [b]Готовые помещения[/b] (Стройка → Помещения): цех 10×6, склад 6×4, кабинет, туалет, столовая, раздевалка, техпомещение — щелчок по земле, и заказаны пол, стены, двери, мебель и свет; зона разметится сама, когда достроят. Размеры — внутренние, без стен.
• [b]Помещение рамкой[/b] (Стройка): протяните прямоугольник — сразу пол, стены и дверь.
• [b]План[/b] (кнопка «План», клавиша V): рисуйте будущий завод на кальке — стены, полы, зоны, станки, готовые помещения. Это бесплатно, рабочие план не трогают. «Утвердить план» превращает его в чертежи по смете; зоны и мебель, которым нужны стены, встанут сами, когда достроят. Снос в режиме плана стирает план.

[b]Объекты и доставка[/b]
• Купленный станок или мебель привозят фургоном: крупное — в нескольких ящиках (каждый несёт один человек), мелочь (стул, цветок, чайник) несут в руках. Когда все ящики у места — объект собирают.
• Отметьте [b]зону разгрузки[/b] у ворот (Стройка → Зона разгрузки): туда разгружают металл и ящики, оттуда разносят по стеллажам и местам установки.
• R — повернуть объект при установке; уже стоящий — кнопкой «Повернуть» в его карточке.
• Демонтированное уносят в ящиках на склад оборудования (помещение «Склад» или зона разгрузки). Поставите такой же объект — возьмут оттуда бесплатно; лишнее можно продать (Производство → Склад оборудования).
• Снабжение работает само: металл и расходники докупаются под заказы. В «Производстве → Металл и расходники» выбирают поставщика и запас металла.

[b]Сети[/b] (кнопка «Сети», клавиша E)
• Станки и приборы работают от электросети. Кабель заводят прямо [b]в клетку розетки[/b] объекта (жёлтый значок в оверлее), а к подстанции — в одну из её клеток. Светильники подключаются сами, если кабель проходит рядом. Так же и трубы: в клетку туалета, раковины, котла.
• Свет — от светильников под потолком: лампа накаливания, ЛПО, промышленный ДРЛ, уличный фонарь. Светильник подключается сам, если кабель проходит не дальше 3 клеток. В темноте работают медленнее и чаще травмируются.
• Кабель, трубы и воздуховоды кладутся [b]чертежом[/b]: деньги сразу, а прокладывают рабочие — кабель электрик (или строитель, разнорабочий), трубы и воздуховоды — строители. Пока клетку не проложили, ток и вода по ней не идут.
• Электричество: [b]трансформаторная подстанция[/b] 2×2 в [b]техпомещении[/b] даёт 40 кВт — от неё питается весь завод, никаких договоров. Вплотную к ней (и по углам) ставят до 9 [b]аккумуляторных шкафов[/b] — каждый +20 кВт, всего до 220 кВт. В гараже и в чистом поле техпомещение уже построено. Над подстанцией — полоска нагрузки; перегрузка выбивает автомат — его сбросит электрик или рабочий.
• Водопровод: [b]насосная[/b] 2×2 в техпомещении (под током) — от неё тяните трубы в клетки туалетов, раковин, душевых и испытательного стенда. Без воды туалетом пользоваться нельзя. Одна насосная тянет 30 приборов; больше — вторая.
• [b]Аварии[/b]: иногда обрывается провод (искрит, дальше тока нет) или лопается труба (лужа, дальше воды нет). Можно вызвать аварийную бригаду за деньги — починят за час, или чинить своими силами: кусок сети появится в чертежах, любой свободный рабочий заменит его вне очереди. Щелчок по месту аварии — карточка с кнопкой «Аварийная бригада».
• [b]Вентиляция[/b]: сварка, покраска и печь дымят — без вытяжки в помещении душно, люди злятся и работают медленнее, санитарный надзор штрафует. Вытяжной вентилятор (под током) тянет воздух из своего помещения и из всех, через которые идёт его воздуховод. [b]Вытяжной зонт[/b] над сварочным постом или камерой убирает три четверти дыма прямо у источника. Оверлей «Вентиляция» показывает воздух в помещениях.
• [b]Сжатый воздух[/b]: компрессор и пневмомагистраль к покрасочной камере (без воздуха красят кистью — в полтора раза дольше) и сборочным столам (на 20% быстрее). Компрессор шумит — ставьте его в отдельную компрессорную.
• [b]Котельная[/b]: газовый котёл в отдельном помещении греет до 16 батарей, подключённых трубой к его сети водопровода. Тепло вдвое дешевле городского, и авария на теплотрассе не страшна.

[b]Охрана труда[/b] (Люди → Охрана труда)
• [b]СОУТ[/b] — спецоценка условий труда: лаборатория замеряет шум, воздух, свет и микроклимат на каждом станке и присваивает класс: 2 — допустимые условия, 3.1–3.3 — вредные. На вредных местах положены доплата 4–12% к ставке и молоко; трудовая инспекция штрафует, если СОУТ не проведена. Улучшили условия — закажите замеры заново, класс снизится.
• [b]СИЗ[/b]: каски, очки, наушники, респираторы. Новички приходят без них, у остальных комплект изнашивается примерно за 20 смен. Поставьте шкаф СИЗ (Объекты → Безопасность) и закупайте комплекты — снабжение докупит само. Без СИЗ травм в полтора раза больше. В наушниках шум не раздражает, в респираторе дым — меньше.
• [b]Молоко за вредность[/b]: включается в «Охране труда», 70 ₽ на человека за смену. Не дают — люди обижаются, инспекция штрафует.
• [b]Акт Н-1[/b]: после каждой травмы комиссия за три рабочих дня находит причины. По вине предприятия — компенсация пострадавшему и штраф; «записать вину на рабочего» дешевле, но люди и профком запомнят, а скрытую травму найдёт трудовая инспекция. Табло «Дней без травм» снижает травмы на 5%.

[b]Бригады и порядок[/b] (Люди → Бригады, клавиша K)
• [b]Бригады[/b]: бригадир получает +10% к ставке и ускоряет своих на 3–6%. Закрепите за бригадой цех — люди берут работу сначала на своих станках. «Сформировать автоматически» разобьёт всех по цехам.
• [b]Соцсоревнование[/b]: по пятницам лучшая бригада (операций на человека) получает вымпел — +настроение и +3% к скорости на неделю.
• [b]График смены[/b] по 15 минут: планёрка (+3% к скорости на смену), обед (не меньше 30 минут — иначе штраф), перерыв на чай, уборка в конце смены. Бригадам можно дать свой график — меньше очередей в столовой.
• [b]Охрана[/b]: несуны выносят металл и расходники, уходя со смены. Охранник на проходной ловит больше половины, камеры (Объекты → Безопасность) отпугивают и записывают; по пятницам — инвентаризация.
• [b]Профсоюз[/b] появляется, когда рабочих 8 и больше. Профком предлагает коллективный договор, заранее предупреждает о забастовке и даёт людям больше терпения; нарушенный колдоговор злит всех.
• Кран-балку ставят внутри цеха: пути — вдоль стен, мост — от стены до стены; тележка ездит к станку с тяжёлой деталью.

[b]Рынок и конкуренты[/b] (Заказы → Конкуренты)
• В районе работают ещё несколько заводов. Наша [b]доля рынка[/b] зависит от мощности, качества, доли заказов, сданных вовремя, репутации, цен и сертификата ISO 9001 — чем мы сильнее, тем больше заявок каждое утро.
• [b]Ценовая политика[/b]: демпинг (−10% к цене, заявок на треть больше), по рынку или премиум (+12%, заявок меньше; с ISO 9001 заказчики почти не уходят).
• Конкуренты устраивают войны цен, расширяются, переманивают опытных рабочих и иногда разоряются — тогда их оборудование можно купить с торгов за 40% цены.
• [b]Цена металла[/b] гуляет каждый день, иногда скачком: дёшево — закупайте впрок, дорого — только под заказы (Производство → Металл и расходники).
• [b]Графики[/b] (Финансы → Графики): деньги, выручка и расходы, доля рынка, настроение и репутация по дням.
• [b]Лизинг[/b]: станок от 40 000 ₽ — 20% сразу, остальное платежами 12 недель (+18%). Включается в «Объектах» или в «Финансы → Кредиты и лизинг».
• [b]Страхование[/b]: имущество (80% ремонта, ущерб от пожара), ответственность (половина неустоек, рекламаций и штрафов по контрактам), несчастный случай (компенсация по акту Н-1). Взнос — по понедельникам.
• [b]ISO 9001[/b] (Управление → ISO 9001): ОТК, качество от 65%, техотдел, СОУТ, инструктаж и две недели без рекламаций — аудитор выдаст сертификат на полгода.
• [b]Главный инженер[/b] (Управление → Главный инженер) подсказывает, что сейчас важнее всего: узкие места, сроки, поломки, настроение, деньги, металл.

[b]Город[/b] (кнопка «Город», клавиша H)
• [b]Общежитие[/b]: комната с двухъярусными кроватями (две койки) и шкафчиком → «Общежитие». Пока есть свободные койки, по понедельникам приезжают иногородние кандидаты: чуть дешевле, никогда не опаздывают, ходят «домой» в общежитие. Плата — 100 ₽ в день с жильца.
• [b]Горячие обеды[/b]: в столовой — промышленная плита (под током) и линия раздачи, в штате — повар. Повар готовит порции на всех, обед с горячим даёт +9 к настроению вместо +6.
• [b]Медпункт[/b]: кушетка, шкаф с лекарствами и раковина + фельдшер. Больничные после травм на 40% короче, грипп (с ноября по февраль) реже. Прививки всему коллективу — вчетверо меньше заболевших.
• [b]Детсад «Шестерёнка»[/b] (с «Малого предприятия»): места для детей работников — родители довольны и не сидят дома с ребёнком. [b]ДК «Машиностроитель»[/b] (со «Среднего предприятия»): кружки и концерты к праздникам.
• [b]Заводское радио[/b]: радиоузел и громкоговорители под потолком — утренние новости, производственная гимнастика в 10:00, музыка в обед.
• [b]Кот[/b] прибьётся сам (быстрее, если есть столовая). Поставьте миску — и он останется: гладить его приятно, а крысы перестанут портить расходники.
• [b]Отношения с городом[/b] растут от заботы о людях и падают от увольнений. От 60 — больше кандидатов, от 75 — налог с выручки на 1% ниже.

[b]Управление заводом[/b] (кнопки «Управление» M и «Разработки» T)
• ИТР-отделы открывают новые возможности: мастер участка ускоряет смену и держит дисциплину, начальник цеха вводит аврал и сверхурочные, бухгалтерия спасает от штрафов налоговой и ведёт отчёты, снабженец находит металл дешевле, ПДО ведёт план и позволяет сбыту брать заказы «впритык», отдел кадров ищет людей, техотдел разрабатывает новые изделия и станки с ЧПУ.
• [b]Разработки[/b] (Управление → Разработки) — деревом: техотдел наверху, ветки техпроцессов, автоматизации, слесарного дела, изделий, управления и социалки. Дерево открывается, когда в штате есть технолог; линии показывают, что нужно изучить раньше.
• Каждому специалисту нужен стол ИТР в кабинете своего отдела (линолеум, стол и, например, сейф для бухгалтерии) или в общей конторе — там на 30% хуже.
• [b]Без человека — без функции[/b]: разделы окон, за которые отвечает отдел, закрыты замком, пока его нет. Без бухгалтера — только деньги и последние операции (ни отчёта по неделям, ни маржи, ни лизинга со страховкой); без кадровика настроение видно словом, без цифр; без снабженца — ни графика цены металла, ни закупки впрок; без ПДО — ни плана, ни оценки «успеваем?». На замке написано, какой кабинет построить и кого нанять, а в «Задачах» — какой отдел следующий.
• [b]Новые отделы[/b]: менеджер по сбыту (конкуренты, ценовая политика, контракты, +10% заявок), инженер по охране труда (−15% травм, вдвое меньший штраф по акту Н-1), главный инженер (советы, ППР станков без отдельной политики, сводка по сетям), юрист (обжалование штрафов проверок с шансом 60%, спор по рекламациям, госзаказы).
• Когда зарплаты съедают больше 70% выручки, бухгалтер предупредит в пятницу, а главный инженер подскажет, кто из станочников простаивает.
• [b]Развитие[/b] (Управление → Развитие): восемь веток по три ступени — финансы, кадры, производство, планирование, рынок, техника, право и охрана, город. Первая ступень ветки открывается наймом специалиста. Остальные директор исследует из [b]кабинета директора[/b] (линолеум и стол директора) — по одной, за деньги и несколько дней. Этап «Мастерская» разрешает вторые ступени, «Малое предприятие» — третьи; что открыть первым, решаете вы.
• Ступени держат люди: «Себестоимость», «Банк и лизинг» и другие работают, пока в отделе-хранителе есть человек. Уволили — ступень гаснет до найма нового. Вторым ступеням нужен собственный кабинет отдела, общей конторы мало.
• Что закрыто ступенями: маржа и прогноз кассы («Себестоимость»), кредит до 3 млн, лизинг и страхование («Банк и лизинг»), ПТУ и иногородние («Связь с ПТУ»), «риск ухода» и автозамена («Кадровый резерв»), доска почёта («Соцсоревнование»), «впритык» («Впритык»), контракты и экспорт («Контракты»), ISO 9001, госзаказ («Тендеры»), плита, раздача, медкабинет и общежитие («Соцсфера»), детсад, ДК и радио («Шефство»). Разработки технолога — тоже в ветке «Техника».
• Налог — 6% с выручки каждую пятницу. Когда в штате больше 8 человек, без бухгалтерии налоговая штрафует.
• В «Финансах» — отчёт по неделям, себестоимость изделий, прогноз кассы на две недели, гранты и кредиты. На «Рынке» видна маржа изделия (с бухгалтером) и успеет ли завод средний заказ (с ПДО).
• [b]Гранты[/b] (Финансы → Гранты) — мини-задания: оформите программу поддержки, выполните условия (оборудовать цех, столовую, создать рабочие места) — и после проверки вам возместят расходы. Кредиты банк даёт с этапа «Мастерская».
• У каждого заказа есть [b]приоритет[/b] (срочные делают первыми) и [b]чертёж[/b] детали по ГОСТ — кнопки в окне «Заказы».
• Деньги: зарплата выдаётся за каждую смену, даже если человеку нечего делать. Нанимайте под заказы; кнопки «Премия всем», «Ставки +5%» и «Ставки по рынку» — в «Люди → Сотрудники».
• Станок переналаживается, когда меняет изделие или операцию — ПДО и бережливое производство сокращают переналадку.

[b]Мир и события[/b] (кнопка «События», клавиша C)
• Рассказчик подбрасывает события: пожары, травмы, кражи, бракованный металл, «горящие» заказы, рацпредложения, визиты губернатора и журналиста. Где нужен выбор — приходит письмо с вариантами (игра встаёт на паузу).
• Малому бизнесу (до «Малого предприятия» включительно) за впервые выявленное нарушение — предупреждение вместо штрафа (ст. 4.1.1 КоАП). Не исправили к сроку предписания — двойной штраф.
• Проверки: пожарный надзор, трудовая инспекция, санитарный надзор, технадзор, экологи, налоговая. Плановые объявляют за три дня. Инспектор обходит завод и записывает нарушения, когда заходит в помещение — пока он идёт, можно успеть исправить. Список требований — во вкладке «Проверки»; нарушения на карте помечены красным.
• Пожар: свободные рабочие бегут тушить, с огнетушителем — в разы быстрее. Огнетушитель нужен в каждом помещении (кроме туалета и душевой), в горячих цехах — два.
• Травмы бывают от усталости, аврала, изношенного станка, темноты и холода. Пострадавший уходит на больничный; аптечка рядом сокращает его.
• Если люди долго недовольны — забастовка: все рабочие уходят к проходной с плакатами и выдвигают требование.
• Календарь сжат: месяц — две недели. Зимой морозы и снег: ставьте [b]батареи отопления[/b] (Объекты → Быт), иначе в цехах холодно; разнорабочие чистят снег лопатами. Есть праздники, летние отпуска и месячный план.
• По понедельникам выходит заводская многотиражка (кнопка «Газета», клавиша N).

[b]Слои[/b] (столбик значков у правого края)
• Зоны, электросеть, водопровод, освещение, температура, потоки людей (где ходят чаще — туда ставьте склады и шкафчики ближе), загрузка станков, чистота, вентиляция, сжатый воздух, бригады. Щелчок — включить, ещё раз — выключить; пояснение — карточкой слева внизу.

[b]Стройка и земля[/b]
• Стены и полы строят из [b]стройматериалов[/b]: кирпич, блоки, панели, мешки цемента, коробки плитки, рулоны линолеума. Цена материала входит в цену чертежа; заказ уходит поставщику сам, бортовой грузовик привозит поддоны в зону разгрузки (без неё — к воротам), строители уносят сколько поднимут и строят клетки рядом. Что едет и когда — строкой в меню «Стройка».
• [b]Деревья и кусты[/b] мешают ставить объекты. Снос → дерево — строитель спилит; пол и стену на месте дерева можно рисовать сразу, сначала его спилят.
• [b]Соседние участки[/b] справа от забора продаются (табличка «ПРОДАЁТСЯ»): Управление → Развитие → «Земля». Купленный участок становится своим — старый забор между участками можно снести.

[b]Живой завод[/b]
• Видно, кто что несёт: прутки на плече, лист под мышкой, мелкие детали в лотке, у ремонтника — ящик с инструментом, у электрика — катушка кабеля, у строителя — мастерок.
• [b]Тяжёлые детали[/b] (валы, корпуса, рамы) носят по одной. В зале с кран-балкой их везёт кран — человек ведёт его пультом; без крана деталь тащат волоком, это заметно медленнее.
• [b]Машины[/b]: мелочь возит фургон, большие партии металла — грузовик, станки и экспорт — фура, стройматериалы — бортовая машина.
• [b]Душевая[/b] (Зоны → Быт и здоровье): душевые кабины и раковина, вода по трубе. После смены станочники, сварщики, маляры и разнорабочие моются; нет душа или все кабины заняты — уходят грязными и недовольными.
• [b]Инспектора[/b] водит по заводу сопровождающий: инженер по охране труда (штрафы на 15% меньше), начальник цеха или мастер. [b]Инструктаж[/b] ведёт он же у доски или стенда, люди стоят полукругом.
• [b]Люди общаются[/b]: болтают на перекурах, в обед и без дела — от этого дружат. Кто не ладит, ругается, а ругань иногда кончается дракой: сбегаются зеваки, охранник или мастер разнимает, а директору приходит письмо — выговор, увольнение зачинщика или разные смены.

[b]Материалы[/b]
• Стены: кирпич, бетон (дешевле), сэндвич-панель (строится вдвое быстрее), перегородка (дёшево делить зал на кабинеты); двери — деревянная и стальная. Полы: бетон и наливной (грязь копится на треть медленнее) — для цеха, кафель и голубая плитка — для быта, линолеум и паркет — для кабинетов.

[b]Клавиши[/b]
• Камера: WASD или стрелки, колесо — масштаб, средняя кнопка — перетаскивание.
• ЛКМ — выбрать человека или объект. ПКМ или Esc — отменить инструмент или выделение.
• [b]Управление человеком[/b]: в карточке рабочего — жёлтая кнопка «Взять под управление». Дальше щёлкните по чертежу, станку, грузу или месту на полу и выберите «Сделать сейчас» — он пойдёт сразу. ПКМ — то же без меню. «Отпустить» или Esc — вернётся к обычной работе.
• Пробел — пауза, 1/2/3 — скорость ×1/×2/×4. B — стройка, O — объекты, R — зоны (при установке объекта — поворот), E — сети, P — цех, M — управление, T — разработки, C — события, N — газета, G — цели, X — снос.
• F5 — быстрое сохранение, F9 — быстрая загрузка, F1 — эта справка.

[b]Рост завода[/b] (кнопка «Цели», клавиша G)
• Завод растёт через шесть этапов: Гараж → Мастерская → Малое предприятие → Среднее → Крупный завод → Градообразующее. На каждом открываются новые станки, цеха и отделы; цели перехода — в окне «Цели». С «Мастерской» к следующему этапу ведут две обязательные цели и любые две из четырёх дорог на выбор: объём, качество, люди или город.
• Рейтинг в звёздах (1–5) складывается из выпуска и сроков, качества, безопасности, настроения людей и финансов.
• Профиль завода задаёт, что у вас заказывают: механика, сельхозмаш (весной заказов вдвое больше), металлоконструкции, насосы (испытания на стенде), железная дорога (жёсткая приёмка), станкостроение, режимное предприятие (госзаказ с авансом и военной приёмкой).
• С этапа «Среднее предприятие» приходят экспортные заказы и госзаказ.
• [b]Достижения[/b] общие для всех партий: список — в окне «Цели» и в главном меню. В песочнице не засчитываются.

[b]Ваш завод[/b]
Название и эмблему придумывают при новой игре; поменять — щелчком по эмблеме в шапке (паспорт завода). Они на вывеске над воротами, в многотиражке, на чертежах и на «Вывеске завода» (Объекты → Декор).
В «Чистом поле» и «Песочнице» первая неделя — на стройку: заказов нет. Готовы раньше — «Начать производство раньше» в списке задач.

[b]Стройка[/b]
Всё ставится чертежом: сначала платите, потом рабочие строят сами, когда свободны. Чертёж можно отменить — деньги вернутся. «Стройка в приоритете» снимает людей с переноски на стройку.
Окна, двери и ворота протягивают по линии стены: несколько клеток подряд становятся одним окном, двустворчатой дверью или секционными воротами. Двери отъезжают в стену, когда кто-то проходит, ворота поднимаются."""
	sc.add_child(txt)
	v.add_child(sc)
	_menu_button(v, "Понятно, за работу!" if first_time else "Закрыть", func() -> void:
		Game.settings["tutorial_done"] = true
		Game.save_settings()
		close_modal())


## Плашка «Достижение получено» сверху по центру, сама исчезает.
var _ach_box: VBoxContainer = null


func show_achievement(a: Dictionary) -> void:
	if _ach_box == null:
		_ach_box = VBoxContainer.new()
		_ach_box.add_theme_constant_override("separation", 8)
		_ach_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_ach_box.position = Vector2(-180, 70)
		_ach_box.custom_minimum_size = Vector2(360, 0)
		_ach_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ach_box)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sb(Color(0.1, 0.1, 0.09, 0.95), Color("#e2b33c"), 2, 8, 14, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UITheme.hbox(12)
	var ic := TextureRect.new()
	ic.texture = Tex.ui("medal")
	ic.custom_minimum_size = Vector2(44, 44)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(ic)
	var v := UITheme.vbox(1)
	v.add_child(UITheme.label("Достижение получено", 12, Color("#e2b33c"), UITheme.f_semi))
	v.add_child(UITheme.label(str(a.get("name", "")), 17, UITheme.TEXT, UITheme.f_semi))
	v.add_child(UITheme.label(str(a.get("desc", "")), 13, UITheme.MUTED))
	h.add_child(v)
	p.add_child(h)
	_ach_box.add_child(p)
	Snd.play("fanfare", -6.0)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.35)
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


## Завод вырос: окно нового этапа со списком открывшегося.
func show_stage_up(st: int) -> void:
	var pg := sim.progress
	Snd.play("fanfare", 0.0)
	var v := _open_modal(620)
	var head := UITheme.hbox(12)
	var ic := TextureRect.new()
	ic.texture = Tex.ui("stage_up")
	ic.custom_minimum_size = Vector2(48, 48)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.modulate = UITheme.GOOD
	head.add_child(ic)
	head.add_child(UITheme.title("Новый этап: «%s»!" % pg.stage_name(st), 24))
	v.add_child(head)
	var names: Array[String] = []
	for k in Defs.objects.keys():
		if int(Defs.objects[k].get("stage", 1)) == st and not Defs.objects[k].has("dev"):
			names.append(str(Defs.objects[k]["name"]))
	for d in Defs.departments.keys():
		if int(Defs.departments[d].get("stage", 1)) == st:
			names.append("отдел: " + str(Defs.departments[d]["name"]).to_lower())
	var txt := "Завод вырос! Открылось: %s." % (", ".join(names) if not names.is_empty() else str(pg.stage_def(st).get("opens", "")).to_lower())
	var steps: Array[String] = []
	for id in Develop.all_ids():
		var sd := Develop.step_def(id)
		if not sd.has("dept") and int(sd.get("stage", 1)) == st:
			steps.append("«%s»" % str(sd["name"]))
	if not steps.is_empty():
		txt += "\n\nВ «Развитии» можно исследовать: %s (Управление → Развитие, нужен кабинет директора)." % ", ".join(steps)
	if st < Progress.STAGE_COUNT:
		var gl: Array[String] = []
		for g: Dictionary in pg.stage_goals():
			gl.append(str(g.get("text", "")))
		txt += "\n\nДальше — «%s». Цели: %s." % [pg.stage_name(st + 1), "; ".join(gl)]
		if pg.choice_need() > 0:
			var cl: Array[String] = []
			for g4: Dictionary in pg.stage_choice().get("list", []):
				cl.append("%s — %s" % [str(g4.get("route", "")), str(g4.get("text", "")).to_lower()])
			txt += " И любые %d на выбор: %s." % [pg.choice_need(), "; ".join(cl)]
	var l := UITheme.label(txt, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(570, 0)
	v.add_child(l)
	for w in sim.workers:
		Mood.add(sim, w, "stage_up")
	_menu_button(v, "Отлично, работаем!", close_modal)


func show_scenario_done() -> void:
	var v := _open_modal(560)
	v.add_child(UITheme.title("Сценарий «%s» пройден!" % str(sim.progress.sdef().get("name", "")), 24))
	var l := UITheme.label("Все цели выполнены, рейтинг завода — %s. Можно продолжать без ограничений: растите до градообразующего предприятия или начните другой сценарий с другим профилем завода." % sim.progress.stars_text(), 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(510, 0)
	v.add_child(l)
	_menu_button(v, "Продолжить игру", close_modal)
	_menu_button(v, "В главное меню", func() -> void:
		Game.autosave(sim)
		Game.to_menu())


## 1.20: конец игры — завод закрыт (трудовая инспекция, банкротство…).
func show_game_over() -> void:
	var v := _open_modal(600)
	var c: Dictionary = sim.crisis.closed
	var pl := FactoryUI.plate("Завод закрыт", "strike", 18)
	pl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pl)
	v.add_child(UITheme.title(str(c.get("title", "Конец игры")), 24))
	v.add_child(UITheme.para(str(c.get("text", "")), 15, UITheme.TEXT))
	var days := sim.day() + 1
	v.add_child(UITheme.para("%s проработал %d %s (до %s). Выполнено заказов: %d, репутация %d." % [Company.title(sim), days, Defs.plural(days, "день", "дня", "дней"), str(c.get("date", sim.date_str())), int(sim.stats.get("orders_done", 0)), int(sim.reputation)], 13, UITheme.MUTED))
	v.add_child(UITheme.para("Чтобы такого не было: платите зарплату вовремя (в долг — не чаще раза в 3 месяца), не набирайте заказов больше, чем успеваете, и держите запас денег на две зарплаты.", 13, UITheme.WARN))
	_menu_button(v, "Загрузить сохранение", show_load_dialog)
	_menu_button(v, "Начать заново", func() -> void: Game.start_new_game())
	_menu_button(v, "В главное меню", func() -> void: Game.to_menu())


## 1.20: «Как исправить» — короткое окно для красной строки из проверок и требований.
func show_fix(what: String, fix: String, cell: Vector2i = Vector2i(-1, -1)) -> void:
	if fix_box and is_instance_valid(fix_box):
		fix_box.queue_free()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sbs(UITheme.BG, UITheme.BAD, 1, 10, 16, 12, 18, 0.6, 6))
	p.custom_minimum_size = Vector2(440, 0)
	var v := UITheme.vbox(8)
	p.add_child(v)
	v.add_child(UITheme.label("Что не так", 12, UITheme.MUTED, UITheme.f_semi))
	var wl := UITheme.para(what, 15, UITheme.BAD)
	wl.custom_minimum_size = Vector2(408, 0)
	v.add_child(wl)
	v.add_child(UITheme.label("Как исправить", 12, UITheme.MUTED, UITheme.f_semi))
	var fl := UITheme.para(fix if fix != "" else "Устраните причину — после этого строка пропадёт.", 14, UITheme.TEXT)
	fl.custom_minimum_size = Vector2(408, 0)
	v.add_child(fl)
	var h := UITheme.hbox(8)
	h.add_child(UITheme.spacer())
	if cell.x >= 0:
		h.add_child(UITheme.button("Показать место", func() -> void:
			close_window()
			g.cam.focus_cell(cell)
			if fix_box and is_instance_valid(fix_box):
				fix_box.queue_free()))
	h.add_child(UITheme.primary("Понятно", func() -> void:
		if fix_box and is_instance_valid(fix_box):
			fix_box.queue_free()))
	v.add_child(h)
	add_child(p)
	fix_box = p
	p.reset_size()
	var vs := get_viewport_rect().size
	var mp := get_viewport().get_mouse_position()
	var sz := p.get_combined_minimum_size()
	p.position = Vector2(clampf(mp.x + 16.0, 8.0, vs.x - sz.x - 8.0), clampf(mp.y - 20.0, 60.0, vs.y - sz.y - 100.0))


## 1.20: увольнение — выбрать причину. Законная — без последствий (или с выплатой); нет оснований — суд и жалоба.
func show_fire_dialog(w: Worker, done: Callable = Callable()) -> void:
	var v := _open_modal(560)
	v.add_child(UITheme.title("Уволить: %s" % w.full_name(), 20))
	v.add_child(UITheme.para("%s · в штате %d дн. Выберите причину — от неё зависит, будут ли последствия. Расчёт за отработанные дни выплачивается всегда." % [w.prof_name(), maxi(0, sim.day() - w.hired_day)], 13, UITheme.MUTED))
	for r: Dictionary in sim.crisis.fire_reasons(w):
		var legal := bool(r["legal"])
		var key := str(r["key"])
		var row := UITheme.card(10, UITheme.BG2, UITheme.GOOD.darkened(0.3) if legal else UITheme.BAD.darkened(0.3))
		var h := UITheme.hbox(10)
		row.add_child(h)
		var col := UITheme.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nh := UITheme.hbox(8)
		nh.add_child(UITheme.label(str(r["name"]), 15, UITheme.TEXT, UITheme.f_semi))
		nh.add_child(UITheme.chip("законно" if legal else "нет оснований", UITheme.GOOD if legal else UITheme.BAD))
		col.add_child(nh)
		var wl := UITheme.para(str(r["why"]), 12, UITheme.MUTED)
		wl.custom_minimum_size = Vector2(360, 0)
		col.add_child(wl)
		h.add_child(col)
		var b := UITheme.button("Уволить", func() -> void:
			var txt := sim.crisis.fire_with(w, key)
			close_modal()
			toast(txt, Sim.LVL_WARN if legal else Sim.LVL_BAD, 5.0)
			if done.is_valid():
				done.call())
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if float(r["cost"]) > 0.0 and not sim.can_afford(float(r["cost"])):
			b.disabled = true
			b.tooltip_text = "Не хватает денег на выплату"
		h.add_child(b)
		v.add_child(row)
	var bh := UITheme.hbox(8)
	bh.add_child(UITheme.spacer())
	bh.add_child(UITheme.primary("Не увольнять", close_modal))
	v.add_child(bh)


func show_bankrupt() -> void:
	var v := _open_modal(520)
	v.add_child(UITheme.title("Долги растут", 24))
	var l := UITheme.label("На счёте %s. Кредиторы звонят каждый день. Можно продолжать в надежде выправить положение — или начать заново." % Defs.money_str(sim.money), 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(470, 0)
	v.add_child(l)
	_menu_button(v, "Продолжить", close_modal)
	_menu_button(v, "Начать заново", func() -> void: Game.start_new_game())
