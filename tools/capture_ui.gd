extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var arguments := OS.get_cmdline_user_args()
	var mode := str(arguments[0]) if arguments.size() > 0 else "map"
	var output_path := str(arguments[1]) if arguments.size() > 1 else "/tmp/arkham-grid-ui-%s.png" % mode
	ProjectSettings.set_setting("arkham_grid/testing/save_directory", "/tmp/arkham_grid_ui_capture_%d" % Time.get_ticks_usec())
	var scene := load("res://main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	for _frame in range(4):
		await process_frame
	var system_menu := main.get_node_or_null("UILayer/SystemMenu")
	if system_menu != null and mode != "title":
		system_menu.hide_menu()
		paused = false
	var run_manager := main.get_node("RunManager") as RunManager
	if mode in ["battle", "battle_action", "battle_armor", "battle_status", "battle_preview", "battle_dead_board", "reward"] and run_manager != null and not run_manager.run_state.available_node_ids.is_empty():
		run_manager.select_map_node(run_manager.run_state.available_node_ids[0])
		for _frame in range(3):
			await process_frame
		if mode in ["battle", "battle_action", "battle_armor", "battle_status", "battle_preview", "battle_dead_board"]:
			var battle_manager := main.get_node("BattleManager")
			battle_manager.start_encounter(run_manager.enemies.slice(0, 5))
			for _frame in range(3):
				await process_frame
			if mode == "battle_armor":
				battle_manager.player.add_armor(14)
				if not battle_manager.enemies.is_empty():
					battle_manager.enemies[0].add_armor(8)
				battle_manager._update_all_status_labels()
				await process_frame
			if mode == "battle_status":
				battle_manager.player.add_status("strength", 2)
				battle_manager.player.add_status("poison", 3)
				if not battle_manager.enemies.is_empty():
					battle_manager.enemies[0].add_status("weak", 2)
					battle_manager.enemies[0].add_status("fragile", 1)
				battle_manager._update_all_status_labels()
				await process_frame
			if mode == "battle_action":
				battle_manager.end_player_turn()
				await create_timer(0.72).timeout
			if mode == "battle_preview":
				battle_manager._on_payment_preview_changed([
					run_manager.content.get_spell("pistol"),
					run_manager.content.get_spell("vest"),
				])
			if mode == "battle_dead_board":
				var tablet = battle_manager.tablet
				tablet._play_dead_board_warning()
				# 下方共用穩定等待會再走 0.35 秒，此處只補一幀以擷取掃描波峰。
				await create_timer(0.03).timeout
		if mode == "reward":
			run_manager._show_reward_choices()
			await process_frame
	elif mode == "build" and run_manager != null:
		run_manager._show_build_pool()
		await process_frame
	elif mode == "settlement" and run_manager != null:
		run_manager._finish_run(false, "UI 預覽")
		await process_frame
	await create_timer(0.35).timeout
	for _frame in range(2):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(output_path)
	if result == OK:
		print("UI CAPTURE OK: %s" % output_path)
		if mode == "battle_dead_board":
			await create_timer(0.45).timeout
		main.queue_free()
		await process_frame
		await process_frame
		quit(0)
	else:
		push_error("UI CAPTURE FAILED: %d" % result)
		quit(1)
