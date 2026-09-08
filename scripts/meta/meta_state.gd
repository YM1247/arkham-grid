class_name MetaState
extends Resource

const SCHEMA_VERSION := 1

@export var shared_currency := 0
@export var unlocked_profession_ids: Array[String] = []
@export var unlocked_block_ids: Array[String] = []
@export var unlocked_spell_ids: Array[String] = []
@export var achievement_ids: Array[String] = []
@export var runs_started := 0
@export var runs_completed := 0


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"shared_currency": shared_currency,
		"unlocked_profession_ids": unlocked_profession_ids.duplicate(),
		"unlocked_block_ids": unlocked_block_ids.duplicate(),
		"unlocked_spell_ids": unlocked_spell_ids.duplicate(),
		"achievement_ids": achievement_ids.duplicate(),
		"runs_started": runs_started,
		"runs_completed": runs_completed,
	}


func unlock_profession(id: String) -> bool:
	return _unlock(id, unlocked_profession_ids)


func unlock_block(id: String) -> bool:
	return _unlock(id, unlocked_block_ids)


func unlock_spell(id: String) -> bool:
	return _unlock(id, unlocked_spell_ids)


func is_content_unlocked(kind: String, id: String) -> bool:
	match kind:
		"profession": return id in unlocked_profession_ids
		"block": return id in unlocked_block_ids
		"spell": return id in unlocked_spell_ids
	return false


static func from_dict(data: Dictionary) -> MetaState:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := MetaState.new()
	state.shared_currency = int(data.get("shared_currency", 0))
	state.unlocked_profession_ids = _strings(data.get("unlocked_profession_ids", []))
	state.unlocked_block_ids = _strings(data.get("unlocked_block_ids", []))
	state.unlocked_spell_ids = _strings(data.get("unlocked_spell_ids", []))
	state.achievement_ids = _strings(data.get("achievement_ids", []))
	state.runs_started = int(data.get("runs_started", 0))
	state.runs_completed = int(data.get("runs_completed", 0))
	return state


static func from_defaults(config: Dictionary) -> MetaState:
	return from_dict({
		"schema_version": SCHEMA_VERSION,
		"shared_currency": int(config.get("initial_shared_currency", 0)),
		"unlocked_profession_ids": config.get("initial_unlocked_profession_ids", []),
		"unlocked_block_ids": config.get("initial_unlocked_block_ids", []),
		"unlocked_spell_ids": config.get("initial_unlocked_spell_ids", []),
		"achievement_ids": [],
		"runs_started": 0,
		"runs_completed": 0,
	})


func _unlock(id: String, target: Array[String]) -> bool:
	if id.is_empty() or id in target:
		return false
	target.append(id)
	return true


static func _strings(values) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value in values:
			result.append(str(value))
	return result
