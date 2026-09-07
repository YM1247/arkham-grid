class_name RunMapView
extends Control

signal node_selected(node_id: String)

@onready var title_label: Label = $Margin/Panel/VBox/Title
@onready var seed_label: Label = $Margin/Panel/VBox/Seed
@onready var graph: Control = $Margin/Panel/VBox/Scroll/Graph


func _ready() -> void:
	graph.node_selected.connect(func(node_id: String): node_selected.emit(node_id))


func render(map_data: Dictionary, available_ids: Array[String], completed_ids: Array[String], current_id: String = "") -> void:
	visible = true
	title_label.text = "探索路線"
	seed_label.text = "Seed：%s｜演算法：%s" % [map_data.get("seed", "--"), map_data.get("algorithm", "fixed")]
	graph.render(map_data, available_ids, completed_ids, current_id)


func hide_map() -> void:
	visible = false

