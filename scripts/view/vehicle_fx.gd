class_name VehicleFx
extends Node2D
## 1.30: машины со своей службой. Нижний слой (под людьми и машинами): пожарные рукава от машины
## до ствола в руках пожарного — тянутся следом и сматываются, когда пожарный идёт обратно; лужи.
## Верхний слой (top = true): струя воды из ствола в огонь, мигалки пожарной машины, дорожный
## указатель у правого края (пункт приёма металлолома, пожарная часть). Звук: сирена и шум струи.
## Всё только для экрана: в симуляцию ничего не пишет.

const T := World.T
const HOSE := Color("#d8d2c0")
const HOSE_D := Color("#6a6458")

var sim: Sim
var top := false
var _t := 0.0
var _trails: Dictionary = {}    ## id пожарного -> [клетка, PackedVector2Array точек рукава в пикселях]
var _siren_t := 0.0


func _ready() -> void:
	z_index = 30 if top else 0


func _process(delta: float) -> void:
	if sim == null:
		return
	_t += delta
	if not top:
		_update_trails()
		_sound(delta)
	queue_redraw()


## Где на экране машина (как в EntityLayer: плавно между шагами симуляции).
static func veh_pos(s: Sim, v: Vehicle) -> Vector2:
	var vx := v.x if v.px < -1e8 or absf(v.px - v.x) > 6.0 else lerpf(v.px, v.x, Worker.view_alpha)
	if v.lane == 0:
		return Vector2(vx * T - 4.0, (s.world.road_row + 0.7) * T)
	return Vector2(vx * T + 4.0, (s.world.road_row + 2.55) * T)


## Точка на машине по координатам её SVG (264×120, линия колёс y=104; масштаб 0.5).
static func veh_point(s: Sim, v: Vehicle, sx: float, sy: float) -> Vector2:
	var p := veh_pos(s, v)
	var lx := sx * 0.5
	var ly := (sy - 104.0) * 0.5
	return Vector2(p.x + (lx if v.lane == 0 else -lx), p.y + ly)


func _fire_trucks() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for v in sim.vehicles:
		if v.kind == "fire":
			out.append(v)
	return out


## Рукав идёт по земле тем же путём, что прошёл пожарный: от патрубка машины через ворота к стволу.
## Путь пересчитывается, когда пожарный переходит в другую клетку (идёт обратно — рукав короче).
func _update_trails() -> void:
	var br := sim.story.brigade
	var seen := {}
	var v := br.truck()
	for c: Dictionary in br.crew:
		var f: Worker = c["w"]
		if str(c["st"]) == "in" or v == null:
			continue
		seen[f.id] = true
		var fc := f.cell()
		var old: Array = _trails.get(f.id, [])
		if not old.is_empty() and old[0] == fc:
			continue
		var dp := br.door_pos(v, br.crew.find(c))
		var dc := Vector2i(floori(dp.x), floori(dp.y))
		var pts := PackedVector2Array([veh_point(sim, v, 110.0, 80.0), dp * T])
		for pc: Vector2i in sim.world.find_path(dc, fc):
			pts.append((Vector2(pc) + Vector2(0.5, 0.6)) * T)
		_trails[f.id] = [fc, pts]
	for id in _trails.keys():
		if not seen.has(id):
			_trails.erase(id)


func _sound(delta: float) -> void:
	var spraying := false
	for c: Dictionary in sim.story.brigade.crew:
		if str(c["st"]) == "spray":
			spraying = true
	Snd.ambient("amb_hose", 0.55 if spraying else 0.0)
	_siren_t -= delta
	for v in _fire_trucks():
		if v.state == "arriving" and _siren_t <= 0.0:
			_siren_t = 3.6
			Snd.play_at("siren", veh_point(sim, v, 132.0, 60.0), -2.0, 3.0)


func _draw() -> void:
	if sim == null:
		return
	if top:
		_draw_spray()
		_draw_lights()
		_draw_sign()
		_draw_scrap_board()
	else:
		_draw_hoses()


func _draw_hoses() -> void:
	for id in _trails.keys():
		var tr: PackedVector2Array = (_trails[id] as Array)[1]
		var f := sim.get_person(int(id))
		if f == null or tr.size() < 2:
			continue
		var pts := tr.duplicate()
		pts.remove_at(pts.size() - 1)   # последняя клетка — та, где он стоит: рукав тянется прямо к руке
		pts.append(f.vpos() * T + Vector2(0, 2))
		var sm := _smooth(pts)
		draw_polyline(sm, HOSE_D, 4.2, true)
		draw_polyline(sm, HOSE, 2.6, true)
		draw_circle(pts[0], 3.5, Color("#d9b13b"))
		# лужа у ствола, пока льёт
		for c: Dictionary in sim.story.brigade.crew:
			if c["w"] == f and str(c["st"]) == "spray" and int(c["fire"]) >= 0:
				var to := (Vector2(sim.world.cell_of(int(c["fire"]))) + Vector2(0.5, 0.7)) * T
				draw_circle(to, 0.45 * T, Color(0.55, 0.7, 0.85, 0.28))


## Сгладить ломаную: середины отрезков и квадратичные дуги между ними.
func _smooth(p: PackedVector2Array) -> PackedVector2Array:
	if p.size() < 3:
		return p
	var out := PackedVector2Array([p[0]])
	for i in range(1, p.size() - 1):
		var a := (p[i - 1] + p[i]) * 0.5
		var b := (p[i] + p[i + 1]) * 0.5
		for k in 4:
			var t := float(k) / 4.0
			out.append(a.lerp(p[i], t).lerp(p[i].lerp(b, t), t))
	out.append(p[p.size() - 1])
	return out


func _draw_spray() -> void:
	for c: Dictionary in sim.story.brigade.crew:
		if str(c["st"]) != "spray":
			continue
		var f: Worker = c["w"]
		var fi := int(c["fire"])
		if fi < 0:
			continue
		var fc := sim.world.cell_of(fi)
		var to := (Vector2(fc) + Vector2(0.5, 0.55)) * T
		var from := f.vpos() * T + Vector2(0, -8)
		var dirv := (to - from).normalized()
		from += dirv * 10.0
		var mid := (from + to) * 0.5 + Vector2(0, -0.45 * T - from.distance_to(to) * 0.12)
		var h := float(f.id % 97) / 97.0
		# струя: сплошная дуга и бегущие по ней капли
		var arc := PackedVector2Array()
		for k in 13:
			var t := float(k) / 12.0
			arc.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
		draw_polyline(arc, Color(0.78, 0.9, 1.0, 0.55), 3.0, true)
		draw_polyline(arc, Color(1, 1, 1, 0.5), 1.2, true)
		for k2 in 10:
			var t2 := fmod(_t * 2.2 + h + float(k2) / 10.0, 1.0)
			var p := from.lerp(mid, t2).lerp(mid.lerp(to, t2), t2) + Vector2(sin(_t * 9.0 + k2) * 1.5, 0)
			draw_circle(p, 1.8 + t2 * 1.2, Color(0.75, 0.9, 1.0, 0.85 * (1.0 - t2 * 0.5)))
		# брызги и пар у огня
		for k3 in 7:
			var ph := fmod(_t * 1.6 + h * 3.0 + float(k3) / 7.0, 1.0)
			var a := float(k3) / 7.0 * TAU + h
			var sp := to + Vector2(cos(a), sin(a) * 0.5) * (4.0 + ph * 14.0) + Vector2(0, -ph * 10.0)
			draw_circle(sp, 1.6, Color(0.85, 0.95, 1.0, 0.8 * (1.0 - ph)))
			draw_circle(to + Vector2(sin(a) * 6.0, -6.0 - ph * 26.0), 5.0 + ph * 8.0, Color(0.92, 0.94, 0.96, 0.32 * (1.0 - ph)))


func _draw_lights() -> void:
	var glow := Tex.fx("glow")
	for v in _fire_trucks():
		if v.state == "leaving":
			continue   # уезжают уже без мигалок
		var ph := fmod(_t * 2.6, 1.0)
		for k in 2:
			var on := (ph < 0.5) == (k == 0)
			var p := veh_point(sim, v, 206.0 + 24.0 * k, 21.5)
			var col := Color("#4f8cff") if on else Color("#1d3a80")
			draw_circle(p, 3.2, col)
			if on:
				var sz := 34.0 + 6.0 * sin(_t * 30.0)
				draw_texture_rect(glow, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(0.4, 0.6, 1.0, 0.85))
				draw_circle(p, 1.6, Color(0.9, 0.95, 1.0))


## Надпись на борту ломовоза: чей и зачем.
func _draw_scrap_board() -> void:
	var fnt: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	for v in sim.vehicles:
		if v.kind != "scrap" or v.lane != 0:
			continue
		var p := veh_point(sim, v, 14.0, 68.0)
		draw_string(fnt, p, "ЛОМ · " + Upkeep.FIRM.replace("«", "").replace("»", "").to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 86.0, 8, Color(0.95, 0.93, 0.85, 0.9))


## Дорожный указатель за правым краем участка: куда уезжает ломовоз, откуда приезжают пожарные.
func _draw_sign() -> void:
	var w := sim.world
	var fnt: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var base := Vector2((w.w + 0.6) * T, (w.sidewalk_row + 0.85) * T)
	var lines := ["Приём металлолома " + Upkeep.FIRM + "  →", "Пожарная часть № 7  →"]
	var bw := 0.0
	for s: String in lines:
		bw = maxf(bw, fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x)
	bw += 12.0
	var bh := 13.0 * lines.size() + 6.0
	var top_y := base.y - 0.55 * T - bh
	draw_rect(Rect2(base.x - 1.5 + 2, top_y + 3, 3, base.y - top_y), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(base.x - 1.5, top_y, 3, base.y - top_y), Color("#8a9196"))
	var r := Rect2(base.x - bw * 0.5, top_y - 2, bw, bh)
	draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.3))
	draw_rect(r, Color("#2456a8"))
	draw_rect(r.grow(-2), Color("#f2f2ee"), false, 1.2)
	for i in lines.size():
		draw_string(fnt, Vector2(r.position.x + 6, r.position.y + 13 + 13 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#f2f2ee"))
