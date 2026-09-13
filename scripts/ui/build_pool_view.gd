class_name BuildPoolView
extends Control

const UIMotionScript = preload("res://scripts/ui/ui_motion.gd")

@onready var summary_label: Label = $Background/Margin/Panel/VBox/Summary
@onready var spell_grid: GridContainer = $Background/Margin/Panel/VBox/Scroll/Content/SpellGrid
@onready var block_grid: GridContainer = $Background/Margin/Panel/VBox/Scroll/Content/BlockGrid
@onready var close_button: Button = $Background/Margin/Panel/VBox/Close


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(hide_pool)


func render(spells: Array, blocks: Array) -> void:
	_clear(spell_grid)
	_clear(block_grid)
	var spell_counts := _count_resources(spells, "content_id")
	var block_counts := _count_resources(blocks, "id")
	summary_label.text = "咒文 %d 種／%d 份　｜　方塊形狀 %d 種" % [spell_counts.size(), spells.size(), block_counts.size()]
	for spell in spells:
		if not spell is BattleItem or spell_counts.get(spell.content_id, 0) <= 0:
			continue
		spell_grid.add_child(_spell_card(spell, int(spell_counts[spell.content_id])))
		spell_counts[spell.content_id] = 0
	for block in blocks:
		if not block is BlockData or block_counts.get(block.id, 0) <= 0:
			continue
		block_grid.add_child(_block_card(block, int(block_counts[block.id])))
		block_counts[block.id] = 0
	visible = true
	UIMotionScript.fade_in(self)
	if close_button.is_inside_tree():
		close_button.grab_focus()


func hide_pool() -> void:
	visible = false


func _spell_card(spell: BattleItem, count: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 132)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s  %s　×%d\nMP %d｜%s｜Tier %d\n%s" % [spell.icon_text, spell.spell_name, count, spell.mp_cost, _rarity_name(spell.rarity), spell.tier, spell.description]
	label.tooltip_text = spell.get_effect_tooltip("目前構築")
	panel.add_child(label)
	return panel


func _block_card(block: BlockData, count: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 86)
	var label := Label.new()
	label.text = "%s　×%d\n%d 格｜Tier %d%s" % [block.display_name, count, block.cells.size(), block.tier, "｜特殊" if block.is_special else ""]
	panel.add_child(label)
	return panel


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
