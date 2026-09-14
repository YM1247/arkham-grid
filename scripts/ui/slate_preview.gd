class_name SlatePreview
extends Control

const BadgeScript = preload("res://scripts/ui/spell_rune_badge.gd")

var block_data: BlockData
var cell_size := 28.0


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
	var origin := size * 0.5 - Vector2(bounds.position + bounds.size * 0.5) * cell_size
	for coord in block_data.cells:
		var rect := Rect2(origin + Vector2(coord) * cell_size + Vector2(1, 1), Vector2.ONE * (cell_size - 2.0))
		draw_rect(rect, block_data.color, true)
		draw_rect(rect, block_data.color.lightened(0.28), false, 2.0)


func _rebuild_badge() -> void:
	for child in get_children():
		child.queue_free()
	if block_data == null or block_data.spell == null:
		return
	var bounds := _bounds()
	var origin := custom_minimum_size * 0.5 - Vector2(bounds.position + bounds.size * 0.5) * cell_size
	var badge: Control = BadgeScript.new()
	badge.position = origin + Vector2(block_data.effect_cell) * cell_size + Vector2(2, 2)
	badge.size = Vector2.ONE * (cell_size - 4.0)
	badge.custom_minimum_size = badge.size
	badge.configure(block_data.spell)
	add_child(badge)


func _bounds() -> Rect2:
	var min_coord := Vector2(block_data.cells[0])
	var max_coord := min_coord
	for coord in block_data.cells:
		min_coord.x = minf(min_coord.x, coord.x)
		min_coord.y = minf(min_coord.y, coord.y)
		max_coord.x = maxf(max_coord.x, coord.x)
		max_coord.y = maxf(max_coord.y, coord.y)
	return Rect2(min_coord, max_coord - min_coord + Vector2.ONE)
