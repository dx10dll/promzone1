class_name ChartView
extends Control
## Небольшой график для окон: линии и/или столбики, сетка с подписями, значения под курсором.
## Рисуется кодом — чёткий при любом масштабе интерфейса.

var series: Array = []      ## [{name, color: Color, values: Array, kind: "line"|"bar"}]
var labels: Array = []      ## подписи по оси X (по одной на точку)
var fmt := "num"            ## money | pct | idx | num — формат чисел на оси и в подсказке
var zero_based := true      ## ось Y от нуля (для денег и долей), иначе — по данным
var hover := -1

const PAD_L := 54.0
const PAD_B := 18.0
const PAD_T := 8.0
const PAD_R := 10.0


func _init() -> void:
	custom_minimum_size = Vector2(280, 170)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(s: Array, lab: Array, f: String = "num", zb: bool = true) -> ChartView:
	series = s
	labels = lab
	fmt = f
	zero_based = zb
	queue_redraw()
	return self


func _count() -> int:
	var n := labels.size()
	for s: Dictionary in series:
		n = maxi(n, (s["values"] as Array).size())
	return n


func _range() -> Vector2:
	var lo := INF
	var hi := -INF
	for s: Dictionary in series:
		for v in s["values"]:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	if lo == INF:
		return Vector2(0, 1)
	if zero_based:
		lo = minf(lo, 0.0)
		hi = maxf(hi, 0.0)
	if hi - lo < 0.0001:
		hi = lo + (absf(lo) * 0.1 + 1.0)
		if not zero_based:
			lo -= absf(lo) * 0.1 + 1.0
	# «круглый» шаг сетки: 1, 2, 2.5, 5 × 10ⁿ
	var raw := (hi - lo) / 4.0
	var mag := pow(10.0, floorf(log(raw) / log(10.0)))
	var st := mag * 10.0
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= m * mag:
			st = m * mag
			break
	_step = st
	return Vector2(floorf(lo / st) * st, ceilf(hi / st) * st)


var _step := 1.0


## Подпись деления оси: знаков после запятой — сколько нужно для шага сетки.
func _tick(v: float) -> String:
	var dec := func(step: float) -> int: return clampi(int(ceilf(-log(step) / log(10.0) - 0.0001)), 0, 3)
	match fmt:
		"money":
			var a := absf(v)
			var sg := "−" if v < -0.0001 else ""
			if a >= 1000000.0 or _step >= 1000000.0:
				return tr("%s млн") % (("%s%." + str(dec.call(_step / 1000000.0)) + "f") % [sg, a / 1000000.0])
			if a >= 1000.0 or _step >= 1000.0:
				return tr("%s тыс.") % (("%s%." + str(dec.call(_step / 1000.0)) + "f") % [sg, a / 1000.0])
			return "%s%d ₽" % [sg, int(roundf(a))]
		"pct":
			return ("%." + str(dec.call(_step * 100.0)) + "f%%") % (v * 100.0)
	return ("%." + str(dec.call(_step)) + "f") % v


func _plot() -> Rect2:
	return Rect2(PAD_L, PAD_T, maxf(10.0, size.x - PAD_L - PAD_R), maxf(10.0, size.y - PAD_T - PAD_B))


static func fmt_val(v: float, f: String) -> String:
	match f:
		"money":
			var a := absf(v)
			var sg := "−" if v < 0.0 else ""
			if a >= 1000000.0:
				return L.t("%s%.1f млн") % [sg, a / 1000000.0]
			if a >= 1000.0:
				return L.t("%s%d тыс.") % [sg, int(roundf(a / 1000.0))]
			return "%s%d ₽" % [sg, int(roundf(a))]
		"pct":
			return "%d%%" % int(roundf(v * 100.0))
		"idx":
			return "%.2f" % v
	return str(int(roundf(v)))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var n := _count()
		if n <= 0:
			return
		var r := _plot()
		var x := (e as InputEventMouseMotion).position.x
		var i := clampi(int(roundf((x - r.position.x) / maxf(1.0, r.size.x) * float(maxi(1, n - 1)))), 0, n - 1)
		if _has_bars():
			i = clampi(int((x - r.position.x) / maxf(1.0, r.size.x) * float(n)), 0, n - 1)
		if i != hover:
			hover = i
			var parts: Array[String] = []
			if i < labels.size():
				parts.append(tr(str(labels[i])))
			for s: Dictionary in series:
				var vals: Array = s["values"]
				if i < vals.size():
					parts.append("%s: %s" % [tr(str(s["name"])), fmt_val(float(vals[i]), fmt)])
			tooltip_text = "\n".join(parts)
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = -1
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


func _has_bars() -> bool:
	for s: Dictionary in series:
		if str(s.get("kind", "line")) == "bar":
			return true
	return false


func _draw() -> void:
	var f: Font = UITheme.f_reg if UITheme.f_reg else get_theme_default_font()
	var r := _plot()
	var n := _count()
	var rg := _range()
	var lo := rg.x
	var hi := rg.y
	var ys := func(v: float) -> float: return r.position.y + r.size.y * (1.0 - (v - lo) / (hi - lo))
	# сетка
	var nt := int(roundf((hi - lo) / _step))
	for k in nt + 1:
		var v := lo + _step * float(k)
		var y: float = ys.call(v)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.06), 1.0)
		var t := _tick(v)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(f, Vector2(r.position.x - 6.0 - tw, y + 4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.DIM)
	if lo < 0.0 and hi > 0.0:
		var y0: float = ys.call(0.0)
		draw_line(Vector2(r.position.x, y0), Vector2(r.end.x, y0), Color(1, 1, 1, 0.18), 1.0)
	if n == 0:
		var e := tr("Данных пока нет — график появится через пару дней")
		var ew := f.get_string_size(e, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		if ew > r.size.x + 20.0:
			e = tr("Данных пока нет")   # узкая карточка
			ew = f.get_string_size(e, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(r.get_center().x - ew * 0.5, r.get_center().y), e, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.MUTED)
		return
	# подписи X: первая, середина, последняя
	if not labels.is_empty():
		for i in [0, int((n - 1) / 2), n - 1]:
			if i >= labels.size():
				continue
			var lt := tr(str(labels[i]))
			var lw := f.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var x := _x(i, n, r)
			x = clampf(x - lw * 0.5, r.position.x - 4.0, r.end.x - lw)
			draw_string(f, Vector2(x, size.y - 4.0), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.DIM)
	# столбики
	var bars := series.filter(func(s: Dictionary) -> bool: return str(s.get("kind", "line")) == "bar")
	if not bars.is_empty():
		var slot := r.size.x / float(n)
		var bw := maxf(1.0, slot * 0.8 / float(bars.size()))
		var y0b: float = ys.call(maxf(lo, 0.0))
		for bi in bars.size():
			var s: Dictionary = bars[bi]
			var col: Color = s["color"]
			var vals: Array = s["values"]
			for i in vals.size():
				var x0 := r.position.x + slot * i + slot * 0.1 + bw * bi
				var yv: float = ys.call(float(vals[i]))
				var c := col if hover < 0 or hover == i else Color(col, 0.55)
				draw_rect(Rect2(x0, minf(yv, y0b), bw - 1.0, maxf(1.0, absf(y0b - yv))), c)
	# линии
	for s2: Dictionary in series:
		if str(s2.get("kind", "line")) != "line":
			continue
		var vals2: Array = s2["values"]
		if vals2.is_empty():
			continue
		var col2: Color = s2["color"]
		var pts := PackedVector2Array()
		for i2 in vals2.size():
			pts.append(Vector2(_x(i2, n, r), ys.call(float(vals2[i2]))))
		if pts.size() == 1:
			draw_circle(pts[0], 3.0, col2)
		else:
			# заливка под главной линией
			if bool(s2.get("fill", false)):
				var poly := pts.duplicate()
				poly.append(Vector2(pts[pts.size() - 1].x, r.end.y))
				poly.append(Vector2(pts[0].x, r.end.y))
				draw_colored_polygon(poly, Color(col2, 0.10))
			draw_polyline(pts, col2, float(s2.get("width", 2.0)), true)
			draw_circle(pts[pts.size() - 1], 3.0, col2)
	# курсор
	if hover >= 0 and hover < n:
		var hx := _x(hover, n, r) if bars.is_empty() else r.position.x + r.size.x / float(n) * (hover + 0.5)
		draw_line(Vector2(hx, r.position.y), Vector2(hx, r.end.y), Color(1, 1, 1, 0.25), 1.0)
		for s3: Dictionary in series:
			var v3: Array = s3["values"]
			if str(s3.get("kind", "line")) == "line" and hover < v3.size():
				draw_circle(Vector2(hx, ys.call(float(v3[hover]))), 4.0, s3["color"])


func _x(i: int, n: int, r: Rect2) -> float:
	if _has_bars():
		return r.position.x + r.size.x / float(n) * (float(i) + 0.5)
	return r.position.x + r.size.x * (float(i) / float(maxi(1, n - 1)))
