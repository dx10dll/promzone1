extends SceneTree
## Тест 1.60 «Разгрузка»: 8 вкладок меню объектов, «Живость города» (полная / умеренная / выкл.), «Ники» (все / важные / нет).
## Окно игры нельзя собрать в режиме -s (автозагрузки), поэтому сама проверка лежит в stage160_ui.tscn,
## а этот файл запускает её отдельным процессом и разбирает вывод.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage160_test.gd


func _initialize() -> void:
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "res://tests/stage160_ui.tscn"], out, true)
	var text := "\n".join(PackedStringArray(out))
	for ln in text.split("\n"):
		if ln.contains("✓") or ln.contains("✗") or ln.contains("—") or ln.contains("РЕЗУЛЬТАТ") or ln.contains("ERROR"):
			print(ln)
	var ok := code == 0 and text.contains("ВСЁ ВЕРНО")
	if not ok:
		print("РЕЗУЛЬТАТ: ОШИБКИ: код выхода %d" % code)
	quit(0 if ok else 1)
