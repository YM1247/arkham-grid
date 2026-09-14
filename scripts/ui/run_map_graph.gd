class_name RunMapGraph
extends Control

signal node_selected(node_id: String)

const NODE_SIZE := Vector2(184, 58)
const FLOOR_GAP := 98.0
const SIDE_MARGIN := 150.0

var _map_data: Dictionary = {}
var _node_positions: Dictionary = {}
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
	custom_minimum_size = Vector2(maxf(minf(1420.0, available_width), 760.0), (max_floor + 1) * FLOOR_GAP + 50)
	_node_positions.clear()
	for node in _map_data.get("nodes", []):
		var node_id := str(node.get("id", ""))
		var column_ratio := 0.5 if max_column <= 0 else float(node.get("column", 0)) / float(max_column)
		var center := Vector2(lerpf(SIDE_MARGIN, custom_minimum_size.x - SIDE_MARGIN, column_ratio), 36.0 + int(node.get("floor", 0)) * FLOOR_GAP)
		_node_positions[node_id] = center
		var button := Button.new()
		button.position = center - NODE_SIZE * 0.5
		button.size = NODE_SIZE
		button.text = "%s  %s%s" % [_type_icon(str(node.get("type", ""))), _type_name(str(node.get("type", ""))), "  ✓" if node_id in _completed_ids else ""]
		button.tooltip_text = "第 %d 層｜%s\n路線節點：%s" % [int(node.get("floor", 0)) + 1, _type_name(str(node.get("type", ""))), node_id]
		button.disabled = node_id not in _available_ids
		button.modulate = _node_color(str(node.get("type", "")), node_id)
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
			var color := Color(0.38, 0.42, 0.5, 0.9)
			var width := 3.0
			if source_id in _completed_ids and (target_id in _completed_ids or target_id in _available_ids):
				color = Color(0.2, 0.9, 0.55, 1.0)
				width = 5.0
			elif source_id == _current_id or target_id in _available_ids:
				color = Color(1.0, 0.83, 0.25, 1.0)
				width = 4.0
			draw_line(_node_positions[source_id], _node_positions[target_id], color, width, true)


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
