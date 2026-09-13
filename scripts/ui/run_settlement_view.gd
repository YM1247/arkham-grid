class_name RunSettlementView
extends Control

const UIMotionScript = preload("res://scripts/ui/ui_motion.gd")

signal restart_requested

@onready var title_label: Label = $Center/Panel/VBox/Title
@onready var summary_label: Label = $Center/Panel/VBox/Summary
@onready var restart_button: Button = $Center/Panel/VBox/Restart


func _ready() -> void:
	restart_button.pressed.connect(func(): restart_requested.emit())


func show_result(victory: bool, summary: String) -> void:
	visible = true
	title_label.text = "探索完成" if victory else "探索失敗"
	title_label.add_theme_color_override("font_color", Color("66c98b") if victory else Color("e56b6f"))
	summary_label.text = summary
	UIMotionScript.fade_in(self, "emphasis")
	if restart_button.is_inside_tree():
		restart_button.grab_focus()


func hide_result() -> void:
	visible = false
