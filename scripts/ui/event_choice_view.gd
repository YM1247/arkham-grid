class_name EventChoiceView
extends Control

const UIMotionScript = preload("res://scripts/ui/ui_motion.gd")

signal choice_selected(option_id: String)

@onready var title_label: Label = $Background/Margin/Panel/VBox/Title
@onready var description_label: Label = $Background/Margin/Panel/VBox/Description
@onready var resource_label: Label = $Background/Margin/Panel/VBox/Resources
@onready var options_container: VBoxContainer = $Background/Margin/Panel/VBox/Options


func render(event_definition: Dictionary, previews: Array[Dictionary], state: Dictionary) -> void:
	_clear_options()
	title_label.text = str(event_definition.get("title", "未知事件"))
	description_label.text = str(event_definition.get("description", ""))
	resource_label.text = "目前資源｜HP %d/%d｜Sanity %d/%d｜MP %d/%d｜金錢 %d" % [
		int(state.get("hp", 0)), int(state.get("max_hp", 0)),
		int(state.get("sanity", 0)), int(state.get("max_sanity", 0)),
		int(state.get("mp", 0)), int(state.get("max_mp", 0)),
		int(state.get("currency", 0)),
	]
	var first_available: Button
	for index in range(previews.size()):
		var preview := previews[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 94)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%d　%s\n　　%s" % [index + 1, str(preview.get("label", "未命名選項")), str(preview.get("summary", ""))]
		button.tooltip_text = str(preview.get("description", ""))
		button.disabled = not bool(preview.get("valid", false)) or not bool(preview.get("affordable", false))
		if button.disabled and not str(preview.get("reason", "")).is_empty():
			button.tooltip_text += "\n無法選擇：%s" % preview.get("reason", "")
		else:
			button.pressed.connect(_emit_choice.bind(str(preview.get("option_id", ""))))
			if first_available == null:
				first_available = button
		options_container.add_child(button)
	visible = true
	UIMotionScript.fade_in(self)
	if first_available != null and is_inside_tree():
		first_available.grab_focus()


func hide_event() -> void:
	visible = false
	_clear_options()


func get_option_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child in options_container.get_children():
		if child is Button:
			buttons.append(child)
	return buttons


func _emit_choice(option_id: String) -> void:
	choice_selected.emit(option_id)


func _clear_options() -> void:
	for child in options_container.get_children():
		options_container.remove_child(child)
		child.queue_free()
