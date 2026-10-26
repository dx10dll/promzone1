extends SceneTree
## Тест 1.48b «Доска заявок»: режимы сбыта (Вручную / Мелочь сам / Всё сам), «Взять», «Отказать», «Торговаться»,
## уход к конкуренту по сроку, сохранение доски и режима.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage148_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _setup(seed_n: int, mode: String) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_n)
	g.story.enabled = false
	S.big_shop(g, true)
	for o0: Dictionary in g.orders.list.duplicate():
		g.orders.list.erase(o0)
	g.sales.board.clear()
	g.sales.log.clear()
	g.sales.queue.clear()
	g.sales.enabled = true
	g.sales.paused = false
	g.sales.mode = mode
	return g


## Заявка заданной суммы и маржи (срок большой, чтобы риск не мешал).
func _offer(g: Sim, sum: float, margin: float, p: String = "pin") -> Dictionary:
	var o := g.orders.make_offer(p)
	o["qty"] = 2
	o["lead"] = 40
	o["deadline"] = g.orders.deadline_after(40)
	var unit := sum / 2.0
	o["price"] = unit
	var cost := g.office.unit_cost(p)
	if margin > 0.0:
		o["price"] = int(ceil(cost / (1.0 - margin) / 10.0) * 10.0)
		o["qty"] = maxi(1, int(round(sum / float(o["price"]))))
	return o


func _initialize() -> void:
	print("== режим по умолчанию и сейв старого формата")
	var g0 := _setup(1480, "small")
	check(Sales.new(g0).mode == "small", "по умолчанию «Мелочь сам»")
	var old := g0.sales.to_dict()
	old.erase("mode")
	old.erase("board")
	g0.sales.from_dict(old)
	check(g0.sales.mode == "small" and g0.sales.board.is_empty(), "старый сейв без режима → «Мелочь сам», доска пуста")

	print("== «Мелочь сам»")
	var g := _setup(1481, "small")
	var small := _offer(g, 60000.0, 0.3)
	check(float(small["price"]) * int(small["qty"]) <= Sales.SMALL_SUM, "тест: заявка мелкая")
	check(g.sales.verdict(small)[0] == "", "тест: сбыт её бы взял (verdict пуст)")
	g.sales.inquiry(small)
	check(g.sales.board.is_empty(), "мелкая выгодная — не на доске")
	check(g.sales.log.size() == 1 and bool(g.sales.log[0]["ok"]) and str(g.sales.log[0]["by"]) == "sales", "мелкая выгодная — взята сбытом, в журнале by=sales")
	var big := _offer(g, 400000.0, 0.3)
	g.sales.inquiry(big)
	check(g.sales.board.size() == 1 and str(big["status"]) == "board", "крупная — на доске")
	var thin := _offer(g, 50000.0, 0.05)
	g.sales.inquiry(thin)
	check(g.sales.board.size() == 2, "мелкая, но маржа ниже 15% — на доске")
	var exp1 := (float(big["expires"]) - g.minute) / 1440.0
	check(exp1 >= 1.0 and exp1 <= 2.0, "срок на доске 1–2 суток (%.2f)" % exp1)

	print("== «Взять», «Отказать»")
	check(g.sales.take(int(thin["id"])) == "", "take: взято, хотя маржа ниже порога")
	check(g.sales.board.size() == 1 and g.orders.get_order(int(thin["id"])).get("status", "") == "active", "take: заказ в работе, с доски ушёл")
	var nid := int(big["id"])
	g.sales.refuse(nid)
	check(g.sales.board.is_empty(), "refuse: доска пуста")
	check(str(g.sales.log.back()["why"]) == "отказ директора" and not bool(g.sales.log.back()["ok"]), "refuse: в журнале «отказ директора»")
	check(g.sales.take(nid) != "", "take несуществующей — отказ с причиной")

	print("== «Вручную»")
	var gm := _setup(1482, "manual")
	gm.sales.inquiry(_offer(gm, 30000.0, 0.4))
	gm.sales.inquiry(_offer(gm, 500000.0, 0.4))
	check(gm.sales.board.size() == 2 and gm.sales.log.is_empty(), "manual: всё на доске, сам ничего не берёт")
	# жёсткий отказ (нет оборудования) на доску не кладём
	gm.sales.off["pin"] = true
	gm.sales.inquiry(_offer(gm, 30000.0, 0.4))
	check(gm.sales.board.size() == 2 and gm.sales.log.size() == 1 and not bool(gm.sales.log[0]["ok"]), "снято с ассортимента — сразу в журнал, не на доску")
	gm.sales.off.erase("pin")
	gm.sales.paused = true
	gm.sales.inquiry(_offer(gm, 30000.0, 0.4))
	check(gm.sales.board.size() == 2, "пауза «Не брать»: на доску ничего не ложится")
	gm.sales.paused = false
	print("== смена режима на «Всё сам» разбирает доску")
	gm.sales.set_mode("auto")
	check(gm.sales.board.is_empty() and gm.sales.mode == "auto", "auto: доска разобрана сбытом")

	print("== «Всё сам» — как раньше")
	var ga := _setup(1483, "auto")
	var big_o := _offer(ga, 500000.0, 0.4)
	big_o["lead"] = 120   # 1.50b: сбыт сам берёт только при «успеем» — срок с запасом
	big_o["deadline"] = ga.orders.deadline_after(120)
	ga.sales.inquiry(big_o)
	check(ga.sales.board.is_empty() and ga.sales.log.size() == 1 and bool(ga.sales.log[0]["ok"]), "auto: крупную берёт сразу, доска пуста")

	print("== торг")
	var gh := _setup(1484, "manual")
	var h1 := _offer(gh, 200000.0, 0.3)
	gh.sales.inquiry(h1)
	var c_small := gh.sales.haggle_chance(h1, 0.05, 0)
	var c_big := gh.sales.haggle_chance(h1, 0.25, 3)
	check(c_small > c_big and c_small <= 0.95 and c_big >= 0.03, "шанс падает с надбавкой (%.2f > %.2f)" % [c_small, c_big])
	check(gh.sales.haggle(int(h1["id"]), 0.0, 0) == "", "торг без надбавки — не попытка")
	var p0 := float(h1["price"])
	var l0 := int(h1["lead"])
	var res := ""
	# детерминизм: тот же сид — тот же исход
	var gh2 := _setup(1484, "manual")
	var h2 := _offer(gh2, 200000.0, 0.3)
	gh2.sales.inquiry(h2)
	res = gh.sales.haggle(int(h1["id"]), 0.05, 1)
	var res2 := gh2.sales.haggle(int(h2["id"]), 0.05, 1)
	check(res == res2 and res != "", "торг детерминирован (%s)" % res)
	if res == "ok":
		check(float(h1["price"]) > p0 and int(h1["lead"]) == l0 + 1 and not gh.sales.board.is_empty(), "согласие: новые условия, заявка осталась на доске")
		check(gh.sales.haggle(int(h1["id"]), 0.05, 1) == "", "вторая попытка торга запрещена")
		check(gh.sales.take(int(h1["id"])) == "", "после торга заявку можно взять")
	else:
		check(gh.sales.board.is_empty() and str(gh.sales.log.back()["why"]).begins_with("торг не удался"), "отказ: заказчик ушёл, в журнале")
	# жадный торг почти всегда проваливается
	var fails_n := 0
	for i in 20:
		var gx := _setup(1500 + i, "manual")
		var hx := _offer(gx, 200000.0, 0.3)
		gx.sales.inquiry(hx)
		if gx.sales.haggle(int(hx["id"]), 0.25, 3) == "no":
			fails_n += 1
	check(fails_n >= 14, "+25%% и +3 дня: чаще отказывают (%d из 20)" % fails_n)

	print("== истечение срока")
	var ge := _setup(1485, "manual")
	ge.sales.inquiry(_offer(ge, 300000.0, 0.3))
	ge.sales.inquiry(_offer(ge, 250000.0, 0.3))
	ge.minute += 2.1 * 1440.0
	ge.sales.morning()
	check(ge.sales.board.is_empty(), "через 2+ суток доска пуста")
	var gone := ge.sales.log.filter(func(e: Dictionary) -> bool: return str(e["why"]) == "ушёл к конкуренту")
	check(gone.size() == 2, "обе ушли к конкуренту, в журнале с причиной")
	var notes := ge.events.filter(func(e: Dictionary) -> bool: return str(e["text"]).begins_with("Заказчики ушли к конкуренту"))
	check(notes.size() == 1, "уведомление одно на утро")

	print("== сейв/загрузка")
	var gs := _setup(1486, "manual")
	gs.sales.inquiry(_offer(gs, 300000.0, 0.3))
	gs.sales.inquiry(_offer(gs, 250000.0, 0.3))
	var id0 := int(gs.sales.board[0]["id"])
	var g2 := Sim.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(g2.sales.mode == "manual" and g2.sales.board.size() == 2, "режим и доска пережили сейв")
	check(int(g2.sales.board[0]["id"]) == id0 and g2.sales.board_left(g2.sales.board[0]) > 0.9, "карточка цела, срок сохранён")
	check(g2.sales.take(id0) == "", "после загрузки заявку можно взять")

	print("== утро: одна пачка заявок")
	var gd := _setup(1487, "manual")
	for i in 3:
		gd.minute += 1440.0
		gd.orders.morning()
	check(gd.sales.board.size() + gd.sales.log.size() > 0, "утренние заявки легли на доску/в журнал")

	print("== экран доски: кнопки")
	var gu := _setup(1488, "manual")
	for sm in [150000.0, 220000.0, 310000.0]:
		gu.sales.inquiry(_offer(gu, sm, 0.3))
	UITheme.build()
	var host := VBoxContainer.new()
	root.add_child(host)
	var toasts: Array = []
	var rb := func(_f: bool) -> void:
		for c in host.get_children():
			c.queue_free()
		OrderBoard.build(host, gu, Callable(), func(t: String, _l: int) -> void: toasts.append(t))
	var rbc: Callable = rb
	host.set_meta("rb", rbc)
	OrderBoard.build(host, gu, rbc, func(t: String, _l: int) -> void: toasts.append(t))
	var btns: Array = host.find_children("*", "Button", true, false)
	var by_text := func(txt: String) -> Array:
		return btns.filter(func(b: Button) -> bool: return b.text == txt)
	check(by_text.call("Взять").size() == 3 and by_text.call("Торговаться").size() == 3, "на экране по кнопке «Взять»/«Торговаться» на карточку")
	check(OrderBoard.sig(gu) != OrderBoard.sig(_setup(1489, "small")), "подпись доски зависит от содержимого")
	(by_text.call("Отказать")[0] as Button).pressed.emit()
	check(gu.sales.board.size() == 2 and toasts.size() == 1, "кнопка «Отказать» работает, тост показан")
	(by_text.call("Взять")[1] as Button).pressed.emit()
	check(gu.sales.board.size() == 1, "кнопка «Взять» работает")
	host.queue_free()

	print("\nПровалов: %d" % fails.size())
	quit(1 if not fails.is_empty() else 0)
