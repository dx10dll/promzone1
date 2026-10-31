class_name WorkerBubbles
extends Node2D
## 1.50d: облачка-мысли над людьми (как в Prison Architect). Один слой на всех: никаких узлов на человека.
## Размер на экране постоянный при любом зуме; проблемы и желания видны всегда (жёлтая/красная обводка),
## 1.51: сами всплывают только красные; желания и действия — у выбранного и под мышью (Game.settings["worker_bubbles"]: auto|all|off).
## Выбор значка считается четыре раза в секунду (BubbleLogic.pick), смена — не чаще раза в 2 с, появление и
## исчезновение плавные. По наведению на человека или облачко — подсказка словами.

const T := World.T
const HEAD := 34.0          ## высота головы над стопой, мировых пикселей
const MIN_ZOOM := 0.3
const TICK := 0.25
const FADE := 5.0           ## скорость появления, 1/с

var sim: Sim
var game: Node
var mouse_override := Vector2(INF, INF)   ## для снимков: «мышь» стоит здесь
var force_mode := ""                       ## для снимков и тестов: auto|all|off поверх настроек
var _st: Dictionary = {}                   ## id человека -> {k, t, since, a, u}
var _clock := 0.0
var _acc := 0.0
var _workers: Dictionary = {}              ## id -> Worker (для подсказки)
var _crowd := 0
var _hov := -1
var _hov_bubble := false
var _busy := true


func _ready() -> void:
	z_index = 6


func mode() -> String:
	if force_mode != "":
		return force_mode
	var gn: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")   # без прямой ссылки: слой собирается и в тестах
	var st: Variant = gn.get("settings") if gn else null
	return str((st as Dictionary).get("worker_bubbles", "auto")) if st is Dictionary else "auto"


func _zoom() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(0.05, get_viewport().get_canvas_transform().get_scale().x)


## Видимая часть мира (с запасом); вне дерева — весь мир.
func _view_rect(pad: float) -> Rect2:
	if not is_inside_tree():
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	return (get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(pad)


func state_of(id: int) -> Dictionary:
	return _st.get(id, {})


## Пересчитать выбор значков (раз в TICK, либо принудительно — для тестов).
func refresh(dt: float) -> void:
	_clock += dt
	var seen: Dictionary = {}
	var z := _zoom()
	var vr := _view_rect(60.0 / z)
	_crowd = 0
	for w: Worker in sim.workers + sim.visitors:
		if not BubbleLogic.relevant(w):
			continue
		var wp := w.vpos() * T
		if vr.has_point(wp):
			_crowd += 1
		var cand := BubbleLogic.pick(sim, w)
		var st: Dictionary = _st.get(w.id, {"k": "", "t": 0, "since": -99.0, "a": 0.0, "u": 0.0})
		BubbleLogic.step(st, cand, _clock)
		st["u"] = float(cand["u"]) if str(st["k"]) == str(cand["k"]) else float(st.get("u", 0.0))
		_st[w.id] = st
		_workers[w.id] = w
		seen[w.id] = true
	for id: int in _st.keys():
		if not seen.has(id):
			# человек ушёл: значок гаснет и забывается
			var s2: Dictionary = _st[id]
			s2["k"] = ""
			s2["t"] = 0
			if float(s2["a"]) <= 0.01:
				_st.erase(id)
				_workers.erase(id)


func _process(d: float) -> void:
	if sim == null:
		return
	_acc += d
	if _acc >= TICK:
		refresh(_acc)
		_acc = 0.0
	else:
		_clock += d
	var z := _zoom()
	var mp := get_global_mouse_position() if mouse_override.x == INF else mouse_override
	var sel := _sel_id()
	var hov := -1
	var hb := false
	var md := mode()
	var busy := false
	for id: int in _st.keys():
		var st: Dictionary = _st[id]
		var w: Worker = _workers.get(id)
		if w == null:
			continue
		var anchor := _anchor(w)
		var on := str(st["k"]) != ""
		var body := Rect2(anchor + Vector2(-9.0, 0.0), Vector2(18.0, HEAD)) .grow(3.0 / z)
		var is_hov := body.has_point(mp)
		var show := on and z >= MIN_ZOOM and BubbleLogic.shown(int(st["t"]), id == sel, is_hov or hov == id, _crowd, md)
		if show and float(st["a"]) > 0.4 and _bubble_rect(anchor, z).grow(2.0 / z).has_point(mp):
			hov = id
			hb = true
		elif is_hov and hov < 0:
			hov = id
		var target := 1.0 if show else 0.0
		var a := float(st["a"])
		if a != target:
			a = move_toward(a, target, d * FADE)
			st["a"] = a
		if a > 0.0:
			busy = true
	# по наведению показываем и действие (обновим цели ещё раз, чтобы не ждать кадр)
	if hov != _hov or hb != _hov_bubble:
		_hov = hov
		_hov_bubble = hb
		busy = true
	# 1.56: когда последнее облачко догасло, перерисовываем ещё раз — иначе на экране оставался
	# прошлый кадр и облачко «висело в воздухе», пока человек уходил
	if busy or _busy:
		queue_redraw()
	_busy = busy


func _sel_id() -> int:
	var tool: Node = game.get("tool") if game else null
	return int(tool.get("sel_id")) if tool and str(tool.get("sel_kind")) == "worker" else -999999


func _anchor(w: Worker) -> Vector2:
	var vp := w.vpos()
	return Vector2(vp.x * T, vp.y * T + 6.0 - HEAD)


## Прямоугольник облачка в мировых координатах (кончик хвостика — на голове).
func _bubble_rect(anchor: Vector2, z: float) -> Rect2:
	var k := 1.0 / z
	return Rect2(anchor + Vector2(-BubbleArt.W * 0.5, -BubbleArt.H - 1.0) * k, Vector2(BubbleArt.W, BubbleArt.H) * k)


func _draw() -> void:
	if sim == null or not _busy:
		return
	var z := _zoom()
	var k := 1.0 / z
	var vr := _view_rect(60.0 * k)
	var tip_w: Worker = null
	for id: int in _st.keys():
		var st: Dictionary = _st[id]
		var a := float(st["a"])
		if a <= 0.01 or str(st["k"]) == "":
			continue
		var w: Worker = _workers.get(id)
		if w == null:
			continue
		var anchor := _anchor(w)
		if not vr.has_point(anchor):
			continue
		if id == _hov:
			tip_w = w
			continue
		_one(anchor, st, a, k, 1.0)
	if tip_w != null and _st.has(tip_w.id):
		var hs: Dictionary = _st[tip_w.id]
		if float(hs["a"]) > 0.01 and str(hs["k"]) != "":
			var an := _anchor(tip_w)
			_one(an, hs, float(hs["a"]), k, 1.14)
			_tip(an, tip_w, hs, k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _one(anchor: Vector2, st: Dictionary, a: float, k: float, grow: float) -> void:
	var t := BubbleArt.tex(str(st["k"]), int(st["t"]))
	if t == null:
		return
	var pulse := 1.0 + (0.035 * sin(_clock * 6.0) if int(st["t"]) >= BubbleLogic.T_BAD else 0.0)
	var s := grow * pulse
	var rise := (1.0 - a) * 6.0   # при появлении слегка «всплывает»
	draw_set_transform(anchor + Vector2(0.0, -1.0 * k + rise * k), 0.0, Vector2(k, k) * s)
	draw_texture_rect(t, Rect2(Vector2(-BubbleArt.W * 0.5, -BubbleArt.H), Vector2(BubbleArt.W, BubbleArt.H)), false, Color(1, 1, 1, a))


func _tip(anchor: Vector2, w: Worker, st: Dictionary, k: float) -> void:
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var kd := str(st["k"])
	var tr := BubbleLogic.tip(sim, w, kd, int(st["t"]))
	var col := Color(BubbleArt.COLS[clampi(int(st["t"]), 1, 3)]) if int(st["t"]) > 1 else Color("#9fb3c4")
	var head := str(tr["head"])
	var why := str(tr["why"])
	var who := w.short_name()
	var px := 11
	var tw := f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, px + 1).x
	tw = maxf(tw, f.get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	tw = maxf(tw, f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	var wd := minf(tw, 280.0) + 16.0
	var lines := 2 + (1 if why != "" else 0)
	var h := 8.0 + 15.0 * lines + 2.0
	# справа от облачка, чтобы не закрывать голову и соседей
	draw_set_transform(anchor + Vector2(BubbleArt.W * 0.5 + 6.0, -BubbleArt.H * 0.9) * k, 0.0, Vector2(k, k))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.07, 0.94)
	bg.border_color = Color(col, 0.85)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	draw_style_box(bg, Rect2(0, 0, wd, h))
	draw_string(f, Vector2(8, 15), head, HORIZONTAL_ALIGNMENT_LEFT, 280, px + 1, col.lightened(0.25))
	var y := 30.0
	if why != "":
		draw_string(f, Vector2(8, y), why, HORIZONTAL_ALIGNMENT_LEFT, 280, px, Color(0.93, 0.9, 0.82))
		y += 15.0
	draw_string(f, Vector2(8, y), who, HORIZONTAL_ALIGNMENT_LEFT, 280, px, Color(0.7, 0.72, 0.72))
