class_name ResearchTree
extends RefCounted
## «Разработки» деревом (1.15): сверху техотдел (технолог), от него ветки — техпроцессы, автоматизация,
## слесарное дело, изделия, управление, социальное. Внутри ветки разработки идут сверху вниз по
## зависимостям; линии от того, что нужно изучить раньше. Дерево открывается, когда есть технолог.
## Щелчок по узлу — подробности и кнопка «Разрабатывать» внизу.

static var sel := ""

const NODE_H := 66.0
const GAP_Y := 24.0
const TOP_NODES := 138.0
const BRANCH_ICONS := {"Техпроцессы": "shop", "Автоматизация": "engineer", "Слесарное дело": "wrench",
	"Изделия": "objects", "Управление": "chart_up", "Социальное": "mood"}


static func layout() -> Array:
	return Office.research_layout()


static func open(sim: Sim) -> bool:
	return sim.office.research_open()


static func status(sim: Sim, id: String) -> String:
	return sim.office.research_status(id)


class TreeView extends Control:
	var sim: Sim
	var root_n: Control
	var heads: Array = []
	var rows: Array = []     # по веткам: [[узел, ...], ...] по ярусам
	var ids: Array = []      # то же, id
	var pos_of: Dictionary = {}

	func _ready() -> void:
		resized.connect(_layout)
		_layout()

	func _layout() -> void:
		var w := size.x
		if w < 100.0:
			return
		var n := rows.size()
		var gap := 10.0
		var cw := (w - gap * float(n - 1)) / float(n)
		root_n.position = Vector2(w * 0.5 - 160.0, 0.0)
		root_n.size = Vector2(320.0, 58.0)
		pos_of.clear()
		for i in n:
			var x := float(i) * (cw + gap)
			var h: Control = heads[i]
			h.position = Vector2(x, 86.0)
			h.size = Vector2(cw, 44.0)
			for j in (rows[i] as Array).size():
				var row: Array = rows[i][j]
				var m := row.size()
				var g2 := 6.0
				var nw := (cw - g2 * float(m - 1)) / float(m)
				for k in m:
					var nd: Control = row[k]
					nd.position = Vector2(x + float(k) * (nw + g2), TOP_NODES + float(j) * (NODE_H + GAP_Y))
					nd.size = Vector2(nw, NODE_H)
					pos_of[str(ids[i][j][k])] = Rect2(nd.position, nd.size)
		queue_redraw()

	func _col(st: String) -> Color:
		match st:
			"works":
				return UITheme.GOOD
			"busy":
				return UITheme.ACCENT
			"ready":
				return Color("#7f9bb4")
		return UITheme.LINE

	func _draw() -> void:
		var w := size.x
		var n := rows.size()
		if n == 0 or w < 100.0 or pos_of.is_empty():
			return
		var gap := 10.0
		var cw := (w - gap * float(n - 1)) / float(n)
		var rc := UITheme.ACCENT if ResearchTree.open(sim) else UITheme.LINE
		draw_line(Vector2(w * 0.5, 58.0), Vector2(w * 0.5, 74.0), rc, 2.0, true)
		draw_line(Vector2(cw * 0.5, 74.0), Vector2(w - cw * 0.5, 74.0), rc, 2.0, true)
		for i in n:
			var cx := float(i) * (cw + gap) + cw * 0.5
			draw_line(Vector2(cx, 74.0), Vector2(cx, 86.0), rc, 2.0, true)
			for j in (ids[i] as Array).size():
				for id in ids[i][j]:
					var r: Rect2 = pos_of[str(id)]
					var top := Vector2(r.get_center().x, r.position.y)
					var st := ResearchTree.status(sim, str(id))
					var col := _col(st)
					var parents: Array = []
					for rq in Defs.research[id].get("req", []):
						if pos_of.has(str(rq)) and str(Defs.research[rq]["branch"]) == str(Defs.research[id]["branch"]):
							parents.append(str(rq))
					if parents.is_empty():
						# корень ветки — от заголовка
						var y0 := 130.0
						draw_line(Vector2(top.x, y0), top - Vector2(0, 6), col, 2.0, true)
						draw_line(Vector2(cx, y0), Vector2(top.x, y0), col, 2.0, true)
					else:
						for p in parents:
							var pr: Rect2 = pos_of[p]
							var a := Vector2(pr.get_center().x, pr.end.y)
							var mid := a.y + (top.y - a.y) * 0.5
							var pts := PackedVector2Array([a, Vector2(a.x, mid), Vector2(top.x, mid), top - Vector2(0, 6)])
							draw_polyline(pts, col, 3.0 if st == "works" else 2.0, true)
					draw_colored_polygon(PackedVector2Array([top + Vector2(-4, -6), top + Vector2(4, -6), top]), col)


static func build(win: GameWindow) -> void:
	var sim := win.sim
	var of := sim.office
	if sel == "" or not Defs.research.has(sel):
		sel = of.research_cur if of.research_cur != "" else "root"
	var rate := of.research_rate()
	win._info(L.t("изучено %d из %d") % [of.research_done.size(), Defs.research.size()] + (L.t(" · ~%.1f очка за смену") % rate if rate > 0.0 else ""))
	win._intro(L.t("Разработки ведёт технолог в техотделе — дерево открывается, когда он появится. Изученное открывает новые изделия, станки и улучшения. Щёлкните по разработке — внизу подробности."))
	var lay := layout()
	var tv := TreeView.new()
	tv.sim = sim
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var max_rows := 1
	for b: Array in lay:
		max_rows = maxi(max_rows, (b[1] as Array).size())
	tv.custom_minimum_size = Vector2(0, TOP_NODES + float(max_rows) * NODE_H + float(max_rows - 1) * GAP_Y + 4.0)
	tv.root_n = _root_node(win)
	tv.add_child(tv.root_n)
	for b2: Array in lay:
		var bname := str(b2[0])
		var hv := VBoxContainer.new()
		hv.alignment = BoxContainer.ALIGNMENT_CENTER
		hv.add_theme_constant_override("separation", 1)
		var ic := win._icon(Tex.ui(str(BRANCH_ICONS.get(bname, "research"))), 20)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hv.add_child(ic)
		var nl := UITheme.label(L.t(bname), 12, UITheme.TEXT, UITheme.f_semi)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hv.add_child(nl)
		tv.heads.append(hv)
		tv.add_child(hv)
		var brows: Array = []
		var bids: Array = []
		for row: Array in b2[1]:
			var nrow: Array = []
			for id in row:
				var nd := _node(win, str(id), row.size() > 1)
				nrow.append(nd)
				tv.add_child(nd)
			brows.append(nrow)
			bids.append(row)
		tv.rows.append(brows)
		tv.ids.append(bids)
	win.content.add_child(tv)
	win.content.add_child(_details(win))


static func _root_node(win: GameWindow) -> Button:
	var sim := win.sim
	var of := sim.office
	var st := "works" if open(sim) else "locked"
	if of.research_cur != "" and open(sim):
		st = "busy"
	var b := DevTree._btn(st, sel == "root", L.t("Техотдел: здесь технолог ведёт разработки"), func() -> void:
		sel = "root"
		win.rebuild(true))
	var v := DevTree._inner(b)
	var hh := HBoxContainer.new()
	hh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_theme_constant_override("separation", 8)
	var ic := win._icon(Tex.ui("research"), 22)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_child(ic)
	var rl := DevTree._lab(L.t("Техотдел"), 14, UITheme.TEXT, UITheme.f_semi)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(rl)
	v.add_child(hh)
	if not open(sim):
		v.add_child(DevTree._lab(L.t("нет технолога — дерево закрыто"), 12, UITheme.WARN))
	elif of.research_cur != "":
		var rd: Dictionary = Defs.research[of.research_cur]
		v.add_child(DevTree._lab(L.t("разрабатывает: «%s» · %d%%") % [L.t(str(rd["name"])), int(float(of.research_pts.get(of.research_cur, 0.0)) / float(rd["cost"]) * 100.0)], 12, UITheme.ACCENT))
	else:
		v.add_child(DevTree._lab(L.t("✓ свободен — выберите разработку"), 12, UITheme.GOOD))
	return b


static func _node(win: GameWindow, id: String, narrow: bool = false) -> Button:
	var sim := win.sim
	var of := sim.office
	var rd: Dictionary = Defs.research[id]
	var st := status(sim, id)
	var b := DevTree._btn(st, sel == id, L.t(str(rd.get("desc", ""))), func() -> void:
		sel = id
		win.rebuild(true))
	var v := DevTree._inner(b)
	var nm := L.t(str(rd.get("short", rd["name"])) if narrow else str(rd["name"]))
	b.tooltip_text = L.t(str(rd["name"])) + "\n" + L.t(str(rd.get("desc", "")))
	v.add_child(DevTree._lab(nm, (11 if nm.length() <= 10 else 10) if narrow else (12 if nm.length() <= 16 else 11), UITheme.TEXT if st != "locked" else UITheme.MUTED, UITheme.f_semi, true))
	var sp := Control.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var txt := L.t("%d очков") % int(rd["cost"])
	var col := UITheme.DIM
	match st:
		"works":
			txt = L.t("✓ изучено")
			col = UITheme.GOOD
		"busy":
			txt = L.t("идёт · %d%%") % int(float(of.research_pts.get(id, 0.0)) / float(rd["cost"]) * 100.0)
			col = UITheme.ACCENT
		"ready":
			var pts := float(of.research_pts.get(id, 0.0))
			txt = (L.t("%d очков") % int(rd["cost"])) + (L.t(" · начато") if pts > 0.0 else "")
			col = Color("#9ab4cc")
		_:
			# зависимость из другой ветки — подписью
			for rq in rd.get("req", []):
				if str(Defs.research[rq]["branch"]) != str(rd["branch"]) and not of.has_tech(str(rq)):
					txt = L.t("после «%s»") % L.t(str(Defs.research[rq]["name"]))
	v.add_child(DevTree._lab(txt, 11, col, null, true))
	if st == "busy":
		var pb := UITheme.bar(float(of.research_pts.get(id, 0.0)) / float(rd["cost"]) * 100.0, UITheme.ACCENT, 60, 4)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(pb)
	return b


static func _details(win: GameWindow) -> PanelContainer:
	var sim := win.sim
	var of := sim.office
	var c := UITheme.card(14, UITheme.BG2, UITheme.LINE)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.vbox(6)
	c.add_child(v)
	if sel == "root" or not Defs.research.has(sel):
		v.add_child(UITheme.label(L.t("Техотдел"), 17, UITheme.TEXT, UITheme.f_semi))
		v.add_child(UITheme.para(L.t("Корень дерева разработок. Очки дают технологи за столами техотдела (стол ИТР, кульман, линолеум — или общая контора). Пока технолога нет, дерево закрыто: видно, что впереди, но разрабатывать некому."), 13))
		var staff := of.staff("tech")
		DevTree._req(v, not staff.is_empty(), (L.t("технолог: %s") % staff[0].full_name()) if not staff.is_empty() else L.t("технолог в штате"))
		var rs := of.room_status("tech")
		DevTree._req(v, int(rs[0]) >= 0, L.t("кабинет: %s") % str(rs[1]).trim_prefix("✓ ").trim_prefix("× "))
		if staff.is_empty():
			var row := UITheme.hbox(8)
			if sim.progress.dept_open("tech"):
				row.add_child(UITheme.primary(L.t("Найти технолога · %s") % Defs.money_str(sim.ad_price("technologist")), func() -> void:
					var err := sim.post_ad("technologist")
					if err != "":
						win.hud.toast(err, Sim.LVL_WARN)
						return
					win.hud.open_window("staff")
					if win.hud.win:
						win.hud.win.select_tab("hire"), L.t("Объявление по профессии — откроется найм")))
			else:
				row.add_child(win._cl(sim.progress.dept_lock_text("tech"), 13, UITheme.MUTED))
			v.add_child(row)
		return c
	var rd: Dictionary = Defs.research[sel]
	var st := status(sim, sel)
	var th := UITheme.hbox(10)
	th.add_child(win._icon(Tex.ui(str(BRANCH_ICONS.get(str(rd["branch"]), "research"))), 28))
	var tv := UITheme.vbox(0)
	tv.add_child(UITheme.label(L.t("«%s»") % L.t(str(rd["name"])), 17, UITheme.TEXT, UITheme.f_semi))
	tv.add_child(UITheme.label(L.t("ветка «%s» · %d очков") % [L.t(str(rd["branch"])), int(rd["cost"])], 12, UITheme.MUTED))
	th.add_child(tv)
	th.add_child(UITheme.spacer())
	var chips := {"works": ["изучено", UITheme.GOOD], "busy": ["в работе", UITheme.ACCENT], "ready": ["можно начать", UITheme.INFO], "locked": ["закрыто", UITheme.MUTED]}
	th.add_child(UITheme.chip(L.t(str(chips[st][0])), chips[st][1]))
	v.add_child(th)
	v.add_child(UITheme.para(L.t(str(rd.get("desc", ""))), 13, UITheme.TEXT))
	DevTree._req(v, open(sim), L.t("технолог в техотделе"))
	for rq in rd.get("req", []):
		DevTree._req(v, of.has_tech(str(rq)), L.t("сначала: «%s»") % L.t(str(Defs.research[rq]["name"])))
	var row2 := UITheme.hbox(8)
	match st:
		"ready":
			var pts := float(of.research_pts.get(sel, 0.0))
			var key := sel
			row2.add_child(UITheme.primary(L.t("Разрабатывать") + (L.t(" (%.0f из %d)") % [pts, int(rd["cost"])] if pts > 0.0 else ""), func() -> void:
				of.set_research(key)
				win.rebuild(true), L.t("Технолог переключится на эту разработку; набранные очки прежней сохранятся")))
		"busy":
			var pb := UITheme.bar(float(of.research_pts.get(sel, 0.0)) / float(rd["cost"]) * 100.0, UITheme.ACCENT, 260, 8)
			row2.add_child(pb)
			row2.add_child(win._cl(L.t("%.1f из %d очков") % [float(of.research_pts.get(sel, 0.0)), int(rd["cost"])], 13, UITheme.ACCENT))
	if row2.get_child_count() > 0:
		v.add_child(row2)
	return c
