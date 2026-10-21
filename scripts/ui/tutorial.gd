class_name TutorialPanel
extends PanelContainer
## 1.17: обучение «на дурака». Сначала — карточка «что мы вообще делаем» со схемой завода, потом шаги:
## экран затемняется, светится ровно то, куда нажать (кнопка, плитка меню, человек на карте),
## к нему ведёт пульсирующая рамка со стрелкой. Шаг засчитывается сам, когда игрок сделал, что просили;
## шаги-пояснения закрываются кнопкой «Понятно».

## 1.29: шаги с "sub": true — подшаги одной главы (общая точка в полоске прогресса).
## "keep": true — на входе в шаг ничего не закрываем и камеру не трогаем (окно открыл сам игрок).
## "grp" — что должно быть открыто, пока идёт шаг ("person" — меню человека, "win:<группа>" — окно);
## закрыл раньше времени — возвращаемся к шагу "back", где это открывают.
## Окна и меню обучение само не закрывает: последний подшаг показывает крестик и ждёт, пока игрок закроет.
const STEPS := [
	{"id": "intro", "card": true, "title": "Что мы делаем",
		"text": "Вы — директор маленькой мастерской в гаражном боксе. Завод работает по кругу: заказ → металл → станок → проверка ОТК → отгрузка → деньги. Люди всё делают сами — вы решаете, что построить, кого нанять и какие заказы брать.",
		"do": "Цель сценария — вырасти до малого предприятия. Обучение займёт пару минут: покажем главные кнопки и окна. Игра пока на паузе."},
	{"id": "cam", "title": "Осмотритесь",
		"text": "Это ваш гараж: станок, стеллажи, бытовка и трое работников. Почти всё на карте можно выбрать щелчком.",
		"do": "Подвигайте камеру: WASD или стрелки. Колесо мыши — ближе и дальше.", "done": "cam"},
	{"id": "speed", "title": "Время",
		"text": "Здесь — часы завода. Игра идёт сама, как настоящий рабочий день. На паузе время стоит, а строить и читать можно спокойно.",
		"do": "Пробел — пауза, клавиши 1, 2, 3 — скорость. Или эти кнопки.", "target": "speed", "next": true},
	{"id": "worker", "title": "Ваши люди",
		"text": "В рамке — ваш работник. Каждый человек живой: работает, ест, устаёт, обижается на низкую зарплату.",
		"do": "Щёлкните по человеку в рамке — откроется его меню.", "target": "worker", "done": "sel_worker"},
	{"id": "pop", "sub": true, "keep": true, "grp": "person", "back": "worker", "title": "Меню человека",
		"text": "Здесь — кто он и кем работает, чем занят прямо сейчас и полоска настроения. Зелёная — доволен, жёлтая и красная — пора разобраться, что не так.",
		"do": "Посмотрите и нажмите «Далее».", "target": "pop", "next": true},
	{"id": "pop_ctl", "sub": true, "keep": true, "grp": "person", "back": "worker", "title": "Взять под управление",
		"text": "Жёлтая кнопка — «Взять под управление». Человек бросит своё и сразу сделает то, что вы покажете щелчком: построит чертёж, встанет за станок, отнесёт груз.",
		"do": "Пригодится, когда что-то нужно срочно. Сейчас — просто «Далее».", "target": "pop:ctl", "next": true},
	{"id": "pop_card", "sub": true, "keep": true, "grp": "person", "back": "worker", "title": "Карточка человека",
		"text": "«Открыть карточку» — всё о человеке: что ему важно (быт, деньги, работа, коллектив, дом), что он умеет, его черты характера.",
		"do": "Можно открыть её сейчас или потом. Дальше — «Далее».", "target": "pop:card", "next": true},
	{"id": "pop_close", "sub": true, "keep": true, "title": "Закрыть меню",
		"text": "Меню и окна в игре закрываются крестиком в углу — или клавишей Esc.",
		"do": "Нажмите × и закройте меню.", "target": "pop:close", "done": "pop_closed"},
	{"id": "orders", "title": "Заказы",
		"text": "Заказы — это ваши деньги. Отдел сбыта берёт их сам, и только те, что завод успеет сделать.",
		"do": "Откройте «Заказы» кнопкой внизу.", "target": "btn:orders", "done": "orders"},
	{"id": "orders_list", "sub": true, "keep": true, "grp": "win:orders", "back": "orders", "title": "Заказы в работе",
		"text": "Здесь — всё, что завод делает сейчас: готовность, срок и сумма. Срок краснеет — заказ горит: поднимите ему приоритет, и станки займутся им первым. Пусто — сбыт возьмёт заказы утром.",
		"do": "Посмотрите список и нажмите «Далее».", "target": "win:scroll", "next": true},
	{"id": "orders_rail", "sub": true, "keep": true, "grp": "win:orders", "back": "orders", "title": "Разделы окна",
		"text": "Слева — разделы окна. «Рынок» — какие заявки есть у клиентов и почему сбыт от каких-то отказался. «Архив» — выполненные и сорванные заказы.",
		"do": "Можно пощёлкать разделы. Потом — «Далее».", "target": "win:rail", "next": true},
	{"id": "orders_close", "sub": true, "keep": true, "title": "Закройте окно",
		"text": "Посмотрели — закрывайте. Открыть снова можно той же кнопкой внизу.",
		"do": "Нажмите × справа вверху (или Esc).", "target": "win:close", "done": "win_closed"},
	{"id": "money", "title": "Деньги и этап",
		"text": "Здесь — главные цифры. Деньги приходят, когда клиент забирает заказ. Рядом — этап завода: выполните цели этапа, и откроются новые станки и отделы.",
		"do": "Поглядывайте сюда. Дальше — «Далее».", "target": "chips", "next": true},
	{"id": "rack", "title": "Склад",
		"text": "Металл и готовые детали лежат на стеллажах. Места мало — поставим ещё один.",
		"do": "«Объекты» → «Склад» → «Стеллаж», затем щёлкните по свободному полу в гараже.", "target": "dyn:rack", "done": "rack"},
	{"id": "rack_close", "sub": true, "keep": true, "title": "Стеллаж заказан",
		"text": "Готово! Строитель сам принесёт материал и соберёт стеллаж. Меню «Объекты» ещё открыто — можно поставить что-нибудь ещё.",
		"do": "Закройте меню: Esc или ещё раз кнопка «Объекты».", "target": "btn:objects", "done": "sub_closed"},
	{"id": "build", "title": "Стройка",
		"text": "Цеху тесно. Проще всего — готовое помещение: стены, пол, двери, мебель и зона разом. Строители всё сделают сами.",
		"do": "«Стройка» → «Помещения» → «Склад 6×4», затем щёлкните по свободной земле рядом с гаражом.", "target": "dyn:build", "done": "template"},
	{"id": "build_close", "sub": true, "keep": true, "title": "Чертёж на месте",
		"text": "Помещение начерчено — строители возьмутся за него сами, когда освободятся. Пока стройка идёт, можно заниматься другим.",
		"do": "Закройте меню: Esc или ещё раз кнопка «Стройка».", "target": "btn:build", "done": "sub_closed"},
	{"id": "nets", "title": "Ток и вода",
		"text": "Станкам нужен ток от подстанции, туалету — вода от насосной (обе — в техпомещении). Кабель и трубы тянут в «Сетях» прямо в клетку прибора.",
		"do": "Включите слой «Коммуникации» справа — так видно, что куда подключено.", "target": "ov:nets", "done": "ov_nets"},
	{"id": "nets_look", "sub": true, "keep": true, "title": "Легенда слоя",
		"text": "Здесь — легенда: что значит каждый цвет на карте. Так сразу видно, где прибор без тока или воды.",
		"do": "Посмотрите на карту и нажмите «Далее».", "target": "legend", "next": true},
	{"id": "nets_off", "sub": true, "keep": true, "title": "Выключить слой",
		"text": "Слой выключается той же кнопкой. Включайте его, когда что-то не работает.",
		"do": "Нажмите кнопку слоя ещё раз.", "target": "ov:nets", "done": "ov_off"},
	{"id": "hire", "title": "Найм",
		"text": "Рук не хватает: строить, носить металл, стоять у станков. Наймём ещё одного человека.",
		"do": "«Люди» → «Найм»: выберите профессию, потом человека — и «Нанять».", "target": "dyn:hire", "done": "hire"},
	{"id": "hire_staff", "sub": true, "keep": true, "grp": "win:people", "back": "hire", "title": "Новичок в команде",
		"text": "Готово! Новый человек уже в «Сотрудниках» — там весь ваш коллектив: зарплаты, навыки, настроение.",
		"do": "Можно заглянуть туда. Потом — «Далее».", "target": "win:rail:staff", "next": true},
	{"id": "hire_close", "sub": true, "keep": true, "title": "Закройте окно",
		"text": "Окно «Люди» больше не нужно — закрывайте.",
		"do": "Нажмите × справа вверху (или Esc).", "target": "win:close", "done": "win_closed"},
	{"id": "todo", "title": "Список задач",
		"text": "Слева сверху — что сейчас важно: срочные письма, заказы, цели этапа. Щёлкните по строке — откроется нужное окно.",
		"do": "Заглядывайте сюда, когда не знаете, что делать дальше.", "target": "todo", "next": true},
	{"id": "goals", "title": "Цели",
		"text": "Куда расти — написано в «Целях». Первая цель — 10 заказов и миллион оборота.",
		"do": "Откройте «Цели» кнопкой внизу.", "target": "btn:goals", "done": "goals"},
	{"id": "goals_stage", "sub": true, "keep": true, "grp": "win:goals", "back": "goals", "title": "Цели этапа",
		"text": "Здесь — цели текущего этапа и прогресс по каждой. Выполните все — завод перейдёт на новый этап.",
		"do": "Посмотрите и нажмите «Далее».", "target": "win:scroll", "next": true},
	{"id": "goals_rail", "sub": true, "keep": true, "grp": "win:goals", "back": "goals", "title": "Рейтинг",
		"text": "«Рейтинг» — звёзды завода. Они складываются из пяти показателей и пересчитываются каждое утро; этапы и сценарии требуют определённого числа звёзд.",
		"do": "Можно открыть раздел. Потом — «Далее».", "target": "win:rail:rating", "next": true},
	{"id": "goals_close", "sub": true, "keep": true, "title": "Закройте окно",
		"text": "Всё, окно можно закрыть.",
		"do": "Нажмите × справа вверху (или Esc).", "target": "win:close", "done": "win_closed"},
	{"id": "end", "card": true, "title": "Готово!", "text": "Теперь вы знаете главное. Остальное подскажут список задач и письма. Полный справочник по разделам — F1, кнопка «?» вверху или меню паузы.",
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
## 1.29: рамка не прыгает — плавно едет к цели (экспоненциальное сглаживание), появляется и гаснет мягко,
## пульсирует медленно.
class Spot:
	extends Control
	var target := Rect2()   ## куда нужно (ставит панель обучения каждый кадр)
	var full := false   ## карточка: затемнить весь экран
	var _t := 0.0
	var _shown := Rect2()   ## где рамка сейчас
	var _a := 0.0           ## видимость рамки 0…1

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		var k := 1.0 - exp(-12.0 * delta)
		if target.size != Vector2.ZERO:
			if _a < 0.05:
				_shown = target   # из ничего — сразу на место, дальше — плавно
			else:
				_shown = Rect2(_shown.position.lerp(target.position, k), _shown.size.lerp(target.size, k))
			_a = minf(1.0, _a + delta * 5.0)
		else:
			_a = maxf(0.0, _a - delta * 5.0)
		queue_redraw()

	func _draw() -> void:
		var vs := get_viewport_rect().size
		if full:
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.04, 0.5))
			return
		if _a <= 0.0 or _shown.size == Vector2.ZERO:
			return
		var r := _shown.grow(6.0)
		var dim := Color(0.02, 0.03, 0.04, 0.55 * _a)
		draw_rect(Rect2(0, 0, vs.x, r.position.y), dim)
		draw_rect(Rect2(0, r.end.y, vs.x, vs.y - r.end.y), dim)
		draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
		draw_rect(Rect2(r.end.x, r.position.y, vs.x - r.end.x, r.size.y), dim)
		var p := 0.5 + 0.5 * sin(_t * 2.6)
		var col := Color(1.0, 0.78, 0.25, (0.8 + 0.2 * p) * _a)
		draw_rect(r.grow(3.0 + p * 4.0), Color(col, 0.18 * _a * (1.0 - 0.5 * p)), false, 5.0)
		draw_rect(r, col, false, 2.5)
		# стрелка к цели: сверху, если есть место, иначе снизу; большой цели (окно, список) стрелка не нужна
		if r.size.y > 160.0:
			return
		var up := r.position.y > 70.0
		var tip := Vector2(r.get_center().x, r.position.y - 4.0) if up else Vector2(r.get_center().x, r.end.y + 4.0)
		var dir := -1.0 if up else 1.0
		var bob := sin(_t * 3.0) * 3.0
		var t2 := tip + Vector2(0, dir * (6.0 + bob))
		var pts := PackedVector2Array([t2, t2 + Vector2(-11, dir * 16), t2 + Vector2(-4, dir * 16), t2 + Vector2(-4, dir * 32),
			t2 + Vector2(4, dir * 32), t2 + Vector2(4, dir * 16), t2 + Vector2(11, dir * 16)])
		draw_colored_polygon(pts, col)
		draw_polyline(pts + PackedVector2Array([t2]), Color(0.1, 0.08, 0.02, 0.8 * _a), 1.2)


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
	if fresh and i > 0 and not bool(st.get("keep", false)):
		_tidy(str(st["id"]))
	_snapshot()
	var is_card := bool(st.get("card", false))
	if is_card and hud.g.speed != 0:
		hud.g.set_speed(0)   # 1.17: пока читают карточку — пауза
	var ch := _chapter(i)
	var n_ch := _chapter(STEPS.size() - 1) + 1
	step_l.text = "ОБУЧЕНИЕ · ШАГ %d ИЗ %d" % [ch + 1, n_ch]
	title_l.text = str(st["title"])
	text_l.text = str(st["text"])
	do_l.text = ("▶ " if not is_card else "") + str(st.get("do", ""))
	next_b.visible = is_card or bool(st.get("next", false))
	next_b.text = "Начать обучение  →" if str(st["id"]) == "intro" else ("Играть" if str(st["id"]) == "end" else "Далее  →")
	UITheme.clear(card_box)
	if str(st["id"]) == "intro":
		card_box.add_child(_cycle())
	UITheme.clear(dots)
	for k in n_ch:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(7, 7)
		d.color = Color("#c9a24a") if k == ch else (Color(0.8, 0.75, 0.6, 0.5) if k < ch else Color(1, 1, 1, 0.15))
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


## 1.29: номер главы (подшаги "sub" — та же глава, что и шаг перед ними).
func _chapter(i: int) -> int:
	var c := -1
	for k in mini(i + 1, STEPS.size()):
		if not bool((STEPS[k] as Dictionary).get("sub", false)):
			c += 1
	return maxi(c, 0)


func _index_of(id: String) -> int:
	for k in STEPS.size():
		if str((STEPS[k] as Dictionary)["id"]) == id:
			return k
	return -1


## 1.29: открыто ли то, о чём рассказывает подшаг (меню человека, нужное окно).
func _grp_ok(grp: String) -> bool:
	if grp == "person":
		return hud.worker_pop.visible or hud.info.visible
	if grp.begins_with("win:"):
		return hud.win != null and hud.win.group == grp.substr(4)
	return true


## 1.21: новый шаг — убрать то, что осталось открытым, и показать камерой то, о чём речь.
## 1.29: подшаги "keep" (внутри открытого окна или меню) сюда не попадают; свои окна обучение
## не закрывает — на последнем подшаге показывает крестик и ждёт, пока игрок закроет сам.
func _tidy(id: String) -> void:
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
		UITheme.tint_icon(ic, ic.texture, Color("#f0cf7a"))
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
		return
	# 1.29: игрок закрыл окно раньше, чем дослушал, — вернёмся к шагу, где его открывают
	if st.has("grp") and not _grp_ok(str(st["grp"])):
		var bk := _index_of(str(st.get("back", "")))
		if bk >= 0:
			sim.progress.tutorial = bk
			_show()


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
	y = minf(y, vs.y - 96.0 - size.y - 8.0)
	if tr.size != Vector2.ZERO and Rect2(Vector2(x, y), size).intersects(tr.grow(10)):
		# 1.29: сначала — под целью (внутри окна там обычно пусто), потом — справа
		var by := tr.end.y + 34.0
		if by + size.y <= vs.y - 96.0 - 8.0:
			position = Vector2(clampf(tr.get_center().x - size.x * 0.5, 12.0, vs.x - size.x - 70.0), by)
			return
		x = vs.x - size.x - 70.0
	position = Vector2(x, y)


func _target_rect() -> Rect2:
	var t := str(_step().get("target", ""))
	if t == "":
		return Rect2()
	if t.begins_with("btn:"):
		return _rect_of(hud.bottom_btns.get(t.substr(4)))
	if t.begins_with("ov:"):
		return _rect_of(hud.ov_btns.get(t.substr(3)))
	if t.begins_with("win:rail:"):
		return _rect_of(hud.win._rail_btns.get(t.substr(9))) if hud.win else Rect2()
	match t:
		"speed":
			return _rect_of(hud.speed_box)
		"pop", "info":
			# 1.29: меню человека встаёт над ним при щелчке и дальше стоит на месте — рамка просто на нём
			if hud.info.visible:
				return _rect_of(hud.info)
			return _rect_of(hud.worker_pop) if hud.worker_pop.visible else Rect2()
		"pop:ctl":
			if hud.worker_pop.visible:
				return _rect_of(hud.worker_pop._ctl_b)
			return _rect_of(hud.info)
		"pop:card":
			if hud.worker_pop.visible:
				return _rect_of(_find_text(hud.worker_pop, "Открыть карточку"))
			return _rect_of(hud.info)
		"pop:close":
			if hud.worker_pop.visible:
				return _rect_of(_find_text(hud.worker_pop, "×"))
			if hud.info.visible:
				return _rect_of(_find_text(hud.info, "×"))
			return Rect2()
		"win:scroll":
			# 1.29: только то, что реально занято списком, — чтобы панель обучения встала рядом, а не поверх
			if hud.win == null:
				return Rect2()
			var wr := _rect_of(hud.win.scroll)
			var cr := _rect_of(hud.win.content)
			if wr.size != Vector2.ZERO and cr.size.y > 40.0:
				wr.size.y = clampf(cr.end.y - wr.position.y, 40.0, wr.size.y)
			return wr
		"win:rail":
			return _rect_of(hud.win._rail.get_parent()) if hud.win else Rect2()
		"win:close":
			return _rect_of(_find_text(hud.win, "×")) if hud.win else Rect2()
		"legend":
			return _rect_of(hud.legend_panel)
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
			# 1.29: в разделе «Найм» — первая видимая кнопка «Нанять» (или весь список, если её не видно)
			var sr := _rect_of(hud.win.scroll)
			var hb := _rect_of(_find_text(hud.win.content, "Нанять"))
			if hb.size != Vector2.ZERO and sr.encloses(hb):
				return hb
			return sr
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


## 1.29: кнопка с таким текстом (крестик «×», «Нанять»…) — первая видимая по дереву.
func _find_text(n: Node, text: String) -> Control:
	if n == null:
		return null
	for c in n.get_children():
		if c is Button and (c as Button).text == text and (c as Control).is_visible_in_tree():
			return c
		var r := _find_text(c, text)
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
			var p := xf * (w.vpos() * World.T)   # 1.29: плавная позиция отрисовки, а не шаг симуляции
			var z := hud.g.cam.zoom.x
			return Rect2(p - Vector2(14, 34) * z, Vector2(28, 42) * z)
	return Rect2()


func _done(key: String) -> bool:
	match key:
		"cam":
			return hud.g.cam.position.distance_to(_cam0) > 3.0 * World.T or absf(hud.g.cam.zoom.x - _zoom0.x) > 0.2
		"sel_worker":
			return hud.g.tool.sel_kind == "worker" and (hud.worker_pop.visible or hud.info.visible)
		"pop_closed":
			return not hud.worker_pop.visible and not hud.info.visible
		"win_closed":
			return hud.win == null
		"sub_closed":
			return hud.sub_kind == "" and hud.g.tool.mode == "select"
		"ov_off":
			return hud.forced_overlay != "nets"
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
