class_name FxLayer
extends Node2D
## Эффекты поверх мира: огонь и дым пожара (со светом), снегопад, отметки нарушений,
## найденных инспектором.

const T := World.T
const MAX_LIGHTS := 6

var sim: Sim
var root: Node2D
var _t := 0.0
var lights: Array[PointLight2D] = []
var flakes: Array[Vector3] = []   ## x, y (доля экрана), скорость
## 1.25: качество эффектов из настроек: 0 — без искр и стружки, 1 — поменьше, 2 — всё.
static var quality := 2


func setup(s: Sim, world_root: Node2D) -> void:
	sim = s
	root = world_root
	z_index = 30
	var glow := Tex.fx("glow")
	for i in MAX_LIGHTS:
		var l := PointLight2D.new()
		l.texture = glow
		l.texture_scale = 2.4
		l.color = Color("#ff9a40")
		l.energy = 0.0
		l.visible = false
		root.add_child(l)
		lights.append(l)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i2 in 260:
		flakes.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.4)))


func _zoom() -> float:
	return get_viewport().get_canvas_transform().get_scale().x


func _process(delta: float) -> void:
	if sim == null:
		return
	_t += delta
	if Engine.get_process_frames() % 30 == 0:
		quality = clampi(int(float(Game.settings.get("quality", 2))), 0, 2)
	_update_lights()
	queue_redraw()


func _update_lights() -> void:
	var keys: Array = sim.story.fires.keys()
	for i in MAX_LIGHTS:
		var l := lights[i]
		if i < keys.size():
			var idx: int = keys[(i * 5) % keys.size()]
			var c := sim.world.cell_of(idx)
			l.position = (Vector2(c) + Vector2(0.5, 0.4)) * T
			l.energy = 0.9 + 0.35 * sin(_t * 11.0 + i * 1.7) + 0.2 * sin(_t * 23.0 + i)
			l.visible = true
		else:
			l.visible = false


func _draw() -> void:
	if sim == null:
		return
	_draw_lots()
	_draw_fire()
	_draw_fumes()
	_draw_steam()
	_draw_brawl()
	_draw_faults()
	_draw_marks()
	if sim.season.is_snowing():
		_draw_snowfall()
	if sim.season.is_raining():
		_draw_rain()


const SIGN_W := 132.0


## 1.29: прямоугольник таблички «Продаётся» участка k (в координатах карты) — по нему можно щёлкнуть.
static func sign_rect(s: Sim, k: int) -> Rect2:
	var lr := s.world.lot_rect(k)
	var sx := (float(lr.position.x) + float(lr.size.x) * 0.5) * T
	var sy := (lr.end.y - 0.6) * T
	return Rect2(sx - SIGN_W * 0.5, sy - 56, SIGN_W, 52)


## Табличка какого некупленного участка под точкой карты (−1 — ни одной).
static func sign_at(s: Sim, p: Vector2) -> int:
	for k in s.world.lots.size():
		if not s.world.lot_bought(k) and sign_rect(s, k).has_point(p):
			return k
	return -1


## Соседние участки, которые ещё не куплены (1.18): лёгкая дымка поверх травы и деревьев —
## чужая земля не отвлекает; табличка «Продаётся» у забора — поверх дымки.
func _draw_lots() -> void:
	var w := sim.world
	if w.lots.is_empty():
		return
	var fnt: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var nxt := sim.next_lot()
	var haze := Color(0.78, 0.82, 0.78, 0.30)
	for k in w.lots.size():
		if w.lot_bought(k):
			continue
		var lr := w.lot_rect(k)
		var rr := Rect2(Vector2(lr.position) * T, Vector2(lr.size) * T)
		draw_rect(rr, haze)
		# мягкий край у забора: дымка гуще к дальней стороне
		for e in 4:
			draw_rect(rr.grow(-float(e) * T * 0.5), Color(haze.r, haze.g, haze.b, 0.05))
		var sx := (float(lr.position.x) + float(lr.size.x) * 0.5) * T
		var sy := (lr.end.y - 0.6) * T
		var bw := SIGN_W
		var sr := sign_rect(sim, k)
		var hot := sr.has_point(get_local_mouse_position())
		draw_rect(Rect2(sx - 2, sy - 6, 4, 18), Color("#5a4a3a"))
		draw_rect(sr, Color("#3a4c3a") if hot else Color("#2c3a2c"))
		draw_rect(sr, Color("#f0d070") if hot else Color("#d8d4c4"), false, 2.0 if hot else 1.5)
		draw_string(fnt, Vector2(sx - bw * 0.5, sy - 41), L.t("ПРОДАЁТСЯ"), HORIZONTAL_ALIGNMENT_CENTER, bw, 12, Color("#f0d070"))
		var sub := "%s · %d×%d" % [Defs.money_str(float(w.lots[k].get("price", 0))), lr.size.x, lr.size.y]
		draw_string(fnt, Vector2(sx - bw * 0.5, sy - 25), sub, HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color("#e7e4d8") if k == nxt else Color("#a8a49a"))
		draw_string(fnt, Vector2(sx - bw * 0.5, sy - 11), L.t("щёлкните — купить"), HORIZONTAL_ALIGNMENT_CENTER, bw, 9, Color("#f0d070") if hot else Color("#8a9a86"))


## 1.18: обрыв провода — искры и вспышки; прорыв трубы — фонтанчик брызг.
func _draw_faults() -> void:
	if sim.faults.list.is_empty():
		return
	for f: Dictionary in sim.faults.list.values():
		var i := int(f["i"])
		var c := sim.world.cell_of(i)
		var base := (Vector2(c) + Vector2(0.5, 0.5)) * T
		var h := float(absi(i * 2654435761) % 1000) / 1000.0
		if str(f["layer"]) == "cable":
			# оборванные концы провода и дуга между ними
			draw_line(base + Vector2(-T * 0.48, 3), base + Vector2(-5, 1), Color(0.1, 0.1, 0.1, 0.95), 3.0)
			draw_line(base + Vector2(5, 0), base + Vector2(T * 0.48, -2), Color(0.1, 0.1, 0.1, 0.95), 3.0)
			draw_circle(base + Vector2(-5, 1), 2.0, Color(0.85, 0.55, 0.25))
			draw_circle(base + Vector2(5, 0), 2.0, Color(0.85, 0.55, 0.25))
			# пульсирующее кольцо — авария видна издалека
			var pr := fmod(_t * 0.9 + h, 1.0)
			draw_arc(base, 8.0 + pr * 18.0, 0.0, TAU, 28, Color(1.0, 0.75, 0.2, 0.55 * (1.0 - pr)), 2.0)
			# вспышки: короткие очереди искр
			var cyc := fmod(_t * 1.3 + h, 1.0)
			var burst := 1.0 - clampf(cyc / 0.45, 0.0, 1.0)
			var arc_pts := PackedVector2Array()
			for z in 6:
				var fx := -5.0 + z * 2.0
				arc_pts.append(base + Vector2(fx, sin(_t * 40.0 + z * 2.3) * 3.0 - 1.0))
			draw_polyline(arc_pts, Color(0.75, 0.9, 1.0, 0.5 + 0.5 * burst), 1.6)
			draw_circle(base, 7.0 + 7.0 * burst, Color(1.0, 0.85, 0.35, 0.18 + 0.45 * burst))
			draw_circle(base, 3.0, Color(1, 1, 0.92, 0.7 + 0.3 * burst))
			if burst > 0.0:
				for k in 11:
					var a := TAU * (k / 11.0) + h * 7.0 + floorf(_t * 1.3 + h) * 1.3
					var ln := (10.0 + 14.0 * fmod(h * 17.0 + k * 0.37, 1.0)) * (1.25 - burst * 0.5)
					var p0 := base + Vector2(cos(a), sin(a) * 0.8) * (4.0 + (1.0 - burst) * 14.0)
					var p1 := p0 + Vector2(cos(a), sin(a) * 0.8 + 0.3 * (1.0 - burst)) * ln * 0.5
					draw_line(p0, p1, Color(1.0, 0.95 - 0.3 * (1.0 - burst), 0.55, burst), 2.0)
		else:
			# фонтанчик из лопнувшей трубы
			for k2 in 8:
				var ph := fmod(_t * 1.4 + k2 / 8.0 + h, 1.0)
				var dx := (k2 - 3.5) * 1.6
				var p2 := base + Vector2(dx * ph * 3.0, -ph * 16.0 + ph * ph * 22.0 - 2.0)
				draw_circle(p2, 1.6, Color(0.75, 0.9, 1.0, 0.85 * (1.0 - ph)))


func _draw_fire() -> void:
	if sim.story.fires.is_empty():
		return
	var w := sim.world
	var flame := Tex.fx("flame")
	var smoke := Tex.fx("smoke_dark")
	for i: int in sim.story.fires.keys():
		var v := float(sim.story.fires[i])
		var c := w.cell_of(i)
		var base := (Vector2(c) + Vector2(0.5, 0.85)) * T
		var h := float((i * 2654435761) % 1000) / 1000.0
		# дым поднимается
		for k in 3:
			var ph := fmod(_t * 0.35 + h + k * 0.33, 1.0)
			var p := base + Vector2(sin(ph * 5.0 + h * 9.0) * 6.0, -18.0 - ph * 46.0 * (0.6 + v))
			var sz := (10.0 + ph * 22.0) * (0.6 + v * 0.6)
			draw_texture_rect(smoke, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, (1.0 - ph) * 0.55))
		# языки пламени
		for k2 in 2:
			var fl := 0.85 + 0.15 * sin(_t * (13.0 + k2 * 4.0) + h * 20.0)
			var fw := T * (0.55 + 0.45 * v) * fl * (1.0 if k2 == 0 else 0.7)
			var fh := fw * (1.15 + 0.15 * sin(_t * 9.0 + h * 7.0 + k2))
			var off := Vector2((k2 * 2 - 1) * 5.0 * v, 0)
			draw_texture_rect(flame, Rect2(base + off - Vector2(fw * 0.5, fh), Vector2(fw, fh)), false)
		# искры
		for k3 in 2:
			var ph2 := fmod(_t * 0.9 + h * 3.0 + k3 * 0.5, 1.0)
			var sp := base + Vector2(sin(h * 30.0 + k3 * 2.0) * 10.0 * ph2, -10.0 - ph2 * 40.0)
			draw_circle(sp, 1.4, Color(1.0, 0.85, 0.4, 1.0 - ph2))


## Дым и пары в помещениях без вентиляции: медленно плывущие серые клубы.
## Пар над занятой душевой кабиной (1.14).
func _draw_steam() -> void:
	for t: Thing in sim.things.values():
		if t.kind() != "shower" or not t.spot_users.has(0):
			continue
		# силуэт за матовым стеклом, запотевшая дверца и пар над кабиной
		var cx := (float(t.cell.x) + 0.5) * T
		var cy := float(t.cell.y) * T
		var sway := sin(_t * 1.7 + t.id) * 1.2
		draw_circle(Vector2(cx + sway, cy - 0.5 * T), 0.17 * T, Color(0.86, 0.68, 0.56, 0.45))
		draw_rect(Rect2(cx - 0.2 * T + sway, cy - 0.34 * T, 0.4 * T, 0.62 * T), Color(0.86, 0.68, 0.56, 0.35))
		draw_rect(Rect2(cx - 0.42 * T, cy - 0.92 * T, 0.84 * T, 1.25 * T), Color(0.95, 0.97, 1.0, 0.3))
		var base := Vector2(cx, cy - 0.95 * T)
		for k in 7:
			var ph := fmod(_t * 0.4 + float(k) / 7.0, 1.0)
			var p := base + Vector2(sin(_t * 1.3 + k) * 5.0 + (k - 3) * 2.2, -ph * 26.0)
			draw_circle(p, 3.5 + ph * 7.0, Color(1, 1, 1, (1.0 - ph) * 0.5))


## Драка (1.14): клубок пыли, из которого торчат кулаки и вылетают звёздочки.
func _draw_brawl() -> void:
	for p: Vector2 in sim.social.fight_spots():
		var base := (p + Vector2(0.0, -0.1)) * T
		for k in 11:
			var a := _t * 3.2 + TAU * k / 11.0
			var r := 15.0 + sin(_t * 7.0 + k * 1.7) * 3.0
			var q := base + Vector2(cos(a) * r * 1.4, sin(a) * r * 0.55 - 9.0)
			var sh := 0.62 + 0.1 * sin(k * 2.3)
			draw_circle(q, 9.5 + sin(_t * 5.0 + k) * 2.0, Color(sh, sh * 0.93, sh * 0.82, 0.72))
		draw_circle(base + Vector2(0, -9.0), 13.0, Color(0.66, 0.61, 0.54, 0.6))
		for k2 in 3:
			var a2 := -_t * 4.0 + TAU * k2 / 3.0
			var sp := base + Vector2(cos(a2) * 20.0, sin(a2) * 7.0 - 26.0)
			var pts := PackedVector2Array()
			for i in 10:
				var aa := -PI / 2.0 + TAU * i / 10.0 + _t * 2.0
				pts.append(sp + Vector2(cos(aa), sin(aa)) * (3.6 if i % 2 == 0 else 1.5))
			draw_colored_polygon(pts, Color(1.0, 0.86, 0.25, 0.95))
		# кулак то с одной, то с другой стороны
		var fx := sin(_t * 9.0) * 15.0
		draw_circle(base + Vector2(fx, -14.0 + cos(_t * 9.0) * 3.0), 3.2, Color(0.93, 0.76, 0.62))
		draw_arc(base + Vector2(fx, -14.0 + cos(_t * 9.0) * 3.0), 3.2, 0.0, TAU, 12, Color(0.35, 0.25, 0.2, 0.9), 1.0)


func _draw_fumes() -> void:
	if sim.eng.fumes.is_empty():
		return
	var smoke := Tex.fx("smoke_dark")
	for r in sim.rooms.list:
		var f := sim.eng.fumes_of(r)
		if f < 20.0:
			continue
		var a := clampf((f - 20.0) / 80.0, 0.0, 1.0) * 0.32
		var n := clampi(int(r.area() / 6), 2, 40)
		for k in n:
			var c: Vector2i = r.cells[(k * 7919) % r.cells.size()]
			var h := float(((c.x * 73856093) ^ (c.y * 19349663)) % 1000) / 1000.0
			var ph := fmod(_t * 0.05 + h, 1.0)
			var p := (Vector2(c) + Vector2(0.5, 0.5)) * T + Vector2(sin(_t * 0.3 + h * 6.0) * 14.0, -ph * 20.0)
			var sz := T * (2.2 + h * 1.6)
			var aa := a * sin(ph * PI)
			draw_texture_rect(smoke, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(0.75, 0.74, 0.7, aa))


func _draw_marks() -> void:
	var marks: Array = sim.inspect.marks
	if marks.is_empty():
		return
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var z := maxf(0.3, _zoom())
	for m: Dictionary in marks:
		var cc: Array = m["cell"]
		var p := (Vector2(float(cc[0]), float(cc[1])) + Vector2(0.5, 0.0)) * T + Vector2(0, -6.0 + sin(_t * 3.0) * 2.0)
		var tri := PackedVector2Array([p + Vector2(0, -12), p + Vector2(10, 6), p + Vector2(-10, 6)])
		draw_colored_polygon(tri, Color("#d8644e"))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color("#23262a"), 1.5)
		draw_rect(Rect2(p + Vector2(-1.2, -6), Vector2(2.4, 6)), Color.WHITE)
		draw_circle(p + Vector2(0, 3), 1.3, Color.WHITE)
		if z >= 0.8:
			var txt := str(m["text"])
			if txt.length() > 46:
				txt = txt.substr(0, 44) + "…"
			var px := int(round(12.0 * z))
			var sw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / z
			var tp := p + Vector2(-sw * 0.5, -16)
			draw_set_transform(tp, 0.0, Vector2(1.0 / z, 1.0 / z))
			draw_string_outline(f, Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(0.08, 0.09, 0.1, 0.9))
			draw_string(f, Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("#ffd0c4"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Снегопад: хлопья в видимой части мира.
func _draw_snowfall() -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var vs := get_viewport_rect().size
	var tl := inv * Vector2.ZERO
	var br := inv * vs
	var size := br - tl
	var z := maxf(0.3, _zoom())
	var w := sim.world
	var od := sim.season.outdoor
	var ok_mask := od.size() == w.w * w.h
	for f in flakes:
		var y := fmod(f.y + _t * 0.06 * f.z, 1.0)
		var x := fmod(f.x + sin(_t * 0.7 + f.y * 12.0) * 0.01 + _t * 0.012, 1.0)
		var p := tl + Vector2(x * size.x, y * size.y)
		var c := Vector2i(floori(p.x / T), floori(p.y / T))
		if ok_mask and w.inb(c) and od[w.idx(c)] == 0:
			continue   # под крышей не идёт
		draw_circle(p, (1.2 + f.z) / z, Color(1, 1, 1, 0.75))


## Дождь: косые штрихи на улице, а в помещении с дырявой крышей — капли.
func _draw_rain() -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var vs := get_viewport_rect().size
	var tl := inv * Vector2.ZERO
	var br := inv * vs
	var size := br - tl
	var z := maxf(0.3, _zoom())
	var w := sim.world
	var od := sim.season.outdoor
	var ok_mask := od.size() == w.w * w.h
	var leak := sim.progress.roof_leak
	for f in flakes:
		var y := fmod(f.y + _t * 0.55 * (0.8 + f.z * 0.3), 1.0)
		var x := fmod(f.x + _t * 0.05, 1.0)
		var p := tl + Vector2(x * size.x, y * size.y)
		var c := Vector2i(floori(p.x / T), floori(p.y / T))
		if ok_mask and w.inb(c) and od[w.idx(c)] == 0:
			if not leak or (c.x * 7 + c.y * 3) % 5 != 0:
				continue
		draw_line(p, p + Vector2(-3.0, 11.0) / z * 1.4, Color(0.75, 0.85, 0.95, 0.55), 1.2 / z)
