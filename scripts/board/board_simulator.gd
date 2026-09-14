class_name BoardSimulator
extends RefCounted

const BOARD_DIMENSION := 8
const DEFAULT_RUNS := 100
const DEFAULT_PLACEMENTS_PER_RUN := 50
const DEFAULT_HAND_SIZE := 3
const DEFAULT_ACTION_POINTS := 5
const SMART_MODE := "smart"
const RANDOM_MODE := "weighted_random"

var _scorer := SmartHandScorer.new()
var _friendly_board_generator := FriendlyBoardGenerator.new()
var _spell_pool: Array[BattleItem] = []


func create_session(block_pool: Array[BlockData], board_rules: Dictionary, options: Dictionary = {}) -> Dictionary:
	_spell_pool.assign(options.get("spell_pool", []))
	var mode := str(options.get("mode", SMART_MODE))
	if block_pool.is_empty() or mode not in [SMART_MODE, RANDOM_MODE]:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(options.get("seed", 424242))
	var board := BoardModel.new(BOARD_DIMENSION)
	_seed_friendly_board(board, board_rules, rng)
	var pool: Array[BlockData] = []
	pool.assign(block_pool)
	var hand: Array[BlockData] = []
	return {
		"board": board,
		"pool": pool,
		"spell_pool": _spell_pool.duplicate(),
		"hand": hand,
		"board_spells": {},
		"rules": board_rules.duplicate(true),
		"rng": rng,
		"mode": mode,
		"hand_size": maxi(int(options.get("hand_size", DEFAULT_HAND_SIZE)), 1),
		"action_points": maxi(int(options.get("action_points", DEFAULT_ACTION_POINTS)), 1),
		"action_points_left": 0,
		"turn": 0,
		"placements": 0,
		"dead_boards": 0,
	}


func begin_session_turn(session: Dictionary) -> bool:
	if not _is_valid_session(session):
		return false
	_spell_pool.assign(session.get("spell_pool", []))
	var hand: Array[BlockData] = session.hand
	var board := session.board as BoardModel
	var pool: Array[BlockData] = session.pool
	var rng := session.rng as RandomNumberGenerator
	session.turn = int(session.turn) + 1
	session.action_points_left = int(session.action_points)
	_refill_hand(
		hand,
		int(session.hand_size),
		board,
		pool,
		str(session.mode),
		maxi(int(session.rules.get("directional_hand_min", 1)), 0),
		rng
	)
	return true


func next_session_event(session: Dictionary) -> Dictionary:
	if not _is_valid_session(session) or int(session.action_points_left) <= 0:
		return {"type": "turn_complete", "turn": int(session.get("turn", 0))}
	_spell_pool.assign(session.get("spell_pool", []))
	var board := session.board as BoardModel
	var hand: Array[BlockData] = session.hand
	var pool: Array[BlockData] = session.pool
	var rng := session.rng as RandomNumberGenerator
	var directional_hand_min := maxi(int(session.rules.get("directional_hand_min", 1)), 0)
	if _count_playable_cards(board, hand) <= 0:
		session.dead_boards = int(session.dead_boards) + 1
		board.clear()
		session.board_spells.clear()
		hand.clear()
		_seed_friendly_board(board, session.rules, rng)
		_refill_hand(hand, int(session.hand_size), board, pool, str(session.mode), directional_hand_min, rng)
		return {"type": "dead_board", "turn": int(session.turn)}
	var choice := _choose_best_placement(board, hand)
	if choice.is_empty():
		return {"type": "invalid", "turn": int(session.turn)}
	var block := choice.get("block") as BlockData
	var placement := board.place(int(choice.origin_x), int(choice.origin_y), block.cells, block.color)
	if not bool(placement.get("placed", false)):
		return {"type": "invalid", "turn": int(session.turn)}
	hand.remove_at(int(choice.hand_index))
	session.action_points_left = int(session.action_points_left) - 1
	session.placements = int(session.placements) + 1
	var rows: Array = placement.get("rows", [])
	var cols: Array = placement.get("cols", [])
	var board_spells: Dictionary = session.board_spells
	if block.spell != null:
		board_spells[Vector2i(int(choice.origin_x), int(choice.origin_y)) + block.effect_cell] = block.spell
	var triggered_spells := _collect_cleared_spells(board_spells, rows, cols)
	# 正式流程同樣會在手牌用盡時先補牌，再完成消線。
	if hand.is_empty():
		_refill_hand(hand, int(session.hand_size), board, pool, str(session.mode), directional_hand_min, rng)
	board.clear_lines(rows, cols)
	return {
		"type": "placement",
		"turn": int(session.turn),
		"block_id": block.id,
		"rows": rows.duplicate(),
		"cols": cols.duplicate(),
		"spells": triggered_spells,
		"occupied_cells": _count_occupied_cells(board),
	}


func add_session_block(session: Dictionary, block: BlockData) -> bool:
	if not _is_valid_session(session) or block == null:
		return false
	var pool: Array[BlockData] = session.pool
	if pool.any(func(owned): return owned != null and owned.id == block.id):
		return false
	pool.append(block)
	return true


func add_session_spell(session: Dictionary, spell: BattleItem) -> bool:
	if not _is_valid_session(session) or spell == null:
		return false
	var spells: Array = session.get("spell_pool", [])
	spells.append(spell)
	session.spell_pool = spells
	_spell_pool.assign(spells)
	return true


func add_session_slate(session: Dictionary, slate: BlockData) -> bool:
	if not _is_valid_session(session) or slate == null or slate.spell == null or slate.slate_uid.is_empty():
		return false
	var pool: Array[BlockData] = session.pool
	if pool.any(func(owned): return owned != null and (owned.slate_uid == slate.slate_uid or slate.is_special and owned.id == slate.id)):
		return false
	pool.append(slate)
	return true


func get_session_board_state(session: Dictionary) -> Array[String]:
	if not _is_valid_session(session):
		return []
	var board := session.board as BoardModel
	return board.serialize_cells()


func simulate(block_pool: Array[BlockData], board_rules: Dictionary, options: Dictionary = {}) -> Dictionary:
	_spell_pool.assign(options.get("spell_pool", []))
	var mode := str(options.get("mode", SMART_MODE))
	if mode not in [SMART_MODE, RANDOM_MODE]:
		return {"error": "未知模擬模式：%s" % mode}
	var runs := maxi(int(options.get("runs", DEFAULT_RUNS)), 1)
	var placements_per_run := maxi(int(options.get("placements_per_run", DEFAULT_PLACEMENTS_PER_RUN)), 1)
	var hand_size := maxi(int(options.get("hand_size", DEFAULT_HAND_SIZE)), 1)
	var action_points := maxi(int(options.get("action_points", DEFAULT_ACTION_POINTS)), 1)
	var seed := int(options.get("seed", 424242))
	var directional_hand_min := maxi(int(board_rules.get("directional_hand_min", 1)), 0)
	var totals := _create_totals(runs * placements_per_run)
	if block_pool.is_empty():
		return {"error": "方塊池不可為空"}
	for run_index in range(runs):
		_simulate_run(
			block_pool,
			board_rules,
			mode,
			seed + run_index * 104729,
			placements_per_run,
			hand_size,
			action_points,
			directional_hand_min,
			totals,
			false,
			[]
		)
	return _build_report(mode, seed, runs, placements_per_run, hand_size, action_points, totals)


func generate_events(block_pool: Array[BlockData], board_rules: Dictionary, options: Dictionary = {}) -> Array[Dictionary]:
	_spell_pool.assign(options.get("spell_pool", []))
	var placements := maxi(int(options.get("placements", DEFAULT_PLACEMENTS_PER_RUN)), 1)
	var hand_size := maxi(int(options.get("hand_size", DEFAULT_HAND_SIZE)), 1)
	var action_points := maxi(int(options.get("action_points", DEFAULT_ACTION_POINTS)), 1)
	var seed := int(options.get("seed", 424242))
	var mode := str(options.get("mode", SMART_MODE))
	var directional_hand_min := maxi(int(board_rules.get("directional_hand_min", 1)), 0)
	var events: Array[Dictionary] = []
	if block_pool.is_empty() or mode not in [SMART_MODE, RANDOM_MODE]:
		return events
	_simulate_run(
		block_pool,
		board_rules,
		mode,
		seed,
		placements,
		hand_size,
		action_points,
		directional_hand_min,
		_create_totals(placements),
		true,
		events
	)
	return events


func _simulate_run(
	block_pool: Array[BlockData],
	board_rules: Dictionary,
	mode: String,
	seed: int,
	placements_target: int,
	hand_size: int,
	action_points: int,
	directional_hand_min: int,
	totals: Dictionary,
	record_events: bool,
	events: Array[Dictionary]
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var board := BoardModel.new(BOARD_DIMENSION)
	var board_spells := {}
	var hand: Array[BlockData] = []
	_seed_friendly_board(board, board_rules, rng)
	var placements := 0
	var action_points_left := 0
	var turn_number := 0
	var loop_guard := placements_target * 20 + 100
	while placements < placements_target and loop_guard > 0:
		loop_guard -= 1
		if action_points_left <= 0:
			turn_number += 1
			action_points_left = action_points
			_refill_hand(hand, hand_size, board, block_pool, mode, directional_hand_min, rng)
		var playable_cards := _count_playable_cards(board, hand)
		totals.hand_checks = int(totals.hand_checks) + 1
		totals.card_checks = int(totals.card_checks) + hand.size()
		totals.playable_card_checks = int(totals.playable_card_checks) + playable_cards
		if playable_cards <= 0:
			totals.dead_boards = int(totals.dead_boards) + 1
			if record_events:
				events.append({"type": "dead_board", "turn": turn_number})
			board.clear()
			board_spells.clear()
			hand.clear()
			_seed_friendly_board(board, board_rules, rng)
			_refill_hand(hand, hand_size, board, block_pool, mode, directional_hand_min, rng)
			continue
		totals.playable_hand_checks = int(totals.playable_hand_checks) + 1
		var choice := _choose_best_placement(board, hand)
		if choice.is_empty():
			continue
		var block := choice.get("block") as BlockData
		var hand_index := int(choice.get("hand_index", -1))
		var placement := board.place(int(choice.origin_x), int(choice.origin_y), block.cells, block.color)
		if not bool(placement.get("placed", false)):
			continue
		hand.remove_at(hand_index)
		action_points_left -= 1
		placements += 1
		totals.successful_placements = int(totals.successful_placements) + 1
		var rows: Array = placement.get("rows", [])
		var cols: Array = placement.get("cols", [])
		if block.spell != null:
			board_spells[Vector2i(int(choice.origin_x), int(choice.origin_y)) + block.effect_cell] = block.spell
		var triggered_spells := _collect_cleared_spells(board_spells, rows, cols)
		var line_count := rows.size() + cols.size()
		if line_count > 0:
			totals.clear_placements = int(totals.clear_placements) + 1
			totals.cleared_lines = int(totals.cleared_lines) + line_count
		if record_events:
			events.append({
				"type": "placement",
				"turn": turn_number,
				"block_id": block.id,
				"rows": rows.duplicate(),
				"cols": cols.duplicate(),
				"spells": triggered_spells,
			})
		# 正式流程會在手牌用盡時先補牌，再播放並完成消線；模擬器保留同一順序。
		if hand.is_empty():
			_refill_hand(hand, hand_size, board, block_pool, mode, directional_hand_min, rng)
		board.clear_lines(rows, cols)
		var occupied_cells := _count_occupied_cells(board)
		totals.occupancy_samples = int(totals.occupancy_samples) + 1
		totals.occupied_cells_total = int(totals.occupied_cells_total) + occupied_cells
		totals.maximum_occupied_cells = maxi(int(totals.maximum_occupied_cells), occupied_cells)
	if placements < placements_target:
		push_warning("棋盤模擬提前停止：seed=%d，完成 %d/%d 次放置" % [seed, placements, placements_target])


func _refill_hand(
	hand: Array[BlockData],
	hand_size: int,
	board: BoardModel,
	block_pool: Array[BlockData],
	mode: String,
	directional_hand_min: int,
	rng: RandomNumberGenerator
) -> void:
	while hand.size() < hand_size:
		var excluded_ids := {}
		for held_block in hand:
			excluded_ids[held_block.id] = true
		var block := _draw_block(board, block_pool, mode, hand.size(), directional_hand_min, excluded_ids, rng)
		if block == null:
			return
		hand.append(block)


func _draw_block(
	board: BoardModel,
	block_pool: Array[BlockData],
	mode: String,
	hand_index: int,
	directional_hand_min: int,
	excluded_ids: Dictionary,
	rng: RandomNumberGenerator
) -> BlockData:
	var selected: BlockData = null
	if mode == SMART_MODE:
		var candidates := _rank_rotated_pool(board, block_pool, excluded_ids)
		if not candidates.is_empty():
			if hand_index < directional_hand_min:
				var clear_candidates := candidates.filter(func(candidate): return int(candidate.get("clear_count", 0)) > 0)
				if not clear_candidates.is_empty():
					selected = _pick_from_top_candidates(clear_candidates, 2, block_pool, rng)
				var directional_candidates := candidates.filter(func(candidate): return int(candidate.get("direction_score", 0)) > 0)
				if selected == null and not directional_candidates.is_empty():
					selected = _pick_from_top_candidates(directional_candidates, 3, block_pool, rng)
			if selected == null:
				selected = _pick_from_top_candidates(candidates, 3, block_pool, rng)
	if selected == null:
		selected = _random_weighted_rotation(block_pool, excluded_ids, rng)
		if selected == null and not excluded_ids.is_empty():
			selected = _random_weighted_rotation(block_pool, {}, rng)
	return _attach_spell(selected, rng)


func _attach_spell(block: BlockData, rng: RandomNumberGenerator) -> BlockData:
	if block != null and block.spell != null:
		return block
	if block == null or _spell_pool.is_empty() or block.cells.is_empty():
		return block
	var spell := _spell_pool[rng.randi_range(0, _spell_pool.size() - 1)] as BattleItem
	return block.with_spell(spell, block.cells[rng.randi_range(0, block.cells.size() - 1)])


func _collect_cleared_spells(board_spells: Dictionary, rows: Array, cols: Array) -> Array[BattleItem]:
	var cleared_coords := {}
	for y in rows:
		for x in range(BOARD_DIMENSION):
			cleared_coords[Vector2i(x, int(y))] = true
	for x in cols:
		for y in range(BOARD_DIMENSION):
			cleared_coords[Vector2i(int(x), y)] = true
	var result: Array[BattleItem] = []
	for coord in cleared_coords:
		var spell := board_spells.get(coord) as BattleItem
		if spell != null:
			result.append(spell)
		board_spells.erase(coord)
	return result


func _rank_rotated_pool(board: BoardModel, block_pool: Array[BlockData], excluded_ids: Dictionary = {}) -> Array:
	var rotated_pool: Array = []
	for block in block_pool:
		if block == null or excluded_ids.has(block.id):
			continue
		for rotation_steps in range(4):
			rotated_pool.append(block.rotated(rotation_steps))
	return _scorer.rank(board, rotated_pool)


func _pick_from_top_candidates(candidates: Array, top_count: int, block_pool: Array[BlockData], rng: RandomNumberGenerator) -> BlockData:
	var unique: Array[Dictionary] = []
	var seen := {}
	for candidate in candidates:
		var block := candidate.get("block") as BlockData
		if block == null or seen.has(block.id):
			continue
		seen[block.id] = true
		unique.append(candidate)
		if unique.size() >= top_count:
			break
	if unique.is_empty():
		return null
	var total_weight := 0.0
	for candidate in unique:
		var block := candidate.get("block") as BlockData
		total_weight += maxf(block.weight, 0.01) * float(_pool_count(block_pool, block.id))
	var roll := rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for candidate in unique:
		var block := candidate.get("block") as BlockData
		cursor += maxf(block.weight, 0.01) * float(_pool_count(block_pool, block.id))
		if roll <= cursor:
			return block
	return unique.back().get("block") as BlockData


func _random_weighted_rotation(block_pool: Array[BlockData], excluded_ids: Dictionary, rng: RandomNumberGenerator) -> BlockData:
	var total_weight := 0.0
	for block in block_pool:
		if not excluded_ids.has(block.id):
			total_weight += maxf(block.weight, 0.01)
	if total_weight <= 0.0:
		return null
	var roll := rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	var fallback: BlockData = null
	for block in block_pool:
		if excluded_ids.has(block.id):
			continue
		fallback = block
		cursor += maxf(block.weight, 0.01)
		if roll <= cursor:
			return block.rotated(rng.randi_range(0, 3))
	return fallback.rotated(rng.randi_range(0, 3)) if fallback != null else null


func _pool_count(block_pool: Array[BlockData], block_id: String) -> int:
	var count := 0
	for block in block_pool:
		if block != null and block.id == block_id:
			count += 1
	return count


func _count_playable_cards(board: BoardModel, hand: Array[BlockData]) -> int:
	var count := 0
	for block in hand:
		if _find_first_valid_origin(board, block) != Vector2i(-1, -1):
			count += 1
	return count


func _choose_best_placement(board: BoardModel, hand: Array[BlockData]) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -999999
	var best_clear_count := -1
	for hand_index in range(hand.size()):
		var block := hand[hand_index]
		for origin_x in range(board.dimension):
			for origin_y in range(board.dimension):
				if not board.can_place(origin_x, origin_y, block.cells):
					continue
				var score := _scorer.score_placement(board, origin_x, origin_y, block)
				var score_value := int(score.get("score", 0))
				var clear_count := int(score.get("clear_count", 0))
				if score_value > best_score or (score_value == best_score and clear_count > best_clear_count):
					best_score = score_value
					best_clear_count = clear_count
					best = {
						"block": block,
						"hand_index": hand_index,
						"origin_x": origin_x,
						"origin_y": origin_y,
						"score": score_value,
						"clear_count": clear_count,
					}
	return best


func _find_first_valid_origin(board: BoardModel, block: BlockData) -> Vector2i:
	for origin_x in range(board.dimension):
		for origin_y in range(board.dimension):
			if board.can_place(origin_x, origin_y, block.cells):
				return Vector2i(origin_x, origin_y)
	return Vector2i(-1, -1)


func _seed_friendly_board(board: BoardModel, rules: Dictionary, rng: RandomNumberGenerator) -> void:
	for coord in _friendly_board_generator.generate(board.dimension, rng, rules):
		board.cells[coord.x][coord.y] = Color.GRAY


func _count_occupied_cells(board: BoardModel) -> int:
	var occupied := 0
	for x in range(board.dimension):
		for y in range(board.dimension):
			if board.cells[x][y] != null:
				occupied += 1
	return occupied


func _build_report(
	mode: String,
	seed: int,
	runs: int,
	placements_per_run: int,
	hand_size: int,
	action_points: int,
	totals: Dictionary
) -> Dictionary:
	var successful := int(totals.successful_placements)
	var hand_checks := int(totals.hand_checks)
	var card_checks := int(totals.card_checks)
	var occupancy_samples := int(totals.occupancy_samples)
	return {
		"mode": mode,
		"seed": seed,
		"runs": runs,
		"placements_per_run": placements_per_run,
		"hand_size": hand_size,
		"action_points": action_points,
		"requested_placements": int(totals.requested_placements),
		"successful_placements": successful,
		"completion_rate": _safe_ratio(successful, int(totals.requested_placements)),
		"legal_hand_rate": _safe_ratio(int(totals.playable_hand_checks), hand_checks),
		"legal_card_rate": _safe_ratio(int(totals.playable_card_checks), card_checks),
		"direct_clear_rate": _safe_ratio(int(totals.clear_placements), successful),
		"lines_per_placement": _safe_ratio(int(totals.cleared_lines), successful),
		"average_occupancy_rate": _safe_ratio(int(totals.occupied_cells_total), occupancy_samples * BOARD_DIMENSION * BOARD_DIMENSION),
		"maximum_occupancy_rate": float(totals.maximum_occupied_cells) / float(BOARD_DIMENSION * BOARD_DIMENSION),
		"dead_boards": int(totals.dead_boards),
		"dead_boards_per_100_placements": 100.0 * _safe_ratio(int(totals.dead_boards), successful),
	}


func _safe_ratio(numerator: int, denominator: int) -> float:
	return 0.0 if denominator <= 0 else float(numerator) / float(denominator)


func _is_valid_session(session: Dictionary) -> bool:
	return (
		session.get("board") is BoardModel
		and session.get("rng") is RandomNumberGenerator
		and session.get("pool") is Array
		and session.get("hand") is Array
		and session.get("rules") is Dictionary
	)


func _create_totals(requested_placements: int) -> Dictionary:
	return {
		"requested_placements": requested_placements,
		"successful_placements": 0,
		"hand_checks": 0,
		"playable_hand_checks": 0,
		"card_checks": 0,
		"playable_card_checks": 0,
		"clear_placements": 0,
		"cleared_lines": 0,
		"dead_boards": 0,
		"occupancy_samples": 0,
		"occupied_cells_total": 0,
		"maximum_occupied_cells": 0,
	}
