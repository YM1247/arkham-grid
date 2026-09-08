class_name BattleStartInput
extends Resource

@export var encounter_id: String = ""
@export var enemies: Array[Dictionary] = []
@export var intent_definitions: Dictionary = {}
@export var player_state: Dictionary = {}
@export var spell_pool_ids: Array[String] = []
@export var seed: int = 0


static func create(id: String, enemy_defs: Array, state: RunState, intents: Array = []) -> BattleStartInput:
	var input := BattleStartInput.new()
	input.encounter_id = id
	for enemy_def in enemy_defs:
		if enemy_def is Dictionary:
			input.enemies.append(enemy_def.duplicate(true))
	for intent in intents:
		if intent is Dictionary:
			input.intent_definitions[str(intent.get("id", ""))] = intent.duplicate(true)
	input.player_state = {"name": state.player_name, "hp": state.hp, "max_hp": state.max_hp, "sanity": state.sanity, "max_sanity": state.max_sanity, "mp": state.mp, "max_mp": state.max_mp, "action_points": state.action_points}
	input.spell_pool_ids = state.spell_pool_ids.duplicate()
	input.seed = state.seed
	return input
