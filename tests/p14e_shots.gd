extends Node
## 1.40, срез E: снимки на английском (под xvfb): обучение, меню «Объекты», справочник, «Развитие», город за забором.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p14e_shots.tscn -- --out=/папка

var out := "/tmp"


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
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": true}
	Game.pending_seed = 142
	Game.settings["tutorial_done"] = false
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	await _shot("p14e_tutorial.png")
	var hud := gm.hud
	gm.sim.progress.tutorial = hud.tutorial._index_of("build")
	hud.tutorial._show()
	gm.sim.progress.all_open = true
	hud.toggle_sub("build")
	await get_tree().create_timer(0.8).timeout
	for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if (b as Button).has_meta("arg") and str((b as Button).get_meta("arg")) == "storage":
			(b as Button).mouse_entered.emit()
	await get_tree().create_timer(0.5).timeout
	await _shot("p14e_build.png")
	gm.sim.progress.tutorial = -1
	hud.tutorial._show()
	hud.obj_cat = "Станки"
	hud.toggle_sub("objects")
	await get_tree().create_timer(0.5).timeout
	for b2: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if (b2 as Button).has_meta("arg") and str((b2 as Button).get_meta("arg")) == "lathe_16k20":
			(b2 as Button).mouse_entered.emit()
	await get_tree().create_timer(0.5).timeout
	await _shot("p14e_objects.png")
	hud.close_sub()
	hud.show_help(false, "power")
	await get_tree().create_timer(1.0).timeout
	await _shot("p14e_help.png")
	hud.close_modal()
	hud.call("open_window", "office:develop")
	DevTree.sel = "fin2"
	hud.win.rebuild(true)
	await get_tree().create_timer(1.0).timeout
	await _shot("p14e_develop.png")
	hud.call("close_window")
	gm.cam.zoom = Vector2(0.35, 0.35)
	gm.cam.position = Vector2(-14 * 32, 10 * 32)
	await get_tree().create_timer(1.5).timeout
	await _shot("p14e_city.png")
	L.apply("ru")
	Game.settings["lang"] = ""
	get_tree().quit(0)
