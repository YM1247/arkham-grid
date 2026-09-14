class_name RunMapView
extends Control

signal node_selected(node_id: String)
signal pool_requested

@onready var title_label: Label = $Margin/Panel/VBox/Title
@onready var progress_label: Label = $Margin/Panel/VBox/Meta/Progress
@onready var seed_label: Label = $Margin/Panel/VBox/Meta/Seed
@onready var graph: Control = $Margin/Panel/VBox/Scroll/Center/Graph


func _ready() -> void:
	graph.node_selected.connect(func(node_id: String): node_selected.emit(node_id))
	$Margin/Panel/VBox/Meta/Pool.pressed.connect(func(): pool_requested.emit())


func render(map_data: Dictionary, available_ids: Array[String], completed_ids: Array[String], current_id: String = "") -> void:
	visible = true
	title_label.text = "選擇下一個節點"
	var total_layers := int(map_data.get("layers", _max_floor(map_data) + 1))
	progress_label.text = "進度｜%d / %d 節點完成" % [completed_ids.size(), total_layers]
	seed_label.text = "路線種子 %s" % map_data.get("seed", "--")
	graph.render(map_data, available_ids, completed_ids, current_id)


func hide_map() -> void:
	visible = false


func _max_floor(map_data: Dictionary) -> int:
	var result := 0
	for node in map_data.get("nodes", []):
		if node is Dictionary:
			result = maxi(result, int(node.get("floor", 0)))
	return result
