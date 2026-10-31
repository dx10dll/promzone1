extends SceneTree
## Тест версии 1.53: энергетика (лимит и вводной автомат, увеличение мощности, ночной тариф, пик, воздух) и директора конкурентов.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage153_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _new_shop(seed_n: int) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_n)
	g.story.enabled = false
	S.big_shop(g)
	for w in g.workers:
		w.present = true
		w.dressed = true
	g.tick(0.5)
	g.tick(1.0)
	return g


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _letter(g: Sim, ev: String) -> Dictionary:
	for l: Dictionary in g.story.letters:
		if str(l["ev"]) == ev:
			return l
	return {}


func _force_work(g: Sim) -> void:
	for m in g.things_of("machine"):
		if m.built and g.power.powered(m):
			m.working = true


func _init() -> void:
	Defs.load_all()
	L.apply("ru")

	print("— 1.56: энергетика как до 1.53 (без тревоги, тарифа и договора)")
	var g3 := _new_shop(1533)
	var pw := g3.power
	check(absf(Defs.b("tariff_night_k") - 1.0) < 0.001, "ночного тарифа нет: цена одна")
	pw.kwh_day = 100.0
	pw.kwh_night = 50.0
	g3.minute = 3.0 * 1440.0 + 1.0
	g3._on_new_day()
	var lines := 0
	for e: Dictionary in g3.ledger:
		if str(e["text"]).begins_with("Электроэнергия"):
			lines += 1
			check(str(e["text"]).begins_with("Электроэнергия: 150"), "одна строка за сутки: %s" % str(e["text"]))
	check(lines == 1, "в журнале денег одна строка за электричество")
	check(not g3.story.letters.any(func(l: Dictionary) -> bool: return str(l["ev"]) == "breaker"), "тревожных писем про автомат нет")

	print("— сжатый воздух: значок «нет воздуха»")
	var booth: Thing = null
	for m in g3.things_of("machine"):
		if g3.eng.air_mode(m) == "need":
			booth = m
	check(booth != null, "в цеху есть пневмостанок (покраска)")
	if booth != null:
		g3.tick(1.0)
		var ar := Stall.air_reason(g3, booth)
		check(str(ar.get("k", "")) == "air", "без компрессора: «%s»" % str(ar.get("why", "")))
		check(StallBadges.title("air") == "Нет воздуха", "заголовок значка есть")
	var plain: Thing = g3.things_of("machine")[0]
	check(Stall.air_reason(g3, plain).is_empty(), "станку без пневматики воздух не нужен")

	print("— директора: характеры дают нужные действия")
	var g4 := _new_shop(1534)
	var mk := g4.market
	var chars := {}
	for c: Dictionary in mk.comps:
		var d := Rivals.dir_of(c)
		check(str(d["name"]) != "" and str(d["char"]) in Rivals.CHARS.keys() and int(d["rel"]) == 0, "%s: %s, %s" % [str(c["id"]), str(d["name"]), Rivals.char_name(str(d["char"]))])
		chars[str(d["char"])] = c
		check(not Rivals.look(c).is_empty(), "портрет собран из PortraitKit")
	check(chars.size() >= 3, "среди соседей разные характеры: %d" % chars.size())
	var stats := {}
	for ch in Rivals.CHARS.keys():
		var fake := {"id": "x_" + str(ch), "dir": {"name": "А Б В", "fem": false, "char": ch, "rel": 0, "log": [], "seed": 1, "last": -100}}
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var cnt := {"poach": 0, "steal": 0, "deal": 0, "help": 0}
		for i in 600:
			cnt[Rivals.pick(fake, rng, 3)] += 1
		stats[ch] = cnt
	var sh: Dictionary = stats["shark"]
	check(int(sh["poach"]) + int(sh["steal"]) > 2 * (int(sh["deal"]) + int(sh["help"])), "«акула» переманивает и перебивает клиентов: %s" % str(sh))
	var od: Dictionary = stats["old"]
	check(int(od["deal"]) + int(od["help"]) > 3 * (int(od["poach"]) + int(od["steal"])), "«старой закалки» предлагает сделки и просит помощи: %s" % str(od))
	var cr: Dictionary = stats["careful"]
	check(int(cr["help"]) >= int(cr["poach"]) * 3 and int(cr["help"]) >= int(cr["deal"]) * 0.9, "«осторожный» чаще просит помощи: %s" % str(cr))
	var nv: Dictionary = stats["novator"]
	check(int(nv["deal"]) > int(nv["steal"]) * 3 and int(nv["poach"]) > int(od["poach"]) * 2, "«новатор» зовёт людей и предлагает сделки: %s" % str(nv))
	# враждебность усиливает удары, дружба — сделки
	var foe := {"id": "foe", "dir": {"name": "А Б В", "fem": false, "char": "careful", "rel": -80, "log": [], "seed": 1, "last": -100}}
	var fr := {"id": "fr", "dir": {"name": "А Б В", "fem": false, "char": "careful", "rel": 80, "log": [], "seed": 1, "last": -100}}
	check(float(Rivals.weights(foe, 3)["poach"]) > float(Rivals.weights(fr, 3)["poach"]) * 3.0 and float(Rivals.weights(fr, 3)["deal"]) > float(Rivals.weights(foe, 3)["deal"]) * 2.0, "враг бьёт чаще, друг делится чаще")

	print("— переманивание: письмо и удержание")
	var shark: Dictionary = chars["shark"]
	g4.story.letters.clear()
	var staff := g4.workers.size()
	for w in g4.workers:
		w.mood = 70.0
	check(Rivals.act(mk, shark, "poach"), "акула делает ход: переманивает")
	var pl := _letter(g4, "poach")
	check(not pl.is_empty() and str(pl["text"]).contains("получил предложение от"), "письмо: «%s»" % str(pl.get("text", "")).substr(0, 70))
	var pw_id := int(pl["data"]["w"])
	var wk: Worker = g4.get_worker(pw_id)
	var wage0 := wk.wage
	var rel0 := Rivals.rel_of(shark)
	g4.story.resolve(int(pl["id"]), 0)
	check(g4.get_worker(pw_id) != null and g4.workers.size() == staff, "удержали надбавкой: человек остался")
	check(wk.wage > wage0, "ставка выросла: %d → %d" % [wage0, wk.wage])
	check(Rivals.rel_of(shark) < rel0, "отношение к нам упало: %d → %d" % [rel0, Rivals.rel_of(shark)])
	check(not (Rivals.dir_of(shark)["log"] as Array).is_empty(), "действие записано в журнал директора")
	g4.story.letters.clear()
	check(Rivals.act(mk, shark, "poach"), "второй раз")
	pl = _letter(g4, "poach")
	var pid2 := int(pl["data"]["w"])
	var rel1 := Rivals.rel_of(shark)
	g4.story.resolve(int(pl["id"]), 2)
	check(g4.get_worker(pid2) == null, "отпустили — ушёл")
	check(Rivals.rel_of(shark) > rel1, "отношение выросло: %d → %d" % [rel1, Rivals.rel_of(shark)])

	print("— перебивание клиентов")
	var k0 := mk.inquiry_k()
	g4.story.letters.clear()
	var rel2 := Rivals.rel_of(shark)
	check(Rivals.act(mk, shark, "steal"), "акула перебивает клиентов")
	check(mk.inquiry_k() < k0 and Rivals.rel_of(shark) < rel2, "заявок меньше (×%.2f → ×%.2f), отношение хуже" % [k0, mk.inquiry_k()])
	var money0 := g4.money
	g4.story.resolve(int(_letter(g4, "rival_steal")["id"]), 0)
	check(absf(mk.inquiry_k() - k0) < 0.001 and g4.money < money0, "обзвонили клиентов — заявки вернулись")

	print("— сделки: заказ, станок, слияние")
	var old_c: Dictionary = chars["old"]
	g4.story.letters.clear()
	var offers0 := g4.orders.by_status(["offer"]).size()
	var got_order := false
	for sd in 40:
		var r := RandomNumberGenerator.new()
		r.seed = sd
		g4.story.letters.clear()
		if not Rivals._deal(mk, old_c, r):
			continue
		var dl := _letter(g4, "rival_deal")
		if str(dl["data"]["sub"]) == "order":
			var rb := Rivals.rel_of(old_c)
			g4.story.resolve(int(dl["id"]), 0)
			got_order = g4.orders.by_status(["offer"]).size() == offers0 + 1 and Rivals.rel_of(old_c) == rb + 5
			break
	check(got_order, "часть заказа соседа — на доске заявок, отношение +5")
	var got_machine := false
	for sd2 in 60:
		var r2 := RandomNumberGenerator.new()
		r2.seed = sd2
		g4.story.letters.clear()
		Rivals._deal(mk, old_c, r2)
		var dl2 := _letter(g4, "rival_deal")
		if not dl2.is_empty() and str(dl2["data"]["sub"]) == "machine":
			var def := str(dl2["data"]["def"])
			g4.story.resolve(int(dl2["id"]), 0)
			got_machine = g4.story.has_mod("voucher:" + def)
			break
	check(got_machine, "станок у соседа со скидкой 40%")
	var got_merger := false
	g4.progress.stage = 2
	var no_merger := true
	for sd3 in 60:
		var r3 := RandomNumberGenerator.new()
		r3.seed = sd3
		g4.story.letters.clear()
		Rivals._deal(mk, old_c, r3)
		var dl3 := _letter(g4, "rival_deal")
		if not dl3.is_empty() and str(dl3["data"]["sub"]) == "merger":
			no_merger = false
	check(no_merger, "слияние на ранних этапах не предлагают")
	g4.progress.stage = 5
	Rivals.shift(old_c, g4, 40, "")
	for sd4 in 60:
		var r4 := RandomNumberGenerator.new()
		r4.seed = sd4
		g4.story.letters.clear()
		Rivals._deal(mk, old_c, r4)
		var dl4 := _letter(g4, "rival_deal")
		if not dl4.is_empty() and str(dl4["data"]["sub"]) == "merger":
			var rb2 := Rivals.rel_of(old_c)
			g4.story.resolve(int(dl4["id"]), 0)
			got_merger = Rivals.rel_of(old_c) > rb2
			break
	check(got_merger, "на поздних этапах при хороших отношениях — предложение слияния")

	print("— просьбы о помощи")
	g4.story.letters.clear()
	var careful_c: Dictionary = chars["careful"]
	var got_mach_help := false
	for sd5 in 20:
		var r5 := RandomNumberGenerator.new()
		r5.seed = sd5
		g4.story.letters.clear()
		if Rivals._help(mk, careful_c, r5):
			var hl := _letter(g4, "rival_help")
			if str(hl["data"]["sub"]) == "machine":
				var tm: Thing = g4.things[int(hl["data"]["thing"])]
				var cond := tm.condition
				var mn := g4.money
				var rb3 := Rivals.rel_of(careful_c)
				g4.story.resolve(int(hl["id"]), 0)
				got_mach_help = g4.money > mn and tm.condition < cond and Rivals.rel_of(careful_c) > rb3
				break
	check(got_mach_help, "одолжили станок: деньги, износ, отношение растёт")
	for i in 12:
		g4.put_on_ground(g4.new_item("mat", "strip2", "raw"), Vector2i(14 + i % 3, 25))
	g4.story.letters.clear()
	var got_metal := false
	for sd6 in 40:
		var r6 := RandomNumberGenerator.new()
		r6.seed = sd6
		g4.story.letters.clear()
		Rivals._help(mk, careful_c, r6)
		var hl2 := _letter(g4, "rival_help")
		if not hl2.is_empty() and str(hl2["data"]["sub"]) == "metal":
			var mat := str(hl2["data"]["mat"])
			var have := g4.free_material(mat)
			var mn2 := g4.money
			g4.story.resolve(int(hl2["id"]), 0)
			got_metal = g4.free_material(mat) == have - int(hl2["data"]["qty"]) and g4.money > mn2
			break
	check(got_metal, "одолжили металл за плату: склад меньше, деньги больше")
	var r7 := Rivals.rel_of(careful_c)
	g4.story.letters.clear()
	Rivals._help(mk, careful_c, RandomNumberGenerator.new())
	g4.story.resolve(int(_letter(g4, "rival_help")["id"]), 1)
	check(Rivals.rel_of(careful_c) < r7, "отказали — отношение упало")

	print("— отношение меняется от решений")
	var tm2: Dictionary = chars["novator"]
	var r8 := Rivals.rel_of(tm2)
	mk.policy = "dump"
	Rivals.week(mk)
	check(Rivals.rel_of(tm2) < r8, "демпинг портит отношения с соседями: %d → %d" % [r8, Rivals.rel_of(tm2)])
	mk.policy = "market"
	Rivals.shift(tm2, g4, 500, "")
	check(Rivals.rel_of(tm2) == 100, "отношение не выше 100")
	Rivals.shift(tm2, g4, -500, "")
	check(Rivals.rel_of(tm2) == -100, "и не ниже −100")
	mk._start_war(tm2)
	var r9 := Rivals.rel_of(tm2)
	g4.story.letters.clear()
	mk._start_war(tm2)
	g4.story.resolve(int(_letter(g4, "price_war")["id"]), 2)
	check(Rivals.rel_of(tm2) > r9, "ответ качеством, а не ценой, уважают")

	print("— каждую неделю кто-то из директоров делает ход")
	var g5 := _new_shop(1535)
	g5.story.letters.clear()
	var acts := {}
	var n_acts := 0
	for wk_i in 30:
		g5.minute = (10.0 + wk_i * 7.0) * 1440.0 + 8.0 * 60.0
		g5.story.letters.clear()
		var res := Rivals.week(g5.market)
		if not res.is_empty():
			n_acts += 1
			acts[str(res["kind"])] = true
	check(n_acts >= 6 and acts.size() >= 3, "за 30 недель %d ходов, видов: %s" % [n_acts, str(acts.keys())])

	print("— старое сохранение грузится")
	var d := _roundtrip(g5.to_dict())
	for c: Dictionary in d["market"]["comps"]:
		c.erase("dir")
	var grid: Dictionary = d["grid"]
	for k in ["contract", "upgrade", "peak", "peak_prev", "kd", "kn", "trips", "hist"]:
		grid.erase(k)
	d["power"] = 12.5
	var old := Sim.from_dict(d)
	var all_dir := true
	for c2: Dictionary in old.market.comps:
		if not c2.has("dir") or str(Rivals.dir_of(c2)["name"]) == "":
			all_dir = false
	check(all_dir, "директора созданы заново")
	check(old.power.contract_steps == 0 and old.power.upgrade.is_empty() and absf(old.power.kwh_day - 12.5) < 0.01, "энергия недосчитанных суток не потеряна")
	for i in 20:
		old.tick(1.0)
	check(true, "и игра идёт дальше")
	var d2 := _roundtrip(g5.to_dict())
	var again := Sim.from_dict(d2)
	check(Rivals.rel_of(again.market.comps[0]) == Rivals.rel_of(g5.market.comps[0]), "новое сохранение хранит отношения")

	print("")
	if fails.is_empty():
		print("СТАДИЯ 1.53: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
