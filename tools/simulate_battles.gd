extends SceneTree

const BattleBatchSimulatorScript = preload("res://scripts/battle/battle_batch_simulator.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := ContentRegistry.new()
	if not registry.load_all():
		push_error("內容資料驗證失敗：%s" % [registry.errors])
		quit(1)
		return
	var run_config := registry.get_document("run_config")
	var enemy_index := {}
	for enemy in registry.get_entries("enemies"):
		enemy_index[str(enemy.get("id", ""))] = enemy
	var intent_index := {}
	for intent in registry.get_entries("intents"):
		intent_index[str(intent.get("id", ""))] = intent
	var simulator = BattleBatchSimulatorScript.new()
	var report: Dictionary = simulator.simulate(
		registry.get_entries("encounters"),
		enemy_index,
		intent_index,
		registry.get_document("player"),
		registry.get_spells(run_config.get("spell_pool", [])),
		registry.get_blocks(run_config.get("block_pool", [])),
		run_config.get("board_growth_rules", {}),
		registry.get_document("sanity"),
		{"seed": int(run_config.get("seed", 424242)), "battles": 10, "max_turns": 12}
	)
	if report.has("error"):
		push_error(str(report.error))
		quit(1)
		return
	print("HEADLESS BATTLE BATCH")
	print("- 固定種子：%d｜每遭遇 %d battles｜最多 %d turns" % [report.seed, report.battles_per_encounter, report.max_turns])
	print("- 策略：%s" % report.policy)
	for encounter in report.encounters:
		print("- %s %s" % [encounter.encounter_id, encounter.name])
		print("  勝率：%.1f%%｜平均回合：%.2f｜HP/SAN/MP 結束：%.1f/%.1f/%.1f｜HP/SAN 敗：%d/%d｜超時：%d" % [
			100.0 * float(encounter.win_rate),
			float(encounter.average_turns),
			float(encounter.average_player_hp_end),
			float(encounter.average_player_sanity_end),
			float(encounter.average_player_mp_end),
			int(encounter.hp_defeats),
			int(encounter.sanity_defeats),
			int(encounter.timeouts),
		])
		print("  咒文觸發／Sanity 代付／失敗／MP 消耗：%.1f/%.1f/%.1f/%.1f" % [
			float(encounter.average_spells_triggered),
			float(encounter.average_spells_paid_with_sanity),
			float(encounter.average_spell_fizzles),
			float(encounter.average_mp_spent),
		])
		print("  傷害 dealt/taken/blocked：%.1f/%.1f/%.1f｜護甲：%.1f｜Sanity 消耗：%.1f" % [
			float(encounter.average_damage_dealt),
			float(encounter.average_damage_taken),
			float(encounter.average_damage_blocked),
			float(encounter.average_armor_gained),
			float(encounter.average_sanity_spent),
		])
		print("  Row/Col/死盤：%.2f/%.2f/%.2f｜敵人存活曲線：%s" % [
			float(encounter.average_rows_cleared),
			float(encounter.average_cols_cleared),
			float(encounter.average_dead_boards),
			_format_curve(encounter.enemy_survival_curve),
		])
	print("HEADLESS BATTLE BATCH OK")
	quit(0)


func _format_curve(curve: Array) -> String:
	var values: Array[String] = []
	for value in curve:
		values.append("%.1f" % float(value))
	return "[" + ", ".join(values) + "]"
