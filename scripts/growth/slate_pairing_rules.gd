class_name SlatePairingRules
extends RefCounted


func spell_strength(spell: Dictionary) -> int:
	var cost := int(spell.get("balance_cost", 0))
	if cost <= 9:
		return 1
	if cost <= 13:
		return 2
	return 3


func is_allowed(shape: Dictionary, spell: Dictionary) -> bool:
	var shape_id := str(shape.get("id", ""))
	var allowed = spell.get("allowed_shape_ids", [])
	var blocked = spell.get("blocked_shape_ids", [])
	if blocked is Array and shape_id in blocked:
		return false
	if allowed is Array and not allowed.is_empty():
		return shape_id in allowed
	return int(shape.get("complexity", 1)) >= spell_strength(spell)


func pairing_weight(shape: Dictionary, spell: Dictionary) -> float:
	if not is_allowed(shape, spell):
		return 0.0
	var distance := absf(float(shape.get("complexity", 1)) - float(spell_strength(spell)))
	return maxf(float(shape.get("weight", 1.0)), 0.01) / (1.0 + distance)
