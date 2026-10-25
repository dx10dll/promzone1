extends Node
## 1.39: снимки для проверки перевода и интро (под xvfb):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p140_shots.tscn -- --lang=en --out=/папка

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
	CustomWorkers.path = "user://p140_custom_workers.json"
	var ip := IntroPlayer.new()
	add_child(ip)
	await get_tree().create_timer(3.5).timeout
	await _shot("p140_intro.png")
	ip.queue_free()
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await _wait(10)
	mm.call("jump", 1)
	await get_tree().create_timer(1.5).timeout
	await _shot("p140_menu_en.png")
	mm.call("_show_settings")
	await _wait(10)
	await _shot("p140_settings_en.png")
	mm.call("_show_new_game")
	await _wait(10)
	await _shot("p140_newgame_en.png")
	mm.call("_show_custom")
	await get_tree().create_timer(1.5).timeout
	await _shot("p140_custom_en.png")
	mm.queue_free()
	await _wait(3)
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 140
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	await _shot("p140_hud_en.png")
	gm.hud.call("show_pause_menu")
	await _wait(6)
	await _shot("p140_pause_en.png")
	get_tree().quit(0)
