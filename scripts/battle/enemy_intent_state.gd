class_name EnemyIntentState
extends RefCounted

var pattern: Array[String] = []
var rules: Array[Dictionary] = []
var current_index: int = 0


func configure(intent_pattern: Array, start_index: int = 0, intent_rules: Array = []) -> void:
	pattern.clear()
	for intent_id in intent_pattern:
		pattern.append(str(intent_id))
	current_index = maxi(start_index, 0)
	rules.clear()
	for value in intent_rules:
		if not value is Dictionary:
			continue
		var rule: Dictionary = value.duplicate(true)
		var rule_pattern: Array[String] = []
		for intent_id in rule.get("pattern", []):
			rule_pattern.append(str(intent_id))
		rule["pattern"] = rule_pattern
		rules.append(rule)


func current_intent_id(current_hp: int = -1, max_hp: int = -1, battle_turn: int = 1) -> String:
	var active_pattern := _select_pattern(current_hp, max_hp, battle_turn)
	if active_pattern.is_empty():
		return ""
	return active_pattern[current_index % active_pattern.size()]


func advance() -> void:
	if not pattern.is_empty():
		current_index += 1


func to_dict() -> Dictionary:
	return {"pattern": pattern.duplicate(), "rules": rules.duplicate(true), "current_index": current_index, "current_intent_id": current_intent_id()}


func _select_pattern(current_hp: int, max_hp: int, battle_turn: int) -> Array[String]:
	for rule in rules:
		if not _matches_rule(rule, current_hp, max_hp, battle_turn):
			continue
		var selected: Array[String] = []
		for intent_id in rule.get("pattern", []):
			selected.append(str(intent_id))
		if not selected.is_empty():
			return selected
	return pattern


func _matches_rule(rule: Dictionary, current_hp: int, max_hp: int, battle_turn: int) -> bool:
	if rule.has("turn_gte") and battle_turn < int(rule.get("turn_gte", 1)):
		return false
	if rule.has("hp_ratio_lte"):
		if max_hp <= 0 or current_hp < 0:
			return false
		if float(current_hp) / float(max_hp) > float(rule.get("hp_ratio_lte", 1.0)):
			return false
	return true
