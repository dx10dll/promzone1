extends Node
## 1.39, кусок A: снимки окон управления на английском (под xvfb):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p14a_shots.tscn -- --out=/папка

var out := "/tmp"


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name))
	print("saved ", out.path_join(name))


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	L.apply("en")
	Game.pending = "new"
	Game.pending_scn = "sandbox"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 141
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	gm.sim.money = 900000.0
	gm.sim.post_ad("turner")
	for k: String in ["orders:market", "prod:supply", "finance:grants", "people:hire", "office:develop"]:
		gm.hud.call("close_window")
		gm.hud.call("open_window", k)
		await get_tree().create_timer(1.0).timeout
		await _shot("p14a_%s.png" % k.get_slice(":", 1))
	L.apply("ru")
	Game.settings["lang"] = ""
	get_tree().quit(0)
