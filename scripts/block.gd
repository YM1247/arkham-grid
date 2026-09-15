extends Control
class_name Block

const SpellRuneBadgeScript = preload("res://scripts/ui/spell_rune_badge.gd")

signal selection_requested(block: Block)

# --- 設定 ---
# 這裡的大小必須跟你的棋盤格子一樣大，不然會對不齊
const CELL_SIZE = Vector2(46, 46)
const SPACING = 4
const HAND_CELL_SCALE := 0.72
const HAND_VISUAL_CENTER := Vector2(75, 72)

# 存方塊的資料
var block_data: BlockData
var centering_offset = Vector2(CELL_SIZE.x + SPACING, CELL_SIZE.y + SPACING)
var drag_enabled := true
var keyboard_selected := false
var shortcut_number := 0
var preview_entity: Entity
var render_cell_size := CELL_SIZE
var render_stride := CELL_SIZE + Vector2(SPACING, SPACING)
var render_origin := Vector2(8, 8)
var render_min_cell := Vector2i.ZERO

# --- 初始化 ---
func set_data(data: BlockData):
	block_data = data
	tooltip_text = block_data.spell.get_effect_tooltip("此方塊的咒文") if block_data != null and block_data.spell != null else ""
	_redraw_shape()
	queue_redraw()


func set_shortcut_number(value: int) -> void:
	shortcut_number = value
	_redraw_shape()

func set_preview_entity(value: Entity) -> void:
	preview_entity = value
	_redraw_shape()


func set_keyboard_selected(active: bool) -> void:
	keyboard_selected = active
	modulate = Color.WHITE if active else Color(1, 1, 1, 1 if drag_enabled else 0.45)
	queue_redraw()

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
	var min_cell := block_data.cells[0]
	var max_cell := min_cell
	for coord in block_data.cells:
		min_cell.x = mini(min_cell.x, coord.x)
		min_cell.y = mini(min_cell.y, coord.y)
		max_cell.x = maxi(max_cell.x, coord.x)
		max_cell.y = maxi(max_cell.y, coord.y)
	render_min_cell = min_cell
	var dimensions := max_cell - min_cell + Vector2i.ONE
	# 所有形狀共用同一格子比例；卡片改用橫向空間容納文字，避免形狀忽大忽小。
	var scale_factor := HAND_CELL_SCALE
	render_cell_size = CELL_SIZE * scale_factor
	render_stride = (CELL_SIZE + Vector2(SPACING, SPACING)) * scale_factor
	var visual_width := float(dimensions.x) * render_cell_size.x + float(dimensions.x - 1) * SPACING * scale_factor
	var visual_height := float(dimensions.y) * render_cell_size.y + float(dimensions.y - 1) * SPACING * scale_factor
	render_origin = HAND_VISUAL_CENTER - Vector2(visual_width, visual_height) * 0.5
		
	for cell_pos in block_data.cells:
		var rect = ColorRect.new()
		rect.size = render_cell_size
		rect.color = block_data.color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 
		
		# 【修改】繪製位置加上偏移量
		# 這樣 (0,0) 就會畫在 Control 的 (70, 70) 位置，而 (0,-1) 會畫在 (70, 0) 位置 -> 都在範圍內了！
		rect.position = Vector2(cell_pos - render_min_cell) * render_stride + render_origin
		
		add_child(rect)
		rect.set_meta("shape_visual", true)
		if block_data.spell != null and cell_pos == block_data.effect_cell:
			var rune: Control = SpellRuneBadgeScript.new()
			rune.size = render_cell_size - Vector2(6, 6) * scale_factor
			rune.position = rect.position + Vector2(3, 3) * scale_factor
			rune.configure(block_data.spell)
			add_child(rune)
			rune.set_meta("shape_visual", true)

	var name_label := Label.new()
	name_label.position = Vector2(140, 17)
	name_label.size = Vector2(136, 28)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.text = "%d　%s" % [shortcut_number, block_data.spell.spell_name] if shortcut_number > 0 and block_data.spell != null else block_data.spell.spell_name if block_data.spell != null else "空白石板"
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", block_data.spell.get_icon_color() if block_data.spell != null else Color.WHITE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)
	var detail_label := Label.new()
	detail_label.position = Vector2(140, 47)
	detail_label.size = Vector2(136, 82)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.text = "%s｜MP %d\n%s" % [block_data.spell.get_category_label(), block_data.spell.mp_cost, block_data.spell.get_runtime_summary(preview_entity)] if block_data.spell != null else "無咒文"
	detail_label.add_theme_font_size_override("font_size", 11)
	detail_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(detail_label)
	
	# 【建議】把最小尺寸設大一點，確保能包住位移後的方塊 (3x3 格子約 220x220)
	custom_minimum_size = Vector2(280, 146)


func _draw() -> void:
	if keyboard_selected:
		draw_style_box(_selection_style(), Rect2(Vector2.ZERO, size))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and drag_enabled:
		selection_requested.emit(self)

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		scale = Vector2.ONE
		_set_shape_visible(true)

func _get_drag_data(at_position):
	if block_data == null or not drag_enabled:
		return null
	
	# 【修改】計算抓取座標時，要把偏移量「扣回來」
	# 這樣我們算出來的 grab_offset 才會變回正確的邏輯座標 (例如 0, -1)
	var adjusted_pos = at_position - render_origin
	
	# 使用 floor() 確保負數除法運算正確 (例如 -35 / 70 應該是 -1 而不是 0)
	var grab_idx_x = floor(adjusted_pos.x / render_stride.x)
	var grab_idx_y = floor(adjusted_pos.y / render_stride.y)
	var grab_offset = Vector2i(grab_idx_x, grab_idx_y) + render_min_cell
	
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
	
	# 手牌可能為了側欄縮小；拖曳時重新以棋盤的原始格尺寸繪製，
	# 避免沿用手牌縮放後的格子與符文尺寸。
	var preview_wrapper := _build_drag_preview(at_position, grab_offset)
	set_drag_preview(preview_wrapper)
	_set_shape_visible(false)
	
	return data_packet


func _build_drag_preview(at_position: Vector2, grab_offset: Vector2i) -> Control:
	var wrapper := Control.new()
	var selected_render_position := Vector2(grab_offset - render_min_cell) * render_stride + render_origin
	var within_selected := Vector2(0.5, 0.5)
	if render_cell_size.x > 0.0 and render_cell_size.y > 0.0:
		within_selected = (at_position - selected_render_position) / render_cell_size
		within_selected.x = clampf(within_selected.x, 0.0, 1.0)
		within_selected.y = clampf(within_selected.y, 0.0, 1.0)
	var full_stride := CELL_SIZE + Vector2(SPACING, SPACING)
	var cursor_offset := within_selected * CELL_SIZE
	for cell_pos in block_data.cells:
		var cell_position := Vector2(cell_pos - grab_offset) * full_stride - cursor_offset
		var rect := ColorRect.new()
		rect.position = cell_position
		rect.size = CELL_SIZE
		rect.color = block_data.color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(rect)
		if block_data.spell != null and cell_pos == block_data.effect_cell:
			var rune: Control = SpellRuneBadgeScript.new()
			rune.position = cell_position + Vector2(3, 3)
			rune.size = CELL_SIZE - Vector2(6, 6)
			rune.configure(block_data.spell)
			wrapper.add_child(rune)
	return wrapper

func _set_shape_visible(is_visible: bool) -> void:
	for child in get_children():
		if child.has_meta("shape_visual"):
			child.visible = is_visible


func _selection_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.72, 0.36, 0.08)
	style.border_color = Color("f7d889")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	return style
