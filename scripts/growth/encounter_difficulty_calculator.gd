class_name EncounterDifficultyCalculator
extends RefCounted


func calculate(enemy_defs: Array, model: Dictionary, context: Dictionary = {}) -> Dictionary:
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
	var result := {
		"strength": strength,
		"reward_tier": reward_tier,
		"enemy_count": enemy_defs.size(),
		"total_hp": total_hp,
		"total_attack": total_attack,
		"sanity_pressure_count": sanity_count,
	}
	var time_pressure: Dictionary = model.get("time_pressure", {})
	if bool(time_pressure.get("enabled", false)):
		var strength_step := maxi(int(time_pressure.get("strength_per_bonus_turn", 45)), 1)
		var depth_interval := maxi(int(time_pressure.get("depth_penalty_interval", 3)), 1)
		var node_depth := maxi(int(context.get("node_depth", 0)), 0)
		var depth_penalty := floori(float(node_depth) / float(depth_interval))
		var turn_limit := int(time_pressure.get("base_turns", 3)) + ceili(float(strength) / float(strength_step)) - depth_penalty
		turn_limit = clampi(
			turn_limit,
			maxi(int(time_pressure.get("minimum_turn_limit", 4)), 1),
			maxi(int(time_pressure.get("maximum_turn_limit", 7)), 1)
		)
		result.merge({
			"node_depth": node_depth,
			"turn_limit": turn_limit,
			"time_pressure_sanity_base": maxi(int(time_pressure.get("sanity_loss_base", 2)), 0),
			"time_pressure_sanity_growth": maxi(int(time_pressure.get("sanity_loss_growth", 2)), 0),
		}, true)
	return result
