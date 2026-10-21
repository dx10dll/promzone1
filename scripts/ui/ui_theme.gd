class_name UITheme
extends RefCounted
## Тема интерфейса и маленькие помощники для сборки окон кодом.

## Палитра 1.7.5: глубокий графит, тёплый текст, янтарный акцент «промышленной безопасности».
## 1.30: под новые значки владельца — графит чуть теплее и нейтральнее (без синевы), текст кремовый.
const BG := Color("#1c1d1f")          ## фон окон
const BG2 := Color("#242527")         ## карточки, строки
const BG3 := Color("#2e2f32")         ## кнопки, поля
const BG4 := Color("#3a3b3e")         ## наведение
const LINE := Color("#3a3b3d")
const LINE2 := Color("#4a4b4e")
const TEXT := Color("#ece4d0")
const MUTED := Color("#a39e93")
const DIM := Color("#77746d")
## 1.30: цвета значков меню — кремовый, кирпичный, оливковый; панели HUD — тёмный графит.
const CREAM := Color("#e6dcc5")
const BRICK := Color("#c8492f")       ## «включено» на панелях HUD (вместо янтаря)
const BRICK_L := Color("#e0705a")     ## кирпичный текст на тёмном — читается лучше
const OLIVE := Color("#8a9358")
const PANEL := Color(0.106, 0.108, 0.112, 0.96)   ## фон верхней/нижней панели, слоёв, списка дел
const ACCENT := Color("#e0a83a")      ## выбранное, главное действие
const ACCENT_D := Color("#b9862a")
const ACCENT_T := Color("#1b1d20")    ## текст на янтарном
const ACCENT2 := Color("#8fcf78")     ## (старое имя) — «хорошо»
const WARN := Color("#e0aa48")
const BAD := Color("#e0675a")
const GOOD := Color("#8fcf78")
const INFO := Color("#7fb6d8")
const RADIUS := 8

static var theme: Theme
static var f_reg: Font
static var f_med: Font
static var f_semi: Font
static var f_caps: Font   ## полужирный с разрядкой — для надписей капсом (бланки, таблички)


static func sb(bg: Color, border: Color, bw: int = 1, radius: int = 6, mx: int = 10, my: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.anti_aliasing = true
	return s


## То же с мягкой тенью — окна, подсказки и кнопки «приподняты» над картой.
static func sbs(bg: Color, border: Color, bw: int, radius: int, mx: int, my: int, sh: int, sh_a: float = 0.4, sh_y: int = 3) -> StyleBoxFlat:
	var s := sb(bg, border, bw, radius, mx, my)
	s.shadow_size = sh
	s.shadow_color = Color(0, 0, 0, sh_a)
	s.shadow_offset = Vector2(0, sh_y)
	return s


static func build() -> Theme:
	if theme:
		return theme
	f_reg = load("res://assets/fonts/IBMPlexSans-Regular.ttf")
	f_med = load("res://assets/fonts/IBMPlexSans-Medium.ttf")
	f_semi = load("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
	# 1.24: в IBM Plex нет ★ ▲ ⚠ ✗ ● и других значков — берём их из маленького запасного шрифта
	# (выборка DejaVu Sans), иначе на части компьютеров вместо них были квадратики
	var sym: Font = load("res://assets/fonts/SymbolsFallback.ttf")
	for f: Font in [f_reg, f_med, f_semi]:
		f.fallbacks = [sym]
	var fv := FontVariation.new()
	fv.base_font = f_semi
	fv.spacing_glyph = 1
	f_caps = fv
	var t := Theme.new()
	t.default_font = f_reg
	t.default_font_size = 14
	t.set_stylebox("panel", "PanelContainer", sbs(BG, LINE, 1, 10, 12, 10, 16, 0.5, 6))
	t.set_stylebox("panel", "Panel", sb(BG, LINE, 1, RADIUS))
	# кнопки: спокойные, выбранная — янтарная
	t.set_stylebox("normal", "Button", sb(BG3, LINE2, 1, RADIUS - 1, 11, 5))
	t.set_stylebox("hover", "Button", sb(BG4, Color("#625f59"), 1, RADIUS - 1, 11, 5))
	t.set_stylebox("pressed", "Button", sb(ACCENT, ACCENT, 1, RADIUS - 1, 11, 5))
	t.set_stylebox("hover_pressed", "Button", sb(Color("#ecb84c"), Color("#ecb84c"), 1, RADIUS - 1, 11, 5))
	t.set_stylebox("disabled", "Button", sb(Color("#212123"), Color("#2e2e30"), 1, RADIUS - 1, 11, 5))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT_T)
	t.set_color("font_hover_pressed_color", "Button", ACCENT_T)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("icon_normal_color", "Button", TEXT)
	t.set_color("icon_pressed_color", "Button", ACCENT_T)
	t.set_color("icon_hover_pressed_color", "Button", ACCENT_T)
	t.set_color("icon_disabled_color", "Button", DIM)
	t.set_constant("h_separation", "Button", 7)
	t.set_font_size("font_size", "Button", 14)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", sb(Color("#161718"), LINE2, 1, RADIUS - 2, 9, 5))
	t.set_stylebox("focus", "LineEdit", sb(Color("#161718"), ACCENT, 1, RADIUS - 2, 9, 5))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("background", "ProgressBar", sb(Color("#131415"), Color("#131415"), 0, 4, 0, 0))
	t.set_stylebox("fill", "ProgressBar", sb(GOOD, GOOD, 0, 4, 0, 0))
	t.set_stylebox("panel", "TooltipPanel", sbs(Color("#121213"), LINE2, 1, 8, 11, 8, 10, 0.55, 4))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_stylebox("panel", "TabContainer", sb(BG, LINE, 1, RADIUS, 10, 10))
	t.set_stylebox("tab_selected", "TabContainer", sb(ACCENT, ACCENT, 1, RADIUS - 2, 12, 5))
	t.set_stylebox("tab_unselected", "TabContainer", sb(BG3, LINE, 1, RADIUS - 2, 12, 5))
	t.set_stylebox("tab_hovered", "TabContainer", sb(BG4, LINE2, 1, RADIUS - 2, 12, 5))
	t.set_color("font_selected_color", "TabContainer", ACCENT_T)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_stylebox("separator", "HSeparator", sb(LINE, LINE, 0, 0, 0, 0))
	t.set_constant("separation", "HSeparator", 10)
	t.set_stylebox("separator", "VSeparator", sb(LINE, LINE, 0, 0, 0, 0))
	t.set_constant("separation", "VSeparator", 10)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckBox", sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 2, 3))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true))
	t.set_icon("radio_checked", "CheckBox", _check_icon(true))
	t.set_icon("radio_unchecked", "CheckBox", _check_icon(false))
	t.set_constant("h_separation", "CheckBox", 8)
	t.set_stylebox("panel", "PopupPanel", sbs(BG, LINE2, 1, RADIUS, 10, 10, 12, 0.5, 4))
	t.set_stylebox("panel", "PopupMenu", sbs(Color("#171819"), LINE2, 1, RADIUS, 6, 6, 12, 0.5, 4))
	t.set_stylebox("hover", "PopupMenu", sb(BG4, BG4, 0, 5, 6, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", 14)
	t.set_constant("v_separation", "PopupMenu", 8)
	# выпадающие списки
	t.set_stylebox("normal", "OptionButton", sb(BG3, LINE2, 1, RADIUS - 1, 11, 5))
	t.set_stylebox("hover", "OptionButton", sb(BG4, Color("#625f59"), 1, RADIUS - 1, 11, 5))
	t.set_stylebox("pressed", "OptionButton", sb(BG4, ACCENT, 1, RADIUS - 1, 11, 5))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "OptionButton", TEXT)
	t.set_color("font_hover_pressed_color", "OptionButton", TEXT)
	# полосы прокрутки — тонкие
	var grab := sb(Color("#4f4e4c"), Color("#4f4e4c"), 0, 4, 0, 0)
	var grab_h := sb(Color("#66645f"), Color("#66645f"), 0, 4, 0, 0)
	var track := sb(Color(0, 0, 0, 0.18), Color(0, 0, 0, 0), 0, 4, 0, 0)
	for cls2 in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls2, track)
		t.set_stylebox("grabber", cls2, grab)
		t.set_stylebox("grabber_highlight", cls2, grab_h)
		t.set_stylebox("grabber_pressed", cls2, grab_h)
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 6)
	for cls in ["CheckButton"]:
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, UITheme.GOOD)
		t.set_color("font_hover_pressed_color", cls, UITheme.GOOD)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(st, cls, StyleBoxEmpty.new())
	theme = t
	return t


## Значок галочки для CheckBox: квадрат со скруглением, отмеченный — янтарный с галкой.
static func _check_icon(on: bool, disabled: bool = false) -> Texture2D:
	var sz := 18
	var img := Image.create(sz * 2, sz * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := 2
	var fill := ACCENT if on else Color("#161718")
	var edge := ACCENT if on else LINE2
	if disabled:
		fill = fill.darkened(0.45)
		edge = edge.darkened(0.3)
	var r := 4 * k
	for y in sz * k:
		for x in sz * k:
			var dx := maxi(maxi(r - x, x - (sz * k - 1 - r)), 0)
			var dy := maxi(maxi(r - y, y - (sz * k - 1 - r)), 0)
			var d := sqrt(float(dx * dx + dy * dy))
			if d > r:
				continue
			var a := clampf(float(r) - d + 0.5, 0.0, 1.0)
			var c := edge if (x < 2 * k or y < 2 * k or x >= sz * k - 2 * k or y >= sz * k - 2 * k or d > r - 2 * k) else fill
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	if on:
		var pts := [Vector2(4.5, 9.5), Vector2(7.5, 12.5), Vector2(13.5, 5.5)]
		for i in 2:
			var a0: Vector2 = pts[i] * k
			var b0: Vector2 = pts[i + 1] * k
			var n := int(a0.distance_to(b0) * 2.0)
			for j in n + 1:
				var p := a0.lerp(b0, float(j) / maxf(1.0, float(n)))
				for oy in range(-k - 1, k + 2):
					for ox in range(-k - 1, k + 2):
						var q := Vector2i(int(p.x) + ox, int(p.y) + oy)
						if q.x >= 0 and q.y >= 0 and q.x < sz * k and q.y < sz * k and Vector2(ox, oy).length() <= k + 0.6:
							img.set_pixelv(q, ACCENT_T)
	img.resize(sz, sz, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 15, col: Color = TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size: int = 20) -> Label:
	return label(text, size, TEXT, f_semi)


static func button(text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## 1.30: значки меню, нарисованные владельцем игры (assets/ui/icons, 128 px с mip-уровнями):
## цветные, без перекраски — показываем «как есть», состояние кнопки рисует сама кнопка.
static var _micons: Dictionary = {}


static func micon(id: String) -> Texture2D:
	if _micons.has(id):
		return _micons[id]
	var path := "res://assets/ui/icons/%s.png" % id
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_micons[id] = t
	return t


## Кнопка-значок с цветной иконкой меню: значок не перекрашивается, неактивная — полупрозрачная.
static func micon_colors(b: Button) -> void:
	for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))


static func icon_button(icon: String, text: String, cb: Callable, tip: String = "") -> Button:
	var b := button(text, cb, tip)
	b.icon = Tex.ui(icon)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 26 if Tex.is_color(b.icon) else 22)
	icon_colors(b)
	return b


## 1.38: у кнопки цветной значок владельца — не перекрашивать (как micon_colors).
static func icon_colors(b: Button) -> void:
	if Tex.is_color(b.icon):
		micon_colors(b)


## 1.38: значок-картинка с цветом: цветной PNG — белым (только прозрачность), векторный — цветом.
static func tint_icon(r: CanvasItem, t: Texture2D, col: Color) -> void:
	r.modulate = Tex.tint(t, col)


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func panel(bg: Color = BG, border: Color = LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, 1, 8, 12, 10))
	return p


static func bar(value: float, col: Color, w: float = 90.0, h: float = 10.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = 100
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(w, h)
	pb.add_theme_stylebox_override("fill", sb(col, col, 0, 3, 0, 0))
	return pb


static func clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


# ---------------------------------------------------------------- компоненты 1.7.5

## Карточка: тёмная панель со скруглением, внутри — вертикальный список.
static func card(pad: int = 12, bg: Color = BG2, border: Color = LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, 1, RADIUS, pad, pad - 2))
	return p


## Заголовок раздела: КАПСОМ, мелко, приглушённо — как в современных панелях.
static func caption(text: String, col: Color = MUTED) -> Label:
	var l := label(text.to_upper(), 11, col, f_caps if f_caps else f_semi)
	return l


## Плитка показателя: подпись, крупное значение, необязательная строка ниже.
static func stat(cap: String, value: String, col: Color = TEXT, sub: String = "", sub_col: Color = MUTED, tip: String = "") -> PanelContainer:
	var p := card(12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_STOP if tip != "" else Control.MOUSE_FILTER_IGNORE
	var v := vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(caption(cap))
	var vl := label(value, 20, col, f_semi)
	v.add_child(vl)
	if sub != "":
		v.add_child(label(sub, 12, sub_col))
	return p


## Цветная «пилюля» со статусом.
static func chip(text: String, col: Color = MUTED, tip: String = "", filled: bool = false) -> Label:
	var l := label(text, 12, ACCENT_T if filled else col, f_semi)
	var bgc := col if filled else Color(col.r, col.g, col.b, 0.13)
	l.add_theme_stylebox_override("normal", sb(bgc, Color(col.r, col.g, col.b, 0.0 if filled else 0.35), 1, 9, 8, 1))
	l.tooltip_text = tip
	if tip != "":
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return l


## Счётчик-бейдж (на кнопках).
static func badge(text: String, col: Color = BAD) -> Label:
	var l := label(text, 11, Color.WHITE, f_semi)
	l.add_theme_stylebox_override("normal", sb(col, col, 0, 8, 5, 0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Главная кнопка действия (янтарная).
static func primary(text: String, cb: Callable, tip: String = "") -> Button:
	var b := button(text, cb, tip)
	b.add_theme_stylebox_override("normal", sb(ACCENT, ACCENT, 1, RADIUS - 1, 12, 5))
	b.add_theme_stylebox_override("hover", sb(Color("#ecb84c"), Color("#ecb84c"), 1, RADIUS - 1, 12, 5))
	b.add_theme_stylebox_override("disabled", sb(Color("#4a3f2a"), Color("#4a3f2a"), 1, RADIUS - 1, 12, 5))
	b.add_theme_color_override("font_color", ACCENT_T)
	b.add_theme_color_override("font_hover_color", ACCENT_T)
	b.add_theme_color_override("font_disabled_color", Color("#8a7a5a"))
	b.add_theme_font_override("font", f_semi)
	return b


## Тихая кнопка без рамки (ссылка-действие).
static func ghost(text: String, cb: Callable, tip: String = "", col: Color = INFO) -> Button:
	var b := button(text, cb, tip)
	b.flat = true
	var e := sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, RADIUS - 1, 6, 3)
	b.add_theme_stylebox_override("normal", e)
	b.add_theme_stylebox_override("hover", sb(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, RADIUS - 1, 6, 3))
	b.add_theme_stylebox_override("pressed", e)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", col)
	return b


## Маленькая кнопка — для строк таблиц.
static func small(text: String, cb: Callable, tip: String = "") -> Button:
	var b := button(text, cb, tip)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", sb(BG3, LINE2, 1, 6, 8, 2))
	b.add_theme_stylebox_override("hover", sb(BG4, Color("#625f59"), 1, 6, 8, 2))
	b.add_theme_stylebox_override("pressed", sb(ACCENT, ACCENT, 1, 6, 8, 2))
	b.add_theme_stylebox_override("disabled", sb(Color("#212123"), Color("#2e2e30"), 1, 6, 8, 2))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## Сегментированный переключатель: [[ключ, текст, подсказка]], выбранный — янтарный.
static func segmented(items: Array, current: String, cb: Callable) -> HBoxContainer:
	var h := hbox(0)
	var g := ButtonGroup.new()
	for i in items.size():
		var it: Array = items[i]
		var b := Button.new()
		b.text = str(it[1])
		b.tooltip_text = str(it[2]) if it.size() > 2 else ""
		b.toggle_mode = true
		b.button_group = g
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = str(it[0]) == current
		var first := i == 0
		var last := i == items.size() - 1
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var base: StyleBoxFlat = (UITheme.theme.get_stylebox(st, "Button") as StyleBoxFlat).duplicate() if UITheme.theme else sb(BG3, LINE2, 1, RADIUS - 1, 11, 5)
			base.corner_radius_top_left = RADIUS - 1 if first else 0
			base.corner_radius_bottom_left = RADIUS - 1 if first else 0
			base.corner_radius_top_right = RADIUS - 1 if last else 0
			base.corner_radius_bottom_right = RADIUS - 1 if last else 0
			base.content_margin_top = 3
			base.content_margin_bottom = 3
			b.add_theme_stylebox_override(st, base)
		b.add_theme_font_size_override("font_size", 13)
		var key := str(it[0])
		b.pressed.connect(func() -> void: cb.call(key))
		h.add_child(b)
	return h


## Значок «?» с подсказкой — объяснения не занимают место на экране.
static func help(text: String) -> Label:
	var l := label("?", 12, MUTED, f_semi)
	l.add_theme_stylebox_override("normal", sb(BG3, LINE2, 1, 9, 6, 0))
	l.tooltip_text = text
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_default_cursor_shape = Control.CURSOR_HELP
	return l


## Тонкая полоса прогресса с подписью справа.
static func meter(value: float, col: Color, w: float = 120.0, txt: String = "") -> HBoxContainer:
	var h := hbox(6)
	var pb := bar(value, col, w, 6)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pb)
	if txt != "":
		h.add_child(label(txt, 12, MUTED))
	return h


## Сетка в N колонок с одинаковой шириной ячеек.
static func grid(cols: int, hsep: int = 10, vsep: int = 10) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", hsep)
	g.add_theme_constant_override("v_separation", vsep)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


## Пустое состояние: значок и пояснение по центру.
static func empty(text: String) -> Control:
	var c := CenterContainer.new()
	c.custom_minimum_size = Vector2(0, 120)
	var l := label(text, 14, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	c.add_child(l)
	return c


## Текст с переносом (растягивается по ширине).
static func para(text: String, size: int = 13, col: Color = MUTED) -> Label:
	var l := label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Строка таблицы: панель-подложка с наведением; внутри — HBox.
static func row(h: int = 40) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(BG2, Color(0, 0, 0, 0), 0, 6, 10, 4))
	p.custom_minimum_size = Vector2(0, h)
	return p


## Цвет по доле 0–1: красный → жёлтый → зелёный.
static func ramp(v: float) -> Color:
	if v < 0.35:
		return BAD
	if v < 0.65:
		return WARN
	return GOOD
