class_name AudioManager
extends Node

@export var music_player_path: NodePath
@export var sfx_player_path: NodePath

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var cue_streams: Dictionary = {}


func _ready() -> void:
	music_player = get_node_or_null(music_player_path) as AudioStreamPlayer
	sfx_player = get_node_or_null(sfx_player_path) as AudioStreamPlayer


func register_cue(cue_id: String, stream: AudioStream) -> void:
	if not cue_id.is_empty() and stream != null:
		cue_streams[cue_id] = stream


func play_cue(cue_id: String) -> void:
	if sfx_player == null or not cue_streams.has(cue_id):
		return
	sfx_player.stream = cue_streams[cue_id]
	sfx_player.play()


func play_music(stream: AudioStream, fade_seconds: float = 0.25) -> void:
	if music_player == null or stream == null:
		return
	music_player.stream = stream
	music_player.volume_db = -24.0 if fade_seconds > 0.0 else 0.0
	music_player.play()
	if fade_seconds > 0.0:
		create_tween().tween_property(music_player, "volume_db", 0.0, fade_seconds)


func stop_music(fade_seconds: float = 0.25) -> void:
	if music_player == null or not music_player.playing:
		return
	if fade_seconds <= 0.0:
		music_player.stop()
		return
	var tween := create_tween()
	tween.tween_property(music_player, "volume_db", -24.0, fade_seconds)
	tween.tween_callback(music_player.stop)
