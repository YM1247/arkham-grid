class_name MetaState
extends Resource

const SCHEMA_VERSION := 2

@export var shared_currency := 0
@export var unlocked_profession_ids: Array[String] = []
@export var unlocked_block_ids: Array[String] = []
@export var unlocked_spell_ids: Array[String] = []
@export var achievement_ids: Array[String] = []
@export var runs_started := 0
@export var runs_completed := 0
@export var run_history: Array[Dictionary] = []


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
		"run_history": run_history.duplicate(true),
	}


func record_run(summary: Dictionary, maximum_entries: int = 20) -> void:
	var normalized := {
		"seed": int(summary.get("seed", 0)),
		"victory": bool(summary.get("victory", false)),
		"reason": str(summary.get("reason", "")),
		"completed_nodes": maxi(int(summary.get("completed_nodes", 0)), 0),
		"battles_won": maxi(int(summary.get("battles_won", 0)), 0),
		"currency": maxi(int(summary.get("currency", 0)), 0),
		"hp": maxi(int(summary.get("hp", 0)), 0),
		"sanity": maxi(int(summary.get("sanity", 0)), 0),
		"mp": maxi(int(summary.get("mp", 0)), 0),
		"finished_at_unix": maxi(int(summary.get("finished_at_unix", Time.get_unix_time_from_system())), 0),
	}
	run_history.append(normalized)
	var overflow := run_history.size() - maxi(maximum_entries, 1)
	for _index in range(maxi(overflow, 0)):
		run_history.pop_front()


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
	state.run_history = _dictionaries(data.get("run_history", []))
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
		"run_history": [],
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


static func _dictionaries(values) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if values is Array:
		for value in values:
			if value is Dictionary:
				result.append(value.duplicate(true))
	return result
