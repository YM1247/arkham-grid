class_name EffectConditionalAttack
extends EffectAttack


func execute_with_context(target: Node, user: Node, context: BattleEffectContext = null) -> void:
	var condition_met := context != null and context.spell_trigger_count > 0
	var original_damage := damage
	if condition_met and bonus_damage > 0:
		damage = bonus_damage
	execute(target, user)
	damage = original_damage
