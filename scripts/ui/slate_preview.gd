class_name SlatePreview
extends Control

const BadgeScript = preload("res://scripts/ui/spell_rune_badge.gd")
const SlateCellScript = preload("res://scripts/ui/slate_cell.gd")

var block_data: BlockData
var cell_size := 28.0
var badge: Control


func set_slate(value: BlockData, preview_cell_size: float = 28.0) -> void:
	block_data = value
	cell_size = preview_cell_size
	custom_minimum_size = Vector2(132, 112)
	_rebuild_badge()
	queue_redraw()


func _draw() -> void:
	if block_data == null or block_data.cells.is_empty():
		return
	var bounds := _bounds()
	var origin := _preview_origin(bounds)
	for coord in block_data.cells:
		var rect := Rect2(origin + Vector2(coord) * cell_size + Vector2(1, 1), Vector2.ONE * (cell_size - 2.0))
		var slate_color := SlateCellScript.stylized_color(block_data.color)
		draw_rect(rect, Color("090d13"), true)
		var face := rect.grow(-2.0)
		draw_rect(face, slate_color, true)
		draw_line(face.position, face.position + Vector2(face.size.x, 0), slate_color.lightened(0.24), 2.0)
		draw_line(face.end, Vector2(face.position.x, face.end.y), slate_color.darkened(0.38), 2.0)


func _rebuild_badge() -> void:
	for child in get_children():
		child.queue_free()
	badge = null
	if block_data == null or block_data.spell == null:
		return
	badge = BadgeScript.new()
	badge.size = Vector2.ONE * (cell_size - 4.0)
	badge.custom_minimum_size = badge.size
	badge.configure(block_data.spell)
	add_child(badge)
	_update_badge_position()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_badge_position()
		queue_redraw()


func _update_badge_position() -> void:
	if badge == null or not is_instance_valid(badge) or block_data == null or block_data.cells.is_empty():
		return
	badge.position = _preview_origin(_bounds()) + Vector2(block_data.effect_cell) * cell_size + Vector2(2, 2)


func _preview_origin(bounds: Rect2) -> Vector2:
	var preview_size := size
	if preview_size.x <= 0.0 or preview_size.y <= 0.0:
		preview_size = custom_minimum_size
	return preview_size * 0.5 - Vector2(bounds.position + bounds.size * 0.5) * cell_size


func _bounds() -> Rect2:
	var min_coord := Vector2(block_data.cells[0])
	var max_coord := min_coord
	for coord in block_data.cells:
		min_coord.x = minf(min_coord.x, coord.x)
		min_coord.y = minf(min_coord.y, coord.y)
		max_coord.x = maxf(max_coord.x, coord.x)
		max_coord.y = maxf(max_coord.y, coord.y)
	return Rect2(min_coord, max_coord - min_coord + Vector2.ONE)
