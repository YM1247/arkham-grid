class_name BattleStatistics
extends RefCounted

var values: Dictionary = {}


func reset(encounter_id: String) -> void:
	values = {
		"encounter_id": encounter_id,
		"turns": 0,
		"rows_cleared": 0,
		"cols_cleared": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"damage_blocked": 0,
		"armor_gained": 0,
		"sanity_spent": 0,
		"sanity_loss_by_source": {},
		"sanity_defeat_source": "",
		"sanity_defeat_source_label": "",
		"mp_spent": 0,
		"spells_triggered": 0,
		"spells_paid_with_sanity": 0,
		"turn_limit": 0,
		"overdue_turns": 0,
		"time_pressure_sanity": 0,
		"spell_fizzles": 0,
		"dead_boards": 0,
		"reward_id": "",
	}


func add(key: String, amount: int = 1) -> void:
	values[key] = int(values.get(key, 0)) + amount


func snapshot() -> Dictionary:
	return values.duplicate(true)
