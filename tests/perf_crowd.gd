extends Node
## 1.23: замер скорости игры с большим числом людей (с картинкой и интерфейсом).
## xvfb-run godot --path . res://tests/perf_crowd.tscn -- <людей> [кадров]
## Печатает среднее время кадра: всего, на симуляцию, на отрисовку и логику слоёв.

const S := preload("res://tests/setups.gd")

var gm: GameMain
var n_people := 200
var frames := 0
var measure := 600
var warm := 150
var acc_proc := 0.0
var acc_sim := 0.0
var acc_frame := 0.0
var _last := 0
var _off: PackedStringArray = []   ## классы слоёв, у которых выключить _process (для поиска, кто ест кадр)


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		n_people = int(a[0])
	if a.size() > 1:
		measure = int(a[1])
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {}
	Game.pending_seed = 77
	Game.settings["tutorial_done"] = true
	Game.settings["autosave"] = false
	Game.settings["pause_on_event"] = false
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	var s := gm.sim
	s.story.enabled = false
	s.progress.tutorial = -1
	s.bmats.enabled = false
	S.big_shop(s)
	S.offices(s)
	S.complex_orders(s, 10)
	var profs := [["laborer", "haul"], ["turner", "turning"], ["miller", "milling"], ["laborer", "haul"], ["qc", "qc"], ["cleaner", "clean"], ["builder", "build"]]
	var k := 0
	while s.workers.size() < n_people:
		var p: Array = profs[k % profs.size()]
		S.hire(s, str(p[0]), str(p[1]), 4)
		k += 1
	s.minute = floor(s.minute / 1440.0) * 1440.0 + 600.0
	for w in s.workers:
		w.present = true
		w.pos = Vector2(randf_range(4.0, 44.0), randf_range(4.0, 26.0))
	gm.set_speed(3)
	gm.cam.zoom = Vector2(0.8, 0.8)
	gm.cam.position = Vector2(24, 15) * 32.0
	if a.size() > 2:
		_off = a[2].split(",")
	print("людей: %d, объектов: %d, предметов: %d" % [s.workers.size(), s.things.size(), s.items.size()])
	_last = Time.get_ticks_usec()


func _process(_d: float) -> void:
	frames += 1
	var now := Time.get_ticks_usec()
	var ft := (now - _last) / 1000.0
	_last = now
	if frames == warm and not _off.is_empty():
		_disable(gm)
	if frames > warm:
		acc_frame += ft
		acc_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		acc_sim += gm.sim_ms
	if frames >= warm + measure:
		var n := float(measure)
		print("кадр %.1f мс (%.0f к/с) · логика кадра %.1f мс · из неё симуляция %.1f мс · людей на заводе %d" % [acc_frame / n, 1000.0 / (acc_frame / n), acc_proc / n, acc_sim / n, gm.sim.workers.filter(func(w: Worker) -> bool: return w.present).size()])
		get_tree().quit()


func _disable(n: Node) -> void:
	var sc: Script = n.get_script()
	if sc and _off.has(sc.get_global_name()):
		n.set_process(false)
	for c in n.get_children():
		_disable(c)
