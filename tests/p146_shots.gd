extends Node
## 1.46: снимки интерфейса. xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 res://tests/p146_shots.tscn -- --mode=full|crop|hud|card|orders --out=/файл.png [--lang=ru]

var out := "/tmp/p146.png"
var mode := "full"
var lang := "ru"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--lang="):
			lang = a.get_slice("=", 1)
	L.apply(lang)
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 146
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(1.5).timeout
	if mode == "hud":
		gm.sim.notify("Выбит автомат — часть завода без тока", Sim.LVL_BAD)
		gm.sim.notify("Новая программа поддержки: «Тепло в цехах» — вернут 40 000 ₽. Финансы → Гранты.", Sim.LVL_GOOD)
		gm.sim.notify("Скоро проверка: пожарная. Приготовьте огнетушители.", Sim.LVL_WARN)
		gm.sim.notify("Принят на работу: Иванов, токарь", Sim.LVL_INFO)
	elif mode == "card":
		for w in gm.sim.workers:
			if not w.is_director():
				gm.hud.info.show_worker(gm.sim, w)
				break
	elif mode == "orders":
		gm.hud.open_window("orders")
	elif mode == "settings":
		gm.hud.show_settings()
	elif mode == "finance":
		gm.hud.open_window("finance")
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if mode == "crop":
		img = img.get_region(Rect2i(480, 880, 960, 200))
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	get_tree().quit(0)
