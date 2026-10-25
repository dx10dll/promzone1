class_name NameLayer
extends Node2D
## Фамилии под людьми на карте. Рисуются на слое оверлеев: не темнеют ночью, всегда поверх
## построек и одного размера на экране при любом масштабе. При сильном отдалении скрываются.
## Цветная метка слева — бригада; выбранный человек подсвечен янтарным.

const T := World.T
const MIN_ZOOM := 0.85   ## дальше этого масштаба подписи не нужны — сливаются в кашу
const FONT_PX := 12

var sim: Sim
var game: Node
var _sb: StyleBoxFlat
var _sb_sel: StyleBoxFlat


func _ready() -> void:
	z_index = 5
	_sb = StyleBoxFlat.new()
	_sb.bg_color = Color(0.07, 0.08, 0.09, 0.66)
	_sb.set_corner_radius_all(6)
	_sb.content_margin_left = 5
	_sb.content_margin_right = 5
	_sb_sel = _sb.duplicate()
	_sb_sel.bg_color = Color(0.11, 0.09, 0.05, 0.85)
	_sb_sel.border_color = UITheme.ACCENT
	_sb_sel.set_border_width_all(1)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or game == null or not bool(Game.settings.get("names_on_map", true)):
		return
	var cam: Camera2D = game.get("cam")
	if cam == null or cam.zoom.x < MIN_ZOOM:
		return
	var f: Font = UITheme.f_med if UITheme.f_med else ThemeDB.fallback_font
	var k := 1.0 / cam.zoom.x
	var view := Rect2(cam.get_screen_center_position() - get_viewport_rect().size * 0.5 * k, get_viewport_rect().size * k).grow(40.0)
	var tool: Node = game.get("tool")
	var sel_id := int(tool.get("sel_id")) if tool and str(tool.get("sel_kind")) == "worker" else -999999
	for w: Worker in sim.workers + sim.visitors:
		if not w.present or w.hidden:
			continue
		var wp := w.vpos()
		var p := Vector2(wp.x * T, wp.y * T + 6.0 + 9.0)
		if not view.has_point(p):
			continue
		var nm := L.name(w.last if w.last != "" else w.first)
		var sel := w.id == sel_id
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
		var has_b := not w.visitor and w.brigade >= 0
		var bw := tw + (8.0 if has_b else 0.0)
		draw_set_transform(p, 0.0, Vector2(k, k))
		var r := Rect2(Vector2(-bw * 0.5 - 5.0, 0.0), Vector2(bw + 10.0, FONT_PX + 4.0))
		draw_style_box(_sb_sel if sel else _sb, r)
		var x := -bw * 0.5
		if has_b:
			draw_circle(Vector2(x + 2.5, FONT_PX * 0.5 + 2.0), 2.6, sim.crew.color(w.brigade))
			x += 8.0
		var col := UITheme.ACCENT if sel else (UITheme.INFO if w.visitor else (Color("#f0907f") if w.mood < 25.0 else Color("#ece8dc")))
		draw_string(f, Vector2(x, FONT_PX + 0.5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, col)
	# кот — тоже с именем, тёплым цветом
	var ct: Cat = sim.town.cat if sim.town else null
	if ct:
		var cp := Vector2(ct.pos.x * T, ct.pos.y * T + 6.0 + 6.0)
		if view.has_point(cp):
			var cn := ct.shown_name()
			var cw := f.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX - 1).x
			draw_set_transform(cp, 0.0, Vector2(k, k))
			draw_style_box(_sb, Rect2(Vector2(-cw * 0.5 - 5.0, 0.0), Vector2(cw + 10.0, FONT_PX + 3.0)))
			draw_string(f, Vector2(-cw * 0.5, FONT_PX - 0.5), cn, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX - 1, Color("#f0c070"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
