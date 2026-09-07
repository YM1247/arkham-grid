class_name EnemyIntentState
extends RefCounted

var pattern: Array[String] = []
var current_index: int = 0


func configure(intent_pattern: Array, start_index: int = 0) -> void:
	pattern.clear()
	for intent_id in intent_pattern:
		pattern.append(str(intent_id))
	current_index = posmod(start_index, pattern.size()) if not pattern.is_empty() else 0


func current_intent_id() -> String:
	if pattern.is_empty():
		return ""
	return pattern[current_index]


func advance() -> void:
	if not pattern.is_empty():
		current_index = (current_index + 1) % pattern.size()


func to_dict() -> Dictionary:
	return {"pattern": pattern.duplicate(), "current_index": current_index, "current_intent_id": current_intent_id()}
