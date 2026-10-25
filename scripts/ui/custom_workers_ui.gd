class_name CustomWorkersUI
extends PanelContainer
## 1.32: «Создать рабочего» (свои рабочие) — редактор в главном меню. Слева список (добавить, выбрать, включить, удалить)
## и шанс появления; посередине — портрет и человечек, как на карте; справа — ФИО, пол, возраст,
## профессия, внешность (стрелки ◀ ▶) и черты характера. Список — в user://custom_workers.json
## (CustomWorkers); в игре свои рабочие приходят кандидатами (CustomPeople).

signal closed

const DOLL_Z := 2.9          ## масштаб человечка в окошке предпросмотра
const POR_Z := 3.3           ## масштаб большого портрета
const DIRS := ["down", "down", "right", "down", "left", "up"]

var sim: Sim                 ## завод на фоне меню — для человечка (зима, улица)
var data: Dictionary = {}    ## {"chance", "workers"}
var sel := -1                ## какая запись открыта; -1 — новая, ещё не в списке
var cur: Dictionary = {}     ## что сейчас в редакторе (копия записи)
var dirty := false
var dressed := true          ## человечек в спецовке или в своей одежде
var rng := RandomNumberGenerator.new()

var list_box: VBoxContainer
var list_cap: Label
var chance_lbl: Label
var form_scroll: ScrollContainer
var form: VBoxContainer
var por: Portrait
var doll_box: DollBox
var bar_status: Label
var save_btn: Button
var del_btn: Button
var name_edits: Dictionary = {}   ## поле -> LineEdit
var name_errs: Dictionary = {}    ## поле -> Label
var fio_lbl: Label
var sub_lbl: Label
var char_box: VBoxContainer   ## описания выбранных черт — под человечком
## 1.38.1: форма строится один раз (и заново — только при смене пола: другие причёски, борода/серьги, лица);
## остальные кнопки обновляют свои строки на месте (_sync_form), список — тоже на месте (_fill_list).
var _form_built := false
var _syncs: Array[Callable] = []   ## обновить строку ◀ ▶ по текущей записи
var _age_lbl: Label
var _prof_ob: OptionButton
var _trait_title: Label
var _trait_hint: Label
var _trait_flow: HFlowContainer
var _gender_seg: HBoxContainer
var _look_box: VBoxContainer      ## раздел «Внешность»: заголовок и сетка строк


func _init(menu_sim: Sim = null) -> void:
	sim = menu_sim
	rng.randomize()
	data = CustomWorkers.load_data()
	add_theme_stylebox_override("panel", UITheme.sb(Color(0.11, 0.12, 0.135, 0.98), UITheme.LINE, 1, 12, 22, 16))
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 48
	offset_right = -48
	offset_top = 30
	offset_bottom = -30
	_build()
	var ws: Array = data["workers"]
	if ws.is_empty():
		_new_draft()
	else:
		_open(0)


func workers() -> Array:
	return data["workers"]


## 1.38.2: фон меню сменил завод (новый день из снимка) — прежний будет отпущен, человечек переходит на новый.
func set_menu_sim(s: Sim) -> void:
	sim = s
	if doll_box and doll_box.doll and is_instance_valid(doll_box.doll):
		doll_box.doll.sim = s


# ---------------------------------------------------------------- каркас

func _build() -> void:
	var root := UITheme.vbox(12)
	add_child(root)
	var head := UITheme.hbox(12)
	var ic := TextureRect.new()
	ic.texture = UITheme.micon("people")
	ic.custom_minimum_size = Vector2(36, 36)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(ic)
	var hv := UITheme.vbox(0)
	hv.add_child(UITheme.title("Создать рабочего", 26))
	hv.add_child(UITheme.label("Соберите своих людей — ФИО, внешность, черты. В новой игре они могут прийти наниматься: в списке кандидатов отмечены ★.", 13, UITheme.MUTED))
	head.add_child(hv)
	head.add_child(UITheme.spacer())
	var cx := UITheme.button("×", func() -> void: close(), "Закрыть (Esc)")
	cx.custom_minimum_size = Vector2(40, 36)
	cx.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(cx)
	root.add_child(head)
	var cols := UITheme.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	cols.add_child(_build_list())
	cols.add_child(_build_preview())
	var right := UITheme.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll = ScrollContainer.new()
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form = UITheme.vbox(10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.add_child(form)
	right.add_child(form_scroll)
	right.add_child(_build_bar())
	cols.add_child(right)


func _build_list() -> Control:
	var v := UITheme.vbox(8)
	v.custom_minimum_size = Vector2(300, 0)
	list_cap = UITheme.caption("")
	v.add_child(list_cap)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_box = UITheme.vbox(6)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_box)
	v.add_child(sc)
	var add := UITheme.button("+  Новый рабочий", func() -> void: _new_draft(), "Новая запись: случайные имя и внешность — поменяйте как хотите")
	add.custom_minimum_size = Vector2(0, 40)
	v.add_child(add)
	# шанс появления
	var card := UITheme.card(12)
	var cv := UITheme.vbox(4)
	card.add_child(cv)
	var ch := UITheme.hbox(8)
	ch.add_child(UITheme.caption("Шанс появления"))
	ch.add_child(UITheme.spacer())
	chance_lbl = UITheme.label("", 15, UITheme.ACCENT, UITheme.f_semi)
	ch.add_child(chance_lbl)
	cv.add_child(ch)
	var sl := HSlider.new()
	sl.min_value = 5
	sl.max_value = 100
	sl.step = 5
	sl.value = roundf(float(data["chance"]) * 100.0)
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(0, 22)
	sl.value_changed.connect(func(x: float) -> void:
		data["chance"] = x / 100.0
		_chance_text()
		CustomWorkers.save_data(data))
	cv.add_child(sl)
	var hint := UITheme.para("Для каждого включённого, кого ещё нет на заводе, — при каждом обновлении кандидатов (по понедельникам и по объявлению). За раз приходит не больше одного.", 12)
	cv.add_child(hint)
	v.add_child(card)
	_chance_text()
	return v


func _chance_text() -> void:
	chance_lbl.text = "%d%%" % roundi(float(data["chance"]) * 100.0)


func _build_preview() -> Control:
	var v := UITheme.vbox(10)
	v.custom_minimum_size = Vector2(250, 0)
	fio_lbl = UITheme.label("", 17, UITheme.TEXT, UITheme.f_semi)
	fio_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fio_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fio_lbl.custom_minimum_size = Vector2(250, 0)
	por = Portrait.new()
	por.async_load = true
	por.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(por)
	v.add_child(fio_lbl)
	sub_lbl = UITheme.label("", 13, UITheme.MUTED)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub_lbl)
	doll_box = DollBox.new()
	doll_box.custom_minimum_size = Vector2(250, 160)
	v.add_child(doll_box)
	var seg := UITheme.segmented([["work", "В спецовке", "Как на работе: одежда по профессии"], ["own", "Своя одежда", "Как приходит на завод и уходит домой"]], "work" if dressed else "own", func(k: String) -> void:
		dressed = k == "work"
		_preview())
	seg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(seg)
	var rl := UITheme.button("Случайная внешность", func() -> void:
		CustomWorkers.random_look(cur, rng)
		_changed(true), "Перебрать внешность целиком (ФИО и черты останутся)")
	rl.custom_minimum_size = Vector2(0, 38)
	v.add_child(rl)
	char_box = UITheme.vbox(4)
	v.add_child(char_box)
	return v


func _build_bar() -> Control:
	var h := UITheme.hbox(10)
	del_btn = UITheme.button("Удалить", func() -> void: _delete(), "Убрать из списка навсегда")
	del_btn.add_theme_color_override("font_color", UITheme.BAD)
	del_btn.custom_minimum_size = Vector2(110, 44)
	h.add_child(del_btn)
	bar_status = UITheme.label("", 13, UITheme.MUTED)
	bar_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(bar_status)
	save_btn = UITheme.primary("Сохранить", func() -> void: _save())
	save_btn.custom_minimum_size = Vector2(230, 44)
	save_btn.add_theme_font_size_override("font_size", 17)
	h.add_child(save_btn)
	return h


# ---------------------------------------------------------------- список

## 1.38.1: строки списка обновляются на месте — не пересобираются (с портретами) на каждое «Сохранить» и выбор.
func _fill_list() -> void:
	var ws := workers()
	list_cap.text = tr("СПИСОК · %d из %d") % [ws.size(), CustomWorkers.MAX]
	var rows: Array[PanelContainer] = []
	var plain := true
	for c in list_box.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is PanelContainer and c.has_meta("l1"):
			rows.append(c as PanelContainer)
		else:
			plain = false
	var hint := ws.is_empty() and sel >= 0
	if hint or not plain:
		UITheme.clear(list_box)
		rows.clear()
		if hint:
			list_box.add_child(UITheme.para("Пока никого. Нажмите «Новый рабочий».", 13))
			return
	var want := ws.size() + (1 if sel < 0 else 0)
	while rows.size() > want:
		var r: PanelContainer = rows.pop_back()
		list_box.remove_child(r)
		r.queue_free()
	while rows.size() < want:
		var r := _row()
		list_box.add_child(r)
		rows.append(r)
	for i in want:
		_sync_row(rows[i], ws[i] if i < ws.size() else cur, i if i < ws.size() else -1)


## Строка списка: портрет, имя, подпись, «включён». Что в ней — _sync_row (индекс — по месту строки в списке).
func _row() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := UITheme.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var pr := Portrait.new()
	pr.async_load = true
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pr)
	var v := UITheme.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l1 := UITheme.label("", 14, UITheme.TEXT, UITheme.f_semi)
	l1.clip_text = true
	l1.custom_minimum_size = Vector2(150, 0)
	v.add_child(l1)
	var l2 := UITheme.label("", 12, UITheme.MUTED)
	l2.clip_text = true
	l2.custom_minimum_size = Vector2(150, 0)
	v.add_child(l2)
	h.add_child(v)
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "Включён: может прийти в новой игре"
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb.toggled.connect(func(x: bool) -> void:
		var i := p.get_index()
		if i >= workers().size():
			return
		(workers()[i] as Dictionary)["enabled"] = x
		if i == sel:
			cur["enabled"] = x
		CustomWorkers.save_data(data)
		l1.add_theme_color_override("font_color", UITheme.TEXT if x else UITheme.MUTED))
	h.add_child(cb)
	p.set_meta("pr", pr)
	p.set_meta("l1", l1)
	p.set_meta("l2", l2)
	p.set_meta("cb", cb)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var i := p.get_index()
			if i < workers().size() and i != sel:
				_open(i))
	return p


func _sync_row(p: PanelContainer, e: Dictionary, i: int) -> void:
	var on := i == sel
	if not p.has_meta("on") or bool(p.get_meta("on")) != on:
		p.set_meta("on", on)
		p.add_theme_stylebox_override("panel", UITheme.sb(Color(UITheme.ACCENT, 0.12) if on else UITheme.BG2, UITheme.ACCENT if on else UITheme.LINE, 1, 8, 8, 6))
	var lh := e.hash()
	if not p.has_meta("lh") or int(p.get_meta("lh")) != lh:
		p.set_meta("lh", lh)
		var pw := CustomPeople.preview_worker(e)
		(p.get_meta("pr") as Portrait).set_look(pw.look, 0.62, {"age": pw.age, "mood": 60.0})
	var nm := L.name(("%s %s" % [str(e.get("last", "")), str(e.get("first", ""))]).strip_edges())
	var l1 := p.get_meta("l1") as Label
	l1.text = nm if nm != "" else tr("Без имени")
	l1.add_theme_color_override("font_color", UITheme.TEXT if bool(e.get("enabled", true)) else UITheme.MUTED)
	var l2 := p.get_meta("l2") as Label
	l2.text = tr("новый — ещё не в списке") if i < 0 else CustomWorkers.subtitle(e)
	l2.add_theme_color_override("font_color", UITheme.WARN if i < 0 else UITheme.MUTED)
	var cb := p.get_meta("cb") as CheckBox
	cb.visible = i >= 0
	cb.set_pressed_no_signal(bool(e.get("enabled", true)))


## Уйти с записи: правильные правки сохраняем сами, черновик новой записи — отбрасываем.
func _leave() -> void:
	if sel >= 0 and dirty and CustomWorkers.validate(cur).is_empty():
		_commit()


func _open(i: int) -> void:
	_leave()
	sel = i
	cur = (workers()[i] as Dictionary).duplicate(true)
	dirty = false
	_refresh_all()


func _new_draft() -> void:
	if workers().size() >= CustomWorkers.MAX:
		bar_status.text = tr("В списке уже %d — больше нельзя. Удалите кого-нибудь.") % CustomWorkers.MAX
		bar_status.add_theme_color_override("font_color", UITheme.WARN)
		return
	_leave()
	sel = -1
	cur = CustomWorkers.new_entry(rng)
	dirty = true
	_refresh_all()


func _commit() -> void:
	for k in ["last", "first", "patr"]:
		cur[k] = CustomWorkers.nice(str(cur.get(k, "")))
	cur["traits"] = CustomPeople.clean_traits(cur.get("traits", []), int(cur.get("age", 30)))
	if sel < 0:
		workers().append(cur.duplicate(true))
		sel = workers().size() - 1
	else:
		workers()[sel] = cur.duplicate(true)
	CustomWorkers.save_data(data)
	dirty = false


func _save() -> void:
	if not CustomWorkers.validate(cur).is_empty():
		return
	var added := sel < 0
	_commit()
	_refresh_all()
	bar_status.text = tr("Добавлена в список. В новой игре может прийти наниматься." if bool(cur.get("female", false)) else "Добавлен в список. В новой игре может прийти наниматься.") if added else tr("Сохранено.")
	bar_status.add_theme_color_override("font_color", UITheme.GOOD)


func _delete() -> void:
	if sel >= 0:
		workers().remove_at(sel)
		CustomWorkers.save_data(data)
	dirty = false
	if workers().is_empty():
		sel = -1
		_new_draft()
		return
	sel = -2   # чтобы _open не сохранял удалённое
	_open(0)


func close() -> void:
	_leave()
	closed.emit()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# ---------------------------------------------------------------- редактор

func _refresh_all() -> void:
	_fill_list()
	_sync_form()
	_preview()
	_bar()


## Что-то поменяли. full — обновить форму по записи (случайная внешность, ФИО, пол, возраст, черты);
## при наборе текста и стрелках — только подписи.
func _changed(full: bool) -> void:
	dirty = true
	if full:
		_sync_form()
	_preview()
	_bar()
	_list_texts()


func _list_texts() -> void:
	# имя в строке списка — сразу, без пересборки (чтобы поле ввода не теряло фокус)
	var idx := sel if sel >= 0 else workers().size()
	if idx < list_box.get_child_count():
		var row := list_box.get_child(idx)
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() >= 2:
			var nm := L.name(("%s %s" % [str(cur.get("last", "")), str(cur.get("first", ""))]).strip_edges())
			(labels[0] as Label).text = nm if nm != "" else tr("Без имени")
			if sel >= 0:
				(labels[1] as Label).text = CustomWorkers.subtitle(cur)


func _bar() -> void:
	var err := CustomWorkers.validate(cur)
	save_btn.text = "Добавить в список" if sel < 0 else ("Сохранить изменения" if dirty else "Сохранено")
	save_btn.disabled = not err.is_empty() or (sel >= 0 and not dirty)
	del_btn.visible = sel >= 0
	if not err.is_empty():
		bar_status.text = "Проверьте ФИО — ошибки отмечены красным."
		bar_status.add_theme_color_override("font_color", UITheme.BAD)
	elif sel < 0:
		bar_status.text = "Новый рабочий ещё не в списке."
		bar_status.add_theme_color_override("font_color", UITheme.MUTED)
	elif dirty:
		bar_status.text = "Есть несохранённые изменения."
		bar_status.add_theme_color_override("font_color", UITheme.WARN)
	else:
		bar_status.text = ""


func _preview() -> void:
	var pw := CustomPeople.preview_worker(cur)
	pw.mood = 62.0
	por.set_look(pw.look, POR_Z, {"age": pw.age, "mood": 62.0, "doc": true, "dressed": dressed})   # 1.34: одежда — как у человечка
	fio_lbl.text = L.name(CustomWorkers.fio(cur))
	sub_lbl.text = CustomWorkers.subtitle(cur)
	doll_box.show_worker(sim, pw, dressed)


func _section(t: String) -> VBoxContainer:
	var v := UITheme.vbox(8)
	var h := UITheme.hbox(8)
	h.add_child(UITheme.label(t, 17, UITheme.TEXT, UITheme.f_semi))
	var ln := ColorRect.new()
	ln.color = UITheme.LINE
	ln.custom_minimum_size = Vector2(0, 1)
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ln)
	v.add_child(h)
	form.add_child(v)
	return v


## Форма — по текущей записи: пол тот же, что у построенной формы, — обновляем строки на месте, иначе строим заново.
func _sync_form() -> void:
	if not _form_built:
		_fill_form()
		return
	var fem := bool(cur.get("female", false))
	var gb := _gender_seg.get_children()
	(gb[0] as Button).set_pressed_no_signal(not fem)
	(gb[1] as Button).set_pressed_no_signal(fem)
	_norm_look()
	for k: String in name_edits.keys():
		var le: LineEdit = name_edits[k]
		var t := str(cur.get(k, ""))
		if le.text != t:
			le.text = t
	_check_names()
	var age := int(cur.get("age", 30))
	_age_lbl.text = "%d %s" % [age, L.pl(age, "год|года|лет")]
	_select_prof()
	for f: Callable in _syncs:
		f.call()
	_fill_traits()


## Внешность записи: есть face_ovr, форма лица — из своих для пола (старое значение — ближайшее).
func _norm_look() -> void:
	var lk: Dictionary = cur.get("look", {})
	if not lk.has("face_ovr"):
		lk["face_ovr"] = {}
	cur["look"] = lk
	var fo: Dictionary = lk["face_ovr"]
	var fem := bool(cur.get("female", false))
	var heads: Array = PortraitKit.heads(fem) if PortraitKit.available() else People.HEADS
	if fo.has("head") and not heads.has(str(fo["head"])):
		fo["head"] = PortraitKit.head_for(fem, str(fo["head"]))


## Словарь, в котором лежит значение строки: "look" — внешность, "fo" — черты лица (face_ovr).
func _tgt(t: String) -> Dictionary:
	var lk: Dictionary = cur.get("look", {})
	return lk if t == "look" else (lk.get("face_ovr", {}) as Dictionary)


func _select_prof() -> void:
	var cur_prof := str(cur.get("prof", ""))
	var ix := 0
	for i in _prof_ob.item_count:
		if not _prof_ob.is_item_separator(i) and str(_prof_ob.get_item_metadata(i)) == cur_prof:
			ix = i
	if _prof_ob.selected != ix:
		_prof_ob.select(ix)


func _fill_form() -> void:
	var keep := form_scroll.scroll_vertical
	UITheme.clear(form)
	name_edits.clear()
	name_errs.clear()
	_syncs.clear()
	var fem := bool(cur.get("female", false))
	_form_built = true
	# --- ФИО
	var s1 := _section("Фамилия, имя, отчество")
	var nrow := UITheme.hbox(12)
	for f: Array in [["last", "Фамилия", "Иванов"], ["first", "Имя", "Иван"], ["patr", "Отчество", "можно не писать"]]:
		var key := str(f[0])
		var fv := UITheme.vbox(3)
		fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fv.add_child(UITheme.label(str(f[1]), 12, UITheme.MUTED))
		var le := LineEdit.new()
		le.text = str(cur.get(key, ""))
		le.placeholder_text = str(f[2])
		le.max_length = CustomWorkers.NAME_MAX + 4
		le.custom_minimum_size = Vector2(0, 36)
		le.add_theme_font_size_override("font_size", 16)
		le.text_changed.connect(func(t: String) -> void:
			cur[key] = t
			_check_names()
			_changed(false))
		le.text_submitted.connect(func(_t: String) -> void: _tidy_names())
		le.focus_exited.connect(func() -> void: _tidy_names())
		fv.add_child(le)
		var el := UITheme.label("", 12, UITheme.BAD)
		el.custom_minimum_size = Vector2(0, 16)
		fv.add_child(el)
		name_edits[key] = le
		name_errs[key] = el
		nrow.add_child(fv)
	s1.add_child(nrow)
	var rn := UITheme.hbox(10)
	rn.add_child(UITheme.button("Случайное ФИО", func() -> void:
		CustomWorkers.random_name(cur, rng)
		_changed(true), "Подобрать фамилию, имя и отчество"))
	rn.add_child(UITheme.label(tr("Русские буквы и дефис, от %d до %d знаков. Пол меняет окончания: Петров → Петрова.") % [CustomWorkers.NAME_MIN, CustomWorkers.NAME_MAX], 12, UITheme.DIM))
	s1.add_child(rn)
	_check_names()
	# --- основное
	var s2 := _section("Кто это")
	var brow := UITheme.hbox(22)
	var gv := UITheme.vbox(3)
	gv.add_child(UITheme.label("Пол", 12, UITheme.MUTED))
	_gender_seg = UITheme.segmented([["m", "Мужчина"], ["f", "Женщина"]], "f" if fem else "m", func(k: String) -> void:
		if (k == "f") != bool(cur.get("female", false)):
			cur["female"] = k == "f"
			CustomWorkers.regender(cur)
			_regender_face()
			_changed(true))
	gv.add_child(_gender_seg)
	brow.add_child(gv)
	var av := UITheme.vbox(3)
	av.add_child(UITheme.label("Возраст", 12, UITheme.MUTED))
	var age := int(cur.get("age", 30))
	var stp := _stepper("%d %s" % [age, L.pl(age, "год|года|лет")], 90, func(d: int) -> void:
		cur["age"] = clampi(int(cur.get("age", 30)) + d, CustomWorkers.AGE_MIN, CustomWorkers.AGE_MAX)
		cur["traits"] = CustomPeople.clean_traits(cur.get("traits", []), int(cur["age"]))
		_changed(true))
	_age_lbl = stp.get_child(1) as Label
	av.add_child(stp)
	brow.add_child(av)
	var pv := UITheme.vbox(3)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_child(UITheme.label("Профессия", 12, UITheme.MUTED))
	var ob := OptionButton.new()
	_prof_ob = ob
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(260, 34)
	ob.add_item("Любая — по тому, кто нужен заводу")
	ob.set_item_metadata(0, "")
	var cur_prof := str(cur.get("prof", ""))
	for grp: Array in CustomWorkers.prof_groups():
		ob.add_separator(str(grp[0]))
		for pk: String in grp[1]:
			ob.add_item(str(Worker.PROF_NAMES.get(pk, pk)))   # пункты OptionButton переводит сам Godot
			ob.set_item_metadata(ob.item_count - 1, pk)
			if pk == cur_prof:
				ob.select(ob.item_count - 1)
	if cur_prof == "":
		ob.select(0)
	ob.item_selected.connect(func(ix: int) -> void:
		cur["prof"] = str(ob.get_item_metadata(ix))
		_changed(false))
	pv.add_child(ob)
	brow.add_child(pv)
	s2.add_child(brow)
	# --- внешность
	_look_box = _section("Внешность")
	_fill_looks()
	# --- черты
	var s4 := _section("Черты характера")
	_trait_title = (s4.get_child(0) as HBoxContainer).get_child(0) as Label
	_trait_hint = UITheme.label("чтобы выбрать другую — снимите одну", 12, UITheme.DIM)
	(s4.get_child(0) as HBoxContainer).add_child(_trait_hint)
	(s4.get_child(0) as HBoxContainer).move_child(_trait_hint, 1)
	_trait_flow = HFlowContainer.new()
	_trait_flow.add_theme_constant_override("h_separation", 6)
	_trait_flow.add_theme_constant_override("v_separation", 5)
	s4.add_child(_trait_flow)
	_fill_traits()
	(func() -> void: form_scroll.scroll_vertical = keep).call_deferred()


## Строки внешности (◀ ▶): набор вариантов зависит от пола — при смене пола строятся заново только они.
func _fill_looks() -> void:
	for i in range(_look_box.get_child_count() - 1, 0, -1):   # заголовок раздела оставляем
		var c := _look_box.get_child(i)
		_look_box.remove_child(c)
		c.queue_free()
	_syncs.clear()
	_norm_look()
	var g := UITheme.grid(2, 18, 4)
	var bodies := func() -> Array:
		var fm := bool(cur.get("female", false))
		var out: Array = []
		for bk: String in CustomWorkers.BODY_ORDER:
			var bn := str((People.BODIES[bk]["name"] as Array)[1 if fm else 0])
			bn = L.t(bn)
			out.append([bk, bn.left(1).to_upper() + bn.substr(1)])
		return out
	g.add_child(_pick("Телосложение", bodies, "look", "body"))
	g.add_child(_pick("Рост", _zip(CustomWorkers.HEIGHTS, ["Ниже среднего", "Средний", "Выше среднего"]), "look", "h"))
	g.add_child(_pick("Кожа", _zip(range(People.SKINS.size()), CustomWorkers.SKIN_NAMES), "look", "skin", People.SKINS))
	g.add_child(_pick("Причёска", func() -> Array:
		var hs: Array = People.HAIR_F if bool(cur.get("female", false)) else People.HAIR_M
		return hs.map(func(x: String) -> Array: return [x, str(CustomWorkers.HAIR_NAMES.get(x, x))]), "look", "hair"))
	g.add_child(_pick("Цвет волос", _zip(CustomWorkers.HAIR_COLS, CustomWorkers.HAIR_COL_NAMES), "look", "hair_col", CustomWorkers.HAIR_COLS))
	# у женщин — серьги, у мужчин — борода (на одном месте сетки: видна одна из двух строк)
	if People.EARRINGS:   # 1.40: серьги убраны (флаг в People)
		g.add_child(_pick("Серьги", [[false, "Нет"], [true, "Есть"]], "fo", "earrings", [], 1))
	g.add_child(_pick("Борода, усы", CustomWorkers.BEARDS.map(func(x: String) -> Array: return [x, str(CustomWorkers.BEARD_NAMES[x])]), "look", "beard", [], 0))
	# 1.37: в наборе v5 у мужчин 4 формы лица, у женщин 3 — показываем только свои (старое значение — ближайшее)
	g.add_child(_pick("Лицо", func() -> Array:
		var heads: Array = PortraitKit.heads(bool(cur.get("female", false))) if PortraitKit.available() else People.HEADS
		return _named(heads, CustomWorkers.HEAD_NAMES), "fo", "head"))
	g.add_child(_pick("Глаза", _named(People.EYE_KINDS, CustomWorkers.EYE_KIND_NAMES), "fo", "eyes"))
	g.add_child(_pick("Цвет глаз", _zip(People.EYE_COLS, CustomWorkers.EYE_NAMES), "look", "eye_col", People.EYE_COLS))
	g.add_child(_pick("Брови", _named(People.BROW_KINDS, CustomWorkers.BROW_NAMES), "fo", "brows"))
	g.add_child(_pick("Нос", _named(People.NOSE_KINDS, CustomWorkers.NOSE_NAMES), "fo", "nose"))
	g.add_child(_pick("Рот", _named(People.MOUTH_KINDS, CustomWorkers.MOUTH_NAMES), "fo", "mouth"))
	g.add_child(_pick("Очки", [[false, "Нет"], [true, "Есть"]], "look", "glasses"))
	g.add_child(_pick("Веснушки", [[false, "Нет"], [true, "Есть"]], "fo", "freckles"))
	g.add_child(_pick("Своя одежда", [["jacket", "Куртка"], ["coat", "Пальто"]], "look", "street"))
	g.add_child(_pick("Её цвет", _zip(People.STREET_COLS, CustomWorkers.STREET_NAMES), "look", "street_col", People.STREET_COLS))
	_look_box.add_child(g)


## Черты характера: заголовок со счётчиком, кнопки (выбранные — янтарные) и описания под человечком.
func _fill_traits() -> void:
	var tr: Array = cur.get("traits", [])
	_trait_title.text = L.t("Черты характера · %d из %d") % [tr.size(), CustomPeople.MAX_TRAITS]
	_trait_hint.visible = tr.size() >= CustomPeople.MAX_TRAITS
	for c in _trait_flow.get_children():
		_trait_flow.remove_child(c)
		c.queue_free()
	for tk: String in Defs.traits.keys():
		var td: Dictionary = Defs.traits[tk]
		if not bool(td.get("gen", true)):
			continue
		_trait_flow.add_child(_trait_btn(tk, td, tr))
	_fill_char(tr)


## Под человечком — что значат выбранные черты.
func _fill_char(tr: Array) -> void:
	UITheme.clear(char_box)
	char_box.add_child(UITheme.caption("Характер"))
	if tr.is_empty():
		char_box.add_child(UITheme.para("Без черт — обычный человек. Выберите до двух справа; несовместимые (трудоголик и лентяй, жаворонок и сова…) вместе не бывают.", 12, UITheme.DIM))
	for t2: Variant in tr:
		var d2: Dictionary = Defs.traits.get(str(t2), {})
		char_box.add_child(UITheme.label(L.dt("trait.%s.name" % str(t2), str(d2.get("name", t2))), 14, UITheme.ACCENT, UITheme.f_semi))
		char_box.add_child(UITheme.para(L.dt("trait.%s.desc" % str(t2), str(d2.get("desc", ""))), 12, UITheme.TEXT))


## Женщине — женские черты лица по умолчанию не навязываем, но причёска и борода меняются в regender.
func _regender_face() -> void:
	var fo: Dictionary = (cur.get("look", {}) as Dictionary).get("face_ovr", {})
	if not bool(cur.get("female", false)) or not People.EARRINGS:
		fo["earrings"] = false


func _trait_btn(tk: String, td: Dictionary, tr: Array) -> Button:
	var on := tr.has(tk)
	var why := ""
	if not on:
		if tr.size() >= CustomPeople.MAX_TRAITS:
			why = "Уже выбраны две черты — снимите одну"
		elif str(td.get("opp", "")) != "" and tr.has(str(td["opp"])):
			why = L.t("Не сочетается с «%s»") % L.dt("trait.%s.name" % str(td["opp"]), str(Defs.traits[str(td["opp"])]["name"]))
		elif tk == "veteran" and int(cur.get("age", 30)) < 45:
			why = "Только с 45 лет"
	var b: Button
	var cb := func() -> void:
		var t3: Array = cur.get("traits", [])
		if t3.has(tk):
			t3.erase(tk)
		elif why == "":
			t3.append(tk)
		cur["traits"] = t3
		_changed(true)
	var tn := L.dt("trait.%s.name" % tk, str(td["name"]))
	b = UITheme.primary(tn, cb) if on else UITheme.small(tn, cb)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, 29)
	b.disabled = why != ""
	b.tooltip_text = L.dt("trait.%s.desc" % tk, str(td.get("desc", ""))) + (("\n" + L.t(why)) if why != "" else "")
	return b


static func _zip(vals: Array, names: Array) -> Array:
	var out: Array = []
	for i in vals.size():
		out.append([vals[i], str(names[i]) if i < names.size() else str(vals[i])])
	return out


static func _named(keys: Array, names: Dictionary) -> Array:
	return keys.map(func(k: String) -> Array: return [k, str(names.get(k, k))])


## Строка выбора: подпись, ◀ значение ▶ (по кругу). swatches — цвета образцов для значений.
## 1.38.1: src — варианты или функция, что их даёт (зависят от пола: телосложение, причёска, лицо);
## only — строка только для мужчин (0) или женщин (1): при смене пола строка прячется, форма не пересобирается.
func _pick(title: String, src: Variant, tgt: String, key: String, swatches: Array = [], only: int = -1) -> Control:
	var opts: Array = (src as Callable).call() if src is Callable else src
	var h := UITheme.hbox(6)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tl := UITheme.label(title, 13, UITheme.MUTED)
	tl.custom_minimum_size = Vector2(112, 0)
	h.add_child(tl)
	var ci := _opt_index(opts, _tgt(tgt).get(key, null))
	# 1.35: стрелка меняет только свою строку — без пересборки всей формы (≈30 мс и сотни узлов на щелчок)
	var st := {"ci": ci, "opts": opts}
	var sw: ColorRect = ColorRect.new() if not swatches.is_empty() else null   # (лямбда захватывает значения — создаём заранее)
	var vl := UITheme.label(str(opts[ci][1]), 14, UITheme.TEXT)
	var pos := UITheme.label("%d/%d" % [ci + 1, opts.size()], 11, UITheme.DIM)
	var step := func(d: int) -> void:
		var op: Array = st["opts"]
		var ni := posmod(int(st["ci"]) + d, op.size())
		st["ci"] = ni
		_tgt(tgt)[key] = op[ni][0]
		vl.text = str(op[ni][1])
		pos.text = "%d/%d" % [ni + 1, op.size()]
		if sw:
			sw.color = Color(str(swatches[ni % swatches.size()]))
		_changed(false)
	# 1.38.1: та же строка — по записи (случайная внешность, выбор в списке)
	_syncs.append(func() -> void:
		var fem := bool(cur.get("female", false))
		h.visible = only < 0 or (only == 1) == fem
		var op: Array = (src as Callable).call() if src is Callable else st["opts"]
		st["opts"] = op
		var ni := _opt_index(op, _tgt(tgt).get(key, null))
		st["ci"] = ni
		vl.text = str(op[ni][1])
		pos.text = "%d/%d" % [ni + 1, op.size()]
		if sw:
			sw.color = Color(str(swatches[ni % swatches.size()])))
	h.visible = only < 0 or (only == 1) == bool(cur.get("female", false))
	var lb := UITheme.small("◀", func() -> void: step.call(-1))
	lb.custom_minimum_size = Vector2(30, 30)
	h.add_child(lb)
	var mid := PanelContainer.new()
	mid.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG3, UITheme.LINE, 1, 6, 8, 3))
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mh := UITheme.hbox(8)
	mid.add_child(mh)
	if sw:
		sw.color = Color(str(swatches[ci % swatches.size()]))
		sw.custom_minimum_size = Vector2(16, 16)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mh.add_child(sw)
	vl.clip_text = true
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.custom_minimum_size = Vector2(80, 0)
	mh.add_child(vl)
	mh.add_child(pos)
	h.add_child(mid)
	var rb := UITheme.small("▶", func() -> void: step.call(1))
	rb.custom_minimum_size = Vector2(30, 30)
	h.add_child(rb)
	return h


static func _opt_index(opts: Array, have: Variant) -> int:
	var ci := 0
	for i in opts.size():
		var ov: Variant = opts[i][0]
		if have != null and (str(ov) == str(have) or (ov is float and (have is float or have is int) and absf(float(ov) - float(have)) < 0.02)):
			ci = i
	return ci


func _stepper(text: String, w: float, cb: Callable) -> Control:
	var h := UITheme.hbox(6)
	var lb := UITheme.small("◀", func() -> void: cb.call(-1))
	lb.custom_minimum_size = Vector2(30, 32)
	h.add_child(lb)
	var l := UITheme.label(text, 15, UITheme.TEXT, UITheme.f_semi)
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(l)
	var rb := UITheme.small("▶", func() -> void: cb.call(1))
	rb.custom_minimum_size = Vector2(30, 32)
	h.add_child(rb)
	return h


func _check_names() -> void:
	var err := CustomWorkers.validate(cur)
	for k: String in name_errs.keys():
		(name_errs[k] as Label).text = str(err.get(k, ""))
		var le: LineEdit = name_edits[k]
		if err.has(k):
			le.add_theme_stylebox_override("normal", UITheme.sb(UITheme.BG3, UITheme.BAD, 1, 6, 10, 4))
		else:
			le.remove_theme_stylebox_override("normal")


## Поле ввода потеряло фокус: «иванов» → «Иванов».
func _tidy_names() -> void:
	for k: String in name_edits.keys():
		var le: LineEdit = name_edits[k]
		var t := str(cur.get(k, ""))
		if t.strip_edges() == "" or CustomWorkers.check_part(t, false) != "":
			continue
		var n := CustomWorkers.nice(t)
		if n != t:
			cur[k] = n
			le.text = n
			_changed(false)


# ---------------------------------------------------------------- человечек

## Окошко с человечком, как на карте: стоит на бетонном полу и поворачивается.
class DollBox:
	extends Control
	var holder := Node2D.new()
	var doll: PreviewDoll = null

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		holder.scale = Vector2(DOLL_Z, DOLL_Z)

	func show_worker(s: Sim, w: Worker, dressed: bool) -> void:
		if doll:
			doll.queue_free()
			doll = null
		if s == null:
			return
		w.id = -9132
		w.pos = Vector2.ZERO
		w.vprev = Vector2.ZERO
		w.present = true
		w.dressed = dressed
		w.anim = "idle"
		doll = PreviewDoll.new()
		holder.add_child(doll)
		doll.setup(s, w)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			holder.position = Vector2(size.x * 0.5, size.y * 0.8)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#6d6f6b"))
		var t := 24.0
		var x := fmod(size.x * 0.5, t) - t
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.08), 1.0)
			x += t
		var y := fmod(size.y * 0.8, t) - t
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.08), 1.0)
			y += t
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.LINE2, false, 1.0)


## Кукла рабочего без симуляции: стоит на месте, медленно поворачивается.
class PreviewDoll:
	extends WorkerView
	var turn := 0.0

	func _process(delta: float) -> void:
		_t += delta
		turn += minf(delta, 0.1)
		position = Vector2.ZERO
		var d: String = DIRS[int(turn / 1.5) % DIRS.size()]
		if d != _dir or worker.dressed != _dressed or _tex_rev != Tex.people_rev:
			_rebuild(d)
		_animate()
