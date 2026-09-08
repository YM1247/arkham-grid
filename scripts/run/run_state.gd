class_name RunState
extends Resource

const SCHEMA_VERSION := 5

@export var seed: int = 0
@export var player_name: String = "調查員"
@export var profession_id: String = "investigator"
@export var hp: int = 80
@export var max_hp: int = 80
@export var sanity: int = 70
@export var max_sanity: int = 100
@export var mp: int = 70
@export var max_mp: int = 100
@export var action_points: int = 5
@export var board_cells: Array[String] = []
@export var board_spell_ids: Array[String] = []
@export var hand_ids: Array[String] = []
@export var hand_state: Array[Dictionary] = []
@export var block_pool_ids: Array[String] = []
@export var spell_pool_ids: Array[String] = []
@export var encounter_index: int = 0
@export var battles_won: int = 0
@export var selected_reward_ids: Array[String] = []
@export var currency: int = 0
@export var battle_reports: Array[Dictionary] = []
@export var flow_state: int = 0
@export var current_node_id: String = ""
@export var completed_node_ids: Array[String] = []
@export var available_node_ids: Array[String] = []
@export var map_data: Dictionary = {}
@export var sanity_effect_ids: Array[String] = []
@export var sanity_history: Array[Dictionary] = []
@export var reward_rng_state: String = "0"
@export var tablet_rng_state: String = "0"


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"seed": seed,
		"player": {"name": player_name, "profession_id": profession_id, "hp": hp, "max_hp": max_hp, "sanity": sanity, "max_sanity": max_sanity, "mp": mp, "max_mp": max_mp, "action_points": action_points},
		"board_cells": board_cells.duplicate(),
		"board_spell_ids": board_spell_ids.duplicate(),
		"hand_ids": hand_ids.duplicate(),
		"hand_state": hand_state.duplicate(true),
		"block_pool_ids": block_pool_ids.duplicate(),
		"spell_pool_ids": spell_pool_ids.duplicate(),
		"encounter_index": encounter_index,
		"battles_won": battles_won,
		"selected_reward_ids": selected_reward_ids.duplicate(),
		"currency": currency,
		"battle_reports": battle_reports.duplicate(true),
		"flow_state": flow_state,
		"current_node_id": current_node_id,
		"completed_node_ids": completed_node_ids.duplicate(),
		"available_node_ids": available_node_ids.duplicate(),
		"map_data": map_data.duplicate(true),
		"sanity_effect_ids": sanity_effect_ids.duplicate(),
		"sanity_history": sanity_history.duplicate(true),
		"rng_state": {"reward": reward_rng_state, "tablet": tablet_rng_state},
	}


static func from_dict(data: Dictionary) -> RunState:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		push_error("RunState schema_version 不支援：%s" % data.get("schema_version"))
		return null
	var state := RunState.new()
	var player: Dictionary = data.get("player", {})
	state.seed = int(data.get("seed", 0))
	state.player_name = str(player.get("name", "調查員"))
	state.profession_id = str(player.get("profession_id", "investigator"))
	state.hp = int(player.get("hp", 80))
	state.max_hp = int(player.get("max_hp", 80))
	state.sanity = int(player.get("sanity", 70))
	state.max_sanity = int(player.get("max_sanity", 100))
	state.mp = int(player.get("mp", 70))
	state.max_mp = int(player.get("max_mp", 100))
	state.action_points = int(player.get("action_points", 5))
	state.board_cells = _strings(data.get("board_cells", []))
	state.board_spell_ids = _strings(data.get("board_spell_ids", []))
	state.hand_ids = _strings(data.get("hand_ids", []))
	state.hand_state = _dictionaries(data.get("hand_state", []))
	state.block_pool_ids = _strings(data.get("block_pool_ids", []))
	state.spell_pool_ids = _strings(data.get("spell_pool_ids", []))
	state.encounter_index = int(data.get("encounter_index", 0))
	state.battles_won = int(data.get("battles_won", 0))
	state.selected_reward_ids = _strings(data.get("selected_reward_ids", []))
	state.currency = int(data.get("currency", 0))
	state.battle_reports = _dictionaries(data.get("battle_reports", []))
	state.flow_state = int(data.get("flow_state", 0))
	state.current_node_id = str(data.get("current_node_id", ""))
	state.completed_node_ids = _strings(data.get("completed_node_ids", []))
	state.available_node_ids = _strings(data.get("available_node_ids", []))
	if data.get("map_data", {}) is Dictionary:
		state.map_data = data.get("map_data", {}).duplicate(true)
	state.sanity_effect_ids = _strings(data.get("sanity_effect_ids", []))
	state.sanity_history = _dictionaries(data.get("sanity_history", []))
	var rng_state: Dictionary = data.get("rng_state", {})
	state.reward_rng_state = str(rng_state.get("reward", "0"))
	state.tablet_rng_state = str(rng_state.get("tablet", "0"))
	return state


static func _strings(values) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value in values:
			result.append(str(value))
	return result


static func _string_int_dictionary(values) -> Dictionary:
	var result := {}
	if values is Dictionary:
		for key in values:
			result[str(key)] = int(values[key])
	return result


static func _dictionaries(values) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if values is Array:
		for value in values:
			if value is Dictionary:
				result.append(value.duplicate(true))
	return result
