class_name FactoryUI
extends RefCounted
## Заводские детали интерфейса: эмалевые таблички, отрывной календарь, предупредительная полоса,
## доска почёта. Всё рисуется кодом — чёткое при любом масштабе.

const ENAMEL := Color("#1f3f68")       ## синяя эмаль табличек
const ENAMEL_D := Color("#16304f")
const CREAM := Color("#efe8d4")        ## эмалевые буквы
const HONOR_RED := Color("#7d2620")    ## бархат доски почёта
const GOLD := Color("#d9b45a")


## Эмалевая табличка с заклёпками: «ЛЮДИ», «ПРОИЗВОДСТВО».
static func plate(text: String, icon: String = "", font_px: int = 15) -> PanelContainer:
	var p := Plate.new()
	var sb := UITheme.sbs(ENAMEL, CREAM.darkened(0.15), 2, 6, 16, 7, 4, 0.45, 2)
	sb.bg_color = ENAMEL
	p.add_theme_stylebox_override("panel", sb)
	var h := UITheme.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if icon != "":
		var ic := TextureRect.new()
		# 1.30: цветной значок из набора владельца, если есть (без перекраски); иначе прежний кремовый
		var mt := UITheme.micon(icon)
		ic.texture = mt if mt != null else Tex.ui(icon)
		ic.custom_minimum_size = Vector2(30, 30) if mt != null else Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Color.WHITE if mt != null else CREAM
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var l := UITheme.label(text.to_upper(), font_px, CREAM, UITheme.f_caps)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return p


class Plate extends PanelContainer:
	func _draw() -> void:
		# заклёпки по углам и блик на эмали
		for c in [Vector2(6, 6), Vector2(size.x - 6, 6), Vector2(6, size.y - 6), Vector2(size.x - 6, size.y - 6)]:
			draw_circle(c + Vector2(0, 0.6), 2.4, Color(0, 0, 0, 0.45))
			draw_circle(c, 2.2, Color("#b8bcc0"))
			draw_circle(c - Vector2(0.6, 0.6), 0.9, Color(1, 1, 1, 0.8))
		draw_line(Vector2(10, 4), Vector2(size.x * 0.55, 4), Color(1, 1, 1, 0.10), 2.0)


## Листок отрывного календаря: красная шапка с месяцем, крупное число.
class Sheet extends Control:
	var day := 1
	var month := "СЕНТ"
	var holiday := false

	func _init() -> void:
		custom_minimum_size = Vector2(28, 32)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var f: Font = UITheme.f_semi
		# тень и листки под верхним (стопка)
		draw_rect(Rect2(2, 3, w - 2, h - 2), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(1, 2, w - 2, h - 2), Color("#cfc8b6"))
		draw_rect(Rect2(0, 0, w - 2, h - 3), Color("#f4efe2"))
		var band := Color("#c23b2e")
		draw_rect(Rect2(0, 0, w - 2, 10), band)
		var fm := 7
		var mw := f.get_string_size(month, HORIZONTAL_ALIGNMENT_LEFT, -1, fm).x
		draw_string(f, Vector2((w - 2 - mw) * 0.5, 8), month, HORIZONTAL_ALIGNMENT_LEFT, -1, fm, Color("#fbeee8"))
		var ds := str(day)
		var fd := 15
		var dw := f.get_string_size(ds, HORIZONTAL_ALIGNMENT_LEFT, -1, fd).x
		draw_string(f, Vector2((w - 2 - dw) * 0.5, h - 7), ds, HORIZONTAL_ALIGNMENT_LEFT, -1, fd, band if holiday else Color("#22252a"))
		# кольца переплёта
		for x in [7.0, w - 9.0]:
			draw_circle(Vector2(x, 1), 1.6, Color("#5b6168"))


## Полоса «осторожно»: жёлто-чёрные диагонали.
class Hazard extends Control:
	var alpha := 0.9

	func _init() -> void:
		custom_minimum_size = Vector2(0, 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.08, alpha))
		var step := 12.0
		var x := -h
		var yel := Color("#e2b62e")
		yel.a = alpha
		while x < size.x + h:
			draw_colored_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + h, 0), Vector2(x + h + step * 0.5, 0), Vector2(x + step * 0.5, h)]), yel)
			x += step


## Рамка фото на доске почёта: фото для пропуска, табличка с фамилией и подписью.
static func honor_photo(w_look: Dictionary, age: int, mood: float, surname: String, first: String, why: String, big: bool = false) -> VBoxContainer:
	var v := UITheme.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.sbs(GOLD.darkened(0.25), GOLD, 2, 2, 4, 4, 6, 0.5, 3))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var por := Portrait.new()
	por.set_look(w_look, 1.3 if big else 1.05, {"age": age, "mood": mood, "doc": true, "wide": true})
	frame.add_child(por)
	v.add_child(frame)
	var nl := UITheme.label(surname.to_upper(), 13 if big else 12, CREAM, UITheme.f_caps)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	var fl := UITheme.label(first, 12, CREAM.darkened(0.2))
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(fl)
	var wl := UITheme.label(why, 11, GOLD)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.custom_minimum_size = Vector2(150, 0)
	v.add_child(wl)
	return v
