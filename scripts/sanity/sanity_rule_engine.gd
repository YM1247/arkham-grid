class_name SanityRuleEngine
extends RefCounted

const MadnessEffectScript = preload("res://scripts/sanity/madness_effect.gd")

var document: Dictionary = {}
var active_effect_ids: Array[String] = []
var _effect_index: Dictionary = {}
var _behaviors: Dictionary = {}
var _ordered_effect_ids: Array[String] = []


func configure(config: Dictionary, seed: int = 0, restored_effect_ids: Array[String] = []) -> void:
	document = config.duplicate(true)
	_effect_index.clear()
	_behaviors.clear()
	_ordered_effect_ids.clear()
	for effect in document.get("effects", []):
		if not effect is Dictionary:
			continue
		var effect_id := str(effect.get("id", ""))
		_effect_index[effect_id] = effect
		var path := str(effect.get("behavior_resource", ""))
		var behavior = load(path) if ResourceLoader.exists(path) else null
		if behavior != null:
			_behaviors[effect_id] = behavior
		_ordered_effect_ids.append(effect_id)
	if not _ordered_effect_ids.is_empty():
		var offset: int = absi(seed) % _ordered_effect_ids.size()
		var rotated: Array[String] = []
		for index in range(_ordered_effect_ids.size()):
			rotated.append(_ordered_effect_ids[(index + offset) % _ordered_effect_ids.size()])
		_ordered_effect_ids = rotated
	active_effect_ids.clear()
	for effect_id in restored_effect_ids:
		if _effect_index.has(effect_id) and effect_id not in active_effect_ids:
			active_effect_ids.append(effect_id)


func synchronize(sanity: int) -> Dictionary:
	var before := active_effect_ids.duplicate()
	var desired := _desired_effect_count(sanity)
	while active_effect_ids.size() < desired:
		var next_id := _next_inactive_effect()
		if next_id.is_empty():
			break
		active_effect_ids.append(next_id)
	while active_effect_ids.size() > desired:
		active_effect_ids.pop_back()
	var added: Array[String] = []
	var removed: Array[String] = []
	for effect_id in active_effect_ids:
		if effect_id not in before:
			added.append(effect_id)
	for effect_id in before:
		if effect_id not in active_effect_ids:
			removed.append(effect_id)
	return {"active": active_effect_ids.duplicate(), "added": added, "removed": removed, "stage": get_stage_name(sanity)}


func preview(current_sanity: int, delta: int) -> Dictionary:
	var final_sanity := maxi(current_sanity + delta, 0)
	var desired := _desired_effect_count(final_sanity)
	var projected := active_effect_ids.duplicate()
	for effect_id in _ordered_effect_ids:
		if projected.size() >= desired:
			break
		if effect_id not in projected:
			projected.append(effect_id)
	while projected.size() > desired:
		projected.pop_back()
	var added: Array[String] = []
	var removed: Array[String] = []
	for effect_id in projected:
		if effect_id not in active_effect_ids:
			added.append(effect_id)
	for effect_id in active_effect_ids:
		if effect_id not in projected:
			removed.append(effect_id)
	return {"sanity": final_sanity, "stage": get_stage_name(final_sanity), "effects": projected, "added": added, "removed": removed, "defeat": final_sanity <= 0}


func describe_preview(current_sanity: int, delta: int) -> String:
	var result := preview(current_sanity, delta)
	var text := "預覽：SAN %d → %d" % [current_sanity, result.sanity]
	if bool(result.defeat):
		return text + "（理智歸零，Run 失敗）"
	if not result.added.is_empty():
		text += "；新增瘋狂：%s" % _effect_names(result.added)
	if not result.removed.is_empty():
		text += "；解除：%s" % _effect_names(result.removed)
	return text


func apply_entity_modifiers(entity: Entity) -> void:
	if entity == null:
		return
	entity.set_meta("madness_attack_modifier", 0)
	entity.set_meta("madness_armor_modifier", 0)
	for effect_id in active_effect_ids:
		var behavior = _behaviors.get(effect_id)
		if behavior != null:
			behavior.apply_to_entity(_effect_index.get(effect_id, {}), entity)


func modify_magic_cost(value: int) -> int:
	var result := value
	for effect_id in active_effect_ids:
		var behavior = _behaviors.get(effect_id)
		if behavior != null:
			result = behavior.modify_magic_cost(_effect_index.get(effect_id, {}), result)
	return result


func modify_dead_board_penalty(value: int) -> int:
	var result := value
	for effect_id in active_effect_ids:
		var behavior = _behaviors.get(effect_id)
		if behavior != null:
			result = behavior.modify_dead_board_penalty(_effect_index.get(effect_id, {}), result)
	return result


func get_active_summary() -> String:
	return _effect_names(active_effect_ids)


func get_stage_name(sanity: int) -> String:
	var stage_name := "穩定"
	for stage in document.get("stages", []):
		if stage is Dictionary and sanity <= int(stage.get("threshold", -1)):
			stage_name = str(stage.get("display_name", stage.get("id", "")))
	return stage_name


func get_source_label(source: String) -> String:
	var prefix := source.get_slice(":", 0)
	return str(document.get("source_labels", {}).get(prefix, source))


func _desired_effect_count(sanity: int) -> int:
	var count := 0
	for stage in document.get("stages", []):
		if stage is Dictionary and sanity <= int(stage.get("threshold", -1)):
			count = maxi(count, int(stage.get("effect_count", 0)))
	return mini(count, _ordered_effect_ids.size())


func _next_inactive_effect() -> String:
	for effect_id in _ordered_effect_ids:
		if effect_id not in active_effect_ids:
			return effect_id
	return ""


func _effect_names(ids: Array) -> String:
	var names: Array[String] = []
	for effect_id in ids:
		var definition: Dictionary = _effect_index.get(str(effect_id), {})
		names.append(str(definition.get("display_name", effect_id)))
	return "、".join(names)
