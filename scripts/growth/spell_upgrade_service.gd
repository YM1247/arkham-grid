class_name SpellUpgradeService
extends RefCounted


func add_to_collection(spell_id: String, collection: Dictionary, definitions: Dictionary) -> Dictionary:
	collection[spell_id] = int(collection.get(spell_id, 0)) + 1
	var current_id := spell_id
	var upgrades: Array[String] = []
	while true:
		var definition: Dictionary = definitions.get(current_id, {})
		var next_id := str(definition.get("upgrade_to", ""))
		var combine_count := int(definition.get("combine_count", 0))
		if next_id.is_empty() or combine_count <= 1 or int(collection.get(current_id, 0)) < combine_count:
			break
		collection[current_id] = int(collection.get(current_id, 0)) - combine_count
		collection[next_id] = int(collection.get(next_id, 0)) + 1
		upgrades.append(next_id)
		current_id = next_id
	return {"spell_id": current_id, "upgrades": upgrades, "collection": collection}
