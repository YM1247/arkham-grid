class_name StatusIconRow
extends HBoxContainer

@export var icon_font_size := 17


func refresh(entity: Entity) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if entity == null:
		visible = false
		return
	var has_status := false
	for status_id_value in CombatIconRegistry.STATUS.keys():
		var status_id := str(status_id_value)
		var amount := entity.get_status_amount(status_id)
		if amount <= 0:
			continue
		has_status = true
		var icon := Label.new()
		icon.text = "%s%d" % [CombatIconRegistry.status_glyph(status_id), amount]
		icon.tooltip_text = "%s ×%d" % [CombatIconRegistry.status_label(status_id), amount]
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.add_theme_font_size_override("font_size", icon_font_size)
		icon.add_theme_color_override("font_color", CombatIconRegistry.status_color(status_id))
		icon.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025, 0.98))
		icon.add_theme_constant_override("outline_size", 3)
		add_child(icon)
	visible = has_status
