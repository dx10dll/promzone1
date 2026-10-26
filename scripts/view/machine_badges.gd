class_name MachineBadges
extends Node2D
## 1.49: значки проблем над станками — нет питания, нет оператора, нет заготовки, выход полон
## (и нейтральное «нет работы» только в слое «Загрузка станков»). Один слой на все станки; состояние
## считает StallBadges раз в полсекунды, перерисовка — только когда что-то изменилось.
## Размер значка на экране постоянный; по наведению — причина и что делать. Мышь не перехватывает.

const T := World.T
const PX := 22.0

const COLS := {"power": Color("#e0524a"), "operator": Color("#e0a63c"), "input": Color("#e0a63c"),
	"full": Color("#e0a63c"), "idle": Color("#9aa0a6"), "air": Color("#6fb4e0")}

var sim: Sim
var game: Node
var tracker := StallBadges.new()
var _sig := ""
var _hov := -1
var _items: Array = []
var mouse_override := Vector2(INF, INF)   ## для снимков: «мышь» стоит здесь


func _ready() -> void:
	z_index = 5


func _process(d: float) -> void:
	if sim == null:
		return
	var ch := tracker.tick(sim, d)
	var z := _zoom()
	_items = tracker.visible_list(_idle_on())
	var mp := get_global_mouse_position() if mouse_override.x == INF else mouse_override
	var hov := -1
	for r: Dictionary in _items:
		if _rect(r["m"] as Thing, z).grow(2.0 / z).has_point(mp):
			hov = (r["m"] as Thing).id
	var sig := "%d|%d|%s|%.2f" % [hov, int(_idle_on()), str(_items.size()), z]
	if ch or sig != _sig:
		_sig = sig
		_hov = hov
		queue_redraw()


func _zoom() -> float:
	return maxf(0.25, get_viewport().get_canvas_transform().get_scale().x)


func _idle_on() -> bool:
	return game != null and game.get("overlay") != null and str((game.get("overlay") as Node).get("mode")) == "load"


## Прямоугольник значка в мировых координатах: по центру станка, над его верхним краем.
func _rect(m: Thing, z: float) -> Rect2:
	var c := Vector2(m.rect().get_center().x * T, float(m.cell.y) * T)
	var s := PX / z
	return Rect2(c - Vector2(s * 0.5, s * 1.05), Vector2(s, s))


func _draw() -> void:
	if sim == null:
		return
	var z := _zoom()
	if z < 0.35:
		return
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var tip: Dictionary = {}
	for r: Dictionary in _items:
		var m := r["m"] as Thing
		if m.id == _hov:
			tip = r
			continue
		_icon(_rect(m, z), str(r["k"]), z, false)
	if not tip.is_empty():
		var rr := _rect(tip["m"] as Thing, z)
		_icon(rr, str(tip["k"]), z, true)
		_tip(rr, tip, z, f)


## Значок: тёмная плашка с рамкой цвета проблемы и простой глиф внутри (сетка 18×18).
func _icon(r: Rect2, k: String, z: float, hot: bool) -> void:
	var col: Color = COLS[k]
	draw_set_transform(r.position, 0.0, Vector2.ONE * (PX / 18.0 / z))   # глифы нарисованы на сетке 18×18
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.1, 0.11, 0.94)
	bg.border_color = col if not hot else col.lightened(0.35)
	bg.set_border_width_all(2 if hot else 1)
	bg.set_corner_radius_all(5)
	bg.anti_aliasing = true
	draw_style_box(bg, Rect2(0, 0, 18, 18))
	match k:
		"power":   # молния
			draw_colored_polygon(PackedVector2Array([Vector2(10.5, 2.5), Vector2(5, 10), Vector2(8.6, 10), Vector2(7.5, 15.5), Vector2(13, 7.8), Vector2(9.4, 7.8)]), col)
		"operator":   # человек с перечёркнутым кругом
			draw_circle(Vector2(9, 6.4), 2.5, col)
			draw_rect(Rect2(4.8, 10.2, 8.4, 3.6), col)
			draw_line(Vector2(3.5, 15), Vector2(14.5, 3), Color(0.09, 0.1, 0.11), 3.0)
			draw_line(Vector2(3.5, 15), Vector2(14.5, 3), Color("#e0524a"), 1.6)
		"input":   # пустой контур заготовки (пунктир) со стрелкой внутрь
			for i in 4:
				draw_line(Vector2(4.0 + i * 3.5, 4.5), Vector2(5.8 + i * 3.5, 4.5), col, 1.5)
				draw_line(Vector2(4.0 + i * 3.5, 13.5), Vector2(5.8 + i * 3.5, 13.5), col, 1.5)
			draw_line(Vector2(4, 6), Vector2(4, 12), col, 1.5)
			draw_line(Vector2(14, 6), Vector2(14, 12), col, 1.5)
			draw_line(Vector2(7, 9), Vector2(11, 9), col, 1.5)
		"air":   # облачко воздуха со стрелкой вниз: пусто
			draw_circle(Vector2(7, 8), 3.2, col)
			draw_circle(Vector2(11, 7), 3.6, col)
			draw_circle(Vector2(9, 10.5), 3.2, col)
			draw_line(Vector2(3.5, 15), Vector2(14.5, 3), Color(0.09, 0.1, 0.11), 3.0)
			draw_line(Vector2(3.5, 15), Vector2(14.5, 3), Color("#e0524a"), 1.6)
		"full":   # стопка деталей
			draw_rect(Rect2(4, 11, 10, 3.6), col)
			draw_rect(Rect2(4, 7, 10, 3.2), col.darkened(0.15))
			draw_rect(Rect2(4, 3.4, 10, 3.2), col.darkened(0.3))
		_:   # нейтральная пауза
			draw_rect(Rect2(5.5, 4.5, 2.6, 9), col)
			draw_rect(Rect2(10, 4.5, 2.6, 9), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tip(r: Rect2, it: Dictionary, z: float, f: Font) -> void:
	var head := StallBadges.title(str(it["k"]))
	var why := str(it["why"])
	var hint := str(it["hint"])
	var px := 11
	var tw := maxf(f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, px + 1).x, 0.0)
	var lines := _wrap(f, hint, px, 230.0)
	for ln: String in lines:
		tw = maxf(tw, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	var m := it["m"] as Thing
	var title := "%s — %s" % [m.title(), why] if why != head else m.title()
	tw = maxf(tw, f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	var w := tw + 16.0
	var h := 8.0 + 15.0 * (2 + lines.size()) + 2.0
	draw_set_transform(r.position + Vector2(r.size.x * 0.5, r.size.y + 3.0 / z), 0.0, Vector2.ONE / z)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.07, 0.92)
	bg.border_color = Color(COLS[str(it["k"])], 0.7)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	draw_style_box(bg, Rect2(-w * 0.5, 0, w, h))
	draw_string(f, Vector2(-w * 0.5 + 8, 15), head, HORIZONTAL_ALIGNMENT_LEFT, -1, px + 1, COLS[str(it["k"])].lightened(0.2))
	draw_string(f, Vector2(-w * 0.5 + 8, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.93, 0.9, 0.82))
	for i in lines.size():
		draw_string(f, Vector2(-w * 0.5 + 8, 45 + 15 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.75, 0.75, 0.72))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _wrap(f: Font, s: String, px: int, maxw: float) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for wd in s.split(" "):
		var t := wd if cur == "" else cur + " " + wd
		if cur != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > maxw:
			out.append(cur)
			cur = wd
		else:
			cur = t
	if cur != "":
		out.append(cur)
	return out
