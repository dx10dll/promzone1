class_name TutorialPanel
extends PanelContainer
## 1.17: обучение «на дурака». Сначала — карточка «что мы вообще делаем» со схемой завода, потом шаги:
## экран затемняется, светится ровно то, куда нажать (кнопка, плитка меню, человек на карте),
## к нему ведёт пульсирующая рамка со стрелкой. Шаг засчитывается сам, когда игрок сделал, что просили;
## шаги-пояснения закрываются кнопкой «Понятно».

const STEPS := [
	{"id": "intro", "card": true, "title": "Что мы делаем",
		"text": "Вы — директор маленькой мастерской в гаражном боксе. Завод работает по кругу: заказ → металл → станок → проверка ОТК → отгрузка → деньги. Люди всё делают сами — вы решаете, что построить, кого нанять и какие заказы брать.",
		"do": "Цель сценария — вырасти до малого предприятия: выполнять заказы, строить цеха, нанимать людей."},
	{"id": "cam", "title": "Осмотритесь", "text": "Это ваш гараж: станок, стеллажи, бытовка и трое работников.",
		"do": "Подвигайте камеру: WASD или стрелки. Колесо мыши — ближе и дальше.", "done": "cam"},
	{"id": "speed", "title": "Время", "text": "Игра идёт сама. На паузе можно спокойно строить и читать.",
		"do": "Пауза — пробел, скорость — клавиши 1, 2, 3 или эти кнопки.", "target": "speed", "next": true},
	{"id": "worker", "title": "Ваши люди", "text": "Каждый человек живой: работает, ест, устаёт, обижается на низкую зарплату.",
		"do": "Щёлкните по любому работнику на карте.", "target": "worker", "done": "sel_worker"},
	{"id": "card", "title": "Меню человека", "text": "Над человеком — чем занят и его настроение. Жёлтая кнопка «Взять под управление» — человек бросит своё и сразу сделает то, что вы покажете щелчком: построит чертёж, встанет за станок, отнесёт груз. «Открыть карточку» — что ему важно (быт, деньги, работа, коллектив, дом) и что умеет.",
		"do": "Посмотрите меню и нажмите «Понятно».", "target": "info", "next": true},
	{"id": "orders", "title": "Заказы", "text": "Заказы берёт отдел сбыта сам — только те, что вы успеете сделать.",
		"do": "Откройте «Заказы» — там видно, что в работе и когда срок.", "target": "btn:orders", "done": "orders"},
	{"id": "money", "title": "Деньги и этап", "text": "Деньги приходят, когда клиент забирает заказ. Рядом — этап завода: выполните цели этапа, и откроются новые станки и отделы.",
		"do": "Это главные цифры — следите за ними.", "target": "chips", "next": true},
	{"id": "rack", "title": "Склад", "text": "Металл и готовые детали лежат на стеллажах. Места мало — поставим ещё один.",
		"do": "«Объекты» → «Склад» → «Стеллаж», затем щёлкните по свободному полу в гараже.", "target": "dyn:rack", "done": "rack"},
	{"id": "build", "title": "Стройка", "text": "Цеху тесно. Проще всего — готовое помещение: стены, пол, двери, мебель и зона разом. Строители всё сделают сами.",
		"do": "«Стройка» → «Помещения» → «Склад 6×4», затем щёлкните по свободной земле рядом с гаражом.", "target": "dyn:build", "done": "template"},
	{"id": "nets", "title": "Ток и вода", "text": "Станкам нужен ток от подстанции, туалету — вода от насосной (обе — в техпомещении). Кабель и трубы тянут в «Сетях» прямо в клетку прибора.",
		"do": "Включите слой «Коммуникации» справа — так видно, что куда подключено.", "target": "ov:nets", "done": "ov_nets"},
	{"id": "hire", "title": "Найм", "text": "Рук не хватает: строить, носить металл, работать у станков.",
		"do": "«Люди» → «Найм»: выберите человека и нажмите «Нанять».", "target": "dyn:hire", "done": "hire"},
	{"id": "todo", "title": "Список задач", "text": "Слева сверху — что сейчас важно: срочные письма, заказы, цели этапа. Щёлкните по строке — откроется нужное окно.",
		"do": "Заглядывайте сюда, когда не знаете, что делать дальше.", "target": "todo", "next": true},
	{"id": "goals", "title": "Цели", "text": "Первая цель — 10 заказов и миллион оборота. Прогресс и рейтинг в звёздах — в «Целях».",
		"do": "Откройте «Цели».", "target": "btn:goals", "done": "goals"},
	{"id": "end", "card": true, "title": "Готово!", "text": "Теперь вы знаете главное. Остальное подскажут список задач и письма. Полная справка — F1 или «Как играть» в меню паузы.",
		"do": "Удачи, директор!"},
]

var hud: Hud
var sim: Sim
var title_l: Label
var text_l: Label
var do_l: Label
var step_l: Label
var next_b: Button
var dots: HBoxContainer
var card_box: Control = null
var spot: Spot
var _spot_layer: CanvasLayer
var _cam0 := Vector2.ZERO
var _zoom0 := Vector2.ONE
var _t := 0.0
var _base := {}   ## снимок на входе в шаг: сколько было стеллажей, людей…
var _cur := -2


## Затемнение экрана с «окном» вокруг цели и пульсирующей рамкой.
class Spot:
	extends Control
	var target := Rect2()
	var full := false   ## карточка: затемнить весь экран
	var _t := 0.0

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var vs := get_viewport_rect().size
		if full:
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.04, 0.5))
			return
		if target.size == Vector2.ZERO:
			return
		var r := target.grow(6.0)
		var dim := Color(0.02, 0.03, 0.04, 0.55)
		draw_rect(Rect2(0, 0, vs.x, r.position.y), dim)
		draw_rect(Rect2(0, r.end.y, vs.x, vs.y - r.end.y), dim)
		draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
		draw_rect(Rect2(r.end.x, r.position.y, vs.x - r.end.x, r.size.y), dim)
		var p := 0.5 + 0.5 * sin(_t * 5.0)
		var col := Color(1.0, 0.78, 0.25, 0.65 + 0.35 * p)
		draw_rect(r.grow(2.0 + p * 3.0), Color(col, 0.25), false, 4.0)
		draw_rect(r, col, false, 2.5)
		# стрелка к цели: сверху, если есть место, иначе снизу
		var up := r.position.y > 70.0
		var tip := Vector2(r.get_center().x, r.position.y - 4.0) if up else Vector2(r.get_center().x, r.end.y + 4.0)
		var dir := -1.0 if up else 1.0
		var bob := sin(_t * 6.0) * 4.0
		var t2 := tip + Vector2(0, dir * (6.0 + bob))
		var pts := PackedVector2Array([t2, t2 + Vector2(-11, dir * 16), t2 + Vector2(-4, dir * 16), t2 + Vector2(-4, dir * 32),
			t2 + Vector2(4, dir * 32), t2 + Vector2(4, dir * 16), t2 + Vector2(11, dir * 16)])
		draw_colored_polygon(pts, col)
		draw_polyline(pts + PackedVector2Array([t2]), Color(0.1, 0.08, 0.02, 0.8), 1.2)


func setup(h: Hud) -> void:
	hud = h
	sim = h.sim
	add_theme_stylebox_override("panel", UITheme.sbs(Color(0.1, 0.11, 0.1, 0.97), Color("#c9a24a"), 2, 12, 18, 14, 18, 0.55, 5))
	custom_minimum_size = Vector2(420, 0)
	var v := UITheme.vbox(8)
	add_child(v)
	var h2 := UITheme.hbox(8)
	step_l = UITheme.label("", 12, Color("#c9a24a"), UITheme.f_semi)
	h2.add_child(step_l)
	h2.add_child(UITheme.spacer())
	h2.add_child(UITheme.ghost("Пропустить обучение", _skip, "", UITheme.MUTED))
	v.add_child(h2)
	title_l = UITheme.label("", 20, UITheme.TEXT, UITheme.f_semi)
	v.add_child(title_l)
	text_l = UITheme.label("", 14, UITheme.TEXT)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.custom_minimum_size = Vector2(384, 0)
	v.add_child(text_l)
	card_box = UITheme.vbox(0)
	v.add_child(card_box)
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", UITheme.sb(Color(0.85, 0.65, 0.2, 0.12), Color(0.85, 0.65, 0.2, 0.5), 1, 8, 12, 8))
	do_l = UITheme.label("", 15, Color("#f0cf7a"), UITheme.f_semi)
	do_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	do_l.custom_minimum_size = Vector2(380, 0)
	dp.add_child(do_l)
	v.add_child(dp)
	var bh := UITheme.hbox(8)
	dots = UITheme.hbox(4)
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(dots)
	bh.add_child(UITheme.spacer())
	next_b = UITheme.primary("Понятно  →", _next)
	next_b.custom_minimum_size = Vector2(150, 36)
	bh.add_child(next_b)
	v.add_child(bh)
	_spot_layer = CanvasLayer.new()
	_spot_layer.layer = 11
	hud.add_child(_spot_layer)
	spot = Spot.new()
	_spot_layer.add_child(spot)
	_cam0 = hud.g.cam.position
	_zoom0 = hud.g.cam.zoom
	_show()


func _skip() -> void:
	sim.progress.tutorial = -1
	_show()


func _next() -> void:
	var was_card := bool(_step().get("card", false))
	sim.progress.tutorial += 1
	if was_card and hud.g.speed == 0:
		hud.g.set_speed(1)   # прочитали карточку — время пошло
	if sim.progress.tutorial >= STEPS.size():
		sim.progress.tutorial = -1
		hud.toast("Обучение пройдено! Справка — F1, цели — G.", Sim.LVL_GOOD, 6.0)
	Snd.play("ui_click", -6.0)
	_show()


func _step() -> Dictionary:
	var i := sim.progress.tutorial
	return STEPS[i] if i >= 0 and i < STEPS.size() else {}


func _show() -> void:
	var i := sim.progress.tutorial
	visible = i >= 0 and i < STEPS.size()
	if spot:
		spot.target = Rect2()
		spot.full = false
	if not visible:
		return
	var st := _step()
	var fresh := i != _cur
	_cur = i
	if fresh and i > 0:
		_tidy(str(st["id"]))
	_snapshot()
	var is_card := bool(st.get("card", false))
	if is_card and hud.g.speed != 0:
		hud.g.set_speed(0)   # 1.17: пока читают карточку — пауза
	step_l.text = "ОБУЧЕНИЕ · %d ИЗ %d" % [i + 1, STEPS.size()]
	title_l.text = str(st["title"])
	text_l.text = str(st["text"])
	do_l.text = ("▶ " if not is_card else "") + str(st.get("do", ""))
	next_b.visible = is_card or bool(st.get("next", false))
	next_b.text = "Начать обучение  →" if str(st["id"]) == "intro" else ("Играть" if str(st["id"]) == "end" else "Понятно  →")
	UITheme.clear(card_box)
	if str(st["id"]) == "intro":
		card_box.add_child(_cycle())
	UITheme.clear(dots)
	for k in STEPS.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(7, 7)
		d.color = Color("#c9a24a") if k == i else (Color(0.8, 0.75, 0.6, 0.5) if k < i else Color(1, 1, 1, 0.15))
		dots.add_child(d)
	# карточки — по центру экрана, шаги — слева
	if is_card:
		custom_minimum_size = Vector2(560, 0)
		text_l.custom_minimum_size = Vector2(524, 0)
		do_l.custom_minimum_size = Vector2(520, 0)
	else:
		custom_minimum_size = Vector2(420, 0)
		text_l.custom_minimum_size = Vector2(384, 0)
		do_l.custom_minimum_size = Vector2(380, 0)
	size = Vector2.ZERO
	call_deferred("reset_size")


## 1.21: новый шаг — убрать окна и меню прошлого шага и показать камерой то, о чём речь.
func _tidy(id: String) -> void:
	if id != "card":
		hud.worker_pop.close()
		hud.close_window()
		hud.close_sub()
		if hud.g.tool.mode != "select":
			hud.g.tool.set_mode("select")
		hud.info.visible = false
	if id != "nets" and hud.forced_overlay == "nets":
		hud.forced_overlay = ""
	var c := _focus_cell(id)
	if c.x >= 0:
		hud.g.cam.focus_cell(c)


func _focus_cell(id: String) -> Vector2i:
	match id:
		"worker":
			for w in sim.workers:
				if w.present and not w.visitor:
					return w.cell()
		"rack":
			for t: Thing in sim.things.values():
				if t.def_id == "rack":
					return t.cell
		"nets":
			for t2 in sim.things_of("pump"):
				return t2.cell
		"build":
			# свободная земля рядом с постройками
			var br := Rect2i()
			for r in sim.rooms.list:
				br = r.srect if br.size == Vector2i.ZERO else br.merge(r.srect)
			if br.size != Vector2i.ZERO:
				return Vector2i(br.get_center().x, mini(br.end.y + 5, sim.world.plot.end.y - 4))
	return Vector2i(-1, -1)


## Схема «как работает завод»: значки по кругу.
func _cycle() -> Control:
	var h := UITheme.hbox(4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var items := [["orders", "заказ"], ["supply", "металл"], ["shop", "станок"], ["inspect", "ОТК"], ["phone", "отгрузка"], ["money", "деньги"]]
	for k in items.size():
		var v := UITheme.vbox(2)
		var ic := TextureRect.new()
		ic.texture = Tex.ui(str(items[k][0]))
		ic.custom_minimum_size = Vector2(38, 38)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Color("#f0cf7a")
		v.add_child(ic)
		var l := UITheme.label(str(items[k][1]), 12, UITheme.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		h.add_child(v)
		if k < items.size() - 1:
			var a := UITheme.label("→", 20, Color("#c9a24a"), UITheme.f_semi)
			a.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			h.add_child(a)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	m.add_child(h)
	return m


func _snapshot() -> void:
	_base = {"racks": sim.things.values().filter(func(t: Thing) -> bool: return t.def_id == "rack").size(),
		"staff": sim.workers.filter(func(w: Worker) -> bool: return not w.visitor).size(),
		"okz": sim.plan.ok_zones.size(), "rooms": sim.rooms.list.size()}
	_cam0 = hud.g.cam.position
	_zoom0 = hud.g.cam.zoom


func _process(delta: float) -> void:
	if sim.progress.tutorial != _cur:
		_show()
	if not visible:
		return
	var ms := get_combined_minimum_size()
	if size.y > ms.y + 1.0:
		size = Vector2(size.x, ms.y)
	_place()
	spot.full = bool(_step().get("card", false))
	spot.target = _target_rect()
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.3
	var st := _step()
	if st.has("done") and _done(str(st["done"])):
		_next()


## Карточки — в центре; шаги — слева, но не под списком задач и не поверх цели.
func _place() -> void:
	var vs := get_viewport_rect().size
	if bool(_step().get("card", false)):
		position = (vs - size) * 0.5
		return
	var y := vs.y * 0.5 - size.y * 0.5
	if hud.todo and hud.todo.visible:
		y = maxf(y, hud.todo.position.y + hud.todo.size.y + 10.0)
	var x := 12.0
	var tr := spot.target if spot else Rect2()
	if tr.size != Vector2.ZERO and Rect2(Vector2(x, y), size).intersects(tr.grow(10)):
		x = vs.x - size.x - 70.0
	position = Vector2(x, minf(y, vs.y - 96.0 - size.y - 8.0))


func _target_rect() -> Rect2:
	var t := str(_step().get("target", ""))
	if t == "":
		return Rect2()
	if t.begins_with("btn:"):
		return _rect_of(hud.bottom_btns.get(t.substr(4)))
	if t.begins_with("ov:"):
		return _rect_of(hud.ov_btns.get(t.substr(3)))
	match t:
		"speed":
			return _rect_of(hud.speed_box)
		"info":
			if hud.info.visible:
				return _rect_of(hud.info)
			return _rect_of(hud.worker_pop) if hud.worker_pop.visible else Rect2()
		"todo":
			return _rect_of(hud.todo)
		"chips":
			var a := _rect_of(hud._chips.get("money"))
			var b := _rect_of(hud._chips.get("goals"))
			return a.merge(b) if a.size != Vector2.ZERO and b.size != Vector2.ZERO else a
		"worker":
			return _worker_rect()
		"dyn:rack":
			return _menu_target("objects", "Склад", "rack")
		"dyn:build":
			return _menu_target("build", "Помещения", "storage")
		"dyn:hire":
			if hud.win == null or hud.win.group != "people":
				return _rect_of(hud.bottom_btns.get("people"))
			if hud.win.sec != "hire":
				return _rect_of(hud.win._rail_btns.get("hire"))
			return Rect2()
	return Rect2()


## Меню снизу: кнопка → раздел → плитка; когда плитка выбрана — подсвечивать нечего, ставьте на карту.
func _menu_target(sub: String, cat: String, arg: String) -> Rect2:
	if hud.sub_kind != sub:
		return _rect_of(hud.bottom_btns.get(sub))
	if hud.g.tool.arg != null and str(hud.g.tool.arg) == arg:
		return Rect2()
	var tile := _find(hud.sub_panel, "arg", arg)
	if tile:
		return _rect_of(tile)
	var cb := _find(hud.sub_panel, "cat", cat)
	return _rect_of(cb) if cb else _rect_of(hud.sub_panel)


func _find(n: Node, key: String, val: String) -> Control:
	if n == null:
		return null
	for c in n.get_children():
		if c is Control and c.has_meta(key) and str(c.get_meta(key)) == val and (c as Control).is_visible_in_tree():
			return c
		var r := _find(c, key, val)
		if r:
			return r
	return null


func _rect_of(c: Variant) -> Rect2:
	if c == null or not (c is Control) or not (c as Control).is_visible_in_tree():
		return Rect2()
	return (c as Control).get_global_rect()


func _worker_rect() -> Rect2:
	for w in sim.workers:
		if w.present and not w.visitor:
			var xf := hud.g.get_viewport().get_canvas_transform()
			var p := xf * (w.pos * World.T)
			var z := hud.g.cam.zoom.x
			return Rect2(p - Vector2(14, 34) * z, Vector2(28, 42) * z)
	return Rect2()


func _done(key: String) -> bool:
	match key:
		"cam":
			return hud.g.cam.position.distance_to(_cam0) > 3.0 * World.T or absf(hud.g.cam.zoom.x - _zoom0.x) > 0.2
		"sel_worker":
			return hud.g.tool.sel_kind == "worker"
		"orders":
			return hud.win != null and hud.win.group == "orders"
		"rack":
			return sim.things.values().filter(func(t: Thing) -> bool: return t.def_id == "rack").size() > int(_base.get("racks", 0))
		"template":
			return sim.plan.ok_zones.size() > int(_base.get("okz", 0)) or sim.rooms.list.size() > int(_base.get("rooms", 0))
		"ov_nets":
			return hud.forced_overlay == "nets"
		"hire":
			return sim.workers.filter(func(w: Worker) -> bool: return not w.visitor).size() > int(_base.get("staff", 0))
		"goals":
			return hud.win != null and hud.win.group == "goals"
	return false
