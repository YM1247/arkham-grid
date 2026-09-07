extends SceneTree

const RunPressureSimulatorScript = preload("res://scripts/run/run_pressure_simulator.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var content := ContentRegistry.new()
	if not content.load_all():
		push_error("內容資料驗證失敗：%s" % [content.errors])
		quit(1)
		return
	var simulator = RunPressureSimulatorScript.new()
	var report: Dictionary = simulator.simulate(content, {"runs": 10, "max_turns": 12})
	if report.has("error"):
		push_error(str(report.error))
		quit(1)
		return
	print("FULL RUN PRESSURE SIMULATION")
	print("- 固定種子：%d｜%d runs｜每場最多 %d turns" % [report.seed, report.runs, report.max_turns_per_battle])
	print("- 策略：%s" % report.policy)
	print("- 通關率：%.1f%%｜平均勝場／抵達戰鬥：%.2f/%.2f" % [
		100.0 * float(report.victory_rate),
		float(report.average_battles_won),
		float(report.average_battles_reached),
	])
	print("- HP/SAN/超時/無效 Run：%d/%d/%d/%d｜結束平均 HP/SAN：%.1f/%.1f" % [
		int(report.hp_defeats),
		int(report.sanity_defeats),
		int(report.timeouts),
		int(report.invalid_runs),
		float(report.average_hp_end),
		float(report.average_sanity_end),
	])
	print("- 平均獎勵／升級／特殊方塊：%.2f/%.2f/%.2f｜放置／死盤：%.1f/%.2f" % [
		float(report.average_rewards),
		float(report.average_upgrades),
		float(report.average_special_blocks),
		float(report.average_board_placements),
		float(report.average_dead_boards),
	])
	for point in report.pressure_curve:
		print("  戰鬥 %d｜抵達 %.1f%%｜抵達後勝率 %.1f%%｜戰後 HP/SAN %.1f/%.1f｜回合 %.2f" % [
			int(point.battle),
			100.0 * float(point.reached_rate),
			100.0 * float(point.win_rate_when_reached),
			float(point.average_hp_after),
			float(point.average_sanity_after),
			float(point.average_turns),
		])
	print("FULL RUN PRESSURE SIMULATION OK")
	quit(0)
