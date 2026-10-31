class_name Thing
extends RefCounted
## Объект на участке: станок, стеллаж, стол, туалет и т.д.

var id := 0
var def_id := ""
var cell := Vector2i.ZERO   ## левая верхняя клетка
var built := false
var build_work := 0.0       ## сколько минут уже строили
var progress := 0.0         ## прогресс текущей операции станка 0..1
var working := false
var condition := 100.0      ## износ станка
var product := ""           ## что сейчас делает станок
var user := -1              ## кто работает на объекте
var spot_users: Dictionary = {} ## индекс места -> id рабочего
var incoming: Array = []    ## по слотам: сколько единиц уже несут сюда
var incoming_key: Array = [] ## по слотам: какой груз несут (если слот пуст)
var demolish := false       ## помечен под снос
var parts_made := 0
var cost_paid := 0.0
var enabled := true          ## станок включён игроком
var broken := false          ## станок сломан — нужен ремонт
var job_step := 0            ## какую операцию маршрута выполняет станок (product — изделие)
var batch_t := 0.0           ## прогресс партии в печи
var setup_key := ""          ## под какую операцию наладен станок («изделие:шаг»)
var util := 0.0              ## загрузка станка в рабочее время (скользящее среднее 0–1)
var defects := 0             ## сколько деталей с браком сделано на станке
var crates_need := 0         ## сколько ящиков с оборудованием нужно привезти к месту установки
var crates_in := 0           ## сколько уже принесли
var order_eta := -1.0        ## когда приедет фургон с оборудованием (-1 — уже привезли или не заказано)
var charge := 0.0            ## 1.13: заряд аккумуляторного шкафа, кВт·ч
var owner := -1              ## 1.15: за кем закреплено рабочее место (id работника, -1 — ни за кем)
var rot := 0                 ## поворот: 0 — рабочая сторона снизу (юг), 1 — слева (запад), 2 — сверху, 3 — справа


func def() -> Dictionary:
	return Defs.objects.get(def_id, {})


## 1.39: название по-русски, как в данных (для журнала денег).
func title_ru() -> String:
	return str(def().get("name", def_id))


func title() -> String:
	return L.dt("object.%s.name" % def_id, str(def().get("name", def_id)))   # 1.39: на языке игры


func base_size() -> Vector2i:
	var s: Array = def().get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


## Размер с учётом поворота: на 90° и 270° ширина и высота меняются местами.
func size() -> Vector2i:
	return Thing.rot_size(base_size(), rot)


static func rot_size(s: Vector2i, r: int) -> Vector2i:
	return Vector2i(s.y, s.x) if r % 2 == 1 else s


## Клетка (смещение от левого верхнего угла в исходной ориентации) после поворота на r четвертей
## по часовой стрелке. Работает и для клеток снаружи футпринта (места работы).
## Поворот 3 (лицом вправо) — зеркало поворота 1: спрайт для него — отражённый боковой вид,
## поэтому и места работы отражаются, а не поворачиваются (иначе рабочий стоит не там, где станок).
static func rot_offset(o: Vector2i, s: Vector2i, r: int) -> Vector2i:
	var rr := (r % 4 + 4) % 4
	if rr == 3:
		var p1 := rot_offset(o, s, 1)
		return Vector2i(s.y - 1 - p1.x, p1.y)
	var p := o
	var sz := s
	for k in rr:
		p = Vector2i(sz.y - 1 - p.y, p.x)
		sz = Vector2i(sz.y, sz.x)
	return p


const FACE_CW := {"down": "left", "left": "up", "up": "right", "right": "down"}


static func rot_face(f: String, r: int) -> String:
	var rr := (r % 4 + 4) % 4
	if rr == 3:
		var f1 := rot_face(f, 1)
		return {"left": "right", "right": "left"}.get(f1, f1)
	var out := f
	for k in rr:
		out = str(FACE_CW.get(out, out))
	return out


## Спрайт с учётом поворота: [ключ, отразить по горизонтали].
## 0 — лицом вниз (основной), 1 — лицом влево (боковой «_v»), 2 — лицом вверх (вид сзади «_b»,
## если его нет — отражённый основной), 3 — лицом вправо (отражённый боковой).
static func sprite_for(def_id: String, r: int) -> Array:
	var rr := (r % 4 + 4) % 4
	var has_v := Defs.sprites.has(def_id + "_v")
	match rr:
		1:
			return [def_id + "_v", false] if has_v else [def_id, true]
		2:
			return [def_id + "_b", false] if Defs.sprites.has(def_id + "_b") else [def_id, true]
		3:
			return [def_id + "_v", true] if has_v else [def_id, false]
	return [def_id, false]


## Сколько вариантов поворота у объекта: 4 — есть боковой вид, 2 — есть вид сзади (или вытянутый
## объект можно развернуть), 1 — поворачивать незачем (цветок, урна, поддон).
static func rotations(def_id: String) -> int:
	var d: Dictionary = Defs.objects.get(def_id, {})
	if bool(d.get("no_rotate", false)):
		return 1
	if Defs.sprites.has(def_id + "_v"):
		return 4
	var s: Array = d.get("size", [1, 1])
	if Defs.sprites.has(def_id + "_b") or int(s[0]) != int(s[1]):
		return 2
	return 1


## Следующий допустимый поворот.
static func next_rot(def_id: String, r: int) -> int:
	match rotations(def_id):
		1:
			return 0
		2:
			return 2 if r == 0 else 0
	return (r + 1) % 4


func kind() -> String:
	return str(def().get("kind", "decor"))


## 1.47: низкий объект (поддон, тара): через него можно перелезть — клетка проходима, но дорого и медленно.
func is_low() -> bool:
	return bool(def().get("low", false))


func blocks() -> bool:
	return bool(def().get("blocks", true))


## 1.30: перекрывает ли объект именно эту клетку. У проходной клетки турникетов («walk») проходимы.
func blocks_at(cc: Vector2i) -> bool:
	if not blocks():
		return false
	var wl: Array = def().get("walk", [])
	if wl.is_empty():
		return true
	var bs := base_size()
	for o: Array in wl:
		if cell + Thing.rot_offset(Vector2i(int(o[0]), int(o[1])), bs, rot) == cc:
			return false
	return true


## 1.30: проходимые клетки объекта (турникеты проходной) с учётом поворота.
func walk_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var bs := base_size()
	for o: Array in def().get("walk", []):
		out.append(cell + Thing.rot_offset(Vector2i(int(o[0]), int(o[1])), bs, rot))
	return out


## 1.30: клетка, где сидит охранник (будка проходной); (-1, -1) — нет.
func seat_cell() -> Vector2i:
	var a: Array = def().get("seat", [])
	if a.size() < 2:
		return Vector2i(-1, -1)
	return cell + Thing.rot_offset(Vector2i(int(a[0]), int(a[1])), base_size(), rot)


## Светильник под потолком: не занимает клетку на полу, может висеть над станком.
func is_ceiling() -> bool:
	return bool(def().get("ceiling", false))


## Клетка подключения (розетка): 1.18 — кабель и трубу заводят именно в неё.
## По умолчанию — задний правый угол (сзади от рабочей стороны).
func inlet_cell() -> Vector2i:
	var bs := base_size()
	var o := Vector2i(bs.x - 1, 0)
	if def().has("inlet"):
		var a: Array = def()["inlet"]
		o = Vector2i(int(a[0]), int(a[1]))
	return cell + Thing.rot_offset(o, bs, rot)


## Нужна ли вода (туалет, раковина, испытательный стенд).
func needs_water() -> bool:
	return bool(def().get("water", false))


func rect() -> Rect2i:
	return Rect2i(cell, size())


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := size()
	for y in s.y:
		for x in s.x:
			out.append(cell + Vector2i(x, y))
	return out


func slot_count() -> int:
	if kind() == "machine":
		return 2
	var st: Dictionary = def().get("storage", {})
	return int(st.get("slots", 0))


func slot_cap(s: int) -> int:
	if kind() == "machine":
		var m: Dictionary = def().get("machine", {})
		return int(m.get("in_cap", 1)) if s == 0 else int(m.get("out_cap", 1))
	var st: Dictionary = def().get("storage", {})
	return int(st.get("cap", 0))


func slot_accepts(s: int, cat: String) -> bool:
	if kind() == "machine":
		return (s == 0 and (cat == "mat" or cat == "wip" or cat == "ok")) or (s == 1 and (cat == "wip" or cat == "machined"))
	var st: Dictionary = def().get("storage", {})
	var acc: Array = st.get("accept", [])
	return acc.has(cat)


## Это склад общего назначения (стеллаж, поддон, тара)?
func is_storage() -> bool:
	return kind() == "storage"


func spots() -> Array:
	var out: Array = []
	var arr: Array = def().get("spots", [])
	var bs := base_size()
	for i in arr.size():
		var s: Array = arr[i]
		var o := Thing.rot_offset(Vector2i(int(s[0]), int(s[1])), bs, rot)
		out.append({"cell": cell + o, "face": Thing.rot_face(str(s[2]), rot), "idx": i})
	return out


func ensure_incoming() -> void:
	var n := slot_count()
	if incoming.size() != n:
		incoming.resize(n)
		incoming_key.resize(n)
		for i in n:
			incoming[i] = 0
			incoming_key[i] = ""


func machine_def() -> Dictionary:
	return def().get("machine", {})


func process() -> String:
	return str(machine_def().get("process", ""))


## 1.16: до какого размера деталей берёт станок (0 мелкие, 1 средние, 2 крупные).
func part_rank() -> int:
	return Defs.size_rank(str(machine_def().get("part_size", "l")))


## Влезает ли изделие на этот станок.
func fits_part(p: String) -> bool:
	return Defs.product_rank(p) <= part_rank()


func is_cnc() -> bool:
	return bool(machine_def().get("cnc", false))


func is_batch() -> bool:
	return bool(machine_def().get("batch", false))


func to_dict() -> Dictionary:
	return {
		"id": id, "def": def_id, "cx": cell.x, "cy": cell.y, "built": built,
		"bw": build_work, "progress": progress, "cond": condition, "product": product,
		"demolish": demolish, "made": parts_made, "paid": cost_paid, "on": enabled, "broken": broken, "jstep": job_step, "batch": batch_t, "setup": setup_key, "util": util, "defects": defects, "rot": rot, "cr_need": crates_need, "cr_in": crates_in, "eta": order_eta, "charge": charge, "own": owner,
	}


static func from_dict(d: Dictionary) -> Thing:
	var t := Thing.new()
	t.id = int(d["id"])
	t.def_id = str(d["def"])
	t.cell = Vector2i(int(d["cx"]), int(d["cy"]))
	t.built = bool(d["built"])
	t.build_work = float(d.get("bw", 0.0))
	t.progress = float(d.get("progress", 0.0))
	t.condition = float(d.get("cond", 100.0))
	t.product = str(d.get("product", ""))
	t.demolish = bool(d.get("demolish", false))
	t.parts_made = int(d.get("made", 0))
	t.cost_paid = float(d.get("paid", 0.0))
	t.enabled = bool(d.get("on", true))
	t.broken = bool(d.get("broken", false))
	t.job_step = int(d.get("jstep", 0))
	t.batch_t = float(d.get("batch", 0.0))
	t.setup_key = str(d.get("setup", ""))
	t.util = float(d.get("util", 0.0))
	t.defects = int(d.get("defects", 0))
	t.rot = int(d.get("rot", 0))
	t.crates_need = int(d.get("cr_need", 0))
	t.crates_in = int(d.get("cr_in", 0))
	t.order_eta = float(d.get("eta", -1.0))
	t.charge = float(d.get("charge", 0.0))
	t.owner = int(d.get("own", -1))
	t.ensure_incoming()
	return t
