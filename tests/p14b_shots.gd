extends Node
## 1.40 (часть B): снимки карточек и людей на английском (под xvfb):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p14b_shots.tscn -- --out=/папка

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
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1402
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(1.0).timeout
	var sim: Sim = gm.sim
	for i in 600:
		sim.tick(1.0)
	sim.story.letters.clear()
	var w: Worker = null
	for x in sim.workers:
		if not x.visitor and w == null:
			w = x
	InfoPanel.w_tab = "main"
	gm.hud.info.show_worker(sim, w)
	await get_tree().create_timer(1.0).timeout
	await _shot("p14b_card_en.png")
	gm.hud.info.visible = false
	sim.office.all_depts = true   # разделы не закрыты отделами
	sim.crew.auto_form()
	gm.hud.open_window("people:brig")
	await get_tree().create_timer(1.0).timeout
	await _shot("p14b_crews_en.png")
	gm.hud.close_window()
	gm.hud.show_stage_up(2)
	await get_tree().create_timer(1.0).timeout
	await _shot("p14b_stageup_en.png")
	gm.hud.close_modal()
	gm.hud.show_drawing({"product": str(Defs.products.keys()[0]), "id": 17, "qty": 40, "client": "ООО «Ромашка»"})
	await get_tree().create_timer(1.0).timeout
	await _shot("p14b_drawing_en.png")
	get_tree().quit(0)
