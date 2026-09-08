extends BattleItem
class_name EffectSupport

@export_group("支援參數")
@export var armor_gain: int = 0
@export var heal_amount: int = 0

func execute(target: Node, user: Node):
	var quiet := user != null and bool(user.get_meta("simulation_quiet", false))
	if not quiet:
		print("   ✦ 咒文 [", spell_name, "] 發動！")
	
	if user:
		if armor_gain > 0:
			if user.has_method("add_armor"):
				var final_armor_gain = armor_gain
				if user.has_method("modify_armor_gain"):
					final_armor_gain = user.modify_armor_gain(final_armor_gain)
				var gained_armor = user.add_armor(final_armor_gain)
				if not quiet:
					print("       -> 玩家獲得 ", gained_armor, " 點護甲")
			else:
				if not quiet:
					print("       -> 使用者沒有 add_armor()，無法獲得護甲")
		if heal_amount > 0:
			if user.has_method("heal"):
				var healed_amount = user.heal(heal_amount)
				if not quiet:
					print("       -> 玩家回復 ", healed_amount, " 生命")
			else:
				if not quiet:
					print("       -> 使用者沒有 heal()，無法回復生命")
		if user.has_method("apply_status_effects") and not status_effects_self.is_empty():
			user.apply_status_effects(status_effects_self)
	if target != null and target.has_method("apply_status_effects") and not status_effects_target.is_empty():
		target.apply_status_effects(status_effects_target)
