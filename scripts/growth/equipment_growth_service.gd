class_name EquipmentGrowthService
extends RefCounted


func add_to_inventory(item_id: String, inventory: Dictionary, definitions: Dictionary) -> Dictionary:
	inventory[item_id] = int(inventory.get(item_id, 0)) + 1
	var current_id := item_id
	var upgrades: Array[String] = []
	while true:
		var definition: Dictionary = definitions.get(current_id, {})
		var next_id := str(definition.get("upgrade_to", ""))
		var combine_count := int(definition.get("combine_count", 0))
		if next_id.is_empty() or combine_count <= 1 or int(inventory.get(current_id, 0)) < combine_count:
			break
		inventory[current_id] = int(inventory.get(current_id, 0)) - combine_count
		inventory[next_id] = int(inventory.get(next_id, 0)) + 1
		upgrades.append(next_id)
		current_id = next_id
	return {"item_id": current_id, "upgrades": upgrades, "inventory": inventory}
