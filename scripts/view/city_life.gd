class_name CityLife
extends Node2D
## 1.23: движение в городе за краем карты — чтобы фон жил: по ветке проходит поезд
## (тепловоз, цистерны, полувагоны, крытые вагоны), по проездам ездят машины, из труб идёт дым,
## на высоких трубах мигают красные огни. Только картинка: на симуляцию не влияет, своя случайность.

const T := World.T

var backdrop: CityBackdrop
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _train_x := -99999.0         ## голова поезда (мир, x); -99999 — поезда нет
var _train_dir := 1.0
var _train_cars: Array = []      ## [тип вагона]
var _train_wait := 1.0
var _cars: Array = []            ## [{lane, k (0..1), v (доля в секунду), col}]
var _puffs: Array = []           ## [{p, v, r, a, life}]
var _puff_t := 0.0
var horn := false                ## поезд только что показался — SoundLayer даст гудок


## Где сейчас середина поезда (мир); Vector2.INF — поезда нет.
func train_pos() -> Vector2:
	if _train_x < -99000.0:
		return Vector2.INF
	return Vector2(_train_x - _train_dir * _train_cars.size() * 32.0, -10 * T + T * 0.5)


## Поезд появится через полсекунды (если сейчас его нет) — для главного меню.
func soon() -> void:
	if _train_x < -99000.0:
		_train_wait = minf(_train_wait, 0.5)


func _ready() -> void:
	_rng.seed = 2310
	z_index = 0


func reset() -> void:
	_cars.clear()
	_puffs.clear()
	if backdrop == null:
		return
	var cols := [Color("#c8c8c0"), Color("#8a2f2a"), Color("#2f4f6f"), Color("#d6c27a"), Color("#4f6f4a"), Color("#e8e6e0"), Color("#222426"), Color("#c23b2f")]
	for i in backdrop.lanes.size():
		var n := 2 if i < 4 else 1
		for k in n:
			_cars.append({"lane": i, "k": _rng.randf(), "v": _rng.randf_range(0.012, 0.03) * (1.0 if i < 4 else 2.5),
				"col": cols[_rng.randi_range(0, cols.size() - 1)], "truck": _rng.randf() < 0.25})


func _process(delta: float) -> void:
	if backdrop == null or backdrop.sim == null:
		return
	var d := minf(delta, 0.1)
	_t += d
	var w := backdrop.sim.world
	# поезд
	if _train_x < -99000.0:
		_train_wait -= d
		if _train_wait <= 0.0:
			_train_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_train_cars.clear()
			var n := _rng.randi_range(7, 16)
			for i in n:
				_train_cars.append(_rng.randi_range(0, 3))
			_train_x = (-CityBackdrop.M * T - 40.0) if _train_dir > 0 else ((w.w + CityBackdrop.M) * T + 40.0)
			horn = true
	else:
		_train_x += _train_dir * 150.0 * d
		var tail := _train_cars.size() * 64.0 + 80.0
		if (_train_dir > 0 and _train_x - tail > (w.w + CityBackdrop.M) * T) or (_train_dir < 0 and _train_x + tail < -CityBackdrop.M * T):
			_train_x = -99999.0
			_train_wait = _rng.randf_range(25.0, 70.0)
	# машины
	for c: Dictionary in _cars:
		var ln: Array = backdrop.lanes[int(c["lane"])]
		var len := maxf(1.0, _lane_len(ln))
		c["k"] = float(c["k"]) + float(c["v"]) * d * (1000.0 / len)
		if float(c["k"]) > 1.0:
			c["k"] = 0.0
	# дым
	_puff_t -= d
	if _puff_t <= 0.0:
		_puff_t = 0.35
		for ch: Array in backdrop.chimneys:
			if _puffs.size() < 160:
				var r: float = ch[1]
				_puffs.append({"p": (ch[0] as Vector2) + Vector2(_rng.randf_range(-2, 2), -2), "v": Vector2(_rng.randf_range(14, 22), _rng.randf_range(-12, -6)),
					"r": r * 0.6, "a": 0.32, "life": 0.0})
	var keep: Array = []
	for p: Dictionary in _puffs:
		p["life"] = float(p["life"]) + d
		p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * d
		p["r"] = float(p["r"]) + 5.0 * d
		p["a"] = 0.32 * (1.0 - float(p["life"]) / 7.0)
		if float(p["life"]) < 7.0:
			keep.append(p)
	_puffs = keep
	queue_redraw()


func _draw() -> void:
	if backdrop == null:
		return
	# машины
	for c: Dictionary in _cars:
		var ln: Array = backdrop.lanes[int(c["lane"])]
		var seg := _lane_seg(ln, float(c["k"]))
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var p: Vector2 = seg[2]
		var horiz := absf(b.x - a.x) > absf(b.y - a.y)
		var big := bool(c["truck"])
		var sz := (Vector2(34, 13) if big else Vector2(20, 11)) if horiz else (Vector2(13, 34) if big else Vector2(11, 20))
		var col: Color = c["col"]
		draw_rect(Rect2(p - sz * 0.5 + Vector2(2, 3), sz), Color(0, 0, 0, 0.28))
		draw_rect(Rect2(p - sz * 0.5, sz), col)
		var fwd := (b - a).normalized()
		draw_rect(Rect2(p + fwd * (sz.x if horiz else sz.y) * 0.22 - Vector2(4, 4), Vector2(8, 8)), Color("#3e5866"))
	# поезд
	if _train_x > -99000.0:
		var y := -10 * T + T * 0.5
		var x := _train_x
		_wagon(Vector2(x, y), -1)
		for kind: int in _train_cars:
			x -= _train_dir * 64.0
			_wagon(Vector2(x, y), kind)
	# дым
	for p: Dictionary in _puffs:
		draw_circle(p["p"], float(p["r"]), Color(0.82, 0.82, 0.8, float(p["a"])))
	# огни на трубах
	var blink := fmod(_t, 1.6) < 0.5
	if blink:
		for ch: Array in backdrop.chimneys:
			if float(ch[1]) >= 12.0:
				draw_circle(ch[0], 3.0, Color(1.0, 0.25, 0.2, 0.9))
		for bp: Vector2 in backdrop.beacons:   # 1.30: заградительные огни телебашни
			draw_circle(bp, 4.0, Color(1.0, 0.25, 0.2, 0.95))
			draw_circle(bp, 9.0, Color(1.0, 0.3, 0.2, 0.25))


func _lane_len(ln: Array) -> float:
	var l := 0.0
	for i in range(1, ln.size()):
		l += (ln[i] as Vector2).distance_to(ln[i - 1] as Vector2)
	return l


## 1.30: проезд может быть ломаной (поворот с боковой улицы на главную): [начало отрезка, конец, точка на доле k].
func _lane_seg(ln: Array, k: float) -> Array:
	var s := k * _lane_len(ln)
	for i in range(1, ln.size()):
		var a: Vector2 = ln[i - 1]
		var b: Vector2 = ln[i]
		var d := a.distance_to(b)
		if s <= d or i == ln.size() - 1:
			return [a, b, a.lerp(b, clampf(s / maxf(d, 1.0), 0.0, 1.0))]
		s -= d
	return [ln[0], ln[0], ln[0]]


## Вагон сверху (центр в p): -1 тепловоз, 0 цистерна, 1 полувагон, 2 крытый, 3 платформа с лесом.
func _wagon(p: Vector2, kind: int) -> void:
	var r := Rect2(p - Vector2(30, 13), Vector2(60, 26))
	draw_rect(Rect2(r.position + Vector2(4, 6), r.size), Color(0, 0, 0, 0.3))
	match kind:
		-1:
			draw_rect(r, Color("#3f6a4a"))
			draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(52, 18)), Color("#4f7d5a"))
			draw_rect(Rect2(r.get_center() + Vector2(_train_dir * 16 - 6, -8), Vector2(12, 16)), Color("#c8463a"))
			draw_circle(r.get_center() - Vector2(_train_dir * 10, 0), 4.0, Color("#2e2f31"))
		0:
			draw_rect(Rect2(r.position + Vector2(0, 3), Vector2(60, 20)), Color("#2e2f31"))
			draw_rect(Rect2(r.position + Vector2(2, 5), Vector2(56, 16)), Color("#3c3d40"))
			draw_circle(r.get_center(), 4.0, Color("#5a5b5e"))
		1:
			draw_rect(r, Color("#6a4a3a"))
			draw_rect(r.grow(-3), Color("#2f2b28"))
			for k in 3:
				draw_circle(r.position + Vector2(14 + k * 16, 13), 6.0, Color("#3a3634"))
		2:
			draw_rect(r, Color("#8a4a3a"))
			draw_line(Vector2(r.position.x + 2, r.get_center().y), Vector2(r.end.x - 2, r.get_center().y), Color("#6a3a2e"), 2.0)
		_:
			draw_rect(r, Color("#5a5048"))
			for k2 in 4:
				draw_rect(Rect2(r.position + Vector2(3, 3 + k2 * 5), Vector2(54, 4)), Color("#9a7a52"))
