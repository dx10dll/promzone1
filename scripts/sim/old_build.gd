class_name OldBuild
extends RefCounted
## 1.26: на соседнем участке, который покупает завод, стоит старое здание —
## справа заброшенный склад, слева бывшая пилорама (навес без передней стены), сзади гаражный ряд.
## Стены, пол и ворота уже есть: дешёвый способ вырасти, но внутри пусто и грязно — свет, сети, уборка за вами.

const NAMES := ["старый склад", "бывшая пилорама", "гаражный ряд"]


## Где на участке встанет здание (ворота — в нижней стене, к своему участку или к дороге).
static func plan(sim: Sim, k: int) -> Rect2i:
	var r := sim.world.lot_rect(k)
	match k:
		0:
			var w0 := mini(14, r.size.x - 4)
			var h0 := mini(10, r.size.y - 5)
			return Rect2i(r.position.x + 2, r.end.y - h0 - 3, w0, h0)
		1:
			var w1 := mini(12, r.size.x - 4)
			var h1 := mini(8, r.size.y - 5)
			return Rect2i(r.end.x - w1 - 2, r.end.y - h1 - 3, w1, h1)
		_:
			var w2 := mini(18, r.size.x - 6)
			var h2 := mini(6, r.size.y - 3)
			return Rect2i(r.position.x + int((r.size.x - w2) / 2), r.end.y - h2 - 1, w2, h2)


## Поставить здание. Возвращает название (пусто — не поместилось).
static func place(sim: Sim, k: int) -> String:
	var b := plan(sim, k)
	if b.size.x < 6 or b.size.y < 5:
		return ""
	var w := sim.world
	for y in range(b.position.y - 1, b.end.y + 1):
		for x in range(b.position.x - 1, b.end.x + 1):
			var c := Vector2i(x, y)
			if not w.inb(c) or w.block[w.idx(c)] >= 0:
				return ""
	for y2 in range(b.position.y - 1, b.end.y + 2):
		for x2 in range(b.position.x - 1, b.end.x + 1):
			var c2 := Vector2i(x2, y2)
			if w.inb(c2):
				w.flora[w.idx(c2)] = 0
	match k:
		0:
			_box(w, b, 1)
			var gx := b.position.x + int(b.size.x / 2) - 1
			for x3 in range(gx, gx + 3):
				w.wall[w.idx(Vector2i(x3, b.end.y - 1))] = World.W_GATE
			w.wall[w.idx(Vector2i(b.position.x, b.end.y - 3))] = World.W_DOOR
			for x4 in range(b.position.x + 2, b.end.x - 2, 3):
				w.wall[w.idx(Vector2i(x4, b.position.y))] = World.W_WINDOW
		1:
			# навес: задняя и боковые стены, спереди — открыто
			_box(w, b, 1)
			for x5 in range(b.position.x + 1, b.end.x - 1):
				w.wall[w.idx(Vector2i(x5, b.end.y - 1))] = World.W_NONE
		_:
			# ряд гаражей по 6 клеток, у каждого ворота
			var n := int((b.size.x - 1) / 5)
			for i in n:
				var gr := Rect2i(b.position.x + i * 5, b.position.y, 6, b.size.y)
				_box(w, gr, 1)
				for x6 in range(gr.position.x + 2, gr.position.x + 4):
					w.wall[w.idx(Vector2i(x6, gr.end.y - 1))] = World.W_GATE
	w.refresh_all()
	_dirty(sim, b)
	_leftovers(sim, k, b)
	sim.rooms.update()
	return NAMES[clampi(k, 0, 2)]


static func _box(w: World, r: Rect2i, floor_id: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := w.idx(Vector2i(x, y))
			w.flr[i] = floor_id
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK


static func _dirty(sim: Sim, b: Rect2i) -> void:
	for y in range(b.position.y + 1, b.end.y - 1):
		for x in range(b.position.x + 1, b.end.x - 1):
			if (x * 7 + y * 13) % 3 == 0:
				sim.upkeep.add_dirt(Vector2i(x, y), 40.0)


## Что осталось от прежних хозяев: поддоны и стеллажи на складе, верстак в гараже.
static func _leftovers(sim: Sim, k: int, b: Rect2i) -> void:
	var list: Array = []
	match k:
		0:
			list = [["rack", b.position.x + 2, b.position.y + 2], ["rack", b.position.x + 2, b.position.y + 4], ["pallet", b.end.x - 4, b.position.y + 2],
				["pallet", b.end.x - 3, b.position.y + 2]]
		1:
			list = [["pallet", b.position.x + 2, b.position.y + 2], ["pallet", b.position.x + 3, b.position.y + 2], ["pallet", b.position.x + 2, b.position.y + 3]]
		_:
			list = [["tool_cabinet", b.position.x + 1, b.position.y + 1]]
	for e: Array in list:
		var c := Vector2i(int(e[1]), int(e[2]))
		if sim.can_place(str(e[0]), c) == "":
			sim.place_thing(str(e[0]), c, true, false)
