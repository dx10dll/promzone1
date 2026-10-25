class_name DrawChunks
extends RefCounted
## 1.40: запись draw_*-команд большого неподвижного рисунка (город за краем карты) с раскладкой по плиткам.
## Godot отсекает невидимое только целыми узлами; один гигантский узел весь кадр отправляет тысячи вызовов.
## Здесь команды идут в порядке рисования; каждая попадает в плитку (узел) по своему положению. Если команда
## перекрывает чужую плитку из текущего слоя, начинается новый слой — порядок наложения остаётся прежним.
## Использование: те же draw_rect/draw_line/… у объекта записи, затем build(parent) создаёт узлы-плитки.

const CELL := 640.0     ## размер плитки
const MARK := 128.0     ## сетка проверки перекрытий
const BIG := Vector2i(1 << 20, 0)

var layers: Array = []          ## слой → {плитка Vector2i → [команды]}
var count := 0
var _cur: Dictionary = {}
var _mark: Dictionary = {}
var _tf: Array = []             ## текущее преобразование [поз, угол, масштаб] или пусто


func clear() -> void:
	layers.clear()
	_cur = {}
	_mark = {}
	_tf = []
	count = 0


func draw_set_transform(pos: Vector2, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> void:
	if pos == Vector2.ZERO and rot == 0.0 and scl == Vector2.ONE:
		_tf = []
	else:
		_tf = [pos, rot, scl]


func draw_rect(r: Rect2, col: Color, filled: bool = true, width: float = -1.0, aa: bool = false) -> void:
	_add(&"draw_rect", [r, col, filled, width, aa], r.abs().grow(2.0 if filled else maxf(width, 1.0) + 1.0))


func draw_circle(p: Vector2, rad: float, col: Color, filled: bool = true, width: float = -1.0, aa: bool = false) -> void:
	_add(&"draw_circle", [p, rad, col, filled, width, aa], Rect2(p, Vector2.ZERO).grow(rad + maxf(width, 1.0) + 1.0))


func draw_line(a: Vector2, b: Vector2, col: Color, width: float = -1.0, aa: bool = false) -> void:
	_add(&"draw_line", [a, b, col, width, aa], Rect2(a, Vector2.ZERO).expand(b).grow(maxf(width, 1.0) + 1.0))


func draw_arc(c: Vector2, rad: float, a0: float, a1: float, pts: int, col: Color, width: float = -1.0, aa: bool = false) -> void:
	_add(&"draw_arc", [c, rad, a0, a1, pts, col, width, aa], Rect2(c, Vector2.ZERO).grow(rad + maxf(width, 1.0) + 1.0))


func draw_colored_polygon(pts: PackedVector2Array, col: Color) -> void:
	_add(&"draw_colored_polygon", [pts, col], _bounds(pts, 2.0))


func draw_polyline(pts: PackedVector2Array, col: Color, width: float = -1.0, aa: bool = false) -> void:
	_add(&"draw_polyline", [pts, col, width, aa], _bounds(pts, maxf(width, 1.0) + 1.0))


func draw_multiline(pts: PackedVector2Array, col: Color, width: float = -1.0, aa: bool = false) -> void:
	_add(&"draw_multiline", [pts, col, width, aa], _bounds(pts, maxf(width, 1.0) + 1.0))


func draw_mesh(mesh: Mesh, tex: Texture2D, xf: Transform2D = Transform2D.IDENTITY, mod: Color = Color.WHITE) -> void:
	var bb := mesh.get_aabb()
	_add(&"draw_mesh", [mesh, tex, xf, mod], xf * Rect2(bb.position.x, bb.position.y, bb.size.x, bb.size.y).grow(2.0))


func draw_string(font: Font, pos: Vector2, text: String, al: int, width: float, size: int, col: Color) -> void:
	_add(&"draw_string", [font, pos, text, al, width, size, col], Rect2(pos.x - 4.0, pos.y - size * 1.3, size * 0.95 * text.length() + 8.0, size * 1.8))


static func _bounds(pts: PackedVector2Array, grow: float) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo).grow(grow)


func _add(method: StringName, args: Array, bb: Rect2) -> void:
	count += 1
	if not _tf.is_empty():   # под поворотом/сдвигом границы не считаем точно — берём с запасом
		bb = Rect2((_tf[0] as Vector2) - Vector2(320, 320), Vector2(640, 640))
	var x0 := int(floorf(bb.position.x / MARK))
	var y0 := int(floorf(bb.position.y / MARK))
	var x1 := int(floorf(bb.end.x / MARK))
	var y1 := int(floorf(bb.end.y / MARK))
	var cx := bb.get_center().x
	var cy := bb.get_center().y
	var key := BIG
	if bb.size.x <= CELL * 1.5 and bb.size.y <= CELL * 1.5:
		key = Vector2i(int(floorf(cx / CELL)), int(floorf(cy / CELL)))
	var clash := false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var m: Variant = _mark.get(Vector2i(x, y))
			if m != null and m != key:
				clash = true
				break
		if clash:
			break
	if clash:
		_flush()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_mark[Vector2i(x, y)] = key
	if not _cur.has(key):
		_cur[key] = []
	(_cur[key] as Array).append([method, args, _tf])


func _flush() -> void:
	if not _cur.is_empty():
		layers.append(_cur)
	_cur = {}
	_mark = {}


## Создаёт по узлу на каждую (слой, плитку) в порядке слоёв и кладёт их в root.
func build(root: Node2D) -> int:
	_flush()
	var n := 0
	for layer: Dictionary in layers:
		for key: Vector2i in layer:
			var nd := Node2D.new()
			nd.draw.connect(_replay.bind(nd, layer[key] as Array))
			root.add_child(nd)
			n += 1
	return n


static func _replay(nd: Node2D, cmds: Array) -> void:
	var cur: Array = []
	for c: Array in cmds:
		var tf: Array = c[2]
		if tf != cur:
			cur = tf
			if tf.is_empty():
				nd.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				nd.draw_set_transform(tf[0], tf[1], tf[2])
		nd.callv(c[0], c[1])
