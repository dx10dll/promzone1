extends Node
## 1.41: снимки звонков. xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p141_shots.tscn -- --out=/папка

var out := "/tmp"


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", out.path_join(name))


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	L.apply("ru")
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 141
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(1.5).timeout
	var sim := gm.sim
	var ph := gm.hud.phone
	sim.calls.queue.clear()
	sim.calls.push("engineer", "worried", "Металла «%s» не хватает на заказы: нужно ещё %d шт. Давайте решим, где взять деньги, пока цех не встал.", ["Сталь", 12], "m1", "prod:supply", "Открыть снабжение")
	await _wait(2)
	ph.ring_t = 150.0
	await _wait(2)
	await _shot("p141_ringing.png")
	ph.answer()
	await get_tree().create_timer(0.6).timeout
	await _shot("p141_engineer.png")
	ph.close()
	sim.inspect._act("fire", [{"key": "t1", "fine": 12000.0, "text": "Нет огнетушителя в цехе", "cell": [-1, -1]}], [], "")
	for l: Dictionary in sim.story.letters.duplicate():
		sim.story.resolve(int(l["id"]), 0)
	await get_tree().create_timer(1.0).timeout
	ph.answer()
	await get_tree().create_timer(0.6).timeout
	await _shot("p141_fire.png")
	ph.close()
	sim.calls.on_reclamation("Втулка", 3)
	await _wait(3)
	ph.answer()
	await get_tree().create_timer(0.6).timeout
	await _shot("p141_customer.png")
	get_tree().quit(0)
