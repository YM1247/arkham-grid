class_name RewardCandidateSelector
extends RefCounted

const RARITY_TIER := {"common": 1, "uncommon": 2, "rare": 3}


func pick(rewards: Array, item_definitions: Dictionary, block_definitions: Dictionary, context: Dictionary, count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array[Dictionary] = []
	var seen_ids := {}
	for value in rewards:
		if not value is Dictionary:
			continue
		var reward: Dictionary = value
		var content_id := str(reward.get("id", ""))
		if content_id.is_empty() or seen_ids.has(content_id):
			continue
		if not _is_eligible(reward, item_definitions, block_definitions, context):
			continue
		seen_ids[content_id] = true
		pool.append(reward)
	var selected: Array = []
	while selected.size() < count and not pool.is_empty():
		var index := _weighted_index(pool, rng)
		selected.append(pool[index])
		pool.remove_at(index)
	return selected


func _is_eligible(reward: Dictionary, item_defs: Dictionary, block_defs: Dictionary, context: Dictionary) -> bool:
	if int(context.get("battles_won", 0)) < int(reward.get("min_battles_won", 0)):
		return false
	if int(context.get("reward_tier", 1)) < int(reward.get("min_reward_tier", 1)):
		return false
	for required_id in reward.get("requires_rewards", []):
		if str(required_id) not in context.get("unlocked_reward_ids", []):
			return false
	var definition: Dictionary
	if str(reward.get("type", "")) == "item":
		definition = item_defs.get(str(reward.get("id", "")), {})
		if RARITY_TIER.get(str(definition.get("rarity", "common")), 1) > int(context.get("reward_tier", 1)):
			return false
	else:
		definition = block_defs.get(str(reward.get("id", "")), {})
		if int(definition.get("tier", 1)) > int(context.get("reward_tier", 1)):
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
