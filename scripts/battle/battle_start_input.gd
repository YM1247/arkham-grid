class_name BattleStartInput
extends Resource

@export var encounter_id: String = ""
@export var enemies: Array[Dictionary] = []
@export var intent_definitions: Dictionary = {}
@export var player_state: Dictionary = {}
@export var spell_pool_ids: Array[String] = []
@export var seed: int = 0
@export var node_depth: int = 0
@export var turn_limit: int = 0
@export var time_pressure_sanity_base: int = 0
@export var time_pressure_sanity_growth: int = 0


static func create(id: String, enemy_defs: Array, state: RunState, intents: Array = [], difficulty: Dictionary = {}) -> BattleStartInput:
	var input := BattleStartInput.new()
	input.encounter_id = id
	for enemy_def in enemy_defs:
		if enemy_def is Dictionary:
			input.enemies.append(enemy_def.duplicate(true))
	for intent in intents:
		if intent is Dictionary:
			input.intent_definitions[str(intent.get("id", ""))] = intent.duplicate(true)
	input.player_state = {"name": state.player_name, "hp": state.hp, "max_hp": state.max_hp, "sanity": state.sanity, "max_sanity": state.max_sanity, "mp": state.mp, "max_mp": state.max_mp, "action_points": state.action_points}
	for slate in state.slate_pool:
		var spell_id := str(slate.get("spell_id", ""))
		if not spell_id.is_empty():
			input.spell_pool_ids.append(spell_id)
	input.seed = state.seed
	input.node_depth = maxi(int(difficulty.get("node_depth", 0)), 0)
	input.turn_limit = maxi(int(difficulty.get("turn_limit", 0)), 0)
	input.time_pressure_sanity_base = maxi(int(difficulty.get("time_pressure_sanity_base", 0)), 0)
	input.time_pressure_sanity_growth = maxi(int(difficulty.get("time_pressure_sanity_growth", 0)), 0)
	return input
