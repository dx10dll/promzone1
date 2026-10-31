class_name SeasonLook
extends RefCounted
## 1.55: сезонная картинка земли. Зимой — иней и снежные пятна на траве и грунте, осенью — жёлтая трава, листья и лужи.
## Весна и лето — как раньше. Всё рисуется в кусках земли WorldView (кэшируются, перерисовка только при смене сезона).

const LEAVES := [Color("#d9a72a"), Color("#c9801f"), Color("#b8561e"), Color("#e0c040"), Color("#a8452a")]


## Вид земли по сезону: "winter", "autumn" или "base" (весна, лето).
static func look(season_id: String) -> String:
	if season_id == "winter":
		return "winter"
	if season_id == "autumn":
		return "autumn"
	return "base"


## Цвет-налёт поверх земли (альфа 0 — без налёта). grass: трава (true) или грунт.
static func wash(lk: String, grass: bool, hv: int) -> Color:
	var j := float(hv % 7) * 0.012
	if lk == "winter":
		return Color(0.90, 0.94, 1.0, (0.50 if grass else 0.34) + j)
	if lk == "autumn":
		return Color(0.82, 0.58, 0.16, (0.34 if grass else 0.10) + j) if grass else Color(0.5, 0.4, 0.3, 0.10)
	return Color(0, 0, 0, 0)


static var _baked: Dictionary = {}


## Плитка земли сезонного вида: исходная с запечённым налётом (один раз на плитку, без лишних вызовов отрисовки).
static func baked(name: String, lk: String, grass: bool) -> Texture2D:
	var base := Tex.tile(name)
	if lk == "base" or base == null:
		return base
	var key := "%s@%s" % [name, lk]
	if _baked.has(key):
		return _baked[key]
	var img := base.get_image()
	if img == null:
		return base
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var ov := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	ov.fill(wash(lk, grass, 3))
	img.blend_rect(ov, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_baked[key] = t
	return t


## Сколько листьев на клетке травы (осенью): на каждой второй клетке 1–2.
static func leaf_count(lk: String, hv: int) -> int:
	return 1 + (hv >> 4) % 2 if lk == "autumn" and hv % 2 == 0 else 0


## Лужа на этой клетке (осенью, на грунте и асфальте).
static func puddle(lk: String, hv: int) -> bool:
	return lk == "autumn" and hv % 9 == 0


## Снежное пятно на этой клетке травы или грунта (зимой).
static func snow_patch(lk: String, hv: int) -> bool:
	return lk == "winter" and hv % 3 == 0


## Рисует листья, лужу или снежные пятна клетки (x, y) на узле n.
static func decorate(n: CanvasItem, lk: String, x: int, y: int, hv: int, grass: bool, T: float) -> void:
	if lk == "base":
		return
	var o := Vector2(x * T, y * T)
	if grass:
		for k in leaf_count(lk, hv):
			var h := (hv * (k + 3) * 2654435761) & 0xffff
			var c := o + Vector2(float(h % 97) / 97.0, float((h >> 7) % 89) / 89.0) * (T - 6.0) + Vector2(3, 3)
			var a := float(h % 31) * 0.2
			var d := Vector2(cos(a), sin(a)) * 2.6
			var e := Vector2(-sin(a), cos(a)) * 1.5
			n.draw_colored_polygon(PackedVector2Array([c + d, c + e, c - d, c - e]), LEAVES[h % LEAVES.size()])
	if puddle(lk, hv) and not grass:
		var pt := Tex.fx("puddle")
		if pt:
			n.draw_texture_rect(pt, Rect2(o + Vector2(-3, 4), Vector2(T + 6, T * 0.6)), false, Color(1, 1, 1, 0.85))
	if snow_patch(lk, hv):
		var sb := Tex.fx("snow_blob")
		if sb:
			n.draw_texture_rect(sb, Rect2(o + Vector2(-T * 0.2, -T * 0.2), Vector2(T, T) * 1.4), false, Color(1, 1, 1, 0.8 if grass else 0.55))
