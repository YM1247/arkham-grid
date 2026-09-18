extends Node

const UIMotionScript = preload("res://scripts/ui/ui_motion.gd")

@onready var run_manager: RunManager = $RunManager
@onready var system_menu: SystemMenu = $UILayer/SystemMenu
@onready var menu_button: Button = $UILayer/ScreenMargin/Screen/TopBar/MenuButton


func _ready() -> void:
	_apply_ui_theme()
	_ensure_input_actions()
	menu_button.pressed.connect(_toggle_pause_menu)
	system_menu.resume_requested.connect(_resume_game)
	system_menu.new_run_requested.connect(_start_new_run)
	system_menu.settings_applied.connect(_apply_settings)
	system_menu.show_title(run_manager.settings_state)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()


func _on_tablet_section_col_activated(col_index: int) -> void:
	$BattleManager.execute_col_effect(col_index)


func _on_tablet_section_row_activated(row_index: int) -> void:
	$BattleManager.execute_row_effect(row_index)


func _apply_ui_theme() -> void:
	var document := run_manager.content.get_document("ui_theme")
	if document.is_empty():
		return
	var ui_theme := UIThemeFactory.build(document)
	UIMotionScript.configure(document)
	for child in $UILayer.get_children():
		if child is Control:
			child.theme = ui_theme
	var background := $UILayer/BG
	if background is ColorRect:
		background.color = UIThemeFactory.color(document, "background", Color("080b12"))


func _toggle_pause_menu() -> void:
	if system_menu.visible:
		_resume_game()
		return
	get_tree().paused = true
	system_menu.show_pause(run_manager.settings_state)


func _resume_game() -> void:
	get_tree().paused = false
	UIMotionScript.fade_out(system_menu, Callable(system_menu, "hide_menu"), "emphasis")


func _start_new_run() -> void:
	get_tree().paused = false
	run_manager.start_new_run()
	UIMotionScript.fade_out(system_menu, Callable(system_menu, "hide_menu"), "emphasis")


func _apply_settings(values: Dictionary) -> void:
	var settings := run_manager.settings_state
	settings.locale = str(values.get("locale", settings.locale))
	settings.fullscreen = bool(values.get("fullscreen", settings.fullscreen))
	settings.master_volume = float(values.get("master_volume", settings.master_volume))
	settings.music_volume = float(values.get("music_volume", settings.music_volume))
	settings.sfx_volume = float(values.get("sfx_volume", settings.sfx_volume))
	if not run_manager.save_settings():
		push_warning("設定儲存失敗")


func _ensure_input_actions() -> void:
	var actions := {
		"hand_slot_1": KEY_1,
		"hand_slot_2": KEY_2,
		"hand_slot_3": KEY_3,
		"board_left": KEY_A,
		"board_right": KEY_D,
		"board_up": KEY_W,
		"board_down": KEY_S,
		"place_selected": KEY_SPACE,
		"cancel_selection": KEY_X,
		"end_turn": KEY_ENTER,
		"toggle_pause": KEY_ESCAPE,
	}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var has_key := false
		for input_event in InputMap.action_get_events(action):
			if input_event is InputEventKey and input_event.physical_keycode == actions[action]:
				has_key = true
				break
		if not has_key:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = actions[action]
			InputMap.action_add_event(action, key_event)
