class_name SystemMenu
extends Control

const UIMotionScript = preload("res://scripts/ui/ui_motion.gd")

signal resume_requested
signal new_run_requested
signal settings_applied(values: Dictionary)

@onready var heading: Label = $Background/Center/Panel/VBox/Heading
@onready var navigation: VBoxContainer = $Background/Center/Panel/VBox/Navigation
@onready var continue_button: Button = $Background/Center/Panel/VBox/Navigation/Continue
@onready var new_run_button: Button = $Background/Center/Panel/VBox/Navigation/NewRun
@onready var settings_button: Button = $Background/Center/Panel/VBox/Navigation/Settings
@onready var settings_panel: VBoxContainer = $Background/Center/Panel/VBox/SettingsPanel
@onready var locale_option: OptionButton = $Background/Center/Panel/VBox/SettingsPanel/Locale
@onready var fullscreen_toggle: CheckButton = $Background/Center/Panel/VBox/SettingsPanel/Fullscreen
@onready var master_slider: HSlider = $Background/Center/Panel/VBox/SettingsPanel/Master
@onready var music_slider: HSlider = $Background/Center/Panel/VBox/SettingsPanel/Music
@onready var sfx_slider: HSlider = $Background/Center/Panel/VBox/SettingsPanel/SFX

var _is_pause_menu := false
var _confirming_new_run := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.pressed.connect(_resume)
	new_run_button.pressed.connect(_request_new_run)
	settings_button.pressed.connect(_show_settings)
	$Background/Center/Panel/VBox/SettingsPanel/Apply.pressed.connect(_apply_settings)
	$Background/Center/Panel/VBox/SettingsPanel/Back.pressed.connect(_show_navigation)
	locale_option.add_item("繁體中文", 0)
	locale_option.add_item("English（文字準備中）", 1)
	locale_option.set_item_disabled(1, true)


func show_title(settings: SettingsState) -> void:
	_is_pause_menu = false
	heading.text = "ARKHAM GRID"
	continue_button.text = "繼續本次調查"
	_load_settings(settings)
	_show_navigation()
	visible = true
	UIMotionScript.fade_in(self, "emphasis")
	if continue_button.is_inside_tree():
		continue_button.grab_focus()


func show_pause(settings: SettingsState) -> void:
	_is_pause_menu = true
	heading.text = "調查暫停"
	continue_button.text = "返回遊戲"
	_load_settings(settings)
	_show_navigation()
	visible = true
	UIMotionScript.fade_in(self, "fast")
	if continue_button.is_inside_tree():
		continue_button.grab_focus()


func hide_menu() -> void:
	visible = false


func is_pause_menu() -> bool:
	return _is_pause_menu


func _resume() -> void:
	visible = false
	resume_requested.emit()


func _show_settings() -> void:
	navigation.visible = false
	settings_panel.visible = true
	locale_option.grab_focus()


func _show_navigation() -> void:
	_confirming_new_run = false
	new_run_button.text = "開始新的調查"
	navigation.visible = true
	settings_panel.visible = false


func _request_new_run() -> void:
	if not _confirming_new_run:
		_confirming_new_run = true
		new_run_button.text = "再次確認：放棄目前進度"
		new_run_button.grab_focus()
		return
	new_run_requested.emit()


func _load_settings(settings: SettingsState) -> void:
	if settings == null:
		return
	locale_option.select(1 if settings.locale == "en" else 0)
	fullscreen_toggle.button_pressed = settings.fullscreen
	master_slider.value = settings.master_volume * 100.0
	music_slider.value = settings.music_volume * 100.0
	sfx_slider.value = settings.sfx_volume * 100.0


func _apply_settings() -> void:
	settings_applied.emit({
		"locale": "en" if locale_option.selected == 1 else "zh_TW",
		"fullscreen": fullscreen_toggle.button_pressed,
		"master_volume": master_slider.value / 100.0,
		"music_volume": music_slider.value / 100.0,
		"sfx_volume": sfx_slider.value / 100.0,
	})
	_show_navigation()
	continue_button.grab_focus()
