class_name RunSettlementView
extends Control

signal restart_requested

@onready var title_label: Label = $Center/Panel/VBox/Title
@onready var summary_label: Label = $Center/Panel/VBox/Summary
@onready var restart_button: Button = $Center/Panel/VBox/Restart


func _ready() -> void:
	restart_button.pressed.connect(func(): restart_requested.emit())


func show_result(victory: bool, summary: String) -> void:
	visible = true
	title_label.text = "探索完成" if victory else "探索失敗"
	summary_label.text = summary


func hide_result() -> void:
	visible = false
