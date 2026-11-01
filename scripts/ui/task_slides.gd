class_name TaskSlides
extends ColorRect
## 1.66: экран «Ваша задача» — три коротких слайда перед первой игрой: кто вы, что делаете, как выиграть и проиграть.
## Открывается и из справочника («?» → «Ваша задача»). Пока открыт, игра стоит (hud.show_task).
## Названия этапов берутся из data/stages.json, условия поражения — из правил кризисов (Crisis).

const COUNT := 3
## Цепочка круга производства: значок, подпись.
const FLOW := [["orders", "Заказ"], ["supply", "Металл"], ["production", "Станок"], ["inspect", "ОТК"], ["load", "Отгрузка"], ["money", "Деньги"]]

var sim: Sim
var on_close: Callable
var page := 0
var _body: VBoxContainer
var _dots: HBoxContainer
var _back: Button
var _next: Button
var _skip: Button
var _step_l: Label
var _never: CheckBox


func setup(s: Sim, close_cb: Callable) -> void:
	sim = s
	on_close = close_cb


func _ready() -> void:
	name = "TaskSlides"
	color = Color(0, 0, 0, 0.72)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vs := get_viewport_rect().size
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sbs(UITheme.BG, UITheme.ACCENT_D, 2, 14, 30, 22, 30, 0.6, 8))
	var psz := Vector2(minf(900.0, vs.x - 40.0), 0.0)
	p.custom_minimum_size = psz
	add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var root := UITheme.vbox(14)
	p.add_child(root)
	var head := UITheme.hbox(10)
	root.add_child(head)
	_step_l = UITheme.label("", 13, UITheme.ACCENT, UITheme.f_semi)
	_step_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_step_l)
	head.add_child(UITheme.spacer())
	_skip = UITheme.ghost("Пропустить", func() -> void: close(), "Закрыть этот экран. Открыть снова можно кнопкой «?» → «Ваша задача»", UITheme.MUTED)
	head.add_child(_skip)
	_body = UITheme.vbox(12)
	_body.custom_minimum_size = Vector2(0, 330)
	root.add_child(_body)
	var foot := UITheme.hbox(10)
	root.add_child(foot)
	_dots = UITheme.hbox(6)
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_dots)
	foot.add_child(UITheme.spacer())
	_never = CheckBox.new()
	_never.name = "Never"
	_never.text = "Не показывать при новой игре"
	_never.focus_mode = Control.FOCUS_NONE
	_never.button_pressed = not bool(Game.settings.get("task_intro", true))
	_never.toggled.connect(func(v: bool) -> void:
		Game.settings["task_intro"] = not v
		Game.save_settings())
	foot.add_child(_never)
	_back = UITheme.button("‹ Назад", func() -> void: _go(page - 1))
	_back.custom_minimum_size = Vector2(110, 38)
	foot.add_child(_back)
	_next = UITheme.primary("Далее  →", func() -> void:
		if page >= COUNT - 1:
			close()
		else:
			_go(page + 1))
	_next.custom_minimum_size = Vector2(190, 38)
	foot.add_child(_next)
	_show()


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		elif k.keycode == KEY_RIGHT or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_next.pressed.emit()
		elif k.keycode == KEY_LEFT and page > 0:
			get_viewport().set_input_as_handled()
			_go(page - 1)


func close() -> void:
	if on_close.is_valid():
		on_close.call()


func _go(i: int) -> void:
	page = clampi(i, 0, COUNT - 1)
	_show()


func _show() -> void:
	_step_l.text = tr("ВАША ЗАДАЧА · %d ИЗ %d") % [page + 1, COUNT]
	_back.visible = page > 0
	_never.visible = page == COUNT - 1
	_next.text = "Начать работу" if page == COUNT - 1 else "Далее  →"
	UITheme.clear(_body)
	UITheme.clear(_dots)
	for k in COUNT:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(26 if k == page else 9, 7)
		d.color = UITheme.ACCENT if k == page else Color(1, 1, 1, 0.2)
		_dots.add_child(d)
	match page:
		0:
			_slide_who()
		1:
			_slide_what()
		_:
			_slide_win_lose()


func _heading(icon: String, text: String) -> void:
	var h := UITheme.hbox(16)
	var ic := UITheme.icon_plate(icon, 72, UITheme.ACCENT, false)
	ic.custom_minimum_size = Vector2(72, 72)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := UITheme.title(text, 30)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	_body.add_child(h)


func _slide_who() -> void:
	_heading("company", "Вы — директор мастерской")
	_body.add_child(UITheme.para("Небольшая мастерская в гаражном боксе промзоны: старый станок, несколько работников и стартовый капитал.", 18, UITheme.TEXT))
	_body.add_child(UITheme.para("Точить детали самому не нужно. Вы решаете, что построить, кого нанять, какие заказы брать и на что тратить деньги. Люди на заводе живые: они работают, устают, обижаются на низкую зарплату и уходят, если нет нормальных условий: туалета, бытовки, столовой.", 16, UITheme.MUTED))
	var tip := UITheme.card(12, Color(0.85, 0.65, 0.2, 0.1), Color(0.85, 0.65, 0.2, 0.45))
	tip.add_child(UITheme.para("Игра идёт сама, как настоящий рабочий день. Пробел — пауза: на паузе можно спокойно строить и читать.", 15, Color("#f0cf7a")))
	_body.add_child(tip)


func _slide_what() -> void:
	_heading("orders", "Что вы делаете")
	var flow := UITheme.hbox(4)
	flow.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in FLOW.size():
		var f: Array = FLOW[i]
		var c := UITheme.card(8, UITheme.BG2, UITheme.LINE)
		var v := UITheme.vbox(4)
		var ic := UITheme.icon_plate(str(f[0]), 40, UITheme.ACCENT, false)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var l := UITheme.label(str(f[1]), 14, UITheme.TEXT, UITheme.f_semi)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		c.add_child(v)
		c.custom_minimum_size = Vector2(104, 0)
		flow.add_child(c)
		if i < FLOW.size() - 1:
			flow.add_child(UITheme.label("›", 22, UITheme.MUTED, UITheme.f_semi))
	_body.add_child(flow)
	_body.add_child(UITheme.para("Берёте заказы, закупаете металл, делаете детали, сдаёте их ОТК и отгружаете клиенту. Клиент платит после погрузки; опоздали со сроком — получите меньше.", 17, UITheme.TEXT))
	_body.add_child(UITheme.para("На вырученные деньги нанимаете людей, строите помещения и ставите станки — и берёте заказы покрупнее. Заказы, деньги и репутацию всегда видно в верхней панели.", 16, UITheme.MUTED))


func _slide_win_lose() -> void:
	_heading("goals", "Как выиграть и как проиграть")
	var cols := UITheme.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(cols)
	# победа: шесть этапов роста
	var win := UITheme.card(14, Color(0.56, 0.81, 0.47, 0.07), Color(0.56, 0.81, 0.47, 0.45))
	win.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wv := UITheme.vbox(5)
	win.add_child(wv)
	wv.add_child(UITheme.label("Победа: вырасти до завода", 17, UITheme.GOOD, UITheme.f_semi))
	for i in Progress.STAGE_COUNT:
		var r := UITheme.hbox(8)
		var n := UITheme.chip(str(i + 1), UITheme.GOOD, "", i == 0)
		n.custom_minimum_size = Vector2(26, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.add_child(n)
		r.add_child(UITheme.label(sim.progress.stage_name(i + 1), 15, UITheme.TEXT))
		wv.add_child(r)
	wv.add_child(UITheme.para("Выполняйте цели этапа («Цели» вверху) — завод растёт, открываются станки и отделы.", 13, UITheme.MUTED))
	cols.add_child(win)
	# поражение: долги
	var lose := UITheme.card(14, Color(0.88, 0.4, 0.35, 0.07), Color(0.88, 0.4, 0.35, 0.45))
	lose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lv := UITheme.vbox(6)
	lose.add_child(lv)
	lv.add_child(UITheme.label("Поражение: долги и банкротство", 17, UITheme.BAD, UITheme.f_semi))
	lv.add_child(UITheme.para(tr("Нечем платить зарплату: сначала её задерживают, люди недовольны и уходят. Трое уволились за две недели — трудовая инспекция закрывает завод, игра окончена."), 14, UITheme.TEXT))
	lv.add_child(UITheme.para(tr("Если долг кассы дойдёт до %s, игра предупредит о долгах, но не оборвёт. Зарплату в долг выдают раз в три месяца.") % Defs.money_str(150000.0), 14, UITheme.MUTED))
	lv.add_child(UITheme.para("Держите запас денег на две зарплаты и не берите заказов больше, чем успеваете.", 14, UITheme.WARN))
	cols.add_child(lose)
