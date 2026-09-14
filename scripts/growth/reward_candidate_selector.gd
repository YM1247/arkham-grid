class_name RewardCandidateSelector
extends RefCounted

const SlatePairingRulesScript = preload("res://scripts/growth/slate_pairing_rules.gd")
const RARITY_TIER := {"common": 1, "uncommon": 2, "rare": 3}

var pairing_rules = SlatePairingRulesScript.new()


func pick(rewards: Array, spell_definitions: Dictionary, block_definitions: Dictionary, context: Dictionary, count: int, rng: RandomNumberGenerator) -> Array:
	var spell_rewards := _eligible_spell_rewards(rewards, spell_definitions, context)
	var special_rewards := _eligible_special_rewards(rewards, block_definitions, context)
	var regular_shapes: Array[Dictionary] = []
	for value in block_definitions.values():
		if value is Dictionary and not bool(value.get("special", false)) and _meta_shape_allowed(value, context):
			regular_shapes.append(value)
	var selected: Array = []
	var seen_pairs := {}
	var force_special := bool(context.get("force_block_reward", false)) and not special_rewards.is_empty()
	var attempts := 0
	while selected.size() < count and attempts < 80 and not spell_rewards.is_empty():
		attempts += 1
		var spell_reward := spell_rewards[_weighted_index(spell_rewards, rng)]
		var spell: Dictionary = spell_definitions.get(str(spell_reward.get("id", "")), {})
		var shape_candidates: Array[Dictionary] = []
		if force_special and selected.is_empty():
			shape_candidates = _special_shape_candidates(special_rewards, block_definitions, spell)
		else:
			shape_candidates = _compatible_shapes(regular_shapes, spell)
			shape_candidates.append_array(_special_shape_candidates(special_rewards, block_definitions, spell))
		if shape_candidates.is_empty():
			continue
		var shape := _weighted_shape(shape_candidates, spell, rng)
		var pair_key := "%s|%s" % [spell.get("id", ""), shape.get("id", "")]
		if seen_pairs.has(pair_key):
			continue
		seen_pairs[pair_key] = true
		var cells: Array = shape.get("cells", [])
		var effect_cell: Array = cells[rng.randi_range(0, cells.size() - 1)].duplicate()
		selected.append({
			"slate_uid": _new_uid(rng),
			"shape_id": str(shape.get("id", "")),
			"spell_id": str(spell.get("id", "")),
			"effect_cell": effect_cell,
			"reward_source_id": str(spell_reward.get("id", "")),
		})
	return selected


func _eligible_spell_rewards(rewards: Array, spell_defs: Dictionary, context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reward in rewards:
		if not reward is Dictionary or str(reward.get("type", "")) != "spell" or not _base_eligible(reward, context):
			continue
		var spell: Dictionary = spell_defs.get(str(reward.get("id", "")), {})
		if spell.is_empty() or RARITY_TIER.get(str(spell.get("rarity", "common")), 1) > int(context.get("reward_tier", 1)):
			continue
		var meta_spells = context.get("meta_unlocked_spell_ids", [])
		if meta_spells is Array and not meta_spells.is_empty() and str(spell.get("id", "")) not in meta_spells:
			continue
		var weighted_reward: Dictionary = reward.duplicate(true)
		var category_id := str(spell.get("category_id", ""))
		var category_weight := 1.35 if category_id == "defense" else 1.1 if category_id in ["empower", "weaken"] else 1.0
		weighted_reward["weight"] = float(reward.get("weight", 1.0)) * category_weight
		result.append(weighted_reward)
	return result


func _eligible_special_rewards(rewards: Array, block_defs: Dictionary, context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var owned = context.get("owned_special_shape_ids", [])
	for reward in rewards:
		if not reward is Dictionary or str(reward.get("type", "")) != "block" or not _base_eligible(reward, context):
			continue
		var shape_id := str(reward.get("id", ""))
		var shape: Dictionary = block_defs.get(shape_id, {})
		if shape.is_empty() or not bool(shape.get("special", false)) or shape_id in owned or not _meta_shape_allowed(shape, context):
			continue
		if int(shape.get("tier", 1)) <= int(context.get("reward_tier", 1)):
			result.append(reward)
	return result


func _base_eligible(reward: Dictionary, context: Dictionary) -> bool:
	if int(context.get("battles_won", 0)) < int(reward.get("min_battles_won", 0)):
		return false
	if int(context.get("reward_tier", 1)) < int(reward.get("min_reward_tier", 1)):
		return false
	for required_id in reward.get("requires_rewards", []):
		if str(required_id) not in context.get("unlocked_reward_ids", []):
			return false
	return true


func _meta_shape_allowed(shape: Dictionary, context: Dictionary) -> bool:
	var meta_shapes = context.get("meta_unlocked_block_ids", [])
	return not (meta_shapes is Array and not meta_shapes.is_empty()) or str(shape.get("id", "")) in meta_shapes


func _compatible_shapes(shapes: Array[Dictionary], spell: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for shape in shapes:
		if pairing_rules.is_allowed(shape, spell):
			result.append(shape)
	return result


func _special_shape_candidates(special_rewards: Array[Dictionary], block_defs: Dictionary, spell: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reward in special_rewards:
		var shape: Dictionary = block_defs.get(str(reward.get("id", "")), {})
		if not shape.is_empty() and pairing_rules.is_allowed(shape, spell):
			var candidate := shape.duplicate(true)
			candidate["reward_weight"] = float(reward.get("weight", 1.0))
			result.append(candidate)
	return result


func _weighted_shape(shapes: Array[Dictionary], spell: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var weights: Array[float] = []
	var total := 0.0
	for shape in shapes:
		var weight := pairing_rules.pairing_weight(shape, spell) * float(shape.get("reward_weight", 1.0))
		weights.append(weight)
		total += weight
	var roll := rng.randf_range(0.0, total)
	var cursor := 0.0
	for index in range(shapes.size()):
		cursor += weights[index]
		if roll <= cursor:
			return shapes[index]
	return shapes.back()


func _weighted_index(pool: Array[Dictionary], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for reward in pool:
		total += maxf(float(reward.get("weight", 1.0)), 0.01)
	var roll := rng.randf_range(0.0, total)
	var cursor := 0.0
	for index in range(pool.size()):
		cursor += maxf(float(pool[index].get("weight", 1.0)), 0.01)
		if roll <= cursor:
			return index
	return pool.size() - 1


func _new_uid(rng: RandomNumberGenerator) -> String:
	return "slate_%08x_%08x" % [rng.randi(), rng.randi()]
