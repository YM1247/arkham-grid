class_name BattleOutcomeResolver
extends RefCounted

enum Outcome { NONE, VICTORY, HP_DEFEAT, SANITY_DEFEAT }


func resolve(player: Entity, enemies: Array[Entity]) -> Outcome:
	if player != null and player.max_sanity > 0 and player.sanity <= 0:
		return Outcome.SANITY_DEFEAT
	if player != null and player.is_dead:
		return Outcome.HP_DEFEAT
	if not enemies.is_empty():
		var all_dead := true
		for enemy in enemies:
			if enemy != null and not enemy.is_dead:
				all_dead = false
				break
		if all_dead:
			return Outcome.VICTORY
	return Outcome.NONE
