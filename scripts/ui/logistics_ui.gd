class_name LogisticsUI
extends RefCounted
## 1.40: окно «Логистика быта». Для каждого цеха — какую бытовку, душевую, туалет, столовую и комнату отдыха
## он использует; для ИТР и конторы — куда ходят обедать, в туалет и отдыхать; какие столовые — только для ИТР.
## «Ближайшее» — по умолчанию, как раньше. Открывается из карточки зоны (кнопка «Логистика быта…»).

const KIND_NAMES := {"locker": "Бытовка", "shower": "Душевая", "wc": "Туалет", "canteen": "Столовая", "restroom": "Комната отдыха"}


static func open(hud: Hud, sim: Sim) -> void:
	var v := hud._open_modal(640)
	v.add_child(UITheme.title(L.t("Логистика быта"), 20))
	v.add_child(UITheme.para(L.t("Какой цех к какой бытовке, туалету и столовой относится и куда ходят ИТР. «Ближайшее» — люди идут туда, что ближе. ИТР и конторе раздевалка не нужна: они работают в своём."), 13, UITheme.MUTED))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(600, 380)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := UITheme.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	v.add_child(sc)
	var shops := sim.areas.rooms_of("workshop")
	if shops.is_empty():
		body.add_child(UITheme.empty(L.t("Цехов пока нет: разметьте зону «Цех».")))
	var n := 0
	for shop in shops:
		n += 1
		var card := UITheme.card(10)
		var cv := UITheme.vbox(6)
		card.add_child(cv)
		cv.add_child(UITheme.label(L.t("Цех №%d · %d кл.") % [n, shop.area()], 15, UITheme.TEXT, UITheme.f_semi))
		var anchor := shop.cells[0]
		for kind: String in Areas.KINDS:
			cv.add_child(_row(sim, kind, sim.areas.link_of(shop, kind), func(r: Rooms.Room) -> void:
				var cur := sim.rooms.room_at(anchor)
				if cur:
					sim.areas.set_link(cur, kind, r)))
		body.add_child(card)
	# ИТР
	var ic := UITheme.card(10)
	var iv := UITheme.vbox(6)
	ic.add_child(iv)
	iv.add_child(UITheme.label(L.t("ИТР и контора (директор, бухгалтерия, отделы)"), 15, UITheme.TEXT, UITheme.f_semi))
	for kind2: String in Areas.ITR_KINDS:
		iv.add_child(_row(sim, kind2, sim.areas.itr_of(kind2), func(r: Rooms.Room) -> void: sim.areas.set_itr(kind2, r)))
	var cants := sim.areas.rooms_of("canteen")
	if not cants.is_empty():
		iv.add_child(UITheme.label(L.t("Столовая только для ИТР (рабочие туда не ходят):"), 13, UITheme.MUTED))
		var k := 0
		for c in cants:
			k += 1
			var cb := CheckBox.new()
			cb.text = _room_title(sim, c, k)
			cb.focus_mode = Control.FOCUS_NONE
			cb.button_pressed = sim.areas.is_itr_canteen(c)
			var ca := c.cells[0]
			cb.toggled.connect(func(on: bool) -> void:
				var cur := sim.rooms.room_at(ca)
				if cur:
					sim.areas.set_itr_canteen(cur, on))
			iv.add_child(cb)
	body.add_child(ic)
	var bh := UITheme.hbox(8)
	bh.add_child(UITheme.spacer())
	bh.add_child(UITheme.primary(L.t("Готово"), hud.close_modal))
	v.add_child(bh)


static func _room_title(sim: Sim, r: Rooms.Room, k: int) -> String:
	return L.t("%s №%d (%d кл.%s)") % [r.title(), k, r.area(), "" if r.valid else L.t(", не оборудована")]


## Строка «вид: [выпадающий список]». Пустой выбор — ближайшее.
static func _row(sim: Sim, kind: String, cur: Rooms.Room, pick: Callable) -> Control:
	var h := UITheme.hbox(8)
	var l := UITheme.label(L.t(str(KIND_NAMES[kind])), 13, UITheme.TEXT)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", 13)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_item(L.t("— ближайшее —"))
	var rooms := sim.areas.rooms_of(kind)
	var sel := 0
	for i in rooms.size():
		ob.add_item(_room_title(sim, rooms[i], i + 1))
		if cur != null and rooms[i].id == cur.id:
			sel = i + 1
	ob.select(sel)
	if rooms.is_empty():
		ob.disabled = true
		ob.tooltip_text = L.t("Таких зон пока нет")
	var anchors: Array[Vector2i] = []
	for r in rooms:
		anchors.append(r.cells[0])
	ob.item_selected.connect(func(i: int) -> void:
		pick.call(null if i == 0 else sim.rooms.room_at(anchors[i - 1])))
	h.add_child(ob)
	return h
