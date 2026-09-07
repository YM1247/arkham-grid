extends BattleItem
class_name EffectStatus

func execute(target: Node, user: Node):
	if user == null or not bool(user.get_meta("simulation_quiet", false)):
		print("   ✦ [", item_name, "] 發動！(類型:", ItemType.keys()[item_type], ")")
	if user != null and user.has_method("apply_status_effects") and not status_effects_self.is_empty():
		user.apply_status_effects(status_effects_self)
	if target != null and target.has_method("apply_status_effects") and not status_effects_target.is_empty():
		target.apply_status_effects(status_effects_target)
