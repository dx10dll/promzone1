extends Node2D
## Галерея ассетов для проверки графики: godot --path . res://tests/gallery.tscn -- <папка> <файл.png> [фильтр]

var frames := 0
var out := "/tmp/gallery.png"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var folder := a[0] if a.size() > 0 else "objects"
	out = a[1] if a.size() > 1 else out
	var filt := a[2] if a.size() > 2 else ""
	RenderingServer.set_default_clear_color(Color("#c9c3b5"))
	var da := DirAccess.open("res://assets/" + folder)
	var files: Array = []
	for f in da.get_files():
		if f.ends_with(".svg") and (filt == "" or f.contains(filt)):
			files.append(f)
	files.sort()
	var x := 10.0
	var y := 10.0
	var row_h := 0.0
	for f in files:
		var tex: Texture2D = Tex.get_tex("res://assets/%s/%s" % [folder, f])
		var sz := tex.get_size()
		if x + sz.x > 1580:
			x = 10
			y += row_h + 28
			row_h = 0
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.position = Vector2(x, y)
		add_child(sp)
		var l := Label.new()
		l.text = f.get_basename()
		l.position = Vector2(x, y + sz.y + 2)
		l.add_theme_color_override("font_color", Color.BLACK)
		l.add_theme_font_size_override("font_size", 12)
		add_child(l)
		x += sz.x + 18
		row_h = maxf(row_h, sz.y)


func _process(_d: float) -> void:
	frames += 1
	if frames == 8:
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
