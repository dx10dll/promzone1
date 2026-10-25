class_name Season
extends RefCounted
## Календарь, погода, снег, отопление и праздники.
## Календарь сжат: месяц — 14 игровых дней (две недели), год — 168 дней.
## Первый день каждого месяца — понедельник.

const MONTHS := ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
const MONTHS_GEN := ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
const MONTHS_PREP := ["январе", "феврале", "марте", "апреле", "мае", "июне", "июле", "августе", "сентябре", "октябре", "ноябре", "декабре"]
const SEASON_NAMES := {"winter": "Зима", "spring": "Весна", "summer": "Лето", "autumn": "Осень"}

var sim: Sim
var start_month := 8               ## с какого месяца началась игра (0 — январь)
var temp_day := 12.0               ## средняя температура сегодняшнего дня
var snap := 0.0                    ## добавка от аномалии (мороз, жара)
var snap_until := -1.0
var snow_from := -1.0              ## снегопад: с какой по какую минуту
var snow_until := -1.0
var rain_from := -1.0              ## дождь: с какой по какую минуту
var rain_until := -1.0
var snow := PackedByteArray()      ## снег на клетке 0–255
var snow_rev := 0
var ice := false                   ## гололёд
var sanding := false               ## посыпать дорожки песком (политика)
var burst_cell := Vector2i(-1, -1) ## прорыв трубы: в этом помещении батареи не греют
var burst_until := -1.0
var room_temp: Dictionary = {}     ## id помещения -> °C
var outdoor := PackedByteArray()   ## 1 — клетка на улице (снег может лежать)
var sweep_cells: Array[Vector2i] = []
var _outdoor_sig := ""
var _t := 0.0
var _tw := 0.0
var snow_avg := 0.0                ## средний снег на дорожках 0–255
var radiators := 0


func _init(s: Sim) -> void:
	sim = s
	start_month = int(Defs.sea("start_month"))
	temp_day = _month_temp(start_month)


func setup_map() -> void:
	var n := sim.world.w * sim.world.h
	snow.resize(n)
	snow.fill(0)
	outdoor.resize(n)
	outdoor.fill(0)


# ---------------------------------------------------------------- календарь

func dpm() -> int:
	return maxi(7, int(Defs.sea("days_per_month")))


func days_per_year() -> int:
	return dpm() * 12


func month_abs(d: int = -1) -> int:
	var dd := sim.day() if d < 0 else d
	return start_month + int((dd - 1) / dpm())


func month(d: int = -1) -> int:
	return month_abs(d) % 12


func year(d: int = -1) -> int:
	return int(month_abs(d) / 12) + 1


func dom(d: int = -1) -> int:
	var dd := sim.day() if d < 0 else d
	return (dd - 1) % dpm() + 1


func week_of_month(d: int = -1) -> int:
	return int((dom(d) - 1) / 7) + 1


func season_id(m: int = -1) -> String:
	var mm := month() if m < 0 else m
	if mm == 11 or mm <= 1:
		return "winter"
	if mm <= 4:
		return "spring"
	if mm <= 7:
		return "summer"
	return "autumn"


func season_name() -> String:
	return L.t(str(SEASON_NAMES[season_id()]))


## «Пн, 2-я нед. сентября»
func date_str(d: int = -1) -> String:
	var dd := sim.day() if d < 0 else d
	if L.is_en():
		return "%s, week %d of %s" % [L.t(sim.weekday_name(dd)), week_of_month(dd), MONTHS_EN[month(dd)]]
	return "%s, %d-я нед. %s" % [sim.weekday_name(dd), week_of_month(dd), MONTHS_GEN[month(dd)]]


const MONTHS_SHORT := ["янв.", "февр.", "марта", "апр.", "мая", "июня", "июля", "авг.", "сент.", "окт.", "нояб.", "дек."]
## 1.39: английские названия месяцев (L.is_en)
const MONTHS_EN := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]


## «Пн, 2 нед. сент.» — для верхней панели
func short_date(d: int = -1) -> String:
	var dd := sim.day() if d < 0 else d
	if L.is_en():
		return "%s, wk %d %s" % [L.t(sim.weekday_name(dd)), week_of_month(dd), MONTHS_EN[month(dd)].left(3)]
	return "%s, %d нед. %s" % [sim.weekday_name(dd), week_of_month(dd), MONTHS_SHORT[month(dd)]]


## «вторник, 2-я неделя сентября, год 1»
func long_date(d: int = -1) -> String:
	var dd := sim.day() if d < 0 else d
	if L.is_en():
		return "week %d of %s, year %d (day %d)" % [week_of_month(dd), MONTHS_EN[month(dd)], year(dd), dd]
	return "%d-я неделя %s, год %d (день %d)" % [week_of_month(dd), MONTHS_GEN[month(dd)], year(dd), dd]


## Первый день месяца (номер игрового дня), к которому относится день d.
func month_start_day(d: int = -1) -> int:
	var dd := sim.day() if d < 0 else d
	return dd - dom(dd) + 1


## День, на который придётся (месяц m, число dom) не раньше текущего дня.
func next_day_of(m: int, dm: int) -> int:
	var d := month_start_day() + dm - 1
	var guard := 0
	while (month(d) != m or d < sim.day()) and guard < 40:
		d += dpm()
		guard += 1
	return d


## Праздник на этот день (по месяцу и числу) или пустой словарь.
func holiday(d: int = -1) -> Dictionary:
	var dd := sim.day() if d < 0 else d
	var m := month(dd)
	var dm := dom(dd)
	for h: Dictionary in Defs.seasons.get("holidays", []):
		var h0 := int(h["dom"])
		if int(h["month"]) == m and dm >= h0 and dm < h0 + int(h.get("days", 1)):
			return h
	return {}


func is_holiday_off(d: int) -> bool:
	return bool(holiday(d).get("off", false))


# ---------------------------------------------------------------- погода

func _month_temp(m: int) -> float:
	var arr: Array = Defs.seasons.get("month_temp", [])
	if arr.is_empty():
		return 10.0
	return float(arr[m % arr.size()])


## Средняя температура для дня с плавным переходом между месяцами.
func _base_temp(d: int) -> float:
	var m := month(d)
	var k := float(dom(d) - 1) / float(dpm())
	var a := _month_temp(m)
	var b := _month_temp(m + 1)
	if k < 0.5:
		return lerpf(_month_temp(m - 1 + 12), a, 0.5 + k)
	return lerpf(a, b, k - 0.5)


func outside_temp(m: float = -1.0) -> float:
	var mm := sim.minute if m < 0.0 else m
	var t := fmod(mm, 1440.0)
	var di := Defs.sea("diurnal") * sin((t - 540.0) / 1440.0 * TAU)
	var s := snap if mm < snap_until else 0.0
	return temp_day + di + s


func heating_season() -> bool:
	return temp_day + (snap if sim.minute < snap_until else 0.0) < Defs.sea("heating_below")


func is_snowing() -> bool:
	return sim.minute >= snow_from and sim.minute < snow_until


func is_raining() -> bool:
	return sim.minute >= rain_from and sim.minute < rain_until


## Дождь сегодня (был или будет).
func is_raining_day() -> bool:
	return int(rain_from / 1440.0) + 1 == sim.day() or is_raining()


func _arr_lerp(key: String, d: int) -> float:
	var arr: Array = Defs.seasons.get(key, [])
	if arr.is_empty():
		return 0.0
	var m := month(d)
	var k := float(dom(d) - 1) / float(dpm())
	return lerpf(float(arr[m]), float(arr[(m + 1) % 12]), k)


func sunrise() -> float:
	var v := _arr_lerp("sunrise", sim.day())
	return v if v > 0.0 else 390.0


func sunset() -> float:
	var v := _arr_lerp("sunset", sim.day())
	return v if v > 0.0 else 1110.0


## Новый день: погода на сегодня, снегопад, гололёд, счёт за отопление.
func on_new_day() -> void:
	var d := sim.day()
	var prev := temp_day
	temp_day = _base_temp(d) + sim.rng.randf_range(-1.0, 1.0) * Defs.sea("temp_noise")
	var sc: Array = Defs.seasons.get("snow_chance", [])
	var chance := float(sc[month(d)]) if sc.size() == 12 else 0.0
	if temp_day < 1.5 and sim.rng.randf() < chance:
		var start := float(d - 1) * 1440.0 + sim.rng.randf_range(0.0, 1200.0)
		snow_from = start
		snow_until = start + sim.rng.randf_range(180.0, 600.0)
	var rc: Array = Defs.seasons.get("rain_chance", [])
	if temp_day >= 1.5 and rc.size() == 12 and sim.rng.randf() < float(rc[month(d)]):
		var rs := float(d - 1) * 1440.0 + sim.rng.randf_range(0.0, 1100.0)
		rain_from = rs
		rain_until = rs + sim.rng.randf_range(120.0, 480.0)
	var t_eff := temp_day + (snap if sim.minute < snap_until else 0.0)
	ice = season_id() != "summer" and ((prev < 0.0 and t_eff > -3.0 and t_eff < 2.5) or (prev > 0.5 and t_eff < -1.0 and snow_avg > 20.0))
	if ice and not sanding:
		sim.notify_once("ice", L.t("Гололёд! На улице легко поскользнуться. Включите «Посыпать дорожки песком» в окне «События»."), Sim.LVL_WARN, Vector2i(-1, -1), 1440.0)
	# счета
	_count_radiators()
	if heating_season() and radiators > 0:
		var k := clampf((18.0 - t_eff) / 18.0, 0.3, 2.2)
		var own := mini(radiators, sim.eng.boiler_rads.size())
		var city := radiators - own
		if city > 0 and not sim.story.has_mod("heat_off") and sim.eng.heater_ok():
			sim.spend(city * Defs.sea("heat_cost_radiator_day") * k, "Отопление: %d %s от электрокотла" % [city, Defs.plural(city, "батарея", "батареи", "батарей")])
		elif city > 0 and not sim.eng.heater_ok():
			sim.notify_once("no_heater", L.t("Батареи холодные: нет работающего электрокотла. Поставьте «Электрокотёл отопления» вплотную к насосной станции (Объекты → Водопровод) и подведите к нему ток."), Sim.LVL_WARN, Vector2i(-1, -1), 2880.0)
		if own > 0:
			sim.spend(own * Defs.sea("heat_cost_radiator_day") * k * Eng.BOILER_K, "Газ для котельной: %d %s" % [own, Defs.plural(own, "батарея", "батареи", "батарей")])
	if sanding and season_id() != "summer" and (snow_avg > 10.0 or ice):
		sim.spend(Defs.sea("sanding_cost_day"), "Песок и уборка территории")
	if month(d) != month(d - 1) and d > 1:
		_month_note()


func _month_note() -> void:
	var m := month()
	var txt := ""
	match m:
		11:
			txt = L.t("Наступила зима. Проверьте отопление: без батарей в цехах будет холодно, люди начнут мёрзнуть и злиться.")
		2:
			txt = L.t("Весна! Снег начнёт таять, а с ним — гололёд и лужи.")
		5:
			txt = L.t("Лето. В горячих цехах будет жарко — пригодятся окна и кулер с водой.")
		8:
			txt = L.t("Осень. Скоро отопительный сезон.")
	if txt != "":
		sim.notify(txt, Sim.LVL_INFO)


func _count_radiators() -> void:
	var n := 0
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "radiator":
			n += 1
	radiators = n


# ---------------------------------------------------------------- ход времени

func tick(dt: float) -> void:
	if snow.size() != sim.world.w * sim.world.h:
		setup_map()
	_t -= dt
	if _t <= 0.0:
		_t = 10.0
		_refresh_outdoor()
		_update_snow()
		update_rooms()
	_tw -= dt
	if _tw <= 0.0:
		_tw = 30.0
		_worker_thoughts()
		for i in sim.traffic.size():
			sim.traffic[i] *= 0.97


## Карта «улицы» и дорожек для уборки снега (пересчёт при перестройке).
func _refresh_outdoor() -> void:
	var w := sim.world
	var sig := "%d|%d" % [w.rev, sim.rooms.rev]
	if sig == _outdoor_sig:
		return
	_outdoor_sig = sig
	for i in w.w * w.h:
		var c := w.cell_of(i)
		var out := sim.rooms.room_at(c) == null and not Defs.wall_solid(w.wall[i]) and not WallKinds.is_door(w.wall[i]) and not WallKinds.is_gate(w.wall[i])
		outdoor[i] = 1 if out else 0
		if not out:
			snow[i] = 0
	_rebuild_sweep()


func _rebuild_sweep() -> void:
	var w := sim.world
	sweep_cells.clear()
	var seen := {}
	var gate := Vector2i(sim.gate_x, w.plot.end.y - 1)
	if not w.passable(gate):
		gate = w.nearest_passable(gate)
	var targets: Array[Vector2i] = []
	for r in sim.rooms.list:
		for c in r.cells:
			for d: Vector2i in Rooms.DIRS:
				var n: Vector2i = c + d
				if w.is_door(n):
					for d2: Vector2i in Rooms.DIRS:
						var o: Vector2i = n + d2
						if w.inb(o) and outdoor[w.idx(o)] == 1 and w.passable(o):
							targets.append(o)
	for t in targets.slice(0, 24):
		for c2 in w.find_path(gate, t):
			var i := w.idx(c2)
			if outdoor[i] == 1 and not seen.has(i) and w.in_plot(c2):
				seen[i] = true
				sweep_cells.append(c2)


func _update_snow() -> void:
	var w := sim.world
	var n := w.w * w.h
	var add := 0.0
	if is_snowing():
		add = Defs.sea("snow_per_hour") / 6.0 * (1.5 if season_id() == "winter" else 0.7)
	var t := outside_temp()
	var melt := 0.0
	if t > 0.5:
		melt = Defs.sea("melt_per_hour_per_deg") * t / 6.0
	if add <= 0.0 and melt <= 0.0:
		_snow_stats()
		return
	var addi := int(round(add + sim.rng.randf() * 0.99))
	var melti := int(ceil(melt))
	for i in n:
		if outdoor[i] == 0:
			continue
		var v := int(snow[i])
		if addi > 0:
			v += addi + (1 if (i * 7 + int(sim.minute)) % 5 == 0 else 0)
		if melti > 0:
			v -= melti
		snow[i] = clampi(v, 0, 255)
	snow_rev += 1
	_snow_stats()


func _snow_stats() -> void:
	if sweep_cells.is_empty():
		snow_avg = 0.0
		return
	var s := 0
	for c in sweep_cells:
		s += snow[sim.world.idx(c)]
	snow_avg = float(s) / sweep_cells.size()


func snow_at(c: Vector2i) -> int:
	var w := sim.world
	if not w.inb(c) or snow.size() != w.w * w.h:
		return 0
	return snow[w.idx(c)]


## Шаг человека по клетке: протаптывает дорожку; на гололёде можно поскользнуться.
func on_step(w: Worker, c: Vector2i) -> void:
	var wd := sim.world
	if not wd.inb(c) or snow.size() != wd.w * wd.h:
		return
	var i := wd.idx(c)
	if sim.traffic.size() != snow.size():
		sim.traffic.resize(snow.size())
	sim.traffic[i] += 1.0
	if outdoor[i] == 0:
		return
	if snow[i] > 0:
		snow[i] = maxi(0, int(snow[i]) - int(Defs.sea("trample")))
		snow_rev += 1
	if w.visitor or not ice or sanding:
		return
	if sim.rng.randf() < Defs.sea("slip_chance") * sim.story.injury_mode_k():
		sim.story.injure(w, "slip")


## Убрать снег с клетки и соседних (лопатой).
func sweep(c: Vector2i) -> void:
	var w := sim.world
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if w.inb(n):
			var i := w.idx(n)
			snow[i] = int(snow[i] * (0 if d == Vector2i.ZERO else 0.35))
	snow_rev += 1


## Клетки дорожек, которые пора чистить.
func dirty_paths(min_v: int = 70) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in sweep_cells:
		if snow[sim.world.idx(c)] >= min_v:
			out.append(c)
	return out


# ---------------------------------------------------------------- температура в помещениях

func update_rooms() -> void:
	var t_out := outside_temp()
	var heat_on := heating_season()
	var ins := Defs.sea("walls_insulation")
	var comfort := Defs.sea("comfort_temp")
	var rc := Defs.sea("radiator_cells")
	room_temp.clear()
	var burst_space := -1
	if sim.minute < burst_until and burst_cell.x >= 0:
		burst_space = sim.rooms.space_id_at(burst_cell)
	# тепло считается на всё помещение-постройку: батарея греет все зоны в одном зале
	for sp in sim.rooms.spaces:
		var heat := 0.0
		var hot := 0.0
		for tid in sp.things:
			var th: Thing = sim.things.get(tid)
			if th == null or not th.built:
				continue
			if th.def_id == "radiator" and heat_on and sp.id != burst_space and sim.eng.radiator_on(th):
				heat += rc
			elif th.kind() == "machine" and th.process() in ["heat", "casting"]:
				# 1.16: печи греют цех по мощности (ТВЧ почти не греет)
				var hmd := th.machine_def()
				hot += float(hmd.get("power_kw", 25.0)) * (1.1 if th.working else 0.32) * float(hmd.get("room_heat", 1.0))
			elif th.kind() == "machine" and th.working:
				hot += 3.0
		var area := maxf(1.0, float(sp.cells.size()))
		var base := t_out + ins
		var tin := base
		if heat > 0.0:
			tin = base + (comfort - base) * clampf(heat / area, 0.0, 1.0)
			if heat / area > 1.2:
				tin += (heat / area - 1.2) * 4.0
		tin += hot / area * 14.0
		if sp.windows > 0 and tin > t_out + 2.0 and not heat_on:
			tin -= minf(4.0, sp.windows * 0.8)
		for rid in sp.rooms:
			room_temp[rid] = clampf(tin, -40.0, 48.0)


func temp_at(c: Vector2i) -> float:
	var r := sim.rooms.room_at(c)
	if r and room_temp.has(r.id):
		return float(room_temp[r.id])
	return outside_temp()


## Множитель скорости работы от температуры на рабочем месте.
func work_k(w: Worker) -> float:
	var t := temp_at(w.cell())
	if t < Defs.sea("freezing_below"):
		return 0.85
	if t < Defs.sea("cold_below"):
		return 0.95
	if t > Defs.sea("hot_above") + 5.0:
		return 0.86
	if t > Defs.sea("hot_above"):
		return 0.94
	return 1.0


func _worker_thoughts() -> void:
	var winter := season_id() == "winter" or temp_day < 0.0
	for w in sim.workers:
		if not w.present or w.hidden:
			continue
		var t := temp_at(w.cell())
		var cooler := _cooler_near(w.cell())
		if t < Defs.sea("freezing_below"):
			Mood.add(sim, w, "freezing")
		elif t < Defs.sea("cold_below"):
			Mood.add(sim, w, "cold")
		elif t > Defs.sea("hot_above") and not cooler:
			Mood.add(sim, w, "hot")
		elif winter and t >= 18.0 and sim.rooms.room_at(w.cell()) != null:
			Mood.add(sim, w, "warm_winter")
		if noise_at(w.cell()) > 80.0 and not bool(w.look.get("phones", false)) and not w.muffs:
			Mood.add(sim, w, "noisy")


func _cooler_near(c: Vector2i) -> bool:
	var si := sim.rooms.space_id_at(c)
	if si < 0:
		return false
	for tid in sim.rooms.spaces[si].things:
		var th: Thing = sim.things.get(tid)
		if th and th.built and th.def_id in ["cooler", "water_cooler"]:
			return true
	return false


## Уровень шума в клетке, дБ: работающие станки, ослабление с расстоянием и через стены.
const NOISE := {"turning": 78.0, "milling": 84.0, "drilling": 80.0, "welding": 82.0, "heat": 72.0, "paint": 74.0, "assembly": 80.0, "test": 70.0, "casting": 84.0, "stamping": 96.0}


## all_on — как если бы работало всё оборудование (замеры СОУТ).
func noise_at(c: Vector2i, all_on: bool = false) -> float:
	var r := sim.rooms.space_id_at(c)
	var best := 40.0
	for m in sim.things_of("machine"):
		if not (m.working or (all_on and m.enabled and not m.demolish)):
			continue
		var lvl := float(NOISE.get(m.process(), 75.0)) - (6.0 if m.is_cnc() else 0.0)
		var mc := m.cell + m.size() / 2
		var d := Vector2(c - mc).length()
		var v := lvl - 2.2 * d
		if sim.rooms.space_of_thing(m) != r:
			v -= 18.0
		best = maxf(best, v)
	for cp in sim.things_of("compressor"):
		if not (sim.eng.compressor_running(cp) or (all_on and cp.enabled)):
			continue
		var d2 := Vector2(c - (cp.cell + cp.size() / 2)).length()
		var v2 := Eng.COMP_NOISE - 2.2 * d2
		if sim.rooms.space_of_thing(cp) != r:
			v2 -= 18.0
		best = maxf(best, v2)
	return best


## Подсказка для игрока: холодные помещения зимой.
func cold_rooms() -> Array:
	var out: Array = []
	for r in sim.rooms.list:
		var t := float(room_temp.get(r.id, 20.0))
		if t < Defs.sea("cold_below") and r.type != "" and r.type != "storage":
			out.append(r)
	return out


# ---------------------------------------------------------------- сохранение

func to_dict() -> Dictionary:
	return {
		"start_month": start_month, "temp_day": temp_day, "snap": snap, "snap_until": snap_until,
		"snow_from": snow_from, "snow_until": snow_until, "rain_from": rain_from, "rain_until": rain_until, "snow": Marshalls.raw_to_base64(snow),
		"ice": ice, "sanding": sanding, "burst": [burst_cell.x, burst_cell.y], "burst_until": burst_until,
	}


func from_dict(d: Dictionary) -> void:
	start_month = int(d.get("start_month", start_month))
	temp_day = float(d.get("temp_day", _base_temp(sim.day())))
	snap = float(d.get("snap", 0.0))
	snap_until = float(d.get("snap_until", -1.0))
	snow_from = float(d.get("snow_from", -1.0))
	snow_until = float(d.get("snow_until", -1.0))
	rain_from = float(d.get("rain_from", -1.0))
	rain_until = float(d.get("rain_until", -1.0))
	ice = bool(d.get("ice", false))
	sanding = bool(d.get("sanding", false))
	var b: Array = d.get("burst", [-1, -1])
	burst_cell = Vector2i(int(b[0]), int(b[1]))
	burst_until = float(d.get("burst_until", -1.0))
	setup_map()
	if d.has("snow"):
		var raw := Marshalls.base64_to_raw(str(d["snow"]))
		if raw.size() == snow.size():
			snow = raw
