class_name EnemyIntentExecutor
extends RefCounted


func execute(intent: Dictionary, actor: Entity, player: Entity) -> Dictionary:
	if actor == null or actor.is_dead or player == null:
		return {"executed": false}
	var action := str(intent.get("action", ""))
	match action:
		"damage":
			var base_damage := int(actor.get_meta("attack_damage", 0))
			var amount := roundi(base_damage * float(intent.get("multiplier", 1.0))) + int(intent.get("flat_bonus", 0))
			amount = actor.modify_attack_damage(amount)
			return {"executed": true, "amount": player.take_damage(amount), "action": action}
		"armor":
			var amount := actor.modify_armor_gain(int(intent.get("amount", 0)))
			return {"executed": true, "amount": actor.add_armor(amount), "action": action}
		"sanity_damage":
			var source := "enemy_intent:%s" % str(intent.get("id", "unknown"))
			return {"executed": true, "amount": player.spend_sanity(int(intent.get("amount", 0)), source), "action": action}
		"status_player":
			player.add_status(str(intent.get("status_id", "")), int(intent.get("amount", 0)))
			return {"executed": true, "action": action}
		"status_self":
			actor.add_status(str(intent.get("status_id", "")), int(intent.get("amount", 0)))
			return {"executed": true, "action": action}
		_:
			push_error("未知敵人意圖 action：%s" % action)
			return {"executed": false, "action": action}
