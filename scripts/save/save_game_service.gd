class_name SaveGameService
extends RefCounted

const SAVE_SCHEMA_VERSION := 1
const DEFAULT_DIRECTORY := "user://saves"
const RUN_FILE := "run_autosave.json"
const BACKUP_SUFFIX := ".backup"
const TEMP_SUFFIX := ".tmp"
const CHECKPOINTS := ["manual", "legacy", "new_run", "node_entered", "node_completed", "run_finished", "migrated"]

var directory: String
var last_error := ""
var last_rejected_path := ""


func _init(save_directory: String = DEFAULT_DIRECTORY) -> void:
	directory = save_directory.trim_suffix("/")


func save_run(state: RunState, checkpoint: String = "manual", content_versions: Dictionary = {}) -> bool:
	last_error = ""
	if state == null:
		return _fail("無法保存空的 RunState。")
	if checkpoint not in CHECKPOINTS:
		return _fail("未知的存檔 checkpoint：%s" % checkpoint)
	var payload := state.to_dict()
	var structure_errors := validate_run_state_payload(payload)
	if not structure_errors.is_empty():
		return _fail("RunState 結構無效：%s" % "; ".join(structure_errors))
	var envelope := {
		"save_schema_version": SAVE_SCHEMA_VERSION,
		"kind": "run_autosave",
		"checkpoint": checkpoint,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"content_versions": content_versions.duplicate(true),
		"run_state": payload,
	}
	return _write_atomically(_run_path(), envelope)


func load_run() -> Dictionary:
	last_error = ""
	var primary := _load_path(_run_path(), "primary")
	if bool(primary.get("ok", false)):
		return primary
	var primary_error := str(primary.get("error", "主存檔無效。"))
	var backup := _load_path(_backup_path(), "backup")
	if bool(backup.get("ok", false)):
		backup["recovered_from_error"] = primary_error
		return backup
	last_error = "%s；備份亦不可用：%s" % [primary_error, backup.get("error", "不存在")]
	return {"ok": false, "error": last_error}


func load_backup_run() -> Dictionary:
	last_error = ""
	var result := _load_path(_backup_path(), "backup")
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "備份不可用。"))
	return result


func has_run_save() -> bool:
	return FileAccess.file_exists(_run_path()) or FileAccess.file_exists(_backup_path())


func get_run_path() -> String:
	return _run_path()


func get_backup_path() -> String:
	return _backup_path()


func get_temp_path() -> String:
	return _temp_path()


func recover_primary_from_backup() -> bool:
	last_error = ""
	last_rejected_path = ""
	var backup := _load_path(_backup_path(), "backup")
	if not bool(backup.get("ok", false)):
		return _fail("無法從備份修復主存檔：%s" % backup.get("error", "備份無效"))
	var absolute_primary := ProjectSettings.globalize_path(_run_path())
	var absolute_temp := ProjectSettings.globalize_path(_temp_path())
	if FileAccess.file_exists(_temp_path()):
		DirAccess.remove_absolute(absolute_temp)
	if FileAccess.file_exists(_run_path()):
		last_rejected_path = "%s.rejected-%d-%d" % [_run_path(), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		var quarantine_error := DirAccess.rename_absolute(absolute_primary, ProjectSettings.globalize_path(last_rejected_path))
		if quarantine_error != OK:
			last_rejected_path = ""
			return _fail("無法隔離損壞主存檔（錯誤 %d）。" % quarantine_error)
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(_backup_path()), absolute_temp)
	if copy_error != OK:
		_restore_rejected_primary(absolute_primary)
		return _fail("無法複製備份（錯誤 %d）。" % copy_error)
	var verification := _load_path(_temp_path(), "recovery")
	if not bool(verification.get("ok", false)):
		DirAccess.remove_absolute(absolute_temp)
		_restore_rejected_primary(absolute_primary)
		return _fail("備份修復驗證失敗：%s" % verification.get("error", "未知錯誤"))
	var promote_error := DirAccess.rename_absolute(absolute_temp, absolute_primary)
	if promote_error != OK:
		_restore_rejected_primary(absolute_primary)
		return _fail("無法將備份提升為主存檔（錯誤 %d）。" % promote_error)
	return true


func validate_run_state_payload(payload: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _is_integer_value(payload.get("schema_version")) or int(payload.get("schema_version")) != RunState.SCHEMA_VERSION:
		errors.append("schema_version 必須為 %d" % RunState.SCHEMA_VERSION)
	var player = payload.get("player")
	if not player is Dictionary:
		errors.append("player 必須是物件")
	else:
		_validate_player(player, errors)
	for key in ["board_cells", "hand_ids", "hand_state", "block_pool_ids", "row_item_ids", "col_item_ids", "selected_reward_ids", "battle_reports", "completed_node_ids", "available_node_ids", "sanity_effect_ids", "sanity_history"]:
		if not payload.get(key) is Array:
			errors.append("%s 必須是陣列" % key)
	for key in ["item_inventory", "map_data", "rng_state"]:
		if not payload.get(key) is Dictionary:
			errors.append("%s 必須是物件" % key)
	if payload.get("board_cells") is Array:
		var board: Array = payload.get("board_cells")
		if not board.is_empty() and board.size() != 64:
			errors.append("board_cells 必須為空或正好 64 格")
		for cell in board:
			if not cell is String:
				errors.append("board_cells 只能包含字串")
				break
			if not cell.is_empty() and not Color.html_is_valid(cell):
				errors.append("board_cells 包含無效色碼")
				break
	_validate_string_array(payload, "hand_ids", errors)
	_validate_string_array(payload, "block_pool_ids", errors)
	_validate_string_array(payload, "row_item_ids", errors)
	_validate_string_array(payload, "col_item_ids", errors)
	_validate_string_array(payload, "selected_reward_ids", errors)
	_validate_string_array(payload, "completed_node_ids", errors)
	_validate_string_array(payload, "available_node_ids", errors)
	_validate_string_array(payload, "sanity_effect_ids", errors)
	for key in ["seed", "encounter_index", "battles_won", "currency", "flow_state"]:
		if not _is_integer_value(payload.get(key)):
			errors.append("%s 必須是整數" % key)
	for key in ["encounter_index", "battles_won", "currency"]:
		if _is_integer_value(payload.get(key)) and int(payload.get(key)) < 0:
			errors.append("%s 不可小於 0" % key)
	if _is_integer_value(payload.get("flow_state")):
		var flow_state := int(payload.get("flow_state"))
		if flow_state < 0 or flow_state > 6:
			errors.append("flow_state 超出已知狀態範圍")
	if _is_integer_value(payload.get("seed")) and absf(float(payload.get("seed"))) > 9007199254740991.0:
		errors.append("seed 超出 JSON 可安全保存的整數範圍")
	if not payload.get("current_node_id") is String:
		errors.append("current_node_id 必須是字串")
	if payload.get("rng_state") is Dictionary:
		var states: Dictionary = payload.get("rng_state")
		for key in ["reward", "tablet"]:
			if not states.get(key) is String or str(states.get(key)).is_empty() or not str(states.get(key)).is_valid_int():
				errors.append("rng_state.%s 必須是可解析的整數字串" % key)
	if payload.get("hand_state") is Array:
		for entry in payload.get("hand_state"):
			if not entry is Dictionary or not entry.get("id") is String or not _is_integer_value(entry.get("rotation_steps")):
				errors.append("hand_state 項目必須包含字串 id 與整數 rotation_steps")
				break
			var rotation := int(entry.get("rotation_steps"))
			if rotation < 0 or rotation > 3:
				errors.append("hand_state.rotation_steps 必須介於 0 到 3")
				break
	if payload.get("hand_ids") is Array and payload.get("hand_state") is Array:
		var hand_ids: Array = payload.get("hand_ids")
		var hand_state: Array = payload.get("hand_state")
		if hand_ids.size() != hand_state.size():
			errors.append("hand_ids 與 hand_state 數量必須一致")
		else:
			for index in range(hand_ids.size()):
				if hand_state[index] is Dictionary and str(hand_ids[index]) != str(hand_state[index].get("id", "")):
					errors.append("hand_ids 與 hand_state 順序必須一致")
					break
	_validate_dictionary_array(payload, "battle_reports", errors)
	_validate_dictionary_array(payload, "sanity_history", errors)
	if payload.get("item_inventory") is Dictionary:
		for key in payload.get("item_inventory"):
			var amount = payload.get("item_inventory")[key]
			if not key is String or not _is_integer_value(amount) or int(amount) < 0:
				errors.append("item_inventory 必須是字串 ID 對非負整數數量")
				break
	if _is_integer_value(payload.get("flow_state")) and player is Dictionary:
		var state := int(payload.get("flow_state"))
		if state != 6 and (_is_integer_value(player.get("hp")) and int(player.get("hp")) <= 0 or _is_integer_value(player.get("sanity")) and int(player.get("sanity")) <= 0):
			errors.append("只有 DEFEAT 存檔可包含歸零的 HP 或 Sanity")
	return errors


func _load_path(path: String, source: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s 存檔不存在" % source}
	var document_result := _read_document(path)
	if not bool(document_result.get("ok", false)):
		return document_result
	var migration := _migrate_document(document_result.get("data", {}))
	if not bool(migration.get("ok", false)):
		return migration
	var payload: Dictionary = migration.get("run_state", {})
	var structure_errors := validate_run_state_payload(payload)
	if not structure_errors.is_empty():
		return {"ok": false, "error": "%s 結構無效：%s" % [source, "; ".join(structure_errors)]}
	var state := RunState.from_dict(payload)
	if state == null:
		return {"ok": false, "error": "%s 無法建立 RunState" % source}
	return {
		"ok": true,
		"state": state,
		"source": source,
		"checkpoint": str(migration.get("checkpoint", "legacy")),
		"migrated": bool(migration.get("migrated", false)),
	}


func _migrate_document(document) -> Dictionary:
	if not document is Dictionary:
		return {"ok": false, "error": "存檔根節點必須是物件"}
	var envelope: Dictionary = document.duplicate(true)
	var migrated := false
	if not envelope.has("save_schema_version"):
		if not envelope.has("schema_version"):
			return {"ok": false, "error": "缺少存檔版本"}
		envelope = {
			"save_schema_version": SAVE_SCHEMA_VERSION,
			"kind": "run_autosave",
			"checkpoint": "legacy",
			"run_state": envelope,
		}
		migrated = true
	if not _is_integer_value(envelope.get("save_schema_version")):
		return {"ok": false, "error": "save_schema_version 必須是整數"}
	var save_version := int(envelope.get("save_schema_version"))
	if save_version != SAVE_SCHEMA_VERSION:
		return {"ok": false, "error": "不支援的存檔版本：%d" % save_version}
	if str(envelope.get("kind", "")) != "run_autosave" or not envelope.get("run_state") is Dictionary:
		return {"ok": false, "error": "存檔類型或 run_state payload 無效"}
	if not envelope.get("checkpoint") is String or str(envelope.get("checkpoint")) not in CHECKPOINTS:
		return {"ok": false, "error": "存檔 checkpoint 無效"}
	if not _is_integer_value(envelope.get("saved_at_unix", 0)) or int(envelope.get("saved_at_unix", 0)) < 0:
		return {"ok": false, "error": "saved_at_unix 必須是非負整數"}
	if not envelope.get("content_versions", {}) is Dictionary:
		return {"ok": false, "error": "content_versions 必須是物件"}
	for key in envelope.get("content_versions", {}):
		if not key is String or not _is_integer_value(envelope.get("content_versions")[key]) or int(envelope.get("content_versions")[key]) < 1:
			return {"ok": false, "error": "content_versions 必須是內容名稱對正整數版本"}
	var run_migration := _migrate_run_state(envelope.get("run_state"))
	if not bool(run_migration.get("ok", false)):
		return run_migration
	return {
		"ok": true,
		"run_state": run_migration.get("data", {}),
		"checkpoint": str(envelope.get("checkpoint", "legacy")),
		"migrated": migrated or bool(run_migration.get("migrated", false)),
	}


func _migrate_run_state(raw: Dictionary) -> Dictionary:
	var data := raw.duplicate(true)
	if not _is_integer_value(data.get("schema_version")):
		return {"ok": false, "error": "RunState 缺少有效 schema_version"}
	var version := int(data.get("schema_version"))
	if version < 1 or version > RunState.SCHEMA_VERSION:
		return {"ok": false, "error": "不支援的 RunState 版本：%d" % version}
	var migrated := false
	while version < RunState.SCHEMA_VERSION:
		match version:
			1:
				if not data.get("hand_state") is Array:
					var migrated_hand: Array[Dictionary] = []
					for hand_id in data.get("hand_ids", []):
						migrated_hand.append({"id": str(hand_id), "rotation_steps": 0})
					data["hand_state"] = migrated_hand
				data["item_inventory"] = data.get("item_inventory", {})
				data["currency"] = data.get("currency", 0)
				data["battle_reports"] = data.get("battle_reports", [])
				data["flow_state"] = data.get("flow_state", 0)
				data["current_node_id"] = data.get("current_node_id", "")
				data["completed_node_ids"] = data.get("completed_node_ids", [])
				data["available_node_ids"] = data.get("available_node_ids", [])
				data["map_data"] = data.get("map_data", {})
				version = 2
			2:
				if not data.get("hand_state") is Array:
					var migrated_hand: Array[Dictionary] = []
					for hand_id in data.get("hand_ids", []):
						migrated_hand.append({"id": str(hand_id), "rotation_steps": 0})
					data["hand_state"] = migrated_hand
				data["sanity_effect_ids"] = data.get("sanity_effect_ids", [])
				data["sanity_history"] = data.get("sanity_history", [])
				version = 3
			3:
				var seed := int(data.get("seed", 0))
				var reward_rng := RandomNumberGenerator.new()
				reward_rng.seed = seed
				var tablet_rng := RandomNumberGenerator.new()
				tablet_rng.seed = seed ^ 0x41C64E6D
				data["rng_state"] = {"reward": str(reward_rng.state), "tablet": str(tablet_rng.state)}
				version = 4
			_:
				return {"ok": false, "error": "缺少 RunState %d 的遷移器" % version}
		data["schema_version"] = version
		migrated = true
	return {"ok": true, "data": data, "migrated": migrated}


func _write_atomically(path: String, document: Dictionary) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _fail("無法建立存檔目錄（錯誤 %d）。" % directory_error)
	var temp_path := _temp_path()
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("無法開啟暫存檔（錯誤 %d）。" % FileAccess.get_open_error())
	file.store_string(JSON.stringify(document, "\t", true, true))
	file.flush()
	file = null
	var verification := _load_path(temp_path, "temp")
	if not bool(verification.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _fail("暫存檔驗證失敗：%s" % verification.get("error", "未知錯誤"))
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_backup := ProjectSettings.globalize_path(_backup_path())
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var moved_primary := false
	if FileAccess.file_exists(path):
		var current_document := _load_path(path, "current")
		if bool(current_document.get("ok", false)):
			if FileAccess.file_exists(_backup_path()):
				var remove_backup_error := DirAccess.remove_absolute(absolute_backup)
				if remove_backup_error != OK:
					DirAccess.remove_absolute(absolute_temp)
					return _fail("無法移除舊備份（錯誤 %d）。" % remove_backup_error)
			var backup_error := DirAccess.rename_absolute(absolute_path, absolute_backup)
			if backup_error != OK:
				DirAccess.remove_absolute(absolute_temp)
				return _fail("無法輪替主存檔至備份（錯誤 %d）。" % backup_error)
			moved_primary = true
		else:
			DirAccess.remove_absolute(absolute_temp)
			return _fail("現有主存檔無效，為避免覆寫而拒絕保存：%s" % current_document.get("error", "未知錯誤"))
	var promote_error := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if promote_error != OK:
		if moved_primary:
			var rollback_error := DirAccess.rename_absolute(absolute_backup, absolute_path)
			if rollback_error != OK:
				return _fail("無法提升暫存檔（錯誤 %d），且主存檔回復失敗（錯誤 %d）；有效資料仍保留於備份。" % [promote_error, rollback_error])
		return _fail("無法將暫存檔提升為主存檔（錯誤 %d）。" % promote_error)
	return true


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "無法讀取 %s（錯誤 %d）" % [path, FileAccess.get_open_error()]}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return {"ok": false, "error": "JSON 第 %d 行解析失敗：%s" % [parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Dictionary:
		return {"ok": false, "error": "JSON 根節點必須是物件"}
	return {"ok": true, "data": parser.data}


func _validate_player(player: Dictionary, errors: Array[String]) -> void:
	if not player.get("name") is String or str(player.get("name")).is_empty():
		errors.append("player.name 必須是非空字串")
	for key in ["hp", "max_hp", "sanity", "max_sanity", "action_points"]:
		if not _is_integer_value(player.get(key)):
			errors.append("player.%s 必須是整數" % key)
	if not errors.is_empty():
		return
	var hp := int(player.get("hp"))
	var max_hp := int(player.get("max_hp"))
	var sanity := int(player.get("sanity"))
	var max_sanity := int(player.get("max_sanity"))
	if max_hp <= 0 or hp < 0 or hp > max_hp:
		errors.append("player.hp/max_hp 範圍無效")
	if max_sanity <= 0 or sanity < 0 or sanity > max_sanity:
		errors.append("player.sanity/max_sanity 範圍無效")
	if int(player.get("action_points")) <= 0:
		errors.append("player.action_points 必須大於 0")


func _validate_string_array(payload: Dictionary, key: String, errors: Array[String]) -> void:
	var value = payload.get(key)
	if not value is Array:
		return
	for entry in value:
		if not entry is String:
			errors.append("%s 只能包含字串" % key)
			return


func _validate_dictionary_array(payload: Dictionary, key: String, errors: Array[String]) -> void:
	var value = payload.get(key)
	if not value is Array:
		return
	for entry in value:
		if not entry is Dictionary:
			errors.append("%s 只能包含物件" % key)
			return


func _is_integer_value(value) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))


func _restore_rejected_primary(absolute_primary: String) -> void:
	if last_rejected_path.is_empty() or FileAccess.file_exists(_run_path()):
		return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(last_rejected_path), absolute_primary)


func _run_path() -> String:
	return "%s/%s" % [directory, RUN_FILE]


func _backup_path() -> String:
	return _run_path() + BACKUP_SUFFIX


func _temp_path() -> String:
	return _run_path() + TEMP_SUFFIX


func _fail(message: String) -> bool:
	last_error = message
	return false
