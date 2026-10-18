class_name CrewUI
extends RefCounted
## Разделы «Люди → Бригады / График смены / Охрана / Профсоюз» (1.7, оформление 1.7.5).
## Плюс карточка «Акты Н-1» для раздела «Охрана труда».

static var brush := "lunch"
static var sched_key := "0"
static var kd_pick: Dictionary = {}


static func tabs() -> Array:
	return [["brig", "Бригады"], ["sched", "График смены"], ["sec", "Охрана"], ["union", "Профсоюз"]]


static func sig(win: GameWindow) -> String:
	var sim := win.sim
	var cr := sim.crew
	var parts: Array[String] = [win.tab, brush, sched_key, str(kd_pick), str(cr.scheds), str(cr.brigades), str(cr.comp), str(cr.pennant),
		str(cr.comp_on), str(cr.comp_prize), str(cr.union), str(cr.caught_total), str(cr.missing.size()), str(cr.history.size()),
		str(sim.story.guard), str(sim.rooms.list.size()), str(sim.thing_rev), str(int(sim.minute / 30.0))]
	for w in sim.workers:
		parts.append("%d:%d:%d:%s:%d" % [w.id, w.brigade, w.shift, str(w.present), int(w.mood / 10.0)])
	return ",".join(parts)


static func build(win: GameWindow) -> void:
	match win.tab:
		"brig":
			_brigades(win)
		"sched":
			_schedule(win)
		"sec":
			_security(win)
		"union":
			_union(win)


static func _check(text: String, on: bool, cb: Callable, tip: String = "", disabled: bool = false) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.button_pressed = on
	c.disabled = disabled
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v: bool) -> void: cb.call(v))
	return c


# ---------------------------------------------------------------- бригады

static func _brigades(win: GameWindow) -> void:
	var sim := win.sim
	var cr := sim.crew
	var free: Array[Worker] = []
	for w in sim.workers:
		if not w.is_itr() and w.brigade < 0:
			free.append(w)
	win._info("бригад %d из %d · без бригады %d чел." % [cr.brigades.size(), Crew.MAX_BRIG, free.size()])
	win._intro("Бригадир получает +10% к ставке и ускоряет свою бригаду на 3–6% (если работает в ту же смену). Люди берут работу в первую очередь на станках своего участка — меньше беготни по заводу. Дружная бригада работает веселее, склочник в бригаде портит всем настроение.")
	win._hbtn("Сформировать автоматически", func() -> void:
		var err := cr.auto_form()
		if err != "":
			win.hud.toast(err, Sim.LVL_WARN)
		win.rebuild(true), "Бригада на каждый цех со станками: люди — к своим станкам, бригадир — самый опытный. Текущие бригады будут расформированы.", cr.brigades.is_empty())
	var nb := win._hbtn("Новая бригада", func() -> void:
		cr.add_brigade()
		win.rebuild(true), "Пустая бригада: добавьте людей, бригадира и участок")
	nb.disabled = cr.brigades.size() >= Crew.MAX_BRIG
	# соцсоревнование — одной строкой
	var comp := UITheme.card(10)
	win.content.add_child(comp)
	var ch := UITheme.hbox(14)
	comp.add_child(ch)
	ch.add_child(_check("Соцсоревнование", cr.comp_on, func(v: bool) -> void:
		cr.comp_on = v
		win.rebuild(true), "По пятницам бригада с наибольшим числом операций на человека получает вымпел: +6 к настроению и +3% к скорости на неделю"))
	ch.add_child(_check("Премия победителям %s" % Defs.money_str(Crew.PRIZE), cr.comp_prize, func(v: bool) -> void:
		cr.comp_prize = v
		win.rebuild(true), "Каждому в бригаде-победителе", not cr.comp_on))
	ch.add_child(UITheme.spacer())
	if cr.comp_on and cr.brigades.size() >= 2:
		for b: Dictionary in cr.brigades:
			var n := cr.members(int(b["id"])).size()
			var ops := int(cr.comp.get(str(b["id"]), 0))
			var lead := cr.pennant == int(b["id"])
			ch.add_child(UITheme.chip("%s%s · %.1f" % ["★ " if lead else "", str(b["name"]), float(ops) / maxf(1.0, float(n))], cr.color(int(b["id"])).lightened(0.2), "%d операций за неделю, %.1f на человека%s" % [ops, float(ops) / maxf(1.0, float(n)), " · вымпел сейчас у них" if lead else ""]))
	elif cr.comp_on:
		ch.add_child(UITheme.label("нужно две бригады и больше", 12, UITheme.MUTED))
	if cr.brigades.is_empty():
		win.content.add_child(UITheme.empty("Бригад пока нет. «Сформировать автоматически» соберёт бригаду на каждый цех со станками — или создайте вручную."))
	else:
		var g := win._cards(2)
		for b2: Dictionary in cr.brigades:
			_brigade_card(win, b2, g)
	if not free.is_empty():
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 6)
		fl.add_theme_constant_override("v_separation", 4)
		fl.add_child(UITheme.caption("Без бригады"))
		for w2 in free:
			fl.add_child(UITheme.chip(w2.call_name(), UITheme.MUTED, "%s, %s" % [w2.full_name(), w2.prof_lc()]))
		win.content.add_child(fl)


static func _brigade_card(win: GameWindow, b: Dictionary, parent: Control) -> void:
	var sim := win.sim
	var cr := sim.crew
	var bid := int(b["id"])
	var ms := cr.members(bid)
	var col := cr.color(bid)
	var card := UITheme.card(12, UITheme.BG2, Color(col.r, col.g, col.b, 0.55))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var v := UITheme.vbox(7)
	card.add_child(v)
	# заголовок
	var h := UITheme.hbox(8)
	var sw := ColorRect.new()
	sw.color = col
	sw.custom_minimum_size = Vector2(6, 26)
	h.add_child(sw)
	var name_e := LineEdit.new()
	name_e.text = str(b["name"])
	name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_e.add_theme_font_override("font", UITheme.f_semi)
	name_e.add_theme_stylebox_override("normal", UITheme.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 4, 2))
	name_e.add_theme_stylebox_override("focus", UITheme.sb(Color("#15181b"), UITheme.ACCENT, 1, 6, 4, 2))
	name_e.tooltip_text = "Щёлкните, чтобы переименовать"
	name_e.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			b["name"] = t.strip_edges()
		win.rebuild(true))
	name_e.focus_exited.connect(func() -> void:
		if name_e.text.strip_edges() != "":
			b["name"] = name_e.text.strip_edges())
	h.add_child(name_e)
	h.add_child(UITheme.chip("%d чел." % ms.size(), UITheme.MUTED))
	if int(b.get("wins", 0)) > 0 or cr.pennant == bid:
		h.add_child(UITheme.chip("вымпел" + (" ×%d" % int(b["wins"]) if int(b.get("wins", 0)) > 1 else ""), UITheme.GOOD, "Побед в соцсоревновании: %d%s" % [int(b.get("wins", 0)), " · вымпел этой недели у них" if cr.pennant == bid else ""], cr.pennant == bid))
	h.add_child(UITheme.ghost("×", func() -> void:
		cr.remove_brigade(bid)
		win.rebuild(true), "Расформировать: люди останутся на заводе, просто без бригады", UITheme.MUTED))
	v.add_child(h)
	# бригадир и строгость
	var h2 := UITheme.hbox(8)
	h2.add_child(UITheme.label("Бригадир", 12, UITheme.MUTED))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.clip_text = true
	ob.fit_to_longest_item = false
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(120, 0)
	ob.add_theme_font_size_override("font_size", 13)
	ob.add_item("— не назначен —", -1)
	var sel := 0
	for i in ms.size():
		var w: Worker = ms[i]
		ob.add_item("%s, %s%s" % [w.call_name(), w.title_lc(), " (2-я смена)" if w.shift == 1 else ""], w.id)
		if int(b["lead"]) == w.id:
			sel = i + 1
	ob.select(sel)
	ob.item_selected.connect(func(idx: int) -> void:
		var wid := ob.get_item_id(idx)
		if wid < 0:
			b["lead"] = -1
		else:
			cr.set_lead(bid, wid)
		win.rebuild(true))
	h2.add_child(ob)
	h2.add_child(_check("Только свой участок", bool(b.get("strict", false)), func(on: bool) -> void:
		b["strict"] = on
		win.rebuild(true), "Люди бригады не берут работу на чужих станках, даже если там простой"))
	v.add_child(h2)
	# участок
	var h3 := HFlowContainer.new()
	h3.add_theme_constant_override("h_separation", 5)
	h3.add_theme_constant_override("v_separation", 4)
	var cap := UITheme.label("Участок", 12, UITheme.MUTED)
	cap.custom_minimum_size = Vector2(62, 0)
	h3.add_child(cap)
	var any_room := false
	for room in sim.rooms.list:
		var nmach := 0
		for tid in room.things:
			var t: Thing = sim.things.get(tid)
			if t and t.kind() in ["machine", "qc", "storage"]:
				nmach += 1
		if nmach == 0:
			continue
		any_room = true
		var owner := cr.room_owner(room)
		var rb := UITheme.small("%s" % room.title(), Callable(), "")
		rb.toggle_mode = true
		rb.button_pressed = owner == bid
		if owner >= 0 and owner != bid:
			rb.modulate = Color(1, 1, 1, 0.5)
			rb.tooltip_text = "Сейчас за «%s» — нажмите, чтобы забрать" % str(cr.brigade(owner).get("name", ""))
		else:
			rb.tooltip_text = "Закрепить помещение (%d клеток) за бригадой" % room.area() if owner != bid else "Снять закрепление"
		var rr := room
		rb.pressed.connect(func() -> void:
			cr.toggle_room(bid, rr)
			win.rebuild(true))
		h3.add_child(rb)
	if not any_room:
		h3.add_child(UITheme.label("нет помещений со станками", 12, UITheme.MUTED))
	v.add_child(h3)
	# люди
	var h4 := HFlowContainer.new()
	h4.add_theme_constant_override("h_separation", 5)
	h4.add_theme_constant_override("v_separation", 4)
	var cap2 := UITheme.label("Люди", 12, UITheme.MUTED)
	cap2.custom_minimum_size = Vector2(62, 0)
	h4.add_child(cap2)
	for w2 in ms:
		var ww := w2
		var mb := UITheme.small(("★ " if int(b["lead"]) == w2.id else "") + w2.call_name() + "  ×", func() -> void:
			cr.set_member(ww, -1)
			win.rebuild(true), "%s, %s. Нажмите, чтобы убрать из бригады" % [w2.full_name(), w2.prof_lc()])
		h4.add_child(mb)
	var add := OptionButton.new()
	add.focus_mode = Control.FOCUS_NONE
	add.fit_to_longest_item = false
	add.add_theme_font_size_override("font_size", 12)
	add.add_theme_stylebox_override("normal", UITheme.sb(Color(0, 0, 0, 0), UITheme.LINE2, 1, 6, 8, 2))
	add.add_item("+ добавить", -1)
	for w3 in sim.workers:
		if w3.is_itr() or w3.brigade == bid:
			continue
		var cur := cr.brigade(w3.brigade)
		add.add_item("%s — %s%s" % [w3.call_name(), w3.prof_lc(), (" (из «%s»)" % str(cur["name"])) if not cur.is_empty() else ""], w3.id)
	add.select(0)
	add.item_selected.connect(func(idx: int) -> void:
		var wid := add.get_item_id(idx)
		var wx := sim.get_worker(wid)
		if wx:
			cr.set_member(wx, bid)
		win.rebuild(true))
	h4.add_child(add)
	v.add_child(h4)
	# график и сплочённость
	var own := str(b.get("sched", "")) != ""
	var sh := cr._brig_shift(bid)
	var foot := UITheme.hbox(8)
	var ms_strip := _mini_strip(cr.sched_str(sh, bid), 5.0, 8.0)
	ms_strip.tooltip_text = cr.sched_text(cr.sched_str(sh, bid), sh)
	ms_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	foot.add_child(ms_strip)
	foot.add_child(UITheme.label("свой график" if own else "график %d-й смены" % (sh + 1), 12, UITheme.INFO if own else UITheme.MUTED))
	foot.add_child(UITheme.spacer())
	if ms.size() >= 2:
		var s := 0.0
		var n := 0
		for a in ms:
			for o in ms:
				if o.id > a.id:
					s += sim.training.rel(a, o)
					n += 1
		var avg := s / maxf(1.0, float(n))
		foot.add_child(UITheme.chip("дружная" if avg >= 25.0 else ("ссорятся" if avg <= -25.0 else "обычная"), UITheme.GOOD if avg >= 25.0 else (UITheme.BAD if avg <= -25.0 else UITheme.MUTED), "Сплочённость: средние отношения внутри бригады"))
	v.add_child(foot)


## Узкая полоска графика смены (для обзора).
static func _mini_strip(s: String, cw: float, ch: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in Crew.SLOTS:
		var r := ColorRect.new()
		var code := s[i] if i < s.length() else "w"
		r.color = Color(Crew.KIND_COLORS[str(Crew.CODES.get(code, "work"))])
		r.custom_minimum_size = Vector2(cw, ch)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	return h


# ---------------------------------------------------------------- график смены

static func _schedule(win: GameWindow) -> void:
	var sim := win.sim
	var cr := sim.crew
	if sched_key.begins_with("b") and cr.brigade(int(sched_key.substr(1))).is_empty():
		sched_key = "0"
	var shift := 0
	if sched_key == "1":
		shift = 1
	elif sched_key.begins_with("b"):
		shift = cr._brig_shift(int(sched_key.substr(1)))
	var s := cr.get_sched(sched_key)
	win._info(cr.sched_text(s, shift))
	win._intro("Выберите, что рисовать, и щёлкайте по клеткам (по 15 минут). Планёрка в начале смены — +3% к скорости на всю смену (если есть бригадир или мастер). Перерыв — чай и отдых, курильщики курят по графику. Уборка в конце — участок чистый к сдаче смены. Обед — не меньше 30 минут, иначе трудовая инспекция оштрафует. Разные графики бригадам — меньше очередей в столовой.")
	# кому график
	var keys: Array = [["0", "1-я смена · 8:00"], ["1", "2-я смена · 17:00"]]
	for b: Dictionary in cr.brigades:
		keys.append(["b%d" % int(b["id"]), str(b["name"]) + (" ✎" if str(b.get("sched", "")) != "" else ""), "Свой график бригады" if str(b.get("sched", "")) != "" else "Бригада работает по общему графику смены"])
	var top := UITheme.hbox(10)
	top.add_child(UITheme.segmented(keys, sched_key, func(k: String) -> void:
		sched_key = k
		win.rebuild(true)))
	win.content.add_child(top)
	# редактор
	var card := UITheme.card(14)
	win.content.add_child(card)
	var sv := UITheme.vbox(8)
	card.add_child(sv)
	var br := UITheme.hbox(6)
	br.add_child(UITheme.caption("Кисть"))
	for kind in ["work", "lunch", "break", "meet", "clean"]:
		var kc := Color(Crew.KIND_COLORS[kind])
		var b2 := Button.new()
		b2.text = str(Crew.KIND_NAMES[kind])
		b2.toggle_mode = true
		b2.focus_mode = Control.FOCUS_NONE
		b2.button_pressed = brush == kind
		b2.add_theme_font_size_override("font_size", 13)
		b2.add_theme_stylebox_override("normal", UITheme.sb(kc.darkened(0.55), kc.darkened(0.2), 1, 6, 12, 4))
		b2.add_theme_stylebox_override("hover", UITheme.sb(kc.darkened(0.4), kc, 1, 6, 12, 4))
		b2.add_theme_stylebox_override("pressed", UITheme.sb(kc, UITheme.TEXT, 2, 6, 12, 4))
		b2.add_theme_stylebox_override("hover_pressed", UITheme.sb(kc, UITheme.TEXT, 2, 6, 12, 4))
		b2.add_theme_color_override("font_pressed_color", UITheme.ACCENT_T)
		b2.add_theme_color_override("font_hover_pressed_color", UITheme.ACCENT_T)
		var kk: String = kind
		b2.pressed.connect(func() -> void:
			brush = kk
			win.rebuild(true))
		br.add_child(b2)
	br.add_child(UITheme.spacer())
	if sched_key.begins_with("b") and str(cr.brigade(int(sched_key.substr(1))).get("sched", "")) == "":
		br.add_child(UITheme.label("общий график смены — измените клетку, появится свой", 12, UITheme.INFO))
	sv.add_child(br)
	var cw := 24.0
	var hours := Control.new()
	hours.custom_minimum_size = Vector2(cw * Crew.SLOTS, 16)
	for i in Crew.SLOTS:
		if i % 4 != 0:
			continue
		var hl := UITheme.label(cr.slot_time(shift, i).split(":")[0] + ":00", 11, UITheme.MUTED)
		hl.position = Vector2(cw * i + 1, 0)
		hours.add_child(hl)
	sv.add_child(hours)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 0)
	for i2 in Crew.SLOTS:
		var kind2 := str(Crew.CODES.get(s[i2], "work"))
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(cw, 40)
		cb.focus_mode = Control.FOCUS_NONE
		cb.tooltip_text = "%s–%s: %s" % [cr.slot_time(shift, i2), cr.slot_time(shift, i2 + 1), str(Crew.KIND_NAMES[kind2])]
		var col := Color(Crew.KIND_COLORS[kind2])
		var edge := UITheme.BG2 if i2 % 4 != 0 else UITheme.TEXT.darkened(0.45)
		cb.add_theme_stylebox_override("normal", _cell_sb(col, edge))
		cb.add_theme_stylebox_override("hover", _cell_sb(col.lightened(0.25), edge))
		cb.add_theme_stylebox_override("pressed", _cell_sb(col.lightened(0.4), edge))
		var idx := i2
		cb.pressed.connect(func() -> void:
			cr.set_slot(sched_key, idx, brush)
			win.rebuild(true))
		cells.add_child(cb)
	sv.add_child(cells)
	var st := UITheme.hbox(8)
	for it in [["work", _hm(cr.minutes(s, "work"))], ["lunch", "%d мин" % cr.minutes(s, "lunch")], ["break", "%d мин" % cr.minutes(s, "break")],
			["meet", "%d мин" % cr.minutes(s, "meet")], ["clean", "%d мин" % cr.minutes(s, "clean")]]:
		st.add_child(UITheme.chip("%s · %s" % [str(Crew.KIND_NAMES[it[0]]).to_lower(), str(it[1])], Color(Crew.KIND_COLORS[it[0]]).lightened(0.25)))
	sv.add_child(st)
	for p in cr.sched_problems(s):
		sv.add_child(UITheme.label("⚠ " + p, 13, UITheme.BAD))
	# шаблоны и обзор
	var g := win._cards(2)
	var t := win._card_in(g, "Шаблоны")
	var pr := HFlowContainer.new()
	pr.add_theme_constant_override("h_separation", 6)
	pr.add_theme_constant_override("v_separation", 6)
	for pp in [["classic", "Только обед", "Как раньше: обед 45 минут"], ["order", "Порядок", "Планёрка, обед час, чай после обеда, уборка в конце"],
			["tea", "Два чаепития", "Планёрка, перерыв до и после обеда, уборка"], ["rush", "Аврал", "Обед 30 минут и больше ничего: выпуск выше, люди устают"]]:
		var key2 := str(pp[0])
		pr.add_child(UITheme.small(str(pp[1]), func() -> void:
			cr.put_sched(sched_key, cr.preset(key2))
			win.rebuild(true), str(pp[2])))
	if sched_key.begins_with("b"):
		pr.add_child(UITheme.small("Вернуть общий", func() -> void:
			cr.reset_sched(sched_key)
			win.rebuild(true), "Бригада снова работает по общему графику своей смены"))
	t.add_child(pr)
	var o := win._card_in(g, "Все графики", "Сравните, чтобы обеды бригад не совпадали: меньше очередей в столовой.")
	for k2: Array in keys:
		var kh := UITheme.hbox(8)
		var kl := UITheme.label(str(k2[1]).split(" · ")[0], 12, UITheme.TEXT if str(k2[0]) == sched_key else UITheme.MUTED)
		kl.custom_minimum_size = Vector2(120, 0)
		kl.clip_text = true
		kh.add_child(kl)
		var ks := str(k2[0])
		var sh2 := 1 if ks == "1" else (cr._brig_shift(int(ks.substr(1))) if ks.begins_with("b") else 0)
		kh.add_child(_mini_strip(cr.get_sched(ks) if not ks.begins_with("b") else cr.sched_str(sh2, int(ks.substr(1))), 7.0, 10.0))
		o.add_child(kh)


static func _cell_sb(col: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = edge
	sb.border_width_left = 1
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	return sb


static func _hm(m: int) -> String:
	return "%d ч %02d мин" % [int(m / 60), m % 60]


# ---------------------------------------------------------------- охрана

static func _security(win: GameWindow) -> void:
	var sim := win.sim
	var cr := sim.crew
	var cp := cr.post()
	var gs := cr.guards()
	var cams := cr.cams()
	var on := 0
	var rooms: Array[String] = []
	for t in cams:
		if cr.cam_ok(t):
			on += 1
			var r := sim.rooms.room_at(t.cell)
			if r and not rooms.has(r.title()):
				rooms.append(r.title())
	var dk := int(round(cr.detect_k() * 100.0))
	win._info("шанс поймать несуна на выходе: %d%%" % dk)
	win._intro("Несуны выносят металл и расходники, уходя со смены. Охранник на проходной ловит больше половины, камеры отпугивают и записывают, а инвентаризация по пятницам показывает, сколько ушло мимо. Охрана ещё и отбивает охоту проносить спиртное.")
	win._hbtn("Нанять охранника…", func() -> void:
		GameWindow.ad_prof = "guard"
		win.select_tab("hire"), "Откроется найм; можно дать объявление на охранника")
	var g := win._cards(4)
	g.add_child(UITheme.stat("Проходная", "есть" if cp else "нет", UITheme.GOOD if cp else UITheme.WARN, "" if cp else "Объекты → Безопасность", UITheme.MUTED, "Проходная с турникетами у въезда: люди проходят через турникеты, охранник сидит в будке"))
	g.add_child(UITheme.stat("Охранники", str(gs.size()), UITheme.TEXT if not gs.is_empty() else UITheme.WARN, "на смене %d" % cr.guards(true).size() if not gs.is_empty() else "наймите в «Найме»"))
	g.add_child(UITheme.stat("Камеры", "%d / %d" % [on, cams.size()], UITheme.GOOD if on > 0 and on == cams.size() else (UITheme.WARN if cams.size() > on else UITheme.MUTED), "работают / всего", UITheme.MUTED, ("Смотрят: " + ", ".join(PackedStringArray(rooms))) if not rooms.is_empty() else "Камере нужен ток"))
	g.add_child(UITheme.stat("Задержано", str(cr.caught_total), UITheme.TEXT, "недостача %s" % Defs.money_str(cr.shortage_total), UITheme.BAD if cr.shortage_total > 0 else UITheme.MUTED))
	var bar := UITheme.card(10)
	win.content.add_child(bar)
	var bh := UITheme.hbox(12)
	bar.add_child(bh)
	bh.add_child(_check("Досмотр силами ЧОП · %s в день" % Defs.money_str(Defs.ev("guard_cost_day")), sim.story.guard, func(v: bool) -> void:
		sim.story.guard = v
		win.rebuild(true), "Нанятая охранная фирма досматривает всех на проходной: ловит 85% несунов, но людям неприятно. Работает, только когда в будке охранник на смене" + ("" if cp else ". Нужна проходная."), cp == null))
	bh.add_child(UITheme.spacer())
	if not cr.missing.is_empty():
		var mv := 0.0
		for m: Dictionary in cr.missing:
			mv += float(m["value"])
		bh.add_child(UITheme.chip("с инвентаризации пропало на %s" % Defs.money_str(mv), UITheme.WARN, "Подробности — в пятницу, на инвентаризации"))
	var cols := win._cards(2)
	var a := win._card_in(cols, "Охранники")
	if gs.is_empty():
		a.add_child(UITheme.para("Охранников нет.", 13))
	for gd in gs:
		var h := UITheme.hbox(8)
		var por := Portrait.new()
		por.set_look(gd.look, 0.6, {"age": gd.age, "mood": gd.mood})
		h.add_child(por)
		var cell := win._cl2(gd.formal_name(), "охрана %d · %s · %s" % [gd.skill("security"), str(Worker.SHIFT_NAMES[gd.shift]).to_lower(), gd.activity])
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cell)
		a.add_child(h)
	var lg := win._card_in(cols, "Журнал охраны")
	if cr.history.is_empty():
		lg.add_child(UITheme.para("Пока тихо.", 13))
	for e: Dictionary in cr.history.slice(0, 8):
		var eh := UITheme.hbox(8)
		var dl := UITheme.label(str(e.get("date", "")), 12, UITheme.DIM)
		dl.custom_minimum_size = Vector2(70, 0)
		dl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		eh.add_child(dl)
		eh.add_child(UITheme.para(str(e["text"]), 12, UITheme.MUTED))
		lg.add_child(eh)


# ---------------------------------------------------------------- профсоюз

static func _union(win: GameWindow) -> void:
	var sim := win.sim
	var cr := sim.crew
	win._intro("Профком ведёт переговоры о колдоговоре, заранее предупреждает о забастовках и участвует в расследовании несчастных случаев.")
	if not cr.union_on():
		var n := cr._staff_n()
		win._info("профсоюза нет")
		var c := UITheme.card(16)
		win.content.add_child(c)
		var v0 := UITheme.vbox(8)
		c.add_child(v0)
		v0.add_child(UITheme.label("Профсоюза пока нет", 18, UITheme.TEXT, UITheme.f_semi))
		v0.add_child(UITheme.para("Он появится сам, когда рабочих станет %d и больше — быстрее, если в коллективе есть активист или люди недовольны." % Crew.UNION_MIN, 13))
		v0.add_child(UITheme.meter(100.0 * n / maxf(1.0, float(Crew.UNION_MIN)), UITheme.INFO, 260, "%d из %d рабочих" % [mini(n, Crew.UNION_MIN), Crew.UNION_MIN]))
		return
	var lw := cr.union_lead()
	var st := str(cr.union.get("stance", "neutral"))
	var stance := {"support": "доволен администрацией", "neutral": "держит нейтралитет", "angry": "недоволен"}
	var scol := UITheme.GOOD if st == "support" else (UITheme.BAD if st == "angry" else UITheme.MUTED)
	win._info("профком %s" % str(stance.get(st, st)))
	var g := win._cards(2)
	var a := win._card_in(g, "Профком")
	var h := UITheme.hbox(10)
	if lw:
		var por := Portrait.new()
		por.set_look(lw.look, 0.7, {"age": lw.age, "mood": lw.mood})
		h.add_child(por)
	var v := UITheme.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UITheme.label(lw.full_name() if lw else "председатель не выбран", 15, UITheme.TEXT, UITheme.f_semi))
	v.add_child(UITheme.label("председатель · с дня %d" % int(cr.union.get("since", 0)), 12, UITheme.MUTED))
	v.add_child(UITheme.chip(str(stance.get(st, st)), scol))
	h.add_child(v)
	a.add_child(h)
	var office := cr.union_office()
	var oh := UITheme.hbox(6)
	oh.add_child(UITheme.label("Комната профкома", 13, UITheme.MUTED))
	oh.add_child(UITheme.chip("есть" if office else "нет", UITheme.GOOD if office else UITheme.WARN, "Председатель там работает — профком спокойнее" if office else "Помещение со столом ИТР и доской профкома (Объекты → Офис), назначьте «Профком»"))
	a.add_child(oh)
	var pat := cr.strike_patience()
	a.add_child(UITheme.para("До забастовки люди терпят на %d %s %s обычного; перед забастовкой профком предупредит письмом." % [absi(pat), Defs.plural(absi(pat), "день", "дня", "дней"), "дольше" if pat >= 0 else "меньше"], 12, UITheme.INFO))
	var offer: Array = cr.union.get("offer", [])
	if not offer.is_empty():
		var b := win._card_in(g, "Проект колдоговора", "Отметьте пункты, на которые согласны. Три и больше — профком доволен; меньше двух — будет недоволен.")
		for k in offer:
			var key := str(k)
			var c2 := _check(str(Crew.CLAUSES[key]["name"]), bool(kd_pick.get(key, true)), func(on: bool) -> void: kd_pick[key] = on, str(Crew.CLAUSES[key]["desc"]))
			b.add_child(c2)
			var dl := UITheme.para(str(Crew.CLAUSES[key]["desc"]), 11, UITheme.DIM)
			dl.add_theme_constant_override("line_spacing", -2)
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_left", 28)
			m.add_child(dl)
			b.add_child(m)
		var sb := UITheme.primary("Подписать на %d дней" % Crew.KD_DAYS, func() -> void:
			var sel: Array = []
			for k2 in offer:
				if bool(kd_pick.get(str(k2), true)):
					sel.append(str(k2))
			var err := cr.sign(sel)
			if err != "":
				win.hud.toast(err, Sim.LVL_WARN)
			kd_pick.clear()
			win.rebuild(true))
		sb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.add_child(sb)
	elif cr.signed():
		var until := int(cr.union["signed"]) + Crew.KD_DAYS
		var b2 := win._card_in(g, "Колдоговор до дня %d" % until)
		var broken: Dictionary = cr.union.get("broken", {})
		for k3 in (cr.union.get("clauses", {}) as Dictionary).keys():
			var bd := -1
			for bk in broken.keys():
				if str(bk).begins_with(str(k3)):
					bd = maxi(bd, int(broken[bk]))
			var ok := bd < 0 or sim.day() - bd > 14
			var rh := UITheme.hbox(8)
			rh.add_child(UITheme.label("✓" if ok else "×", 14, UITheme.GOOD if ok else UITheme.BAD, UITheme.f_semi))
			var nl := UITheme.para(str(Crew.CLAUSES[str(k3)]["name"]), 13, UITheme.TEXT)
			nl.tooltip_text = str(Crew.CLAUSES[str(k3)]["desc"])
			nl.mouse_filter = Control.MOUSE_FILTER_STOP
			rh.add_child(nl)
			if not ok:
				rh.add_child(UITheme.chip("нарушен в день %d" % bd, UITheme.BAD))
			b2.add_child(rh)
		if (cr.union.get("clauses", {}) as Dictionary).is_empty():
			b2.add_child(UITheme.para("Договор подписан без единого пункта — профком недоволен.", 13, UITheme.WARN))
	else:
		var b3 := win._card_in(g, "Колдоговор")
		b3.add_child(UITheme.para("Профком готовит проект (с дня %d). Как будет готов — придёт письмо." % int(cr.union.get("talk", sim.day())), 13))


# ---------------------------------------------------------------- Н-1 для «Охраны труда»

static func n1_section(win: GameWindow, parent: Control = null) -> void:
	var sim := win.sim
	var cr := sim.crew
	var v := win._card_in(parent if parent else win.content, "Акты Н-1", "После каждой травмы комиссия за %d рабочих дня расследует причины и составляет акт Н-1. Причины по вине предприятия — компенсация пострадавшему и штраф трудовой инспекции; табло «Дней без травм» снижает травмы на 5%%." % Crew.N1_DAYS)
	var sd := cr.safe_days()
	v.add_child(UITheme.label("%d %s без травм" % [sd, Defs.plural(sd, "день", "дня", "дней")], 18, UITheme.GOOD if sd >= 30 else UITheme.TEXT, UITheme.f_semi))
	if cr.cases.is_empty():
		v.add_child(UITheme.para("Несчастных случаев не было.", 13))
		return
	for c: Dictionary in cr.cases.slice(0, 6):
		var causes: Array[String] = []
		for k in c["causes"]:
			causes.append(cr.cause_text(str(k)))
		var st := str(c["status"])
		var status := ""
		match st:
			"open":
				status = "расследование"
			"act":
				status = "акт ждёт подписи"
			"hidden":
				status = "не оформлен"
			_:
				status = str(c.get("verdict", ""))
				if float(c.get("fine", 0.0)) > 0.0:
					status += ", штраф " + Defs.money_str(float(c["fine"]))
		var h := UITheme.hbox(8)
		var cell := win._cl2("День %d · %s (%s)" % [int(c["day"]), str(c["name"]), str(c["prof"]).to_lower()], "; ".join(PackedStringArray(causes)), UITheme.TEXT, UITheme.MUTED, 13)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cell)
		h.add_child(UITheme.chip(status, UITheme.WARN if st in ["open", "act", "hidden"] else UITheme.MUTED))
		v.add_child(h)
