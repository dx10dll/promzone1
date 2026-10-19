extends SceneTree
## Тест версий 1.33–1.36 «Новые портреты» (1.36 — набор v3: цельная основа «голова + шея + плечи» по телосложению,
## одежда по посадке, маска body_keep, без слоёв v2): все слои и маски набора на месте и читаются, лишнего нет;
## порядок слоёв по compose_example.py; рецепт и сборка для 200 случайных людей; одно и то же лицо — одна и та же
## картинка (хэш); кэш; окраска не трогает прозрачность, ткань одежды — в цвет спецовки; головные уборы как у
## человечка на карте; любая черта из редактора «Создать рабочего» видна на портрете; без набора — старый портрет.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage133_test.gd

var fails: Array[String] = []

const BASE := ["eyes_almond", "eyes_narrow", "eyes_round", "eyes_heavy", "eyes_deep",
	"brows_straight", "brows_arched", "brows_thick", "brows_thin", "brows_angled", "brows_bushy",
	"nose_small", "nose_straight", "nose_long", "nose_wide", "nose_hooked",
	"mouth_neutral", "mouth_smile", "mouth_thin", "mouth_full", "mouth_down",
	"beard_mustache", "beard_full", "beard_goatee", "beard_stubble", "beard_chevron", "beard_short",
	"glasses", "earrings", "freckles", "lines_mid", "lines_old", "kerchief_f",
	"eyes_almond_lids", "eyes_narrow_lids", "eyes_round_lids", "eyes_heavy_lids", "eyes_deep_lids",
	"cap", "helmet", "welder_mask", "ushanka"]
const HAIRS := ["short", "crew", "side", "slick", "receding", "bald", "curly", "mullet", "bob", "bun", "ponytail", "long", "pixie", "curly_f", "braid", "perm"]
const COLLARS := ["overall", "shirt", "jacket", "suit", "robe", "sweater", "vest", "firefighter"]
const FITS := ["very_thin", "thin", "normal", "strong", "powerful", "full", "very_full"]


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


func _collars() -> Array:
	var out: Array = []
	for f: String in FITS:
		for c: String in COLLARS:
			for g: String in ["m", "f"]:
				out.append("collar_%s_%s_%s" % [c, g, f])
		out.append("collar_kerchief_f_" + f)
	return out


func _all_base() -> Array:
	var out: Array = BASE.duplicate()
	for h: String in HAIRS:
		out.append("hair_%s_front" % h)
		out.append("hair_%s_back" % h)
	for f: String in FITS:
		for g: String in ["m", "f"]:
			out.append("base_%s_%s" % [f, g])
	return out + _collars()


func _layers() -> void:
	print("— слои набора v3")
	check(PortraitKit.available(), "набор assets/portrait2 найден (layers.json версии 3 и текстуры)")
	var base := _all_base()
	check(base.size() == 42 + 32 + 14 + 119, "в наборе 207 игровых слоёв (черты, причёски, 14 основ, 119 сочетаний одежды): %d" % base.size())
	var bad: Array = []
	for n: String in base:
		if not PortraitKit.has(n) or PortraitKit.tex(n) == null:
			bad.append(n)
	check(bad.is_empty(), "все слои читаются" + ("" if bad.is_empty() else ": нет " + str(bad.slice(0, 8))))
	var total := 0
	for n2: Variant in PortraitKit.names():
		if PortraitKit.tex(str(n2)) == null:
			bad.append(n2)
		total += 1
	check(bad.is_empty() and total >= 207 + 5, "всего слоёв с производными (радужка, изнанки): %d, все читаются" % total)
	# ничего из v2 и ничего лишнего: ни голов, шей, щёк, подбородков, ни серых копий, _fab, _skinpart
	var junk: Array = []
	for n3: Variant in PortraitKit.names() + PortraitKit.mask_names():
		var s3 := str(n3)
		for pre: String in ["head_", "neck_", "cheeks_", "chin_", "base_template"]:
			if s3.begins_with(pre):
				junk.append(s3)
		if s3.ends_with("_gray") or s3.ends_with("_skinpart") or s3.ends_with("_g") or s3.ends_with("_cut") or (s3.begins_with("collar_") and s3.ends_with("_fab")) \
				or s3.contains("keep_face") or s3.contains("skin_keep") or s3.ends_with("_skin_mask"):
			junk.append(s3)
	check(junk.is_empty(), "нет слоёв и масок v2 (head_, neck_, cheeks_, chin_, _cut, _fab, _skinpart, keep_face, skin_keep) и серых копий" + ("" if junk.is_empty() else ": " + str(junk.slice(0, 8))))
	var dirbad: Array = []
	for f: String in DirAccess.get_files_at(PortraitKit.DIR):
		if f.ends_with(".png") and not PortraitKit.has(f.get_basename()) and not PortraitKit.has_mask(f.get_basename()):
			dirbad.append(f)
	check(dirbad.is_empty(), "в папке набора нет лишних PNG" + ("" if dirbad.is_empty() else ": " + str(dirbad.slice(0, 8))))
	# маски: основа под каждой одеждой (body_keep), ткань каждой одежды, волосы под уборами
	var mbad: Array = []
	for cn: String in _collars():
		for suf: String in ["_keep", "_fab"]:
			if not PortraitKit.has_mask("mask_" + cn + suf) or PortraitKit.tex("mask_" + cn + suf) == null:
				mbad.append(cn + suf)
		if PortraitKit.gain(cn) < 0.8 or PortraitKit.gain(cn) > 2.6:
			mbad.append(cn + " gain")
	for h: String in ["cap", "helmet", "welder_mask", "ushanka"]:
		if not PortraitKit.has_mask("mask_hat_" + h) or PortraitKit.tex("mask_hat_" + h) == null:
			mbad.append(h)
	check(mbad.is_empty() and PortraitKit.mask_names().size() == 119 * 2 + 4, "масок 242 (body_keep и ткань для 119 сочетаний, 4 убора), все читаются: %d" % PortraitKit.mask_names().size() + ("" if mbad.is_empty() else ": нет " + str(mbad.slice(0, 8))))
	var mt := PortraitKit.tex("mask_collar_suit_m_normal_keep")
	check(mt != null and mt.get_size() == Vector2(512, 512) and mt.get_image().get_format() == Image.FORMAT_L8, "маска одноканальная (L8), на том же холсте 512")
	var t := PortraitKit.tex("base_normal_m")
	check(t != null and t.get_size() == Vector2(512, 512), "холст 512×512: %s" % str(t.get_size() if t else Vector2.ZERO))
	check(PortraitKit.bbox("base_normal_m").end.y >= 511.0 and PortraitKit.bbox("base_normal_m").position.y < 70.0, "основа цельная: от макушки до низа холста")
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
	# телосложение -> посадка основы и одежды, порядок слоёв по compose_example.py
	var lk2 := {"fem": false, "skin": 1, "hair": "short", "hair_col": "#4a3020", "outfit": "overall", "fs": 5, "age": 40, "beard": "full", "glasses": true}
	var fits := {"vthin": "very_thin", "thin": "thin", "normal": "normal", "stout": "strong", "strong": "powerful", "fat": "full", "vfat": "very_full"}
	var fok := true
	for bk: String in fits:
		lk2["body"] = bk
		var rb := PortraitKit.recipe(lk2, {})
		var f := str(fits[bk])
		if str(rb["fit"]) != f or not _names(rb).has("base_%s_m" % f) \
				or str(rb["collar"]) != "collar_overall_m_" + f or str(rb["mask_body"]) != "mask_collar_overall_m_%s_keep" % f:
			fok = false
	check(fok, "7 телосложений -> 7 посадок: основа, одежда и маска body_keep той же посадки")
	lk2["body"] = "normal"
	var ro := PortraitKit.recipe(lk2, {"age": 60})
	var no := _names(ro)
	var ek2 := "eyes_" + str(People.face(lk2, 60)["eyes"])
	var order := ["hair_short_back", "base_normal_m", ek2 + "_lids", ek2, "nose_" + str(People.face(lk2, 60)["nose"]), "mouth_" + str(People.face(lk2, 60)["mouth"]),
		"brows_" + str(People.face(lk2, 60)["brows"]), "lines_old", "beard_full", "collar_overall_m_normal", "hair_short_front", "glasses"]
	var idx: Array = order.map(func(x: String) -> int: return no.find(x))
	var sorted_ok := not idx.has(-1)
	for i in range(1, idx.size()):
		if int(idx[i]) <= int(idx[i - 1]):
			sorted_ok = false
	check(sorted_ok, "порядок: волосы сзади → основа → веки, глаза, нос, рот, брови, морщины, борода → одежда → волосы спереди, очки: %s" % str(idx))
	var lj := lk2.duplicate()
	lj["outfit"] = "coat"
	var rj := _names(PortraitKit.recipe(lj, {}))
	check(rj.has("collar_robe_m_normal_inner") and rj.find("collar_robe_m_normal_inner") == 0, "изнанка одежды — первой, под всем")
	check(PortraitKit.GROUPS == ["inner", "back", "body", "face", "cloth", "hair", "top"], "группы рисования в порядке v3")
	# одежда по спецовке
	var outfits := {"overall": "overall", "coat": "robe", "jacket": "jacket", "fireman": "firefighter", "shirt": "shirt"}
	var ok := true
	for o: String in outfits:
		var lk3 := lk2.duplicate()
		lk3["body"] = "normal"
		lk3["outfit"] = o
		lk3["fs"] = 7
		if not _names(PortraitKit.recipe(lk3, {})).has("collar_%s_m_normal" % str(outfits[o])):
			ok = false
			print("    одежда %s -> %s" % [o, str(_names(PortraitKit.recipe(lk3, {})))])
	check(ok, "одежда по спецовке: комбинезон, халат, куртка, боёвка, рубашка")
	var fk := {"fem": true, "skin": 0, "hair": "perm", "hair_col": "#9a6a3a", "outfit": "overall", "hat": "kerchief", "hat_col": "#3d5a7a", "fs": 3, "age": 50}
	var nk := _names(PortraitKit.recipe(fk, {}))
	check(nk.has("kerchief_f") and nk.has("collar_kerchief_f_normal") and nk.find("kerchief_f") > nk.find("hair_perm_front"), "работница в косынке: косынка поверх волос, рабочая рубашка")
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
	var src := PortraitKit._layer_img("base_normal_m", 128)
	var bb := Rect2i(0, 0, 128, 128)
	var dark := PortraitKit.tint_region(src, bb, Color(str(People.SKINS[5])))
	var light := PortraitKit.tint_region(src, bb, Color(str(People.SKINS[0])))
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
			"face_ovr": {"eyes": "almond", "brows": "straight", "nose": "small", "mouth": "neutral", "freckles": false, "earrings": false}}
		var bad: Array = []
		var groups := {"eyes": People.EYE_KINDS, "brows": People.BROW_KINDS, "nose": People.NOSE_KINDS, "mouth": People.MOUTH_KINDS}
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
			bodies[str(_names(r))] = true
		if bodies.size() != People.BODIES.size():
			bad.append("телосложение")
		var cols := {}
		for ec: Variant in People.EYE_COLS:
			var lk6: Dictionary = base.duplicate(true)
			lk6["eye_col"] = ec
			cols[str(_col(PortraitKit.recipe(lk6, {}), "eyes_almond_iris"))] = true
		if cols.size() != People.EYE_COLS.size():
			bad.append("цвет глаз")
		check(bad.is_empty(), "%s: глаза, брови, нос, рот, причёска, %sочки, веснушки, серьги, телосложение, цвет глаз — все различимы%s" % ["женщина" if fem else "мужчина", "" if fem else "борода, ", "" if bad.is_empty() else ": " + str(bad)])
	# 1.36: форма головы на портрете не видна — у старых сохранений поле face_ovr.head просто не учитывается
	var o1 := {"fem": false, "skin": 2, "hair": "short", "hair_col": "#4a3020", "outfit": "overall", "fs": 11, "age": 35, "body": "normal", "face_ovr": {"head": "square"}}
	var o2: Dictionary = o1.duplicate(true)
	(o2["face_ovr"] as Dictionary)["head"] = "long"
	check(str(_names(PortraitKit.recipe(o1, {}))) == str(_names(PortraitKit.recipe(o2, {}))), "старое поле «форма лица» не мешает и ни на что не влияет")


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
	var bi := PortraitKit.GROUPS.find("body")
	var ci := PortraitKit.GROUPS.find("cloth")
	var bm: Variant = (p._lay[bi].material as ShaderMaterial).get_shader_parameter("mask")
	check(bm is Texture2D and (bm as Texture2D).resource_path.ends_with("_keep.png"), "у основы — маска body_keep своей одежды")
	var cm := p._lay[ci].material as ShaderMaterial
	check(cm.get_shader_parameter("fab") == 1.0 and cm == p._lay[PortraitKit.GROUPS.find("inner")].material and float(cm.get_shader_parameter("gain")) >= 0.8, "перед и изнанка одежды — общий материал перекраски ткани")
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
	print("— веки, одежда в цвет спецовки, головные уборы")
	var lk := {"fem": true, "skin": 4, "hair": "bob", "hair_col": "#4a3020", "outfit": "shirt", "outfit_col": "#2f6f4f", "street_col": "#5a2f2f", "fs": 13, "age": 30, "body": "normal",
		"hat": "", "hat_col": "#c8a020", "street": "jacket"}
	var r := PortraitKit.recipe(lk, {})
	var skin := Color(str(People.SKINS[4]))
	var sk := Color(skin.r, skin.g, skin.b, 1.0)
	var n := _names(r)
	var ek := "eyes_" + str(People.face(lk)["eyes"])
	check(n.find(ek + "_lids") >= 0 and n.find(ek + "_lids") < n.find(ek) and _col(r, ek + "_lids") == sk, "веки под глазами, цвета кожи")
	check(_col(r, str(r["base"])) == sk and _col(r, "nose_" + str(People.face(lk)["nose"])) == sk, "основа и нос — одним цветом кожи")
	var plain := Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF)
	check(_col(r, "mouth_" + str(People.face(lk)["mouth"])) == plain and _col(r, ek) == plain, "губы и глаза не красятся цветом кожи")
	var cn := str(r["collar"])
	check(cn == "collar_shirt_f_normal" and _col(r, cn) == Color("#2f6f4f") and str(r["mask_cloth"]) == "mask_%s_fab" % cn, "одежда — в цвет спецовки по маске ткани")
	var lk2 := lk.duplicate()
	lk2["outfit_col"] = "#8a2f2f"
	var a := PortraitKit.compose_image(lk, {}, 128)
	var b := PortraitKit.compose_image(lk2, {}, 128)
	check(_hash(a) != _hash(b), "другой цвет спецовки — другой портрет")
	# перекраска ткани: яркость рисунка × gain × цвет; вне ткани (галстук) — как есть
	var suit := PortraitKit._layer_img("collar_suit_m_normal", 128)
	var fm := PortraitKit._layer_img("mask_collar_suit_m_normal_fab", 128)
	var g := PortraitKit.gain("collar_suit_m_normal")
	var rr := Rect2i(0, 0, 128, 128)
	var red := PortraitKit.tint_region(suit, rr, Color("#a03030"), fm, true, g)
	var blue := PortraitKit.tint_region(suit, rr, Color("#3040a0"), fm, true, g)
	var fab_d := 0
	var own_same := 0
	var own_n := 0
	var alpha_ok := true
	for y in range(64, 128, 2):
		for x in range(0, 128, 2):
			var s0 := suit.get_pixel(x, y)
			if s0.a < 0.95:
				continue
			if absf(red.get_pixel(x, y).a - s0.a) > 0.003:
				alpha_ok = false
			var m := fm.get_pixel(x, y).r
			if m > 0.99 and red.get_pixel(x, y).r > blue.get_pixel(x, y).r + 0.05:
				fab_d += 1
			elif m == 0.0:
				own_n += 1
				if red.get_pixel(x, y).is_equal_approx(s0) and blue.get_pixel(x, y).is_equal_approx(s0):
					own_same += 1
	check(fab_d > 100 and own_n > 10 and own_same == own_n and alpha_ok, "пиджак красится, галстук и рубашка своего цвета, прозрачность та же: ткань %d, своё %d/%d" % [fab_d, own_same, own_n])
	# головные уборы — как у человечка на карте
	var m := {"fem": false, "skin": 1, "hair": "short", "hair_col": "#4a3020", "outfit": "jacket", "outfit_col": "#3d5a7a", "fs": 5, "age": 40, "body": "normal", "hat": "helmet", "hat_col": "#e0a020", "street": "jacket", "street_col": "#3b3f44"}
	var rh := PortraitKit.recipe(m, {})
	check(_names(rh).has("helmet") and _col(rh, "helmet") == Color("#e0a020") and str(rh["mask_hair"]) == "mask_hat_helmet" and str(rh["mask_back"]) == "mask_hat_helmet", "каска в цвет убора, волосы под каской срезаны маской")
	check(_names(rh).find("helmet") > _names(rh).find("hair_short_front"), "убор — поверх волос")
	var rs := PortraitKit.recipe(m, {"dressed": false, "winter": true})
	check(_names(rs).has("ushanka") and not _names(rs).has("helmet") and _col(rs, str(rs["collar"])) == Color("#3b3f44"), "не переоделся зимой: своя куртка, ушанка, без каски")
	var rd := PortraitKit.recipe(m, {"dressed": false})
	check(not _names(rd).has("helmet") and str(rd["hat"]) == "", "не переоделся летом: без каски")
	m["hat"] = "cap"
	check(_names(PortraitKit.recipe(m, {"winter": true, "outside": true})).has("ushanka"), "в мороз на улице — ушанка вместо кепки")
	check(_names(PortraitKit.recipe(m, {"winter": true})).has("cap"), "зимой в цеху — кепка")
	m["hat"] = "weldmask"
	check(_names(PortraitKit.recipe(m, {})).has("welder_mask"), "сварщик — в сварочной маске")
	# маска body_keep действительно ограничивает основу
	var rv: Dictionary = PortraitKit.recipe(m, {}).duplicate()
	var full := PortraitKit.compose_recipe(rv, 128)
	rv["mask_body"] = ""
	check(_hash(PortraitKit.compose_recipe(rv, 128)) != _hash(full), "маска body_keep меняет картинку (основа не вылезает из одежды)")
