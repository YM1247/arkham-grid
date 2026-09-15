class_name BattleStageView
extends Control

const PLAYER_ART := "res://assets/art/characters/investigator_chibi_opaque.png"

@onready var player_art: TextureRect = $PlayerArt
@onready var player_name_label: Label = $PlayerName
@onready var combat_log: Label = $ActionLog

var _recent_entries: Array[String] = []
var _idle_tween: Tween


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(PLAYER_ART):
		player_art.texture = load(PLAYER_ART)
	_refresh_log()
	_start_idle_motion()


func begin_encounter(player_name: String) -> void:
	player_name_label.text = player_name
	_recent_entries.clear()
	_refresh_log()


func present_enemy_windup(enemy_name: String, intent_name: String) -> void:
	combat_log.text = "%s　%s" % [enemy_name, intent_name]
	var tween := create_tween()
	tween.tween_property(combat_log, "modulate", Color("f6d889"), 0.08)
	tween.tween_property(combat_log, "modulate", Color.WHITE, 0.18)
	await get_tree().create_timer(0.22).timeout


func present_enemy_resolution(enemy_name: String, intent_name: String, result_text: String, harms_player: bool) -> void:
	_append_log("%s｜%s｜%s" % [enemy_name, intent_name, result_text])
	if harms_player:
		var base_x := player_art.position.x
		var tween := create_tween()
		tween.tween_property(player_art, "modulate", Color("ff8a8a"), 0.06)
		tween.tween_property(player_art, "position:x", base_x - 5.0, 0.05)
		tween.tween_property(player_art, "position:x", base_x + 5.0, 0.05)
		tween.tween_property(player_art, "position:x", base_x, 0.05)
		tween.tween_property(player_art, "modulate", Color.WHITE, 0.14)
		await tween.finished
	else:
		await get_tree().create_timer(0.18).timeout


func finish_enemy_action() -> void:
	await get_tree().create_timer(0.14).timeout


func _append_log(entry: String) -> void:
	_recent_entries.push_front(entry)
	if _recent_entries.size() > 4:
		_recent_entries.resize(4)
	_refresh_log()


func _refresh_log() -> void:
	combat_log.text = "尚無行動紀錄" if _recent_entries.is_empty() else "\n".join(_recent_entries)


func _start_idle_motion() -> void:
	if _idle_tween != null:
		_idle_tween.kill()
	player_art.pivot_offset = player_art.size * 0.5
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(player_art, "scale", Vector2(1.012, 0.992), 1.4).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(player_art, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE)
