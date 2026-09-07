class_name FriendlyBoardGenerator
extends RefCounted


func generate(dimension: int, rng: RandomNumberGenerator, rules: Dictionary) -> Array[Vector2i]:
	var target_count := clampi(int(rules.get("friendly_seed_cells", 15)), 1, dimension * dimension - 1)
	var row_holes := clampi(int(rules.get("friendly_row_holes", 2)), 1, dimension - 1)
	var col_holes := clampi(int(rules.get("friendly_col_holes", 3)), 1, dimension - 1)
	var occupied := {}
	var row := rng.randi_range(0, dimension - 1)
	var row_hole_ids := _pick_unique_indices(dimension, row_holes, rng)
	for x in range(dimension):
		if x not in row_hole_ids:
			occupied[Vector2i(x, row)] = true
	var col := rng.randi_range(0, dimension - 1)
	var col_hole_ids := _pick_unique_indices(dimension, col_holes, rng)
	for y in range(dimension):
		if y not in col_hole_ids:
			occupied[Vector2i(col, y)] = true
	var attempts := dimension * dimension * 4
	while occupied.size() < target_count and attempts > 0:
		attempts -= 1
		var coord := Vector2i(rng.randi_range(0, dimension - 1), rng.randi_range(0, dimension - 1))
		if occupied.has(coord):
			continue
		occupied[coord] = true
		if _would_complete_line(occupied, coord, dimension):
			occupied.erase(coord)
	var result: Array[Vector2i] = []
	for coord in occupied:
		result.append(coord)
	return result


func _pick_unique_indices(count: int, amount: int, rng: RandomNumberGenerator) -> Array[int]:
	var values: Array[int] = []
	while values.size() < amount:
		var value := rng.randi_range(0, count - 1)
		if value not in values:
			values.append(value)
	return values


func _would_complete_line(occupied: Dictionary, coord: Vector2i, dimension: int) -> bool:
	var row_full := true
	var col_full := true
	for i in range(dimension):
		row_full = row_full and occupied.has(Vector2i(i, coord.y))
		col_full = col_full and occupied.has(Vector2i(coord.x, i))
	return row_full or col_full
