class_name LayeredMapGenerator
extends RefCounted

const NODE_TYPES := ["normal_battle", "elite", "event", "shop", "rest"]

var _rng := RandomNumberGenerator.new()


func generate(seed: int, map_template: Dictionary) -> Dictionary:
	_rng.seed = seed
	var config: Dictionary = map_template.get("generation", {})
	var floors := maxi(int(config.get("floors", 8)), 3)
	var columns := maxi(int(config.get("columns", 5)), 2)
	var min_nodes := clampi(int(config.get("min_nodes_per_floor", 2)), 1, columns)
	var max_nodes := clampi(int(config.get("max_nodes_per_floor", 3)), min_nodes, columns)
	var start_count := clampi(int(config.get("start_count", 2)), 1, columns)
	var max_links := maxi(int(config.get("max_links_per_node", 2)), 1)
	var nodes := {}
	var floor_ids: Array = []
	var next_id := 0
	for floor in range(floors):
		var ids: Array[int] = []
		var chosen_columns: Array[int]
		if floor == 0:
			chosen_columns = _even_columns(start_count, columns)
		elif floor == floors - 1:
			chosen_columns = [columns / 2]
		else:
			chosen_columns = _random_columns(_rng.randi_range(min_nodes, max_nodes), columns)
		for column in chosen_columns:
			nodes[next_id] = {
				"numeric_id": next_id,
				"id": "node_%02d" % next_id,
				"floor": floor,
				"column": column,
				"type": "normal_battle",
				"content_id": "",
				"next": [],
				"prev": [],
			}
			ids.append(next_id)
			next_id += 1
		floor_ids.append(ids)
	_connect_floors(nodes, floor_ids, max_links)
	_assign_types_and_content(nodes, floor_ids, map_template)
	var output_nodes: Array = []
	for id in nodes:
		var node: Dictionary = nodes[id]
		var next_ids: Array[String] = []
		for target_id in node.next:
			next_ids.append(str(nodes[target_id].id))
		output_nodes.append({
			"id": str(node.id),
			"floor": int(node.floor),
			"column": int(node.column),
			"type": str(node.type),
			"content_id": str(node.content_id),
			"next_ids": next_ids,
		})
	var starts: Array[String] = []
	for id in floor_ids[0]:
		starts.append(str(nodes[id].id))
	var boss_id := str(nodes[floor_ids[-1][0]].id)
	return {
		"schema_version": int(map_template.get("schema_version", 1)),
		"map_id": "%s_%d" % [map_template.get("map_id", "generated_run"), seed],
		"seed": seed,
		"algorithm": "layered_dag",
		"start_node_ids": starts,
		"boss_node_id": boss_id,
		"nodes": output_nodes,
	}


func verify_connectivity(map_data: Dictionary) -> bool:
	var index := {}
	for node in map_data.get("nodes", []):
		index[str(node.get("id", ""))] = node
	var boss_id := str(map_data.get("boss_node_id", ""))
	for start_id in map_data.get("start_node_ids", []):
		if not _can_reach(str(start_id), boss_id, index):
			return false
	return not boss_id.is_empty() and index.has(boss_id)


func _connect_floors(nodes: Dictionary, floors: Array, max_links: int) -> void:
	for floor in range(floors.size() - 1):
		var current: Array = floors[floor]
		var next: Array = floors[floor + 1]
		var band_edges: Array = []
		for source_id in current:
			var desired := 1 if floor == floors.size() - 2 else _rng.randi_range(1, max_links)
			var candidates := _sort_by_distance(nodes, next, int(source_id))
			var links := 0
			for target_id in candidates:
				if links >= desired:
					break
				if _would_cross(nodes, int(source_id), int(target_id), band_edges):
					continue
				_add_edge(nodes, int(source_id), int(target_id))
				band_edges.append([source_id, target_id])
				links += 1
			if links == 0:
				_add_edge(nodes, int(source_id), int(candidates[0]))
				band_edges.append([source_id, candidates[0]])
		for target_id in next:
			if nodes[target_id].prev.is_empty():
				var sources := _sort_by_distance(nodes, current, int(target_id))
				_add_edge(nodes, int(sources[0]), int(target_id))


func _assign_types_and_content(nodes: Dictionary, floors: Array, template: Dictionary) -> void:
	var config: Dictionary = template.get("generation", {})
	var weights: Dictionary = config.get("type_weights", {})
	var pools: Dictionary = template.get("content_pools", {})
	var normal_content_index := 0
	for floor in range(floors.size()):
		var floor_has_normal_battle := false
		for local_index in range(floors[floor].size()):
			var id: int = floors[floor][local_index]
			var type := "normal_battle"
			if floor == floors.size() - 1:
				type = "boss"
			elif floor == floors.size() - 2 and bool(config.get("force_rest_before_boss", true)):
				type = "rest"
			elif floor > 0:
				if bool(config.get("structured_node_types", false)):
					type = "normal_battle"
					if floor == int(config.get("event_floor", 2)):
						type = "event"
					elif floor == int(config.get("elite_floor", 3)):
						type = "elite"
					elif floor == int(floors.size() / 2) and bool(config.get("force_mid_shop", true)):
						type = "shop"
				else:
					type = _weighted_type(weights)
					if floor == int(floors.size() / 2) and local_index == 0 and bool(config.get("force_mid_shop", true)):
						type = "shop"
				for previous_id in nodes[id].prev:
					if nodes[previous_id].type == "rest" and type == "rest":
						type = "normal_battle"
			nodes[id].type = type
			var normal_sequence = config.get("normal_encounter_indices", [])
			var normal_pool_index := int(normal_sequence[normal_content_index]) if normal_sequence is Array and normal_content_index < normal_sequence.size() else normal_content_index
			var content_index := normal_pool_index if type == "normal_battle" else floor
			nodes[id].content_id = _pick_content(type, content_index, pools)
			floor_has_normal_battle = floor_has_normal_battle or type == "normal_battle"
		if floor_has_normal_battle:
			normal_content_index += 1


func _pick_content(type: String, floor: int, pools: Dictionary) -> String:
	var pool_key := type
	if type in ["normal_battle", "elite", "boss"]:
		pool_key = "%s_encounters" % type.trim_suffix("_battle")
	var values = pools.get(pool_key, [])
	if not values is Array or values.is_empty():
		return ""
	if type == "normal_battle":
		return str(values[mini(floor, values.size() - 1)])
	return str(values[_rng.randi_range(0, values.size() - 1)])


func _weighted_type(weights: Dictionary) -> String:
	var total := 0.0
	for type in NODE_TYPES:
		total += maxf(float(weights.get(type, 0.0)), 0.0)
	var roll := _rng.randf_range(0.0, total)
	var cursor := 0.0
	for type in NODE_TYPES:
		cursor += maxf(float(weights.get(type, 0.0)), 0.0)
		if roll <= cursor:
			return type
	return "normal_battle"


func _even_columns(count: int, columns: int) -> Array[int]:
	var result: Array[int] = []
	if count == 1:
		return [columns / 2]
	for i in range(count):
		result.append(int(round(float(i * (columns - 1)) / float(count - 1))))
	return result


func _random_columns(count: int, columns: int) -> Array[int]:
	var choices: Array[int] = []
	for column in range(columns):
		choices.append(column)
	for i in range(choices.size() - 1, 0, -1):
		var swap := _rng.randi_range(0, i)
		var value := choices[i]
		choices[i] = choices[swap]
		choices[swap] = value
	var result := choices.slice(0, count)
	result.sort()
	return result


func _sort_by_distance(nodes: Dictionary, candidates: Array, node_id: int) -> Array:
	var result := candidates.duplicate()
	result.sort_custom(func(a, b):
		var a_distance: int = abs(int(nodes[a].column) - int(nodes[node_id].column))
		var b_distance: int = abs(int(nodes[b].column) - int(nodes[node_id].column))
		return a_distance < b_distance
	)
	return result


func _add_edge(nodes: Dictionary, source_id: int, target_id: int) -> void:
	if target_id in nodes[source_id].next:
		return
	nodes[source_id].next.append(target_id)
	nodes[target_id].prev.append(source_id)


func _would_cross(nodes: Dictionary, source_id: int, target_id: int, edges: Array) -> bool:
	var a := Vector2(nodes[source_id].column, nodes[source_id].floor)
	var b := Vector2(nodes[target_id].column, nodes[target_id].floor)
	for edge in edges:
		var c := Vector2(nodes[edge[0]].column, nodes[edge[0]].floor)
		var d := Vector2(nodes[edge[1]].column, nodes[edge[1]].floor)
		if _segments_cross(a, b, c, d):
			return true
	return false


func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if a == c or a == d or b == c or b == d:
		return false
	return ((b - a).cross(c - a) * (b - a).cross(d - a) < 0.0
		and (d - c).cross(a - c) * (d - c).cross(b - c) < 0.0)


func _can_reach(start_id: String, target_id: String, index: Dictionary) -> bool:
	var pending: Array[String] = [start_id]
	var visited := {}
	while not pending.is_empty():
		var current: String = pending.pop_front()
		if current == target_id:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for next_id in index.get(current, {}).get("next_ids", []):
			pending.append(str(next_id))
	return false
