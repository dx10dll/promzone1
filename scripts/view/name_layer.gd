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
var _sb_fast: StyleBoxTexture   ## 1.40: та же плашка одной картинкой-«девятью заплатками» — дешевле StyleBoxFlat в каждом кадре
var _sb_sel: StyleBoxFlat


func _ready() -> void:
	z_index = 5
	_sb = StyleBoxFlat.new()
	_sb.bg_color = Color(0.07, 0.08, 0.09, 0.66)
	_sb.set_corner_radius_all(6)
	_sb.content_margin_left = 5
	_sb.content_margin_right = 5
	_sb_fast = _bake_box(Color(0.07, 0.08, 0.09, 0.66))
	_sb_sel = _sb.duplicate()
	_sb_sel.bg_color = Color(0.11, 0.09, 0.05, 0.85)
	_sb_sel.border_color = UITheme.ACCENT
	_sb_sel.set_border_width_all(1)


var _tw: Dictionary = {}


## Скруглённая плашка 16×16 (радиус 6) с мягкой кромкой; цвет — через modulate_color.
static func _bake_box(col: Color) -> StyleBoxTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var px := absf(x + 0.5 - 8.0) - (8.0 - 6.0)
			var py := absf(y + 0.5 - 8.0) - (8.0 - 6.0)
			var d := Vector2(maxf(px, 0.0), maxf(py, 0.0)).length() + minf(maxf(px, py), 0.0) - 6.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(0.5 - d, 0.0, 1.0)))
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(6.0)
	sb.modulate_color = col
	return sb


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
		var tl: TextLine = _tw.get(nm)
		if tl == null:   # 1.40: текст раскладываем один раз на имя, а не каждый кадр на каждого человека
			tl = TextLine.new()
			tl.add_string(nm, f, FONT_PX)
			_tw[nm] = tl
		var tw := tl.get_size().x
		var has_b := not w.visitor and w.brigade >= 0
		var bw := tw + (8.0 if has_b else 0.0)
		draw_set_transform(p, 0.0, Vector2(k, k))
		var r := Rect2(Vector2(-bw * 0.5 - 5.0, 0.0), Vector2(bw + 10.0, FONT_PX + 4.0))
		draw_style_box(_sb_sel if sel else _sb_fast, r)
		var x := -bw * 0.5
		if has_b:
			draw_circle(Vector2(x + 2.5, FONT_PX * 0.5 + 2.0), 2.6, sim.crew.color(w.brigade))
			x += 8.0
		var col := UITheme.ACCENT if sel else (UITheme.INFO if w.visitor else (Color("#f0907f") if w.mood < 25.0 else Color("#ece8dc")))
		tl.draw(get_canvas_item(), Vector2(x, FONT_PX + 0.5 - tl.get_line_ascent()), col)
	# кот — тоже с именем, тёплым цветом
	var ct: Cat = sim.town.cat if sim.town else null
	if ct:
		var cv := ct.vpos()   # 1.48: по сглаженной позиции (как у людей), а не по шагу клетки — ник не дёргается
		var cp := Vector2(cv.x * T, cv.y * T + 10.5)
		if view.has_point(cp):
			var cn := ct.shown_name()
			var ckey := "cat:" + cn
			var ctl: TextLine = _tw.get(ckey)
			if ctl == null:
				ctl = TextLine.new()
				ctl.add_string(cn, f, FONT_PX)
				_tw[ckey] = ctl
			var cw := ctl.get_size().x
			draw_set_transform(cp, 0.0, Vector2(k, k))
			draw_style_box(_sb_fast, Rect2(Vector2(-cw * 0.5 - 5.0, 0.0), Vector2(cw + 10.0, FONT_PX + 4.0)))
			ctl.draw(get_canvas_item(), Vector2(-cw * 0.5, FONT_PX + 0.5 - ctl.get_line_ascent()), Color("#f0c070"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
