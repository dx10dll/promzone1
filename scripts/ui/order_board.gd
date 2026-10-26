class_name OrderBoard
extends RefCounted
## 1.48b: доска «Новые заявки». Заявки не принимаются сразу, а ложатся карточками: игрок решает
## «Взять», «Торговаться» или «Отказать». Сверху — режим отдела сбыта (Вручную / Мелочь сам / Всё сам).
## Состояние показа (сортировка, открытый торг) — только на экране, в сейв не идёт; всё решает sim.sales.

static var sort_key := "sum"
static var _seen: Dictionary = {}      ## id -> true: карточка уже показывалась (анимируем только новые)
static var _hg: Dictionary = {}        ## id -> {"open": bool, "pk": 0..25 (%), "la": 0..3}

const MODES := ["manual", "small", "auto"]
const SORTS := ["sum", "lead", "risk", "left"]


## Подпись для окна: что изменилось — то и перестраиваем.
static func sig(sim: Sim) -> String:
	var parts: Array[String] = [sim.sales.mode, sort_key, str(int(sim.minute / 360.0)), str(sim.sales.paused)]
	for o: Dictionary in sim.sales.board:
		parts.append("%d%s" % [int(o["id"]), str(o.get("haggled", ""))])
	return ",".join(parts)


static func mode_name(m: String) -> String:
	return L.t({"manual": "Вручную", "small": "Мелочь сам", "auto": "Всё сам"}.get(m, m))


static func mode_hint(m: String) -> String:
	var sl := Sales
	match m:
		"manual":
			return L.t("Все заявки ложатся на доску — решаете вы: взять, поторговаться или отказать. Сбыт сам ничего не берёт.")
		"small":
			return L.t("Мелкие выгодные заявки (до %s и маржа от %d%%) сбыт берёт сам, если завод успеет. Остальные ложатся на доску.") % [Defs.money_str(sl.SMALL_SUM), int(round(sl.SMALL_MARGIN * 100.0))]
		_:
			return L.t("Сбыт сам решает по всем заявкам — по порогу маржи и риску из «В работе». Доска пустует.")


static func build(parent: Control, sim: Sim, refresh: Callable, toast: Callable) -> void:
	var sl := sim.sales
	# --- режим отдела сбыта
	var top := UITheme.card(12)
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(top)
	var tv := UITheme.vbox(8)
	top.add_child(tv)
	var mh := UITheme.hbox(10)
	var ml := UITheme.label(L.t("Отдел сбыта берёт заявки:"), 13, UITheme.MUTED)
	ml.tooltip_text = L.t("Режим работы сбыта. Переключается в любой момент: карточки на доске остаются, а при «Мелочь сам» и «Всё сам» сбыт сразу разберёт те, что вправе решить сам.")
	ml.mouse_filter = Control.MOUSE_FILTER_STOP
	mh.add_child(ml)
	var items: Array = []
	for m: String in MODES:
		items.append([m, mode_name(m), mode_hint(m)])
	mh.add_child(UITheme.segmented(items, sl.mode, func(k: String) -> void:
		sl.set_mode(k)
		toast.call(L.t("Режим сбыта: %s.") % mode_name(k), Sim.LVL_INFO)
		refresh.call(true)))
	tv.add_child(mh)
	var hint := UITheme.para(mode_hint(sl.mode), 12, UITheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(hint)
	if sl.paused:
		tv.add_child(UITheme.para(L.t("Приём заказов на паузе («В работе» → «Новые заказы: Не брать») — новые заявки не принимаются и на доску не ложатся."), 12, UITheme.WARN))
	elif sim.money < 0.0:
		tv.add_child(UITheme.para(L.t("Завод в долгах — новые заявки не принимаются, пока касса в минусе."), 12, UITheme.BAD))

	# --- карточки
	var cards: Array = sl.board.duplicate()
	_prune(cards)
	if cards.size() > 1:
		var sh := UITheme.hbox(8)
		var sc := UITheme.label(L.t("Сортировать:"), 12, UITheme.MUTED)
		sc.tooltip_text = L.t("Порядок карточек на доске.")
		sc.mouse_filter = Control.MOUSE_FILTER_STOP
		sh.add_child(sc)
		sh.add_child(UITheme.segmented([
			["sum", L.t("Сумма"), L.t("Сначала самые крупные заявки.")],
			["lead", L.t("Срок"), L.t("Сначала самые короткие сроки.")],
			["risk", L.t("Риск"), L.t("Сначала те, где больше риск не успеть.")],
			["left", L.t("Уйдёт"), L.t("Сначала те, что скоро уйдут к конкуренту.")]], sort_key, func(k: String) -> void:
			sort_key = k
			refresh.call(true)))
		parent.add_child(sh)
	if cards.is_empty():
		parent.add_child(UITheme.empty(L.t("Новых заявок нет — следующие придут утром.")))
	else:
		_sort(sim, cards)
		for o: Dictionary in cards:
			_card(parent, sim, o, refresh, toast)

	# --- журнал: что сбыт взял сам сегодня
	var auto_today: Array = sl.log.filter(func(e: Dictionary) -> bool: return bool(e["ok"]) and str(e.get("by", "")) == "sales" and int(e["day"]) == sim.day())
	if not auto_today.is_empty():
		parent.add_child(UITheme.caption(L.t("Журнал доски — сегодня")))
		auto_today.reverse()
		for e: Dictionary in auto_today.slice(0, 12):
			var row := UITheme.hbox(8)
			row.add_child(UITheme.icon_plate("handshake", 16, UITheme.GOOD, false))
			var txt := L.t("Сбыт взял сам: %s × %d — %s, %s") % [Defs.product_name(str(e["p"])), int(e["qty"]), L.name(str(e.get("client", ""))), Defs.money_str(float(e["sum"]))]
			var lb := UITheme.label(txt, 13, UITheme.TEXT)
			lb.tooltip_text = L.t("Эту заявку отдел сбыта взял без вас — по правилам выбранного режима. Она уже в «В работе».")
			lb.mouse_filter = Control.MOUSE_FILTER_STOP
			lb.clip_text = true
			lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lb)
			parent.add_child(row)


static func _prune(cards: Array) -> void:
	var ids := {}
	for o: Dictionary in cards:
		ids[int(o["id"])] = true
	for k in _seen.keys():
		if not ids.has(k):
			_seen.erase(k)
	for k2 in _hg.keys():
		if not ids.has(k2):
			_hg.erase(k2)


static func _sort(sim: Sim, cards: Array) -> void:
	var sl := sim.sales
	var key := {}
	for o: Dictionary in cards:
		var id := int(o["id"])
		match sort_key:
			"lead":
				key[id] = float(int(o.get("lead", 3)))
			"risk":
				var r := sl.board_risk(o)
				key[id] = -(float(r["level"]) * 1000.0 + minf(99.0, float(r["days"])) / maxf(1.0, float(int(o.get("lead", 3)))))
			"left":
				key[id] = float(o["expires"])
			_:
				key[id] = -(float(o["price"]) * int(o["qty"]))
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: float = key[int(a["id"])]
		var kb: float = key[int(b["id"])]
		if is_equal_approx(ka, kb):
			return int(a["id"]) < int(b["id"])
		return ka < kb)


static func _stat(cap: String, value: String, col: Color, tip: String, w: float = 96.0) -> VBoxContainer:
	var v := UITheme.vbox(0)
	v.custom_minimum_size = Vector2(w, 0)
	v.tooltip_text = tip
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var c := UITheme.label(cap, 11, UITheme.DIM)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(c)
	var l := UITheme.label(value, 15, col, UITheme.f_semi)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(l)
	return v


static func _word_chance(c: float) -> Array:
	if c >= 0.65:
		return [L.t("скорее согласится"), UITheme.GOOD]
	if c >= 0.3:
		return [L.t("может согласиться"), UITheme.WARN]
	return [L.t("вряд ли"), UITheme.BAD]


static func _card(parent: Control, sim: Sim, o: Dictionary, refresh: Callable, toast: Callable) -> void:
	var sl := sim.sales
	var id := int(o["id"])
	var p := str(o["product"])
	var qty := int(o["qty"])
	var price := float(o["price"])
	var total := price * qty
	var lead := int(o.get("lead", 3))
	var mg := sim.office.margin(o)
	var rk := sl.board_risk(o)
	var rcol: Color = [UITheme.GOOD, UITheme.WARN, UITheme.BAD][int(rk["level"])]
	var pname := Defs.product_name(p)
	var bottleneck := Defs.process_name(str(rk["proc"])).to_lower() if str(rk["proc"]) != "" else ""

	var card := UITheme.card(12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var row := UITheme.hbox(14)
	card.add_child(row)

	# значок изделия
	var ic := TextureRect.new()
	var tex := Tex.item(p)
	var isz := 52.0
	if Tex.is_color(tex):
		isz = roundf(isz * 1.2)
		tex = Tex.at(tex, isz)
	ic.texture = tex
	ic.custom_minimum_size = Vector2(isz, isz)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.tooltip_text = pname
	ic.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(ic)

	var mid := UITheme.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var th := UITheme.hbox(8)
	var tl := UITheme.label("%s × %d" % [pname, qty], 16, UITheme.TEXT, UITheme.f_semi)
	tl.tooltip_text = L.t("Изделие и количество в заявке.")
	tl.mouse_filter = Control.MOUSE_FILTER_STOP
	th.add_child(tl)
	var cl := UITheme.label(L.name(str(o["client"])), 13, UITheme.MUTED)
	cl.tooltip_text = L.t("Заказчик. Уйдёт к конкуренту, если заявку не решить вовремя.")
	cl.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.clip_text = true
	cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(cl)
	if bool(o.get("trial", false)):
		th.add_child(UITheme.chip(L.t("пробная партия"), UITheme.INFO, L.t("Срок вдвое больше, без неустойки.")))
	if str(o.get("haggled", "")) == "ok":
		th.add_child(UITheme.chip(L.t("условия согласованы"), UITheme.GOOD, L.t("Заказчик согласился на ваши условия. Торг — одна попытка на заявку.")))
	mid.add_child(th)

	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 18)
	fl.add_theme_constant_override("v_separation", 4)
	mid.add_child(fl)
	fl.add_child(_stat(L.t("СРОК"), "%d %s" % [lead, L.pl(lead, "день|дня|дней")], UITheme.TEXT,
		L.t("Срок на изготовление и отгрузку — в рабочих днях с момента, как возьмёте заявку. За просрочку — неустойка."), 70.0))
	fl.add_child(_stat(L.t("ЦЕНА"), Defs.money_str(price), UITheme.TEXT, L.t("Цена за штуку."), 86.0))
	fl.add_child(_stat(L.t("СУММА"), Defs.money_str(total), UITheme.TEXT, L.t("Сумма заявки целиком: цена × количество."), 110.0))
	var mcol := UITheme.BAD if mg < 0.05 else (UITheme.WARN if mg < 0.15 else UITheme.GOOD)
	fl.add_child(_stat(L.t("МАРЖА"), "%d%%" % int(round(mg * 100.0)), mcol,
		L.t("Какая доля цены останется после себестоимости (~%s за штуку). Красная — почти в ноль или в убыток, жёлтая — ниже 15%%, зелёная — выгодно.") % Defs.money_str(sim.office.unit_cost(p)), 70.0))
	var days := float(rk["days"])
	var dtxt := L.t("некому") if days >= 98.0 else L.t("%.1f дн.") % days
	fl.add_child(_stat(L.t("ЗАГРУЗКА"), dtxt, rcol,
		L.t("Сколько рабочих дней уйдёт на самом загруженном переделе (%s), если взять эту заявку вместе с тем, что уже в работе. Сравнивается со сроком.") % (bottleneck if bottleneck != "" else "—"), 90.0))
	var rtxt: String = [L.t("успеем"), L.t("впритык"), L.t("не успеем")][int(rk["level"])]
	fl.add_child(_stat(L.t("РИСК"), rtxt, rcol,
		L.t("Риск не успеть к сроку: зелёный — загрузка до 60% срока, жёлтый — впритык, красный — срыв и неустойка почти наверняка."), 90.0))

	# сколько ещё висит
	var left := sl.board_left(o)
	var lh := UITheme.hbox(8)
	var urgent := left < 0.6
	var lcol := UITheme.BAD if urgent else (UITheme.WARN if left < 1.1 else UITheme.MUTED)
	var ltxt := L.t("уйдёт к конкуренту через ~%s") % _left_str(left)
	var lt := UITheme.label(ltxt, 12, lcol)
	var ltip := L.t("Заявка висит на доске 1–2 игровых дня, потом заказчик уходит к конкуренту.")
	lt.tooltip_text = ltip
	lt.mouse_filter = Control.MOUSE_FILTER_STOP
	lh.add_child(lt)
	var lb := UITheme.bar(clampf(left / 2.0, 0.0, 1.0) * 100.0, lcol, 90.0, 6.0)
	lb.tooltip_text = ltip
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(lb)
	mid.add_child(lh)

	# кнопки
	var bv := UITheme.vbox(6)
	bv.custom_minimum_size = Vector2(130, 0)
	bv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bv)
	var tried := str(o.get("haggled", "")) != ""
	var hs: Dictionary = _hg.get(id, {"open": false, "pk": 10, "la": 0})
	_hg[id] = hs

	var b_take := UITheme.primary(L.t("Взять"), Callable(), L.t("Принять заявку на этих условиях. Порог маржи и риск вы решаете сами — сбыт не возражает, но без оборудования заявку не взять."))
	var b_hag := UITheme.button(L.t("Торговаться"), Callable(), L.t("Попросить заказчика поднять цену и/или дать больше времени. Одна попытка: не согласится — уйдёт к конкуренту.") if not tried else L.t("Торг уже был — одна попытка на заявку."))
	b_hag.disabled = tried
	var b_no := UITheme.button(L.t("Отказать"), Callable(), L.t("Отказать заказчику. Заявка уйдёт в журнал отказов."))
	for b: Button in [b_take, b_hag, b_no]:
		b.custom_minimum_size = Vector2(130, 30)
		bv.add_child(b)

	var leave := func(msg: String, lvl: int) -> void:
		if msg != "":
			toast.call(msg, lvl)
		_fade_out(card, refresh)
	b_take.pressed.connect(func() -> void:
		var why := sl.take(id)
		if why != "":
			toast.call(why, Sim.LVL_WARN)
			refresh.call(true)
			return
		leave.call(L.t("Заявка взята: %s × %d, %s.") % [pname, qty, Defs.money_str(float(sl.log.back()["sum"]))], Sim.LVL_GOOD))
	b_no.pressed.connect(func() -> void:
		sl.refuse(id)
		leave.call(L.t("Отказали заказчику: %s × %d.") % [pname, qty], Sim.LVL_INFO))
	b_hag.pressed.connect(func() -> void:
		hs["open"] = not bool(hs["open"])
		refresh.call(true))

	if bool(hs["open"]) and not tried:
		_haggle_panel(parent, sim, o, hs, refresh, toast, card)

	# появление (только у новых карточек) — неброско
	if not _seen.has(id):
		_seen[id] = true
		if card.is_inside_tree():
			card.modulate.a = 0.0
			card.create_tween().tween_property(card, "modulate:a", 1.0, 0.25)


static func _left_str(left: float) -> String:
	if left >= 1.0:
		return L.t("%.1f сут.") % left
	return L.t("%d ч") % maxi(1, int(round(left * 24.0)))


## Карточка исчезает плавно; после — перерисовка окна.
static func _fade_out(card: Control, refresh: Callable) -> void:
	for n in card.find_children("*", "Button", true, false):
		(n as Button).disabled = true
	if card.is_inside_tree():
		var tw := card.create_tween()
		tw.tween_property(card, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void: refresh.call(true))
	else:
		refresh.call(true)


static func _haggle_panel(parent: Control, sim: Sim, o: Dictionary, hs: Dictionary, refresh: Callable, toast: Callable, card: Control) -> void:
	var sl := sim.sales
	var id := int(o["id"])
	var pc := UITheme.card(10, UITheme.BG3)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(pc)
	var v := UITheme.vbox(6)
	pc.add_child(v)
	v.add_child(UITheme.caption(L.t("Торг") + " — " + Defs.product_name(str(o["product"])) + " × " + str(int(o["qty"]))))
	var price := float(o["price"])
	var lead := int(o.get("lead", 3))
	var pl := UITheme.label("", 13, UITheme.TEXT)
	var ll := UITheme.label("", 13, UITheme.TEXT)
	var cw := UITheme.label("", 13, UITheme.TEXT, UITheme.f_semi)
	var cb := UITheme.bar(0.0, UITheme.WARN, 160.0, 8.0)
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var upd := func() -> void:
		var pk := float(hs["pk"]) / 100.0
		var la := int(hs["la"])
		pl.text = L.t("Цена: +%d%% → %s за штуку") % [int(hs["pk"]), Defs.money_str(round(price * (1.0 + pk) / 10.0) * 10.0)]
		ll.text = L.t("Срок: +%d дн. → %d дн.") % [la, lead + la]
		var c := sl.haggle_chance(o, pk, la)
		var w := _word_chance(c)
		cw.text = str(w[0])
		cw.add_theme_color_override("font_color", w[1] as Color)
		cb.value = c * 100.0
		cb.add_theme_stylebox_override("fill", UITheme.sb(w[1] as Color, w[1] as Color, 0, 3, 0, 0))
	var mk := func(mx: int, step: int, key: String, lab: Label, tip: String) -> HBoxContainer:
		var h := UITheme.hbox(10)
		lab.custom_minimum_size = Vector2(280, 0)
		lab.tooltip_text = tip
		lab.mouse_filter = Control.MOUSE_FILTER_STOP
		h.add_child(lab)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = mx
		s.step = step
		s.value = int(hs[key])
		s.custom_minimum_size = Vector2(200, 20)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.tooltip_text = tip
		s.value_changed.connect(func(x: float) -> void:
			hs[key] = int(x)
			upd.call())
		h.add_child(s)
		return h
	v.add_child(mk.call(int(Sales.HAGGLE_PRICE_MAX * 100.0), 5, "pk", pl, L.t("Насколько поднять цену: от 0 до +25%. Чем больше просите, тем меньше шанс; на дорогом рынке заказчики упрямее.")))
	v.add_child(mk.call(Sales.HAGGLE_LEAD_MAX, 1, "la", ll, L.t("Сколько дней добавить к сроку: от 0 до +3. Время даёт запас, но заказчик не любит ждать.")))
	var ch := UITheme.hbox(10)
	var cl := UITheme.label(L.t("Шанс согласия:"), 13, UITheme.MUTED)
	cl.tooltip_text = L.t("Оценка: как заказчик ответит на такое предложение. Исход всё равно случайный.")
	cl.mouse_filter = Control.MOUSE_FILTER_STOP
	ch.add_child(cl)
	ch.add_child(cw)
	ch.add_child(cb)
	var go := UITheme.primary(L.t("Предложить"), func() -> void:
		var res := sl.haggle(id, float(hs["pk"]) / 100.0, int(hs["la"]))
		if res == "ok":
			hs["open"] = false
			toast.call(L.t("Заказчик согласился на новые условия — заявку можно брать."), Sim.LVL_GOOD)
			refresh.call(true)
		elif res == "no":
			toast.call(L.t("Заказчик отказался торговаться и ушёл к конкуренту."), Sim.LVL_WARN)
			_fade_out(card, refresh)
		else:
			toast.call(L.t("Предложите хоть что-то: поднимите цену или добавьте срок."), Sim.LVL_INFO)
		, L.t("Назвать условия. Одна попытка на заявку."))
	var cn := UITheme.button(L.t("Отмена"), func() -> void:
		hs["open"] = false
		refresh.call(true))
	ch.add_child(go)
	ch.add_child(cn)
	v.add_child(ch)
	upd.call()
