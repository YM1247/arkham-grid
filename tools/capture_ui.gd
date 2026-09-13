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
	var run_manager := main.get_node("RunManager") as RunManager
	if mode in ["battle", "reward"] and run_manager != null and not run_manager.run_state.available_node_ids.is_empty():
		run_manager.select_map_node(run_manager.run_state.available_node_ids[0])
		for _frame in range(3):
			await process_frame
		if mode == "reward":
			run_manager._show_reward_choices()
			await process_frame
	elif mode == "settlement" and run_manager != null:
		run_manager._finish_run(false, "UI 預覽")
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(output_path)
	if result == OK:
		print("UI CAPTURE OK: %s" % output_path)
		quit(0)
	else:
		push_error("UI CAPTURE FAILED: %d" % result)
		quit(1)
