class_name MadnessEffect
extends Resource

enum Behavior {
	SPELL_MP_COST,
	DEAD_BOARD_PENALTY,
	ATTACK_MODIFIER,
	ARMOR_GAIN_MODIFIER,
}

@export var behavior: Behavior = Behavior.SPELL_MP_COST


func apply_to_entity(definition: Dictionary, entity: Entity) -> void:
	if entity == null:
		return
	var amount := int(definition.get("amount", 0))
	match behavior:
		Behavior.ATTACK_MODIFIER:
			entity.set_meta("madness_attack_modifier", int(entity.get_meta("madness_attack_modifier", 0)) + amount)
		Behavior.ARMOR_GAIN_MODIFIER:
			entity.set_meta("madness_armor_modifier", int(entity.get_meta("madness_armor_modifier", 0)) + amount)


func modify_spell_mp_cost(definition: Dictionary, value: int) -> int:
	return maxi(value + int(definition.get("amount", 0)), 0) if behavior == Behavior.SPELL_MP_COST else value


func modify_dead_board_penalty(definition: Dictionary, value: int) -> int:
	return maxi(value + int(definition.get("amount", 0)), 0) if behavior == Behavior.DEAD_BOARD_PENALTY else value
