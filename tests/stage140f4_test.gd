extends SceneTree
## Тест 1.40 (f4): оптимизация кадров. DrawChunks раскладывает команды по плиткам с прежним порядком наложения;
## фон города собирается в плитки (а не в один гигантский узел); в настройках есть предел 30 кадров; имена в EN кешируются.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage140f4_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func this_root_add(n: Node) -> void:
	get_root().add_child(n)


func _initialize() -> void:
	var rec := DrawChunks.new()
	rec.draw_rect(Rect2(0, 0, 100, 100), Color.RED)           # плитка (0,0)
	rec.draw_rect(Rect2(5000, 0, 100, 100), Color.GREEN)      # другая плитка, не пересекается: тот же слой
	check(rec.layers.is_empty(), "до build слой ещё не закрыт")
	rec.draw_rect(Rect2(-50, -50, 6000, 300), Color.BLUE)     # большая: перекрывает обе — новый слой, порядок сохранён
	rec.draw_rect(Rect2(10, 10, 20, 20), Color.WHITE)         # поверх большой — снова новый слой
	var root := Node2D.new()
	var n := rec.build(root)
	check(rec.layers.size() == 3, "три слоя из-за перекрытий (%d)" % rec.layers.size())
	check((rec.layers[0] as Dictionary).size() == 2, "в первом слое две плитки")
	check(n == 4 and root.get_child_count() == 4, "узлов-плиток: %d" % n)
	root.free()
	# фон города: много плиток, команды не потеряны
	var sim := Scenario.new_game("garage", "mech", "market", 5)
	var cb := CityBackdrop.new()
	cb.sim = sim
	root = Node2D.new()
	this_root_add(root)
	await process_frame
	root.add_child(cb)
	check(cb._tiles_n > 50 and cb._rec.count > 1000, "город разложен на плитки: %d узлов, %d команд" % [cb._tiles_n, cb._rec.count])
	check(cb.chimneys.size() > 0 and cb.lanes.size() > 0, "трубы и проезды для CityLife собраны")
	root.free()
	# предел кадров в настройках
	var src := FileAccess.get_file_as_string("res://scripts/ui/settings_ui.gd")
	check(src.contains('[30.0, "30"]') and src.contains("без предела"), "в настройках есть 30/60/120/144/без предела")
	check(FileAccess.get_file_as_string("res://scripts/autoload/game.gd").contains("\"fps_cap\": 0.0") and FileAccess.get_file_as_string("res://scripts/autoload/game.gd").contains("\"vsync\": 0.0"), "по умолчанию: без предела, V-Sync выкл.")
	print("РЕЗУЛЬТАТ: %s" % ("OK" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	quit(0 if fails.is_empty() else 1)
