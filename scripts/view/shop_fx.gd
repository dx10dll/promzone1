class_name ShopFx
extends RefCounted
## 1.55: живость цеха — какие эффекты показывает станок. Чистая функция от состояния: ThingView рисует по её ответу,
## тест проверяет её же. Всё рисуется «по месту» на уже существующих слоях объектов (один проход, только в кадре,
## не чаще 30 раз в секунду); отдельных узлов-частиц нет, поэтому цена — несколько линий и кружков на станок.
## Выключается настройкой «Меньше анимации» (reduce_motion) и качеством эффектов «низкое».

const ZOOM_MIN := 0.5   ## дальше этого масштаба частицы не рисуем — мелочь всё равно не видна


## «Меньше анимации» включена?
static func calm() -> bool:
	var gn: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game") if Engine.get_main_loop() is SceneTree else null
	var st: Variant = gn.get("settings") if gn else null
	return bool(st.get("reduce_motion", false)) if st is Dictionary else false


## Какое качество эффектов действует: 0 — без частиц, 1 — поменьше, 2 — всё.
static func level(setting_quality: int, reduce_motion: bool) -> int:
	return 0 if reduce_motion else clampi(setting_quality, 0, 2)


## Список эффектов станка: «sparks» (искры), «chips» (стружка), «steam» (пар), «mist» (краска), «beacon» (аварийная лампа).
## Аварийная лампа над сломанным станком есть всегда (при «Меньше анимации» — горит ровно, не мигает).
static func effects(process: String, working: bool, broken: bool, q: int, zoom: float = 1.0) -> PackedStringArray:
	var out := PackedStringArray()
	if broken:
		out.append("beacon")
	if q <= 0 or zoom < ZOOM_MIN or not working:
		return out
	match process:
		"welding", "stamping", "assembly":
			out.append("sparks")
		"turning", "milling", "drilling":
			out.append("chips")
		"casting":
			out.append("sparks")
			out.append("steam")
		"heat":
			out.append("steam")
		"paint":
			out.append("mist")
	return out


## Аварийная лампа: яркость 0–1 в момент t. Мигает оранжевым; при «Меньше анимации» — ровный свет.
static func beacon_k(t: float, reduce_motion: bool) -> float:
	if reduce_motion:
		return 0.8
	var ph := fmod(t, 0.9) / 0.9
	return 1.0 if ph < 0.5 else 0.12
