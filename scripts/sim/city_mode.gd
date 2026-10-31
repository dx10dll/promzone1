class_name CityMode
extends RefCounted
## 1.60: «Живость города» (Game.settings["city_life"]): 2 — полная (по умолчанию), 1 — умеренная, 0 — выкл.
## Умеренная: фоновых горожан, машин и голубей вдвое меньше. Выкл.: нет горожан, автобуса без пассажиров,
## пожарных и мусорных машин на улице, голубей, поезда и кота на карте.
## Машины, которые обслуживают завод (поставки, отгрузка, посетители), и наши люди не затрагиваются.

const FULL := 2
const MODERATE := 1
const OFF := 0
## Виды машин, которые считаются городским фоном (остальные работают на завод).
const AMBIENT_VEHICLES := ["fire", "scrap"]


## Настройка из автозагрузки Game; без неё (тесты в режиме -s) — значение по умолчанию.
static func setting(key: String, def: int) -> int:
	var ml := Engine.get_main_loop()
	var g: Node = (ml as SceneTree).root.get_node_or_null("Game") if ml is SceneTree else null
	if g == null:
		return def
	return int((g.get("settings") as Dictionary).get(key, def))


static func level() -> int:
	return clampi(setting("city_life", FULL), 0, 2)


## Сколько штук фона оставить из n при данном уровне.
static func count(n: int, lvl: int = -1) -> int:
	var l := level() if lvl < 0 else lvl
	if l >= FULL:
		return n
	if l == MODERATE:
		return int(ceil(float(n) * 0.5))
	return 0


static func vehicle_shown(kind: String, lvl: int = -1) -> bool:
	var l := level() if lvl < 0 else lvl
	return l > OFF or not AMBIENT_VEHICLES.has(kind)


static func cat_shown(lvl: int = -1) -> bool:
	return (level() if lvl < 0 else lvl) > OFF
