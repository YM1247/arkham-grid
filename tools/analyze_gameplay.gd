extends SceneTree

const RunPressureSimulatorScript = preload("res://scripts/run/run_pressure_simulator.gd")
const BattleBatchSimulatorScript = preload("res://scripts/battle/battle_batch_simulator.gd")

const SEEDS := [424242, 13579, 8675309, 20260908, 314159]
const RUNS_PER_SEED := 8
const BATTLES_PER_ENCOUNTER := 6
const MAX_TURNS := 12


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var content := ContentRegistry.new()
	if not content.load_all():
		push_error("內容資料驗證失敗：%s" % [content.errors])
		quit(1)
		return
	var run_simulator = RunPressureSimulatorScript.new()
	var battle_simulator = BattleBatchSimulatorScript.new()
	var enemy_index: Dictionary = content.indexes.get("enemies", {})
	var intent_index: Dictionary = content.indexes.get("intents", {})
	var config := content.get_document("run_config")
	var totals := {
		"runs": 0, "victories": 0.0, "hp_defeats": 0, "sanity_defeats": 0, "timeouts": 0,
		"hp": 0.0, "sanity": 0.0, "mp": 0.0, "battles": 0.0, "special_blocks": 0.0, "dead_boards": 0.0,
		"time_pressure_sanity": 0.0, "overdue_turns": 0.0,
	}
	print("MULTI-SEED FULL RUN ANALYSIS")
	for seed in SEEDS:
		var report: Dictionary = run_simulator.simulate(content, {"seed": seed, "runs": RUNS_PER_SEED, "max_turns": MAX_TURNS})
		print("seed=%d runs=%d win=%.1f%% hp/san/timeout=%d/%d/%d avg_hp/san/mp=%.1f/%.1f/%.1f battles=%.2f special=%.2f dead=%.2f" % [
			seed, RUNS_PER_SEED, 100.0 * float(report.victory_rate), report.hp_defeats, report.sanity_defeats, report.timeouts,
			report.average_hp_end, report.average_sanity_end, report.average_mp_end, report.average_battles_won,
			report.average_special_blocks, report.average_dead_boards,
		])
		totals.runs += RUNS_PER_SEED
		totals.victories += float(report.victory_rate) * RUNS_PER_SEED
		for key in ["hp_defeats", "sanity_defeats", "timeouts"]:
			totals[key] += int(report[key])
		totals.hp += float(report.average_hp_end) * RUNS_PER_SEED
		totals.sanity += float(report.average_sanity_end) * RUNS_PER_SEED
		totals.mp += float(report.average_mp_end) * RUNS_PER_SEED
		totals.battles += float(report.average_battles_won) * RUNS_PER_SEED
		totals.special_blocks += float(report.average_special_blocks) * RUNS_PER_SEED
		totals.dead_boards += float(report.average_dead_boards) * RUNS_PER_SEED
		totals.time_pressure_sanity += float(report.average_time_pressure_sanity) * RUNS_PER_SEED
		totals.overdue_turns += float(report.average_overdue_turns) * RUNS_PER_SEED
	print("aggregate runs=%d win=%.1f%% hp/san/timeout=%d/%d/%d avg_hp/san/mp=%.1f/%.1f/%.1f battles=%.2f special=%.2f dead=%.2f" % [
		totals.runs, 100.0 * totals.victories / totals.runs, totals.hp_defeats, totals.sanity_defeats, totals.timeouts,
		totals.hp / totals.runs, totals.sanity / totals.runs, totals.mp / totals.runs, totals.battles / totals.runs,
		totals.special_blocks / totals.runs, totals.dead_boards / totals.runs,
	])
	print("aggregate time_pressure_sanity=%.2f overdue_turns=%.2f" % [
		totals.time_pressure_sanity / totals.runs,
		totals.overdue_turns / totals.runs,
	])
	print("MULTI-SEED ENCOUNTER ANALYSIS")
	for seed in SEEDS:
		var report: Dictionary = battle_simulator.simulate(
			content.get_entries("encounters"), enemy_index, intent_index, content.get_document("player"),
			content.get_spells(config.get("spell_pool", [])), content.get_blocks(config.get("block_pool", [])),
			config.get("board_growth_rules", {}), content.get_document("sanity"),
			{"seed": seed, "battles": BATTLES_PER_ENCOUNTER, "max_turns": MAX_TURNS, "difficulty_model": config.get("difficulty_model", {})}
		)
		var parts: Array[String] = []
		for encounter in report.encounters:
			parts.append("%s %.0f%% %.1ft HP%.1f SAN%.1f alt%.1f" % [
				encounter.encounter_id, 100.0 * encounter.win_rate, encounter.average_turns,
				encounter.average_player_hp_end, encounter.average_player_sanity_end,
				encounter.average_spells_paid_with_sanity,
			])
		print("seed=%d | %s" % [seed, " | ".join(parts)])
	print("MULTI-SEED GAMEPLAY ANALYSIS OK")
	quit(0)
