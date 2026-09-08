extends ColorRect
class_name GridCell

var grid_x: int
var grid_y: int
var manager: Node

# 紀錄原本的顏色，用於復原
var original_color: Color
var spell_marker: Label

func init(x, y, m_manager):
	grid_x = x
	grid_y = y
	manager = m_manager
	original_color = color # 記住初始顏色 (深灰色)
	spell_marker = Label.new()
	spell_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	spell_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spell_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	spell_marker.add_theme_font_size_override("font_size", 28)
	spell_marker.add_theme_color_override("font_color", Color(0.95, 0.9, 0.35))
	spell_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spell_marker)
	
	# (除錯 Label 這裡省略，你可以保留你的)

# --- 新增：預覽相關功能 ---

# 開啟高亮 (變亮一點)
func set_highlight(active: bool):
	if active:
		# 利用 modulate 讓顏色變亮 (疊加白色)
		modulate = Color(1.5, 1.5, 1.5, 1.0)
	else:
		# 恢復正常亮度
		modulate = Color(1, 1, 1, 1)

func set_clear_preview(active: bool):
	if active:
		modulate = Color(2.4, 2.1, 0.8, 1.0)
	else:
		modulate = Color(1, 1, 1, 1)

# 重置顏色 (變回原本的深灰色或被佔用的顏色)
func reset_color():
	color = original_color
	set_highlight(false)


func set_spell(spell: BattleItem) -> void:
	if spell_marker == null:
		return
	spell_marker.text = spell.icon_text if spell != null else ""
	if spell != null:
		spell_marker.add_theme_color_override("font_color", spell.get_icon_color())
	tooltip_text = spell.get_effect_tooltip("盤面咒文") if spell != null else ""

# --- 核心互動邏輯更新 ---

func _can_drop_data(_at_position, data):
	# 檢查 data 是否為我們剛剛打包的 Dictionary
	if typeof(data) == TYPE_DICTIONARY and data.has("block_data"):
		
		var block = data["block_data"]
		var offset = data["grab_offset"]
		
		# 【重點】校正座標
		# 如果我抓著 (1,0) 的位置指著這裡 (grid_x, grid_y)
		# 那方塊真正的原點 (0,0) 應該是在 (grid_x - 1, grid_y - 0)
		var true_origin_x = grid_x - offset.x
		var true_origin_y = grid_y - offset.y
		
		# 呼叫 Manager 時，傳入校正後的座標
		var is_valid = manager.check_placement_valid(true_origin_x, true_origin_y, block)
		manager.update_preview(true_origin_x, true_origin_y, block, is_valid)
		
		return is_valid
		
	return false

func _drop_data(_at_position, data):
	if typeof(data) == TYPE_DICTIONARY and data.has("block_data"):
		var block = data["block_data"]
		var offset = data["grab_offset"]
		var source_block = data.get("source_block")
		
		# 同樣校正座標
		var true_origin_x = grid_x - offset.x
		var true_origin_y = grid_y - offset.y
		
		manager.place_block(true_origin_x, true_origin_y, block, source_block)
