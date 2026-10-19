extends SceneTree
## Тест версий 1.33–1.34 «Новые портреты» (1.34 — исправленный набор: маски шеи и воротников, веки, головные уборы,
## серая одежда в цвет спецовки): все слои и маски набора на месте и читаются; рецепт и сборка портрета
## для 200 случайных людей (оба пола, все телосложения, причёски, бороды) — без ошибок; одно и то же лицо —
## одна и та же картинка (хэш); кэш работает; окраска не трогает прозрачность; любая черта из редактора
## «Создать рабочего» видна на портрете; Portrait рисует новый набор, а без него — старый.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage133_test.gd

var fails: Array[String] = []

const BASE := ["head_m_oval", "head_m_square", "head_m_round", "head_m_long", "head_f_soft", "head_f_oval", "head_f_round",
	"eyes_almond", "eyes_narrow", "eyes_round", "eyes_heavy", "eyes_deep",
	"brows_straight", "brows_arched", "brows_thick", "brows_thin", "brows_angled", "brows_bushy",
	"nose_small", "nose_straight", "nose_long", "nose_wide", "nose_hooked",
	"mouth_neutral", "mouth_smile", "mouth_thin", "mouth_full", "mouth_down",
	"beard_mustache", "beard_full", "beard_goatee", "beard_stubble", "beard_chevron", "beard_short",
	"glasses", "earrings", "freckles", "lines_mid", "lines_old", "kerchief_f", "collar_kerchief_f",
	"eyes_almond_lids", "eyes_narrow_lids", "eyes_round_lids", "eyes_heavy_lids", "eyes_deep_lids",
	"cap", "helmet", "welder_mask", "ushanka"]
const HAIRS := ["short", "crew", "side", "slick", "receding", "bald", "curly", "mullet", "bob", "bun", "ponytail", "long", "pixie", "curly_f", "braid", "perm"]
const COLLARS := ["overall", "shirt", "jacket", "suit", "robe", "sweater", "vest", "firefighter"]


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _initialize() -> void:
	Defs.load_all()
	_layers()
	_recipes()
	_compose()
	_determinism()
	_cache()
	_alpha()
	_editor_options()
	_v2()
	await _portrait()
	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)


func _all_base() -> Array:
	var out: Array = BASE.duplicate()
	for h: String in HAIRS:
		out.append("hair_%s_front" % h)
		out.append("hair_%s_back" % h)
	for c: String in COLLARS:
		for g: String in ["m", "f"]:
			out.append("collar_%s_%s" % [c, g])
	for g2: String in ["m", "f"]:
		for n: String in ["neck_thin_", "neck_strong_", "cheeks_full_", "chin_double_"]:
			out.append(n + g2)
	return out


func _layers() -> void:
	print("— слои набора")
	check(PortraitKit.available(), "набор assets/portrait2 найден (layers.json и текстуры)")
	var base := _all_base()
	check(base.size() == 106, "в наборе 106 игровых слоёв (без base_template и вспомогательных серых): %d" % base.size())
	var bad: Array = []
	for n: String in base:
		if not PortraitKit.has(n) or PortraitKit.tex(n) == null:
			bad.append(n)
	check(bad.is_empty(), "все 106 слоёв читаются" + ("" if bad.is_empty() else ": нет " + str(bad)))
	var extra := 0
	for n2: Variant in PortraitKit.names():
		if PortraitKit.tex(str(n2)) == null:
			bad.append(n2)
		extra += 1
	check(bad.is_empty() and extra >= 150, "всего слоёв с производными (радужка, голова без шеи, ткань, кожа выреза): %d, все читаются" % extra)
	check(not PortraitKit.has("base_template"), "base_template в игру не попал (только для выравнивания)")
	var junk: Array = []
	for n3: Variant in PortraitKit.names():
		var s3 := str(n3)
		if s3.ends_with("_gray") or (s3.begins_with("collar_") and (s3.ends_with("_skin") or s3.ends_with("_back"))) or s3.ends_with("_lid"):
			junk.append(s3)
	check(junk.is_empty(), "нет старых обходных слоёв 1.33 (_lid, _back, _skin) и исходных серых" + ("" if junk.is_empty() else ": " + str(junk)))
	# маски: тело внутри каждого воротника, волосы под головными уборами
	var mbad: Array = []
	for c: String in COLLARS + ["kerchief"]:
		for g: String in ["m", "f"]:
			var cn := "collar_%s_%s" % [c, g]
			if PortraitKit.has(cn) and (not PortraitKit.has_mask("mask_%s_keep" % cn) or PortraitKit.tex("mask_%s_keep" % cn) == null):
				mbad.append(cn)
	for h: String in ["cap", "helmet", "welder_mask", "ushanka"]:
		if not PortraitKit.has_mask("mask_hat_" + h) or PortraitKit.tex("mask_hat_" + h) == null:
			mbad.append(h)
	check(mbad.is_empty() and PortraitKit.mask_names().size() == 21, "масок 21 (17 воротников, 4 убора), все читаются" + ("" if mbad.is_empty() else ": нет " + str(mbad)))
	var mt := PortraitKit.tex("mask_collar_suit_m_keep")
	check(mt != null and mt.get_size() == Vector2(512, 512), "маска на том же холсте 512")
	for h2: String in ["head_m_oval", "head_f_round"]:
		check(PortraitKit.has(h2 + "_cut") and PortraitKit.bbox(h2 + "_cut").end.y < PortraitKit.bbox(h2).end.y, "%s_cut: своя шея у головы срезана маской keep_face" % h2)
	var t := PortraitKit.tex("head_m_oval")
	check(t != null and t.get_size() == Vector2(512, 512), "холст 512×512: %s" % str(t.get_size() if t else Vector2.ZERO))
	var bb := PortraitKit.bbox("eyes_almond")
	check(bb.position.y > 170 and bb.end.y < 220 and absf(bb.get_center().x - 256.0) < 4.0, "глаза на своём месте холста (ось x=256): %s" % str(bb))


func _looks(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1330
	var profs := ["turner", "qc", "electrician", "miller", "welder", "caster", "painter", "assembler", "laborer", "builder",
		"foreman", "accountant", "cook", "nurse", "guard", "chief", "hr", "cleaner", "cnc_operator", "lawyer", "fitter", "setter"]
	var bodies: Array = People.BODIES.keys()
	var out: Array = []
	for i in n:
		var w := People.make(rng, str(profs[i % profs.size()]), 0.5)
		var lk := w.look
		lk["body"] = bodies[i % bodies.size()]
		var hs: Array = People.HAIR_F if w.female else People.HAIR_M
		lk["hair"] = hs[(i / 2) % hs.size()]
		if not w.female:
			lk["beard"] = ["", "mustache", "full", "goatee", "stubble", "chevron", "short"][i % 7]
		lk["skin"] = i % People.SKINS.size()
		if i % 9 == 0:
			lk["outfit"] = "fireman"
		lk.erase("_face")
		out.append([lk, {"age": [19, 30, 41, 55, 63][i % 5], "mood": [15.0, 50.0, 85.0][i % 3]}])
	return out


func _recipes() -> void:
	print("— рецепты: 200 случайных людей")
	var missing: Array = []
	var both := {}
	var t0 := Time.get_ticks_usec()
	for e: Array in _looks(200):
		var lk: Dictionary = e[0]
		both[bool(lk.get("fem", false))] = true
		var r := PortraitKit.recipe(lk, e[1])
		for n: Variant in PortraitKit.layer_names(r):
			if not PortraitKit.has(str(n)):
				missing.append(n)
		for gname: String in PortraitKit.GROUPS:
			var m := str(r.get("mask_" + gname, ""))
			if m != "" and not PortraitKit.has_mask(m):
				missing.append(m)
	var us := float(Time.get_ticks_usec() - t0) / 200.0
	check(missing.is_empty(), "все слои рецептов есть в наборе" + ("" if missing.is_empty() else ": " + str(missing.slice(0, 6))))
	check(both.size() == 2, "и мужчины, и женщины")
	check(us < 2000.0, "рецепт собирается быстро: %.0f мкс на человека" % us)
	# телосложение: шея, щёки, второй подбородок, ширина плеч
	var lk2 := {"fem": false, "skin": 1, "hair": "short", "hair_col": "#4a3020", "outfit": "overall", "fs": 5, "age": 40}
	lk2["body"] = "vfat"
	var r2 := PortraitKit.recipe(lk2, {})
	var n2 := _names(r2)
	check(n2.has("cheeks_full_m") and n2.has("chin_double_m") and not n2.has("neck_strong_m") and float(r2["sx"]) > 1.05, "очень полный: щёки, второй подбородок, шире плечи")
	check(n2.has("head_m_round_cut") and n2.find("chin_double_m") > n2.find("head_m_round_cut") and n2.find("chin_double_m") < n2.find("eyes_" + str(People.face(lk2)["eyes"])), "второй подбородок — поверх круглой головы без своей шеи, до черт лица")
	lk2["body"] = "fat"
	var nf := _names(PortraitKit.recipe(lk2, {}))
	check(nf.has("head_m_round") and nf.has("cheeks_full_m") and not nf.has("head_m_round_cut") and not nf.has("neck_strong_m"), "полный: круглая голова (новая), щёки, своя шея")
	lk2["body"] = "vthin"
	var r3 := PortraitKit.recipe(lk2, {})
	var n3 := _names(r3)
	check(n3.has("neck_thin_m") and n3.has("head_m_long_cut") and not n3.has("head_m_long") and float(r3["sx"]) < 0.95, "очень худой: тонкая шея вместо своей, вытянутое лицо, уже плечи")
	check(n3.find("neck_thin_m") < n3.find("head_m_long_cut") and _col(r3, "neck_thin_m").a == 1.0 and str(r3["mask_body"]) == "mask_collar_overall_m_keep", "тонкая шея — за головой, непрозрачная, тело внутри воротника")
	lk2["body"] = "normal"
	var rn := PortraitKit.recipe(lk2, {})
	var hn := "head_m_" + str(rn["head"])
	check(_names(rn).has(hn) and not str(_names(rn)).contains("_cut") and not str(_names(rn)).contains("neck_"), "обычный: своя шея головы, без дополнительной")
	lk2["body"] = "strong"
	check(_names(PortraitKit.recipe(lk2, {})).has("neck_strong_m"), "могучий: сильная шея")
	# одежда по спецовке
	var outfits := {"overall": "overall", "coat": "robe", "jacket": "jacket", "fireman": "firefighter", "shirt": "shirt"}
	var ok := true
	for o: String in outfits:
		var lk3 := lk2.duplicate()
		lk3["body"] = "normal"
		lk3["outfit"] = o
		lk3["fs"] = 7
		if not _names(PortraitKit.recipe(lk3, {})).has("collar_%s_m" % str(outfits[o])):
			ok = false
			print("    одежда %s -> %s" % [o, str(_names(PortraitKit.recipe(lk3, {})))])
	check(ok, "одежда по спецовке: комбинезон, халат, куртка, боёвка, рубашка")
	var fk := {"fem": true, "skin": 0, "hair": "perm", "hair_col": "#9a6a3a", "outfit": "overall", "hat": "kerchief", "hat_col": "#3d5a7a", "fs": 3, "age": 50}
	var nk := _names(PortraitKit.recipe(fk, {}))
	check(nk.has("kerchief_f_g") and nk.has("collar_kerchief_f") and nk.find("kerchief_f_g") > nk.find("hair_perm_front"), "работница в косынке: косынка поверх волос, рабочая рубашка")
	# возраст: морщины и седина
	var old := PortraitKit.recipe(lk2, {"age": 60})
	var young := PortraitKit.recipe(lk2, {"age": 25})
	check(_names(old).has("lines_old") and not _names(young).has("lines_old") and not _names(young).has("lines_mid"), "морщины по возрасту")
	check(_col(old, "hair_short_front").s < _col(young, "hair_short_front").s, "к старости волосы седеют")
	# настроение: улыбка и грусть
	check(_names(PortraitKit.recipe(lk2, {"mood": 90.0})).has("mouth_smile") and _names(PortraitKit.recipe(lk2, {"mood": 10.0})).has("mouth_down"), "настроение видно по губам")


func _names(r: Dictionary) -> Array:
	return PortraitKit.layer_names(r)


func _col(r: Dictionary, n: String) -> Color:
	for gname: String in PortraitKit.GROUPS:
		for l: Array in r.get(gname, []):
			if str(l[0]) == n:
				return l[1]
	return Color.BLACK


func _compose() -> void:
	print("— сборка картинки: 200 случайных людей")
	var bad := 0
	var t0 := Time.get_ticks_msec()
	for e: Array in _looks(200):
		var im := PortraitKit.compose_image(e[0], e[1], 96)
		if im == null or im.get_width() != 96 or im.get_pixel(48, 40).a < 0.9 or im.get_pixel(48, 92).a < 0.9:
			bad += 1
	var ms := float(Time.get_ticks_msec() - t0) / 200.0
	check(bad == 0, "все 200 портретов собрались (лицо и одежда на месте), ошибок: %d" % bad)
	print("    сборка в Image 96 px: %.1f мс на портрет (в игре портрет рисует видеокарта по рецепту — без сборки)" % ms)
	var lk: Dictionary = (_looks(1)[0] as Array)[0]
	var t1 := Time.get_ticks_usec()
	var big := PortraitKit.compose_image(lk, {}, 256)
	var ms2 := float(Time.get_ticks_usec() - t1) / 1000.0
	check(big.get_width() == 256, "сборка 256 px: %.1f мс" % ms2)


func _hash(im: Image) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(im.get_data())
	return hc.finish().hex_encode()


func _determinism() -> void:
	print("— детерминизм")
	var e: Array = _looks(7)[6]
	var a := _hash(PortraitKit.compose_image(e[0], e[1], 128))
	var lk2: Dictionary = (e[0] as Dictionary).duplicate(true)
	var b := _hash(PortraitKit.compose_image(lk2, (e[1] as Dictionary).duplicate(), 128))
	check(a == b, "то же лицо — та же картинка (sha256 %s…)" % a.left(12))
	var other: Array = _looks(8)[7]
	check(_hash(PortraitKit.compose_image(other[0], other[1], 128)) != a, "другое лицо — другая картинка")
	var r1 := str(PortraitKit.recipe(e[0], e[1]))
	PortraitKit._rec.clear()
	PortraitKit._rec_order.clear()
	check(str(PortraitKit.recipe(e[0], e[1])) == r1, "рецепт после очистки кэша тот же")


func _cache() -> void:
	print("— кэш")
	var looks := _looks(140)
	var e: Array = looks[0]
	var c0 := PortraitKit.compose_count
	var t1 := PortraitKit.compose_texture(e[0], e[1], 64)
	var t2 := PortraitKit.compose_texture(e[0], e[1], 64)
	check(t1 != null and t1 == t2 and PortraitKit.compose_count == c0 + 1, "второй раз берётся из кэша")
	for i in range(1, 140):
		PortraitKit.compose_texture((looks[i] as Array)[0], (looks[i] as Array)[1], 64)
	check(PortraitKit._comp.size() <= PortraitKit.CACHE_MAX and PortraitKit._comp_order.size() <= PortraitKit.CACHE_MAX, "кэш не растёт больше %d: %d" % [PortraitKit.CACHE_MAX, PortraitKit._comp.size()])
	var c1 := PortraitKit.compose_count
	PortraitKit.compose_texture(e[0], e[1], 64)
	check(PortraitKit.compose_count == c1 + 1, "самый старый вытеснен и собирается заново")
	check(PortraitKit._rec.size() <= PortraitKit.CACHE_MAX, "кэш рецептов ограничен: %d" % PortraitKit._rec.size())


func _alpha() -> void:
	print("— окраска")
	var src := PortraitKit._layer_img("head_m_oval", 128)
	var bb := Rect2i(0, 0, 128, 128)
	var dark := PortraitKit._tint_region(src, bb, Color(str(People.SKINS[5])), false, 1.0, 0.25)
	var light := PortraitKit._tint_region(src, bb, Color(str(People.SKINS[0])), false, 1.0, 0.25)
	var same := true
	var diff := 0.0
	for y in range(0, 128, 3):
		for x in range(0, 128, 3):
			var s := src.get_pixel(x, y)
			if absf(dark.get_pixel(x, y).a - s.a) > 0.003 or absf(light.get_pixel(x, y).a - s.a) > 0.003:
				same = false
			if s.a > 0.9:
				diff += light.get_pixel(x, y).get_luminance() - dark.get_pixel(x, y).get_luminance()
	check(same, "прозрачность слоя после окраски та же (светлая и тёмная кожа)")
	check(diff > 0.0, "тёмная кожа темнее светлой")
	# штриховка на тёмной коже различима: разброс яркости внутри лица
	var lo := 1.0
	var hi := 0.0
	for y2 in range(40, 75):
		for x2 in range(45, 83):
			var p := dark.get_pixel(x2, y2)
			if p.a > 0.95:
				lo = minf(lo, p.get_luminance())
				hi = maxf(hi, p.get_luminance())
	check(hi - lo > 0.12, "на тёмной коже штриховка видна: разброс яркости %.2f" % (hi - lo))


func _editor_options() -> void:
	print("— редактор: каждая черта видна на портрете")
	for fem: bool in [false, true]:
		var base := {"fem": fem, "skin": 2, "hair": "bob" if fem else "short", "hair_col": "#4a3020", "outfit": "overall", "fs": 11, "age": 35, "body": "normal",
			"face_ovr": {"head": "round" if fem else "oval", "eyes": "almond", "brows": "straight", "nose": "small", "mouth": "neutral", "freckles": false, "earrings": false}}
		var bad: Array = []
		var heads: Array = PortraitKit.heads(fem)
		var groups := {"head": heads, "eyes": People.EYE_KINDS, "brows": People.BROW_KINDS, "nose": People.NOSE_KINDS, "mouth": People.MOUTH_KINDS}
		for k: String in groups:
			var seen := {}
			for v: Variant in groups[k]:
				var lk: Dictionary = base.duplicate(true)
				(lk["face_ovr"] as Dictionary)[k] = v
				seen[str(_names(PortraitKit.recipe(lk, {"mood": 50.0})))] = true
			if seen.size() != (groups[k] as Array).size():
				bad.append(k)
		for hk: Variant in (People.HAIR_F if fem else People.HAIR_M):
			var lk2: Dictionary = base.duplicate(true)
			lk2["hair"] = hk
			var hs := People.hair_style(lk2)
			if not _names(PortraitKit.recipe(lk2, {})).has("hair_%s_front" % hs):
				bad.append("hair " + str(hk))
		if not fem:
			for bd: Variant in CustomWorkers.BEARDS:
				var lk3: Dictionary = base.duplicate(true)
				lk3["beard"] = bd
				if str(bd) != "" and not _names(PortraitKit.recipe(lk3, {})).has("beard_" + str(bd)):
					bad.append("beard " + str(bd))
		var flags := {"glasses": "glasses", "freckles": "freckles", "earrings": "earrings"}
		for f: String in flags:
			var lk4: Dictionary = base.duplicate(true)
			if f == "glasses":
				lk4["glasses"] = true
			else:
				(lk4["face_ovr"] as Dictionary)[f] = true
			if not _names(PortraitKit.recipe(lk4, {})).has(flags[f]):
				bad.append(f)
		var bodies := {}
		for b: String in People.BODIES.keys():
			var lk5: Dictionary = base.duplicate(true)
			lk5["body"] = b
			var r := PortraitKit.recipe(lk5, {})
			bodies[str(_names(r)) + str(r["sx"])] = true
		if bodies.size() != People.BODIES.size():
			bad.append("телосложение")
		var cols := {}
		for ec: Variant in People.EYE_COLS:
			var lk6: Dictionary = base.duplicate(true)
			lk6["eye_col"] = ec
			cols[str(_col(PortraitKit.recipe(lk6, {}), "eyes_almond_iris"))] = true
		if cols.size() != People.EYE_COLS.size():
			bad.append("цвет глаз")
		check(bad.is_empty(), "%s: лицо, глаза, брови, нос, рот, причёска, %sочки, веснушки, серьги, телосложение, цвет глаз — все различимы%s" % ["женщина" if fem else "мужчина", "" if fem else "борода, ", "" if bad.is_empty() else ": " + str(bad)])
	check(PortraitKit.heads(true).size() == 3 and PortraitKit.heads(false).size() == 4, "форм лица: у женщин 3, у мужчин 4 (как в наборе)")


func _portrait() -> void:
	print("— Portrait в интерфейсе")
	UITheme.build()
	var w := People.make(RandomNumberGenerator.new(), "turner", 0.0)
	var p := Portrait.new()
	p.set_look(w.look, 1.0, {"age": w.age, "mood": 50.0})
	root.add_child(p)
	await process_frame
	var mats := 0
	for c: Control in p._lay:
		if c.material is ShaderMaterial:
			mats += 1
	check(p._lay.size() == PortraitKit.GROUPS.size() + 1 and mats == p._lay.size(), "новый портрет рисуется группами слоёв с шейдером окраски: %d" % p._lay.size())
	var bm: Variant = (p._lay[1].material as ShaderMaterial).get_shader_parameter("mask")
	check(bm is Texture2D, "у тела — маска воротника")
	check(not p._rec.is_empty(), "рецепт собран")
	check(p.custom_minimum_size == Vector2(64, 74), "размер прежний: %s" % str(p.custom_minimum_size))
	p.queue_free()
	# без набора — старый векторный портрет
	PortraitKit._ok = 0
	var p2 := Portrait.new()
	p2.set_look(w.look, 1.0, {"age": w.age})
	root.add_child(p2)
	await process_frame
	check(p2._lay.is_empty() and p2.layers().size() > 5, "набор не загрузился — рисуется старый портрет")
	p2.queue_free()
	PortraitKit._ok = 1
	await process_frame


func _v2() -> void:
	print("— 1.34: веки, одежда в цвет спецовки, кожа в вырезе, головные уборы")
	var lk := {"fem": true, "skin": 4, "hair": "bob", "hair_col": "#4a3020", "outfit": "shirt", "outfit_col": "#2f6f4f", "street_col": "#5a2f2f", "fs": 13, "age": 30, "body": "normal",
		"hat": "", "hat_col": "#c8a020", "street": "jacket"}
	var r := PortraitKit.recipe(lk, {})
	var skin := Color(str(People.SKINS[4]))
	var n := _names(r)
	var ek := "eyes_" + str(People.face(lk)["eyes"])
	check(n.find(ek + "_lids") >= 0 and n.find(ek + "_lids") < n.find(ek) and _col(r, ek + "_lids") == Color(skin.r, skin.g, skin.b, 1.0), "веки под глазами, цвета кожи")
	var cn := str(r["collar"])
	check(n.has(cn + "_skinpart") and _col(r, cn + "_skinpart") == Color(skin.r, skin.g, skin.b, 1.0), "кожа в вырезе женской одежды — цвета кожи (%s)" % cn)
	check(n.has(cn + "_fab") and _col(r, cn + "_fab") == Color("#2f6f4f"), "ткань — в цвет спецовки")
	var lk2 := lk.duplicate()
	lk2["outfit_col"] = "#8a2f2f"
	var a := PortraitKit.compose_image(lk, {}, 128)
	var b := PortraitKit.compose_image(lk2, {}, 128)
	check(_hash(a) != _hash(b), "другой цвет спецовки — другой портрет")
	# головные уборы — как у человечка на карте
	var m := {"fem": false, "skin": 1, "hair": "short", "hair_col": "#4a3020", "outfit": "jacket", "outfit_col": "#3d5a7a", "fs": 5, "age": 40, "body": "normal", "hat": "helmet", "hat_col": "#e0a020", "street": "jacket", "street_col": "#3b3f44"}
	var rh := PortraitKit.recipe(m, {})
	check(_names(rh).has("helmet") and _col(rh, "helmet") == Color("#e0a020") and str(rh["mask_hair"]) == "mask_hat_helmet", "каска в цвет убора, волосы под каской срезаны маской")
	var rs := PortraitKit.recipe(m, {"dressed": false, "winter": true})
	check(_names(rs).has("ushanka") and not _names(rs).has("helmet") and _col(rs, str(rs["collar"]) + "_fab") == Color("#3b3f44"), "не переоделся зимой: своя куртка, ушанка, без каски")
	var rd := PortraitKit.recipe(m, {"dressed": false})
	check(not _names(rd).has("helmet") and str(rd["hat"]) == "", "не переоделся летом: без каски")
	m["hat"] = "cap"
	check(_names(PortraitKit.recipe(m, {"winter": true, "outside": true})).has("ushanka"), "в мороз на улице — ушанка вместо кепки")
	check(_names(PortraitKit.recipe(m, {"winter": true})).has("cap"), "зимой в цеху — кепка")
	m["hat"] = "weldmask"
	check(_names(PortraitKit.recipe(m, {})).has("welder_mask"), "сварщик — в сварочной маске")
	# маска тела действительно ограничивает шею и голову
	var rv: Dictionary = PortraitKit.recipe(m, {}).duplicate()
	var full := PortraitKit.compose_recipe(rv, 128)
	rv["mask_body"] = ""
	check(_hash(PortraitKit.compose_recipe(rv, 128)) != _hash(full), "маска воротника меняет картинку (тело не вылезает из воротника)")
