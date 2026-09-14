class_name BuildPoolView
extends Control

const UIMotionScript = preload("res://scripts/ui/ui_motion.gd")
const SlatePreviewScript = preload("res://scripts/ui/slate_preview.gd")
const SpellRuneBadgeScript = preload("res://scripts/ui/spell_rune_badge.gd")

@onready var summary_label: Label = $Background/Margin/Panel/VBox/Summary
@onready var spell_grid: GridContainer = $Background/Margin/Panel/VBox/Scroll/Content/SpellGrid
@onready var close_button: Button = $Background/Margin/Panel/VBox/Close


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(hide_pool)


func render(spells_or_slates: Array, blocks: Array = []) -> void:
	_clear(spell_grid)
	var slates := _normalize_slates(spells_or_slates, blocks)
	var unique_spells := {}
	var unique_shapes := {}
	for slate in slates:
		if slate is BlockData:
			unique_shapes[slate.id] = true
			if slate.spell != null:
				unique_spells[slate.spell.content_id] = true
	summary_label.text = "石板 %d 塊　｜　%d 種咒文　｜　%d 種形狀" % [slates.size(), unique_spells.size(), unique_shapes.size()]
	for slate in slates:
		if slate is BlockData:
			spell_grid.add_child(_slate_card(slate))
	visible = true
	UIMotionScript.fade_in(self)
	if close_button.is_inside_tree():
		close_button.grab_focus()


func hide_pool() -> void:
	visible = false


func _slate_card(slate: BlockData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(350, 142)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var preview: Control = SlatePreviewScript.new()
	preview.set_slate(slate, 27.0)
	row.add_child(preview)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = slate.spell.spell_name if slate.spell != null else "空白石板"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", slate.spell.get_icon_color() if slate.spell != null else Color.WHITE)
	details.add_child(title)
	var meta := Label.new()
	meta.text = "%s｜MP %d｜複雜度 %d" % [slate.spell.get_category_label(), slate.spell.mp_cost, slate.complexity] if slate.spell != null else "無咒文"
	details.add_child(meta)
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = slate.spell.description if slate.spell != null else ""
	description.tooltip_text = slate.spell.get_effect_tooltip("目前構築") if slate.spell != null else ""
	details.add_child(description)
	row.add_child(details)
	panel.add_child(row)
	return panel


func _normalize_slates(primary: Array, blocks: Array) -> Array[BlockData]:
	var result: Array[BlockData] = []
	if blocks.is_empty():
		for value in primary:
			if value is BlockData:
				result.append(value)
		return result
	if primary.is_empty():
		return result
	for index in range(blocks.size()):
		var block := blocks[index] as BlockData
		var spell := primary[index % primary.size()] as BattleItem
		if block != null:
			result.append(block.with_spell(spell, Vector2i.ZERO))
	return result


func _count_resources(resources: Array, property: String) -> Dictionary:
	var result := {}
	for resource in resources:
		if resource == null:
			continue
		var id := str(resource.get(property))
		result[id] = int(result.get(id, 0)) + 1
	return result


func _rarity_name(rarity: String) -> String:
	match rarity:
		"uncommon": return "罕見"
		"rare": return "稀有"
		_: return "普通"


func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
