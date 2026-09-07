class_name EnemyFactory
extends RefCounted


func create(enemy_def: Dictionary, template: Entity, parent: Node, index: int) -> Entity:
	var instance := template if index == 0 else Entity.new()
	if index > 0:
		instance.name = "Enemy%d" % (index + 1)
		parent.add_child(instance)
	instance.reset_entity(str(enemy_def.get("name", "未知敵人")), int(enemy_def.get("hp", 1)))
	instance.set_meta("content_id", str(enemy_def.get("id", "")))
	instance.set_meta("attack_damage", int(enemy_def.get("attack", 0)))
	instance.set_meta("tier", int(enemy_def.get("tier", 1)))
	instance.set_meta("speed", int(enemy_def.get("speed", 0)))
	instance.set_meta("spawn_index", index)
	var intent_state := EnemyIntentState.new()
	intent_state.configure(enemy_def.get("intent_pattern", ["attack"]))
	instance.set_meta("intent_state", intent_state)
	return instance
