class_name BattleResult
extends Resource

enum Outcome { VICTORY, DEFEAT }

@export var outcome: Outcome = Outcome.DEFEAT
@export var reason: String = ""
@export var encounter_id: String = ""
@export var player_state: Dictionary = {}
@export var statistics: Dictionary = {}


static func create(won: bool, result_reason: String, id: String, state: Dictionary, stats: Dictionary = {}) -> BattleResult:
	var result := BattleResult.new()
	result.outcome = Outcome.VICTORY if won else Outcome.DEFEAT
	result.reason = result_reason
	result.encounter_id = id
	result.player_state = state.duplicate(true)
	result.statistics = stats.duplicate(true)
	return result
