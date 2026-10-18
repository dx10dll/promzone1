extends SceneTree
## 1.30: снимки улицы за краем карты по ходу игры (не тест):
## godot --path . -s res://tests/street_probe.gd -- <файл-префикс> <зум> <x> <y> <минута1,минута2,...> [скорость]

var gm: Node
var shots: Array = []
var pre := ""
var z := 0.8
var cx := 0.0
var cy := 0.0
var done := 0
var warped := false
var skip_to := -1.0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	pre = a[0]
	z = float(a[1])
	cx = float(a[2])
	cy = float(a[3])
	for s in a[4].split(","):
		shots.append(float(s))
	var g: Node = root.get_node("Game")
	g.set("pending", "new")
	g.set("pending_scn", "garage")
	g.set("pending_profile", "mech")
	g.set("pending_opts", {})
	g.set("pending_seed", 4242)
	(g.get("settings") as Dictionary)["tutorial_done"] = true
	(g.get("settings") as Dictionary)["fast_night"] = false
	gm = load("res://scenes/game.tscn").instantiate()
	root.add_child(gm)
	skip_to = float(a[6]) if a.size() > 6 else -1.0
	var spd := int(a[5]) if a.size() > 5 else 3
	(func() -> void:
		gm.call("set_speed", spd)).call_deferred()


func _process(_d: float) -> bool:
	if gm == null or gm.get("sim") == null:
		return false
	var cam: Camera2D = gm.get("cam")
	cam.zoom = Vector2(z, z)
	cam.position = Vector2(cx, cy) * 32.0
	var sim: RefCounted = gm.get("sim")
	if not warped:
		warped = true
		while float(sim.get("minute")) < skip_to:
			sim.call("tick", 0.5)
	if done < shots.size() and float(sim.get("minute")) >= float(shots[done]):
		var img := root.get_texture().get_image()
		var fn := "%s_%d.png" % [pre, int(shots[done])]
		img.save_png(fn)
		print("saved ", fn, " people on street: ", (load("res://scripts/view/street_folk.gd") as GDScript).get("pose").size())
		done += 1
	return done >= shots.size()
