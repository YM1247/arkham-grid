class_name SmartHandScorer
extends RefCounted


func rank(board: BoardModel, block_pool: Array) -> Array:
	var candidates: Array = []
	for block_data in block_pool:
		if not block_data is BlockData:
			continue
		var best_score := -999999
		var best_clear_count := 0
		var best_direction_score := 0
		var valid_placements := 0
		for origin_x in range(board.dimension):
			for origin_y in range(board.dimension):
				if not board.can_place(origin_x, origin_y, block_data.cells):
					continue
				valid_placements += 1
				var result := score_placement(board, origin_x, origin_y, block_data)
				if int(result.score) > best_score:
					best_score = int(result.score)
					best_clear_count = int(result.clear_count)
					best_direction_score = int(result.direction_score)
		if valid_placements > 0:
			candidates.append({"block": block_data, "score": best_score, "clear_count": best_clear_count, "direction_score": best_direction_score, "valid_placements": valid_placements})
	candidates.sort_custom(func(a, b):
		if int(a.score) == int(b.score):
			return int(a.valid_placements) > int(b.valid_placements)
		return int(a.score) > int(b.score)
	)
	return candidates


func score_placement(board: BoardModel, origin_x: int, origin_y: int, block_data: BlockData) -> Dictionary:
	var projected := {}
	for offset in block_data.cells:
		projected[Vector2i(origin_x + offset.x, origin_y + offset.y)] = true
	var score := 0
	var clear_count := 0
	var direction_score := 0
	for y in range(board.dimension):
		var filled := 0
		var contributes_to_row := false
		for x in range(board.dimension):
			if board.cells[x][y] != null or projected.has(Vector2i(x, y)):
				filled += 1
			if projected.has(Vector2i(x, y)):
				contributes_to_row = true
		var line_score := _line_score(filled, board.dimension)
		score += line_score
		if contributes_to_row:
			direction_score = maxi(direction_score, line_score)
		if filled == board.dimension:
			clear_count += 1
	for x in range(board.dimension):
		var filled := 0
		var contributes_to_col := false
		for y in range(board.dimension):
			if board.cells[x][y] != null or projected.has(Vector2i(x, y)):
				filled += 1
			if projected.has(Vector2i(x, y)):
				contributes_to_col = true
		var line_score := _line_score(filled, board.dimension)
		score += line_score
		if contributes_to_col:
			direction_score = maxi(direction_score, line_score)
		if filled == board.dimension:
			clear_count += 1
	score += block_data.cells.size() + block_data.smart_score_bonus
	if block_data.is_special:
		score += 4
	return {"score": score, "clear_count": clear_count, "direction_score": direction_score}


func _line_score(filled: int, dimension: int) -> int:
	if filled == dimension:
		return 100
	if filled >= dimension - 1:
		return 24
	if filled >= dimension - 2:
		return 10
	return 0
