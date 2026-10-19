class_name WorkerPop
extends PanelContainer
## 1.21: щелчок по человеку на карте — маленькое меню прямо над ним, как у объектов:
## кто это, чем занят, настроение и две кнопки — «Взять под управление» и «Открыть карточку».
## Полная карточка открывается только по кнопке (или из окна «Люди»).
## 1.29: меню встаёт над человеком в момент щелчка и дальше стоит на месте — не убегает вместе с ним,
## по кнопкам легко попасть даже на большой скорости.

var hud: Hud
var wid := -1
var _name: Label
var _act: Label
var _mood: ProgressBar
var _mood_l: Label
var _ctl_b: Button
var _por: Portrait
var _t := 0.0


func setup(h: Hud) -> void:
	hud = h
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.sbs(Color(0.106, 0.108, 0.112, 0.97), UITheme.LINE2, 1, 10, 10, 8, 14, 0.55, 4))
	var v := UITheme.vbox(6)
	add_child(v)
	var top := UITheme.hbox(8)
	_por = Portrait.new()
	_por.set_look({}, 0.62)
	_por.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_por)
	var col := UITheme.vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name = UITheme.label("", 14, UITheme.TEXT, UITheme.f_semi)
	col.add_child(_name)
	_act = UITheme.label("", 12, UITheme.MUTED)
	_act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_act.custom_minimum_size = Vector2(170, 0)
	col.add_child(_act)
	var mh := UITheme.hbox(6)
	_mood = UITheme.bar(50.0, UITheme.GOOD, 90.0, 7.0)
	_mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh.add_child(_mood)
	_mood_l = UITheme.label("", 11, UITheme.MUTED)
	mh.add_child(_mood_l)
	col.add_child(mh)
	top.add_child(col)
	var cx := UITheme.ghost("×", close, "Закрыть (Esc)", UITheme.MUTED)
	cx.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(cx)
	v.add_child(top)
	var bh := UITheme.hbox(6)
	_ctl_b = UITheme.primary("Взять под управление", _toggle_ctl, "Человек бросит своё и сделает то, что вы покажете щелчком")
	_ctl_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_ctl_b)
	var ob := UITheme.button("Открыть карточку", _open_card, "Полная карточка: навыки, настроение, история")
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(ob)
	v.add_child(bh)


func show_for(w: Worker) -> void:
	wid = w.id
	_por.set_look(w.look, 0.62, PortraitKit.live_info(hud.sim, w))
	_name.text = "%s · %s" % [w.full_name(), w.prof_name()]
	_t = 0.0
	visible = true
	_refresh()
	reset_size()
	_follow()


func close() -> void:
	visible = false
	wid = -1


func _w() -> Worker:
	return hud.sim.get_worker(wid) if wid >= 0 else null


func _toggle_ctl() -> void:
	var w := _w()
	if w == null:
		close()
		return
	if w.controlled:
		hud.ctl.release()
	else:
		hud.ctl.take(w)
	_refresh()


func _open_card() -> void:
	var w := _w()
	close()
	if w:
		hud.info.near_screen = Vector2(-1, -1)
		hud.info.show_worker(hud.sim, w)


func _refresh() -> void:
	var w := _w()
	if w == null or not w.present:
		close()
		return
	_act.text = w.activity if w.activity != "" else "—"
	_mood.value = w.mood
	_mood.add_theme_stylebox_override("fill", UITheme.sb(UITheme.ramp(w.mood / 100.0), UITheme.ramp(w.mood / 100.0), 0, 3, 0, 0))
	_mood_l.text = "настроение %d" % int(w.mood)
	_ctl_b.text = "Отпустить" if w.controlled else "Взять под управление"
	var blk := hud.sim.brain.order_block(w)
	_ctl_b.disabled = blk != "" and not w.controlled
	_ctl_b.tooltip_text = ("Нельзя: " + blk) if _ctl_b.disabled else "Человек бросит своё и сделает то, что вы покажете щелчком"


## Над головой человека; у края экрана — прижимается внутрь.
func _follow() -> void:
	var w := _w()
	if w == null:
		return
	var xf := hud.g.get_viewport().get_canvas_transform()
	var p := xf * (w.pos * World.T)
	var z := hud.g.cam.zoom.x
	var sz := get_combined_minimum_size()
	var vs := get_viewport_rect().size
	var pos := Vector2(p.x - sz.x * 0.5, p.y - 40.0 * z - sz.y - 6.0)
	if pos.y < 60.0:
		pos.y = p.y + 14.0 * z
	position = Vector2(clampf(pos.x, 8.0, vs.x - sz.x - 66.0), clampf(pos.y, 60.0, vs.y - sz.y - 100.0))


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_refresh()
