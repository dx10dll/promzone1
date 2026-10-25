extends Node
## 1.39, срез C: снимки письма-события и многотиражки по-английски (под xvfb):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p14c_shots.tscn -- --out=/папка

var out := "/tmp"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", out.path_join(name))


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	L.apply("en")
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 140
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	L.apply("en")
	var sim: Sim = gm.sim
	for i in 30:
		sim.tick(30.0)
	sim.story._start("rumor", false)
	sim.story._start("raid", false)
	sim.inspect._act("fire", sim.inspect.violations("fire") + [sim.inspect._v("fire", "no_ext", Vector2i(-1, -1), -1, ["Shop"]), sim.inspect._v("fire", "clutter", Vector2i(-1, -1), -1)], [], L.t("плановая"))
	gm.hud.show_letter(sim.story.letters[-1])
	await get_tree().create_timer(1.0).timeout
	await _shot("p14c_letter.png")
	gm.hud.call("_close_letter")
	sim.story.letters.clear()
	sim.story._start("metal_up", false)
	sim.story._start("heatwave", false)
	sim.story._ev_gift("wedding")
	sim.story.letters.clear()
	for w in sim.workers:
		w.week_score = 20
	sim.paper.publish(true)
	gm.hud.open_window("paper")
	await get_tree().create_timer(1.0).timeout
	await _shot("p14c_paper.png")
	get_tree().quit(0)
