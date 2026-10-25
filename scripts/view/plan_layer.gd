class_name PlanLayer
extends Node2D
## 1.17: план-калька поверх мира — синие стены, полы, подписанные зоны и призраки объектов.
## В режиме планировки — ярко, в обычном режиме — бледно (план не мешает смотреть на завод).

const T := World.T
const BLUE := Color(0.36, 0.62, 1.0)
const INK := Color(0.82, 0.9, 1.0)

static var faded := false

var sim: Sim
var tool: BuildTool
var _sig := ""


func _process(_d: float) -> void:
	if sim == null:
		return
	var sig := "%d|%s|%s" % [sim.plan.rev, tool.plan_mode if tool else false, faded]
	if sig != _sig:
		_sig = sig
		queue_redraw()


func _draw() -> void:
	if sim == null or sim.plan.is_empty():
		return
	var on := tool != null and tool.plan_mode
	if faded and not on:
		return
	var k := 1.0 if on else 0.5
	var pl := sim.plan
	var w := sim.world
	# полы — бледная калька с сеткой
	for i in pl.floors.keys():
		var c := w.cell_of(int(i))
		var r := Rect2(Vector2(c) * T, Vector2(T, T))
		draw_rect(r, Color(BLUE.r, BLUE.g, BLUE.b, 0.16 * k))
		draw_rect(r.grow(-0.5), Color(BLUE.r, BLUE.g, BLUE.b, 0.16 * k), false, 1.0)
	# зоны — цвет зоны и граница
	_draw_zones(pl.zones, k, false, false)
	_draw_zones(pl.ok_zones, k, true, false)
	# стены, двери, окна, ворота
	for i2 in pl.walls.keys():
		var c2 := w.cell_of(int(i2))
		_draw_wall(c2, int(pl.walls[i2]), k)
	# объекты — призраки
	for o: Dictionary in pl.objs:
		_draw_obj(o, k)
	# подписи зон — поверх всего
	_draw_zones(pl.zones, k, false, true)
	_draw_zones(pl.ok_zones, k, true, true)


func _plan_wall(c: Vector2i) -> bool:
	var w := sim.world
	if not w.inb(c):
		return false
	var i := w.idx(c)
	return sim.plan.walls.has(i) or WallKinds.is_room_wall(w.wall[i]) or (w.bp_wall[i] != World.BP_NONE and WallKinds.is_room_wall(w.bp_wall[i]))


func _draw_wall(c: Vector2i, kind: int, k: float) -> void:
	var ctr := (Vector2(c) + Vector2(0.5, 0.5)) * T
	var th := T * 0.42
	var fill := Color(0.22, 0.45, 0.92, 0.62 * k)
	var edge := Color(INK.r, INK.g, INK.b, 0.95 * k)
	var arms: Array[Vector2] = []
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _plan_wall(c + d):
			arms.append(Vector2(d))
	var rects: Array[Rect2] = [Rect2(ctr - Vector2(th, th) * 0.5, Vector2(th, th))]
	for a in arms:
		if a.x != 0:
			rects.append(Rect2(Vector2(ctr.x if a.x > 0 else ctr.x - T * 0.5, ctr.y - th * 0.5), Vector2(T * 0.5, th)))
		else:
			rects.append(Rect2(Vector2(ctr.x - th * 0.5, ctr.y if a.y > 0 else ctr.y - T * 0.5), Vector2(th, T * 0.5)))
	var cat := str(Defs.wall_by_id.get(kind, {}).get("kind", "wall"))
	if cat in ["door", "gate"]:
		fill = Color(0.95, 0.75, 0.3, 0.6 * k)
	elif cat == "window":
		fill = Color(0.55, 0.85, 1.0, 0.6 * k)
	for r in rects:
		draw_rect(r, fill)
	# осевая линия, как на чертеже
	for a2 in arms:
		draw_line(ctr, ctr + a2 * T * 0.5, edge, 1.2)
	if arms.is_empty():
		draw_rect(rects[0], edge, false, 1.2)
	if cat in ["door", "gate"]:
		# дуга открывания двери
		draw_arc(ctr, T * 0.34, -PI * 0.5, 0.0, 10, Color(1, 0.9, 0.6, 0.9 * k), 1.4)
	elif cat == "window":
		draw_line(ctr - Vector2(T * 0.3, 0), ctr + Vector2(T * 0.3, 0), Color(1, 1, 1, 0.8 * k), 1.2)


func _draw_zones(zones: Dictionary, k: float, approved: bool, labels: bool) -> void:
	if zones.is_empty():
		return
	var w := sim.world
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	if labels:
		_draw_zone_labels(zones, k, approved, f)
		return
	for i in zones.keys():
		var c := w.cell_of(int(i))
		var t := str(zones[i])
		var col := Color(str(Defs.rooms.get(t, {}).get("color", "#88aaff")))
		var r := Rect2(Vector2(c) * T, Vector2(T, T))
		draw_rect(r, Color(col.r, col.g, col.b, (0.14 if approved else 0.24) * k))
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if w.inb(n) and str(zones.get(w.idx(n), "")) == t:
				continue
			var a := r.position + Vector2(T if d.x > 0 else 0.0, T if d.y > 0 else 0.0)
			var b := a + (Vector2(0, T) if d.x != 0 else Vector2(T, 0))
			if approved:
				draw_dashed_line(a, b, Color(col.r, col.g, col.b, 0.9 * k), 2.0, 5.0)
			else:
				draw_line(a, b, Color(col.r, col.g, col.b, 0.95 * k), 2.0)


func _draw_zone_labels(zones: Dictionary, k: float, approved: bool, f: Font) -> void:
	var w := sim.world
	var seen := {}
	for i2 in zones.keys():
		if seen.has(i2):
			continue
		var t2 := str(zones[i2])
		var comp: Array[Vector2i] = []
		var q: Array[int] = [int(i2)]
		seen[i2] = true
		while not q.is_empty():
			var ci: int = q.pop_back()
			var cc := w.cell_of(ci)
			comp.append(cc)
			for d2: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nn := cc + d2
				if not w.inb(nn):
					continue
				var ni := w.idx(nn)
				if not seen.has(ni) and str(zones.get(ni, "")) == t2:
					seen[ni] = true
					q.append(ni)
		var mn := comp[0]
		var mx := comp[0]
		var sum := Vector2.ZERO
		for cc2 in comp:
			mn = Vector2i(mini(mn.x, cc2.x), mini(mn.y, cc2.y))
			mx = Vector2i(maxi(mx.x, cc2.x), maxi(mx.y, cc2.y))
			sum += Vector2(cc2)
		var ctr := (sum / comp.size() + Vector2(0.5, 0.5)) * T
		var col2 := Color(str(Defs.rooms.get(t2, {}).get("color", "#88aaff")))
		var nm := str(Defs.rooms.get(t2, {}).get("name", t2)).to_upper()
		var sub := "%d×%d%s" % [mx.x - mn.x + 1, mx.y - mn.y + 1, L.t(" · ждёт стен") if approved else L.t(" · план")]
		var fs := 13
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, ctr + Vector2(-tw * 0.5 + 1, 2), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5 * k))
		draw_string(f, ctr + Vector2(-tw * 0.5, 1), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col2.lightened(0.35), 0.95 * k))
		var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f, ctr + Vector2(-sw * 0.5, 14), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(INK, 0.85 * k))


func _draw_obj(o: Dictionary, k: float) -> void:
	var def_id := str(o["def"])
	var c := Vector2i(int(o["x"]), int(o["y"]))
	var rot := int(o["rot"])
	var sk := Thing.sprite_for(def_id, rot)
	var key := "chair_down" if def_id == "chair" else str(sk[0])
	var meta: Dictionary = Defs.sprites.get(key, {})
	var tex := Tex.obj(key)
	var r := Plan.obj_rect(def_id, c, rot)
	var ok := bool(o.get("ok", false))
	var col := Color(0.62, 0.82, 1.0, (0.5 if ok else 0.72) * k)
	draw_rect(Rect2(Vector2(r.position) * T, Vector2(r.size) * T), Color(BLUE.r, BLUE.g, BLUE.b, 0.18 * k))
	draw_rect(Rect2(Vector2(r.position) * T, Vector2(r.size) * T).grow(-1), Color(INK.r, INK.g, INK.b, 0.7 * k), false, 1.0)
	if tex:
		var bottom := Vector2(r.position.x * T, r.end.y * T)
		var sz := tex.get_size() * 0.5
		var pos := bottom - Vector2(float(meta.get("ox", 0)), float(meta.get("oy", 64))) * 0.5
		if bool(sk[1]) and def_id != "chair":
			draw_set_transform(Vector2(pos.x * 2.0 + float(r.size.x) * T, 0), 0.0, Vector2(-1, 1))
			draw_texture_rect(tex, Rect2(pos, sz), false, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, Rect2(pos, sz), false, col)
	if ok:
		# утверждён, ждёт пола и стен: значок часов
		var p := (Vector2(r.end) - Vector2(0.3, r.size.y - 0.3)) * T
		draw_circle(p, 6.0, Color(0.1, 0.14, 0.2, 0.85 * k))
		draw_arc(p, 5.0, 0, TAU, 14, Color(INK, k), 1.2)
		draw_line(p, p + Vector2(0, -3.5), Color(INK, k), 1.2)
		draw_line(p, p + Vector2(2.5, 0), Color(INK, k), 1.2)
