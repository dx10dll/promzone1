class_name WallPiece
extends Node2D
## Одна клетка стены/окна/двери/ворот/забора. Узел стоит в нижнем крае клетки (для сортировки по Y).
## Вся стена рисуется строго внутри своей клетки: сверху — тёмная «шапка» (вид сверху),
## внизу — лицевая грань из кирпича высотой FACE (если ниже нет другой стены).
## Тот же код рисует и чертежи (призраки) недостроенных стен, окон, дверей и ворот.

const T := World.T
const FACE := 12.0                        ## высота лицевой грани внутри клетки
const CAP := Color("#33373d")
const OPEN_CAP := Color("#7e4f3d")
const CAP_EDGE := Color("#50565e")
const CAP_DARK := Color("#1d2023")
const FRAME := Color("#dcdfd9")
const FRAME_DARK := Color("#7d8388")
const GLASS := Color("#8fbcd6")
const GLASS_HI := Color("#d8ecf5")
const WOOD := Color("#8a6646")
const WOOD_DARK := Color("#5e432c")
const STEEL := Color("#8b9296")
const STEEL_DARK := Color("#5c6368")
const GHOST_FILL := Color(0.42, 0.66, 1.0, 0.42)
const GHOST_LINE := Color(0.70, 0.86, 1.0, 0.95)

var sim: Sim
var cell := Vector2i.ZERO
var kind := 0
var nb: Dictionary = {}
var _open_t := 0.0      ## 0 — дверь закрыта, 1 — открыта
var _open_goal := 0.0
var _swing := 1.0        ## куда открывается створка: +1 вниз/вправо, −1 вверх/влево
var _glow_t := 0.0       ## таймер проверки: светится ли окно ночью


func setup(s: Sim, c: Vector2i) -> void:
	sim = s
	cell = c
	kind = s.world.get_wall(c)
	position = Vector2(c.x * T, (c.y + 1) * T)
	nb = neighbors(s.world, c, kind, false)
	if WallKinds.is_fence(kind):
		_setup_fence()
	if WallKinds.is_door(kind):
		_swing = _swing_dir()
	set_process(WallKinds.is_door(kind) or WallKinds.is_gate(kind) or kind == World.W_WINDOW)
	_glow_t = randf() * 1.5
	queue_redraw()


## Соседи клетки: какие стороны примыкают к стене помещения, в какой ориентации проём.
## with_bp — учитывать чертежи (для призраков).
static func neighbors(w: World, c: Vector2i, k: int, with_bp: bool) -> Dictionary:
	var f := func(d: Vector2i) -> int:
		var n := c + d
		if not w.inb(n):
			return World.W_NONE
		var v := w.wall[w.idx(n)]
		if v == World.W_NONE and with_bp:
			var b := w.bp_wall[w.idx(n)]
			if b != World.BP_NONE and b != 0:
				return b
		return v
	var up: int = f.call(Vector2i(0, -1))
	var dn: int = f.call(Vector2i(0, 1))
	var lf: int = f.call(Vector2i(-1, 0))
	var rt: int = f.call(Vector2i(1, 0))
	var d := {"up": WallKinds.is_room_wall(up), "dn": WallKinds.is_room_wall(dn),
		"lf": WallKinds.is_room_wall(lf), "rt": WallKinds.is_room_wall(rt)}
	# ориентация проёма: стена сверху и снизу (и не с обеих сторон по горизонтали) — вертикальная
	var ud := bool(d["up"]) and bool(d["dn"])
	var lr := bool(d["lf"]) and bool(d["rt"])
	var vert := false
	if ud and not lr:
		vert = true
	elif not (bool(d["lf"]) or bool(d["rt"])):
		vert = bool(d["up"]) or bool(d["dn"])
	d["vert"] = vert
	# у ворот — продолжается ли проём в соседнюю клетку (столбы только по краям)
	d["same_a"] = (lf == k) if not d["vert"] else (up == k)
	d["same_b"] = (rt == k) if not d["vert"] else (dn == k)
	return d


func _swing_dir() -> float:
	var vert := bool(nb.get("vert", false))
	var a := cell + (Vector2i(-1, 0) if vert else Vector2i(0, -1))
	var b := cell + (Vector2i(1, 0) if vert else Vector2i(0, 1))
	var ra := sim.rooms.room_at(a) != null
	var rb := sim.rooms.room_at(b) != null
	if ra and not rb:
		return -1.0
	return 1.0


func _setup_fence() -> void:
	var w := sim.world
	var l := WallKinds.is_fence(w.get_wall(cell + Vector2i(-1, 0)))
	var r := WallKinds.is_fence(w.get_wall(cell + Vector2i(1, 0)))
	var sp := Sprite2D.new()
	sp.centered = false
	sp.scale = Vector2(0.5, 0.5)
	if l or r:
		sp.texture = Tex.tile("fence_h")
		sp.position = Vector2(0, -22 - 8)
	else:
		sp.texture = Tex.tile("fence_v")
		sp.position = Vector2(0, -T)
	add_child(sp)
	# столбы у въезда
	if w.get_wall(cell + Vector2i(1, 0)) == World.W_FENCE_GATE or w.get_wall(cell + Vector2i(-1, 0)) == World.W_FENCE_GATE:
		var post := Sprite2D.new()
		post.texture = Tex.tile("fence_post")
		post.centered = false
		post.scale = Vector2(0.5, 0.5)
		post.position = Vector2(0, -24 - 6)
		add_child(post)


func set_door_open(v: bool) -> void:
	if not WallKinds.is_door(kind) and not WallKinds.is_gate(kind):
		return
	_open_goal = 1.0 if v else 0.0


func _process(delta: float) -> void:
	if kind == World.W_WINDOW or kind == World.W_DOOR or kind == World.W_GLASS_DOOR or kind == World.W_DOOR_GREEN:
		_glow_t -= delta
		if _glow_t <= 0.0:
			_glow_t = 1.5
			var g := _lit_inside()
			if g != bool(nb.get("glow", false)):
				nb["glow"] = g
				queue_redraw()
	if kind == World.W_WINDOW or absf(_open_t - _open_goal) < 0.001:
		return
	_open_t = move_toward(_open_t, _open_goal, delta * (4.5 if WallKinds.is_door(kind) else 2.2))
	queue_redraw()


## Ночью окно светится тёплым светом, если в помещении за ним горят лампы.
func _lit_inside() -> bool:
	if sim == null or sim.is_daylight():
		return false
	var w := sim.world
	if sim.light.size() != w.w * w.h:
		return false
	var vert := bool(nb.get("vert", false))
	for dd: Vector2i in ([Vector2i(-1, 0), Vector2i(1, 0)] if vert else [Vector2i(0, -1), Vector2i(0, 1)]):
		var c := cell + dd
		if w.inb(c) and sim.light[w.idx(c)] != 0:
			return true
	return false


func _draw() -> void:
	if WallKinds.is_fence(kind):
		return
	paint(self, kind, Vector2(0, -T), nb, _open_t, _swing, false)


# ================================================================ рисование

static func _col(c: Color, ghost: bool, line: bool = false) -> Color:
	if not ghost:
		return c
	return GHOST_LINE if line else GHOST_FILL


## Нарисовать клетку стены kind с левым верхним углом o на холсте ci.
static func paint(ci: CanvasItem, k: int, o: Vector2, d: Dictionary, open_t: float, swing: float, ghost: bool) -> void:
	match k:
		World.W_BRICK, World.W_CONCRETE, World.W_SANDWICH, World.W_PARTITION, World.W_SILICATE, World.W_GASBLOCK:
			_paint_brick(ci, o, d, ghost, k)
		World.W_WINDOW:
			if not ghost:
				# 1.19.1: под окном — та же стена: скаты и гребень идут сквозь, окно поверх (стена монолитом)
				var vert := bool(d.get("vert", false))
				_paint_brick(ci, o, {"up": vert, "dn": vert, "lf": not vert, "rt": not vert}, false, World.W_BRICK)
			_paint_window(ci, o, d, ghost)
		World.W_DOOR, World.W_METAL_DOOR, World.W_GLASS_DOOR, World.W_DOOR_BROWN, World.W_DOOR_GREEN:
			_paint_door(ci, o, d, open_t, swing, ghost, k == World.W_METAL_DOOR, k == World.W_GLASS_DOOR,
				"brown" if k == World.W_DOOR_BROWN else ("green" if k == World.W_DOOR_GREEN else ""))
		World.W_GATE, World.W_GATE_WARM:
			_paint_gate(ci, o, d, ghost, open_t, k == World.W_GATE_WARM)


## Фактуры глухих стен (1.12): шапка и лицевая грань.
const PLAIN_TEX := {World.W_BRICK: ["wall_top", "wall_face"], World.W_CONCRETE: ["wall_top_concrete", "wall_face_concrete"],
	World.W_SANDWICH: ["wall_top_sandwich", "wall_face_sandwich"], World.W_PARTITION: ["wall_top_partition", "wall_face_partition"]}


## Шапка стены с подсветкой открытых краёв.
static func _cap(ci: CanvasItem, r: Rect2, d: Dictionary, ghost: bool, key: String = "wall_top") -> void:
	var tex: Texture2D = null if ghost else Tex.tile(key)
	if tex:
		# фактура верха стены, непрерывная от клетки к клетке
		var o := Vector2(fposmod(r.position.x, T), fposmod(r.position.y, T))
		ci.draw_texture_rect_region(tex, r, Rect2(o * 2.0, r.size * 2.0))
	else:
		ci.draw_rect(r, _col(CAP, ghost))
	if ghost:
		ci.draw_rect(r.grow(-0.5), GHOST_LINE, false, 1.0)
		return
	if not bool(d.get("up", false)):
		ci.draw_line(r.position + Vector2(0, 1), Vector2(r.end.x, r.position.y + 1), CAP_EDGE, 2.0)
	if not bool(d.get("lf", false)):
		ci.draw_line(r.position + Vector2(1, 0), Vector2(r.position.x + 1, r.end.y), CAP_EDGE, 2.0)
	if not bool(d.get("rt", false)):
		ci.draw_line(Vector2(r.end.x - 1, r.position.y), Vector2(r.end.x - 1, r.end.y), CAP_DARK, 2.0)


## Кирпичная лицевая грань по ширине [x0, x0 + wd] в нижней части клетки.
static func _face(ci: CanvasItem, o: Vector2, x0: float, wd: float, ghost: bool, key: String = "wall_face") -> void:
	var r := Rect2(o + Vector2(x0, T - FACE), Vector2(wd, FACE))
	if ghost:
		ci.draw_rect(r, Color(0.35, 0.55, 0.9, 0.5))
		ci.draw_rect(r.grow(-0.5), GHOST_LINE, false, 1.0)
		return
	var tex := Tex.tile(key)
	if tex:
		ci.draw_texture_rect_region(tex, r, Rect2(x0 * 2.0, 0, wd * 2.0, FACE * 2.0))
	else:
		ci.draw_rect(r, Color("#6e5a4c"))
	ci.draw_line(r.position, Vector2(r.end.x, r.position.y), CAP_DARK, 1.0)
	# лёгкая тень на полу под стеной
	ci.draw_rect(Rect2(r.position.x, r.end.y, wd, 3.0), Color(0, 0, 0, 0.16))


## 1.19.1: глухая стена «пирамидкой» (вид сверху): по середине — узкий светлый гребень вдоль стены,
## от него к краям клетки — скаты из кирпича (бетона, панелей). Свет сверху-слева: северный скат светлее,
## восточный темнее. Со стороны соседней стены ската нет — гребень идёт дальше.
const SLOPE_TEX := {World.W_BRICK: "brick", World.W_CONCRETE: "concrete", World.W_SANDWICH: "sandwich", World.W_PARTITION: "partition",
	World.W_SILICATE: "silicate", World.W_GASBLOCK: "gasblock"}
const RIDGE := Color("#d8d1bf")
const RIDGE_EDGE := Color("#8d8574")
const SHADE := {"up": 1.0, "lf": 0.9, "dn": 0.74, "rt": 0.64}


static func _paint_brick(ci: CanvasItem, o: Vector2, d: Dictionary, ghost: bool, k: int = World.W_BRICK) -> void:
	if ghost:
		var keys: Array = PLAIN_TEX.get(k, PLAIN_TEX[World.W_BRICK])
		var face := not bool(d.get("dn", false))
		_cap(ci, Rect2(o, Vector2(T, T - FACE if face else T)), d, ghost, str(keys[0]))
		if face:
			_face(ci, o, 0.0, T, ghost, str(keys[1]))
		return
	var nm := str(SLOPE_TEX.get(k, "brick"))
	var th: Texture2D = Tex.tile("wslope_%s_h" % nm)
	var tv: Texture2D = Tex.tile("wslope_%s_v" % nm)
	var c := Vector2(T, T) * 0.5
	var corner := {"up": [Vector2(0, 0), Vector2(T, 0)], "rt": [Vector2(T, 0), Vector2(T, T)],
		"dn": [Vector2(T, T), Vector2(0, T)], "lf": [Vector2(0, T), Vector2(0, 0)]}
	var mid := {"up": Vector2(T * 0.5, 0), "rt": Vector2(T, T * 0.5), "dn": Vector2(T * 0.5, T), "lf": Vector2(0, T * 0.5)}
	# у какого угла какая соседняя сторона: [сторона, угол]
	var perp := {"up": ["lf", "rt"], "rt": ["up", "dn"], "dn": ["rt", "lf"], "lf": ["dn", "up"]}
	for sd: String in ["up", "rt", "dn", "lf"]:
		var cs: Array = corner[sd]
		if not bool(d.get(sd, false)):
			_tri(ci, o, [cs[0], cs[1], c], th if sd == "up" or sd == "dn" else tv, float(SHADE[sd]))
		else:
			# сторона примыкает к соседней стене — её треугольник делят скаты соседних сторон
			var pa: String = perp[sd][0]
			var pb: String = perp[sd][1]
			for h in 2:
				var p_side: String = pa if h == 0 else pb
				var tri := [cs[0], mid[sd], c] if h == 0 else [mid[sd], cs[1], c]
				var open := not bool(d.get(p_side, false))
				var tex := th if p_side == "up" or p_side == "dn" else tv
				_tri(ci, o, tri, tex, float(SHADE[p_side]) if open else 0.82)
	# внешние края скатов — тёмная кромка, под южным — тень на полу
	for sd2: String in ["up", "rt", "dn", "lf"]:
		if bool(d.get(sd2, false)):
			continue
		var e: Array = corner[sd2]
		ci.draw_line(o + e[0], o + e[1], CAP_DARK, 1.2)
	if not bool(d.get("dn", false)):
		ci.draw_rect(Rect2(o.x, o.y + T, T, 3.0), Color(0, 0, 0, 0.16))
	# гребень: от центра к каждой соседней стене, узкой светлой полосой; кромки — сплошными линиями
	# до края клетки, чтобы у соседней клетки они продолжались без разрывов (стены — монолитом)
	var r := 3.0 if k == World.W_PARTITION else 5.0
	var sq := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	var conn := 0
	for sd3: String in ["up", "rt", "dn", "lf"]:
		if bool(d.get(sd3, false)):
			conn += 1
	if conn == 0:
		sq = sq.grow(r * 0.6)
	var arms := {"up": Rect2(c.x - r, 0, r * 2.0, c.y - r), "dn": Rect2(c.x - r, c.y + r, r * 2.0, T - c.y - r),
		"lf": Rect2(0, c.y - r, c.x - r, r * 2.0), "rt": Rect2(c.x + r, c.y - r, T - c.x - r, r * 2.0)}
	ci.draw_rect(Rect2(o + sq.position, sq.size), RIDGE)
	for sd4: String in ["up", "rt", "dn", "lf"]:
		if bool(d.get(sd4, false)):
			var ar: Rect2 = arms[sd4]
			ci.draw_rect(Rect2(o + ar.position, ar.size), RIDGE)
	var ew := 1.0
	for sd5: String in ["up", "rt", "dn", "lf"]:
		var ar2: Rect2 = arms[sd5]
		if bool(d.get(sd5, false)):
			# длинные кромки рукава гребня
			if sd5 == "up" or sd5 == "dn":
				ci.draw_line(o + Vector2(ar2.position.x, ar2.position.y), o + Vector2(ar2.position.x, ar2.end.y), RIDGE_EDGE, ew)
				ci.draw_line(o + Vector2(ar2.end.x, ar2.position.y), o + Vector2(ar2.end.x, ar2.end.y), RIDGE_EDGE, ew)
			else:
				ci.draw_line(o + Vector2(ar2.position.x, ar2.position.y), o + Vector2(ar2.end.x, ar2.position.y), RIDGE_EDGE, ew)
				ci.draw_line(o + Vector2(ar2.position.x, ar2.end.y), o + Vector2(ar2.end.x, ar2.end.y), RIDGE_EDGE, ew)
		else:
			# сторона центральной площадки, куда гребень не идёт
			match sd5:
				"up":
					ci.draw_line(o + sq.position, o + Vector2(sq.end.x, sq.position.y), RIDGE_EDGE, ew)
				"dn":
					ci.draw_line(o + Vector2(sq.position.x, sq.end.y), o + sq.end, RIDGE_EDGE, ew)
				"lf":
					ci.draw_line(o + sq.position, o + Vector2(sq.position.x, sq.end.y), RIDGE_EDGE, ew)
				_:
					ci.draw_line(o + Vector2(sq.end.x, sq.position.y), o + sq.end, RIDGE_EDGE, ew)


## Треугольник ската с фактурой (UV — в пределах клетки) и затенением.
static func _tri(ci: CanvasItem, o: Vector2, pts: Array, tex: Texture2D, shade: float) -> void:
	var pp := PackedVector2Array()
	var uv := PackedVector2Array()
	var col := Color(shade, shade, shade)
	for q: Vector2 in pts:
		pp.append(o + q)
		uv.append(q / T)
	if tex:
		ci.draw_polygon(pp, PackedColorArray([col, col, col]), uv, tex)
	else:
		ci.draw_colored_polygon(pp, Color(0.55 * shade, 0.36 * shade, 0.28 * shade))


## Многоугольник с фактурой верха стены (фактура непрерывна от клетки к клетке), с оттенком col.
static func _poly(ci: CanvasItem, tex: Texture2D, o: Vector2, pts: Array, col: Color) -> void:
	var pp := PackedVector2Array()
	var uv := PackedVector2Array()
	var cs := PackedColorArray()
	var base := Vector2(fposmod(o.x, T), fposmod(o.y, T))
	for q: Vector2 in pts:
		pp.append(o + q)
		uv.append((base + q) / T)
		cs.append(col)
	if tex:
		ci.draw_polygon(pp, cs, uv, tex)
	else:
		ci.draw_colored_polygon(pp, Color(CAP.r * col.r, CAP.g * col.g, CAP.b * col.b))


## Края проёма: начинается ли здесь окно/дверь/ворота (a — слева/сверху) и кончается ли (b — справа/снизу).
## Несколько клеток подряд рисуются как один объект: рама и откосы только по краям.
static func _ends(d: Dictionary) -> Array:
	return [not bool(d.get("same_a", false)), not bool(d.get("same_b", false))]


## Стекло с вертикальным (или, для боковой стены, горизонтальным) переливом и бликами.
static func _glass(ci: CanvasItem, r: Rect2, ghost: bool, side: bool, glow: bool) -> void:
	if ghost:
		ci.draw_rect(r, GHOST_FILL)
		return
	var top := Color("#d6edf7") if not glow else Color("#fff0c2")
	var bot := Color("#6fa3c4") if not glow else Color("#efb95c")
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([top, top, bot, bot]) if not side else PackedColorArray([top, bot, bot, top])
	ci.draw_polygon(pts, cols)
	if glow:
		return
	# два косых блика
	var hi := Color(1, 1, 1, 0.42)
	if not side:
		var k := r.size.y * 0.45
		for f: float in [0.30, 0.62]:
			var x := r.position.x + r.size.x * f
			var wd := 3.0 if f < 0.5 else 1.6
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x, r.position.y), Vector2(x + wd, r.position.y), Vector2(x + wd - k, r.end.y), Vector2(x - k, r.end.y)]), hi)
	else:
		var k2 := r.size.x * 0.45
		for f2: float in [0.30, 0.62]:
			var y := r.position.y + r.size.y * f2
			var hd := 3.0 if f2 < 0.5 else 1.6
			ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, y), Vector2(r.position.x, y + hd), Vector2(r.end.x, y + hd - k2), Vector2(r.end.x, y - k2)]), hi)


## Окно — один объект во всю длину проёма: светлая рама, переплёт, стекло с бликами, подоконник.
## В горизонтальной стене видно спереди (сбоку), в вертикальной — та же рама, повёрнутая вдоль стены.
static func _paint_window(ci: CanvasItem, o: Vector2, d: Dictionary, ghost: bool) -> void:
	var vert := bool(d.get("vert", false))
	var e := _ends(d)
	var a_end: bool = e[0]
	var b_end: bool = e[1]
	var glow := bool(d.get("glow", false))
	var cap := _col(OPEN_CAP, ghost)   # 1.19.1: откосы проёмов — кирпичные, как скаты стен
	var fr := _col(FRAME, ghost, true)
	var frd := _col(FRAME_DARK, ghost, true)
	var j := 3.0
	if not vert:
		var face := not bool(d.get("dn", false))
		var bottom := T - 6.0 if face else T - 3.0
		# верх стены над окном и откосы по краям проёма
		ci.draw_rect(Rect2(o, Vector2(T, 3.0)), cap)
		if a_end:
			ci.draw_rect(Rect2(o + Vector2(0, 3.0), Vector2(j, T - 3.0)), cap)
		if b_end:
			ci.draw_rect(Rect2(o + Vector2(T - j, 3.0), Vector2(j, T - 3.0)), cap)
		if face:
			# кирпичный цоколь под окном
			var x0 := j if a_end else 0.0
			var x1 := T - j if b_end else T
			var tex := Tex.tile("wall_face")
			var pr := Rect2(o + Vector2(x0, bottom), Vector2(x1 - x0, T - bottom))
			if ghost:
				ci.draw_rect(pr, Color(0.35, 0.55, 0.9, 0.5))
			elif tex:
				ci.draw_texture_rect_region(tex, pr, Rect2(x0 * 2.0, (FACE - (T - bottom)) * 2.0, (x1 - x0) * 2.0, (T - bottom) * 2.0))
			else:
				ci.draw_rect(pr, Color("#6e5a4c"))
		# рама
		var fx0 := o.x + (j if a_end else 0.0)
		var fx1 := o.x + T - (j if b_end else 0.0)
		var fy0 := o.y + 3.0
		var fy1 := o.y + bottom
		var fr_r := Rect2(fx0, fy0, fx1 - fx0, fy1 - fy0)
		ci.draw_rect(fr_r, fr)
		var gx0 := fx0 + (2.0 if a_end else 0.0)
		var gx1 := fx1 - (2.0 if b_end else 0.0)
		var g := Rect2(gx0, fy0 + 2.0, gx1 - gx0, fy1 - fy0 - 4.0)
		_glass(ci, g, ghost, false, glow)
		# переплёт: стойка посередине клетки, форточка сверху, стык рам между клетками
		var mx := o.x + T * 0.5
		ci.draw_rect(Rect2(mx - 0.75, g.position.y, 1.5, g.size.y), fr)
		var ty := g.position.y + g.size.y * 0.36
		ci.draw_rect(Rect2(g.position.x, ty - 0.75, g.size.x, 1.5), fr)
		if not a_end:
			ci.draw_rect(Rect2(o.x - 1.0, fy0, 2.0, fy1 - fy0), fr)
		if not ghost:
			ci.draw_rect(fr_r, frd, false, 1.0)
			if not a_end:
				ci.draw_line(Vector2(o.x, fy0), Vector2(o.x, fy0 + 1.0), frd, 1.0)
		# подоконник-отлив
		if face:
			ci.draw_rect(Rect2(fx0 - (1.5 if a_end else 0.0), fy1 - 1.0, fx1 - fx0 + (1.5 if a_end else 0.0) + (1.5 if b_end else 0.0), 2.5), _col(Color("#cfd2cc"), ghost, true))
			if not ghost:
				ci.draw_rect(Rect2(fx0, fy1 + 1.5, fx1 - fx0, 1.5), Color(0, 0, 0, 0.25))
		return
	# окно в вертикальной стене: та же рама, повёрнутая вдоль стены
	ci.draw_rect(Rect2(o, Vector2(4.0, T)), cap)
	ci.draw_rect(Rect2(o + Vector2(T - 4.0, 0), Vector2(4.0, T)), cap)
	if a_end:
		ci.draw_rect(Rect2(o, Vector2(T, j)), cap)
	if b_end:
		ci.draw_rect(Rect2(o + Vector2(0, T - j), Vector2(T, j)), cap)
	var vy0 := o.y + (j if a_end else 0.0)
	var vy1 := o.y + T - (j if b_end else 0.0)
	var vr := Rect2(o.x + 4.0, vy0, T - 8.0, vy1 - vy0)
	ci.draw_rect(vr, fr)
	var vg := Rect2(vr.position.x + 2.0, vy0 + (2.0 if a_end else 0.0), vr.size.x - 4.0, vy1 - vy0 - (2.0 if a_end else 0.0) - (2.0 if b_end else 0.0))
	_glass(ci, vg, ghost, true, glow)
	var my := o.y + T * 0.5
	ci.draw_rect(Rect2(vg.position.x, my - 0.75, vg.size.x, 1.5), fr)
	var tx := vg.position.x + vg.size.x * 0.36
	ci.draw_rect(Rect2(tx - 0.75, vg.position.y, 1.5, vg.size.y), fr)
	if not a_end:
		ci.draw_rect(Rect2(vr.position.x, o.y - 1.0, vr.size.x, 2.0), fr)
	if not ghost:
		ci.draw_rect(vr, frd, false, 1.0)
		# подоконники с обеих сторон — видна толщина стены
		ci.draw_rect(Rect2(o.x + 2.5, vy0, 1.5, vy1 - vy0), Color("#cfd2cc"))
		ci.draw_rect(Rect2(o.x + T - 4.0, vy0, 1.5, vy1 - vy0), Color("#cfd2cc"))


## Дверь: проём во всю клетку, полотно отъезжает в стену, когда кто-то проходит.
## Две двери подряд — одна двустворчатая: створки разъезжаются в разные стороны.
## 1.40: style — «brown» (простая коричневая, глухая: цеха и склады) или «green» (зелёная филёнчатая со стеклом: кабинеты).
const DOOR_STYLES := {
	"brown": {"frame": "#6b4a30", "leaf": "#6e4a2e", "dark": "#3f2a1a", "up": "#5b3c24", "lo": "#5b3c24"},
	"green": {"frame": "#e4e2d8", "leaf": "#3f7a52", "dark": "#22452f", "up": "#2f5f3f", "lo": "#356a46"},
}


static func _paint_door(ci: CanvasItem, o: Vector2, d: Dictionary, open_t: float, _swing: float, ghost: bool, metal: bool = false, glass: bool = false, style: String = "") -> void:
	var vert := bool(d.get("vert", false))
	var e := _ends(d)
	var a_end: bool = e[0]
	var b_end: bool = e[1]
	var cap := _col(OPEN_CAP, ghost)   # 1.19.1: откосы проёмов — кирпичные, как скаты стен
	var frame := _col(Color("#d9dcd6") if not metal else Color("#6f767b"), ghost, true)
	var leaf_c := _col(WOOD if not metal else Color("#7c858b"), ghost)
	if glass:
		frame = _col(Color("#c9ced2"), ghost, true)
		leaf_c = _col(Color("#aab3b9"), ghost)
	var leaf_d := _col(WOOD_DARK if not metal else Color("#4b5257"), ghost, true)
	var sty: Dictionary = DOOR_STYLES.get(style, {})
	if not sty.is_empty():
		frame = _col(Color(str(sty["frame"])), ghost, true)
		leaf_c = _col(Color(str(sty["leaf"])), ghost)
		leaf_d = _col(Color(str(sty["dark"])), ghost, true)
	var j := 3.0
	# куда уезжает створка: одиночная — к началу проёма, в двустворчатой — от соседней створки
	var to_a := a_end or not b_end
	if not a_end and b_end:
		to_a = false
	if a_end and not b_end:
		to_a = true
	var shown := 1.0 - clampf(open_t, 0.0, 1.0) * 0.9
	if not vert:
		# вид спереди: перемычка, откосы, наличник, тёмный проём, полотно с филёнками и ручкой
		ci.draw_rect(Rect2(o, Vector2(T, 3.0)), cap)
		if a_end:
			ci.draw_rect(Rect2(o + Vector2(0, 3.0), Vector2(j, T - 3.0)), cap)
		if b_end:
			ci.draw_rect(Rect2(o + Vector2(T - j, 3.0), Vector2(j, T - 3.0)), cap)
		var x0 := o.x + (j if a_end else 0.0)
		var x1 := o.x + T - (j if b_end else 0.0)
		ci.draw_rect(Rect2(x0, o.y + 3.0, x1 - x0, 2.0), frame)
		if a_end:
			ci.draw_rect(Rect2(x0, o.y + 3.0, 2.0, T - 3.0), frame)
			x0 += 2.0
		if b_end:
			ci.draw_rect(Rect2(x1 - 2.0, o.y + 3.0, 2.0, T - 3.0), frame)
			x1 -= 2.0
		var y0 := o.y + 5.0
		var y1 := o.y + T - 1.0
		if not ghost and open_t < 0.98:
			ci.draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), Color(0.06, 0.07, 0.08, 0.55 * (1.0 - open_t)))
		var lw := (x1 - x0) * shown
		var lx := x0 if to_a else x1 - lw
		var lr := Rect2(lx, y0, lw, y1 - y0)
		ci.draw_rect(lr, leaf_c)
		if not ghost and lw > 4.0:
			# филёнки: верхняя — со стеклом
			var pw := lr.size.x - 6.0
			var px := lr.position.x + 3.0
			if pw > 2.0 and glass:
				# остеклённая дверь: алюминиевая рама, стекло почти на всё полотно
				var gp := Rect2(px, y0 + 2.5, pw, y1 - y0 - 6.0)
				_glass(ci, gp, false, false, bool(d.get("glow", false)))
				ci.draw_rect(Rect2(px, y0 + (y1 - y0) * 0.55, pw, 1.5), Color("#8f989e"))
			elif pw > 2.0 and metal:
				# стальная дверь: без стекла, рёбра жёсткости и глазок
				for kk in 3:
					var ry := y0 + 6.0 + kk * (y1 - y0 - 12.0) / 2.0
					ci.draw_rect(Rect2(px, ry, pw, 2.0), Color("#5d656a"))
					ci.draw_line(Vector2(px, ry + 2.5), Vector2(px + pw, ry + 2.5), Color(1, 1, 1, 0.14), 1.0)
				ci.draw_circle(Vector2(px + pw * 0.5, y0 + 4.0), 1.0, Color("#2a2e31"))
			elif pw > 2.0 and style == "brown":
				# простая дверь: две глухие филёнки, без стекла
				var hh2 := (y1 - y0 - 9.0) * 0.5
				for kk2 in 2:
					var pr := Rect2(px, y0 + 3.0 + kk2 * (hh2 + 3.0), pw, hh2)
					ci.draw_rect(pr, Color(str(sty["up"])))
					ci.draw_line(pr.position + Vector2(0, pr.size.y), pr.end, Color(1, 1, 1, 0.10), 1.0)
			elif pw > 2.0 and style == "green":
				# зелёная филёнчатая: стекло сверху в светлой раскладке, внизу две филёнки
				var up2 := Rect2(px, y0 + 3.0, pw, (y1 - y0) * 0.34)
				ci.draw_rect(up2, Color(str(sty["up"])))
				_glass(ci, up2.grow(-1.0), false, false, bool(d.get("glow", false)))
				ci.draw_line(Vector2(up2.get_center().x, up2.position.y + 1.0), Vector2(up2.get_center().x, up2.end.y - 1.0), Color("#e4e2d8"), 1.0)
				var lo2 := Rect2(px, up2.end.y + 3.0, pw, y1 - up2.end.y - 6.0)
				ci.draw_rect(lo2, Color(str(sty["lo"])))
				ci.draw_rect(lo2.grow(-1.5), Color(1, 1, 1, 0.08), false, 1.0)
			elif pw > 2.0:
				var up := Rect2(px, y0 + 3.0, pw, (y1 - y0) * 0.32)
				ci.draw_rect(up, Color("#5e432c"))
				_glass(ci, up.grow(-1.0), false, false, bool(d.get("glow", false)))
				var lo := Rect2(px, up.end.y + 3.0, pw, y1 - up.end.y - 6.0)
				ci.draw_rect(lo, Color("#7a5a3d"))
				ci.draw_line(lo.position + Vector2(0, lo.size.y), lo.end, Color(1, 1, 1, 0.12), 1.0)
			# ручка у свободного края створки (у зелёной — латунная)
			var hx := lr.end.x - 3.5 if to_a else lr.position.x + 2.0
			ci.draw_rect(Rect2(hx, y0 + (y1 - y0) * 0.52, 1.5, 4.0), Color("#e2b73a") if style == "green" else Color("#d8dbde"))
			ci.draw_line(Vector2(lr.position.x + 1.0, y0 + 1.0), Vector2(lr.position.x + 1.0, y1 - 1.0), Color(1, 1, 1, 0.14), 1.0)
		ci.draw_rect(lr, leaf_d, false, 1.0)
		# порожек
		ci.draw_rect(Rect2(o.x + (j if a_end else 0.0), o.y + T - 1.5, T - (j if a_end else 0.0) - (j if b_end else 0.0), 1.5), _col(Color("#9aa0a4"), ghost))
		return
	# вертикальная стена: вид сверху, полотно-плита вдоль стены уезжает в откос
	if a_end:
		ci.draw_rect(Rect2(o, Vector2(T, 4.0)), cap)
		ci.draw_rect(Rect2(o + Vector2(T * 0.5 - 7.0, 4.0), Vector2(14.0, 1.5)), frame)
	if b_end:
		ci.draw_rect(Rect2(o + Vector2(0, T - 4.0), Vector2(T, 4.0)), cap)
		ci.draw_rect(Rect2(o + Vector2(T * 0.5 - 7.0, T - 5.5), Vector2(14.0, 1.5)), frame)
	var vy0 := o.y + (5.5 if a_end else 0.0)
	var vy1 := o.y + T - (5.5 if b_end else 0.0)
	if not ghost:
		# порог по всей ширине проёма
		ci.draw_rect(Rect2(o.x + T * 0.5 - 7.0, vy0, 14.0, vy1 - vy0), Color(0, 0, 0, 0.10))
	var lh := (vy1 - vy0) * shown
	var ly := vy0 if to_a else vy1 - lh
	var vr := Rect2(o.x + T * 0.5 - 4.5, ly, 9.0, lh)
	ci.draw_rect(vr, leaf_c)
	if not ghost and lh > 4.0:
		var inner_c := Color("#7a5a3d") if not metal else Color("#687076")
		if not sty.is_empty():
			inner_c = Color(str(sty["lo"]))
		ci.draw_rect(Rect2(vr.position.x + 2.0, vr.position.y + 2.0, vr.size.x - 4.0, vr.size.y - 4.0), inner_c)
		ci.draw_line(Vector2(vr.position.x + 1.0, vr.position.y + 1.0), Vector2(vr.position.x + 1.0, vr.end.y - 1.0), Color(1, 1, 1, 0.22), 1.0)
		var hy := vr.end.y - 3.5 if to_a else vr.position.y + 2.0
		ci.draw_rect(Rect2(vr.position.x - 1.5, hy, 2.0, 1.5), Color("#d8dbde"))
		ci.draw_rect(Rect2(vr.end.x - 0.5, hy, 2.0, 1.5), Color("#d8dbde"))
	ci.draw_rect(vr, leaf_d, false, 1.0)


## Ворота — подъёмные секционные: короб сверху, ламели, столбы с жёлто-чёрной разметкой.
## Поднимаются, когда кто-то проходит или проезжает.
static func _paint_gate(ci: CanvasItem, o: Vector2, d: Dictionary, ghost: bool, open_t: float = 0.0, warm: bool = false) -> void:
	var vert := bool(d.get("vert", false))
	var e := _ends(d)
	var a_end: bool = e[0]
	var b_end: bool = e[1]
	var steel := _col(STEEL if not warm else Color("#4f78a8"), ghost)
	var steel_d := _col(STEEL_DARK if not warm else Color("#2f4f78"), ghost, true)
	var box := _col(Color("#4d5459"), ghost)
	var p := 4.0
	var shown := 1.0 - clampf(open_t, 0.0, 1.0) * 0.88
	if not vert:
		var x0 := o.x + (p if a_end else 0.0)
		var x1 := o.x + T - (p if b_end else 0.0)
		var top := o.y + 6.0
		var hgt := (T - 7.0) * shown
		var sr := Rect2(x0, top, x1 - x0, hgt)
		ci.draw_rect(sr, steel)
		if not ghost:
			var yy := top + 3.0
			while yy < top + hgt - 1.0:
				ci.draw_line(Vector2(x0, yy), Vector2(x1, yy), Color("#6f777c") if not warm else Color("#3d618c"), 1.0)
				ci.draw_line(Vector2(x0, yy + 1.0), Vector2(x1, yy + 1.0), Color(1, 1, 1, 0.18), 1.0)
				yy += 3.5
			# нижняя планка с ручкой
			ci.draw_rect(Rect2(x0, top + hgt - 2.0, x1 - x0, 2.0), Color("#3e4448"))
			if a_end and hgt > 8.0:
				ci.draw_rect(Rect2(x0 + 3.0, top + hgt - 5.0, 4.0, 1.5), Color("#d8dbde"))
		# короб над проёмом
		ci.draw_rect(Rect2(o.x, o.y, T, 6.0), box)
		if not ghost:
			ci.draw_line(o + Vector2(0, 1.0), o + Vector2(T, 1.0), Color(1, 1, 1, 0.22), 1.0)
			ci.draw_line(o + Vector2(0, 6.0), o + Vector2(T, 6.0), Color(0, 0, 0, 0.35), 1.0)
		# столбы по краям
		if a_end:
			_post(ci, Rect2(o, Vector2(p, T)), false, ghost)
		if b_end:
			_post(ci, Rect2(o + Vector2(T - p, 0), Vector2(p, T)), false, ghost)
		if not ghost:
			if a_end:
				ci.draw_line(Vector2(x0 + 0.5, top), Vector2(x0 + 0.5, top + hgt), steel_d, 1.0)
			if b_end:
				ci.draw_line(Vector2(x1 - 0.5, top), Vector2(x1 - 0.5, top + hgt), steel_d, 1.0)
		return
	# вертикальная стена: вид сверху — короб по оси, полотно-плита вдоль стены
	var y0 := o.y + (p if a_end else 0.0)
	var y1 := o.y + T - (p if b_end else 0.0)
	ci.draw_rect(Rect2(o.x + T * 0.5 + 3.0, y0, 4.0, y1 - y0), box)
	var w := 8.0 * shown
	var vr := Rect2(o.x + T * 0.5 + 3.0 - w, y0, w, y1 - y0)
	if w > 0.5:
		ci.draw_rect(vr, steel)
		if not ghost:
			var yy2 := y0 + 2.0
			while yy2 < y1 - 1.0:
				ci.draw_line(Vector2(vr.position.x, yy2), Vector2(vr.end.x, yy2), Color("#6f777c"), 1.0)
				yy2 += 3.5
			ci.draw_line(vr.position + Vector2(0.5, 0), Vector2(vr.position.x + 0.5, vr.end.y), steel_d, 1.0)
			if a_end:
				ci.draw_line(vr.position, Vector2(vr.end.x, vr.position.y), steel_d, 1.0)
			if b_end:
				ci.draw_line(Vector2(vr.position.x, vr.end.y - 0.5), Vector2(vr.end.x, vr.end.y - 0.5), steel_d, 1.0)
	if a_end:
		_post(ci, Rect2(o, Vector2(T, p)), true, ghost)
	if b_end:
		_post(ci, Rect2(o + Vector2(0, T - p), Vector2(T, p)), true, ghost)


## Столб ворот с жёлто-чёрной разметкой.
static func _post(ci: CanvasItem, r: Rect2, horiz: bool, ghost: bool) -> void:
	if ghost:
		ci.draw_rect(r, GHOST_FILL)
		ci.draw_rect(r, GHOST_LINE, false, 1.0)
		return
	ci.draw_rect(r, CAP)
	var inner := r.grow(-0.5)
	_hazard(ci, Rect2(inner.position + (Vector2(0, 6.0) if not horiz else Vector2(4.0, 0)), inner.size - (Vector2(0, 6.0) if not horiz else Vector2(8.0, 0))), not horiz, false)
	ci.draw_rect(r, CAP_DARK, false, 1.0)


## Жёлто-чёрная разметка у ворот.
static func _hazard(ci: CanvasItem, r: Rect2, vert: bool, ghost: bool) -> void:
	if ghost:
		ci.draw_rect(r, GHOST_FILL)
		return
	ci.draw_rect(r, Color("#d9b13b"))
	var n := 6
	for i in n:
		if i % 2 == 0:
			continue
		if vert:
			var yy := r.position.y + r.size.y * i / n
			ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, yy), Vector2(r.end.x, yy - 3), Vector2(r.end.x, yy + r.size.y / n - 3), Vector2(r.position.x, yy + r.size.y / n)]), Color("#2a2c2e"))
		else:
			var xx := r.position.x + r.size.x * i / n
			ci.draw_colored_polygon(PackedVector2Array([Vector2(xx, r.end.y), Vector2(xx + 3, r.position.y), Vector2(xx + 3 + r.size.x / n, r.position.y), Vector2(xx + r.size.x / n, r.end.y)]), Color("#2a2c2e"))
