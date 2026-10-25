class_name TownUI
extends RefCounted
## Окно «Город» (1.9): обзор соцсферы, общежитие, столовая и медпункт, детсад и ДК, радио, кот.


static func sig(win: GameWindow) -> String:
	var sim := win.sim
	var t := sim.town
	var parts: Array[String] = [win.tab, str(int(t.rel)), str(t.beds), str(t.invite_away), str(t.portions), str(t.meals_today), str(t.kg_level), str(t.dk),
		str(t.radio), str(t.vaccinated_until), str(t.cat != null), str(sim.rooms.list.size()), str(sim.thing_rev), str(sim.workers.size()), str(int(sim.money / 50000.0)), str(int(sim.minute / 30.0))]
	if t.cat:
		parts.append(t.cat.name + t.cat.activity)
	return ",".join(parts)


static func build(win: GameWindow) -> void:
	match win.tab:
		"dorm":
			_dorm(win)
		"canteen":
			_canteen(win)
		"kg":
			_kg(win)
		"radio":
			_radio(win)
		"cat":
			_cat(win)
		_:
			_overview(win)


static func _status_row(v: Control, text: String, ok: bool, hint: String = "") -> void:
	var h := UITheme.hbox(8)
	h.add_child(UITheme.label("✓" if ok else "×", 14, UITheme.GOOD if ok else UITheme.BAD, UITheme.f_semi))
	var l := UITheme.label(L.t(text), 13, UITheme.TEXT if ok else UITheme.MUTED)
	l.tooltip_text = L.t(hint)
	l.mouse_filter = Control.MOUSE_FILTER_STOP if hint != "" else Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	v.add_child(h)


# ---------------------------------------------------------------- обзор

static func _overview(win: GameWindow) -> void:
	var sim := win.sim
	var t := sim.town
	win._info(L.t("город %s · отношения %d из 100") % [L.t(t.rel_text()), int(t.rel)])
	win._intro(L.t("Город смотрит, как завод заботится о людях: общежитие, горячие обеды, медпункт, детсад, Дом культуры, радио. Отношения от 60 — больше кандидатов, от 75 — льгота: налог с выручки на 1% ниже. Увольнения город не любит."))
	var g := win._cards(4)
	g.add_child(UITheme.stat("Отношения с городом", "%d" % int(t.rel), UITheme.ramp(t.rel / 100.0), L.t(t.rel_text())))
	g.add_child(UITheme.stat("Общежитие", "%d / %d" % [t.residents().size(), t.dorm_capacity()], UITheme.TEXT, "жильцов / коек"))
	g.add_child(UITheme.stat("Горячих обедов", str(t.meals_today), UITheme.GOOD if t.meals_today > 0 else UITheme.MUTED, L.t("сегодня · всего %d") % t.meals_total))
	g.add_child(UITheme.stat("Детсад", "%d / %d" % [t.kg_kids().size(), t.parents().size()], UITheme.TEXT, "мест получили / родителей"))
	var cards := win._cards(3)
	var items := [
		["bed", "Общежитие", not t.dorm_rooms().is_empty(), "Койки для иногородних: новые кандидаты, жильцы не опаздывают.", "Комната с двухъярусной кроватью и шкафчиком → «Общежитие»", "dorm"],
		["heat", "Кухня и повар", t.kitchen_ready() and not t.cooks().is_empty(), "Горячие обеды: +9 к настроению вместо +6.", "Плита и линия раздачи в столовой, повар в штате", "canteen"],
		["med", "Медпункт", not t.medbays().is_empty() and not t.nurses().is_empty(), "Больничные короче на 40%, гриппа меньше.", "Кушетка, шкаф с лекарствами, раковина и фельдшер", "canteen"],
		["kid", "Детсад «Шестерёнка»", t.kg_level > 0, "Родителям спокойнее, прогулов меньше.", "С этапа «Малое предприятие»", "kg"],
		["culture", "ДК «Машиностроитель»", t.dk, "Кружки и концерты к праздникам.", "С этапа «Среднее предприятие»", "kg"],
		["radio", "Заводское радио", t.radio_station() != null, "Новости, гимнастика и музыка в обед.", "Радиоузел и громкоговорители (Объекты → Офис)", "radio"],
	]
	for it: Array in items:
		var v := win._card_in(cards)
		var h := UITheme.hbox(8)
		h.add_child(win._icon(Tex.ui(str(it[0])), 22))
		var tl := UITheme.label(str(it[1]), 15, UITheme.TEXT, UITheme.f_semi)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tl)
		h.add_child(UITheme.chip(L.t("работает") if bool(it[2]) else L.t("нет"), UITheme.GOOD if bool(it[2]) else UITheme.MUTED))
		v.add_child(h)
		v.add_child(UITheme.para(str(it[3]), 12, UITheme.TEXT))
		if not bool(it[2]):
			v.add_child(UITheme.para(str(it[4]), 12, UITheme.INFO))
		var sec := str(it[5])
		var ob := UITheme.small("Подробнее →", func() -> void: win.select_tab(sec))
		ob.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(ob)
	if t.cat:
		var cc := win._card_in(win.content)
		var ch := UITheme.hbox(10)
		cc.add_child(ch)
		ch.add_child(_cat_pic(t.cat, 1.4))
		var cv := UITheme.vbox(2)
		cv.add_child(UITheme.label(L.name(t.cat.title()), 15, UITheme.TEXT, UITheme.f_semi))
		cv.add_child(UITheme.label(L.t(t.cat.activity), 12, UITheme.INFO))
		ch.add_child(cv)


# ---------------------------------------------------------------- общежитие

static func _dorm(win: GameWindow) -> void:
	var sim := win.sim
	var t := sim.town
	var res := t.residents()
	win._info(L.t("жильцов %d · свободно коек %d") % [res.size(), t.free_beds()])
	win._intro(L.t("Общежитие — комната с двухъярусной кроватью (две койки) и шкафчиком, назначенная «Общежитием». Пока есть свободные койки, по понедельникам приходят иногородние кандидаты: они чуть дешевле и никогда не опаздывают. Уютная комната (окна, свет, декор) — им веселее. Плата — %s в день с жильца.") % Defs.money_str(Town.DORM_FEE))
	var g := win._cards(3)
	g.add_child(UITheme.stat("Комнат", str(t.dorm_rooms().size()), UITheme.TEXT, "оборудованных общежитий"))
	g.add_child(UITheme.stat("Коек", "%d / %d" % [res.size(), t.dorm_capacity()], UITheme.TEXT, "занято / всего"))
	g.add_child(UITheme.stat("Плата в день", Defs.money_str(Town.DORM_FEE * res.size()), UITheme.GOOD if not res.is_empty() else UITheme.MUTED, "с жильцов"))
	var bar := UITheme.card(10)
	win.content.add_child(bar)
	var bh := UITheme.hbox(12)
	bar.add_child(bh)
	var cb := CheckBox.new()
	cb.text = "Приглашать иногородних кандидатов"
	cb.button_pressed = t.invite_away
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "По понедельникам — до трёх кандидатов из других городов, если в общежитии есть свободные койки"
	cb.toggled.connect(func(on: bool) -> void:
		t.invite_away = on
		win.rebuild(true))
	bh.add_child(cb)
	bh.add_child(UITheme.spacer())
	if not sim.dev.on("hr2"):
		cb.disabled = true
		bh.add_child(UITheme.label("иногородних зовёт кадровик после ступени «Связь с ПТУ»", 12, UITheme.WARN))
	else:
		bh.add_child(UITheme.label(L.t("на следующей неделе приедут: %d") % t.away_candidates(), 12, UITheme.MUTED))
	if t.dorm_rooms().is_empty():
		win.content.add_child(UITheme.empty("Общежития нет. Постройте комнату, поставьте двухъярусную кровать и шкафчик (Объекты → Быт) и назначьте её «Общежитием»."))
		return
	if res.is_empty():
		win.content.add_child(UITheme.empty("Пока никто не живёт. Наймите иногороднего кандидата в «Люди → Найм» — у него пометка «иногородний»."))
		return
	win._thead([["", 40], ["Жилец", 260], ["Профессия", 200], ["Комната", -1]])
	for w: Worker in res:
		var por := Portrait.new()
		por.set_look(w.look, 0.6, {"age": w.age, "mood": w.mood})
		var bed := t.bed_of(w)
		var r := sim.rooms.room_of_thing(bed) if bed else null
		var wid := w.id
		win._trow([[por, 40], [win._cl2(w.formal_name(), L.t(("иногородняя" if w.female else "иногородний") if w.from_away else ("местная" if w.female else "местный"))), 260], [win._cl(L.t(w.prof_name()), 13), 200],
			[win._cl(r.title() if r else "—", 13, UITheme.MUTED), -1]], func() -> void:
				win.hud.select_worker(wid)
				win.closed.emit(), 40.0, "Показать на заводе")


# ---------------------------------------------------------------- столовая и медпункт

static func _canteen(win: GameWindow) -> void:
	var sim := win.sim
	var t := sim.town
	win._info(L.t("горячих обедов сегодня %d · порций готово %d") % [t.meals_today, t.portions])
	var g := win._cards(2)
	var a := win._card_in(g, L.t("Кухня"), L.t("Повар у плиты готовит порции на всех, кто сегодня обедает (продукты — %s за порцию). Обед в столовой с горячим: +9 к настроению вместо +6, и человек отдыхает.") % Defs.money_str(Town.MEAL_COST))
	var st := t.kitchen()
	_status_row(a, "Плита в столовой", st != null, "Объекты → Быт → Электроплита промышленная (6 кВт)")
	_status_row(a, "Плита под током", st != null and sim.power.powered(st))
	_status_row(a, "Линия раздачи", t.has_serving(), "Объекты → Быт → Линия раздачи")
	var ck := t.cooks()
	_status_row(a, L.t("Повар в штате") + (": " + ck[0].full_name() if not ck.is_empty() else ""), not ck.is_empty(), "Люди → Найм: повар")
	if ck.is_empty() and st != null:
		var hb := UITheme.small("Найти повара →", func() -> void:
			GameWindow.ad_prof = "cook"
			win.hud.open_window("people")
			if win.hud.win:
				win.hud.win.select_tab("hire"))
		hb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		a.add_child(hb)
	a.add_child(UITheme.para(L.t("Сегодня: %d горячих обедов, готово ещё %d порций. Всего накормили: %d.") % [t.meals_today, t.portions, t.meals_total], 12, UITheme.INFO))
	var b := win._card_in(g, L.t("Медпункт"), L.t("Комната с кушеткой, шкафом с лекарствами и раковиной, назначенная «Медпунктом», и фельдшер на смене: больничные после травм на 40% короче, грипп реже и легче, прививки дешевле."))
	_status_row(b, "Медпункт оборудован", not t.medbays().is_empty(), "Кушетка, шкаф с лекарствами (Объекты → Безопасность), раковина")
	var nr := t.nurses()
	_status_row(b, L.t("Фельдшер в штате") + (": " + nr[0].full_name() if not nr.is_empty() else ""), not nr.is_empty(), "Люди → Найм: фельдшер")
	if nr.is_empty() and not t.medbays().is_empty():
		var nb := UITheme.small("Найти фельдшера →", func() -> void:
			GameWindow.ad_prof = "nurse"
			win.hud.open_window("people")
			if win.hud.win:
				win.hud.win.select_tab("hire"))
		nb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.add_child(nb)
	b.add_child(UITheme.caption("Грипп"))
	var vac := t.vaccinated_until >= sim.day()
	b.add_child(UITheme.para(L.t("Сезон гриппа — с ноября по февраль. " if not t.flu_season() else "Сейчас сезон гриппа! ") + (L.t("Коллектив привит до дня %d.") % t.vaccinated_until if vac else L.t("Прививка — в четыре раза меньше заболевших.")) + (L.t(" Болели в этом году: %d.") % t.flu_cases if t.flu_cases > 0 else ""), 12, UITheme.WARN if t.flu_season() and not vac else UITheme.MUTED))
	var cost := Town.VACCINE * sim.workers.size() * (0.7 if not nr.is_empty() else 1.0)
	var vb := UITheme.small(L.t("Сделать прививки · %s") % Defs.money_str(cost), func() -> void:
		var err := t.vaccinate()
		if err != "":
			win.hud.toast(err, Sim.LVL_WARN)
		win.rebuild(true), L.t("%s на человека%s") % [Defs.money_str(Town.VACCINE), L.t(", с фельдшером на 30% дешевле") if not nr.is_empty() else ""])
	vb.disabled = vac and t.vaccinated_until >= sim.day() + 30
	vb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_child(vb)


# ---------------------------------------------------------------- детсад и ДК

static func _kg(win: GameWindow) -> void:
	var sim := win.sim
	var t := sim.town
	var ps := t.parents()
	var placed := t.kg_kids()
	win._info(L.t("родителей %d · мест в садике %d") % [ps.size(), t.kg_places()])
	var g := win._cards(2)
	var a := win._card_in(g, L.t("Детсад «%s»") % L.t(t.kg_name()), L.t("Завод содержит группы в городском саду. Работникам с детьми дают места (сначала мамам, потом по стажу): «Ребёнок в заводском садике» +5. Без садика родители иногда сидят с ребёнком и не выходят на смену."))
	a.add_child(UITheme.label(L.t("%d мест") % t.kg_places() if t.kg_level > 0 else L.t("своего садика нет"), 20, UITheme.TEXT if t.kg_level > 0 else UITheme.MUTED, UITheme.f_semi))
	if t.kg_level > 0:
		a.add_child(UITheme.para(L.t("содержание %s в неделю") % Defs.money_str(float(Town.KG_LEVELS[t.kg_level][2])), 12))
	if t.kg_level < Town.KG_LEVELS.size() - 1:
		var nx: Array = Town.KG_LEVELS[t.kg_level + 1]
		var cost := float(nx[1]) - float(Town.KG_LEVELS[t.kg_level][1])
		var ub := UITheme.primary(L.t("Открыть группы на %d мест · %s" if t.kg_level == 0 else "Расширить до %d мест · %s") % [int(nx[0]), Defs.money_str(cost)], func() -> void:
			var err := t.kg_upgrade()
			if err != "":
				win.hud.toast(err, Sim.LVL_WARN)
			win.rebuild(true), L.t("Потом — %s в неделю на содержание") % Defs.money_str(float(nx[2])))
		ub.disabled = not sim.dev.on("city3")
		ub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		a.add_child(ub)
		if ub.disabled:
			a.add_child(UITheme.para("Откроется со ступенью «Шефство» (Управление → Развитие).", 12, UITheme.WARN))
	var b := win._card_in(g, L.t("ДК «Машиностроитель»"), L.t("Завод берёт на баланс городской Дом культуры: каждую неделю кто-то из работников ходит в кружки (+4), к Новому году и Дню машиностроителя — концерт (+6 всем). Город очень доволен."))
	b.add_child(UITheme.label(L.t("на балансе завода с дня %d") % t.dk_since if t.dk else L.t("пока городской"), 20, UITheme.GOOD if t.dk else UITheme.MUTED, UITheme.f_semi))
	if t.dk:
		b.add_child(UITheme.para(L.t("содержание %s в неделю") % Defs.money_str(Town.DK_WEEK), 12))
	else:
		var db := UITheme.primary(L.t("Взять на баланс · %s") % Defs.money_str(Town.DK_COST), func() -> void:
			var err2 := t.dk_buy()
			if err2 != "":
				win.hud.toast(err2, Sim.LVL_WARN)
			win.rebuild(true), L.t("Потом — %s в неделю") % Defs.money_str(Town.DK_WEEK))
		db.disabled = not sim.dev.on("city3")
		db.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.add_child(db)
		if db.disabled:
			b.add_child(UITheme.para("Откроется со ступенью «Шефство» (Управление → Развитие).", 12, UITheme.WARN))
	if ps.is_empty():
		win.content.add_child(UITheme.empty("Работников с маленькими детьми пока нет."))
		return
	win._thead([["", 40], ["Родитель", 260], ["Детей", 80], ["Садик", -1]])
	for w: Worker in ps:
		var por := Portrait.new()
		por.set_look(w.look, 0.6, {"age": w.age, "mood": w.mood})
		var ok := placed.has(w)
		var cw := HBoxContainer.new()
		cw.alignment = BoxContainer.ALIGNMENT_BEGIN
		cw.add_child(UITheme.chip(L.t("место есть" if ok else ("нет места" if t.kg_level > 0 else "садика нет")), UITheme.GOOD if ok else UITheme.MUTED))
		win._trow([[por, 40], [win._cl2(w.formal_name(), L.t(w.prof_name())), 260], [win._cl(str(w.kids), 13), 80], [cw, -1]], Callable(), 54.0)


# ---------------------------------------------------------------- радио

static func _radio(win: GameWindow) -> void:
	var sim := win.sim
	var t := sim.town
	var st := t.radio_station()
	var rooms := t.radio_rooms()
	win._info(L.t("радио «Заводская волна» · %s") % L.t("в эфире" if st else "молчит"))
	win._intro(L.t("Радиоузел (Объекты → Офис) под током и громкоговорители под потолком: радио слышно в помещениях, где висит рупор. Программы — по рабочим дням."))
	var g := win._cards(2)
	var a := win._card_in(g, L.t("Эфир"))
	var have := not sim.things_of("radio").is_empty()
	_status_row(a, "Радиоузел", have, "Объекты → Офис → Радиоузел (этап «Малое предприятие»)")
	_status_row(a, "Радиоузел под током", st != null)
	var sp := sim.things_of("speaker").size()
	_status_row(a, L.t("Громкоговорители: %d") % sp, sp > 0, "Объекты → Офис → Громкоговоритель, кабель не дальше 3 клеток")
	var names: Array[String] = []
	for r in rooms:
		names.append(L.t((r as Rooms.Room).title()))
	a.add_child(UITheme.para(L.t("Слышно: %s") % (", ".join(names) if not names.is_empty() else L.t("нигде")), 12, UITheme.INFO if not names.is_empty() else UITheme.MUTED))
	var b := win._card_in(g, L.t("Программы"))
	for k in Town.RADIO_PROGRAMS.keys():
		var pd: Dictionary = Town.RADIO_PROGRAMS[k]
		var key := str(k)
		var cb := CheckBox.new()
		cb.text = L.t(str(pd["name"]))
		cb.button_pressed = bool(t.radio.get(key, false))
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void:
			t.radio[key] = on
			win.rebuild(true))
		b.add_child(cb)
		var dl := UITheme.para(L.t(str(pd["desc"])), 11, UITheme.DIM)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 28)
		m.add_child(dl)
		b.add_child(m)


# ---------------------------------------------------------------- кот

static func _cat_pic(c: Cat, z: float) -> Control:
	var host := Control.new()
	host.custom_minimum_size = Vector2(48, 38) * z
	for nm in ["fur", "fx"]:
		var tr := TextureRect.new()
		tr.texture = Tex.fx("cat_sit_%s" % nm)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if nm == "fur":
			tr.modulate = c.fur_color()
		host.add_child(tr)
	return host


static func _cat(win: GameWindow) -> void:
	var sim := win.sim
	var t := sim.town
	var c := t.cat
	if c == null:
		win._info(L.t("кота нет"))
		var msg := L.t("Кот ушёл: без миски на заводе голодно. Может, прибьётся другой…" if t.cat_gone else ("Кот отказался от предложения — ну и ладно." if t.cat_offered else "Кот ещё не прибился. Обычно это случается, когда на заводе есть столовая: запах котлет слышно издалека."))
		win.content.add_child(UITheme.empty(msg))
		return
	win._info(L.t(c.activity).to_lower())
	win._intro(L.t("Заводской кот гуляет по цехам, спит у тёплого, ест из миски дважды в день (корм — 40 ₽ в день) и ловит крыс: с ним крысы не портят расходники на складе. Кто проходит мимо в перерыв, гладит его: +3 к настроению."))
	var cols := win._cards(2)
	var a := win._card_in(cols)
	var h := UITheme.hbox(14)
	a.add_child(h)
	var fr := PanelContainer.new()
	fr.add_theme_stylebox_override("panel", UITheme.sb(Color("#cfd6dc"), FactoryUI.GOLD, 2, 4, 6, 6))
	fr.add_child(_cat_pic(c, 3.0))
	h.add_child(fr)
	var v := UITheme.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ne := LineEdit.new()
	ne.text = c.shown_name()   # 1.40: в английском — латиницей; не меняли — кличку не трогаем
	ne.add_theme_font_override("font", UITheme.f_semi)
	ne.add_theme_font_size_override("font_size", 20)
	ne.tooltip_text = "Щёлкните, чтобы переименовать"
	ne.text_submitted.connect(func(s: String) -> void:
		if s.strip_edges() != "" and s.strip_edges() != c.shown_name():
			c.name = s.strip_edges().left(16)
		win.rebuild(true))
	v.add_child(ne)
	v.add_child(UITheme.label(L.t("%s %s · на заводе с %d-го дня") % [L.t(c.fur_name()), L.t("кошка" if c.female else "кот"), c.since], 13, UITheme.MUTED))
	v.add_child(UITheme.label(L.t(c.activity), 14, UITheme.INFO))
	v.add_child(UITheme.label(L.t("поймано крыс: %d") % c.mice, 13, UITheme.TEXT))
	var bowl := c._bowl()
	v.add_child(UITheme.chip("миска есть" if bowl else "нет миски — уйдёт!", UITheme.GOOD if bowl else UITheme.BAD))
	h.add_child(v)
	var b := win._card_in(cols, L.t("Гладили сегодня"))
	var n := 0
	for w in sim.workers:
		if int(w.get_meta("cat_day", -1)) == sim.day() and w.thoughts.any(func(th: Dictionary) -> bool: return str(th["id"]) == "cat_pet" and float(th["until"]) > sim.minute):
			b.add_child(UITheme.label("· " + w.full_name(), 13, UITheme.TEXT))
			n += 1
	if n == 0:
		b.add_child(UITheme.para("Пока никого. Кот выходит к людям в обед и в перерывы.", 13))
	var fb := UITheme.small("Показать на заводе", func() -> void:
		win.hud.g.cam.focus_cell(c.cell())
		win.closed.emit())
	fb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_child(fb)
