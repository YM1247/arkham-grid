class_name BattleEffectContext
extends RefCounted

var user: Entity
var primary_target: Entity
var targets: Array[Entity] = []
var trigger_axis: String = ""
var trigger_index: int = -1
var weapon_trigger_count: int = 0
var trigger_history: Array[Dictionary] = []
var battle_state: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"trigger_axis": trigger_axis,
		"trigger_index": trigger_index,
		"weapon_trigger_count": weapon_trigger_count,
		"trigger_history": trigger_history.duplicate(true),
		"battle_state": battle_state.duplicate(true),
	}
