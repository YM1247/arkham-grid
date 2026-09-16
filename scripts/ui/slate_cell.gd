class_name SlateCell
extends Control

var base_color := Color("596270")


func configure(value: Color) -> void:
	base_color = stylized_color(value)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	if bounds.size.x < 4.0 or bounds.size.y < 4.0:
		return
	# 粗顆粒的石板陰影、磨損邊與切角。刻意只用整數像素，避免與像素背景脫節。
	draw_rect(bounds, Color("090d13"), true)
	var face := Rect2(Vector2(2, 1), bounds.size - Vector2(4, 4))
	draw_rect(face, base_color.darkened(0.08), true)
	draw_line(face.position, face.position + Vector2(face.size.x, 0), base_color.lightened(0.24), 2.0)
	draw_line(face.position, face.position + Vector2(0, face.size.y), base_color.lightened(0.14), 2.0)
	draw_line(face.end, Vector2(face.position.x, face.end.y), base_color.darkened(0.38), 3.0)
	draw_line(face.end, Vector2(face.end.x, face.position.y), base_color.darkened(0.32), 3.0)
	var chip := base_color.darkened(0.48)
	draw_rect(Rect2(Vector2(2, 1), Vector2(5, 3)), chip, true)
	draw_rect(Rect2(Vector2(size.x - 7, size.y - 6), Vector2(5, 3)), chip, true)
	draw_line(Vector2(size.x * 0.62, 4), Vector2(size.x * 0.55, 10), base_color.darkened(0.3), 1.0)


static func stylized_color(value: Color) -> Color:
	if value.s < 0.08:
		return Color.from_hsv(0.11, 0.16, clampf(value.v * 0.72, 0.34, 0.72), 1.0)
	return Color.from_hsv(value.h, minf(value.s * 0.62, 0.52), clampf(value.v * 0.68, 0.34, 0.72), 1.0)
