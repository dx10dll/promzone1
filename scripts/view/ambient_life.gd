class_name AmbientLife
extends Node2D
## 1.23: мелкая жизнь поверх мира — чтобы картинка не стояла на месте:
## — тени облаков медленно плывут по участку (днём, не в пасмурную погоду);
## — осенью с деревьев летят листья, летом днём над травой и клумбами порхают бабочки.
## Только картинка, своя случайность; рисуется лишь то, что видно на экране.

const T := World.T

var sim: Sim
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _leaves: Array = []        ## [{p, v, rot, col, life}]
var _flies: Array = []         ## [{home, p, ph, col}]
var _leaf_t := 0.0
var _fly_sig := ""


func _ready() -> void:
	z_index = 31
	_rng.seed = 2311


func _view() -> Rect2:
	var vp := get_viewport()
	var inv := get_canvas_transform().affine_inverse()
	var r := vp.get_visible_rect()
	return Rect2(inv * r.position, inv.basis_xform(r.size))


func _process(delta: float) -> void:
	if sim == null:
		return
	var d := minf(delta, 0.1)
	_t += d
	var view := _view().grow(64.0)
	var sea := sim.season.season_id()
	var w := sim.world
	# листья: осенью от деревьев в кадре
	_leaf_t -= d
	if sea == "autumn" and _leaf_t <= 0.0 and _leaves.size() < 60 and w.flora.size() == w.w * w.h:
		_leaf_t = 0.25
		for k in 4:
			var c := Vector2i(_rng.randi_range(0, w.w - 1), _rng.randi_range(0, w.h - 1))
			var v := int(w.flora[w.idx(c)])
			if v >= 1 and v <= 3 and view.has_point(Vector2(c) * T):
				var cols := [Color("#d9a03a"), Color("#c8642e"), Color("#e2c048"), Color("#a8532a")]
				_leaves.append({"p": (Vector2(c) + Vector2(_rng.randf_range(0.0, 1.0), -_rng.randf_range(1.5, 3.0))) * T,
					"v": Vector2(_rng.randf_range(6, 16), _rng.randf_range(10, 18)), "rot": _rng.randf() * TAU, "col": cols[_rng.randi_range(0, 3)], "life": 0.0})
	var keep: Array = []
	for lf: Dictionary in _leaves:
		lf["life"] = float(lf["life"]) + d
		lf["p"] = (lf["p"] as Vector2) + (lf["v"] as Vector2) * d + Vector2(sin(_t * 2.0 + float(lf["rot"])) * 10.0 * d, 0)
		lf["rot"] = float(lf["rot"]) + d * 2.0
		if float(lf["life"]) < 6.0:
			keep.append(lf)
	_leaves = keep
	# бабочки: летом днём у клумб и над травой
	var want := sea == "summer" and sim.is_daylight() and not sim.season.is_raining()
	var sig := "%s|%d" % [str(want), sim.thing_rev]
	if sig != _fly_sig:
		_fly_sig = sig
		_flies.clear()
		if want:
			for t: Thing in sim.things.values():
				if t.built and (t.def_id == "flower_bed" or t.def_id == "plant" or t.def_id == "palm") and _flies.size() < 12:
					_flies.append(_fly((Vector2(t.cell) + Vector2(t.size()) * 0.5) * T))
			for k2 in 6:
				var c2 := Vector2i(_rng.randi_range(0, w.w - 1), _rng.randi_range(0, w.h - 1))
				if w.ground[w.idx(c2)] == World.Ground.GRASS:
					_flies.append(_fly((Vector2(c2) + Vector2(0.5, 0.5)) * T))
	for fl: Dictionary in _flies:
		var ph := _t * 0.7 + float(fl["ph"])
		fl["p"] = (fl["home"] as Vector2) + Vector2(sin(ph) * 22.0 + sin(ph * 2.3) * 8.0, cos(ph * 0.8) * 16.0 - 10.0)
	queue_redraw()


func _fly(home: Vector2) -> Dictionary:
	var cols := [Color("#f2f0e8"), Color("#f2c84b"), Color("#e8843a"), Color("#8ab8f0")]
	return {"home": home, "p": home, "ph": _rng.randf() * TAU, "col": cols[_rng.randi_range(0, 3)]}


func _draw() -> void:
	if sim == null:
		return
	var view := _view()
	# тени облаков — большие мягкие пятна, плывут по ветру
	if sim.is_daylight() and not sim.season.is_raining():
		var span := 2400.0
		for k in 4:
			var base := Vector2(fmod(_t * 14.0 + k * 700.0, span) - 600.0, k * 520.0 + 180.0 * sin(k * 1.7))
			var c := Vector2(floor(view.position.x / span) * span, floor(view.position.y / 2000.0) * 2000.0) + base
			for j in 2:
				var cc := c + Vector2(j * span, 0)
				if view.grow(260.0).has_point(cc):
					for m in 5:
						draw_circle(cc + Vector2(m * 70.0 - 140.0, sin(m * 2.1 + k) * 40.0), 110.0 + 30.0 * sin(m + k), Color(0.05, 0.07, 0.1, 0.035))
	for lf: Dictionary in _leaves:
		var p: Vector2 = lf["p"]
		if not view.has_point(p):
			continue
		var a := float(lf["rot"])
		var dx := Vector2(cos(a), sin(a)) * 3.0
		var dy := Vector2(-sin(a), cos(a)) * 1.6
		var col: Color = lf["col"]
		col.a = clampf(6.0 - float(lf["life"]), 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([p - dx, p + dy, p + dx, p - dy]), col)
	for fl: Dictionary in _flies:
		var p2: Vector2 = fl["p"]
		if not view.has_point(p2):
			continue
		var flap := absf(sin(_t * 18.0 + float(fl["ph"]) * 3.0))
		var col2: Color = fl["col"]
		draw_rect(Rect2(p2 + Vector2(-3.0 * flap - 0.5, -1.5), Vector2(3.0 * flap, 3.0)), col2)
		draw_rect(Rect2(p2 + Vector2(0.5, -1.5), Vector2(3.0 * flap, 3.0)), col2)
		draw_line(p2 + Vector2(0, -1.5), p2 + Vector2(0, 1.5), Color(0.15, 0.12, 0.1), 1.0)
