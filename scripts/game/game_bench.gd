class_name GameBench
extends Node
## 1.40: замер кадров в игре на большом заводе: `Promzona -- --bench-game=<сек> [--bench-people=<n>]`.
## Показательный завод из фона меню, людей добавляется до n (по умолчанию 90), все в первой смене; 10:00 рабочего дня.
## Фазы: скорость ×1, затем 3-я скорость (×4); в каждой — средний кадр, 1% худших (p99) и 0,1%, логика, симуляция,
## вызовы отрисовки; затем «кто сколько стоит»: _process каждого класса узлов (бенч вызывает его сам, под таймером)
## и отрисовка слоёв (слой на время прячется — разница кадра). Печатает строки BENCH и выходит. Без флага не работает.

const SKIP := ["GameMain", "GameBench", "Portrait"]   ## их _process не оборачиваем

var seconds := 60.0
var people := 90
var gm: GameMain = null
var _phase := "start"
var _t := 0.0
var _last := 0
var _ft: PackedFloat32Array = []
var _proc := 0.0
var _sim := 0.0
var _calls := 0.0
var _n := 0
var _wrapped: Array[Node] = []
var _cost: Dictionary = {}       ## класс → мкс за фазу
var _count: Dictionary = {}      ## класс → узлов
var _scan_t := 0.0
var _abl: Array = []             ## [имя, узлы]
var _abl_i := -1
var _abl_base := 0.0
var _results: Array = []
var _shot := ""


func _ready() -> void:
	process_priority = 1000   # после GameMain: слои рисуют уже посчитанный шаг, как в игре
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench-game="):
			seconds = maxf(12.0, float(a.substr(13)))
		elif a.begins_with("--bench-shot="):
			_shot = a.substr(13)
		elif a.begins_with("--bench-people="):
			people = clampi(int(a.substr(15)), 10, 400)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_start.call_deferred()


## Большой завод: показательный «Горизонт» + люди до `people`, все в первой смене, утро промотано до 10:00.
static func build_plant(n: int) -> Sim:
	var sim := MenuScenes.build()
	var profs := [["laborer", "haul"], ["turner", "turning"], ["miller", "milling"], ["welder", "welding"], ["assembler", "assembly"],
		["laborer", "haul"], ["qc", "qc"], ["cleaner", "clean"], ["painter", "paint"], ["builder", "build"]]
	var k := 0
	while sim.workers.size() < n:
		var p: Array = profs[k % profs.size()]
		var wk := People.make(sim.rng, str(p[0]))
		wk.skills[str(p[1])] = 5
		wk.traits = []
		wk.wage = People.wage_for(wk)
		sim.add_worker(wk)
		k += 1
	for w in sim.workers:
		w.shift = 0
	Workplace.auto_assign(sim)
	MenuScenes.advance_to(sim, MenuScenes.next_minute(sim.minute, 10.0 * 60.0), 4000)
	sim.events.clear()
	return sim


func _start() -> void:
	for i in 10:
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	Game.settings["tutorial_done"] = true
	Game.settings["autosave"] = false
	Game.settings["pause_on_event"] = false
	Game.pending_sim = build_plant(people)
	print("BENCH завод: людей %d, объектов %d, предметов %d, сборка %d мс" % [Game.pending_sim.workers.size(),
		Game.pending_sim.things.size(), Game.pending_sim.items.size(), Time.get_ticks_msec() - t0])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	for i in 5:
		await get_tree().process_frame
	gm = get_tree().current_scene as GameMain
	if gm == null:
		print("BENCH ошибка: нет игровой сцены")
		get_tree().quit(1)
		return
	var z := 0.9
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench-zoom="):
			z = float(a.substr(13))
	gm.cam.zoom = Vector2(z, z)
	gm.cam.position = Vector2(26.0, 14.0) * World.T
	gm.set_speed(1)
	_phase = "warm"
	_t = 0.0
	_last = Time.get_ticks_usec()


func _process(delta: float) -> void:
	if gm == null or _phase == "start" or _phase == "done":
		return
	var now := Time.get_ticks_usec()
	var ft := (now - _last) / 1000.0
	_last = now
	_t += ft / 1000.0
	if gm.menu_paused:   # окно или письмо на старте — замер идёт с работающим заводом
		print("BENCH окно на старте закрыто (модальное: %s, письмо: %s)" % [gm.hud.modal_open(), gm.hud.letter_box != null])
		gm.hud.close_modal()
		gm.menu_paused = false
	_run_wrapped(delta)
	_scan_t -= ft / 1000.0
	if _scan_t <= 0.0:
		_scan_t = 0.5
		_scan(gm)
	if _phase != "warm":
		_ft.append(ft)
		_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_sim += gm.sim_ms
		_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_n += 1
	var span := seconds * 0.35
	match _phase:
		"warm":
			if _shot != "":   # снимок с диагностикой F3 на большом заводе
				if _t < 4.0:
					return
				_phase = "shot"
				gm._toggle_fps()
				for i in 12:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(_shot)
				print("BENCH снимок: ", _shot)
				get_tree().quit()
				_phase = "done"
				return
			if _t >= minf(6.0, seconds * 0.1):
				_next("x1")
		"x1":
			if _t >= span:
				_report("×1")
				gm.set_speed(3)
				_next("x4")
		"x4":
			if _t >= span:
				_report("×4")
				gm.set_speed(1)
				_abl = _ablation_sets()
				_abl_i = -1
				_next("abl")
		"abl":
			if _t >= maxf(1.0, seconds * 0.3 / float(_abl.size() * 2 + 1)) and _n >= 4:
				_abl_step()


func _next(ph: String) -> void:
	_phase = ph
	_t = 0.0
	_ft.clear()
	_proc = 0.0
	_sim = 0.0
	_calls = 0.0
	_n = 0
	_cost.clear()


func _avg() -> float:
	var s := 0.0
	for f in _ft:
		s += f
	return s / maxf(1.0, float(_ft.size()))


func _pct(p: float) -> float:
	var a := _ft.duplicate()
	a.sort()
	if a.is_empty():
		return 0.0
	return a[clampi(int(ceil(a.size() * p)) - 1, 0, a.size() - 1)]


func _report(label: String) -> void:
	var n := maxf(1.0, float(_n))
	var avg := _avg()
	var present := 0
	for w in gm.sim.workers:
		if w.present:
			present += 1
	print("BENCH %s: кадров %d · кадр %.2f мс (%.0f к/с) · 1%% худших %.2f мс · 0,1%% %.2f мс · логика %.2f мс · симуляция %.2f мс · вызовов отрисовки %.0f · узлов %d · на заводе %d" % [
		label, _ft.size(), avg, 1000.0 / maxf(0.001, avg), _pct(0.99), _pct(0.999), _proc / n, _sim / n, _calls / n,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), present])
	var cen: Dictionary = {}
	_census(gm.ents, "", cen)
	print("BENCH %s видимых рисующих узлов по владельцам: %s" % [label, cen])
	_count.clear()
	for c in _wrapped:
		if is_instance_valid(c):
			var kc: String = (c.get_script() as Script).get_global_name()
			_count[kc] = int(_count.get(kc, 0)) + 1
	var keys := _cost.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(_cost[a]) > float(_cost[b]))
	var parts: PackedStringArray = []
	for k: String in keys.slice(0, 14):
		parts.append("%s×%d %.2f" % [k, int(_count.get(k, 0)), float(_cost[k]) / 1000.0 / n])
	print("BENCH %s _process, мс/кадр: %s" % [label, ", ".join(parts)])


## Оборачиваем _process узлов игры: выключаем их собственный и зовём сами под таймером (порядок — как в дереве).
func _scan(n: Node) -> void:
	for c in n.get_children():
		var sc: Script = c.get_script()
		if sc and c.is_processing() and not SKIP.has(sc.get_global_name()) and c.has_method("_process"):
			c.set_process(false)
			_wrapped.append(c)
		_scan(c)


## Сколько рисующих узлов реально видно и чьи они (WorkerView/ThingView/…): куда уходят вызовы отрисовки.
func _census(n: Node, owner_name: String, out: Dictionary) -> void:
	for c in n.get_children():
		var ci := c as CanvasItem
		if ci != null and not ci.visible:
			continue
		var on := owner_name
		var sc: Script = c.get_script()
		if sc and sc.get_global_name() != "":
			on = sc.get_global_name()
		if c is Sprite2D or c is Line2D or c is Polygon2D:
			out[on] = int(out.get(on, 0)) + 1
		_census(c, on, out)


func _run_wrapped(delta: float) -> void:
	var i := 0
	while i < _wrapped.size():
		var c := _wrapped[i]
		if not is_instance_valid(c) or not c.is_inside_tree():
			_wrapped.remove_at(i)
			continue
		i += 1
		if not c.can_process():
			continue
		var t0 := Time.get_ticks_usec()
		c.call("_process", delta)
		var k: String = (c.get_script() as Script).get_global_name()
		_cost[k] = float(_cost.get(k, 0.0)) + float(Time.get_ticks_usec() - t0)


## Слои, которые прячем по одному (отрисовка + видеокарта): разница с обычным кадром — их цена.
func _ablation_sets() -> Array:
	var by: Dictionary = {}
	for c in gm.world_root.get_children():
		var sc: Script = c.get_script()
		var k: String = sc.get_global_name() if sc else c.get_class()
		if not by.has(k):
			by[k] = []
		(by[k] as Array).append(c)
	var out: Array = []
	for k: String in by.keys():
		if k in ["GameCamera", "BuildTool", "SoundLayer"]:
			continue
		out.append([k, by[k]])
	out.append(["OverlayLayer+ZoneMarks+NameLayer", [gm.overlay.get_parent()]])
	out.append(["Hud", [gm.hud]])
	return out


## Чередуем: обычный кадр, кадр без слоя, обычный, без следующего… Цена слоя — против среднего соседних обычных окон.
var _abl_hidden := false
var _abl_prev := [0.0, 0.0]    ## прошлое обычное окно: [кадр, вызовы]
var _abl_pend: Array = []      ## окно без слоя, ждёт следующего обычного: [имя, кадр, вызовы]


func _abl_step() -> void:
	var avg := _avg()
	var calls := _calls / maxf(1.0, float(_n))
	if _abl_hidden:
		var set_: Array = _abl[_abl_i]
		_set_vis(set_[1], true)
		_abl_pend = [str(set_[0]), avg, calls]
		_abl_hidden = false
	else:
		if _abl_i < 0:
			print("BENCH отрисовка: обычный кадр %.2f мс, вызовов %.0f; цена слоя = обычный кадр − кадр без него" % [avg, calls])
		if not _abl_pend.is_empty():
			var base_t := (float(_abl_prev[0]) + avg) * 0.5
			var base_c := (float(_abl_prev[1]) + calls) * 0.5
			_results.append([_abl_pend[0], base_t - float(_abl_pend[1]), base_c - float(_abl_pend[2])])
			_abl_pend = []
		_abl_prev = [avg, calls]
		_abl_i += 1
		if _abl_i >= _abl.size():
			_results.sort_custom(func(x: Array, y: Array) -> bool: return float(x[2]) > float(y[2]))
			var parts: PackedStringArray = []
			for r: Array in _results:
				parts.append("%s %.1f мс/%.0f выз." % [r[0], r[1], r[2]])
			print("BENCH отрисовка слоёв (мс кадра / вызовов отрисовки): %s" % ", ".join(parts))
			_phase = "done"
			get_tree().quit()
			return
		_set_vis((_abl[_abl_i] as Array)[1], false)
		_abl_hidden = true
	_next("abl")


func _set_vis(nodes: Array, v: bool) -> void:
	for n in nodes:
		if n is CanvasItem:
			(n as CanvasItem).visible = v
		elif n is CanvasLayer:
			(n as CanvasLayer).visible = v
