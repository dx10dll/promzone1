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


# ---------------------------------------------------------------- 1.38.2: долгий прогон (soak)
## `Promzona -- --soak-editor=<сек> [--soak-mode=click|idle|menu]`: фон меню ЖИВОЙ (как у игрока), каждую секунду —
## строка SOAK с кадром (среднее/макс), process, объектами/узлами/сиротами/ресурсами, памятью, отрисовкой, узлами фона,
## твинами, таймерами, кэшем портретов. click — щёлкать редактор в темпе человека (1–3 нажатия в секунду, с паузами),
## idle — редактор открыт, без нажатий, menu — одно главное меню. В конце — сравнение первой и последней минуты и
## какие коллекции (массивы/словари в полях скриптов, в т. ч. статических) выросли.

var soak_rows: Array = []          ## по секунде: словарь показателей
var soak_grew: Array = []          ## [имя коллекции, было, стало] — выросшие сильнее всего
var _fr: Array[float] = []         ## длительности кадров за текущую секунду, мс
var _last_us := 0


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_fr.append((now - _last_us) / 1000.0)
	_last_us = now


func _max_minute() -> float:
	var m := 0.0
	if menu:
		for w: Sim in menu.get("worlds"):
			m = maxf(m, w.minute)
	return m


static func count_nodes(n: Node) -> int:
	if n == null or not is_instance_valid(n):
		return 0
	var c := 1
	for ch in n.get_children():
		c += count_nodes(ch)
	return c


func soak_sample(t: int) -> Dictionary:
	var fr := _fr.duplicate()
	_fr.clear()
	var avg := 0.0
	var mx := 0.0
	for f in fr:
		avg += f
		mx = maxf(mx, f)
	avg /= maxf(1.0, float(fr.size()))
	var bg: Node = menu.get("scene_root") as Node if menu else null
	var timers := get_tree().root.find_children("*", "Timer", true, false).size()
	var st := {"t": t, "frames": fr.size(), "ms_avg": avg, "ms_max": mx,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"vid_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"robjs": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"bg_nodes": count_nodes(bg), "tweens": get_tree().get_processed_tweens().size(), "timers": timers,
		"kit": PortraitKit.loaded_count(), "people": Tex._people_hi.size(), "clicks": clicks,
		"scene": int(menu.get("scene_i")) if menu else 0, "minute": _max_minute()}
	return st


## Сумма размеров коллекций в полях скрипта obj (и на уровень глубже — в объектах-полях). out: имя -> размер.
static func scan_obj(obj: Object, prefix: String, out: Dictionary, depth: int, seen: Dictionary) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var oid := obj.get_instance_id()
	if seen.has(oid):
		return
	seen[oid] = true
	for p: Dictionary in obj.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var nm := str(p["name"])
		var v: Variant = obj.get(nm)
		var key := prefix + "." + nm
		match typeof(v):
			TYPE_ARRAY, TYPE_DICTIONARY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
					TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
					TYPE_PACKED_COLOR_ARRAY:
				out[key] = int(out.get(key, 0)) + int(v.size())
			TYPE_OBJECT:
				if depth > 0 and v != null and is_instance_valid(v) and not (v is Node) and not (v is Resource and not (v is Script)):
					scan_obj(v as Object, key, out, depth - 1, seen)


## Снимок: коллекции во всех узлах дерева (по классу узла — сумма) и в статических полях глобальных классов.
func scan_all() -> Dictionary:
	var out := {}
	var seen := {}
	if menu:   # сначала заводы фона: их поля — под постоянными именами (иначе их «увидит» первый попавшийся вид)
		var ws: Array = menu.get("worlds")
		for i in ws.size():
			scan_obj(ws[i] as Object, "menu_world%d" % i, out, 2, seen)
	for n: Node in get_tree().root.find_children("*", "", true, false):
		var s := n.get_script() as Script
		if s == null:
			continue
		var cls := s.get_global_name()
		if cls == &"":
			cls = StringName(s.resource_path.get_file())
		scan_obj(n, "node:" + str(cls), out, 2, seen)
	for c: Dictionary in ProjectSettings.get_global_class_list():
		var sc := load(str(c["path"])) as Script
		if sc:
			for p: Dictionary in sc.get_property_list():
				var v: Variant = sc.get(str(p["name"]))
				if v is Array or v is Dictionary:
					var key := "static:" + str(c["class"]) + "." + str(p["name"])
					out[key] = int(out.get(key, 0)) + int(v.size())
	return out


func _soak_line(st: Dictionary) -> String:
	return "SOAK t=%4d кадров %3d кадр %.2f/%.1f мс process %.2f мс объектов %d узлов %d сирот %d ресурсов %d static %.1f МБ текстуры %.1f МБ видео %.1f МБ draw %d robj %d фон-узлов %d твинов %d таймеров %d кэш-портр %d растры-людей %d нажатий %d вид %d мин-завода %.0f" % [
		st["t"], st["frames"], st["ms_avg"], st["ms_max"], st["process_ms"], st["objects"], st["nodes"], st["orphans"], st["resources"],
		st["static_mb"], st["tex_mb"], st["vid_mb"], st["draws"], st["robjs"], st["bg_nodes"], st["tweens"], st["timers"], st["kit"], st["people"], st["clicks"], st["scene"], st["minute"]]


## Средние показатели за секунды [a, b).
func soak_avg(a: int, b: int) -> Dictionary:
	var out := {}
	var n := 0
	for st: Dictionary in soak_rows:
		if int(st["t"]) >= a and int(st["t"]) < b:
			n += 1
			for k: String in st.keys():
				out[k] = float(out.get(k, 0.0)) + float(st[k])
	for k: String in out.keys():
		out[k] = float(out[k]) / maxf(1.0, float(n))
	return out


## Долгий прогон: secs секунд по-настоящему, mode — "click", "idle" или "menu". hold_scene — фон живой, но без смены
## видов (для теста: кадр сравнивается на одном и том же виде). Перед замером — прогрев: все виды по разу
## (их текстуры грузятся при первом показе — это не рост).
var hold_scene := false


func soak(m: Node, secs: int, mode: String, seed_v: int = 1382) -> void:
	menu = m
	rng.seed = seed_v
	for i in MenuScenes.count():
		menu.call("jump", i)
		await _wait(4)
	if mode != "menu":
		ed = menu.get("ng_root") as CustomWorkersUI
		if ed == null:
			menu.call("_show_custom")
			await _wait(5)
			ed = menu.get("ng_root") as CustomWorkersUI
		while ed.workers().size() < 6:
			_press(ed.save_btn)
			await _wait(1)
			_press(_btns(ed, ["+  Новый рабочий"]).front())
			await _wait(1)
		_build_seq()
	await _wait(10)
	var scan0 := scan_all()
	var t0 := Time.get_ticks_msec()
	var next_click := t0 + 1000
	var next_sec := t0 + 1000
	var sec := 0
	_fr.clear()
	print("SOAK: режим %s, %d с, версия %s, окно %s" % [mode, secs, ProjectSettings.get_setting("application/config/version"),
		str(get_viewport().get_visible_rect().size)])
	while sec < secs:
		await get_tree().process_frame
		if hold_scene:
			menu.set("scene_t", 4.0)
		var now := Time.get_ticks_msec()
		if mode == "click" and now >= next_click and is_instance_valid(ed):
			var k: String = _seq[rng.randi_range(0, _seq.size() - 1)]
			if _do(k):
				clicks += 1
			# человек: 1–3 нажатия в секунду, иногда пауза на пару секунд (посмотреть на портрет)
			next_click = now + (rng.randi_range(2000, 5000) if rng.randf() < 0.12 else rng.randi_range(330, 1000))
		if now >= next_sec:
			next_sec += 1000
			sec += 1
			var st := soak_sample(sec)
			soak_rows.append(st)
			print(_soak_line(st))
	var scan1 := scan_all()
	var grew: Array = []
	for k: String in scan1.keys():
		var a := int(scan0.get(k, 0))
		var b := int(scan1[k])
		if b > a + 10 and b > a * 1.2:
			grew.append([k, a, b])
	grew.sort_custom(func(x: Array, y: Array) -> bool: return int(x[2]) - int(x[1]) > int(y[2]) - int(y[1]))
	soak_grew = grew
	print("SOAK: выросшие коллекции (было → стало): %d" % grew.size())
	for g: Array in grew.slice(0, 40):
		print("SOAK   %-70s %7d → %7d" % [g[0], g[1], g[2]])
	var m1 := mini(60, maxi(1, secs / 5))
	var a1 := soak_avg(m1 / 6, m1 + m1 / 6)       # первая «минута» (без первых секунд разгона)
	var a2 := soak_avg(secs - m1, secs + 1)        # последняя
	print("SOAK ИТОГ (%s): первые %d с → последние %d с" % [mode, m1, m1])
	for k: String in ["ms_avg", "ms_max", "frames", "process_ms", "objects", "nodes", "orphans", "resources", "static_mb", "tex_mb", "vid_mb",
			"draws", "robjs", "bg_nodes", "tweens", "timers", "kit", "people"]:
		print("SOAK ИТОГ   %-11s %10.2f → %10.2f  (×%.2f)" % [k, float(a1.get(k, 0.0)), float(a2.get(k, 0.0)),
			float(a2.get(k, 0.0)) / maxf(0.001, float(a1.get(k, 0.0)))])
	# по видам фона: кадр в первой и последней трети прогона (виды рисуются по-разному — сравнивать один с одним)
	for sc in MenuScenes.count():
		var f1 := _scene_ms(sc, 0, secs / 3)
		var f2 := _scene_ms(sc, secs - secs / 3, secs + 1)
		if f1 > 0.0 and f2 > 0.0:
			print("SOAK ИТОГ   вид %d %-22s кадр %8.2f → %8.2f мс (×%.2f)" % [sc, MenuScenes.caption(sc), f1, f2, f2 / f1])
	finished.emit()


func _scene_ms(sc: int, a: int, b: int) -> float:
	var sum := 0.0
	var n := 0
	for st: Dictionary in soak_rows:
		if int(st["scene"]) == sc and int(st["t"]) >= a and int(st["t"]) < b and int(st["frames"]) > 0:
			sum += float(st["ms_avg"])
			n += 1
	return sum / n if n > 0 else 0.0
