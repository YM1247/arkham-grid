class_name EncounterDifficultyCalculator
extends RefCounted


func calculate(enemy_defs: Array, model: Dictionary) -> Dictionary:
	var total_hp := 0
	var total_attack := 0
	var tier_sum := 0
	var sanity_count := 0
	for enemy in enemy_defs:
		if not enemy is Dictionary:
			continue
		total_hp += int(enemy.get("hp", 0))
		total_attack += int(enemy.get("attack", 0))
		tier_sum += int(enemy.get("tier", 1))
		if bool(enemy.get("sanity_pressure", false)):
			sanity_count += 1
	var strength := int(round(
		float(total_hp) * float(model.get("hp_weight", 0.35))
		+ float(total_attack) * float(model.get("attack_weight", 2.0))
		+ float(tier_sum) * float(model.get("enemy_tier_weight", 12.0))
		+ float(sanity_count) * float(model.get("sanity_pressure_weight", 8.0))
	))
	var reward_tier := 1
	var thresholds = model.get("reward_tier_thresholds", [80, 150])
	if thresholds is Array:
		for threshold in thresholds:
			if strength >= int(threshold):
				reward_tier += 1
	return {
		"strength": strength,
		"reward_tier": reward_tier,
		"enemy_count": enemy_defs.size(),
		"total_hp": total_hp,
		"total_attack": total_attack,
		"sanity_pressure_count": sanity_count,
	}
