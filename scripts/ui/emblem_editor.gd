class_name EmblemEditor
extends HBoxContainer
## 1.17: «Ваш завод» — название и эмблема из формы, знака, цветов и букв. Используется в окне новой игры
## и в паспорте завода (щелчок по эмблеме в шапке). data = {"name": "...", "emblem": {...}} меняется на месте.

signal changed

var data: Dictionary
var ooo := false
var profile := ""
var preview: Emblem.View
var title_lbl: Label
var name_edit: LineEdit
var text_edit: LineEdit
var _shape_btns := {}
var _sym_btns := {}
var _sw := {"bg": {}, "fg": {}, "rim": {}}
var _rng := RandomNumberGenerator.new()
var sign_prev: Control


func _init(d: Dictionary, is_ooo: bool = false, prof: String = "") -> void:
	data = d
	ooo = is_ooo
	profile = prof
	_rng.randomize()
	if not data.has("emblem") or not (data["emblem"] is Dictionary) or (data["emblem"] as Dictionary).is_empty():
		data["emblem"] = Company.random_emblem(_rng, profile)
	if str(data.get("name", "")) == "":
		data["name"] = Company.random_name(_rng)
	add_theme_constant_override("separation", 22)
	_build()
	_refresh()


func _em() -> Dictionary:
	return data["emblem"]


func _build() -> void:
	# слева — крупно, как будет на вывеске
	var left := UITheme.vbox(10)
	left.custom_minimum_size = Vector2(230, 0)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.sb(Color(0.06, 0.07, 0.08, 0.9), UITheme.LINE, 1, 10, 20, 18))
	preview = Emblem.View.new(_em(), 170.0)
	frame.add_child(preview)
	left.add_child(frame)
	title_lbl = UITheme.label("", 17, UITheme.TEXT, UITheme.f_semi)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(230, 0)
	left.add_child(title_lbl)
	var rb := UITheme.button("Случайная эмблема", func() -> void:
		var keep := str(_em().get("text", ""))
		data["emblem"] = Company.random_emblem(_rng, profile)
		_em()["text"] = keep
		_refresh(), "Подобрать форму, знак и цвета наугад")
	left.add_child(rb)
	var note := UITheme.label("Эмблема — в шапке, на вывеске у ворот, в многотиражке и на табличках в цехе.", 12, UITheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(230, 0)
	left.add_child(note)
	add_child(left)
	# справа — настройки
	var right := UITheme.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_cap("Название"))
	var nh := UITheme.hbox(6)
	name_edit = LineEdit.new()
	name_edit.max_length = Company.MAX_NAME
	name_edit.text = str(data.get("name", ""))
	name_edit.placeholder_text = "Например, Прогресс"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(0, 34)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.text_changed.connect(func(t: String) -> void:
		data["name"] = t
		_refresh_title()
		changed.emit())
	nh.add_child(name_edit)
	nh.add_child(UITheme.button("Случайно", func() -> void:
		data["name"] = Company.random_name(_rng)
		name_edit.text = str(data["name"])
		_refresh_title()
		changed.emit(), "Случайное название"))
	right.add_child(nh)
	right.add_child(_cap("Форма"))
	var sr := UITheme.hbox(6)
	for sh: Array in Company.SHAPES:
		var key := str(sh[0])
		var b := _emblem_button(str(sh[1]), 40.0)
		b.pressed.connect(func() -> void:
			_em()["shape"] = key
			_refresh())
		_shape_btns[key] = b
		sr.add_child(b)
	right.add_child(sr)
	right.add_child(_cap("Знак"))
	var sg := GridContainer.new()
	sg.columns = 6
	sg.add_theme_constant_override("h_separation", 6)
	sg.add_theme_constant_override("v_separation", 6)
	for sy: Array in Company.SYMBOLS:
		var key2 := str(sy[0])
		var b2 := _emblem_button(str(sy[1]), 40.0)
		b2.pressed.connect(func() -> void:
			_em()["symbol"] = key2
			if key2 == "letters" and str(_em().get("text", "")) == "":
				_em()["text"] = Company.initials(str(data.get("name", "")))
				text_edit.text = str(_em()["text"])
			_refresh())
		_sym_btns[key2] = b2
		sg.add_child(b2)
	right.add_child(sg)
	var th := UITheme.hbox(8)
	th.add_child(UITheme.label("Буквы на эмблеме", 13, UITheme.MUTED))
	text_edit = LineEdit.new()
	text_edit.max_length = 3
	text_edit.text = str(_em().get("text", ""))
	text_edit.placeholder_text = Company.initials(str(data.get("name", "")))
	text_edit.custom_minimum_size = Vector2(70, 30)
	text_edit.tooltip_text = "До трёх букв — для знака «Буквы»"
	text_edit.text_changed.connect(func(t: String) -> void:
		_em()["text"] = t.to_upper()
		if t != "":
			_em()["symbol"] = "letters"
		_refresh())
	th.add_child(text_edit)
	right.add_child(th)
	right.add_child(_palette("Фон", "bg", Company.BG))
	right.add_child(_palette("Знак", "fg", Company.FG))
	right.add_child(_palette("Кайма", "rim", Company.FG + ["#8a6d2f", "#2b2f33"]))
	right.add_child(_cap("Так будет на вывеске у ворот"))
	sign_prev = SignPreview.new()
	sign_prev.ed = self
	right.add_child(sign_prev)
	add_child(right)


func _cap(t: String) -> Label:
	return UITheme.label(t, 14, UITheme.TEXT, UITheme.f_semi)


func _emblem_button(tip: String, px: float) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(px + 10, px + 10)
	# 1.21: свои фоны во всех состояниях — без белой вспышки при нажатии
	var n := UITheme.sb(Color(1, 1, 1, 0.04), UITheme.LINE, 1, 7, 0, 0)
	var hv := UITheme.sb(Color(1, 1, 1, 0.09), UITheme.LINE2, 1, 7, 0, 0)
	var pr := UITheme.sb(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.18), UITheme.ACCENT, 2, 7, 0, 0)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	var v := Emblem.View.new({}, px)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 5
	v.offset_top = 5
	v.offset_right = -5
	v.offset_bottom = -5
	b.add_child(v)
	b.set_meta("view", v)
	return b


func _palette(cap: String, key: String, cols: Array) -> HBoxContainer:
	var h := UITheme.hbox(5)
	var l := UITheme.label(cap, 13, UITheme.MUTED)
	l.custom_minimum_size = Vector2(56, 0)
	h.add_child(l)
	for c in cols:
		var hex := str(c)
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(26, 26)
		b.tooltip_text = hex
		var col := Color(hex)
		b.add_theme_stylebox_override("normal", UITheme.sb(col, col.darkened(0.35), 1, 5, 0, 0))
		b.add_theme_stylebox_override("hover", UITheme.sb(col, Color(1, 1, 1, 0.7), 2, 5, 0, 0))
		b.add_theme_stylebox_override("pressed", UITheme.sb(col, UITheme.ACCENT, 3, 5, 0, 0))
		b.add_theme_stylebox_override("hover_pressed", UITheme.sb(col, UITheme.ACCENT, 3, 5, 0, 0))
		b.add_theme_stylebox_override("focus", UITheme.sb(col, col.darkened(0.35), 1, 5, 0, 0))
		b.pressed.connect(func() -> void:
			_em()[key] = hex
			_refresh())
		(_sw[key] as Dictionary)[hex] = b
		h.add_child(b)
	return h


func _refresh_title() -> void:
	var n := Company.clean_name(str(data.get("name", "")))
	title_lbl.text = (("ООО «%s»" if ooo else "Мастерская «%s»") % n) if n != "" else "Без названия"
	text_edit.placeholder_text = Company.initials(n)
	if sign_prev:
		sign_prev.queue_redraw()


func _refresh() -> void:
	var em := _em()
	preview.set_spec(em)
	for k in _shape_btns.keys():
		var b: Button = _shape_btns[k]
		var s := em.duplicate()
		s["shape"] = k
		(b.get_meta("view") as Emblem.View).set_spec(s)
		b.set_pressed_no_signal(str(em.get("shape", "")) == str(k))
	for k2 in _sym_btns.keys():
		var b2: Button = _sym_btns[k2]
		var s2 := em.duplicate()
		s2["symbol"] = k2
		if k2 == "letters" and str(s2.get("text", "")) == "":
			s2["text"] = "А"
		(b2.get_meta("view") as Emblem.View).set_spec(s2)
		b2.set_pressed_no_signal(str(em.get("symbol", "")) == str(k2))
	for key in _sw.keys():
		for hex in (_sw[key] as Dictionary).keys():
			((_sw[key] as Dictionary)[hex] as Button).set_pressed_no_signal(str(em.get(key, "")) == str(hex))
	_refresh_title()
	changed.emit()


## Предпросмотр вывески над воротами.
class SignPreview:
	extends Control
	var ed: EmblemEditor

	func _init() -> void:
		custom_minimum_size = Vector2(440, 86)

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), Vector2(minf(size.x - 8.0, 440.0), 74))
		draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.3))
		draw_rect(r, Color("#8a9399"))
		var inner := r.grow(-5.0)
		draw_rect(inner, Color("#1d2a38"))
		var n := Company.clean_name(str(ed.data.get("name", "")))
		Emblem.draw_sign_plate(self, inner, ed.data["emblem"], n if n != "" else "Без названия", "ООО" if ed.ooo else "МАСТЕРСКАЯ")
