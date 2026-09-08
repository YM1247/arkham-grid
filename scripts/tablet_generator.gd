extends VBoxContainer

signal row_activated(row_index: int)
signal col_activated(col_index: int)
signal spell_activated(spell: BattleItem, board_cell: Vector2i)
signal block_placed(block_data: BlockData)
signal no_valid_moves(penalty: int)

# --- 設定參數 ---
# 這裡的大小要跟 GridCell 的大小一致
const CELL_SIZE = Vector2(70, 70)
const GRID_DIMENSION = 8

# --- 資源載入 ---
# 載入剛剛做的格子場景
var grid_cell_scene = preload("res://grid_cell.tscn")
var block_scene = preload("res://block.tscn")
var _current_preview_cells: Array[GridCell] = []
var _current_clear_preview_cells: Array[GridCell] = []

# --- 節點參照 ---
@onready var corner_spacer = $Header/Corner
@onready var col_icons_container = $Header/ColIcons
@onready var row_icons_container = $Body/RowIcons
@onready var grid_container = $Body/GridCells
@onready var hand_area = $HandArea

# --- 手牌設定 ---
@export var block_pool: Array[BlockData] = []
@export var spell_pool: Array[BattleItem] = []
@export var hand_size: int = 3
@export var no_valid_moves_sanity_penalty: int = 10
@export var seed_board_on_start: bool = true
@export var smart_hand_enabled: bool = true
@export var directional_hand_min: int = 1
@export var friendly_board_rules: Dictionary = {}

# --- 資料層 (Model) ---
# 0 或 null 代表空，有東西則存顏色或資料
var grid_data: Array = [] 
var grid_spells: Array = []
var board_model := BoardModel.new(GRID_DIMENSION)
var smart_hand_scorer := SmartHandScorer.new()
var friendly_board_generator = preload("res://scripts/board/friendly_board_generator.gd").new()
var rng := RandomNumberGenerator.new()
var placement_enabled := true
var _is_recovering_from_no_moves := false

func _ready():
	rng.randomize()
	_setup_layout_properties()
	_init_grid_data()  # 初始化資料陣列
	_generate_tablet()
	if seed_board_on_start:
		_seed_friendly_board()
	
	# 初始抽牌
	await get_tree().process_frame
	refill_hand()

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		# 當任何拖曳行為結束時，強制清除所有預覽
		clear_preview()

func _setup_layout_properties():
	grid_container.columns = GRID_DIMENSION
	corner_spacer.custom_minimum_size = CELL_SIZE
	
	# 確保手牌區高度夠
	hand_area.custom_minimum_size.y = 200
	
	# 如果你在編輯器有用 PaddingContainer，這裡的 spacing 可以設為 0 或小一點
	# 根據你的截圖，這裡其實用預設值就好，不用特別 override 也可以

func _init_grid_data():
	board_model.clear()
	grid_data = board_model.cells
	grid_spells.clear()
	for x in range(GRID_DIMENSION):
		var column: Array = []
		column.resize(GRID_DIMENSION)
		column.fill(null)
		grid_spells.append(column)

func _generate_tablet():
	# 1. 生成 Header (直行圖示)
	for i in range(GRID_DIMENSION):
		var icon = Label.new()
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.custom_minimum_size = CELL_SIZE
		icon.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
		icon.text = _get_col_slot_label(i, null)
		col_icons_container.add_child(icon)
		
	# 2. 生成 Left (橫列圖示)
	for i in range(GRID_DIMENSION):
		var icon = Label.new()
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.custom_minimum_size = CELL_SIZE
		icon.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
		icon.text = _get_row_slot_label(i, null)
		row_icons_container.add_child(icon)
		
	# 3. 生成 GridCell (核心改動)
	for i in range(GRID_DIMENSION * GRID_DIMENSION):
		# 實例化格子場景
		var cell = grid_cell_scene.instantiate()
		
		# 計算二維座標
		var x = i % GRID_DIMENSION
		var y = i / GRID_DIMENSION
		
		# 初始化：傳入座標和自己(Manager)
		cell.init(x, y, self)
		
		grid_container.add_child(cell)

func _spawn_block(data):
	var block = block_scene.instantiate()
	hand_area.add_child(block)
	block.set_data(data)
	if block.has_method("set_drag_enabled"):
		block.set_drag_enabled(placement_enabled)
	return block

func draw_new_hand():
	_clear_hand()
	refill_hand()

func refill_hand():
	if block_pool.is_empty():
		push_warning("TableGenerator 沒有設定 block_pool，無法抽牌。")
		return
	var current_count := _count_active_hand_blocks()
	var excluded_ids := {}
	for held_block in _get_active_hand_block_data():
		excluded_ids[held_block.id] = true
	for i in range(current_count, hand_size):
		var drawn := _draw_block_data(i, excluded_ids)
		if drawn == null:
			break
		_spawn_block(drawn)
		excluded_ids[drawn.id] = true
	_sync_hand_drag_enabled()
	_check_no_valid_moves_deferred()

func _draw_block_data(hand_index: int = 0, excluded_ids: Dictionary = {}) -> BlockData:
	var selected: BlockData = null
	if smart_hand_enabled:
		var smart_block = _draw_smart_block_data(hand_index, excluded_ids)
		if smart_block != null:
			selected = smart_block
	if selected == null:
		var weighted := _draw_weighted_random_block(excluded_ids)
		if weighted == null and not excluded_ids.is_empty():
			weighted = _draw_weighted_random_block()
		selected = _randomize_block_rotation(weighted)
	return _attach_random_spell(selected)


func _attach_random_spell(block_data: BlockData) -> BlockData:
	if block_data == null or spell_pool.is_empty() or block_data.cells.is_empty():
		return block_data
	var spell := spell_pool[rng.randi_range(0, spell_pool.size() - 1)] as BattleItem
	var marked_cell := block_data.cells[rng.randi_range(0, block_data.cells.size() - 1)]
	return block_data.with_spell(spell, marked_cell)

func _draw_weighted_random_block(excluded_ids: Dictionary = {}) -> BlockData:
	var total_weight := 0.0
	for block_data in block_pool:
		if block_data is BlockData and not excluded_ids.has(block_data.id):
			total_weight += maxf(block_data.weight, 0.01)
	if total_weight <= 0.0:
		return null
	var roll = rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	var fallback: BlockData = null
	for block_data in block_pool:
		if not block_data is BlockData or excluded_ids.has(block_data.id):
			continue
		fallback = block_data
		cursor += maxf(block_data.weight, 0.01)
		if roll <= cursor:
			return block_data
	return fallback

func _draw_smart_block_data(hand_index: int, excluded_ids: Dictionary = {}) -> BlockData:
	var candidates = _score_block_pool_for_current_board(excluded_ids)
	if candidates.is_empty():
		return null
	if hand_index < directional_hand_min:
		var clear_candidates = candidates.filter(func(candidate): return int(candidate.get("clear_count", 0)) > 0)
		if not clear_candidates.is_empty():
			return _pick_from_top_candidates(clear_candidates, 2)
		var directional_candidates = candidates.filter(func(candidate): return int(candidate.get("direction_score", 0)) > 0)
		if not directional_candidates.is_empty():
			return _pick_from_top_candidates(directional_candidates, 3)
	return _pick_from_top_candidates(candidates, 3)

func _score_block_pool_for_current_board(excluded_ids: Dictionary = {}) -> Array:
	var rotated_pool: Array = []
	for block_data in block_pool:
		if not block_data is BlockData or excluded_ids.has(block_data.id):
			continue
		for rotation_steps in range(4):
			rotated_pool.append(block_data.rotated(rotation_steps))
	return smart_hand_scorer.rank(board_model, rotated_pool)

func _randomize_block_rotation(block_data: BlockData) -> BlockData:
	if block_data == null:
		return null
	return block_data.rotated(rng.randi_range(0, 3))

func _score_smart_hand_placement(origin_x: int, origin_y: int, block_data: BlockData) -> Dictionary:
	return smart_hand_scorer.score_placement(board_model, origin_x, origin_y, block_data)

func _pick_from_top_candidates(candidates: Array, top_count: int) -> BlockData:
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
		total_weight += maxf(block.weight, 0.01) * float(get_block_pool_count(block.id))
	var roll := rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for candidate in unique:
		var block := candidate.get("block") as BlockData
		cursor += maxf(block.weight, 0.01) * float(get_block_pool_count(block.id))
		if roll <= cursor:
			return block
	return unique.back().get("block") as BlockData

func _clear_hand():
	for child in hand_area.get_children():
		child.queue_free()

func set_placement_enabled(enabled: bool):
	placement_enabled = enabled
	if not placement_enabled:
		clear_preview()
	_sync_hand_drag_enabled()

func set_block_pool(new_block_pool: Array):
	block_pool.clear()
	for block_data in new_block_pool:
		if block_data is BlockData:
			block_pool.append(block_data)


func set_spell_pool(new_spell_pool: Array) -> void:
	spell_pool.clear()
	for spell in new_spell_pool:
		if spell is BattleItem:
			spell_pool.append(spell)


func add_spell_to_pool(spell: BattleItem) -> void:
	if spell != null:
		spell_pool.append(spell)


func get_spell_pool_ids() -> Array[String]:
	var ids: Array[String] = []
	for spell in spell_pool:
		if spell != null:
			ids.append(spell.content_id)
	return ids

func add_block_to_pool(block_data: BlockData):
	if block_data == null:
		return
	if get_block_pool_count(block_data.id) > 0:
		return
	block_pool.append(block_data)

func get_block_pool_count(block_id: String) -> int:
	var count := 0
	for block_data in block_pool:
		if block_data is BlockData and block_data.id == block_id:
			count += 1
	return count

func set_board_growth_rules(rules: Dictionary) -> void:
	directional_hand_min = maxi(int(rules.get("directional_hand_min", directional_hand_min)), 0)
	friendly_board_rules = rules.duplicate(true)


func set_rng_seed(value: int) -> void:
	rng.seed = value


func set_rng_state(value: String) -> bool:
	if not value.is_valid_int():
		return false
	rng.state = int(value)
	return true


func get_rng_state() -> String:
	return str(rng.state)

func reset_tablet():
	clear_preview()
	_init_grid_data()
	for child in grid_container.get_children():
		if child is GridCell:
			child.color = Color(0.15, 0.15, 0.15)
			child.original_color = child.color
			child.set_spell(null)
			child.reset_color()
	if seed_board_on_start:
		_seed_friendly_board()
	draw_new_hand()

# --- 邏輯判斷區 (大腦) ---

# 檢查是否可以放置
func check_placement_valid(origin_x: int, origin_y: int, block_data: BlockData) -> bool:
	return placement_enabled and block_data != null and board_model.can_place(origin_x, origin_y, block_data.cells)

# 【新增】更新預覽狀態 (被 GridCell 呼叫)
func update_preview(origin_x: int, origin_y: int, block_data: BlockData, is_valid: bool):
	# 1. 無論如何，先清除上一次的預覽狀態
	clear_preview()
	
	# 2. 如果當前位置不合法，就只要清除舊的就好，不用畫新的
	if not is_valid:
		return
		
	# 3. 計算新的預覽位置並高亮它們
	for offset in block_data.cells:
		var target_x = origin_x + offset.x
		var target_y = origin_y + offset.y
		
		# 找到對應的格子節點
		var cell_index = target_y * GRID_DIMENSION + target_x
		var cell_node = grid_container.get_child(cell_index) as GridCell
		
		# 開啟高亮
		cell_node.set_highlight(true)
		# 加入追蹤陣列
		_current_preview_cells.append(cell_node)
	
	_update_clear_line_preview(origin_x, origin_y, block_data)

# 【新增】清除所有預覽
func clear_preview():
	for cell in _current_preview_cells:
		cell.set_highlight(false)
	_current_preview_cells.clear()
	for cell in _current_clear_preview_cells:
		cell.set_clear_preview(false)
	_current_clear_preview_cells.clear()

# 執行放置 (原本的函數，稍微修改)
func place_block(origin_x: int, origin_y: int, block_data: BlockData, source_block: Node = null):
	print("放置方塊於: ", origin_x, ",", origin_y)
	
	# 【新增】放置前先清除預覽，確保狀態乾淨
	clear_preview()
	
	for offset in block_data.cells:
		var target_x = origin_x + offset.x
		var target_y = origin_y + offset.y
		
		# A. 更新資料
		grid_data[target_x][target_y] = block_data.color
		
		# B. 更新視覺
		var cell_index = target_y * GRID_DIMENSION + target_x
		var cell_node = grid_container.get_child(cell_index) as GridCell
		
		# 更新顏色並記住新的「原始顏色」
		cell_node.color = block_data.color
		cell_node.original_color = block_data.color
		if offset == block_data.effect_cell and block_data.spell != null:
			grid_spells[target_x][target_y] = block_data.spell
			cell_node.set_spell(block_data.spell)
	
	block_placed.emit(block_data)
	if source_block != null:
		source_block.queue_free()
	_refill_hand_if_empty()
	await _check_and_clear_lines()
	_check_no_valid_moves_deferred()
	
func _check_and_clear_lines():
	var lines := board_model.get_full_lines()
	var rows_to_clear: Array = lines.rows
	var cols_to_clear: Array = lines.cols
	
	# 如果沒有消除，直接結束
	if rows_to_clear.is_empty() and cols_to_clear.is_empty():
		return

	# 3. 執行消除 (Visual & Data Clear)
	# 這裡我們定義一個 helper function 來處理清除
	await _execute_clear(rows_to_clear, cols_to_clear)

func _execute_clear(rows: Array, cols: Array):
	# --- 階段 1: 視覺特效 (只閃爍，不刪資料) ---
	
	# 收集所有需要消除的格子座標，避免重複 (十字消除的中心點)
	var cells_to_clear = []
	
	# 處理直行。設計規則：同時消除時固定先 Col 再 Row。
	for x in cols:
		col_activated.emit(x) # 發送信號
		for y in range(GRID_DIMENSION):
			if not Vector2i(x, y) in cells_to_clear:
				cells_to_clear.append(Vector2i(x, y))
	
	# 處理橫列
	for y in rows:
		row_activated.emit(y) # 發送信號
		for x in range(GRID_DIMENSION):
			if not Vector2i(x, y) in cells_to_clear:
				cells_to_clear.append(Vector2i(x, y))

	# 每個被消除的效果格只觸發一次；Row／Col 交會不重複結算。
	for coord in cells_to_clear:
		var spell := grid_spells[coord.x][coord.y] as BattleItem
		if spell != null:
			spell_activated.emit(spell, coord)
	
	# 對這些格子播放閃爍特效
	for coord in cells_to_clear:
		_play_flash_effect(coord.x, coord.y)
	
	# --- 階段 2: 停頓 (關鍵延遲) ---
	# 這裡設定 0.3 秒，你可以自己調整喜歡的節奏
	await get_tree().create_timer(0.15).timeout
	
	# --- 階段 3: 真實清除 (資料與顏色) ---
	for coord in cells_to_clear:
		_clear_cell_data(coord.x, coord.y)

# 只負責視覺閃爍
func _play_flash_effect(x: int, y: int):
	var cell_index = y * GRID_DIMENSION + x
	var cell_node = grid_container.get_child(cell_index) as GridCell
	
	# 讓顏色瞬間變亮 (白色 200%)
	# 這裡不改變 cell.color，只改變 modulate (疊加色)
	var tween = create_tween()
	tween.tween_property(cell_node, "modulate", Color(2.5, 2.5, 2.5), 0.1) # 瞬間變亮
	tween.tween_property(cell_node, "modulate", Color(1, 1, 1), 0.2)     # 慢慢變回來

# 只負責清除資料
func _clear_cell_data(x: int, y: int):
	# 1. 清除資料
	grid_data[x][y] = null
	grid_spells[x][y] = null
	
	# 2. 恢復格子顏色
	var cell_index = y * GRID_DIMENSION + x
	var cell_node = grid_container.get_child(cell_index) as GridCell
	
	cell_node.color = Color(0.15, 0.15, 0.15) # 變回深灰色
	cell_node.original_color = cell_node.color
	cell_node.set_spell(null)


func get_board_state() -> Array[String]:
	return board_model.serialize_cells()


func restore_board_state(serialized: Array[String]) -> bool:
	if not board_model.restore_cells(serialized):
		return false
	grid_data = board_model.cells
	for y in range(GRID_DIMENSION):
		for x in range(GRID_DIMENSION):
			var cell_node = grid_container.get_child(y * GRID_DIMENSION + x) as GridCell
			var value = grid_data[x][y]
			cell_node.color = value if value is Color else Color(0.15, 0.15, 0.15)
			cell_node.original_color = cell_node.color
			cell_node.reset_color()
	return true


func get_board_spell_state() -> Array[String]:
	var state: Array[String] = []
	for y in range(GRID_DIMENSION):
		for x in range(GRID_DIMENSION):
			var spell := grid_spells[x][y] as BattleItem
			state.append(spell.content_id if spell != null else "")
	return state


func restore_board_spell_state(state: Array[String], resources: Dictionary) -> bool:
	if state.size() != GRID_DIMENSION * GRID_DIMENSION:
		return false
	for y in range(GRID_DIMENSION):
		for x in range(GRID_DIMENSION):
			var spell := resources.get(state[y * GRID_DIMENSION + x]) as BattleItem
			grid_spells[x][y] = spell
			var cell_node = grid_container.get_child(y * GRID_DIMENSION + x) as GridCell
			cell_node.set_spell(spell)
	return true


func get_hand_ids() -> Array[String]:
	var ids: Array[String] = []
	for block_data in _get_active_hand_block_data():
		ids.append(block_data.id)
	return ids

func get_hand_state() -> Array[Dictionary]:
	var state: Array[Dictionary] = []
	for child in hand_area.get_children():
		if child.is_queued_for_deletion() or not "block_data" in child or not child.block_data is BlockData:
			continue
		state.append({
			"id": child.block_data.id,
			"rotation_steps": child.block_data.get_rotation_steps(),
			"spell_id": child.block_data.spell.content_id if child.block_data.spell != null else "",
			"effect_cell": [child.block_data.effect_cell.x, child.block_data.effect_cell.y],
		})
	return state


func restore_hand(blocks: Array[BlockData]) -> void:
	_clear_hand()
	for block_data in blocks:
		_spawn_block(block_data)
	_sync_hand_drag_enabled()

func restore_hand_state(state: Array, resources: Dictionary) -> void:
	_clear_hand()
	for value in state:
		if not value is Dictionary:
			continue
		var base := resources.get(str(value.get("id", ""))) as BlockData
		if base != null:
			var restored := base.rotated(int(value.get("rotation_steps", 0)))
			var effect_cell = value.get("effect_cell", [0, 0])
			if effect_cell is Array and effect_cell.size() == 2:
				restored = restored.with_spell(_find_spell_in_pool(str(value.get("spell_id", ""))), Vector2i(int(effect_cell[0]), int(effect_cell[1])))
			_spawn_block(restored)
	_sync_hand_drag_enabled()


func _find_spell_in_pool(spell_id: String) -> BattleItem:
	for spell in spell_pool:
		if spell != null and spell.content_id == spell_id:
			return spell
	return null


func get_block_pool_ids() -> Array[String]:
	var ids: Array[String] = []
	for block_data in block_pool:
		if block_data != null:
			ids.append(block_data.id)
	return ids

func _refill_hand_if_empty():
	if _count_active_hand_blocks() > 0:
		return
	draw_new_hand()

func _count_active_hand_blocks() -> int:
	var count = 0
	for child in hand_area.get_children():
		if child.has_method("set_data") and not child.is_queued_for_deletion():
			count += 1
	return count

func _sync_hand_drag_enabled():
	for child in hand_area.get_children():
		if child.has_method("set_drag_enabled"):
			child.set_drag_enabled(placement_enabled)

func _check_no_valid_moves_deferred():
	if _is_recovering_from_no_moves or not placement_enabled:
		return
	call_deferred("_handle_no_valid_moves_if_needed")

func _handle_no_valid_moves_if_needed():
	if _is_recovering_from_no_moves or not placement_enabled:
		return
	if block_pool.is_empty() or _get_active_hand_block_data().is_empty():
		return
	if _has_any_valid_move():
		return
	print("盤面無任何可放置方塊，觸發 Sanity 懲罰：", no_valid_moves_sanity_penalty)
	_is_recovering_from_no_moves = true
	no_valid_moves.emit(no_valid_moves_sanity_penalty)
	clear_preview()
	_clear_board_cells()
	if seed_board_on_start:
		_seed_friendly_board()
	draw_new_hand()
	_is_recovering_from_no_moves = false

func _has_any_valid_move() -> bool:
	for block_data in _get_active_hand_block_data():
		for origin_x in range(GRID_DIMENSION):
			for origin_y in range(GRID_DIMENSION):
				if check_placement_valid(origin_x, origin_y, block_data):
					return true
	return false

func _get_active_hand_block_data() -> Array[BlockData]:
	var hand_blocks: Array[BlockData] = []
	for child in hand_area.get_children():
		if child.is_queued_for_deletion():
			continue
		if "block_data" in child and child.block_data is BlockData:
			hand_blocks.append(child.block_data)
	return hand_blocks

func _clear_board_cells():
	_init_grid_data()
	for child in grid_container.get_children():
		if child is GridCell:
			child.color = Color(0.15, 0.15, 0.15)
			child.original_color = child.color
			child.set_spell(null)
			child.reset_color()

func _seed_friendly_board():
	var seed_color = Color(0.32, 0.38, 0.52)
	var accent_color = Color(0.38, 0.32, 0.50)
	var seed_cells := friendly_board_generator.generate(GRID_DIMENSION, rng, friendly_board_rules)
	for i in range(seed_cells.size()):
		var color = seed_color if i % 2 == 0 else accent_color
		_set_seed_cell(seed_cells[i], color)

func _set_seed_cell(coord: Vector2i, color: Color):
	if coord.x < 0 or coord.x >= GRID_DIMENSION or coord.y < 0 or coord.y >= GRID_DIMENSION:
		return
	grid_data[coord.x][coord.y] = color
	var cell_index = coord.y * GRID_DIMENSION + coord.x
	var cell_node = grid_container.get_child(cell_index) as GridCell
	if cell_node == null:
		return
	cell_node.color = color
	cell_node.original_color = color
	cell_node.reset_color()

func _get_row_slot_label(index: int, item: BattleItem) -> String:
	return "R%d" % [index + 1]

func _get_col_slot_label(index: int, item: BattleItem) -> String:
	return "C%d" % [index + 1]

func _update_clear_line_preview(origin_x: int, origin_y: int, block_data: BlockData):
	var projected_cells = {}
	for x in range(GRID_DIMENSION):
		for y in range(GRID_DIMENSION):
			if grid_data[x][y] != null:
				projected_cells[Vector2i(x, y)] = true
	for offset in block_data.cells:
		projected_cells[Vector2i(origin_x + offset.x, origin_y + offset.y)] = true
	
	var rows_to_clear = []
	var cols_to_clear = []
	for y in range(GRID_DIMENSION):
		var row_full = true
		for x in range(GRID_DIMENSION):
			if not projected_cells.has(Vector2i(x, y)):
				row_full = false
				break
		if row_full:
			rows_to_clear.append(y)
	for x in range(GRID_DIMENSION):
		var col_full = true
		for y in range(GRID_DIMENSION):
			if not projected_cells.has(Vector2i(x, y)):
				col_full = false
				break
		if col_full:
			cols_to_clear.append(x)
	
	for x in cols_to_clear:
		for y in range(GRID_DIMENSION):
			_add_clear_preview_cell(x, y)
	for y in rows_to_clear:
		for x in range(GRID_DIMENSION):
			_add_clear_preview_cell(x, y)

func _add_clear_preview_cell(x: int, y: int):
	var cell_index = y * GRID_DIMENSION + x
	var cell_node = grid_container.get_child(cell_index) as GridCell
	if cell_node == null or _current_clear_preview_cells.has(cell_node):
		return
	cell_node.set_clear_preview(true)
	_current_clear_preview_cells.append(cell_node)
