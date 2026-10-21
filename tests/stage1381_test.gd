extends Node
## 1.38.1: редактор «Создать рабочего» не тормозит от нажатий ЛЮБЫХ его кнопок (EditorBench: стрелки всех строк,
## пол, телосложение, возраст, черты, профессия, случайная внешность и ФИО, одежда, ввод ФИО, список, добавить,
## сохранить, удалить). Каждое нажатие — сам сигнал и 2 кадра; последняя пачка не хуже первой (×1,5), ничего не копится.
## xvfb-run -a godot --path . --rendering-driver opengl3 tests/stage1381_test.tscn

const N := 300
const PER := 30

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	CustomWorkers.path = "user://test1381_custom_workers.json"
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	for i in 5:
		await get_tree().process_frame
	mm.call("_show_custom")
	for i in 5:
		await get_tree().process_frame
	check(mm.get("ng_root") is CustomWorkersUI, "редактор открыт, как из главного меню")
	var b := EditorBench.new()
	add_child(b)
	await b.run(mm, N, PER)
	check(b.clicks >= N, "сделано нажатий: %d" % b.clicks)
	check(b.kinds.size() >= 20, "нажаты все виды кнопок: %d" % b.kinds.size())
	var a: Dictionary = b.rows[1]    # первая пачка — прогрев
	var z: Dictionary = b.rows[b.rows.size() - 1]
	var avg_a := 0.0
	var avg_z := 0.0
	for i in 3:
		avg_a += float(b.rows[1 + i]["ms_click"]) / 3.0
		avg_z += float(b.rows[b.rows.size() - 1 - i]["ms_click"]) / 3.0
	check(avg_z <= maxf(avg_a * 1.5, avg_a + 3.0), "время нажатия не растёт: %.2f → %.2f мс" % [avg_a, avg_z])
	check(float(z["ms_frame"]) <= maxf(float(a["ms_frame"]) * 1.5, float(a["ms_frame"]) + 4.0), "кадр (медиана) не тяжелеет: %.2f → %.2f мс" % [a["ms_frame"], z["ms_frame"]])
	check(int(z["nodes"]) <= int(a["nodes"]) * 1.15, "узлы не копятся: %d → %d" % [a["nodes"], z["nodes"]])
	check(int(z["orphans"]) <= int(a["orphans"]) + 20, "нет осиротевших узлов: %d → %d" % [a["orphans"], z["orphans"]])
	check(int(z["objects"]) <= int(a["objects"]) * 1.1 + 300, "объекты не копятся: %d → %d" % [a["objects"], z["objects"]])
	check(float(z["tex_mb"]) <= float(a["tex_mb"]) * 1.3 + 40.0, "память текстур не растёт: %.1f → %.1f МБ" % [a["tex_mb"], z["tex_mb"]])
	check(int(z["kit_tex"]) <= PortraitKit.TEX_KEEP + 8, "слоёв портрета в памяти не больше предела: %d" % z["kit_tex"])
	var worst := 0.0
	var wk := ""
	for k: String in b.kinds.keys():
		var e := float(b.kinds[k]["emit"]) / 1000.0 / float(b.kinds[k]["n"])
		if e > worst:
			worst = e
			wk = k
	check(worst < 40.0, "самое дорогое нажатие (сам сигнал) в среднем — меньше 40 мс: %s %.2f" % [wk, worst])
	var rows: Dictionary = b.kinds.get("row:Телосложение", {})
	check(not rows.is_empty() and float(rows["emit"]) / 1000.0 / float(rows["n"]) < 8.0, "смена телосложения (новый набор портретов) не читает слои в щелчке")
	_finish()


func _finish() -> void:
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
	print("РЕЗУЛЬТАТ: OK" if fails.is_empty() else "РЕЗУЛЬТАТ: ОШИБКИ: " + ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)
