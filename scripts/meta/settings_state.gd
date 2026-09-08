class_name SettingsState
extends Resource

const SCHEMA_VERSION := 1
const SUPPORTED_LOCALES := ["zh_TW", "en"]

@export var locale := "zh_TW"
@export var fullscreen := false
@export var master_volume := 1.0
@export var music_volume := 1.0
@export var sfx_volume := 1.0
@export var anonymous_telemetry := false


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"locale": locale,
		"fullscreen": fullscreen,
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"anonymous_telemetry": anonymous_telemetry,
	}


static func from_dict(data: Dictionary) -> SettingsState:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := SettingsState.new()
	state.locale = str(data.get("locale", "zh_TW"))
	state.fullscreen = bool(data.get("fullscreen", false))
	state.master_volume = float(data.get("master_volume", 1.0))
	state.music_volume = float(data.get("music_volume", 1.0))
	state.sfx_volume = float(data.get("sfx_volume", 1.0))
	state.anonymous_telemetry = bool(data.get("anonymous_telemetry", false))
	return state
