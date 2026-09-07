extends SceneTree

const BoardSimulatorScript = preload("res://scripts/board/board_simulator.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := ContentRegistry.new()
	if not registry.load_all():
		push_error("內容資料驗證失敗：%s" % [registry.errors])
		quit(1)
		return
	var run_config := registry.get_document("run_config")
	var block_pool := registry.get_blocks(run_config.get("block_pool", []))
	var board_rules: Dictionary = run_config.get("board_growth_rules", {})
	var player: Dictionary = registry.get_document("player")
	var options := {
		"seed": int(run_config.get("seed", 424242)),
		"runs": 10,
		"placements_per_run": 30,
		"hand_size": 3,
		"action_points": int(player.get("action_points", 5)),
	}
	var simulator = BoardSimulatorScript.new()
	print("BOARD / HAND SIMULATION")
	print("- 固定種子：%d｜每模式 %d runs × %d placements" % [options.seed, options.runs, options.placements_per_run])
	for mode in [BoardSimulatorScript.SMART_MODE, BoardSimulatorScript.RANDOM_MODE]:
		options.mode = mode
		var report: Dictionary = simulator.simulate(block_pool, board_rules, options)
		if report.has("error"):
			push_error(str(report.error))
			quit(1)
			return
		_print_report(report)
	print("BOARD / HAND SIMULATION OK")
	quit(0)


func _print_report(report: Dictionary) -> void:
	print("- %s" % report.mode)
	print("  完成率：%.2f%%｜合法手牌率：%.2f%%｜合法卡片率：%.2f%%" % [
		100.0 * float(report.completion_rate),
		100.0 * float(report.legal_hand_rate),
		100.0 * float(report.legal_card_rate),
	])
	print("  直接消線率：%.2f%%｜每次放置消線：%.3f" % [
		100.0 * float(report.direct_clear_rate),
		float(report.lines_per_placement),
	])
	print("  平均佔用率：%.2f%%｜最高佔用率：%.2f%%｜每百次放置死盤：%.2f（%d 次）" % [
		100.0 * float(report.average_occupancy_rate),
		100.0 * float(report.maximum_occupancy_rate),
		float(report.dead_boards_per_100_placements),
		int(report.dead_boards),
	])
