extends SceneTree

const DifficultyCalculator = preload("res://scripts/growth/encounter_difficulty_calculator.gd")


func _init() -> void:
	var content := ContentRegistry.new()
	if not content.load_all():
		for error in content.errors:
			push_error(error)
		quit(1)
		return
	var calculator = DifficultyCalculator.new()
	var model: Dictionary = content.get_document("run_config").get("difficulty_model", {})
	print("encounter_id\tstrength\treward_tier\tenemies\ttotal_hp\ttotal_attack\tsanity_enemies")
	for encounter in content.get_entries("encounters"):
		var enemy_defs: Array = []
		for enemy_id in encounter.get("enemy_ids", []):
			enemy_defs.append(content.get_definition("enemies", str(enemy_id)))
		var metrics := calculator.calculate(enemy_defs, model)
		print("%s\t%d\t%d\t%d\t%d\t%d\t%d" % [
			encounter.get("id", ""), metrics.strength, metrics.reward_tier,
			metrics.enemy_count, metrics.total_hp, metrics.total_attack,
			metrics.sanity_pressure_count,
		])
	quit(0)
