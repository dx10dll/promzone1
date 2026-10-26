class_name BuildTool
extends Node2D
## Инструменты: выделение, стройка полов/стен/дверей/окон/ворот, установка объектов, снос, отмена.
## Рисует предпросмотр поверх мира (z_index выше сущностей).

signal message(text: String, good: bool)
signal selection_changed()
signal mode_changed()
signal room_clicked(room_id: int)
signal control_click(c: Vector2i, screen: Vector2)   ## 1.19: щелчок, пока человек под управлением
signal cell_clicked(c: Vector2i)     ## стена, проём или пол без помещения — карточка клетки (1.12)

const T := World.T

var sim: Sim
var game: Node
var mode := "select"
var arg: Variant = null
var hover := Vector2i(-1, -1)
var drag_from := Vector2i(-1, -1)
var dragging := false
var sel_kind := ""     ## "worker" | "thing" | ""
var sel_id := -1
var _t := 0.0
var preview_cost := 0.0
var overlay: OverlayLayer
var place_rot := 0     ## поворот объекта при установке (R)
var plan_mode := false ## 1.17: режим планировки — всё ставится на план-кальку, бесплатно
var click_screen := Vector2(-1, -1)   ## где на экране щёлкнули при выделении — карточка появится рядом (1.12)
var click_ms := -100000               ## когда щёлкнули (карточка из окна-списка — справа, как раньше)


## Место недавнего щелчка по карте (−1 — щелчка не было, выбрали из окна).
func recent_click() -> Vector2:
	if Time.get_ticks_msec() - click_ms < 600:
		return click_screen
	return Vector2(-1, -1)


func _ready() -> void:
	z_index = 50


func set_mode(m: String, a: Variant = null) -> void:
	mode = m
	arg = a
	if m == "object" and a != null and Thing.rotations(str(a)) < 4 and place_rot % 2 == 1:
		place_rot = 0
	dragging = false
	if m != "logistics":
		_logi_set_src(null)
	mode_changed.emit()
	queue_redraw()


func clear_selection() -> void:
	sel_kind = ""
	sel_id = -1
	selection_changed.emit()


func select_worker(id: int) -> void:
	sel_kind = "worker"
	sel_id = id
	selection_changed.emit()


func select_thing(id: int) -> void:
	sel_kind = "thing"
	sel_id = id
	selection_changed.emit()


func _process(delta: float) -> void:
	_t += delta
	var c := _mouse_cell()
	if c != hover:
		hover = c
		queue_redraw()
		if overlay and (mode == "room" or mode == "logistics"):
			var rr := sim.rooms.room_at(c)
			overlay.hover_room = rr.id if rr else -1
			overlay.queue_redraw()
	elif mode != "select" or sel_kind == "thing" or sel_kind == "worker" or not sim.bp_cells.is_empty() or sim.brain.controlled_worker() != null:
		queue_redraw()


func _mouse_cell() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x / T), floori(p.y / T))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(_mouse_cell())
			else:
				_on_release(_mouse_cell())
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if dragging:
				dragging = false
			elif mode == "logistics" and logi_remove_at(get_global_mouse_position()):
				pass
			elif mode != "select":
				set_mode("select")
			elif sim.brain.controlled_worker() != null:
				# 1.19: под управлением ПКМ — сразу первое подходящее действие
				var cw := sim.brain.controlled_worker()
				var ctxt := sim.brain.give_order(cw, _mouse_cell())
				if ctxt != "":
					message.emit(ctxt, not cw.order.is_empty())
				queue_redraw()
			elif sel_kind == "worker" and sim.get_worker(sel_id) and not sim.get_worker(sel_id).visitor:
				# 1.15: приказ выбранному человеку — работать на объекте или идти в клетку
				var ow := sim.get_worker(sel_id)
				var txt := sim.brain.give_order(ow, _mouse_cell())
				if txt != "":
					message.emit(txt, not ow.order.is_empty())
				queue_redraw()
			else:
				clear_selection()
			get_viewport().set_input_as_handled()


func _on_press(c: Vector2i) -> void:
	match mode:
		"select":
			click_screen = get_viewport().get_mouse_position()
			click_ms = Time.get_ticks_msec()
			_select_at()
		"room":
			if (arg is String and str(arg) != "") or plan_mode:
				dragging = true
				drag_from = c
			else:
				click_screen = get_viewport().get_mouse_position()
				click_ms = Time.get_ticks_msec()
				var r := sim.rooms.room_at(c)
				room_clicked.emit(r.id if r else -1)
		"logistics":
			logi_press_at(get_global_mouse_position())
		"object":
			_place_object(c)
		"template":
			_place_template(c)
		_:
			dragging = true
			drag_from = c
	queue_redraw()


func _on_release(c: Vector2i) -> void:
	if mode == "logistics":
		logi_release_at(get_global_mouse_position())
		return
	if not dragging:
		return
	dragging = false
	var r := _drag_rect(drag_from, c)
	if plan_mode and _plan_release(r, c):
		queue_redraw()
		return
	match mode:
		"room":
			_apply_zone(r, c)
		"floor":
			_apply_floor(r)
		"roomframe":
			_apply_room(r)
		"wall":
			_apply_wall(r)
		"door", "window", "gate":
			_apply_openings(r)
		"demolish":
			_apply_demolish(r)
		"cancel":
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					sim.cancel_all_at(Vector2i(x, y))
			message.emit(L.t("Чертежи отменены, деньги возвращены."), true)
		"cable":
			var n := 0
			var broke := false
			for cc in cable_path(drag_from, c):
				if not sim.can_afford(Defs.b("cable_cost")):
					broke = true
					break
				if sim.place_cable(cc):
					n += 1
			if n > 0:
				message.emit(L.t("Чертёж кабеля: %d кл. (%s). Проложит электрик или строитель.") % [n, Defs.money_str(n * Defs.b("cable_cost"))], true)
			elif broke:
				message.emit(L.t("Не хватает денег на кабель."), false)
		"zone":
			var nz := sim.set_area(r, int(arg))
			if nz < 0:
				message.emit(sim.area_refusal, false)   # 1.29: последнюю клетку обязательной зоны не стереть
			elif int(arg) == Logistics.A_UNLOAD:
				message.emit(L.t("Зона разгрузки: %d кл. Сюда будут разгружать металл (на поддоны заготовок) и ящики с оборудованием.") % nz if nz > 0 else L.t("Здесь нельзя отметить зону."), nz > 0)
			elif int(arg) == Logistics.A_SHIP:
				message.emit(L.t("Зона отгрузки: %d кл. Сюда понесут готовые заказы — машина клиента грузит только отсюда.") % nz if nz > 0 else L.t("Здесь нельзя отметить зону."), nz > 0)
			else:
				message.emit(L.t("Зона убрана: %d кл.") % nz if nz > 0 else L.t("Здесь нет зоны."), nz > 0)
		"pipe":
			var np := 0
			var brokep := false
			for cc in cable_path(drag_from, c):
				if not sim.can_afford(Defs.b("pipe_cost")):
					brokep = true
					break
				if sim.place_pipe(cc):
					np += 1
			if np > 0:
				message.emit(L.t("Чертёж трубы: %d кл. (%s). Проложат строители.") % [np, Defs.money_str(np * Defs.b("pipe_cost"))], true)
			elif brokep:
				message.emit(L.t("Не хватает денег на трубы."), false)
		"duct", "air":
			var lay := mode
			var nl := 0
			var brokel := false
			for cc in cable_path(drag_from, c):
				if not sim.can_afford(Defs.b(lay + "_cost")):
					brokel = true
					break
				if sim.place_line(lay, cc):
					nl += 1
			var lname := L.t("воздуховода") if lay == "duct" else L.t("пневмомагистрали")
			if nl > 0:
				message.emit(L.t("Чертёж %s: %d кл. (%s). Проложат строители.") % [lname, nl, Defs.money_str(nl * Defs.b(lay + "_cost"))], true)
			elif brokel:
				message.emit(L.t("Не хватает денег."), false)
		"unduct", "unair":
			var lay2 := "duct" if mode == "unduct" else "air"
			var nr := 0
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					if sim.remove_line(lay2, Vector2i(x, y)):
						nr += 1
			message.emit(L.t("Снято: %d кл.") % nr if nr > 0 else L.t("Здесь ничего нет."), nr > 0)
		"unpipe":
			var nu := 0
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					if sim.remove_pipe(Vector2i(x, y)):
						nu += 1
			message.emit(L.t("Снято трубы: %d кл.") % nu if nu > 0 else L.t("Здесь нет трубы."), nu > 0)
		"uncable":
			var n2 := 0
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					if sim.remove_cable(Vector2i(x, y)):
						n2 += 1
			message.emit(L.t("Снято кабеля: %d кл.") % n2 if n2 > 0 else L.t("Здесь нет кабеля."), n2 > 0)
	queue_redraw()


## 1.17: в режиме планировки инструменты рисуют на плане. true — обработано.
func _plan_release(r: Rect2i, c: Vector2i) -> bool:
	var pl := sim.plan
	var n := 0
	match mode:
		"floor":
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					if pl.add_floor(Vector2i(x, y), int(arg)):
						n += 1
		"wall":
			for cc in _wall_cells(r):
				if pl.add_wall(cc, int(arg)):
					n += 1
		"door", "window", "gate":
			for cc2 in _opening_cells(r):
				if pl.add_wall(cc2, int(arg)):
					n += 1
		"roomframe":
			if r.size.x < 3 or r.size.y < 3:
				message.emit(L.t("Помещение — от 3×3 клеток вместе со стенами."), false)
				return true
			for y2 in range(r.position.y + 1, r.end.y - 1):
				for x2 in range(r.position.x + 1, r.end.x - 1):
					pl.add_floor(Vector2i(x2, y2), int(arg))
			for cc3 in _wall_cells(r):
				pl.add_wall(cc3, World.W_BRICK)
			pl.add_wall(sim.room_door_cell(r), World.W_DOOR)
			n = r.size.x * r.size.y
		"room":
			var type := "" if str(arg) == "_erase" else str(arg)
			n = pl.paint_zone(r, type)
		"demolish", "cancel":
			n = pl.erase(r)
			message.emit(L.t("Стёрто с плана: %d.") % n if n > 0 else L.t("Здесь на плане ничего нет."), n > 0)
			return true
		"cable", "pipe", "duct", "air", "uncable", "unpipe", "unduct", "unair", "zone":
			message.emit(L.t("Сети и уличные зоны на плане не рисуются — проложите их, когда начнёте строить."), false)
			return true
		_:
			return false
	if n > 0:
		Snd.play("place", -12.0)
	return true


## Путь кабеля «уголком»: сначала по горизонтали, потом по вертикали.
func cable_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var sx := 1 if b.x >= a.x else -1
	var x := a.x
	while true:
		out.append(Vector2i(x, a.y))
		if x == b.x:
			break
		x += sx
	var sy := 1 if b.y >= a.y else -1
	var y := a.y
	while y != b.y:
		y += sy
		out.append(Vector2i(b.x, y))
	return out


func _drag_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var p := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var e := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(p, e - p + Vector2i.ONE)


## Клетки стены по прямоугольнику: контур, или линия, если тянули в одну клетку шириной.
func _wall_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge:
				out.append(Vector2i(x, y))
	return out


func _opening_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var anchor := drag_from if r.has_point(drag_from) else r.position
	if r.size.x >= r.size.y:
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, anchor.y))
	else:
		for y in range(r.position.y, r.end.y):
			out.append(Vector2i(anchor.x, y))
	return out


func _apply_floor(r: Rect2i) -> void:
	var n := 0
	var fid := int(arg)
	var broke := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not sim.world.in_plot(c):
				continue
			if not sim.can_afford(sim.floor_cost(fid)):
				broke = true
				continue
			if sim.place_floor_bp(c, fid):
				n += 1
	_report(n, broke, L.t("пола"))


## Зона (1.12): протянули прямоугольник — разметить клетки; просто щёлкнули — залить помещение, как ведром.
## «_erase» — стереть разметку.
func _apply_zone(r: Rect2i, c: Vector2i) -> void:
	var type := "" if str(arg) == "_erase" else str(arg)
	var n := 0
	if r.size == Vector2i.ONE:
		n = sim.rooms.fill(c, type)
	else:
		n = sim.rooms.paint(r, type)
	if n <= 0:
		if sim.rooms.room_at(c) == null and type != "":
			message.emit(L.t("Зоны рисуют внутри помещения: на полу, обнесённом стенами с дверью. Разгрузку и отгрузку — в «Стройке», на улице."), false)
		return
	Snd.play("place", -8.0)
	if type == "":
		message.emit(L.t("Разметка снята: %d кл.") % n, true)
		return
	var rr := sim.rooms.room_at(c) if r.size == Vector2i.ONE else sim.rooms.room_at(r.get_center())
	var nm := L.t(str(Defs.rooms.get(type, {}).get("name", "")))
	if rr and rr.type == type and rr.valid:
		message.emit(L.t("Зона «%s»: %d кл. Всё нужное на месте.") % [nm, rr.area()], true)
	elif rr and rr.type == type:
		message.emit(L.t("Зона «%s»: %d кл. Не хватает: %s.") % [nm, rr.area(), ", ".join(rr.missing.map(func(x: String) -> String: return L.tx(x)))], false)
	else:
		message.emit(L.t("Зона «%s» размечена: %d кл.") % [nm, n], true)


## Помещение одной рамкой (сама логика — в Sim.place_room_bp).
func _apply_room(r: Rect2i) -> void:
	var err := sim.place_room_bp(r, int(arg))
	if err != "":
		message.emit(err, false)
		return
	message.emit(L.t("Чертёж помещения %d×%d: пол, стены и дверь. Назначение выберите после постройки (Помещения).") % [r.size.x, r.size.y], true)


func _apply_wall(r: Rect2i) -> void:
	var n := 0
	var broke := false
	for c in _wall_cells(r):
		if not sim.world.in_plot(c):
			continue
		if not sim.can_afford(sim.wall_cost(int(arg))):
			broke = true
			continue
		if sim.place_wall_bp(c, int(arg)):
			n += 1
	_report(n, broke, L.t("стены"))


func _apply_openings(r: Rect2i) -> void:
	var n := 0
	var broke := false
	for c in _opening_cells(r):
		if not sim.world.in_plot(c):
			continue
		if not sim.can_afford(sim.wall_cost(int(arg))):
			broke = true
			continue
		if sim.place_wall_bp(c, int(arg)):
			n += 1
	_report(n, broke, L.t("проёмов"))


func _apply_demolish(r: Rect2i) -> void:
	var n := 0
	var seen := {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var t := sim.thing_at(c)
			if t:
				if seen.has(t.id):
					continue
				seen[t.id] = true
			if sim.place_demolish(c):
				n += 1
	if n > 0:
		message.emit(L.t("Отмечено под снос: %d. Стены и полы разберут, объекты — упакуют в ящики и унесут на склад оборудования.") % n, true)
	else:
		message.emit(L.t("Здесь нечего сносить."), false)


func _report(n: int, broke: bool, what: String) -> void:
	if n > 0:
		message.emit(L.t("Чертёж %s: %d кл. Рабочие построят, когда освободятся.") % [what, n], true)
	if broke:
		message.emit(L.t("Не хватает денег на весь чертёж."), false)
	elif n == 0:
		message.emit(L.t("Здесь строить нельзя или уже построено."), false)


## Повернуть объект, который сейчас ставим (клавиша R).
func rotate_ghost() -> void:
	if mode != "object" or arg == null:
		return
	place_rot = Thing.next_rot(str(arg), place_rot)
	Snd.play("ui_click", -10.0)
	queue_redraw()


func _place_object(c: Vector2i) -> void:
	var def_id := str(arg)
	if plan_mode:
		var perr := sim.plan.add_obj(def_id, c, place_rot)
		if perr != "":
			message.emit(perr, false)
		else:
			Snd.play("place", -12.0)
		return
	var err := sim.can_place(def_id, c, place_rot)
	if err != "":
		message.emit(err, false)
		return
	var cost := sim.thing_cost(def_id)
	if not sim.can_afford(cost):
		message.emit(L.t("Не хватает денег: нужно %s") % Defs.money_str(cost), false)
		return
	sim.place_thing(def_id, c, false, true, place_rot)
	Snd.play("place", -6.0)
	message.emit(L.t("Заказано: %s. Рабочие смонтируют.") % L.t(str(Defs.objects[def_id]["name"])), true)


## 1.17: готовое помещение — центр под курсором.
func template_origin(c: Vector2i) -> Vector2i:
	return c - Templates.size(str(arg)) / 2


func _place_template(c: Vector2i) -> void:
	var id := str(arg)
	var o := template_origin(c)
	var err := Templates.place(sim, id, o, plan_mode)
	if err != "":
		message.emit(err, false)
		return
	Snd.play("place", -6.0)
	var nm := L.t(str(Templates.def(id).get("name", "")))
	if plan_mode:
		message.emit(L.t("«%s» — на плане.") % nm, true)
	else:
		message.emit(L.t("Заказано помещение «%s»: строители начнут с пола и стен, мебель и зону поставят, когда достроят.") % nm, true)


func _draw_template_ghost() -> void:
	var id := str(arg)
	var o := template_origin(hover)
	var err := "" if plan_mode else Templates.check(sim, id, o)
	var ok := err == ""
	var col := Color(0.62, 0.82, 1.0, 0.75) if plan_mode else (Color(0.6, 1.0, 0.65, 0.7) if ok else Color(1.0, 0.45, 0.4, 0.7))
	var s := Templates.size(id)
	draw_rect(Rect2(Vector2(o) * T, Vector2(s) * T), Color(col.r, col.g, col.b, 0.14))
	var wc := Templates.wall_cells(id, o)
	for c in wc.keys():
		var k := int(wc[c])
		var cat := str(Defs.wall_by_id.get(k, {}).get("kind", "wall"))
		var fc := Color(col.r, col.g, col.b, 0.55)
		if cat in ["door", "gate"]:
			fc = Color(0.95, 0.78, 0.35, 0.75)
		elif cat == "window":
			fc = Color(0.6, 0.85, 1.0, 0.75)
		if Templates.shared(sim, c) and cat == "wall":
			# 1.21: общая с соседом стена — пунктиром, её не строят и не оплачивают
			fc = Color(0.75, 0.9, 1.0, 0.28)
		draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)).grow(-2), fc)
	for ob: Array in Templates.objs(id):
		var def_id := str(ob[0])
		var cc := o + Vector2i(int(ob[1]), int(ob[2]))
		var sk := Thing.sprite_for(def_id, int(ob[3]))
		var key := "chair_down" if def_id == "chair" else str(sk[0])
		var meta: Dictionary = Defs.sprites.get(key, {})
		var tex := Tex.obj(key)
		var bs: Array = Defs.objects.get(def_id, {}).get("size", [1, 1])
		if tex:
			var bottom := Vector2(cc.x * T, (cc.y + int(bs[1])) * T)
			var pos := bottom - Vector2(float(meta.get("ox", 0)), float(meta.get("oy", 64))) * 0.5
			draw_texture_rect(tex, Rect2(pos, tex.get_size() * 0.5), false, col)
	draw_rect(Rect2(Vector2(o) * T, Vector2(s) * T), Color(col.r, col.g, col.b, 0.95), false, 2.0)
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var nm := L.t(str(Templates.def(id).get("name", "")))
	var nsh := 0
	for c2 in wc.keys():
		if Templates.shared(sim, c2):
			nsh += 1
	var lbl := (nm + (L.t("  · общая стена: %d кл.") % nsh if nsh > 0 else "")) if ok else err
	draw_string(f, Vector2(o.x * T, o.y * T - 6), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95) if ok else Color(1.0, 0.6, 0.55))
	if not plan_mode:
		preview_cost = Templates.cost(sim, id, o)


func _select_at() -> void:
	var mp := get_global_mouse_position()
	if FxLayer.sign_at(sim, mp) >= 0:
		cell_clicked.emit(_mouse_cell())   # 1.40: табличка «Продаётся» — game_main откроет «Развитие» на участке
		return
	var ctl_on := sim.brain.controlled_worker() != null
	var best_id := -1
	var bd := 22.0 * 22.0
	for w in sim.workers + sim.visitors:
		if not w.present or w.hidden:
			continue
		var center := Vector2(w.pos.x * T, w.pos.y * T - 12.0)
		var d := center.distance_squared_to(mp)
		if d < bd:
			bd = d
			best_id = w.id
	if best_id >= 0 and not (ctl_on and best_id == sim.brain.controlled_worker().id):
		select_worker(best_id)
		return
	var mc := _mouse_cell()
	if ctl_on:
		control_click.emit(mc, get_viewport().get_mouse_position())
		return
	var t := sim.thing_at(mc)
	if t:
		select_thing(t.id)
		return
	clear_selection()
	# стена, окно, дверь, забор или пол — тоже можно щёлкнуть: карточка с описанием и сносом
	if not sim.world.inb(mc):
		return
	var i := sim.world.idx(mc)
	if sim.world.wall[i] != World.W_NONE or sim.world.bp_wall[i] != World.BP_NONE:
		cell_clicked.emit(mc)
		return
	# 1.18: авария на сети или груз на земле — своя карточка
	if sim.faults.at("cable", mc) or sim.faults.at("pipe", mc) or not sim.logi.ground_on(mc).is_empty():
		cell_clicked.emit(mc)
		return
	# 1.50b: обычный щелчок по полу или зоне ничего не открывает (карточка зоны — только из меню «Зоны»)
	if sim.rooms.room_at(mc):
		return
	if sim.world.bp_floor[i] != World.BP_NONE or sim.world.flora[i] != 0:
		cell_clicked.emit(mc)


# ---------------------------------------------------------------- рисование предпросмотра

# ---------------------------------------------------------------- 1.40: оверлей «Логистика»
var logi_src: Rooms.Room = null     ## откуда тянут линию (цех или контора)
var logi_press: Rooms.Room = null   ## на чём нажали, если это не источник (столовая — переключатель «только ИТР»)


func _logi_room(p: Vector2) -> Rooms.Room:
	return sim.rooms.room_at(Vector2i(floori(p.x / T), floori(p.y / T)))


func _logi_set_src(r: Rooms.Room) -> void:
	logi_src = r
	if overlay:
		overlay.logi_src = r.id if r else -1
		overlay.queue_redraw()
	queue_redraw()


## Убрать связь под точкой мира. true — что-то убрали.
func logi_remove_at(p: Vector2) -> bool:
	var l := OverlayLayer.logi_hit(sim, p, T * 0.5)
	if l.is_empty():
		return false
	sim.areas.unlink(l["src"], str(l["kind"]), bool(l["itr"]))
	message.emit(L.t("Связь убрана: %s — теперь ближайшее.") % L.t(str(OverlayLayer.LOGI_NAME[str(l["kind"])])).to_lower(), true)
	if overlay:
		overlay.queue_redraw()
	return true


func logi_press_at(p: Vector2) -> void:
	logi_press = null
	if logi_remove_at(p):
		return
	var r := _logi_room(p)
	if r != null and (r.type == "workshop" or Areas.is_office_type(r.type)):
		_logi_set_src(r)
	else:
		logi_press = r


func logi_release_at(p: Vector2) -> void:
	var dst := _logi_room(p)
	if logi_src != null:
		var src := logi_src
		_logi_set_src(null)
		if dst == null or dst.id == src.id:
			return
		var kind := sim.areas.drag_link(src, dst)
		if kind == "":
			message.emit(L.t("Сюда линию не провести: цех тянется к бытовке, душевой, туалету, столовой или комнате отдыха, контора (ИТР) — к туалету, столовой и комнате отдыха."), false)
		else:
			message.emit(L.t("Связь: %s — %s.") % [L.t(str(OverlayLayer.LOGI_NAME[kind])).to_lower(), dst.title()], true)
	elif logi_press != null and dst != null and dst.id == logi_press.id and dst.type == "canteen":
		var on := not sim.areas.is_itr_canteen(dst)
		sim.areas.set_itr_canteen(dst, on)
		message.emit(L.t("Столовая только для ИТР: рабочие туда не ходят.") if on else L.t("Столовая снова для всех."), true)
	logi_press = null
	if overlay:
		overlay.queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var w := sim.world
	if mode == "logistics" and logi_src != null:
		var a := logi_src.center * T
		var b := get_global_mouse_position()
		draw_line(a, b, Color(1, 1, 1, 0.85), 3.0, true)
		draw_circle(b, 5.0, Color(1, 1, 1, 0.9))
	# чертежи стен
	for i in sim.bp_cells.keys():
		var bw := w.bp_wall[i]
		if bw == World.BP_NONE:
			continue
		var c := w.cell_of(i)
		var r := Rect2(c.x * T, c.y * T, T, T)
		if bw == 0:
			_cross(r, Color(0.95, 0.35, 0.3, 0.9))
		else:
			# призрак: так будет выглядеть стена, окно, дверь или ворота после постройки
			var nbd := WallPiece.neighbors(w, c, bw, true)
			WallPiece.paint(self, bw, r.position, nbd, 0.0, 1.0, true)
	# объекты под снос и выделенный объект
	for t: Thing in sim.things.values():
		if t.demolish:
			var rr := Rect2(Vector2(t.cell) * T, Vector2(t.size()) * T)
			draw_rect(rr, Color(0.95, 0.35, 0.3, 0.9), false, 2.0)
	var cw2 := sim.brain.controlled_worker()
	if cw2 and cw2.present and not cw2.hidden:
		# 1.19: под управлением — янтарное кольцо под ногами и рамка клетки под курсором
		var fp := cw2.pos * T
		var pa := 0.55 + 0.35 * sin(_t * 5.0)
		draw_arc(fp + Vector2(0, 2), 13.0, 0.0, TAU, 32, Color(0.98, 0.72, 0.2, pa), 2.5)
		draw_arc(fp + Vector2(0, 2), 17.0 + fmod(_t * 10.0, 8.0), 0.0, TAU, 32, Color(0.98, 0.72, 0.2, 0.5 - fmod(_t * 10.0, 8.0) / 16.0), 1.5)
		if mode == "select" and sim.world.inb(hover):
			draw_rect(Rect2(Vector2(hover) * T, Vector2(T, T)).grow(-1), Color(0.98, 0.72, 0.2, 0.85), false, 2.0)
	var line_w := sim.get_worker(sel_id) if sel_kind == "worker" else null
	if cw2:
		line_w = cw2
	if line_w:
		var sw := line_w
		if sw and not sw.order.is_empty():
			# куда послан: пунктир от человека и флажок
			var oc := Vector2(int(sw.order["cx"]) + 0.5, int(sw.order["cy"]) + 0.5) * T
			var from := (sw.pos) * T
			var col := Color(0.98, 0.78, 0.3, 0.85)
			draw_dashed_line(from, oc, col, 2.0, 8.0)
			draw_line(oc + Vector2(0, 10), oc + Vector2(0, -16), Color(0.2, 0.2, 0.2), 2.5)
			draw_colored_polygon(PackedVector2Array([oc + Vector2(0, -16), oc + Vector2(13, -11), oc + Vector2(0, -6)]), col)
	if sel_kind == "thing" and sim.things.has(sel_id):
		var st: Thing = sim.things[sel_id]
		var rs := Rect2(Vector2(st.cell) * T, Vector2(st.size()) * T).grow(2)
		var a := 0.6 + 0.3 * sin(_t * 4.0)
		draw_rect(rs, Color(0.45, 0.85, 0.55, a), false, 2.0)
	if mode == "select":
		return
	# сетка участка
	var pr := w.plot
	var gc := Color(1, 1, 1, 0.07)
	for x in range(pr.position.x, pr.end.x + 1):
		draw_line(Vector2(x * T, pr.position.y * T), Vector2(x * T, pr.end.y * T), gc, 1.0)
	for y in range(pr.position.y, pr.end.y + 1):
		draw_line(Vector2(pr.position.x * T, y * T), Vector2(pr.end.x * T, y * T), gc, 1.0)
	preview_cost = 0.0
	if mode == "object":
		_draw_object_ghost()
		return
	if mode == "template":
		_draw_template_ghost()
		return
	if mode == "room":
		_draw_zone_preview()
		return
	var cells: Array[Vector2i] = []
	if mode in ["cable", "pipe", "duct", "air"]:
		cells = cable_path(drag_from, hover) if dragging else [hover]
		var pc := Color(0.95, 0.78, 0.3, 0.8)
		match mode:
			"pipe":
				pc = Color(0.35, 0.65, 1.0, 0.85)
			"duct":
				pc = Color(0.72, 0.78, 0.82, 0.85)
			"air":
				pc = Color(0.95, 0.55, 0.25, 0.85)
		for c in cells:
			if w.in_plot(c):
				var rc := Rect2(c.x * T + 8, c.y * T + 8, T - 16, T - 16)
				if mode == "duct":
					rc = Rect2(c.x * T + 4, c.y * T + 4, T - 8, T - 8)
				draw_rect(rc, pc)
				if w.net_at(mode, c) == 0:
					preview_cost += sim.net_cost(mode)
		return
	if mode == "roomframe" and dragging:
		var rf := _drag_rect(drag_from, hover)
		var ok := rf.size.x >= 3 and rf.size.y >= 3
		draw_rect(Rect2(Vector2(rf.position) * T, Vector2(rf.size) * T), Color(0.55, 0.8, 1.0, 0.18) if ok else Color(0.95, 0.4, 0.35, 0.2))
		if ok:
			var wset := {}
			for c0 in _wall_cells(rf):
				wset[c0] = true
			for c1 in _wall_cells(rf):
				var nbd0 := WallPiece.neighbors(w, c1, World.W_BRICK, true)
				if not bool(nbd0["dn"]) and wset.has(c1 + Vector2i(0, 1)):
					nbd0["dn"] = true
				WallPiece.paint(self, World.W_BRICK, Vector2(c1) * T, nbd0, 0.0, 1.0, true)
			var dc := sim.room_door_cell(rf)
			draw_rect(Rect2(Vector2(dc) * T, Vector2(T, T)), Color(0.95, 0.8, 0.35, 0.8))
			preview_cost = sim.room_bp_cost(rf, int(arg))
		return
	if dragging:
		var r2 := _drag_rect(drag_from, hover)
		match mode:
			"wall":
				cells = _wall_cells(r2)
			"door", "window", "gate":
				cells = _opening_cells(r2)
			_:
				for y in range(r2.position.y, r2.end.y):
					for x in range(r2.position.x, r2.end.x):
						cells.append(Vector2i(x, y))
	else:
		cells = [hover]
	var col := Color(0.4, 0.7, 1.0, 0.35)
	if mode == "demolish":
		col = Color(0.95, 0.4, 0.35, 0.35)
	elif mode in ["cancel", "uncable", "unpipe", "unduct", "unair"]:
		col = Color(0.95, 0.75, 0.3, 0.35)
	var unit := 0.0
	match mode:
		"floor":
			unit = sim.floor_cost(int(arg))
		"wall", "door", "window", "gate":
			unit = sim.wall_cost(int(arg))
	# стены, окна, двери и ворота — сразу в виде будущего объекта (проём из нескольких клеток — одним целым)
	var opening := mode in ["door", "window", "gate"] and arg != null
	var cset := {}
	if opening or mode == "wall":
		for c0 in cells:
			cset[c0] = true
	for c in cells:
		if not w.in_plot(c):
			continue
		var r3 := Rect2(c.x * T, c.y * T, T, T)
		if (opening or mode == "wall") and arg != null:
			var k := int(arg)
			var nbd := WallPiece.neighbors(w, c, k, true)
			if mode == "wall":
				if not bool(nbd["dn"]) and cset.has(c + Vector2i(0, 1)):
					nbd["dn"] = true
			else:
				var vert := bool(nbd["vert"])
				var cu := cset.has(c + Vector2i(0, -1)) or cset.has(c + Vector2i(0, 1))
				var cl := cset.has(c + Vector2i(-1, 0)) or cset.has(c + Vector2i(1, 0))
				if cu and not cl:
					vert = true
				elif cl and not cu:
					vert = false
				nbd["vert"] = vert
				var sa := c + (Vector2i(0, -1) if vert else Vector2i(-1, 0))
				var sb := c + (Vector2i(0, 1) if vert else Vector2i(1, 0))
				nbd["same_a"] = bool(nbd["same_a"]) or cset.has(sa)
				nbd["same_b"] = bool(nbd["same_b"]) or cset.has(sb)
			WallPiece.paint(self, k, r3.position, nbd, 0.0, 1.0, true)
		else:
			draw_rect(r3, col)
		draw_rect(r3.grow(-0.5), Color(col.r, col.g, col.b, 0.9), false, 1.0)
		preview_cost += unit


## Разметка зоны: прямоугольник при протягивании, при наведении — клетки, которые зальёт щелчок.
func _draw_zone_preview() -> void:
	if not (arg is String) or str(arg) == "":
		return
	var w := sim.world
	var er := str(arg) == "_erase"
	var col := Color(0.95, 0.45, 0.4) if er else Color(str(Defs.rooms.get(str(arg), {}).get("color", "#88aaff")))
	if dragging:
		var r := _drag_rect(drag_from, hover)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				if not w.inb(c):
					continue
				var inner := w.flr[w.idx(c)] > 0 and w.wall[w.idx(c)] == World.W_NONE
				var rc := Rect2(Vector2(c) * T, Vector2(T, T))
				draw_rect(rc, Color(col.r, col.g, col.b, 0.30 if inner else 0.08))
		draw_rect(Rect2(Vector2(r.position) * T, Vector2(r.size) * T), Color(col.r, col.g, col.b, 0.9), false, 2.0)
		return
	var room := sim.rooms.room_at(hover)
	if room:
		for c2 in room.cells:
			draw_rect(Rect2(Vector2(c2) * T, Vector2(T, T)), Color(col.r, col.g, col.b, 0.16))
	draw_rect(Rect2(Vector2(hover) * T, Vector2(T, T)), Color(col.r, col.g, col.b, 0.85), false, 2.0)


func _draw_object_ghost() -> void:
	var def_id := str(arg)
	var sk := Thing.sprite_for(def_id, place_rot)
	var key := "chair_down" if def_id == "chair" else str(sk[0])
	var meta: Dictionary = Defs.sprites.get(key, {})
	var tex := Tex.obj(key)
	var ok := (sim.plan.can_add_obj(def_id, hover, place_rot) if plan_mode else sim.can_place(def_id, hover, place_rot)) == ""
	var d: Dictionary = Defs.objects.get(def_id, {})
	var bs: Array = d.get("size", [1, 1])
	var s := Thing.rot_size(Vector2i(int(bs[0]), int(bs[1])), place_rot)
	var bottom := Vector2(hover.x * T, (hover.y + s.y) * T)
	var col := Color(0.6, 1.0, 0.65, 0.7) if ok else Color(1.0, 0.45, 0.4, 0.7)
	if plan_mode and ok:
		col = Color(0.62, 0.82, 1.0, 0.75)
	draw_rect(Rect2(Vector2(hover) * T, Vector2(s) * T), Color(col.r, col.g, col.b, 0.25))
	if tex:
		var sz := tex.get_size() * 0.5
		var pos := bottom - Vector2(float(meta.get("ox", 0)), float(meta.get("oy", 64))) * 0.5
		if bool(sk[1]) and def_id != "chair":
			draw_set_transform(Vector2(pos.x * 2.0 + float(s.x) * T, 0), 0.0, Vector2(-1, 1))
			draw_texture_rect(tex, Rect2(pos, sz), false, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, Rect2(pos, sz), false, col)
	# 1.21: светильник — сразу видно, какой круг он осветит (у лампы, ЛПО и ДРЛ — разный)
	if d.has("light_r"):
		var lr := float(d["light_r"]) * T
		var lc := (Vector2(hover) + Vector2(0.5, 0.5)) * T
		var warm := Color(1.0, 0.86, 0.45) if def_id != "lamp_tube" else Color(0.85, 0.95, 1.0)
		if def_id == "lamp_drl":
			warm = Color(0.82, 0.9, 1.0)
		for k in 5:
			var f := 1.0 - k * 0.2
			draw_circle(lc, lr * f, Color(warm.r, warm.g, warm.b, 0.05 + k * 0.025))
		draw_arc(lc, lr, 0, TAU, 64, Color(warm.r, warm.g, warm.b, 0.7), 2.0)
		draw_circle(lc, 5.0, Color(warm.r, warm.g, warm.b, 0.95))
	# кран-балка: показать пути вдоль стен и мост от стены до стены
	if bool(d.get("span", false)):
		var room := sim.rooms.room_at(hover)
		if room:
			var rr := room.srect
			var x0 := rr.position.x * T + 3.0
			var x1 := rr.end.x * T - 3.0
			for xx in [x0, x1]:
				draw_line(Vector2(xx, rr.position.y * T + 2.0), Vector2(xx, rr.end.y * T - 2.0), Color(col.r, col.g, col.b, 0.8), 4.0)
			var by := (hover.y + 0.5) * T
			draw_rect(Rect2(x0 - 4.0, by - 5.0, x1 - x0 + 8.0, 10.0), Color(col.r, col.g, col.b, 0.55))
			draw_rect(Rect2(x0 - 4.0, by - 5.0, x1 - x0 + 8.0, 10.0), Color(col.r, col.g, col.b, 0.95), false, 1.5)
	# где будет стоять рабочий: стрелки на местах работы
	var tmp := Thing.new()
	tmp.def_id = def_id
	tmp.cell = hover
	tmp.rot = place_rot
	for sp: Dictionary in tmp.spots():
		var cc: Vector2i = sp["cell"]
		var ctr := (Vector2(cc) + Vector2(0.5, 0.5)) * T
		draw_circle(ctr, 5.0, Color(1, 1, 1, 0.55))
		draw_circle(ctr, 3.0, Color(0.2, 0.55, 0.3, 0.9))
	preview_cost = sim.thing_cost(str(arg))


func _cross(r: Rect2, col: Color) -> void:
	var a := r.grow(-6)
	draw_line(a.position, a.end, col, 3.0)
	draw_line(Vector2(a.end.x, a.position.y), Vector2(a.position.x, a.end.y), col, 3.0)
