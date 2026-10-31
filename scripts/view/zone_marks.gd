class_name ZoneMarks
extends Node2D
## Предупреждения на зонах (1.12): если зоне чего-то не хватает — маленький жёлтый треугольник
## в углу зоны; что именно не так — только при наведении мыши на значок (1.13).
## Один размер на экране при любом масштабе, ночью не темнеет.

const T := World.T

var sim: Sim
var game: Node
var hover_room := -1
var mouse_override := Vector2(INF, INF)   ## для снимков: «мышь» стоит здесь


func _ready() -> void:
	z_index = 4


var _rt := 0.0


func _process(d: float) -> void:
	_rt -= d   # 1.40: метки и подсветка комнаты под мышью — 30 раз в секунду
	if _rt <= 0.0:
		_rt = 0.033
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var z := maxf(0.25, get_viewport().get_canvas_transform().get_scale().x)
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var mp := get_global_mouse_position()
	var hr := sim.rooms.room_at(Vector2i(floori(mp.x / T), floori(mp.y / T)))
	hover_room = hr.id if hr else -1
	# метки копим, рисуем значками, а текст — только у той, на которую навели мышь
	_q.clear()
	for r in sim.rooms.list:
		if r.type == "" or r.valid:
			continue
		_q.append([_room_mark_pos(r, z), r.missing, "Нужно:"])
	for oz: Dictionary in sim.rooms.open_zones:
		var rr: Rect2i = oz["rect"]
		_q.append([Vector2(rr.position) * T + Vector2(6, 6) / z, ["стены и дверь — зона только в помещении"], "Нужно:"])
	_power_marks(z, f, mp)
	_pile_badges(z, f)
	_pallet_tags(z, f)
	_far_marks(z, f, mp)
	# объекты вне своей зоны (1.13): ими не пользуются
	var bare := {}    # неразмеченная часть зала -> [объекты]
	for t: Thing in sim.things.values():
		if not t.built or sim.rooms.zone_ok(t):
			continue
		var r2 := sim.rooms.room_of_thing(t)
		if r2 and r2.type == "":
			if not bare.has(r2.id):
				bare[r2.id] = []
			(bare[r2.id] as Array).append(t)
			continue
		_q.append([Vector2(t.cell) * T + Vector2(2, 2) / z, [L.t("зона %s") % Rooms.zone_names(t.def_id)], "Не работает, нужна:"])
	# неразмеченное помещение с оборудованием — одна метка на всё
	for rid in bare.keys():
		var rr2: Rooms.Room = sim.rooms.list[int(rid)]
		var seen := {}
		var lines: Array = []
		for t2: Thing in bare[rid]:
			var key := Rooms.zone_names(t2.def_id)
			if seen.has(key):
				continue
			seen[key] = true
			lines.append("%s → %s" % [t2.title(), key])
		_q.append([_room_mark_pos(rr2, z), lines.slice(0, 4), "Не размечено — не работают:"])
	var hov := -1
	for k in _q.size():
		var pos: Vector2 = _q[k][0]
		if Rect2(pos, Vector2(22, 18) / z).grow(2.0 / z).has_point(mp):
			hov = k
	for k2 in _q.size():
		if k2 != hov:
			_mark(_q[k2][0], _q[k2][1], false, z, f, str(_q[k2][2]))
	if hov >= 0:
		_mark(_q[hov][0], _q[hov][1], true, z, f, str(_q[hov][2]))


var _q: Array = []
var _pile_rev := -1
var _piles: Dictionary = {}   ## индекс клетки -> сколько грузов лежит


## 1.18: на штабеле и пачке — число единиц (крупная поставка — несколько штабелей с цифрами).
func _pile_badges(z: float, f: Font) -> void:
	if z < 0.55:
		return
	if sim.item_rev != _pile_rev:
		_pile_rev = sim.item_rev
		_piles.clear()
		for gid in sim.ground_items:
			var it: Item = sim.items.get(gid)
			if it and it.kind != "crate":
				var k := sim.world.idx(it.cell)
				_piles[k] = int(_piles.get(k, 0)) + 1
	var fs := 10
	for k2 in _piles.keys():
		var n := int(_piles[k2])
		if n < 2:
			continue
		var c := sim.world.cell_of(int(k2))
		var txt := str(n)
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var sz := Vector2(tw + 8.0, 13.0)
		var pos := Vector2(c.x + 1, c.y) * T + Vector2(-sz.x - 1.0, 2.0) / z
		draw_set_transform(pos, 0.0, Vector2.ONE / z)
		draw_style_box(_badge_box(), Rect2(Vector2.ZERO, sz))
		draw_string(f, Vector2(4.0, 10.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _tag_rev := -1
var _tags: Array = []     ## [id заказа, клетки его поддонов]
var _tbox: StyleBoxFlat = null


## 1.56: бирка заказа на поддоне в зоне отгрузки: «Заказ №N, заказчик, K шт.» (1.58: только при наведении на поддон).
func _pallet_tags(z: float, f: Font) -> void:
	if z < 0.3:
		return
	if sim.item_rev != _tag_rev:
		_tag_rev = sim.item_rev
		_tags.clear()
		var by_order := {}
		for gid in sim.ground_items:
			var it: Item = sim.items.get(gid)
			if it and it.kind == "part" and it.ord_id >= 0 and sim.logi.in_ship(it.cell):
				if not by_order.has(it.ord_id):
					by_order[it.ord_id] = {}
				(by_order[it.ord_id] as Dictionary)[it.cell] = true
		var ids: Array = by_order.keys()
		ids.sort()
		for oid in ids:
			_tags.append([int(oid), (by_order[oid] as Dictionary).keys()])
	if _tags.is_empty():
		return
	# 1.58: бирка — только при наведении мыши на поддон в зоне отгрузки; поддоны этого заказа (2–4 штуки) подсвечиваются
	var mpos := get_global_mouse_position() if mouse_override.x == INF else mouse_override
	var mc := Vector2i(floori(mpos.x / T), floori(mpos.y / T))
	var hit: Array = []
	for tg in _tags:
		if (tg[1] as Array).has(mc):
			hit = tg
			break
	if hit.is_empty():
		return
	var o := sim.orders.get_order(int(hit[0]))
	if o.is_empty():
		return
	if _tbox == null:
		_tbox = StyleBoxFlat.new()
		_tbox.bg_color = Color(0.96, 0.9, 0.62, 0.96)
		_tbox.border_color = Color(0.45, 0.33, 0.12, 0.95)
		_tbox.set_border_width_all(1)
		_tbox.set_corner_radius_all(3)
		_tbox.anti_aliasing = true
	var hl := Color(0.98, 0.84, 0.3)
	var top := 9999
	var top_x := mc.x
	for c: Vector2i in hit[1]:
		var r := Rect2(Vector2(c) * T, Vector2(T, T))
		draw_rect(r, Color(hl, 0.22))
		draw_rect(r.grow(-1.0), Color(hl, 0.9), false, 2.0 / z)
		if c.y < top:
			top = c.y
			top_x = c.x
	var fs := 10
	var txt := sim.orders.tag(o)
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var sz := Vector2(tw + 8.0, 14.0)
	var pos := Vector2(top_x, top) * T + Vector2(0.0, -18.0) / z
	draw_set_transform(pos, 0.0, Vector2.ONE / z)
	draw_style_box(_tbox, Rect2(Vector2.ZERO, sz))
	draw_string(f, Vector2(4.0, 10.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.2, 0.13, 0.04))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 1.57: зона далеко от дороги — грузчики ходят пешком, погрузка и разгрузка идут дольше. Маленькая подпись под зоной
## «Далеко от дороги: погрузка ×N» (только от ×1.5); при наведении на зону — пояснение, сколько идти.
func _far_marks(z: float, f: Font, mp: Vector2) -> void:
	var mc := Vector2i(floori(mp.x / T), floori(mp.y / T))
	for area: int in [Logistics.A_UNLOAD, Logistics.A_SHIP]:
		var txt := sim.logi.far_text(area)
		if txt == "":
			continue
		var cells: Array[Vector2i] = sim.logi.zone_cells() if area == Logistics.A_UNLOAD else sim.logi.ship_cells()
		var lo := Vector2i(9999, 9999)
		var hi := Vector2i(-9999, -9999)
		var hovered := false
		for c in cells:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
			if c == mc:
				hovered = true
		if z < 0.45 and not hovered:
			continue
		var lines: Array[String] = [txt]
		if hovered:
			lines.append(sim.logi.far_hint(area))
		var fs := 10
		var tw := 0.0
		for ln in lines:
			tw = maxf(tw, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var sz := Vector2(tw + 22.0, 4.0 + 13.0 * float(lines.size()))
		var pos := Vector2(lo.x, hi.y + 1) * T + Vector2(0.0, 2.0) / z
		draw_set_transform(pos, 0.0, Vector2.ONE / z)
		draw_style_box(_badge_box(), Rect2(Vector2.ZERO, sz))
		draw_colored_polygon(PackedVector2Array([Vector2(8, 3), Vector2(14, 12), Vector2(2, 12)]), UITheme.WARN)
		for k in lines.size():
			draw_string(f, Vector2(18.0, 11.0 + 13.0 * float(k)), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UITheme.WARN, 0.95) if k == 0 else Color(0.93, 0.9, 0.82, 0.95))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _bbox: StyleBoxFlat = null


func _badge_box() -> StyleBoxFlat:
	if _bbox == null:
		_bbox = StyleBoxFlat.new()
		_bbox.bg_color = Color(0.1, 0.12, 0.14, 0.82)
		_bbox.border_color = Color(1, 1, 1, 0.25)
		_bbox.set_border_width_all(1)
		_bbox.set_corner_radius_all(5)
		_bbox.anti_aliasing = true
	return _bbox


## 1.18: метка помещения — по центру (над подписью зоны), а не в углу.
func _room_mark_pos(r: Rooms.Room, z: float) -> Vector2:
	var c := Vector2(r.rect.position) + Vector2(r.rect.size) * 0.5
	return c * T - Vector2(11, 34) / z


## Метка: жёлтый треугольник; полная — «Нужно:» и чего не хватает столбиком.
func _mark(pos: Vector2, items: Array, full: bool, z: float, f: Font, header: String = "Нужно:") -> void:
	var px := 11
	var s := 1.0 / z
	draw_set_transform(pos, 0.0, Vector2(s, s))
	var lines: Array[String] = []
	for it in items:
		var t := L.tx(str(it))   # 1.40: недостающее приходит из rooms.gd по-русски — статичное переводим здесь
		lines.append(t if t.length() <= 40 else t.substr(0, 38) + "…")
	header = L.t(header)
	var lh := 15.0
	var tw := 0.0
	if full:
		tw = f.get_string_size(header, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		for ln in lines:
			tw = maxf(tw, f.get_string_size("• " + ln, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	var wbox := 22.0 + (tw + 10.0 if full else 0.0)
	var hbox := 18.0 + (lh * float(lines.size()) + 2.0 if full else 0.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.07, 0.82)
	bg.set_corner_radius_all(8)
	bg.border_color = Color(UITheme.WARN, 0.6)
	bg.set_border_width_all(1)
	draw_style_box(bg, Rect2(Vector2.ZERO, Vector2(wbox, hbox)))
	# треугольник «внимание»
	var tri := PackedVector2Array([Vector2(11, 3), Vector2(19, 15), Vector2(3, 15)])
	draw_colored_polygon(tri, UITheme.WARN)
	draw_rect(Rect2(10.2, 6.5, 1.6, 4.8), Color(0.1, 0.08, 0.05))
	draw_rect(Rect2(10.2, 12.2, 1.6, 1.6), Color(0.1, 0.08, 0.05))
	if full:
		draw_string(f, Vector2(24, 13), header, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(UITheme.WARN, 0.95))
		for k in lines.size():
			draw_string(f, Vector2(24, 13 + lh * float(k + 1)), "• " + lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.93, 0.9, 0.82, 0.95))
	elif lines.size() > 1:
		draw_string(f, Vector2(21, 16), str(lines.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.WARN)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Нагрузка подстанций и щитов (1.13): полоска над источником — зелёная, жёлтая, красная;
## при перегрузе мигает «ПЕРЕГРУЗ» и сколько тянут аккумуляторы. У шкафов — заряд.
func _power_marks(z: float, f: Font, mp: Vector2) -> void:
	var pw := sim.power
	var mc := Vector2i(floori(mp.x / T), floori(mp.y / T))
	var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 160.0)
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		if t.kind() == "battery":
			continue
		if str(t.def().get("power_source", "")) == "":
			continue
		var net := pw.net_of_thing(t)
		if net == null or net.capacity <= 0.0:
			continue
		var ratio := net.load / maxf(net.capacity, 0.01)
		var over := net.over()
		var hovered := t.rect().has_point(mc)
		if not hovered and net.sources.size() > 1 and t.id != net.sources.min():
			continue   # 1.15: у сети из нескольких трансформаторов — одна полоска нагрузки
		var ov_power := game != null and game.get("overlay") != null and str((game.get("overlay") as Node).get("mode")) in ["power", "nets"]
		var s := 1.0 / z
		var top := Vector2(t.rect().get_center().x * T, t.cell.y * T) + Vector2(0, -6) / z
		draw_set_transform(top, 0.0, Vector2(s, s))
		var w := 54.0
		var col2 := Color("#6fbf86") if ratio < 0.75 else (Color("#e0b040") if ratio <= 1.0 else Color("#d8644e"))
		draw_rect(Rect2(-w * 0.5 - 1, -8, w + 2, 8), Color(0.07, 0.08, 0.09, 0.9))
		draw_rect(Rect2(-w * 0.5, -7, w * clampf(ratio, 0.0, 1.0), 6), col2)
		if ratio > 1.0:
			draw_rect(Rect2(-w * 0.5, -7, w, 6), Color(0.85, 0.3, 0.25, 0.35 * blink))
		var txt := ""
		if net.tripped:
			txt = L.t("ВЫБИТ АВТОМАТ")
		elif over:
			txt = L.t("ПЕРЕГРУЗ %.0f/%d кВт") % [net.load, int(net.capacity)]
		elif (hovered or z >= 1.25) and not ov_power:
			txt = L.t("%.1f / %d кВт" if net.load < 10.0 else "%.0f / %d кВт") % [net.load, int(net.capacity)]
		if txt != "":
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var red := over or net.tripped
			draw_rect(Rect2(-tw * 0.5 - 5, -24, tw + 10, 15), Color(0.08, 0.08, 0.07, 0.85))
			draw_string(f, Vector2(-tw * 0.5, -12.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.45, 0.35, 0.6 + 0.4 * blink) if red else Color(0.93, 0.9, 0.82))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
