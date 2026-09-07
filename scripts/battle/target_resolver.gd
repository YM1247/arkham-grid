class_name TargetResolver
extends RefCounted


func resolve(scope: String, enemies: Array[Entity], selected_index: int) -> Array[Entity]:
	var living: Array[Entity] = []
	for enemy in enemies:
		if enemy != null and not enemy.is_dead:
			living.append(enemy)
	if scope == "all":
		return living
	if selected_index < 0 or selected_index >= enemies.size():
		return []
	var selected := enemies[selected_index]
	if selected == null or selected.is_dead:
		return []
	if scope == "spread":
		var living_index := living.find(selected)
		var targets: Array[Entity] = []
		for index in [living_index - 1, living_index, living_index + 1]:
			if index >= 0 and index < living.size():
				targets.append(living[index])
		return targets
	return [selected]
