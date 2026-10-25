extends Node
## 1.40 (f2): снимки — чистое поле (отдельное техпомещение, раковина), песочница (насосная), новые двери
## и каски, меню «Окна и двери». Под xvfb:
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p140f2_shots.tscn -- --lang=ru --out=/папка

var out := "/tmp"
var pre := "p140f2"


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(pre + "_" + name + ".png"))
	print("saved ", name)


func _game(scn: String) -> GameMain:
	Game.pending = "new"
	Game.pending_scn = scn
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 140
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(10.0).timeout
	return gm


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var gm := await _game("field")
	gm.cam.zoom = Vector2(2.2, 2.2)
	gm.cam.focus_cell(Vector2i(15, 29))
	await _wait(10)
	await _shot("field")
	gm.queue_free()
	await _wait(4)
	gm = await _game("sandbox")
	var tr: Thing = gm.sim.things_of("pump")[0]
	gm.cam.zoom = Vector2(2.6, 2.6)
	gm.cam.focus_cell(tr.cell)
	await _wait(10)
	await _shot("sandbox")
	# новые двери и каски: ряд дверей в стене техпомещения не трогаем — ставим домик рядом
	var s := gm.sim
	var w := s.world
	var o := tr.cell + Vector2i(-14, -9)
	for y in range(o.y, o.y + 5):
		for x in range(o.x, o.x + 10):
			var c := Vector2i(x, y)
			w.flr[w.idx(c)] = 1
			if x == o.x or x == o.x + 9 or y == o.y or y == o.y + 4:
				w.wall[w.idx(c)] = World.W_BRICK
	w.wall[w.idx(o + Vector2i(2, 4))] = World.W_DOOR_BROWN
	w.wall[w.idx(o + Vector2i(4, 4))] = World.W_DOOR
	w.wall[w.idx(o + Vector2i(6, 4))] = World.W_DOOR_GREEN
	w.wall[w.idx(o + Vector2i(9, 2))] = World.W_DOOR_GREEN
	w.refresh_all()
	var k := 0
	for pf: String in ["electrician", "caster", "builder", "safety_engineer", "foreman", "builder"]:
		var p := People.make(s.rng, pf)
		p.look["hat"] = "helmet"
		Worker.sync_helmet(p.look, pf)
		s.add_worker(p)
		p.present = true
		p.pos = Vector2(o + Vector2i(1 + k, 6)) + Vector2(0.5, 0.5)
		k += 1
	await _wait(30)
	gm.cam.zoom = Vector2(2.4, 2.4)
	gm.cam.focus_cell(o + Vector2i(4, 4))
	await _wait(20)
	await _shot("doors_helmets")
	var h: Hud = gm.hud
	BuildMenu.build_cat = "open"
	h.toggle_sub("build")
	await _wait(8)
	await _shot("build_doors")
	get_tree().quit(0)
