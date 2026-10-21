class_name EditorBench
extends Node
## 1.38.1: замер редактора «Создать рабочего» — щёлкает ВСЕ виды его кнопок через настоящие сигналы
## (стрелки каждой строки, пол, телосложение, возраст, черты, профессия, «Случайная внешность», «Случайное ФИО»,
## спецовка/своя одежда, ввод ФИО, выбор в списке, добавить/сохранить/удалить) и меряет каждое нажатие:
## сам сигнал + 2 следующих кадра. По пачкам — узлы, объекты, сироты, память текстур, загрузки слоёв портрета.
## Используют tests/stage1381_test и флаг запуска `-- --bench-editor` (main_menu): в обычной игре не работает.

signal finished

var ed: CustomWorkersUI
var menu: Node
var rng := RandomNumberGenerator.new()   ## только для выбора кнопок, симуляцию не трогает
var kinds: Dictionary = {}               ## вид нажатия -> {"n", "us", "max"}
var rows: Array = []                     ## по пачке: статистика
var clicks := 0
var quiet_bg := true                     ## на время замера остановить и спрятать фон меню
var idle_ms := 0.0                       ## кадр без нажатий (медиана)
var _seq: Array[String] = []


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _btns(root: Node, texts: Array) -> Array:
	var out: Array = []
	for b: Node in root.find_children("*", "Button", true, false):
		if texts.has((b as Button).text) and not (b as Button).disabled and (b as Button).is_visible_in_tree():
			out.append(b)
	return out


## Стрелки строки с подписью title (◀ ▶ в строке _pick или в степпере возраста).
func _row_arrows(title: String) -> Array:
	var out: Array = []
	for b: Node in _btns(ed.form, ["◀", "▶"]):
		var p := b.get_parent()
		var l0 := p.get_child(0) as Label
		if l0 == null and p.get_parent() != null:
			l0 = p.get_parent().get_child(0) as Label
		if l0 and l0.text == title:
			out.append(b)
	return out


func _row_titles() -> Array:
	var out: Array = []
	for b: Node in _btns(ed.form, ["▶"]):
		var p := b.get_parent()
		var l0 := p.get_child(0) as Label
		if l0 == null and p.get_parent() != null:
			l0 = p.get_parent().get_child(0) as Label
		if l0 and not out.has(l0.text):
			out.append(l0.text)
	return out


func _press(b: Variant) -> bool:
	if b is Button and is_instance_valid(b):
		var bt := b as Button
		if bt.toggle_mode and bt.button_group != null:
			bt.button_pressed = true   # сегмент: как щелчок мышью — кнопка группы становится нажатой
		bt.pressed.emit()
		return true
	return false


func _pick_one(a: Array) -> Variant:
	return null if a.is_empty() else a[rng.randi_range(0, a.size() - 1)]


## Одно нажатие вида k. Возвращает false, если такой кнопки сейчас нет.
func _do(k: String) -> bool:
	match k:
		"gender":
			var fem := bool(ed.cur.get("female", false))
			return _press(_pick_one(_btns(ed.form, ["Мужчина" if fem else "Женщина"])))
		"dressed":
			return _press(_pick_one(_btns(ed, ["Своя одежда" if ed.dressed else "В спецовке"])))
		"random_look":
			return _press(_pick_one(_btns(ed, ["Случайная внешность"])))
		"random_name":
			return _press(_pick_one(_btns(ed.form, ["Случайное ФИО"])))
		"age":
			return _press(_pick_one(_row_arrows("Возраст")))
		"trait":
			var tb: Array = []
			for fl: Node in ed.form.find_children("*", "HFlowContainer", true, false):
				for b: Node in fl.get_children():
					if b is Button and not (b as Button).disabled:
						tb.append(b)
			return _press(_pick_one(tb))
		"prof":
			var obs := ed.form.find_children("*", "OptionButton", true, false)
			if obs.is_empty():
				return false
			var ob := obs[0] as OptionButton
			var ix := rng.randi_range(0, ob.item_count - 1)
			if ob.is_item_separator(ix):
				ix = 0
			ob.select(ix)
			ob.item_selected.emit(ix)
			return true
		"type":
			var keys := ed.name_edits.keys()
			if keys.is_empty():
				return false
			var le := ed.name_edits[keys[rng.randi_range(0, keys.size() - 1)]] as LineEdit
			if not is_instance_valid(le):
				return false
			var t := le.text
			t = t.left(t.length() - 1) if t.length() > 4 and rng.randf() < 0.5 else t + "а"
			le.text = t
			le.text_changed.emit(t)
			return true
		"list":
			var rws: Array = []
			for i in ed.list_box.get_child_count():
				var r := ed.list_box.get_child(i)
				if r is PanelContainer and i != ed.sel and i < ed.workers().size() and not r.is_queued_for_deletion():
					rws.append(r)
			var row: Variant = _pick_one(rws)
			if row == null:
				return false
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			(row as Control).gui_input.emit(ev)
			return true
		"add":
			if ed.workers().size() >= CustomWorkers.MAX - 1:
				return _do("delete")
			return _press(_btns(ed, ["+  Новый рабочий"]).front() if not _btns(ed, ["+  Новый рабочий"]).is_empty() else null)
		"save":
			if ed.save_btn.disabled:
				return false
			return _press(ed.save_btn)
		"delete":
			if not ed.del_btn.visible or ed.workers().size() <= 2:
				return false
			return _press(ed.del_btn)
	# стрелка строки внешности: "row:<подпись>"
	if k.begins_with("row:"):
		return _press(_pick_one(_row_arrows(k.substr(4))))
	return false


func _stats() -> Dictionary:
	return {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"loads": PortraitKit.load_count, "kit_tex": PortraitKit.loaded_count()}


## Порядок нажатий: каждый вид много раз, вперемешку; телосложение и пол — почаще (новый набор портретов).
func _build_seq() -> void:
	var base: Array[String] = ["gender", "dressed", "random_look", "random_name", "age", "trait", "prof", "type", "type",
		"list", "add", "save", "delete", "row:Телосложение", "row:Телосложение"]
	for t: String in _row_titles():
		if t != "Возраст":
			base.append("row:" + t)
	_seq = base


## n нажатий пачками по per; печатает таблицу. Возвращает rows (по пачке) и kinds (по виду).
func run(m: Node, n: int, per: int, seed_v: int = 1381) -> void:
	menu = m
	rng.seed = seed_v
	ed = menu.get("ng_root") as CustomWorkersUI
	if ed == null:
		menu.call("_show_custom")
		await _wait(5)
		ed = menu.get("ng_root") as CustomWorkersUI
	# в списке — пара записей, чтобы было что выбирать и удалять
	while ed.workers().size() < 15:
		_press(ed.save_btn)
		await _wait(1)
		_press(_btns(ed, ["+  Новый рабочий"]).front())
		await _wait(1)
	# фон меню (показательный завод) на время замера — стоп: он под окном, а его кадр (на этой машине — сотни мс
	# программной отрисовки) топит время самого редактора
	var bg: Node2D = menu.get("scene_root") as Node2D
	if quiet_bg:
		menu.set_process(false)
		if bg:
			bg.visible = false
	await _wait(10)
	var idle: Array[float] = []
	for i in 20:
		var ti := Time.get_ticks_usec()
		await get_tree().process_frame
		idle.append((Time.get_ticks_usec() - ti) / 1000.0)
	idle.sort()
	idle_ms = idle[idle.size() / 2]
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _wait(3)
	print("BENCH: кадр без нажатий (медиана) %.2f мс; process %.2f мс, отрисовка CPU %.2f / GPU %.2f мс, окно %s" % [idle_ms,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(vp),
		RenderingServer.viewport_get_measured_render_time_gpu(vp), str(get_viewport().get_visible_rect().size)])
	_build_seq()
	print("BENCH: видов нажатий %d: %s" % [_seq.size(), ", ".join(_seq)])
	var done := 0
	var bi := 0
	while done < n:
		var t_b := 0
		var e_b := 0
		var n_b := 0
		var frames: Array[float] = []
		for j in per:
			if done >= n:
				break
			if menu.get("scene_t") != null:
				menu.set("scene_t", 4.0)   # фон меню держим на одной сцене: смена вида за окном — не про редактор
			var k: String = _seq[rng.randi_range(0, _seq.size() - 1)]
			var t0 := Time.get_ticks_usec()
			var l0 := PortraitKit.load_count
			var ok := _do(k)
			if not ok:
				continue
			var de := Time.get_ticks_usec() - t0
			await get_tree().process_frame
			var tf := Time.get_ticks_usec()
			await get_tree().process_frame
			var dt := Time.get_ticks_usec() - t0
			frames.append((Time.get_ticks_usec() - tf) / 1000.0)
			if not kinds.has(k):
				kinds[k] = {"n": 0, "us": 0, "max": 0, "emit": 0, "emit_max": 0, "loads": 0}
			var kd: Dictionary = kinds[k]
			kd["n"] = int(kd["n"]) + 1
			kd["emit"] = int(kd["emit"]) + de
			kd["emit_max"] = maxi(int(kd["emit_max"]), de)
			kd["loads"] = int(kd["loads"]) + PortraitKit.load_count - l0
			e_b += de
			kd["us"] = int(kd["us"]) + dt
			kd["max"] = maxi(int(kd["max"]), dt)
			t_b += dt
			n_b += 1
			done += 1
		await _wait(3)
		var st := _stats()
		st["ms_click"] = t_b / 1000.0 / maxi(1, n_b)
		st["ms_emit"] = e_b / 1000.0 / maxi(1, n_b)
		frames.sort()
		st["ms_frame"] = frames[frames.size() / 2] if not frames.is_empty() else 0.0
		rows.append(st)
		bi += 1
		print("BENCH пачка %2d: сигнал %.2f мс, нажатие+2 кадра %.2f мс, кадр (медиана) %.2f мс, узлов %d, объектов %d, сирот %d, ресурсов %d, текстуры %.1f МБ, загрузок слоёв %d (в памяти %d)" % [bi,
			st["ms_emit"], st["ms_click"], st["ms_frame"], st["nodes"], st["objects"], st["orphans"], st["resources"], st["tex_mb"], st["loads"], st["kit_tex"]])
	clicks = done
	if quiet_bg:
		menu.set_process(true)
		if is_instance_valid(bg):
			bg.visible = true
	var ks := kinds.keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return float(kinds[a]["us"]) / float(kinds[a]["n"]) > float(kinds[b]["us"]) / float(kinds[b]["n"]))
	print("BENCH: худшие нажатия, мс: сигнал среднее/макс | сигнал+2 кадра среднее/макс | загрузок слоёв на нажатие")
	for k: String in ks:
		var kd: Dictionary = kinds[k]
		var nk := float(kd["n"])
		print("BENCH   %-20s %4d раз | %7.2f %7.2f | %7.2f %7.2f | %5.1f" % [k, kd["n"], float(kd["emit"]) / 1000.0 / nk, float(kd["emit_max"]) / 1000.0,
			float(kd["us"]) / 1000.0 / nk, float(kd["max"]) / 1000.0, float(kd["loads"]) / nk])
	finished.emit()
