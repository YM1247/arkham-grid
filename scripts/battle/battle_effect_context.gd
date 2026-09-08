class_name BattleEffectContext
extends RefCounted

var user: Entity
var primary_target: Entity
var targets: Array[Entity] = []
var effect_cell: Vector2i = Vector2i(-1, -1)
var spell_trigger_count: int = 0
var trigger_history: Array[Dictionary] = []
var battle_state: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"effect_cell": [effect_cell.x, effect_cell.y],
		"spell_trigger_count": spell_trigger_count,
		"trigger_history": trigger_history.duplicate(true),
		"battle_state": battle_state.duplicate(true),
	}
