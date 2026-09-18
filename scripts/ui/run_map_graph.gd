class_name RunMapGraph
extends Control

signal node_selected(node_id: String)

const NODE_SIZE := Vector2(184, 58)
const FLOOR_GAP := 132.0
const SIDE_MARGIN := 230.0
const NODE_GAP := 48.0
const FLOOR_DRIFT := 20.0
const NODE_JITTER := 10.0
const FLOOR_JITTER := 20.0

var _map_data: Dictionary = {}
var _node_positions: Dictionary = {}
var _node_rects: Dictionary = {}
var _incoming_ids: Dictionary = {}
var _available_ids: Array[String] = []
var _completed_ids: Array[String] = []
var _current_id := ""
var _edge_count := 0


func render(map_data: Dictionary, available_ids: Array[String], completed_ids: Array[String], current_id: String) -> void:
	_map_data = map_data.duplicate(true)
	_available_ids = available_ids.duplicate()
	_completed_ids = completed_ids.duplicate()
	_current_id = current_id
	_edge_count = 0
	for node in _map_data.get("nodes", []):
		if node is Dictionary:
			_edge_count += node.get("next_ids", []).size()
	for child in get_children():
		child.queue_free()
	var max_floor := 0
	var max_column := 0
	for node in _map_data.get("nodes", []):
		max_floor = maxi(max_floor, int(node.get("floor", 0)))
		max_column = maxi(max_column, int(node.get("column", 0)))
	var available_width := get_viewport_rect().size.x - 220.0
	var collision_free_width := float(max_column) * (NODE_SIZE.x + NODE_GAP) + SIDE_MARGIN * 2.0
	custom_minimum_size = Vector2(maxf(minf(1420.0, available_width), collision_free_width), (max_floor + 1) * FLOOR_GAP + 58.0)
	_node_positions.clear()
	_node_rects.clear()
	_incoming_ids.clear()
	for node in _map_data.get("nodes", []):
		var source_id := str(node.get("id", ""))
		for target_value in node.get("next_ids", []):
			var target_id := str(target_value)
			if not _incoming_ids.has(target_id):
				_incoming_ids[target_id] = []
			_incoming_ids[target_id].append(source_id)
	var map_seed := int(_map_data.get("seed", 0))
	for node in _map_data.get("nodes", []):
		var node_id := str(node.get("id", ""))
		var floor := int(node.get("floor", 0))
		var column_ratio := 0.5 if max_column <= 0 else float(node.get("column", 0)) / float(max_column)
		var floor_drift := _signed_jitter("floor_x:%d:%d" % [map_seed, floor], FLOOR_DRIFT)
		var node_jitter := _signed_jitter("node_x:%d:%s" % [map_seed, node_id], NODE_JITTER)
		var floor_jitter := _signed_jitter("floor_y:%d:%d" % [map_seed, floor], FLOOR_JITTER)
		var center_x := lerpf(SIDE_MARGIN, custom_minimum_size.x - SIDE_MARGIN, column_ratio) + floor_drift + node_jitter
		center_x = clampf(center_x, SIDE_MARGIN - NODE_JITTER, custom_minimum_size.x - SIDE_MARGIN + NODE_JITTER)
		var center := Vector2(center_x, 40.0 + floor * FLOOR_GAP + floor_jitter)
		_node_positions[node_id] = center
		_node_rects[node_id] = Rect2(center - NODE_SIZE * 0.5, NODE_SIZE)
	# 位置先完整算好，端口排序和首幀鎖定都不再依賴尚未完成的容器版面。
	for node in _map_data.get("nodes", []):
		var node_id := str(node.get("id", ""))
		var center: Vector2 = _node_positions[node_id]
		var button := Button.new()
		button.position = center - NODE_SIZE * 0.5
		button.size = NODE_SIZE
		button.text = "%s  %s%s" % [_type_icon(str(node.get("type", ""))), _type_name(str(node.get("type", ""))), "  ✓" if node_id in _completed_ids else ""]
		button.tooltip_text = "第 %d 層｜%s\n路線節點：%s" % [int(node.get("floor", 0)) + 1, _type_name(str(node.get("type", ""))), node_id]
		button.disabled = node_id not in _available_ids
		_configure_node_style(button, str(node.get("type", "")), node_id)
		button.pressed.connect(func(): node_selected.emit(node_id))
		add_child(button)
	_configure_focus_navigation()
	queue_redraw()


func get_edge_count() -> int:
	return _edge_count


func _draw() -> void:
	for node in _map_data.get("nodes", []):
		var source_id := str(node.get("id", ""))
		if not _node_positions.has(source_id):
			continue
		for next_id_value in node.get("next_ids", []):
			var target_id := str(next_id_value)
			if not _node_positions.has(target_id):
				continue
			var style := get_edge_style(source_id, target_id)
			var route := _edge_route(source_id, target_id)
			# 像素化斷線只連接節點外緣；每條分支使用不同端口，不穿過文字也不共線。
			draw_dashed_line(route[0], route[1], Color(0.015, 0.02, 0.03, 0.92), style.width + 4.0, 10.0, false, false)
			draw_dashed_line(route[0], route[1], style.color, style.width, 10.0, false, false)


func _edge_route(source_id: String, target_id: String) -> PackedVector2Array:
	var source_rect: Rect2 = _node_rects[source_id]
	var target_rect: Rect2 = _node_rects[target_id]
	var outgoing: Array = _next_ids_for(source_id)
	outgoing.sort_custom(func(a, b): return _node_positions.get(str(a), Vector2.ZERO).x < _node_positions.get(str(b), Vector2.ZERO).x)
	var incoming: Array = _incoming_ids.get(target_id, []).duplicate()
	incoming.sort_custom(func(a, b): return _node_positions.get(str(a), Vector2.ZERO).x < _node_positions.get(str(b), Vector2.ZERO).x)
	var source_offset := _port_offset(outgoing.find(target_id), outgoing.size())
	var target_offset := _port_offset(incoming.find(source_id), incoming.size())
	return PackedVector2Array([
		Vector2(source_rect.get_center().x + source_offset, source_rect.end.y + 3.0),
		Vector2(target_rect.get_center().x + target_offset, target_rect.position.y - 3.0),
	])


func _next_ids_for(source_id: String) -> Array:
	for node in _map_data.get("nodes", []):
		if str(node.get("id", "")) == source_id:
			var result: Array = []
			for value in node.get("next_ids", []):
				result.append(str(value))
			return result
	return []


func _port_offset(index: int, count: int) -> float:
	if count <= 1 or index < 0:
		return 0.0
	return (float(index) - float(count - 1) * 0.5) * minf(34.0, NODE_SIZE.x / float(count + 1))


func _signed_jitter(key: String, amplitude: float) -> float:
	var stable := 17
	for codepoint in key.to_utf32_buffer():
		stable = int((stable * 31 + int(codepoint)) % 2147483647)
	return (float(stable % 2001) / 1000.0 - 1.0) * amplitude


func get_edge_style(source_id: String, target_id: String) -> Dictionary:
	if source_id in _completed_ids and target_id in _completed_ids:
		return {"color": Color(0.2, 0.9, 0.55, 1.0), "width": 5.0, "state": "completed"}
	# 可前往的是「已完成節點通往目前候選」的那一段；同一候選的其他匯入線仍為灰色。
	if source_id in _completed_ids and target_id in _available_ids:
		return {"color": Color(1.0, 0.83, 0.25, 1.0), "width": 4.0, "state": "available"}
	return {"color": Color(0.38, 0.42, 0.5, 0.9), "width": 3.0, "state": "locked"}


func _node_color(type: String, node_id: String) -> Color:
	if node_id in _available_ids:
		return Color(1.0, 0.9, 0.45)
	match type:
		"normal_battle": return Color(0.75, 0.82, 0.95)
		"elite": return Color(1.0, 0.55, 0.4)
		"boss": return Color(0.9, 0.3, 0.35)
		"event": return Color(0.65, 0.55, 0.95)
		"shop": return Color(0.95, 0.78, 0.35)
		"rest": return Color(0.45, 0.85, 0.6)
		_: return Color.WHITE


func _configure_node_style(button: Button, type: String, node_id: String) -> void:
	var color := _node_color(type, node_id)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", color.lightened(0.24))
	button.add_theme_color_override("font_disabled_color", color.darkened(0.22))
	button.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025, 0.96))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_stylebox_override("normal", _node_style(Color(0.02, 0.03, 0.045, 0.64), color.darkened(0.25), 1))
	button.add_theme_stylebox_override("hover", _node_style(Color(0.12, 0.11, 0.09, 0.72), color, 2))
	button.add_theme_stylebox_override("pressed", _node_style(Color(0.2, 0.15, 0.08, 0.78), color.lightened(0.18), 2))
	button.add_theme_stylebox_override("disabled", _node_style(Color(0.02, 0.03, 0.045, 0.52), color.darkened(0.5), 1))
	button.add_theme_stylebox_override("focus", _node_style(Color(0, 0, 0, 0), Color("f2ce78"), 3))


func _node_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _type_name(type: String) -> String:
	match type:
		"normal_battle": return "普通戰鬥"
		"elite": return "菁英"
		"boss": return "Boss"
		"event": return "事件"
		"shop": return "商店"
		"rest": return "休息"
		_: return type


func _type_icon(type: String) -> String:
	match type:
		"normal_battle": return "⚔"
		"elite": return "◆"
		"boss": return "☠"
		"event": return "?"
		"shop": return "$"
		"rest": return "♨"
		_: return "•"


func _configure_focus_navigation() -> void:
	var available_buttons: Array[Button] = []
	for child in get_children():
		if child is Button and not child.disabled:
			available_buttons.append(child)
	if available_buttons.is_empty():
		return
	available_buttons.sort_custom(func(a: Button, b: Button): return a.position.y < b.position.y)
	for index in range(available_buttons.size()):
		var button := available_buttons[index]
		button.focus_neighbor_top = available_buttons[maxi(index - 1, 0)].get_path()
		button.focus_neighbor_bottom = available_buttons[mini(index + 1, available_buttons.size() - 1)].get_path()
	if available_buttons[0].is_inside_tree():
		available_buttons[0].grab_focus()
