class_name WorldView
extends Node2D
## Нижний слой: грунт, полы, разметка дороги, пороги дверей, чертежи полов.

const T := World.T

var sim: Sim
var _rev := -1


func _process(_d: float) -> void:
	if sim and sim.world.rev != _rev:
		_rev = sim.world.rev
		queue_redraw()


static func vhash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995)


func _draw() -> void:
	if sim == null:
		return
	var w := sim.world
	# 1.21: за краем карты — промышленный город (CityBackdrop), здесь только дорога
	var dirt: Array[Texture2D] = []
	var grass: Array[Texture2D] = []
	var conc: Array[Texture2D] = []
	for i in 4:
		dirt.append(Tex.tile("dirt_%d" % i))
		grass.append(Tex.tile("grass_%d" % i))
		conc.append(Tex.tile("concrete_%d" % i))
	var asph: Array[Texture2D] = []
	for i5 in 5:
		asph.append(Tex.tile("asphalt_%d" % i5))
	var road := [Tex.tile("road_0"), Tex.tile("road_1")]
	var side := Tex.tile("sidewalk")
	var tile_t := Tex.tile("tile")
	var lino := Tex.tile("lino")
	# полы по номеру (1.12: наливной пол, голубая плитка, паркет)
	var ftex := {}
	for fid in Defs.floor_by_id.keys():
		var tk := str(Defs.floor_by_id[fid].get("tex", ""))
		if tk != "" and tk != "concrete":
			ftex[int(fid)] = Tex.tile(tk)
	_noise_cache(w)
	for y in w.h:
		for x in w.w:
			var c := Vector2i(x, y)
			var i := w.idx(c)
			var r := Rect2(x * T, y * T, T, T)
			var hv := vhash(x, y)
			var fl := w.flr[i]
			if fl == 0:
				var gk := w.ground[i]
				match gk:
					World.Ground.GRASS:
						_ground_cell(grass[hv % 4], x, y, hv, gk)
					World.Ground.ASPHALT:
						var av := hv % 23
						_ground_cell(asph[4 if av == 0 else (2 if av == 1 else (3 if av == 2 else (hv >> 5) % 2))], x, y, hv, gk)
					World.Ground.ROAD:
						draw_texture_rect(road[hv % 2], r, false)
					World.Ground.SIDEWALK:
						draw_texture_rect(side, r, false)
					_:
						_ground_cell(dirt[hv % 4], x, y, hv, gk)
			if fl > 0:
				var ft: Texture2D = conc[hv % 4]
				# плиты бетона чуть разного тона — пол не выглядит «обоями»
				var tone := Color.WHITE
				if ftex.has(int(fl)) and ftex[int(fl)] != null:
					ft = ftex[int(fl)]
				else:
					var v := 0.955 + float(hv % 9) * 0.01
					tone = Color(v, v, v * 1.005)
				draw_texture_rect(ft, r, false, tone)
			# чертёж пола
			var bf := w.bp_floor[i]
			if bf != World.BP_NONE:
				if bf == 0:
					_draw_cross(r, Color(0.9, 0.3, 0.25, 0.8))
				else:
					var gt: Texture2D = ftex.get(int(bf), conc[0]) if bf != 1 else conc[0]
					draw_texture_rect(gt, r, false, Color(0.55, 0.75, 1.0, 0.55))
					draw_rect(r.grow(-1), Color(0.35, 0.6, 0.95, 0.9), false, 1.0)
	_draw_grass_edges()
	_draw_ao()
	# зоны на улице: разгрузка — жёлтая штриховка, отгрузка — бирюзовая; рамка по краю зоны
	for zk: Array in [[1, Color(0.95, 0.78, 0.25), "РАЗГРУЗКА"], [2, Color(0.35, 0.8, 0.78), "ОТГРУЗКА"]]:
		var zv: int = zk[0]
		var zc: Color = zk[1]
		var any_zone := Vector2i(-1, -1)
		for y2 in w.h:
			for x2 in w.w:
				var c2 := Vector2i(x2, y2)
				if w.area[w.idx(c2)] != zv:
					continue
				if any_zone.x < 0:
					any_zone = c2
				var r2 := Rect2(x2 * T, y2 * T, T, T)
				draw_rect(r2, Color(zc.r, zc.g, zc.b, 0.10))
				for k in 4:
					var o := k * 8.0
					draw_line(r2.position + Vector2(o, T), r2.position + Vector2(minf(T, o + 8.0), T - minf(8.0, T - o)), Color(zc.r, zc.g, zc.b, 0.35), 1.5)
				for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
					var n2: Vector2i = c2 + d
					if w.inb(n2) and w.area[w.idx(n2)] == zv:
						continue
					match d:
						Vector2i(0, -1):
							draw_line(r2.position, r2.position + Vector2(T, 0), Color(zc, 0.9), 2.0)
						Vector2i(0, 1):
							draw_line(r2.position + Vector2(0, T), r2.end, Color(zc, 0.9), 2.0)
						Vector2i(-1, 0):
							draw_line(r2.position, r2.position + Vector2(0, T), Color(zc, 0.9), 2.0)
						_:
							draw_line(r2.position + Vector2(T, 0), r2.end, Color(zc, 0.9), 2.0)
		if any_zone.x >= 0:
			var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
			draw_string(f, Vector2(any_zone) * T + Vector2(3, 12), str(zk[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(zc, 0.85))
	# соседние участки (1.13): дымка и табличка «Продаётся» — в FxLayer, поверх деревьев (1.18)
	# разметка дороги
	var mid := (w.road_row + 1) * T
	for x in range(-CityBackdrop.M, w.w + CityBackdrop.M):
		if x % 2 == 0:
			draw_rect(Rect2(x * T + 4, mid - 1.5, 22, 3), Color(0.92, 0.92, 0.86, 0.85))
	draw_rect(Rect2(-CityBackdrop.M * T, (w.road_row + 3) * T - 2, (w.w + 2 * CityBackdrop.M) * T, 2), Color(0.9, 0.9, 0.85, 0.6))
	# продолжение дороги и тротуара за краями карты
	for x in range(-CityBackdrop.M, 0):
		_draw_outside_column(x, side, road)
	for x in range(w.w, w.w + CityBackdrop.M):
		_draw_outside_column(x, side, road)


# ---------------------------------------------------------------- 1.19: земля богаче

var _nz := PackedFloat32Array()   ## тон в узлах сетки клеток (-1..1): плавные пятна — сухая трава, сырая земля
var _nzw := 0


static func _hf(x: int, y: int, s: int) -> float:
	return float(absi((x * 92837111) ^ (y * 689287499) ^ (s * 283923481)) % 10007) / 10006.0


## Шум значений: крупные пятна (шаг 6 клеток) + мелкие (шаг 2), билинейно — без квадратов.
static func _vn(x: float, y: float, step: float, s: int) -> float:
	var fx := x / step
	var fy := y / step
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := lerpf(_hf(x0, y0, s), _hf(x0 + 1, y0, s), tx)
	var b := lerpf(_hf(x0, y0 + 1, s), _hf(x0 + 1, y0 + 1, s), tx)
	return lerpf(a, b, ty)


func _noise_cache(w: World) -> void:
	if _nzw == w.w + 1 and _nz.size() == (w.w + 1) * (w.h + 1):
		return
	_nzw = w.w + 1
	_nz.resize((w.w + 1) * (w.h + 1))
	for y in w.h + 1:
		for x in w.w + 1:
			var v := 0.7 * _vn(float(x), float(y), 6.0, 11) + 0.3 * _vn(float(x), float(y), 2.0, 23)
			_nz[y * _nzw + x] = clampf((v - 0.5) * 2.4, -1.0, 1.0)


func _tone(gk: int, t: float) -> Color:
	match gk:
		World.Ground.GRASS:
			# t < 0 — подсохшая (желтее и светлее), t > 0 — сочная (темнее, зеленее)
			if t < 0.0:
				return Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.95, 0.74), -t)
			return Color(1.0, 1.0, 1.0).lerp(Color(0.8, 0.9, 0.78), t)
		World.Ground.ASPHALT:
			var v := 0.95 + 0.05 * t
			return Color(v, v, v)
		_:
			# грунт: сырые пятна темнее и теплее
			if t > 0.0:
				return Color(1.0, 1.0, 1.0).lerp(Color(0.84, 0.81, 0.76), t)
			return Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.98, 0.93), -t)


## Клетка земли: текстура в случайном повороте/отражении, тон плавно меняется по углам клетки.
func _ground_cell(tex: Texture2D, x: int, y: int, hv: int, gk: int) -> void:
	var p := Vector2(x * T, y * T)
	var pts := PackedVector2Array([p, p + Vector2(T, 0), p + Vector2(T, T), p + Vector2(0, T)])
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var o := (hv >> 3) % 8   # 8 ориентаций: 4 поворота × отражение
	if o >= 4:
		uv = [uv[1], uv[0], uv[3], uv[2]]
	for k in o % 4:
		uv = [uv[1], uv[2], uv[3], uv[0]]
	var cols := PackedColorArray([_tone(gk, _nz[y * _nzw + x]), _tone(gk, _nz[y * _nzw + x + 1]),
		_tone(gk, _nz[(y + 1) * _nzw + x + 1]), _tone(gk, _nz[(y + 1) * _nzw + x])])
	draw_polygon(pts, cols, PackedVector2Array(uv), tex)


## Кромки газона: пучки травы свешиваются на соседний грунт — газон не «квадратами».
func _draw_grass_edges() -> void:
	var w := sim.world
	var ed := {Vector2i(0, 1): Tex.tile("grass_edge_s"), Vector2i(0, -1): Tex.tile("grass_edge_n"),
		Vector2i(1, 0): Tex.tile("grass_edge_e"), Vector2i(-1, 0): Tex.tile("grass_edge_w")}
	for y in w.h:
		for x in w.w:
			var i := w.idx(Vector2i(x, y))
			if w.flr[i] != 0 or w.ground[i] != World.Ground.GRASS:
				continue
			for d: Vector2i in ed.keys():
				var n := Vector2i(x, y) + d
				if not w.inb(n):
					continue
				var j := w.idx(n)
				if w.flr[j] != 0 or w.ground[j] == World.Ground.GRASS:
					continue
				var tex: Texture2D = ed[d]
				var tone := _tone(World.Ground.GRASS, _nz[y * _nzw + x])
				match d:
					Vector2i(0, 1):
						draw_texture_rect(tex, Rect2(x * T, (y + 1) * T, T, 8), false, tone)
					Vector2i(0, -1):
						draw_texture_rect(tex, Rect2(x * T, y * T - 8, T, 8), false, tone)
					Vector2i(1, 0):
						draw_texture_rect(tex, Rect2((x + 1) * T, y * T, 8, T), false, tone)
					_:
						draw_texture_rect(tex, Rect2(x * T - 8, y * T, 8, T), false, tone)


## Затенение пола у стен (ambient occlusion): в углах и вдоль стен пол темнее — у помещений появляется глубина.
func _draw_ao() -> void:
	var w := sim.world
	var dk := Color(0.0, 0.02, 0.05, 0.30)
	var clear := Color(0.0, 0.02, 0.05, 0.0)
	for y in w.h:
		for x in w.w:
			var c := Vector2i(x, y)
			if w.flr[w.idx(c)] <= 0 or Defs.wall_solid(w.wall[w.idx(c)]):
				continue
			var p := Vector2(x * T, y * T)
			if _solid(c + Vector2i(0, -1)):
				_grad(p, p + Vector2(T, 0), Vector2(0, 14), dk, clear)
			if _solid(c + Vector2i(-1, 0)):
				_grad(p, p + Vector2(0, T), Vector2(11, 0), Color(dk, 0.24), clear)
			if _solid(c + Vector2i(1, 0)):
				_grad(p + Vector2(T, 0), p + Vector2(T, T), Vector2(-11, 0), Color(dk, 0.24), clear)
			if _solid(c + Vector2i(0, 1)):
				_grad(p + Vector2(0, T), p + Vector2(T, T), Vector2(0, -7), Color(dk, 0.16), clear)


func _solid(c: Vector2i) -> bool:
	var v := sim.world.get_wall(c)
	return WallKinds.is_plain(v) or v == World.W_WINDOW


## Полоса тени от линии a–b внутрь на вектор d: от цвета c0 у стены к c1.
func _grad(a: Vector2, b: Vector2, d: Vector2, c0: Color, c1: Color) -> void:
	draw_polygon(PackedVector2Array([a, b, b + d, a + d]), PackedColorArray([c0, c0, c1, c1]))


func _draw_outside_column(x: int, side: Texture2D, road: Array) -> void:
	var w := sim.world
	draw_texture_rect(side, Rect2(x * T, w.sidewalk_row * T, T, T), false)
	for y in range(w.sidewalk_row + 1, w.sidewalk_row + 5):
		draw_texture_rect(road[vhash(x, y) % 2], Rect2(x * T, y * T, T, T), false)


func _draw_cross(r: Rect2, col: Color) -> void:
	var a := r.grow(-6)
	draw_line(a.position, a.end, col, 3.0)
	draw_line(Vector2(a.end.x, a.position.y), Vector2(a.position.x, a.end.y), col, 3.0)


func _vertical(c: Vector2i) -> bool:
	return WallKinds.is_room_wall(sim.world.get_wall(c + Vector2i(0, -1))) or WallKinds.is_room_wall(sim.world.get_wall(c + Vector2i(0, 1)))
