extends VBoxContainer

signal row_activated(row_index: int)
signal col_activated(col_index: int)
signal spell_activated(spell: BattleItem, board_cell: Vector2i)
signal spell_announcement_requested(spell: BattleItem)
signal block_placed(block_data: BlockData)
signal no_valid_moves(penalty: int)
signal dead_board_warning_started
signal payment_preview_changed(spells: Array)

# --- 設定參數 ---
# 這裡的大小要跟 GridCell 的大小一致
const CELL_SIZE = Vector2(46, 46)
const GRID_DIMENSION = 8
const HAND_SLOT_SIZE := Vector2(420, 146)
const HAND_SLOT_SEPARATION := 50

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
@onready var hand_area = $Body/HandArea

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
var _dead_board_warning_active := false
var _is_resolving_clear := false
var _no_move_check_pending := false
var _keyboard_selected_block: Block
var _keyboard_origin := Vector2i(3, 3)
var _preview_entity: Entity

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
	grid_container.add_theme_constant_override("h_separation", 2)
	grid_container.add_theme_constant_override("v_separation", 2)
	$Header.visible = false
	row_icons_container.visible = false
	corner_spacer.custom_minimum_size = Vector2.ZERO
	hand_area.custom_minimum_size = Vector2(HAND_SLOT_SIZE.x, HAND_SLOT_SIZE.y * hand_size + HAND_SLOT_SEPARATION * max(hand_size - 1, 0))
	hand_area.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_area.add_theme_constant_override("separation", HAND_SLOT_SEPARATION)
	_ensure_hand_slots()
	
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
	# 盤面刻度已移除，僅保留獨立的石板桌與格子。
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
	var slot := _first_empty_hand_slot()
	if slot == null:
		block.queue_free()
		return null
	slot.add_child(block)
	block.set_data(data)
	block.set_preview_entity(_preview_entity)
	block.selection_requested.connect(_select_block)
	_refresh_hand_shortcuts()
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
	return selected

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
	_keyboard_selected_block = null
	for child in _get_hand_blocks():
		child.queue_free()


func _ensure_hand_slots() -> void:
	for index in range(hand_size):
		var slot := PanelContainer.new()
		slot.name = "HandSlot%d" % (index + 1)
		slot.custom_minimum_size = HAND_SLOT_SIZE
		slot.set_meta("hand_slot_index", index)
		slot.set_meta("hand_slot_height", HAND_SLOT_SIZE.y)
		slot.set_meta("hand_slot_is_last", index == hand_size - 1)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color(0, 0, 0, 0)
		style.set_border_width_all(0)
		style.set_corner_radius_all(0)
		slot.add_theme_stylebox_override("panel", style)
		hand_area.add_child(slot)


func _first_empty_hand_slot() -> Control:
	for slot in hand_area.get_children():
		var occupied := false
		for child in slot.get_children():
			if child is Block and not child.is_queued_for_deletion():
				occupied = true
				break
		if not occupied:
			return slot as Control
	return null


func _get_hand_blocks() -> Array[Block]:
	var blocks: Array[Block] = []
	for slot in hand_area.get_children():
		for child in slot.get_children():
			if child is Block and not child.is_queued_for_deletion():
				blocks.append(child)
	return blocks

func set_placement_enabled(enabled: bool):
	placement_enabled = enabled
	if not placement_enabled:
		_select_block(null)
		clear_preview()
	_sync_hand_drag_enabled()

func set_preview_entity(entity: Entity) -> void:
	_preview_entity = entity
	for block in _get_hand_blocks():
		block.set_preview_entity(entity)

func set_block_pool(new_block_pool: Array):
	block_pool.clear()
	for block_data in new_block_pool:
		if block_data is BlockData:
			block_pool.append(block_data)
	_bind_legacy_pools()


func set_spell_pool(new_spell_pool: Array) -> void:
	spell_pool.clear()
	for spell in new_spell_pool:
		if spell is BattleItem:
			spell_pool.append(spell)
	_bind_legacy_pools()


func set_slate_pool(new_slate_pool: Array) -> void:
	block_pool.clear()
	spell_pool.clear()
	for slate in new_slate_pool:
		if slate is BlockData and slate.spell != null and not slate.slate_uid.is_empty():
			block_pool.append(slate)
			spell_pool.append(slate.spell)


func add_slate(slate: BlockData) -> bool:
	if slate == null or slate.spell == null or slate.slate_uid.is_empty():
		return false
	for existing in block_pool:
		if existing is BlockData and (existing.slate_uid == slate.slate_uid or slate.is_special and existing.id == slate.id):
			return false
	block_pool.append(slate)
	spell_pool.append(slate.spell)
	return true


func get_slate_pool_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slate in block_pool:
		if slate is BlockData and slate.spell != null and not slate.slate_uid.is_empty():
			result.append(slate.to_slate_state())
	return result


func restore_slate_pool_state(states: Array, registry: ContentRegistry) -> bool:
	if registry == null:
		return false
	var restored := registry.create_slates(states)
	if restored.size() != states.size():
		return false
	set_slate_pool(restored)
	return true


func _bind_legacy_pools() -> void:
	if block_pool.is_empty() or spell_pool.is_empty():
		return
	var bound: Array[BlockData] = []
	for index in range(block_pool.size()):
		var shape := block_pool[index] as BlockData
		var spell := spell_pool[index % spell_pool.size()] as BattleItem
		if shape != null and spell != null:
			bound.append(shape.as_slate("legacy_%02d_%s_%s" % [index, shape.id, spell.content_id], spell, Vector2i.ZERO))
	block_pool.assign(bound)


func add_spell_to_pool(spell: BattleItem) -> void:
	push_warning("add_spell_to_pool 已由 add_slate 取代；忽略未綁定咒文 %s。" % (spell.content_id if spell != null else ""))


func get_spell_pool_ids() -> Array[String]:
	var ids: Array[String] = []
	for spell in spell_pool:
		if spell != null:
			ids.append(spell.content_id)
	return ids

func add_block_to_pool(block_data: BlockData):
	push_warning("add_block_to_pool 已由 add_slate 取代；忽略未綁定形狀 %s。" % (block_data.id if block_data != null else ""))

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
			child.set_empty_color()
			child.set_spell(null)
			child.reset_color()
	if seed_board_on_start:
		_seed_friendly_board()
	draw_new_hand()

# --- 邏輯判斷區 (大腦) ---

# 檢查是否可以放置
func check_placement_valid(origin_x: int, origin_y: int, block_data: BlockData) -> bool:
	return placement_enabled and not _is_resolving_clear and block_data != null and board_model.can_place(origin_x, origin_y, block_data.cells)


func preview_drop_at_cell(grid_x: int, grid_y: int, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("block_data"):
		return false
	var block := data["block_data"] as BlockData
	var offset: Vector2i = data.get("grab_offset", Vector2i.ZERO)
	var origin := Vector2i(grid_x, grid_y) - offset
	var valid := check_placement_valid(origin.x, origin.y, block)
	update_preview(origin.x, origin.y, block, valid)
	return valid


func commit_drop_at_cell(grid_x: int, grid_y: int, data) -> void:
	if typeof(data) != TYPE_DICTIONARY or not data.has("block_data"):
		return
	var block := data["block_data"] as BlockData
	var offset: Vector2i = data.get("grab_offset", Vector2i.ZERO)
	var origin := Vector2i(grid_x, grid_y) - offset
	if check_placement_valid(origin.x, origin.y, block):
		place_block(origin.x, origin.y, block, data.get("source_block"))

# 【新增】更新預覽狀態 (被 GridCell 呼叫)
func update_preview(origin_x: int, origin_y: int, block_data: BlockData, is_valid: bool):
	# 1. 無論如何，先清除上一次的預覽狀態
	clear_preview()
	
	# 2. 合法位置顯示亮色，不合法位置以紅色保留輪廓回饋。
	for offset in block_data.cells:
		var target_x = origin_x + offset.x
		var target_y = origin_y + offset.y
		if target_x < 0 or target_x >= GRID_DIMENSION or target_y < 0 or target_y >= GRID_DIMENSION:
			continue
		
		# 找到對應的格子節點
		var cell_index = target_y * GRID_DIMENSION + target_x
		var cell_node = grid_container.get_child(cell_index) as GridCell
		
		# 開啟高亮
		cell_node.set_placement_preview(true, is_valid)
		# 加入追蹤陣列
		_current_preview_cells.append(cell_node)
	
	if is_valid:
		_update_clear_line_preview(origin_x, origin_y, block_data)

# 【新增】清除所有預覽
func clear_preview():
	for cell in _current_preview_cells:
		cell.set_placement_preview(false, true)
	_current_preview_cells.clear()
	for cell in _current_clear_preview_cells:
		cell.set_clear_preview(false)
	_current_clear_preview_cells.clear()
	payment_preview_changed.emit([])

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
		cell_node.set_slate_color(block_data.color)
		if offset == block_data.effect_cell and block_data.spell != null:
			grid_spells[target_x][target_y] = block_data.spell
			cell_node.set_spell(block_data.spell)
	
	block_placed.emit(block_data)
	if source_block != null:
		if source_block == _keyboard_selected_block:
			_keyboard_selected_block = null
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
	_is_resolving_clear = true
	_sync_hand_drag_enabled()
	await _execute_clear(rows_to_clear, cols_to_clear)
	_is_resolving_clear = false
	_sync_hand_drag_enabled()

func _execute_clear(rows: Array, cols: Array):
	# --- 階段 1: 收集本次消除範圍，資料與畫面都先保持原狀 ---
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

	# 先保存效果格內容；盤面消失後仍能依原本的固定 Col→Row 順序結算。
	var spells_to_trigger: Array[Dictionary] = []
	for coord in cells_to_clear:
		var spell := grid_spells[coord.x][coord.y] as BattleItem
		if spell != null:
			spells_to_trigger.append({"spell": spell, "coord": coord})

	# --- 階段 2: 全體同步閃白 ---
	for coord in cells_to_clear:
		_play_flash_effect(coord.x, coord.y)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.32).timeout

	# --- 階段 3: 先清除資料與畫面 ---
	for coord in cells_to_clear:
		_clear_cell_data(coord.x, coord.y)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.08).timeout

	# --- 階段 4: 棋格消失後，再逐一播放咒文名稱並結算效果 ---
	for trigger in spells_to_trigger:
		var spell := trigger.get("spell") as BattleItem
		var coord: Vector2i = trigger.get("coord", Vector2i.ZERO)
		if DisplayServer.get_name() != "headless":
			spell_announcement_requested.emit(spell)
			await get_tree().create_timer(0.62).timeout
		spell_activated.emit(spell, coord)
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.18).timeout

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
	
	cell_node.set_empty_color()
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
			if value is Color:
				cell_node.set_slate_color(value)
			else:
				cell_node.set_empty_color()
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
	for child in _get_hand_blocks():
		if child.is_queued_for_deletion() or not "block_data" in child or not child.block_data is BlockData:
			continue
		state.append({
			"slate_uid": child.block_data.slate_uid,
			"rotation_steps": child.block_data.get_rotation_steps(),
		})
	return state


func restore_hand(blocks: Array[BlockData]) -> void:
	_clear_hand()
	for block_data in blocks:
		_spawn_block(block_data)
	_sync_hand_drag_enabled()

func restore_hand_state(state: Array, _resources: Dictionary = {}) -> void:
	_clear_hand()
	for value in state:
		if not value is Dictionary:
			continue
		var base := _find_slate_in_pool(str(value.get("slate_uid", "")))
		if base != null:
			var restored := base.rotated(int(value.get("rotation_steps", 0)))
			_spawn_block(restored)
	_sync_hand_drag_enabled()


func _find_slate_in_pool(uid: String) -> BlockData:
	for slate in block_pool:
		if slate is BlockData and slate.slate_uid == uid:
			return slate
	return null


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
	return _get_hand_blocks().size()

func _sync_hand_drag_enabled():
	for child in _get_hand_blocks():
		child.set_drag_enabled(placement_enabled and not _is_resolving_clear and not _is_recovering_from_no_moves)
	_refresh_hand_shortcuts()


func _unhandled_input(event: InputEvent) -> void:
	if not placement_enabled or _is_resolving_clear or _is_recovering_from_no_moves or not event.is_pressed() or event.is_echo():
		return
	for index in range(3):
		if event.is_action_pressed("hand_slot_%d" % [index + 1]):
			_select_hand_index(index)
			get_viewport().set_input_as_handled()
			return
	if _keyboard_selected_block == null or not is_instance_valid(_keyboard_selected_block):
		return
	var handled := true
	if event.is_action_pressed("board_left"):
		_keyboard_origin.x = maxi(_keyboard_origin.x - 1, 0)
	elif event.is_action_pressed("board_right"):
		_keyboard_origin.x = mini(_keyboard_origin.x + 1, GRID_DIMENSION - 1)
	elif event.is_action_pressed("board_up"):
		_keyboard_origin.y = maxi(_keyboard_origin.y - 1, 0)
	elif event.is_action_pressed("board_down"):
		_keyboard_origin.y = mini(_keyboard_origin.y + 1, GRID_DIMENSION - 1)
	elif event.is_action_pressed("place_selected"):
		if check_placement_valid(_keyboard_origin.x, _keyboard_origin.y, _keyboard_selected_block.block_data):
			var selected := _keyboard_selected_block
			_keyboard_selected_block = null
			place_block(_keyboard_origin.x, _keyboard_origin.y, selected.block_data, selected)
		else:
			_update_keyboard_preview()
	elif event.is_action_pressed("cancel_selection"):
		_select_block(null)
	else:
		handled = false
	if handled:
		_update_keyboard_preview()
		get_viewport().set_input_as_handled()


func _select_hand_index(index: int) -> void:
	if index < 0 or index >= hand_area.get_child_count():
		return
	var slot := hand_area.get_child(index)
	for child in slot.get_children():
		if child is Block and not child.is_queued_for_deletion():
			_select_block(child)
			return


func _select_block(block: Block) -> void:
	if _keyboard_selected_block != null and is_instance_valid(_keyboard_selected_block):
		_keyboard_selected_block.set_keyboard_selected(false)
	_keyboard_selected_block = block
	clear_preview()
	if block == null:
		return
	block.set_keyboard_selected(true)
	_keyboard_origin = _find_keyboard_origin(block.block_data)
	_update_keyboard_preview()


func _find_keyboard_origin(block_data: BlockData) -> Vector2i:
	var preferred := Vector2i(3, 3)
	if check_placement_valid(preferred.x, preferred.y, block_data):
		return preferred
	for y in range(GRID_DIMENSION):
		for x in range(GRID_DIMENSION):
			if check_placement_valid(x, y, block_data):
				return Vector2i(x, y)
	return preferred


func _update_keyboard_preview() -> void:
	if _keyboard_selected_block == null or not is_instance_valid(_keyboard_selected_block):
		clear_preview()
		return
	var data := _keyboard_selected_block.block_data
	update_preview(_keyboard_origin.x, _keyboard_origin.y, data, check_placement_valid(_keyboard_origin.x, _keyboard_origin.y, data))


func _refresh_hand_shortcuts() -> void:
	for slot_index in range(hand_area.get_child_count()):
		for child in hand_area.get_child(slot_index).get_children():
			if child is Block and not child.is_queued_for_deletion():
				child.set_shortcut_number(slot_index + 1)



func _check_no_valid_moves_deferred():
	if _is_recovering_from_no_moves or _is_resolving_clear or _no_move_check_pending or not placement_enabled:
		return
	_no_move_check_pending = true
	call_deferred("_handle_no_valid_moves_if_needed")

func _handle_no_valid_moves_if_needed():
	_no_move_check_pending = false
	if _is_recovering_from_no_moves or _is_resolving_clear or not placement_enabled:
		return
	if block_pool.is_empty() or _get_active_hand_block_data().is_empty():
		return
	if _has_any_valid_move():
		return
	print("盤面無任何可放置方塊，觸發 Sanity 懲罰：", no_valid_moves_sanity_penalty)
	_is_recovering_from_no_moves = true
	clear_preview()
	_sync_hand_drag_enabled()
	# 保留一小段辨識時間，再以斜向紅色脈衝提示死盤；動畫完成後才結算 Sanity。
	await get_tree().create_timer(0.22).timeout
	await _play_dead_board_warning()
	no_valid_moves.emit(no_valid_moves_sanity_penalty)
	await get_tree().create_timer(0.16).timeout
	_clear_board_cells()
	if seed_board_on_start:
		_seed_friendly_board()
	draw_new_hand()
	_is_recovering_from_no_moves = false
	_sync_hand_drag_enabled()


func _play_dead_board_warning() -> void:
	_dead_board_warning_active = true
	dead_board_warning_started.emit()
	for index in range(grid_container.get_child_count()):
		var cell := grid_container.get_child(index) as GridCell
		if cell == null:
			continue
		var x := index % GRID_DIMENSION
		var y := index / GRID_DIMENSION
		var tween := create_tween()
		tween.tween_interval(float(x + y) * 0.018)
		tween.tween_property(cell, "dead_board_warning_intensity", 1.0, 0.1)
		tween.tween_property(cell, "dead_board_warning_intensity", 0.42, 0.14)
		tween.tween_property(cell, "dead_board_warning_intensity", 0.0, 0.2)
	await get_tree().create_timer(0.72).timeout
	for child in grid_container.get_children():
		if child is GridCell:
			child.dead_board_warning_intensity = 0.0
	_dead_board_warning_active = false

func _has_any_valid_move() -> bool:
	for block_data in _get_active_hand_block_data():
		for origin_x in range(GRID_DIMENSION):
			for origin_y in range(GRID_DIMENSION):
				if check_placement_valid(origin_x, origin_y, block_data):
					return true
	return false

func _get_active_hand_block_data() -> Array[BlockData]:
	var hand_blocks: Array[BlockData] = []
	for child in _get_hand_blocks():
		if child.block_data is BlockData:
			hand_blocks.append(child.block_data)
	return hand_blocks

func _clear_board_cells():
	_init_grid_data()
	for child in grid_container.get_children():
		if child is GridCell:
			child.set_empty_color()
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
	cell_node.set_slate_color(color)
	cell_node.reset_color()

func _get_row_slot_label(index: int, item: BattleItem) -> String:
	return char(65 + index)

func _get_col_slot_label(index: int, item: BattleItem) -> String:
	return str(index + 1)

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

	var spells_to_trigger: Array = []
	var seen_cells := {}
	var placed_effect_cell := Vector2i(origin_x, origin_y) + block_data.effect_cell
	for x in cols_to_clear:
		for y in range(GRID_DIMENSION):
			_collect_preview_spell(Vector2i(x, y), placed_effect_cell, block_data, seen_cells, spells_to_trigger)
	for y in rows_to_clear:
		for x in range(GRID_DIMENSION):
			_collect_preview_spell(Vector2i(x, y), placed_effect_cell, block_data, seen_cells, spells_to_trigger)
	payment_preview_changed.emit(spells_to_trigger)


func _collect_preview_spell(coord: Vector2i, placed_effect_cell: Vector2i, block_data: BlockData, seen_cells: Dictionary, output: Array) -> void:
	if seen_cells.has(coord):
		return
	seen_cells[coord] = true
	var spell := block_data.spell if coord == placed_effect_cell else grid_spells[coord.x][coord.y] as BattleItem
	if spell != null:
		output.append(spell)

func _add_clear_preview_cell(x: int, y: int):
	var cell_index = y * GRID_DIMENSION + x
	var cell_node = grid_container.get_child(cell_index) as GridCell
	if cell_node == null or _current_clear_preview_cells.has(cell_node):
		return
	cell_node.set_clear_preview(true)
	_current_clear_preview_cells.append(cell_node)
