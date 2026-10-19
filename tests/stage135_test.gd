extends Node
## 1.35: редактор «Создать рабочего» не тормозит при долгом переборе внешности. Открываем его, как главное меню,
## и 300 раз меняем внешность его же кнопками (◀ ▶, пол, «своя одежда»); по пачкам смотрим время на одно
## изменение, число узлов и объектов, «осиротевшие» узлы, память текстур и размеры статических кэшей —
## последняя пачка не хуже первой (×1,5), ничего не копится.
## xvfb-run -a godot --path . tests/stage135_test.tscn   (или godot --headless --path . --audio-driver Dummy tests/stage135_test.tscn)

const BATCHES := 10
const PER := 30

var fails: Array[String] = []
var rng := RandomNumberGenerator.new()   ## только для выбора кнопок в тесте
var ed: CustomWorkersUI


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _buttons(root: Node, texts: Array) -> Array:
	var out: Array = []
	for b: Node in root.find_children("*", "Button", true, false):
		if texts.has((b as Button).text) and not (b as Button).disabled:
			out.append(b)
	return out


func _caches() -> Dictionary:
	return {"portrait": Portrait._cache.size(), "kit_rec": PortraitKit._rec.size(), "kit_comp": PortraitKit._comp.size(),
		"kit_img": PortraitKit._img.size(), "kit_mats": PortraitKit._mats.size(), "tex_people": Tex._people_hi.size(),
		"tex": Tex._cache.size(), "tex_ui": Tex._ui_vec.size(), "vec_inner": Vec._inner.size()}


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children(true):
		c += _count(ch)
	return c


func _stats() -> Dictionary:
	return {"ed_nodes": _count(ed), "doll_nodes": _count(ed.doll_box),"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0}


var t_arrow := 0     ## мкс на стрелки ◀ ▶ в пачке
var n_arrow := 0


func _change(i: int) -> void:
	if i % 10 == 9:
		var fem := bool(ed.cur.get("female", false))
		var gb := _buttons(ed.form, ["Мужчина" if fem else "Женщина"])
		(gb[0] as Button).pressed.emit()
	elif i % 7 == 6:
		var db := _buttons(ed, ["Своя одежда" if ed.dressed else "В спецовке"])
		(db[0] as Button).pressed.emit()
	else:
		var arrows := _buttons(ed.form, ["◀", "▶"])
		var a0 := Time.get_ticks_usec()
		(arrows[rng.randi_range(0, arrows.size() - 1)] as Button).pressed.emit()
		t_arrow += Time.get_ticks_usec() - a0
		n_arrow += 1


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	rng.seed = 135
	CustomWorkers.path = "user://test135_custom_workers.json"
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await _wait(5)
	mm.call("_show_custom")
	await _wait(5)
	ed = mm.get("ng_root") as CustomWorkersUI
	check(ed != null and ed.is_inside_tree(), "редактор открыт, как из главного меню")
	if ed == null:
		_finish()
		return
	await _wait(20)
	# стрелка ◀ ▶ не пересобирает форму: строка та же, значение и счётчик обновились, человечек и портрет — тоже
	var first := ed.form.get_child(0)
	var row: Control = null
	for b: Node in _buttons(ed.form, ["▶"]):
		var l0 := b.get_parent().get_child(0) as Label
		if l0 and l0.text == "Цвет волос":
			row = b.get_parent() as Control
	check(row != null, "есть строка «Цвет волос»")
	if row:
		var hc0 := str((ed.cur["look"] as Dictionary).get("hair_col", ""))
		var doll0 := ed.doll_box.doll
		var labels0 := row.find_children("*", "Label", true, false).map(func(x: Node) -> String: return (x as Label).text)
		var sw0 := (row.find_children("*", "ColorRect", true, false)[0] as ColorRect).color
		(row.get_child(row.get_child_count() - 1) as Button).pressed.emit()
		await _wait(2)
		var hc1 := str((ed.cur["look"] as Dictionary).get("hair_col", ""))
		var labels1 := row.find_children("*", "Label", true, false).map(func(x: Node) -> String: return (x as Label).text)
		var sw1 := (row.find_children("*", "ColorRect", true, false)[0] as ColorRect).color
		check(is_instance_valid(first) and not first.is_queued_for_deletion() and is_instance_valid(row) and not row.is_queued_for_deletion(), "стрелка не пересобирает форму")
		check(hc1 != hc0 and sw1 == Color(hc1) and sw1 != sw0, "цвет волос сменился, образец цвета — тоже: %s → %s" % [hc0, hc1])
		check(labels1 != labels0 and str(labels1[2]).begins_with("%d/" % (CustomWorkers.HAIR_COLS.find(hc1) + 1)), "подпись и счётчик в строке обновились: %s" % str(labels1))
		check(ed.doll_box.doll != doll0 and ed.dirty, "человечек и портрет обновились, есть несохранённые изменения")
		check(ed.por.look.get("hair_col", "") == hc1 or str(ed.por.look.get("hair_col", "")) == hc1, "портрет — с новым цветом волос")
	var rows: Array = []
	var n := 0
	for bi in BATCHES:
		var t_change := 0
		t_arrow = 0
		n_arrow = 0
		var t0 := Time.get_ticks_usec()
		var frames: Array[float] = []
		for j in PER:
			mm.set("scene_t", 4.0)   # фон меню держим на одной сцене: смена мира за окном — не про редактор
			var c0 := Time.get_ticks_usec()
			_change(n)
			t_change += Time.get_ticks_usec() - c0
			n += 1
			await get_tree().process_frame
			frames.append((Time.get_ticks_usec() - c0) / 1000.0)
		var t_all := Time.get_ticks_usec() - t0
		await _wait(4)   # queue_free доходит до конца
		var st := _stats()
		st["ms_change"] = t_change / 1000.0 / PER
		frames.sort()
		st["ms_frame"] = frames[frames.size() / 2]   # медиана: редкие подвисания фона не в счёт
		st["ms_avg"] = t_all / 1000.0 / PER
		st["ms_arrow"] = t_arrow / 1000.0 / maxi(1, n_arrow)
		st["caches"] = _caches()
		rows.append(st)
		print("пачка %2d: изм %.2f мс (стрелка %.2f), кадр %.2f мс (в среднем %.2f), узлов %d (редактор %d, кукла %d), объектов %d, сирот %d, ресурсов %d, текстуры %.1f МБ, кэши %s" % [bi + 1,
			st["ms_change"], st["ms_arrow"], st["ms_frame"], st["ms_avg"], st["nodes"], st["ed_nodes"], st["doll_nodes"], st["objects"], st["orphans"], st["resources"], st["tex_mb"], str(st["caches"])])
	var a: Dictionary = rows[1]    # первая пачка — прогрев кэшей, сравниваем со второй
	var z: Dictionary = rows[rows.size() - 1]
	check(float(z["ms_change"]) <= maxf(float(a["ms_change"]) * 1.5, float(a["ms_change"]) + 2.0), "время на изменение не растёт: %.2f → %.2f мс" % [a["ms_change"], z["ms_change"]])
	check(float(z["ms_arrow"]) <= maxf(float(a["ms_arrow"]) * 1.5, float(a["ms_arrow"]) + 1.0), "стрелка не дорожает: %.2f → %.2f мс" % [a["ms_arrow"], z["ms_arrow"]])
	check(float(z["ms_arrow"]) < 12.0, "стрелка дешёвая (без пересборки формы): %.2f мс" % z["ms_arrow"])
	check(int(z["ed_nodes"]) <= int(a["ed_nodes"]) + 10 and int(z["doll_nodes"]) <= int(a["doll_nodes"]) + 10, "узлы редактора и куклы не копятся: %d → %d, %d → %d" % [a["ed_nodes"], z["ed_nodes"], a["doll_nodes"], z["doll_nodes"]])
	check(float(z["ms_frame"]) <= maxf(float(a["ms_frame"]) * 1.5, float(a["ms_frame"]) + 4.0), "кадр (медиана) не тяжелеет: %.2f → %.2f мс" % [a["ms_frame"], z["ms_frame"]])
	check(int(z["nodes"]) <= int(a["nodes"]) * 1.15, "узлы не копятся: %d → %d" % [a["nodes"], z["nodes"]])
	check(int(z["orphans"]) <= int(a["orphans"]) + 20, "нет осиротевших узлов: %d → %d" % [a["orphans"], z["orphans"]])
	check(int(z["objects"]) <= int(a["objects"]) * 1.1 + 200, "объекты не копятся: %d → %d" % [a["objects"], z["objects"]])
	check(float(z["tex_mb"]) <= float(a["tex_mb"]) * 1.5 + 8.0, "память текстур не растёт: %.1f → %.1f МБ" % [a["tex_mb"], z["tex_mb"]])
	ed.close()
	_finish()


func _finish() -> void:
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
	print("РЕЗУЛЬТАТ: OK" if fails.is_empty() else "РЕЗУЛЬТАТ: ОШИБКИ: " + ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)
