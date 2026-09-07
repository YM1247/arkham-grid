class_name RunNodeResult
extends Resource

enum Outcome { COMPLETED, FAILED, SKIPPED }

@export var node_id: String = ""
@export var node_type: String = ""
@export var outcome: Outcome = Outcome.COMPLETED
@export var state_changes: Dictionary = {}
@export var next_node_ids: Array[String] = []


static func create(id: String, type: String, result_outcome: Outcome, changes: Dictionary = {}, next_ids: Array[String] = []):
	var result = (load("res://scripts/run/run_node_result.gd") as GDScript).new()
	result.node_id = id
	result.node_type = type
	result.outcome = result_outcome
	result.state_changes = changes.duplicate(true)
	result.next_node_ids = next_ids.duplicate()
	return result
