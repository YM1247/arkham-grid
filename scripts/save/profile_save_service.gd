class_name ProfileSaveService
extends RefCounted

const PROFILE_SAVE_SCHEMA_VERSION := 1
const DEFAULT_DIRECTORY := "user://saves"
const SETTINGS_FILE := "settings.json"
const META_FILE := "meta_progress.json"
const BACKUP_SUFFIX := ".backup"
const TEMP_SUFFIX := ".tmp"

var directory: String
var last_error := ""


func _init(save_directory: String = DEFAULT_DIRECTORY) -> void:
	directory = save_directory.trim_suffix("/")


func save_settings(state: SettingsState) -> bool:
	if state == null:
		return _fail("無法保存空的 SettingsState。")
	return _save("settings", state.to_dict())


func save_meta(state: MetaState) -> bool:
	if state == null:
		return _fail("無法保存空的 MetaState。")
	return _save("meta", state.to_dict())


func load_settings() -> Dictionary:
	return _load_with_backup("settings")


func load_meta() -> Dictionary:
	return _load_with_backup("meta")


func get_primary_path(kind: String) -> String:
	return "%s/%s" % [directory, SETTINGS_FILE if kind == "settings" else META_FILE]


func get_backup_path(kind: String) -> String:
	return get_primary_path(kind) + BACKUP_SUFFIX


func get_temp_path(kind: String) -> String:
	return get_primary_path(kind) + TEMP_SUFFIX


func validate_settings_payload(payload: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _is_integer(payload.get("schema_version")) or int(payload.get("schema_version")) != SettingsState.SCHEMA_VERSION:
		errors.append("settings.schema_version 必須為 %d" % SettingsState.SCHEMA_VERSION)
	if not payload.get("locale") is String or str(payload.get("locale")) not in SettingsState.SUPPORTED_LOCALES:
		errors.append("settings.locale 不在支援清單")
	for key in ["fullscreen", "anonymous_telemetry"]:
		if not payload.get(key) is bool:
			errors.append("settings.%s 必須是布林值" % key)
	for key in ["master_volume", "music_volume", "sfx_volume"]:
		var value = payload.get(key)
		if not _is_number(value) or float(value) < 0.0 or float(value) > 1.0:
			errors.append("settings.%s 必須介於 0 與 1" % key)
	return errors


func validate_meta_payload(payload: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _is_integer(payload.get("schema_version")) or int(payload.get("schema_version")) != MetaState.SCHEMA_VERSION:
		errors.append("meta.schema_version 必須為 %d" % MetaState.SCHEMA_VERSION)
	for key in ["shared_currency", "runs_started", "runs_completed"]:
		if not _is_integer(payload.get(key)) or int(payload.get(key, -1)) < 0:
			errors.append("meta.%s 必須是非負整數" % key)
	for key in ["unlocked_profession_ids", "unlocked_block_ids", "unlocked_spell_ids", "achievement_ids"]:
		_validate_unique_string_array(payload, key, errors)
	if payload.get("unlocked_profession_ids") is Array and payload.get("unlocked_profession_ids").is_empty():
		errors.append("meta.unlocked_profession_ids 不可為空")
	return errors


func _save(kind: String, payload: Dictionary) -> bool:
	last_error = ""
	var errors := _validate_payload(kind, payload)
	if not errors.is_empty():
		return _fail("%s 結構無效：%s" % [kind, "; ".join(errors)])
	var envelope := {
		"profile_save_schema_version": PROFILE_SAVE_SCHEMA_VERSION,
		"kind": kind,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"payload": payload,
	}
	return _write_atomically(kind, envelope)


func _load_with_backup(kind: String) -> Dictionary:
	last_error = ""
	var primary := _load_path(get_primary_path(kind), kind, "primary")
	if bool(primary.get("ok", false)):
		return primary
	var primary_error := str(primary.get("error", "主檔無效"))
	var backup := _load_path(get_backup_path(kind), kind, "backup")
	if bool(backup.get("ok", false)):
		backup["recovered_from_error"] = primary_error
		return backup
	last_error = "%s；備份亦不可用：%s" % [primary_error, backup.get("error", "不存在")]
	return {"ok": false, "error": last_error}


func _load_path(path: String, expected_kind: String, source: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s %s 檔不存在" % [source, expected_kind]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "無法讀取 %s" % path}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "%s JSON 無效" % source}
	var migration := _migrate_document(parser.data, expected_kind)
	if not bool(migration.get("ok", false)):
		return migration
	var payload: Dictionary = migration.get("payload", {})
	var errors := _validate_payload(expected_kind, payload)
	if not errors.is_empty():
		return {"ok": false, "error": "%s 結構無效：%s" % [source, "; ".join(errors)]}
	var state = SettingsState.from_dict(payload) if expected_kind == "settings" else MetaState.from_dict(payload)
	if state == null:
		return {"ok": false, "error": "%s 無法建立狀態" % source}
	return {"ok": true, "state": state, "source": source, "migrated": bool(migration.get("migrated", false))}


func _migrate_document(document: Dictionary, expected_kind: String) -> Dictionary:
	var envelope := document.duplicate(true)
	var migrated := false
	if not envelope.has("profile_save_schema_version"):
		if not envelope.has("schema_version"):
			return {"ok": false, "error": "缺少 profile 存檔版本"}
		envelope = {
			"profile_save_schema_version": PROFILE_SAVE_SCHEMA_VERSION,
			"kind": expected_kind,
			"saved_at_unix": 0,
			"payload": envelope,
		}
		migrated = true
	if not _is_integer(envelope.get("profile_save_schema_version")) or int(envelope.get("profile_save_schema_version")) != PROFILE_SAVE_SCHEMA_VERSION:
		return {"ok": false, "error": "不支援的 profile 存檔版本"}
	if str(envelope.get("kind", "")) != expected_kind or not envelope.get("payload") is Dictionary:
		return {"ok": false, "error": "profile 存檔類型或 payload 無效"}
	if not _is_integer(envelope.get("saved_at_unix", 0)) or int(envelope.get("saved_at_unix", 0)) < 0:
		return {"ok": false, "error": "saved_at_unix 必須是非負整數"}
	return {"ok": true, "payload": envelope.get("payload", {}).duplicate(true), "migrated": migrated}


func _write_atomically(kind: String, envelope: Dictionary) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _fail("無法建立 profile 目錄（錯誤 %d）" % directory_error)
	var temp_path := get_temp_path(kind)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("無法開啟 profile 暫存檔")
	file.store_string(JSON.stringify(envelope, "\t", true, true))
	file.flush()
	file = null
	var verification := _load_path(temp_path, kind, "temp")
	if not bool(verification.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _fail("profile 暫存檔驗證失敗：%s" % verification.get("error", "未知錯誤"))
	var primary_path := get_primary_path(kind)
	var backup_path := get_backup_path(kind)
	if FileAccess.file_exists(primary_path):
		var current := _load_path(primary_path, kind, "current")
		if not bool(current.get("ok", false)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
			return _fail("現有 %s 主檔無效，拒絕覆寫" % kind)
		if FileAccess.file_exists(backup_path):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
			if remove_error != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
				return _fail("無法移除舊 profile 備份")
		var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(primary_path), ProjectSettings.globalize_path(backup_path))
		if backup_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
			return _fail("無法輪替 profile 備份")
	var promote_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(primary_path))
	if promote_error != OK:
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(primary_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(primary_path))
		return _fail("無法提升 profile 暫存檔")
	return true


func _validate_payload(kind: String, payload: Dictionary) -> Array[String]:
	return validate_settings_payload(payload) if kind == "settings" else validate_meta_payload(payload)


func _validate_unique_string_array(payload: Dictionary, key: String, errors: Array[String]) -> void:
	var value = payload.get(key)
	if not value is Array:
		errors.append("meta.%s 必須是陣列" % key)
		return
	var seen := {}
	for entry in value:
		if not entry is String or str(entry).is_empty() or seen.has(str(entry)):
			errors.append("meta.%s 只能包含唯一非空字串" % key)
			return
		seen[str(entry)] = true


func _is_integer(value) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)


func _is_number(value) -> bool:
	return value is int or value is float and is_finite(value)


func _fail(message: String) -> bool:
	last_error = message
	return false
