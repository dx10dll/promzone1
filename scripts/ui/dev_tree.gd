class_name DevTree
extends RefCounted
## Окно «Развитие» деревом (1.11): сверху кабинет директора, от него — ветки по три ступени
## сверху вниз. Открытый путь подсвечен, щелчок по ступени показывает подробности и кнопку
## под деревом. У «Техотдела» внизу — разработки технолога.

static var sel := ""   ## выбранная ступень; "root" — кабинет директора

const NODE_H := 78.0
const GAP_Y := 26.0
const TOP_NODES := 138.0


## Холст дерева: раскладывает узлы по ширине и рисует линии под ними.
class TreeView extends Control:
	var dv: Develop
	var root_n: Control
	var heads: Array = []      # заголовки веток
	var cols: Array = []       # [[узел1, узел2, узел3], ...]
	var ids: Array = []        # [[id1, id2, id3], ...]

	func _ready() -> void:
		resized.connect(_layout)
		_layout()

	func _layout() -> void:
		var w := size.x
		if w < 100.0:
			return
		var n := cols.size()
		var gap := 8.0
		var cw := (w - gap * float(n - 1)) / float(n)
		root_n.position = Vector2(w * 0.5 - 150.0, 0.0)
		root_n.size = Vector2(300.0, 58.0)
		for i in n:
			var x := float(i) * (cw + gap)
			var h: Control = heads[i]
			h.position = Vector2(x, 86.0)
			h.size = Vector2(cw, 44.0)
			for j in (cols[i] as Array).size():
				var nd: Control = cols[i][j]
				nd.position = Vector2(x, TOP_NODES + float(j) * (NODE_H + GAP_Y))
				nd.size = Vector2(cw, NODE_H)
		queue_redraw()

	func _col(st: String) -> Color:
		match st:
			"works":
				return UITheme.GOOD
			"busy":
				return UITheme.ACCENT
			"idle":
				return UITheme.WARN
			"ready":
				return Color("#7f9bb4")
		return UITheme.LINE

	func _draw() -> void:
		var w := size.x
		var n := cols.size()
		if n == 0 or w < 100.0:
			return
		var gap := 8.0
		var cw := (w - gap * float(n - 1)) / float(n)
		var rc := UITheme.ACCENT if dv.root_ok() else UITheme.LINE
		draw_line(Vector2(w * 0.5, 58.0), Vector2(w * 0.5, 74.0), rc, 2.0, true)
		draw_line(Vector2(cw * 0.5, 74.0), Vector2(w - cw * 0.5, 74.0), rc, 2.0, true)
		for i in n:
			var cx := float(i) * (cw + gap) + cw * 0.5
			draw_line(Vector2(cx, 74.0), Vector2(cx, 86.0), rc, 2.0, true)
			var prev_y := 130.0
			for j in (ids[i] as Array).size():
				var st := dv.status(str(ids[i][j]))
				var col := _col(st)
				var top := TOP_NODES + float(j) * (NODE_H + GAP_Y)
				draw_line(Vector2(cx, prev_y), Vector2(cx, top), col, 3.0 if st == "works" else 2.0, true)
				# стрелка вниз
				draw_colored_polygon(PackedVector2Array([Vector2(cx - 4.0, top - 6.0), Vector2(cx + 4.0, top - 6.0), Vector2(cx, top)]), col)
				prev_y = top + NODE_H


static func build(win: GameWindow) -> void:
	var sim := win.sim
	var dv := sim.dev
	if sel == "" or (sel != "root" and Develop.step_def(sel).is_empty()):
		var nr := dv.next_ready()
		sel = dv.cur if dv.cur != "" else (nr if nr != "" else "root")
	var working := 0
	for d0 in Defs.departments.keys():
		if sim.office.eff(str(d0)) > 0.0:
			working += 1
	win._info(L.t("открыто ступеней: %d из %d · работают %d из %d отделов") % [dv.count_on(), Develop.all_ids().size(), working, Defs.departments.size()])
	win._intro(L.t("Первую ступень ветки открывает найм специалиста. Остальные директор исследует из своего кабинета — по одной, за деньги и время. Этап разрешает ступень, а не дарит её; ступень держат люди. Щёлкните по ступени — внизу подробности."))
	var tv := TreeView.new()
	tv.dv = dv
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.custom_minimum_size = Vector2(0, TOP_NODES + 3.0 * NODE_H + 2.0 * GAP_Y + 4.0)
	tv.root_n = _root_node(win)
	tv.add_child(tv.root_n)
	for br: Dictionary in Develop.branches():
		var hv := VBoxContainer.new()
		hv.alignment = BoxContainer.ALIGNMENT_CENTER
		hv.add_theme_constant_override("separation", 1)
		var ic := win._icon(Tex.ui(str(br.get("icon", "office"))), 20)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hv.add_child(ic)
		var nl := UITheme.label(L.t(str(br["name"])), 12, UITheme.TEXT, UITheme.f_semi)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hv.add_child(nl)
		tv.heads.append(hv)
		tv.add_child(hv)
		var col: Array = []
		var cid: Array = []
		var steps: Array = br["steps"]
		for i in steps.size():
			var id := str(steps[i]["id"])
			var nd := _node(win, id, i + 1)
			col.append(nd)
			cid.append(id)
			tv.add_child(nd)
		tv.cols.append(col)
		tv.ids.append(cid)
	win.content.add_child(_orders(win))
	win.content.add_child(tv)
	win.content.add_child(_details(win))
	if sel.begins_with("tech"):
		win.content.add_child(win._dev_research())


## 1.19: приказы директора (были во вкладке «Отделы и политики», которая повторяла это дерево).
static func _orders(win: GameWindow) -> PanelContainer:
	var sim := win.sim
	var c := UITheme.card(8, Color("#1a1e22"), UITheme.LINE)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UITheme.hbox(14)
	c.add_child(h)
	h.add_child(UITheme.label(L.t("Приказы директора"), 13, UITheme.TEXT, UITheme.f_semi))
	var ch_on := sim.office.eff("chief") > 0.0
	var a := win._policy("rush", "Аврал: +25% к скорости, брака больше", ch_on)
	var b := win._policy("overtime", "Сверхурочные: +2 часа за полуторную оплату", ch_on)
	for cb: CheckBox in [a, b]:
		if not ch_on:
			cb.text = cb.text.replace(L.t(" (нужен отдел)"), "").replace(" (нужен отдел)", "")
			cb.tooltip_text = L.t("Нужен начальник цеха (ветка «Производство»)")
		h.add_child(cb)
	var hr := win._policy("auto_hire", "Автонайм замены", sim.dev.on("hr3"))
	hr.text = L.t("Кадровик сам нанимает замену")
	hr.tooltip_text = L.t("Уволился человек — кадровик сам найдёт такого же") if sim.dev.on("hr3") else L.t("Нужна ступень «Кадровый резерв» (ветка «Кадры»)")
	h.add_child(hr)
	return c


## Стиль узла: фон и рамка по состоянию, толще — у выбранного.
static func _style(st: String, chosen: bool) -> Array:
	var bg := {"works": Color("#1f2a22"), "idle": Color("#2a2619"), "busy": Color("#2c261a"), "ready": Color("#202831"), "locked": Color("#1a1c20")}
	var bd := {"works": Color("#4f7a4a"), "idle": Color("#8a7430"), "busy": UITheme.ACCENT, "ready": Color("#6a86a0"), "locked": UITheme.LINE}
	var b: Color = bd.get(st, UITheme.LINE)
	var f: Color = bg.get(st, UITheme.BG2)
	return [UITheme.sb(f, UITheme.ACCENT if chosen else b, 3 if chosen else 1, 7, 6, 4),
		UITheme.sb(f.lightened(0.06), UITheme.ACCENT if chosen else b.lightened(0.2), 3 if chosen else 1, 7, 6, 4)]


static func _btn(st: String, chosen: bool, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var sts := _style(st, chosen)
	b.add_theme_stylebox_override("normal", sts[0])
	b.add_theme_stylebox_override("pressed", sts[0])
	b.add_theme_stylebox_override("hover", sts[1])
	b.add_theme_stylebox_override("hover_pressed", sts[1])
	b.pressed.connect(cb)
	return b


static func _inner(b: Button) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 7
	v.offset_right = -6
	v.offset_top = 5
	v.offset_bottom = -4
	b.add_child(v)
	return v


static func _lab(text: String, size: int, col: Color, font: Font = null, wrap: bool = false) -> Label:
	var l := UITheme.label(text, size, col, font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.max_lines_visible = 2
	else:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


static func _root_node(win: GameWindow) -> Button:
	var dv := win.sim.dev
	var st := "works" if dv.root_ok() else "locked"
	if dv.cur != "":
		st = "busy"
	var b := _btn(st, sel == "root", L.t("Кабинет директора: отсюда исследуются ступени"), func() -> void:
		sel = "root"
		win.rebuild(true))
	var v := _inner(b)
	var hh := HBoxContainer.new()
	hh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_theme_constant_override("separation", 8)
	var ic := win._icon(Tex.ui("develop"), 22)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_child(ic)
	var rl := _lab(L.t("Кабинет директора"), 14, UITheme.TEXT, UITheme.f_semi)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(rl)
	v.add_child(hh)
	if dv.cur != "":
		v.add_child(_lab(L.t("занят: «%s» · %.1f дн.") % [L.t(str(Develop.step_def(dv.cur)["name"])), dv.days_left()], 12, UITheme.ACCENT))
	elif dv.root_ok():
		v.add_child(_lab(L.t("✓ свободен — можно исследовать"), 12, UITheme.GOOD))
	else:
		v.add_child(_lab(L.t("нет кабинета — ступени не исследуются"), 12, UITheme.WARN))
	return b


static func _node(win: GameWindow, id: String, _n: int) -> Button:
	var sim := win.sim
	var dv := sim.dev
	var sd := Develop.step_def(id)
	var st := dv.status(id)
	var b := _btn(st, sel == id, L.t(str(sd.get("desc", ""))), func() -> void:
		sel = id
		win.rebuild(true))
	var v := _inner(b)
	var nm := L.t(str(sd["name"]))
	v.add_child(_lab(nm, 12 if nm.length() <= 12 else (11 if nm.length() <= 14 else 10), UITheme.TEXT if st != "locked" else UITheme.MUTED, UITheme.f_semi, true))
	var sp := Control.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var txt := ""
	var col := UITheme.MUTED
	if sd.has("dept"):
		var d := str(sd["dept"])
		if st == "works":
			txt = L.t("✓ работает")
			col = UITheme.GOOD
		elif not sim.progress.dept_open(d):
			txt = L.t("этап «%s»") % sim.progress.stage_name(int(Defs.departments.get(d, {}).get("stage", 1)))
			col = UITheme.DIM
		else:
			txt = L.t("нанять: %s") % Worker.lc(L.t(str(Worker.PROF_NAMES.get(str(Defs.departments[d]["prof"]), ""))))
			col = Color("#9ab4cc")
	else:
		match st:
			"works":
				txt = L.t("✓ работает")
				col = UITheme.GOOD
			"idle":
				txt = L.t("нет человека")
				col = UITheme.WARN
			"busy":
				txt = L.t("идёт · %.1f дн.") % dv.days_left()
				col = UITheme.ACCENT
			"ready":
				txt = L.t("%d тыс. · %d дн.") % [int(dv.cost_of(id) / 1000.0), int(sd.get("days", 1))]
				col = Color("#9ab4cc")
			_:
				txt = (L.t("%d тыс. · %d дн.") % [int(dv.cost_of(id) / 1000.0), int(sd.get("days", 1))]) if not (Develop.is_lot_step(id) and int(sd["lot"]) >= sim.world.lots.size()) else L.t("нет на карте")
				col = UITheme.DIM
	v.add_child(_lab(txt, 11, col, null, true))
	if st == "busy":
		var pb := UITheme.bar(dv.progress01() * 100.0, UITheme.ACCENT, 60, 4)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(pb)
	if id == "tech1":
		b.tooltip_text += L.t("\nРазработки технолога: изучено %d из %d — выберите ступень, они внизу.") % [sim.office.research_done.size(), Defs.research.size()]
	return b


## Подробности выбранной ступени: что даёт, что нужно, кнопка действия.
static func _details(win: GameWindow) -> PanelContainer:
	var sim := win.sim
	var dv := sim.dev
	var c := UITheme.card(14, UITheme.BG2, UITheme.LINE)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.vbox(6)
	c.add_child(v)
	if sel == "root":
		v.add_child(UITheme.label(L.t("Кабинет директора"), 17, UITheme.TEXT, UITheme.f_semi))
		v.add_child(UITheme.para(L.t("Корень дерева. Директор исследует ступени по одной: деньги списываются сразу, ступень открывается через несколько дней. Кабинет — комната с линолеумом, столом директора (Объекты → Офис), назначенная «Кабинетом директора»."), 13))
		if dv.root_ok():
			v.add_child(win._cl(L.t("✓ кабинет есть"), 13, UITheme.GOOD))
		else:
			v.add_child(UITheme.primary(L.t("Построить кабинет директора"), func() -> void:
				win.closed.emit()
				win.hud.open_rooms_type(Develop.ROOT_ROOM), L.t("Откроется каталог помещений с этим типом")))
		if dv.cur != "":
			var hh := UITheme.hbox(8)
			hh.add_child(win._cl(L.t("Сейчас: «%s» — осталось %.1f дн.") % [L.t(str(Develop.step_def(dv.cur)["name"])), dv.days_left()], 13, UITheme.ACCENT))
			hh.add_child(UITheme.spacer())
			hh.add_child(UITheme.small(L.t("Отложить (вернут половину)"), func() -> void:
				dv.cancel()
				win.rebuild(true)))
			v.add_child(hh)
		return c
	var sd := Develop.step_def(sel)
	var st := dv.status(sel)
	var br := Develop.branch_of(sel)
	var steps: Array = br.get("steps", [])
	var num := 1
	for i in steps.size():
		if str(steps[i]["id"]) == sel:
			num = i + 1
	var th := UITheme.hbox(10)
	th.add_child(win._icon(Tex.ui(str(br.get("icon", "office"))), 28))
	var tv := UITheme.vbox(0)
	tv.add_child(UITheme.label(L.t("«%s»") % L.t(str(sd["name"])), 17, UITheme.TEXT, UITheme.f_semi))
	var sub := L.t("ветка «%s» · ступень %d") % [L.t(str(br.get("name", ""))), num]
	if not sd.has("dept"):
		sub += " · %s · %d %s" % [Defs.money_str(dv.cost_of(sel)), int(sd.get("days", 1)), Defs.plural(int(sd.get("days", 1)), "день", "дня", "дней")]
	tv.add_child(UITheme.label(sub, 12, UITheme.MUTED))
	th.add_child(tv)
	th.add_child(UITheme.spacer())
	var chips := {"works": ["работает", UITheme.GOOD], "idle": ["открыто, не работает", UITheme.WARN], "busy": ["исследуется", UITheme.ACCENT], "ready": ["можно начать", UITheme.INFO], "locked": ["закрыто", UITheme.MUTED]}
	th.add_child(UITheme.chip(L.t(str(chips[st][0])), chips[st][1]))
	v.add_child(th)
	v.add_child(UITheme.para(L.t(str(sd.get("desc", ""))), 13, UITheme.TEXT))
	# что нужно
	var req := UITheme.vbox(2)
	v.add_child(req)
	if sd.has("dept"):
		var d := str(sd["dept"])
		var dd: Dictionary = Defs.departments.get(d, {})
		var prof := str(dd.get("prof", ""))
		_req(req, sim.progress.dept_open(d), L.t("этап «%s»") % sim.progress.stage_name(int(dd.get("stage", 1))))
		var rs := sim.office.room_status(d)
		_req(req, int(rs[0]) >= 0, L.t("кабинет: %s") % str(rs[1]).trim_prefix("✓ ").trim_prefix("× "))
		var staff := sim.office.staff(d)
		_req(req, not staff.is_empty(), (L.t("специалист: %s") % staff[0].full_name()) if not staff.is_empty() else L.t("специалист: %s") % Worker.lc(L.t(str(Worker.PROF_NAMES.get(prof, prof)))))
		if st != "works" and sim.progress.dept_open(d):
			var row := UITheme.hbox(8)
			if staff.is_empty():
				row.add_child(UITheme.primary(L.t("Найти: %s · %s") % [Worker.lc(L.t(str(Worker.PROF_NAMES.get(prof, prof)))), Defs.money_str(sim.ad_price(prof))], func() -> void:
					var err := sim.post_ad(prof)
					if err != "":
						win.hud.toast(err, Sim.LVL_WARN)
						return
					win.hud.open_window("staff")
					if win.hud.win:
						win.hud.win.select_tab("hire"), L.t("Объявление по профессии — откроется найм")))
			if int(rs[0]) < 1:
				var room := str(dd.get("room", ""))
				row.add_child(UITheme.button(L.t("Построить кабинет"), func() -> void:
					win.closed.emit()
					win.hud.open_rooms_type(room), L.t("Откроется каталог помещений с этим типом")))
			v.add_child(row)
		return c
	var stg := int(sd.get("stage", 1))
	if stg > 1:
		_req(req, sim.progress.stage >= stg or sim.progress.all_open, L.t("этап «%s»") % sim.progress.stage_name(stg))
	var pv := Develop.prev_of(sel)
	if pv != "":
		_req(req, dv.on(pv), L.t("предыдущая ступень «%s» работает") % L.t(str(Develop.step_def(pv)["name"])))
	var holder := str(sd.get("holder", ""))
	if holder != "":
		_req(req, sim.office.active(holder), L.t("отдел «%s» работает — он держит ступень") % L.t(str(Defs.departments.get(holder, {}).get("name", holder))))
		if bool(sd.get("own_room", false)):
			var room2 := str(Defs.departments.get(holder, {}).get("room", ""))
			_req(req, int(sim.office.room_status(holder)[0]) == 1, L.t("свой кабинет «%s» (общей конторы мало)") % L.t(str(Defs.rooms.get(room2, {}).get("name", room2))))
	if int(sd.get("staff", 0)) > 0:
		_req(req, sim.workers.size() >= int(sd["staff"]), L.t("%d человек в штате") % int(sd["staff"]))
	if Develop.is_lot_step(sel):
		var k := int(sd["lot"])
		if k < sim.world.lots.size():
			var lr := sim.world.lot_rect(k)
			_req(req, true, L.t("участок %s: %d×%d клеток") % [L.t(sim.world.lot_side(k)), lr.size.x, lr.size.y])
		else:
			_req(req, false, L.t("на этой карте такого участка нет"))
	_req(req, dv.root_ok(), L.t("кабинет директора"))
	if st != "works" and st != "idle":
		_req(req, dv.cur == "" or dv.cur == sel, L.t("директор свободен") + (L.t(" (занят: «%s»)") % L.t(str(Develop.step_def(dv.cur)["name"])) if dv.cur != "" and dv.cur != sel else ""))
		_req(req, sim.money >= dv.cost_of(sel) or dv.cur == sel, L.t("деньги: %s") % Defs.money_str(dv.cost_of(sel)))
	var row2 := UITheme.hbox(8)
	match st:
		"ready":
			row2.add_child(UITheme.primary(L.t("Купить · %s · %d %s" if Develop.is_lot_step(sel) else "Начать · %s · %d %s") % [Defs.money_str(dv.cost_of(sel)), int(sd.get("days", 1)), Defs.plural(int(sd.get("days", 1)), "день", "дня", "дней")], func() -> void:
				var err2 := dv.start(sel)
				if err2 != "":
					win.hud.toast(err2, Sim.LVL_WARN)
				win.rebuild(true), L.t("Деньги спишутся сразу")))
		"busy":
			var pb := UITheme.bar(dv.progress01() * 100.0, UITheme.ACCENT, 260, 8)
			row2.add_child(pb)
			row2.add_child(win._cl(L.t("осталось %.1f дн.") % dv.days_left(), 13, UITheme.ACCENT))
			row2.add_child(UITheme.small(L.t("Отложить (вернут половину)"), func() -> void:
				dv.cancel()
				win.rebuild(true)))
		"idle":
			row2.add_child(win._cl(L.t("Ступень открыта, но не работает, пока в отделе «%s» нет человека.") % L.t(str(Defs.departments.get(holder, {}).get("name", holder))), 13, UITheme.WARN))
		"locked":
			if not dv.root_ok():
				row2.add_child(UITheme.button(L.t("Построить кабинет директора"), func() -> void:
					win.closed.emit()
					win.hud.open_rooms_type(Develop.ROOT_ROOM)))
	if row2.get_child_count() > 0:
		v.add_child(row2)
	return c


static func _req(host: Control, ok: bool, text: String) -> void:
	var h := UITheme.hbox(6)
	h.add_child(UITheme.label("✓" if ok else "×", 13, UITheme.GOOD if ok else UITheme.BAD, UITheme.f_semi))
	h.add_child(UITheme.label(L.t(text), 13, UITheme.TEXT if ok else UITheme.MUTED))
	host.add_child(h)
