extends GridContainer

const DROP_EDGE_TOLERANCE := 7.0


func _can_drop_data(at_position: Vector2, data) -> bool:
	var target := _nearest_cell(at_position)
	if target.x < 0:
		return false
	var tablet := get_parent().get_parent()
	return tablet.preview_drop_at_cell(target.x, target.y, data)


func _drop_data(at_position: Vector2, data) -> void:
	var target := _nearest_cell(at_position)
	if target.x < 0:
		return
	var tablet := get_parent().get_parent()
	tablet.commit_drop_at_cell(target.x, target.y, data)


func _nearest_cell(at_position: Vector2) -> Vector2i:
	if get_child_count() == 0 or columns <= 0:
		return Vector2i(-1, -1)
	var sample := get_child(0) as Control
	if sample == null:
		return Vector2i(-1, -1)
	var horizontal_gap := float(get_theme_constant("h_separation"))
	var vertical_gap := float(get_theme_constant("v_separation"))
	var stride := sample.size + Vector2(horizontal_gap, vertical_gap)
	var tolerated := Rect2(-Vector2.ONE * DROP_EDGE_TOLERANCE, size + Vector2.ONE * DROP_EDGE_TOLERANCE * 2.0)
	if not tolerated.has_point(at_position):
		return Vector2i(-1, -1)
	var x := clampi(int(round((at_position.x - sample.size.x * 0.5) / stride.x)), 0, columns - 1)
	var rows := int(ceil(float(get_child_count()) / float(columns)))
	var y := clampi(int(round((at_position.y - sample.size.y * 0.5) / stride.y)), 0, rows - 1)
	return Vector2i(x, y)
