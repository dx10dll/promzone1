class_name EntityLayer
extends Node2D
## Слой сущностей с сортировкой по Y: стены, объекты, люди, фургоны, грузы на полу.
## Синхронизируется с симуляцией по счётчикам изменений.

const T := World.T
const VAN_COLORS := [Color("#dfe3e6"), Color("#c9d6e0"), Color("#e0d6b8"), Color("#b8c9b0")]
const TRUCK_COLORS := [Color("#e08a3a"), Color("#3d6fb0"), Color("#4f7a4a"), Color("#c94a3a")]
const SEMI_COLORS := [Color("#eef0f0"), Color("#c9d6e0"), Color("#3d6fb0"), Color("#b8392e")]

var sim: Sim
var walls: Dictionary = {}       ## индекс клетки -> WallPiece
var doors: Array[WallPiece] = []
var things: Dictionary = {}      ## id -> ThingView
var workers: Dictionary = {}     ## id -> WorkerView
var vans: Dictionary = {}        ## id -> Node2D
var ground: Dictionary = {}      ## id -> Sprite2D
var dogs: Array[Sprite2D] = []   ## бродячие (или заводские) собаки
const DOG_COLS := [Color("#8a6a4a"), Color("#3a3530"), Color("#c98a4a"), Color("#a29a8e")]
var _dog_t := 0.0
var cat_node: Node2D = null      ## заводской кот: шерсть (тонируется) и детали
var _cat_fur: Sprite2D
var _cat_fx: Sprite2D
var _wall_hash := 0
var flora_nodes: Array[Sprite2D] = []
var _flora_sig := ""
var _thing_rev := -1
var _item_rev := -1


func _ready() -> void:
	y_sort_enabled = true


func _process(_d: float) -> void:
	if sim == null:
		return
	var inv := get_canvas_transform().affine_inverse()
	var vr := get_viewport().get_visible_rect()
	WorkerView.view = Rect2(inv * vr.position, inv.basis_xform(vr.size)).grow(160.0)
	var wh := hash(sim.world.wall)
	if wh != _wall_hash:
		_wall_hash = wh
		_rebuild_walls()
	if sim.thing_rev != _thing_rev:
		_thing_rev = sim.thing_rev
		_sync_things()
	if sim.item_rev != _item_rev:
		_item_rev = sim.item_rev
		_sync_ground()
	_sync_flora()
	_sway(_d)
	_sync_workers()
	_sync_vans()
	_update_doors()
	_sync_dogs(_d)
	_sync_cat()


func _rebuild_walls() -> void:
	for p in walls.values():
		p.queue_free()
	walls.clear()
	doors.clear()
	var w := sim.world
	for y in w.h:
		for x in w.w:
			var c := Vector2i(x, y)
			var v := w.get_wall(c)
			if v == World.W_NONE or v == World.W_FENCE_GATE:
				continue
			var piece := WallPiece.new()
			add_child(piece)
			piece.setup(sim, c)
			walls[w.idx(c)] = piece
			if WallKinds.is_door(v) or WallKinds.is_gate(v):
				doors.append(piece)


var hold_doors := false   ## для снимков: не трогать двери


func _update_doors() -> void:
	if hold_doors:
		return
	var people := sim.workers + sim.visitors
	var want := {}
	var by_cell := {}
	for d in doors:
		by_cell[d.cell] = d
		var center := Vector2(d.cell) + Vector2(0.5, 0.5)
		var r2 := 1.3 if WallKinds.is_door(d.kind) else 2.6
		for wk in people:
			if wk.present and wk.pos.distance_squared_to(center) < r2:
				want[d.cell] = true
				break
	# двустворчатая дверь и ворота из нескольких секций открываются целиком
	for c: Vector2i in want.keys().duplicate():
		var d0: WallPiece = by_cell[c]
		var step := Vector2i(0, 1) if bool(d0.nb.get("vert", false)) else Vector2i(1, 0)
		for sg: int in [-1, 1]:
			var n := c + step * sg
			while by_cell.has(n) and (by_cell[n] as WallPiece).kind == d0.kind:
				want[n] = true
				n += step * sg
	for d in doors:
		d.set_door_open(want.has(d.cell))


func _sync_things() -> void:
	for id in things.keys():
		if not sim.things.has(id):
			things[id].queue_free()
			things.erase(id)
	for t: Thing in sim.things.values():
		if not things.has(t.id):
			var v := ThingView.new()
			add_child(v)
			v.setup(sim, t)
			things[t.id] = v
		else:
			(things[t.id] as ThingView)._refresh_texture(true)


## Деревья и кусты (1.13): спрайты в общем слое с сортировкой по Y — люди заходят за крону.
## Сезон: летом зелёные, осенью желтеют (в сентябре — не все сразу), зимой голые ветки в снегу.
var _sway_t := 0.0


## 1.23: деревья и кусты качаются на ветру (сильнее зимой и в дождь), каждое — со своей фазой.
func _sway(d: float) -> void:
	_sway_t += d
	var wind := 0.035 if (sim.season.is_raining() or sim.season.season_id() == "winter") else 0.018
	for sp in flora_nodes:
		var ph := sp.position.x * 0.013 + sp.position.y * 0.007
		sp.skew = (sin(_sway_t * 1.3 + ph) + 0.4 * sin(_sway_t * 3.1 + ph * 2.0)) * wind


func _sync_flora() -> void:
	var w := sim.world
	var sea := sim.season.season_id()
	var mon := sim.season.month()
	var sig := "%d|%s|%d" % [w.flora_rev, sea, mon]
	if sig == _flora_sig:
		return
	_flora_sig = sig
	for n in flora_nodes:
		n.queue_free()
	flora_nodes.clear()
	if w.flora.size() != w.w * w.h:
		return
	var tree_names := ["poplar", "birch", "maple"]
	var bush_names := ["lilac", "rose"]
	for i in w.w * w.h:
		var v := int(w.flora[i])
		if v == 0:
			continue
		var c := w.cell_of(i)
		var hv := WorldView.vhash(c.x, c.y)
		var tree := v <= 3
		var key := str(tree_names[v - 1]) if tree else str(bush_names[clampi(v - 4, 0, 1)])
		var look := "summer"
		match sea:
			"winter":
				look = "winter"
			"autumn":
				look = "autumn" if mon >= 9 or hv % 3 != 0 else "summer"
		var sp := Sprite2D.new()
		sp.texture = Tex.obj(("tree_%s_%s" if tree else "bush_%s_%s") % [key, look])
		sp.centered = false
		var k := (0.7 if tree else 0.62) * (0.92 + float(hv % 5) * 0.04)
		sp.scale = Vector2(k, k)
		sp.offset = Vector2(-48, -120) if tree else Vector2(-32, -58)
		sp.flip_h = hv % 2 == 0
		if sp.flip_h:
			sp.offset.x = -sp.offset.x - (96.0 if tree else 64.0)
		sp.position = Vector2(c.x * T + T * 0.5, c.y * T + T * 0.94)
		if sea == "spring" and look == "summer":
			sp.modulate = Color(1.06, 1.1, 0.96)
		add_child(sp)
		flora_nodes.append(sp)


func _sync_workers() -> void:
	var seen := {}
	for w in sim.workers + sim.visitors:
		seen[w.id] = true
		if not workers.has(w.id):
			var v := WorkerView.new()
			add_child(v)
			v.setup(sim, w)
			workers[w.id] = v
	for id in workers.keys():
		if not seen.has(id):
			workers[id].queue_free()
			workers.erase(id)


func _sync_vans() -> void:
	var seen := {}
	for v in sim.vehicles:
		seen[v.id] = true
		var n: Node2D = vans.get(v.id)
		if n == null:
			n = Node2D.new()
			var kind := v.body if v.body in ["flatbed", "truck", "semi"] else "van"
			var body := Sprite2D.new()
			body.texture = Tex.get_tex("res://assets/vehicles/%s_body.svg" % kind)
			body.centered = false
			body.offset = Vector2(0, -104)
			body.scale = Vector2(0.5, 0.5)
			body.modulate = VAN_COLORS[v.color % VAN_COLORS.size()]
			if kind == "truck" or kind == "flatbed":
				body.modulate = TRUCK_COLORS[(v.color + v.id) % TRUCK_COLORS.size()]
			elif kind == "semi":
				body.modulate = SEMI_COLORS[(v.color + v.id) % SEMI_COLORS.size()]
			n.add_child(body)
			var det := Sprite2D.new()
			det.texture = Tex.get_tex("res://assets/vehicles/%s_details.svg" % kind)
			det.centered = false
			det.offset = Vector2(0, -104)
			det.scale = Vector2(0.5, 0.5)
			n.add_child(det)
			if kind == "flatbed" or kind == "truck":
				var cg := Sprite2D.new()
				cg.name = "cargo"
				cg.texture = Tex.get_tex("res://assets/vehicles/%s_cargo.svg" % kind)
				cg.centered = false
				cg.offset = Vector2(0, -104)
				cg.scale = Vector2(0.5, 0.5)
				n.add_child(cg)
			add_child(n)
			vans[v.id] = n
		var vx := v.x if v.px < -1e8 or absf(v.px - v.x) > 3.0 else lerpf(v.px, v.x, Worker.view_alpha)   # 1.29: плавно между шагами
		n.position = Vector2(vx * T - 4.0, (sim.world.road_row + 0.7) * T)
		var cgn := n.get_node_or_null("cargo")
		if cgn:
			# поддоны в кузове видны, пока их не разгрузили (до прибытия — тоже)
			var full := (sim.veh_items.get(v.id, []) as Array).size() > 0 or v.state == "arriving"
			if v.kind == "visit":
				full = v.state == "leaving"    # ломовоз увозит лом
			elif v.kind == "pickup":
				full = v.loaded > 0            # машина клиента полнеет по мере погрузки
			(cgn as Sprite2D).visible = full
	for id in vans.keys():
		if not seen.has(id):
			vans[id].queue_free()
			vans.erase(id)


func _sync_ground() -> void:
	for sp in ground.values():
		sp.queue_free()
	ground.clear()
	var per_cell := {}
	var piles := {}     # стройматериалы: клетка -> [def, сколько]
	for gid in sim.ground_items:
		var it: Item = sim.items.get(gid)
		if it == null:
			continue
		var k := sim.world.idx(it.cell)
		if it.kind == "bmat":
			if not piles.has(k):
				piles[k] = [it.def_id, 0, gid]
			piles[k][1] = int(piles[k][1]) + 1
			continue
		var n := int(per_cell.get(k, 0))
		per_cell[k] = n + 1
		if it.kind == "crate":
			ground[gid] = _crate_sprite(it, Vector2(it.cell.x * T + T * 0.5, it.cell.y * T + T * 0.92))
			continue
		if n >= 12:
			continue   # большая пачка в зоне разгрузки: рисуем верхние
		var sp := Sprite2D.new()
		sp.texture = Tex.for_item(it)
		sp.scale = Vector2(0.5, 0.5)
		sp.position = Vector2(it.cell.x * T + T * 0.5 + (n % 3) * 5.0 - 5.0, it.cell.y * T + T * 0.66 - int(n / 3) * 3.0)
		add_child(sp)
		ground[gid] = sp
	# штабель стройматериала на поддоне: одна картинка на клетку, высота — по заполнению
	for k2 in piles.keys():
		var pd: Array = piles[k2]
		var key := str(pd[0])
		var full := float(pd[1]) / float(BuildMats.pallet(key))
		var lv := 1 if full <= 0.34 else (2 if full <= 0.67 else 3)
		var c := sim.world.cell_of(int(k2))
		var ps := Sprite2D.new()
		ps.texture = Tex.item("%s_p%d" % [key, lv])
		ps.centered = false
		ps.scale = Vector2(0.5, 0.5)
		ps.offset = Vector2(-32, -62)
		ps.position = Vector2(c.x * T + T * 0.5, c.y * T + T * 0.97)
		add_child(ps)
		ground[int(pd[2])] = ps


## Ящик с оборудованием (или сама мелочь — стул, цветок) на земле. Узел стоит у нижнего края клетки.
func _crate_sprite(it: Item, bottom: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = bottom
	add_child(n)
	if it.q == "loose":
		var sk := Thing.sprite_for(it.def_id, 0)
		var key := "chair_down" if it.def_id == "chair" else str(sk[0])
		var m: Dictionary = Defs.sprites.get(key, {})
		var sp := Sprite2D.new()
		sp.texture = Tex.obj(key)
		sp.centered = false
		var k := 0.4
		sp.scale = Vector2(k, k)
		sp.offset = Vector2(-float(m.get("w", 64)) * 0.5, -float(m.get("oy", 64)) - 4.0)
		n.add_child(sp)
		return n
	var cr := Sprite2D.new()
	cr.texture = Tex.item("equip_crate")
	cr.scale = Vector2(0.44, 0.44)
	cr.offset = Vector2(0, -32)
	n.add_child(cr)
	# на боку ящика — трафарет: силуэт того, что внутри, тёмной краской (а не уменьшенная картинка)
	var ic := Sprite2D.new()
	var sk2 := Thing.sprite_for(it.def_id, 0)
	ic.texture = Tex.obj(str(sk2[0]))
	if ic.texture:
		var sz := ic.texture.get_size()
		var fit := 15.0 / maxf(sz.x, sz.y)
		ic.scale = Vector2(fit, fit)
		ic.position = Vector2(4.5, -15.5)
		ic.modulate = Color(0.16, 0.10, 0.05, 0.62)
		n.add_child(ic)
	return n


func _sync_dogs(delta: float) -> void:
	var list: Array = sim.progress.dogs
	while dogs.size() > list.size():
		dogs.pop_back().queue_free()
	while dogs.size() < list.size():
		var sp := Sprite2D.new()
		sp.centered = false
		sp.offset = Vector2(-32, -44)
		sp.scale = Vector2(0.5, 0.5)
		var spots := Sprite2D.new()
		spots.centered = false
		spots.offset = Vector2(-32, -44)
		spots.texture = Tex.fx("dog_spots")
		spots.name = "spots"
		sp.add_child(spots)
		add_child(sp)
		dogs.append(sp)
	_dog_t += delta
	for i in dogs.size():
		var d: Dictionary = list[i]
		var sp2 := dogs[i]
		sp2.position = Vector2(float(d["x"]) * T, float(d["y"]) * T + 6.0)
		var moving := bool(d.get("moving", false))
		var fr := int(_dog_t * 7.0 + i) % 2 if moving else 0
		sp2.texture = Tex.fx("dog_%d" % fr)
		sp2.flip_h = not bool(d.get("right", true))
		var f := int(d.get("f", 0))
		sp2.modulate = DOG_COLS[f % DOG_COLS.size()]
		var spots2: Sprite2D = sp2.get_node("spots")
		spots2.visible = f % 2 == 1
		spots2.flip_h = sp2.flip_h
		if not moving:
			sp2.position.y += sin(_dog_t * 2.0 + i) * 0.4


func _sync_cat() -> void:
	var c: Cat = sim.town.cat if sim.town else null
	if c == null:
		if cat_node:
			cat_node.queue_free()
			cat_node = null
		return
	if cat_node == null:
		cat_node = Node2D.new()
		_cat_fur = Sprite2D.new()
		_cat_fx = Sprite2D.new()
		for sp in [_cat_fur, _cat_fx]:
			sp.centered = false
			sp.offset = Vector2(-32, -45)   # 1.22: новый кот — холст 64×48
			sp.scale = Vector2(0.5, 0.5)
			cat_node.add_child(sp)
		add_child(cat_node)
	var cp := c.vpos()
	cat_node.position = Vector2(cp.x * T, cp.y * T + 7.0)
	var pose := "sit"
	match c.state:
		"walk":
			pose = "walk" if int(_dog_t * 6.0) % 2 == 0 else "walk2"
		"sleep":
			pose = "sleep"
		"eat":
			pose = "walk"
		"pounce":
			pose = "pounce"
	_cat_fur.texture = Tex.fx("cat_%s_fur" % pose)
	_cat_fx.texture = Tex.fx("cat_%s_fx" % pose)
	_cat_fur.modulate = c.fur_color()
	var flip := c.dir < 0 and pose != "sit"
	_cat_fur.flip_h = flip
	_cat_fx.flip_h = flip
	if pose == "sleep":
		cat_node.position.y += sin(_dog_t * 1.6) * 0.3


func worker_view(id: int) -> WorkerView:
	return workers.get(id)


func thing_view(id: int) -> ThingView:
	return things.get(id)
