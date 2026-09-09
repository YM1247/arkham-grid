class_name RewardCandidateSelector
extends RefCounted

const RARITY_TIER := {"common": 1, "uncommon": 2, "rare": 3}


func pick(rewards: Array, spell_definitions: Dictionary, block_definitions: Dictionary, context: Dictionary, count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array[Dictionary] = []
	var seen_ids := {}
	for value in rewards:
		if not value is Dictionary:
			continue
		var reward: Dictionary = value
		var content_id := str(reward.get("id", ""))
		if content_id.is_empty() or seen_ids.has(content_id):
			continue
		if not _is_eligible(reward, spell_definitions, block_definitions, context):
			continue
		seen_ids[content_id] = true
		pool.append(reward)
	var selected: Array = []
	if bool(context.get("force_block_reward", false)):
		var block_pool: Array[Dictionary] = []
		for reward in pool:
			if str(reward.get("type", "")) == "block":
				block_pool.append(reward)
		if not block_pool.is_empty():
			var forced := block_pool[_weighted_index(block_pool, rng)]
			selected.append(forced)
			pool.erase(forced)
	while selected.size() < count and not pool.is_empty():
		var index := _weighted_index(pool, rng)
		selected.append(pool[index])
		pool.remove_at(index)
	return selected


func _is_eligible(reward: Dictionary, spell_defs: Dictionary, block_defs: Dictionary, context: Dictionary) -> bool:
	if int(context.get("battles_won", 0)) < int(reward.get("min_battles_won", 0)):
		return false
	if int(context.get("reward_tier", 1)) < int(reward.get("min_reward_tier", 1)):
		return false
	for required_id in reward.get("requires_rewards", []):
		if str(required_id) not in context.get("unlocked_reward_ids", []):
			return false
	var definition: Dictionary
	var reward_type := str(reward.get("type", ""))
	var reward_id := str(reward.get("id", ""))
	if reward_type == "spell":
		var meta_spells = context.get("meta_unlocked_spell_ids", [])
		if meta_spells is Array and not meta_spells.is_empty() and reward_id not in meta_spells:
			return false
		definition = spell_defs.get(reward_id, {})
		if RARITY_TIER.get(str(definition.get("rarity", "common")), 1) > int(context.get("reward_tier", 1)):
			return false
	elif reward_type == "block":
		var meta_blocks = context.get("meta_unlocked_block_ids", [])
		if meta_blocks is Array and not meta_blocks.is_empty() and reward_id not in meta_blocks:
			return false
		# 特殊形狀只需解鎖一次，避免重複份數讓低格數方塊壟斷手牌。
		if reward_id in context.get("unlocked_reward_ids", []):
			return false
		definition = block_defs.get(reward_id, {})
		if int(definition.get("tier", 1)) > int(context.get("reward_tier", 1)):
			return false
	else:
		return false
	if definition.is_empty():
		return false
	return true


func _weighted_index(pool: Array[Dictionary], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for reward in pool:
		total += maxf(float(reward.get("weight", 1.0)), 0.01)
	var roll := rng.randf_range(0.0, total)
	var cursor := 0.0
	for i in range(pool.size()):
		cursor += maxf(float(pool[i].get("weight", 1.0)), 0.01)
		if roll <= cursor:
			return i
	return pool.size() - 1
