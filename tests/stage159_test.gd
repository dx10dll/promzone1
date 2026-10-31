extends SceneTree
## Тест 1.59 «Разгрузка интерфейса»: пять слоёв карты с подвкладками, совет в «Что делать» не дублируется уведомлением,
## «План» (калька) — кнопка внутри «Стройки». Окно игры нельзя собрать в режиме -s (автозагрузки), поэтому
## сама проверка лежит в stage159_ui.tscn, а этот файл запускает её отдельным процессом и разбирает вывод.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage159_test.gd


func _initialize() -> void:
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "res://tests/stage159_ui.tscn"], out, true)
	var text := "\n".join(PackedStringArray(out))
	for ln in text.split("\n"):
		if ln.contains("✓") or ln.contains("✗") or ln.contains("—") or ln.contains("РЕЗУЛЬТАТ") or ln.contains("ERROR"):
			print(ln)
	var ok := code == 0 and text.contains("ВСЁ ВЕРНО")
	if not ok:
		print("РЕЗУЛЬТАТ: ОШИБКИ: код выхода %d" % code)
	quit(0 if ok else 1)
