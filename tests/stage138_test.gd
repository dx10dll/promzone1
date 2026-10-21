extends SceneTree
## Тест версии 1.38 «Новые иконки»: все 102 значка владельца из assets/ui/icons/icons.json на месте и находятся
## через Tex.ui / UITheme.micon (emo_* — через Tex.emo), помечены как цветные (не перекрашиваются);
## у каждой зоны из Defs.rooms и у каждого сценария есть свой цветной значок.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage138_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _initialize() -> void:
	Defs.load_all()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/icons/icons.json"))
	check(d is Array and (d as Array).size() == 102, "icons.json: 102 значка")
	var bad: Array[String] = []
	var n := 0
	if d is Array:
		for e: Dictionary in d:
			var id := str(e["id"])
			n += 1
			var t: Texture2D = Tex.emo(id.substr(4)) if id.begins_with("emo_") else Tex.ui(id)
			if t == null or not Tex.is_color(t) or UITheme.micon(id) == null:
				bad.append(id)
	check(n == 102 and bad.is_empty(), "все значки находятся через Tex.ui/Tex.emo и micon, цветные%s" % ("" if bad.is_empty() else ": нет " + ", ".join(bad)))
	var nz: Array[String] = []
	for k: String in Defs.rooms.keys():
		if k.begins_with("_"):
			continue
		if not Tex.is_color(Tex.ui_world("zone_" + k)):
			nz.append(k)
	check(nz.is_empty(), "у каждой зоны цветной значок владельца %s" % str(nz))
	var ns: Array[String] = []
	for k: String in Defs.scenarios.keys():
		if not Tex.is_color(Tex.ui("scn_" + k)):
			ns.append(k)
	check(ns.is_empty(), "у каждого сценария цветной значок %s" % str(ns))
	check(Tex.tint(Tex.ui("fire"), Color(1, 0, 0, 0.5)) == Color(1, 1, 1, 0.5), "цветной значок не перекрашивается, прозрачность сохраняется")
	check(not Tex.is_color(Tex.ui("zone_erase")), "векторные значки остались векторными")
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
