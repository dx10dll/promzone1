class_name ControlUI
extends Control
## 1.19: «Под управлением». Плашка сверху — кто под управлением и что делать; меню «Сделать сейчас»
## у курсора — что этот человек может сделать в клетке (строить, проложить сеть, встать за станок,
## отнести груз, идти). Сама логика — в Brain (take_control, order_options, give_order).

var hud: Hud
var banner: PanelContainer
var b_name: Label
var b_act: Label
var menu: PanelContainer = null
var _t := 0.0
var _last_id := -1


func setup(h: Hud) -> void:
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner = PanelContainer.new()
	var st := UITheme.sbs(Color(0.11, 0.1, 0.07, 0.96), UITheme.ACCENT, 2, 10, 14, 8, 10, 0.45, 4)
	banner.add_theme_stylebox_override("panel", st)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 1.0
	banner.anchor_bottom = 1.0
	banner.offset_top = -112
	banner.offset_bottom = -112
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := UITheme.hbox(12)
	var ic := TextureRect.new()
	ic.texture = Tex.ui("control")
	ic.custom_minimum_size = Vector2(30, 30)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := UITheme.vbox(2)
	b_name = UITheme.label("", 15, UITheme.ACCENT, UITheme.f_semi)
	col.add_child(b_name)
	var how := UITheme.label("Щёлкните по стройке, станку, грузу или месту на полу — выберите «Сделать сейчас»", 13, UITheme.TEXT)
	col.add_child(how)
	b_act = UITheme.label("", 12, UITheme.MUTED)
	col.add_child(b_act)
	row.add_child(col)
	var show := UITheme.button("Показать", func() -> void:
		var w := _w()
		if w:
			hud.g.cam.focus_cell(w.cell())
			hud.g.tool.select_worker(w.id), "Камера на человека")
	show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(show)
	var rel := UITheme.primary("Отпустить", release, "Вернуть к обычной работе (Esc)")
	rel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rel)
	banner.add_child(row)
	banner.visible = false
	add_child(banner)


func _w() -> Worker:
	return hud.sim.brain.controlled_worker()


func active() -> bool:
	return _w() != null


func release() -> void:
	var w := _w()
	if w:
		hud.sim.brain.release_control(w)
		hud.toast("%s вернулся к обычной работе." % w.full_name() if not w.female else "%s вернулась к обычной работе." % w.full_name(), Sim.LVL_INFO, 3.0)
	close_menu()
	_refresh()


func take(w: Worker) -> void:
	var txt := hud.sim.brain.take_control(w)
	hud.toast(txt, Sim.LVL_GOOD if w.controlled else Sim.LVL_WARN, 5.0)
	_refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.2
	var w := _w()
	if w and hud.sim.brain.order_block(w) != "":
		# ушёл домой, заболел — управление снимается само
		hud.toast("%s: %s — управление снято." % [w.full_name(), hud.sim.brain.order_block(w)], Sim.LVL_INFO, 4.0)
		hud.sim.brain.release_control(w)
	_refresh()


func _refresh() -> void:
	var w := _w()
	banner.visible = w != null
	if w == null:
		close_menu()
		_last_id = -1
		return
	b_name.text = "Под управлением: %s · %s" % [w.full_name(), w.prof_name()]
	b_act.text = "Сейчас: " + (w.activity if w.activity != "" else "ждёт команды")
	_last_id = w.id


## Щелчок по карте, пока человек под управлением: меню «Сделать сейчас».
func on_map_click(c: Vector2i, screen: Vector2) -> void:
	var w := _w()
	if w == null:
		return
	close_menu()
	var opts := hud.sim.brain.order_options(w, c)
	if opts.is_empty():
		hud.toast("Сюда %s не пройти и делать здесь нечего." % w.first, Sim.LVL_WARN, 3.0)
		return
	menu = PanelContainer.new()
	menu.add_theme_stylebox_override("panel", UITheme.sbs(UITheme.BG, UITheme.ACCENT, 1, 8, 10, 8, 12, 0.5, 4))
	var col := UITheme.vbox(6)
	col.add_child(UITheme.label("%s — что сделать?" % w.short_name(), 13, UITheme.MUTED, UITheme.f_semi))
	var first := true
	for o: Dictionary in opts:
		var key := str(o["key"])
		var cb := func() -> void:
			var txt := hud.sim.brain.give_order(w, c, key)
			hud.toast(txt, Sim.LVL_GOOD if not w.order.is_empty() else Sim.LVL_WARN, 3.5)
			close_menu()
		var b: Button
		if bool(o["ok"]) and first and key != "go":
			b = UITheme.primary(str(o["label"]), cb)
			first = false
		else:
			b = UITheme.button(str(o["label"]), cb)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not bool(o["ok"])
		col.add_child(b)
		if not bool(o["ok"]) and str(o["why"]) != "":
			var why := UITheme.label("   " + str(o["why"]), 11, UITheme.WARN)
			col.add_child(why)
	col.add_child(UITheme.ghost("Отмена", close_menu, "", UITheme.MUTED))
	menu.add_child(col)
	add_child(menu)
	menu.reset_size()
	var vs := get_viewport_rect().size
	var sz := menu.get_combined_minimum_size()
	menu.position = Vector2(clampf(screen.x + 14.0, 8.0, vs.x - sz.x - 8.0), clampf(screen.y - 10.0, 64.0, vs.y - sz.y - 100.0))


func close_menu() -> void:
	if menu and is_instance_valid(menu):
		menu.queue_free()
	menu = null


func menu_open() -> bool:
	return menu != null and is_instance_valid(menu)
