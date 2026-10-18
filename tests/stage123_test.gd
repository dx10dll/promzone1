extends SceneTree
## Тест версии 1.23 «Живой завод»: снос начального забора, мелкие подписи оверлеев,
## звуки по приближению камеры, новый декор.
## godot --headless --path . -s res://tests/stage123_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()

	print("— начальный забор сносится")
	var g := Scenario.new_game("garage", "mech", "calm", 231)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	var w := g.world
	var fy := w.plot.end.y
	var fc := Vector2i(w.plot.position.x + 3, fy)
	if w.get_wall(fc) != World.W_FENCE:
		for x in range(w.plot.position.x, w.plot.end.x):
			if w.get_wall(Vector2i(x, fy)) == World.W_FENCE:
				fc = Vector2i(x, fy)
				break
	check(w.get_wall(fc) == World.W_FENCE, "забор у дороги на месте (%d, %d)" % [fc.x, fc.y])
	check(w.inner_fence(fc), "забор по краю участка — свой")
	check(not w.inner_fence(Vector2i(0, 0)), "край карты — не свой")
	check(g.place_demolish(fc), "снос забора поставлен в план")
	for i in 2400:
		g.tick(0.5)
		if w.get_wall(fc) == World.W_NONE:
			break
	check(w.get_wall(fc) == World.W_NONE, "рабочие разобрали забор")

	print("— звуки помещений и города")
	for snd in ["amb_canteen", "amb_locker", "amb_office", "amb_shop", "amb_boiler", "amb_city", "amb_train", "grinder", "dishes", "train_horn", "pigeon_coo", "meow"]:
		check(ResourceLoader.exists("res://assets/sound/%s.ogg" % snd) or ResourceLoader.exists("res://assets/sound/%s.wav" % snd), "звук " + str(snd))

	print("— новый декор")
	var decor := ["cactus", "monstera", "flower_bed", "bust", "floor_clock", "water_cooler", "coat_rack", "radio", "samovar",
		"trophy_case", "globe", "ny_tree", "flagpole", "statue_worker", "notice_board"]
	for id: String in decor:
		var d: Dictionary = Defs.objects.get(id, {})
		check(str(d.get("kind", "")) == "decor" and int(d.get("prestige", 0)) > 0, "декор «%s» в каталоге" % str(d.get("name", id)))
		check(ResourceLoader.exists("res://assets/objects/%s.svg" % id) or ResourceLoader.exists("res://assets/objects/%s.png" % id), "картинка " + id)

	print("— быстрые справочники (оптимизация)")
	var g2 := Scenario.new_game("garage", "mech", "calm", 232)
	g2.story.enabled = false
	var a := S.hire(g2, "turner", "turning", 4)
	var b := S.hire(g2, "miller", "milling", 4)
	check(g2.get_worker(a.id) == a and g2.get_worker(b.id) == b, "человек находится по номеру")
	check(g2.get_worker(-5) == null, "несуществующий номер — пусто")
	g2.training._add_rel(a, b, 90.0)
	check(g2.training.friends(a).has(b), "друзья видны сразу после знакомства")
	g2.training._add_rel(a, b, -190.0)
	check(not g2.training.friends(a).has(b) and g2.training.foes(a).has(b), "поссорились — список обновился")
	var n0 := g2.things_of("decor").size()
	var t := g2.place_thing("cactus", Vector2i(g2.world.plot.position.x + 2, g2.world.plot.position.y + 2), true, false)
	check(g2.things_of("decor").size() == n0 + 1 and g2.things_of("decor").has(t), "новый объект сразу в списке по виду")
	g2.things_of("decor").clear()
	check(g2.things_of("decor").size() == n0 + 1, "чужие правки списка не портят запомненное")
	g2.fire(b, true, true)
	check(g2.get_worker(b.id) == null, "ушедший больше не находится")
	check(g2.training.foes(a).is_empty(), "ушедший пропал из недругов")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
