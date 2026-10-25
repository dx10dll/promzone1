extends Node
## 1.44: снимки. xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/p144_shots.tscn -- --mode=sharp --out=/файл.png [--scale=1.3] [--lang=ru]

var out := "/tmp/p144.png"
var mode := "sharp"
var scale := 1.0
var lang := "ru"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--scale="):
			scale = float(a.get_slice("=", 1))
		elif a.begins_with("--lang="):
			lang = a.get_slice("=", 1)
	L.apply(lang)
	Game.settings["ui_scale"] = scale
	Game.apply_ui_scale()
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 144
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(1.5).timeout
	if mode == "skip":
		gm.sim.minute = 5.0 * 1440.0 + 21.0 * 60.0
		for w in gm.sim.workers:
			w.present = false
		gm.set_speed(1)
		await get_tree().create_timer(0.8).timeout
	elif mode == "settings":
		gm.hud.show_settings()
		await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if mode == "sharp":
		img = img.get_region(Rect2i(0, 0, 520, 200))
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	get_tree().quit(0)
