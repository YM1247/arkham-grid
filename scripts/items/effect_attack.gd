extends BattleItem
class_name EffectAttack

@export_group("攻擊參數")
@export var damage: int = 10
@export var bonus_damage: int = 0
@export var hit_count: int = 1 # 攻擊段數

func execute(target: Node, user: Node):
	var quiet := user != null and bool(user.get_meta("simulation_quiet", false))
	if not quiet:
		print("   ✦ 咒文 [", spell_name, "] 發動！")
	
	if target:
		for i in range(hit_count):
			if target.has_method("take_damage"):
				var attack_damage = damage
				if user != null and user.has_method("modify_attack_damage"):
					attack_damage = user.modify_attack_damage(attack_damage)
				var final_damage = target.take_damage(attack_damage)
				if not quiet:
					print("       -> 對敵人造成 ", final_damage, " 點傷害")
			else:
				if not quiet:
					print("       -> 目標沒有 take_damage()，無法造成傷害")
	if user != null and user.has_method("apply_status_effects") and not status_effects_self.is_empty():
		user.apply_status_effects(status_effects_self)
	if target != null and target.has_method("apply_status_effects") and not status_effects_target.is_empty():
		target.apply_status_effects(status_effects_target)
