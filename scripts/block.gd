extends Control
class_name Block

# --- 設定 ---
# 這裡的大小必須跟你的棋盤格子一樣大，不然會對不齊
const CELL_SIZE = Vector2(70, 70) 
const SPACING = 4

# 存方塊的資料
var block_data: BlockData
var centering_offset = Vector2(CELL_SIZE.x + SPACING, CELL_SIZE.y + SPACING)
var drag_enabled := true

# --- 初始化 ---
func set_data(data: BlockData):
	block_data = data
	tooltip_text = block_data.spell.get_effect_tooltip("此方塊的咒文") if block_data != null and block_data.spell != null else ""
	_redraw_shape()

func set_drag_enabled(enabled: bool):
	drag_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if drag_enabled else Control.MOUSE_FILTER_IGNORE
	modulate.a = 1.0 if drag_enabled else 0.45
	scale = Vector2.ONE
	_set_shape_visible(true)

# --- 繪圖邏輯 ---
func _redraw_shape():
	for child in get_children():
		child.queue_free()
	
	if block_data == null:
		return
		
	for cell_pos in block_data.cells:
		var rect = ColorRect.new()
		rect.size = CELL_SIZE
		rect.color = block_data.color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 
		
		# 【修改】繪製位置加上偏移量
		# 這樣 (0,0) 就會畫在 Control 的 (70, 70) 位置，而 (0,-1) 會畫在 (70, 0) 位置 -> 都在範圍內了！
		rect.position = (Vector2(cell_pos) * (CELL_SIZE + Vector2(SPACING, SPACING))) + centering_offset
		
		add_child(rect)
		if block_data.spell != null and cell_pos == block_data.effect_cell:
			var rune := Label.new()
			rune.text = block_data.spell.icon_text
			rune.tooltip_text = block_data.spell.get_effect_tooltip("方塊咒文")
			rune.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rune.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rune.add_theme_font_size_override("font_size", 30)
			rune.add_theme_color_override("font_color", block_data.spell.get_icon_color())
			rune.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rune.size = CELL_SIZE
			rune.position = rect.position
			add_child(rune)
	
	# 【建議】把最小尺寸設大一點，確保能包住位移後的方塊 (3x3 格子約 220x220)
	custom_minimum_size = Vector2(230, 230)

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		scale = Vector2.ONE
		_set_shape_visible(true)

func _get_drag_data(at_position):
	if block_data == null or not drag_enabled:
		return null
	
	# 【修改】計算抓取座標時，要把偏移量「扣回來」
	# 這樣我們算出來的 grab_offset 才會變回正確的邏輯座標 (例如 0, -1)
	var adjusted_pos = at_position - centering_offset
	
	# 使用 floor() 確保負數除法運算正確 (例如 -35 / 70 應該是 -1 而不是 0)
	var grab_idx_x = floor(adjusted_pos.x / (CELL_SIZE.x + SPACING))
	var grab_idx_y = floor(adjusted_pos.y / (CELL_SIZE.y + SPACING))
	var grab_offset = Vector2i(grab_idx_x, grab_idx_y)
	
	# 空氣牆檢查
	if not block_data.cells.has(grab_offset):
		return null
	
	print("開始拖曳: ", block_data.id)
	scale = Vector2(1.06, 1.06)
	
	var data_packet = {
		"block_data": block_data,
		"grab_offset": grab_offset,
		"source_block": self
	}
	
	# --- 預覽圖 ---
	var preview_wrapper = Control.new()
	var visual_content = Control.new()
	for child in get_children():
		if child is ColorRect or child is Label:
			var dup = child.duplicate()
			visual_content.add_child(dup)
	
	visual_content.modulate.a = 1
	
	# 【修改】預覽圖的位置也要修正
	# at_position 是滑鼠在 Block 裡的位置 (包含偏移)
	# 我們要把 visual_content 往回推，讓滑鼠對準抓取點
	visual_content.position = -at_position
	
	preview_wrapper.add_child(visual_content)
	set_drag_preview(preview_wrapper)
	_set_shape_visible(false)
	
	return data_packet

func _set_shape_visible(is_visible: bool) -> void:
	for child in get_children():
		if child is ColorRect or child is Label:
			child.visible = is_visible
