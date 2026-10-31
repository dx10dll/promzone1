extends Node
## Тест версии 1.55: живость цеха (искры, стружка, пар, аварийная лампа), звук пространства, ночь и сезоны.
## godot --headless --path . --audio-driver Dummy res://tests/stage155_test.tscn

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _ready() -> void:
	Defs.load_all()
	L.apply("ru")

	print("— эффекты станков")
	var q := ShopFx.level(2, false)
	check("sparks" in ShopFx.effects("welding", true, false, q), "сварка: искры")
	check("sparks" in ShopFx.effects("assembly", true, false, q), "слесарная сборка (болгарка): искры")
	check("chips" in ShopFx.effects("turning", true, false, q) and "chips" in ShopFx.effects("milling", true, false, q), "токарный и фрезерный: стружка")
	check("steam" in ShopFx.effects("heat", true, false, q) and "steam" in ShopFx.effects("casting", true, false, q), "термичка и литьё: пар")
	check(ShopFx.effects("welding", false, false, q).is_empty(), "стоящий станок — без эффектов")
	check("beacon" in ShopFx.effects("turning", false, true, q), "сломанный станок: аварийная лампа")
	check(ShopFx.effects("welding", true, false, q, 0.3).is_empty(), "далеко (мелкий масштаб) — без частиц")
	var calm := ShopFx.level(2, true)
	check(calm == 0 and ShopFx.effects("welding", true, false, calm).is_empty() and ShopFx.effects("heat", true, false, calm).is_empty(), "«Меньше анимации» выключает искры и пар")
	check("beacon" in ShopFx.effects("welding", true, true, calm), "…но аварийная лампа остаётся")
	check(ShopFx.beacon_k(0.1, false) != ShopFx.beacon_k(0.7, false) and ShopFx.beacon_k(0.1, true) == ShopFx.beacon_k(0.7, true), "лампа мигает, при «Меньше анимации» горит ровно")
	(get_node("/root/Game").settings as Dictionary)["reduce_motion"] = true
	FxLayer.refresh_quality()
	check(FxLayer.quality == 0 and ShopFx.calm(), "настройка reduce_motion обнуляет качество эффектов")
	(get_node("/root/Game").settings as Dictionary)["reduce_motion"] = false
	(get_node("/root/Game").settings as Dictionary)["quality"] = 2.0
	FxLayer.refresh_quality()
	check(FxLayer.quality == 2 and not ShopFx.calm(), "без настройки — полное качество")

	print("— звук пространства")
	check(SoundLayer.machine_db(100.0, 1.0) > SoundLayer.machine_db(700.0, 1.0), "дальше от центра камеры — тише")
	check(SoundLayer.machine_db(300.0, 2.0) > SoundLayer.machine_db(300.0, 0.6), "выше (дальше) камера — тише")
	check(SoundLayer.reverb_wet("workshop", 1.5) > 0.1 and SoundLayer.reverb_wet("canteen", 1.5) == 0.0, "реверберация только над цехом")
	check(SoundLayer.reverb_wet("workshop", 2.0) > SoundLayer.reverb_wet("workshop", 0.6), "и сильнее при приближении")
	check(SoundLayer.city_gain(0.0, false) > SoundLayer.city_gain(1.0, false) and SoundLayer.city_gain(1.0, false) > 0.0, "улица слышна тихо даже вблизи, громче издали")
	check(SoundLayer.city_gain(0.5, true) < SoundLayer.city_gain(0.5, false), "в помещении город глуше")
	var snd: Node = get_node("/root/Snd")
	var bi := AudioServer.get_bus_index("Shop")
	check(bi >= 0 and AudioServer.get_bus_effect(bi, 0) is AudioEffectReverb, "шина цеха с реверберацией")
	check(AudioServer.get_bus_send(bi) == "SFX" and snd.bus_for("m_lathe") == "Shop" and snd.bus_for("grinder") == "Shop", "станки идут через шину цеха в «Звуки»")
	check(AudioServer.get_bus_index("Music") >= 0 and snd.bus_for("cough") == "People", "музыка и прочие шины на месте")
	check(snd != null, "автозагрузка Snd")

	print("— сезонная картинка")
	check(SeasonLook.look("winter") == "winter" and SeasonLook.look("autumn") == "autumn" and SeasonLook.look("summer") == "base" and SeasonLook.look("spring") == "base", "вид земли по сезону")
	check(SeasonLook.wash("winter", true, 5).a > 0.3 and SeasonLook.wash("autumn", true, 5).a > 0.2 and SeasonLook.wash("base", true, 5).a == 0.0, "налёт: зима и осень есть, лето нет")
	check(SeasonLook.leaf_count("autumn", 100) >= 1 and SeasonLook.leaf_count("summer", 100) == 0, "листья только осенью")
	var any_p := false
	var any_s := false
	for h in 40:
		any_p = any_p or SeasonLook.puddle("autumn", h)
		any_s = any_s or SeasonLook.snow_patch("winter", h)
	check(not any_p and any_s and not SeasonLook.snow_patch("autumn", 9), "1.56: луж нет (владелец просил убрать), снежные пятна зимой")

	var gb := Tex.tile("grass_0")
	var gw := SeasonLook.baked("grass_0", "winter", true)
	var ga := SeasonLook.baked("grass_0", "autumn", true)
	check(gb != null and gw != gb and ga != gb and SeasonLook.baked("grass_0", "base", true) == gb, "плитка земли выбирается по сезону")
	check(gw.get_image().get_pixel(20, 20).get_luminance() > gb.get_image().get_pixel(20, 20).get_luminance() + 0.03, "зимняя трава светлее (иней)")
	check(ga.get_image().get_pixel(20, 20).r > ga.get_image().get_pixel(20, 20).b and ga.get_image().get_pixel(20, 20).g > gb.get_image().get_pixel(20, 20).g * 0.8, "осенняя трава желтее")

	print("— ночь, лампы и фонари")
	var g := Scenario.new_game("garage", "mech", "calm", 1551)
	g.story.enabled = false
	g.tick(0.5)
	var pts := DayNight.street_lamp_points(g.world)
	check(pts.size() >= 6, "уличные фонари вдоль дороги и забора: %d" % pts.size())
	var dn := DayNight.new()
	var rt := Node2D.new()
	add_child(rt)
	dn.setup(g, rt, rt)
	rt.add_child(dn)
	dn._process(0.0)
	check(dn.lamps.is_empty(), "PointLight2D для ламп больше нет (дешёвые пятна)")
	check(dn.street.size() == pts.size(), "фонари переданы в слой света")
	var sp := {"id": -5, "pos": Vector2.ZERO, "r": 3.0, "col": Color.WHITE, "dark": false}
	dn.night = 1.0
	check(dn.spot_alpha(sp) == 0.0, "не подключённая лампа не светит")
	g.power.lamp_on[-5] = true
	check(dn.spot_alpha(sp) > 0.4, "горящая лампа ночью светит")
	dn.night = 0.0
	check(dn.spot_alpha(sp) < 0.05, "днём пятно не видно")

	print(("ИТОГ: все проверки пройдены" if fails.is_empty() else "ПРОВАЛЕНО: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
