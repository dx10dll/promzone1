class_name Stamp
extends Control
## Резиновая печать или штамп: круглая (текст по кругу + строки в центре) или прямоугольная
## с двойной рамкой. Чернила полупрозрачные, слегка повёрнуты — как на настоящих документах.

var ring := ""                    ## текст по окружности (только у круглой)
var lines: PackedStringArray = [] ## строки в центре
var ink := Color("#5a4fcf")
var round_shape := true
var angle := -12.0                ## поворот, градусы
var font_px := 11


## Круглая печать отдела кадров, ОТК и т.п.
static func round_stamp(ring_text: String, center: PackedStringArray, col: Color = Color("#5a4fcf"), d: float = 64.0, ang: float = -12.0) -> Stamp:
	var s := Stamp.new()
	s.ring = ring_text
	s.lines = center
	s.ink = col
	s.round_shape = true
	s.angle = ang
	s.custom_minimum_size = Vector2(d, d)
	s.size = Vector2(d, d)
	s.font_px = int(clampf(d / 6.2, 8.0, 14.0))
	return s


## Ширина штампа под текст заданного кегля.
static func fit_w(text: String, px: int) -> float:
	var f: Font = UITheme.f_semi
	return (f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if f else text.length() * px * 0.62) + 22.0


## Прямоугольный штамп «ВЫПОЛНЕНО», «ПРИНЯТО ОТК».
static func box_stamp(text: PackedStringArray, col: Color = Color("#c0453a"), w: float = 120.0, h: float = 38.0, ang: float = -8.0) -> Stamp:
	var s := Stamp.new()
	s.lines = text
	s.ink = col
	s.round_shape = false
	s.angle = ang
	s.custom_minimum_size = Vector2(w, h)
	s.size = Vector2(w, h)
	s.font_px = int(clampf(h * 0.46 / maxf(1.0, float(text.size())), 8.0, 18.0))
	return s


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var f: Font = UITheme.f_semi if UITheme.f_semi else get_theme_default_font()
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var col := Color(ink.r, ink.g, ink.b, ink.a * 0.82)
	draw_set_transform(c, deg_to_rad(angle), Vector2.ONE)
	if round_shape:
		var r := minf(size.x, size.y) * 0.5 - 1.5
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, col, 2.0, true)
		draw_arc(Vector2.ZERO, r - 3.0, 0.0, TAU, 64, col, 0.9, true)
		var fpx := font_px
		var rt := r - 3.0 - float(fpx) * 0.72
		var widths: Array[float] = []
		var total := 0.0
		if ring != "":
			# кегль по кругу — чтобы надпись уместилась на окружности
			while fpx > 6:
				rt = r - 3.0 - float(fpx) * 0.72
				total = f.get_string_size(ring, HORIZONTAL_ALIGNMENT_LEFT, -1, fpx).x
				if total <= TAU * rt * 0.94:
					break
				fpx -= 1
			for ch in ring:
				widths.append(f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fpx).x)
		var ri := rt - float(fpx) * 0.72
		draw_arc(Vector2.ZERO, ri, 0.0, TAU, 48, col, 0.9, true)
		if ring != "":
			var span := TAU * 0.98
			var k := span / maxf(1.0, total) if total > TAU * rt * 0.7 else 1.0 / rt
			var a := -PI * 0.5 - total * k * 0.5
			for i in ring.length():
				var aw := widths[i] * k
				var mid := a + aw * 0.5
				var p := Vector2(cos(mid), sin(mid)) * rt
				draw_set_transform(c + p.rotated(deg_to_rad(angle)), mid + PI * 0.5 + deg_to_rad(angle), Vector2.ONE)
				draw_string(f, Vector2(-widths[i] * 0.5, float(fpx) * 0.36), ring[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fpx, col)
				a += aw
			draw_set_transform(c, deg_to_rad(angle), Vector2.ONE)
		_center_lines(f, col, ri * 1.7)
	else:
		var rect := Rect2(-size * 0.5 + Vector2(1.5, 1.5), size - Vector2(3, 3))
		draw_rect(rect, col, false, 2.2)
		draw_rect(rect.grow(-3.5), col, false, 1.0)
		_center_lines(f, col, rect.size.x - 10.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _center_lines(f: Font, col: Color, max_w: float) -> void:
	if lines.is_empty():
		return
	var lh := float(font_px) * 1.12
	var y0 := -lh * float(lines.size()) * 0.5 + float(font_px) * 0.86
	for i in lines.size():
		var fs := font_px
		var wl := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while wl > max_w and fs > 7:
			fs -= 1
			wl = f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(-wl * 0.5, y0 + lh * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
