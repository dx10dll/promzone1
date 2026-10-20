extends SceneTree
## Тест версий 1.33–1.37 «Новые портреты» (1.37 — набор v5: 14 изолированных наборов пол × телосложение,
## все детали человека — из его набора; шея своя у каждой одежды; формы лица снова видны): все слои и маски
## на месте и читаются, лишнего нет; порядок слоёв по README/compose.py; рецепт и сборка для 200 случайных людей;
## одно и то же лицо — одна и та же картинка (хэш); кэш; окраска не трогает прозрачность, ткань одежды — в цвет
## спецовки; головные уборы как у человечка на карте; любая черта из редактора «Создать рабочего» видна на
## портрете; без набора — старый портрет.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage133_test.gd

var fails: Array[String] = []

const FACE := ["eyes_almond", "eyes_narrow", "eyes_round", "eyes_heavy", "eyes_deep",
	"eyes_almond_lids", "eyes_narrow_lids", "eyes_round_lids", "eyes_heavy_lids", "eyes_deep_lids",
	"brows_straight", "brows_arched", "brows_thick", "brows_thin", "brows_angled", "brows_bushy",
	"nose_small", "nose_straight", "nose_long", "nose_wide", "nose_hooked",
	"mouth_neutral", "mouth_smile", "mouth_thin", "mouth_full", "mouth_down",
	"glasses", "freckles", "lines_mid", "lines_old", "cap", "helmet", "welder_mask", "ushanka"]
const FITS := ["very_thin", "thin", "normal", "strong", "powerful", "full", "very_full"]
const OUT_M := ["overall", "shirt", "jacket", "suit", "robe", "sweater", "vest", "firefighter"]


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


## Слои, которые обязаны быть в наборе sid.
func _set_layers(sid: String) -> Array:
	var fem := sid.ends_with("_f")
	var g := "f" if fem else "m"
	var out: Array = []
	for n: String in FACE:
		out.append(sid + "/" + n)
	for h: String in PortraitKit.heads(fem):
		out.append("%s/head_%s_%s" % [sid, g, h])
	for hs: String in (People.HAIR_F if fem else People.HAIR_M):
		out.append("%s/hair_%s_front" % [sid, hs])
		out.append("%s/hair_%s_back" % [sid, hs])
	if fem:
		out.append(sid + "/earrings")
		out.append(sid + "/kerchief_f")
	else:
		for bd: String in CustomWorkers.BEARDS:
			if bd != "":
				out.append(sid + "/beard_" + bd)
	for o: String in OUT_M + (["kerchief"] if fem else []):
		out.append("%s/collar_%s_%s" % [sid, o, g])
		out.append("%s/neck_%s_%s" % [sid, o, g])
	return out


func _layers() -> void:
	print("— слои набора v5")
	check(PortraitKit.available(), "набор assets/portrait2 найден (layers.json версии 5 и текстуры)")
	check(PortraitKit.set_ids().size() == 14, "14 наборов: %s" % str(PortraitKit.set_ids()))
	var bad: Array = []
	var need := 0
	for f: String in FITS:
		for g: String in ["m", "f"]:
			for n: String in _set_layers("%s_%s" % [f, g]):
				need += 1
				if not PortraitKit.has(n) or PortraitKit.tex(n) == null:
					bad.append(n)
	check(bad.is_empty() and need > 1000, "все обязательные слои всех наборов читаются: %d" % need + ("" if bad.is_empty() else ", нет " + str(bad.slice(0, 8))))
	var total := 0
	for n2: Variant in PortraitKit.names():
		total += 1
		if PortraitKit.tex(str(n2)) == null:
			bad.append(n2)
	check(bad.is_empty(), "всего слоёв %d (с радужкой и изнанками), все читаются" % total)
	var junk: Array = []
	for n3: Variant in PortraitKit.names() + PortraitKit.mask_names():
		var s3 := str(n3)
		if s3.count("/") != 1 or s3.ends_with("_gray") or s3.contains("base_") or s3.contains("cheeks_") or s3.contains("chin_") \
				or s3.contains("_keep") or s3.contains("_skinpart") or (s3.ends_with("_m/earrings")):
			junk.append(s3)
	check(junk.is_empty(), "нет серых копий, base_template, слоёв v2/v3 (основы, body_keep, щёки) и лишнего" + ("" if junk.is_empty() else ": " + str(junk.slice(0, 8))))
	# все наборы самостоятельны: одежда набора — шея, изнанка, перед из того же набора
	var cross: Array = []
	for sid: String in PortraitKit.set_ids():
		var st: Dictionary = PortraitKit.set_info(sid)
		for o: String in (st["outfits"] as Dictionary):
			if not PortraitKit.has_mask("%s/mask_%s_fab" % [sid, o]) or PortraitKit.gain(sid, o) < 0.8 or PortraitKit.gain(sid, o) > 2.6:
				cross.append("%s %s fab" % [sid, o])
		for h: String in ["cap", "helmet", "welder_mask", "ushanka"]:
			if not PortraitKit.has_mask("%s/mask_hat_%s" % [sid, h]):
				cross.append("%s %s" % [sid, h])
	check(cross.is_empty() and PortraitKit.mask_names().size() == 119 + 14 * 4, "масок 175 (ткань 119 одежд, 4 убора × 14 наборов): %d" % PortraitKit.mask_names().size() + ("" if cross.is_empty() else ": " + str(cross.slice(0, 6))))
	var mt := PortraitKit.tex("normal_m/mask_suit_fab")
	check(mt != null and mt.get_size() == Vector2(512, 512) and mt.get_image().get_format() == Image.FORMAT_L8, "маска одноканальная (L8), на том же холсте 512")
	var t := PortraitKit.tex("normal_m/head_m_oval")
	check(t != null and t.get_size() == Vector2(512, 512), "холст 512×512: %s" % str(t.get_size() if t else Vector2.ZERO))
	var dirbad: Array = []
	for sid2: String in PortraitKit.set_ids():
		for f2: String in DirAccess.get_files_at(PortraitKit.DIR + sid2):
			if f2.ends_with(".png") and not PortraitKit.has(sid2 + "/" + f2.get_basename()) and not PortraitKit.has_mask(sid2 + "/" + f2.get_basename()):
				dirbad.append(sid2 + "/" + f2)
	check(dirbad.is_empty(), "в папках наборов нет лишних PNG" + ("" if dirbad.is_empty() else ": " + str(dirbad.slice(0, 8))))


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
	# телосложение -> набор; все слои рецепта — только из своего набора; порядок по README набора
	var lk2 := {"fem": false, "skin": 1, "hair": "short", "hair_col": "#4a3020", "outfit": "overall", "fs": 5, "age": 40, "beard": "full", "glasses": true}
	var fits := {"vthin": "very_thin", "thin": "thin", "normal": "normal", "stout": "strong", "strong": "powerful", "fat": "full", "vfat": "very_full"}
	var fok := true
	for fem: bool in [false, true]:
		for bk: String in fits:
			var lb := lk2.duplicate()
			lb["fem"] = fem
			lb["hair"] = "bob" if fem else "short"
			lb["body"] = bk
			var rb := PortraitKit.recipe(lb, {})
			var sid := "%s_%s" % [fits[bk], "f" if fem else "m"]
			if str(rb["set"]) != sid:
				fok = false
			for n: Variant in _names(rb):
				if not str(n).begins_with(sid + "/"):
					fok = false
			for gname: String in PortraitKit.GROUPS:
				var m := str(rb.get("mask_" + gname, ""))
				if m != "" and not m.begins_with(sid + "/"):
					fok = false
	check(fok, "7 телосложений × 2 пола -> 14 наборов; все слои и маски рецепта — из своего набора")
	lk2["body"] = "normal"
	var ro := PortraitKit.recipe(lk2, {"age": 60})
	var no := _names(ro)
	var fc2 := People.face(lk2, 60)
	var p := "normal_m/"
	var order := [p + "hair_short_back", p + "neck_overall_m", p + "head_m_" + str(fc2["head"]), p + "collar_overall_m", p + "eyes_%s_lids" % fc2["eyes"], p + "eyes_" + str(fc2["eyes"]),
		p + "brows_" + str(fc2["brows"]), p + "nose_" + str(fc2["nose"]), p + "mouth_" + str(fc2["mouth"]), p + "lines_old", p + "beard_full", p + "hair_short_front", p + "glasses"]
	var idx: Array = order.map(func(x: String) -> int: return no.find(x))
	var sorted_ok := not idx.has(-1)
	for i in range(1, idx.size()):
		if int(idx[i]) <= int(idx[i - 1]):
			sorted_ok = false
	check(sorted_ok, "порядок: волосы сзади → шея одежды → голова → одежда → веки, глаза, брови, нос, рот → морщины, борода → волосы спереди → очки: %s" % str(idx))
	var lj := lk2.duplicate()
	lj["outfit"] = "coat"
	var rj := _names(PortraitKit.recipe(lj, {}))
	check(rj.find(p + "collar_robe_m_inner") > rj.find(p + "hair_short_back") and rj.find(p + "collar_robe_m_inner") < rj.find(p + "neck_robe_m") and rj.has(p + "collar_robe_m"), "изнанка халата — за шеей, шея — своя для халата")
	check(PortraitKit.GROUPS == ["back", "inner", "body", "cloth", "face", "hair", "top"], "группы рисования в порядке v5")
	# формы лица снова видны: у каждой формы — своя голова набора; чужие формы (старые сохранения) — ближайшая своя
	var hm := {}
	for h: String in PortraitKit.HEADS_M:
		var lh := lk2.duplicate(true)
		lh["face_ovr"] = {"head": h}
		hm[str(PortraitKit.recipe(lh, {})["head"])] = true
	var lf := {"fem": true, "skin": 1, "hair": "bob", "hair_col": "#4a3020", "outfit": "overall", "fs": 5, "age": 40, "body": "fat", "face_ovr": {"head": "square"}}
	var rf := PortraitKit.recipe(lf, {})
	check(hm.size() == 4 and str(rf["head"]) == "round" and _names(rf).has("full_f/head_f_round"), "4 формы лица у мужчин; у женщины старое «квадратное» -> круглое своего набора")
	var lm := lk2.duplicate()
	lm["hair"] = "ponytail"
	check(str(PortraitKit.recipe(lm, {})["hairdo"]) == "mullet", "чужая причёска (смена пола) -> ближайшая своего набора")
	# одежда по спецовке
	var outfits := {"overall": "overall", "coat": "robe", "jacket": "jacket", "fireman": "firefighter", "shirt": "shirt"}
	var ok := true
	for o: String in outfits:
		var lk3 := lk2.duplicate()
		lk3["body"] = "normal"
		lk3["outfit"] = o
		lk3["fs"] = 7
		if not _names(PortraitKit.recipe(lk3, {})).has("normal_m/collar_%s_m" % str(outfits[o])):
			ok = false
			print("    одежда %s -> %s" % [o, str(_names(PortraitKit.recipe(lk3, {})))])
	check(ok, "одежда по спецовке: комбинезон, халат, куртка, боёвка, рубашка")
	var fk := {"fem": true, "skin": 0, "hair": "perm", "hair_col": "#9a6a3a", "outfit": "overall", "hat": "kerchief", "hat_col": "#3d5a7a", "fs": 3, "age": 50}
	var nk := _names(PortraitKit.recipe(fk, {}))
	check(nk.has("normal_f/kerchief_f") and nk.has("normal_f/collar_kerchief_f") and nk.has("normal_f/neck_kerchief_f") and nk.find("normal_f/kerchief_f") > nk.find("normal_f/hair_perm_front"), "работница в косынке: косынка поверх волос, рабочая рубашка со своей шеей")
	# возраст: морщины и седина
	var old := PortraitKit.recipe(lk2, {"age": 60})
	var young := PortraitKit.recipe(lk2, {"age": 25})
	check(_names(old).has("normal_m/lines_old") and not _names(young).has("normal_m/lines_old") and not _names(young).has("normal_m/lines_mid"), "морщины по возрасту")
	check(_col(old, "normal_m/hair_short_front").s < _col(young, "normal_m/hair_short_front").s, "к старости волосы седеют")
	# настроение: улыбка и грусть
	check(_names(PortraitKit.recipe(lk2, {"mood": 90.0})).has("normal_m/mouth_smile") and _names(PortraitKit.recipe(lk2, {"mood": 10.0})).has("normal_m/mouth_down"), "настроение видно по губам")


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
	var src := PortraitKit._layer_img("normal_m/head_m_oval", 128)
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
			"face_ovr": {"head": "round" if fem else "oval", "eyes": "almond", "brows": "straight", "nose": "small", "mouth": "neutral", "freckles": false, "earrings": false}}
		var bad: Array = []
		var sp := "normal_f/" if fem else "normal_m/"
		var groups := {"head": PortraitKit.heads(fem), "eyes": People.EYE_KINDS, "brows": People.BROW_KINDS, "nose": People.NOSE_KINDS, "mouth": People.MOUTH_KINDS}
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
			if not _names(PortraitKit.recipe(lk2, {})).has(sp + "hair_%s_front" % hs):
				bad.append("hair " + str(hk))
		if not fem:
			for bd: Variant in CustomWorkers.BEARDS:
				var lk3: Dictionary = base.duplicate(true)
				lk3["beard"] = bd
				if str(bd) != "" and not _names(PortraitKit.recipe(lk3, {})).has(sp + "beard_" + str(bd)):
					bad.append("beard " + str(bd))
		var flags := {"glasses": "glasses", "freckles": "freckles", "earrings": "earrings"} if fem else {"glasses": "glasses", "freckles": "freckles"}
		for f: String in flags:
			var lk4: Dictionary = base.duplicate(true)
			if f == "glasses":
				lk4["glasses"] = true
			else:
				(lk4["face_ovr"] as Dictionary)[f] = true
			if not _names(PortraitKit.recipe(lk4, {})).has(sp + str(flags[f])):
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
			cols[str(_col(PortraitKit.recipe(lk6, {}), sp + "eyes_almond_iris"))] = true
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
	var bi := PortraitKit.GROUPS.find("body")
	var ci := PortraitKit.GROUPS.find("cloth")
	var bm: Variant = (p._lay[bi].material as ShaderMaterial).get_shader_parameter("mask")
	check(bm == null, "у шеи и головы маски нет (шея своя у каждой одежды)")
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
	var ek := "normal_f/eyes_" + str(People.face(lk)["eyes"])
	check(n.find(ek + "_lids") >= 0 and n.find(ek + "_lids") < n.find(ek) and _col(r, ek + "_lids") == sk, "веки под глазами, цвета кожи")
	check(_col(r, "normal_f/neck_shirt_f") == sk and _col(r, "normal_f/head_f_" + str(r["head"])) == sk and _col(r, "normal_f/nose_" + str(People.face(lk)["nose"])) == sk, "шея, голова и нос — одним цветом кожи")
	var plain := Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF)
	check(_col(r, "normal_f/mouth_" + str(People.face(lk)["mouth"])) == plain and _col(r, ek) == plain, "губы и глаза не красятся цветом кожи")
	var cn := str(r["collar"])
	check(cn == "shirt" and _col(r, "normal_f/collar_shirt_f") == Color("#2f6f4f") and str(r["mask_cloth"]) == "normal_f/mask_shirt_fab", "одежда — в цвет спецовки по маске ткани")
	var lk2 := lk.duplicate()
	lk2["outfit_col"] = "#8a2f2f"
	var a := PortraitKit.compose_image(lk, {}, 128)
	var b := PortraitKit.compose_image(lk2, {}, 128)
	check(_hash(a) != _hash(b), "другой цвет спецовки — другой портрет")
	# перекраска ткани: яркость рисунка × gain × цвет; вне ткани (галстук) — как есть
	var suit := PortraitKit._layer_img("normal_m/collar_suit_m", 128)
	var fm := PortraitKit._layer_img("normal_m/mask_suit_fab", 128)
	var g := PortraitKit.gain("normal_m", "suit")
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
	check(_names(rh).has("normal_m/helmet") and _col(rh, "normal_m/helmet") == Color("#e0a020") and str(rh["mask_hair"]) == "normal_m/mask_hat_helmet" and str(rh["mask_back"]) == "normal_m/mask_hat_helmet", "каска в цвет убора, волосы под каской срезаны маской")
	check(_names(rh).find("normal_m/helmet") > _names(rh).find("normal_m/hair_short_front"), "убор — поверх волос")
	var rs := PortraitKit.recipe(m, {"dressed": false, "winter": true})
	check(_names(rs).has("normal_m/ushanka") and not _names(rs).has("normal_m/helmet") and _col(rs, "normal_m/collar_%s_m" % rs["collar"]) == Color("#3b3f44"), "не переоделся зимой: своя куртка, ушанка, без каски")
	var rd := PortraitKit.recipe(m, {"dressed": false})
	check(not _names(rd).has("normal_m/helmet") and str(rd["hat"]) == "", "не переоделся летом: без каски")
	m["hat"] = "cap"
	check(_names(PortraitKit.recipe(m, {"winter": true, "outside": true})).has("normal_m/ushanka"), "в мороз на улице — ушанка вместо кепки")
	check(_names(PortraitKit.recipe(m, {"winter": true})).has("normal_m/cap"), "зимой в цеху — кепка")
	m["hat"] = "weldmask"
	check(_names(PortraitKit.recipe(m, {})).has("normal_m/welder_mask"), "сварщик — в сварочной маске")
	# маска ткани действительно ограничивает перекраску
	var rv: Dictionary = PortraitKit.recipe(m, {}).duplicate()
	var full := PortraitKit.compose_recipe(rv, 128)
	rv["mask_cloth"] = ""
	check(_hash(PortraitKit.compose_recipe(rv, 128)) != _hash(full), "маска ткани меняет картинку (перекраска только по ткани)")
