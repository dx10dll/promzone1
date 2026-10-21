class_name ZoneLayer
extends Node2D
## Зоны на полу (1.12): тусклое название зоны во всю её ширину, значок, лёгкий цвет группы
## и пунктир на границе между зонами одного зала. Как краска по бетону — не мешает смотреть.

const T := World.T

var sim: Sim
var _rev := -1
var _zoom := 1.0


func _process(_d: float) -> void:
	if sim == null:
		return
	var z := get_viewport().get_canvas_transform().get_scale().x
	if sim.rooms.rev != _rev or absf(z - _zoom) > 0.02:
		_rev = sim.rooms.rev
		_zoom = z
		queue_redraw()


static func group_color(type: String) -> Color:
	return Color(str(Defs.rooms.get(type, {}).get("color", "#888888")))


func _draw() -> void:
	if sim == null:
		return
	var w := sim.world
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	for r in sim.rooms.list:
		if r.type == "":
			continue
		var col := group_color(r.type)
		var tint := Color(col.r, col.g, col.b, 0.07)
		var edge := Color(col.r, col.g, col.b, 0.55)
		for c in r.cells:
			var p := Vector2(c) * T
			draw_rect(Rect2(p, Vector2(T, T)), tint)
			# пунктир там, где зона граничит с другой зоной (или неразмеченной частью) того же зала
			for d: Vector2i in Rooms.DIRS:
				var nb: Vector2i = c + d
				if not w.inb(nb):
					continue
				var ri := sim.rooms.room_of[w.idx(nb)]
				if ri < 0 or ri == r.id:
					continue
				_dash_edge(p, d, edge)
		_title(r.rect, r.type, r.title(), col, f, r.valid)
	for oz: Dictionary in sim.rooms.open_zones:
		var col2 := group_color(str(oz["type"]))
		for c2: Vector2i in oz["cells"]:
			var p2 := Vector2(c2) * T
			draw_rect(Rect2(p2, Vector2(T, T)), Color(col2.r, col2.g, col2.b, 0.10))
			draw_line(p2 + Vector2(4, T - 4), p2 + Vector2(T - 4, 4), Color(0.9, 0.4, 0.3, 0.25), 1.5)
		_title(oz["rect"], str(oz["type"]), str(Defs.rooms.get(str(oz["type"]), {}).get("name", "")), col2, f, false)


## Пунктир по стороне клетки d (наружу).
func _dash_edge(p: Vector2, d: Vector2i, col: Color) -> void:
	var a: Vector2
	var b: Vector2
	match d:
		Vector2i(0, -1):
			a = p
			b = p + Vector2(T, 0)
		Vector2i(0, 1):
			a = p + Vector2(0, T)
			b = p + Vector2(T, T)
		Vector2i(-1, 0):
			a = p
			b = p + Vector2(0, T)
		_:
			a = p + Vector2(T, 0)
			b = p + Vector2(T, T)
	var n := 4
	for k in n:
		var t0 := float(k) / float(n)
		draw_line(a.lerp(b, t0 + 0.04), a.lerp(b, t0 + 0.17), col, 2.0)


## Название зоны во всю её ширину — тусклыми заглавными буквами, со значком слева.
func _title(rect: Rect2i, type: String, title: String, col: Color, f: Font, valid: bool) -> void:
	var text := title.to_upper()
	var box := Rect2(Vector2(rect.position) * T, Vector2(rect.size) * T)
	if box.size.x < T * 2.0 or box.size.y < T:
		return
	var spacing := 0.18     # разрядка, в долях кегля
	var est := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x / 32.0 + spacing * text.length()
	var icon_k := 1.15
	var size := (box.size.x * 0.84) / (est + icon_k + 0.3)
	size = minf(size, box.size.y * 0.36)
	size = clampf(size, 9.0, 64.0)
	var tw := (est + icon_k + 0.3) * size
	var x := box.get_center().x - tw * 0.5
	var y := box.get_center().y + size * 0.36
	var a := 0.34 if valid else 0.24
	var dc := col.darkened(0.18)
	var tc := Color(dc.r, dc.g, dc.b, a)
	var tex := Tex.ui_world("zone_" + type)
	if tex:
		var isz := size * icon_k
		# 1.38: цветной значок владельца — без перекраски, только приглушён прозрачностью
		var ic := Color(1, 1, 1, 0.5 if valid else 0.32) if Tex.is_color(tex) else tc
		draw_texture_rect(tex, Rect2(Vector2(x, y - size * 0.36 - isz * 0.5), Vector2(isz, isz)), false, ic)
	x += size * (icon_k + 0.3)
	# буквы рисуем в экранном кегле и уменьшаем обратно — при приближении надпись остаётся чёткой
	var z := maxf(0.25, _zoom)
	var px := maxi(6, int(round(size * z)))
	for ch in text:
		draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0 / z, 1.0 / z))
		draw_string(f, Vector2.ZERO, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, tc)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / z + spacing * size
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
