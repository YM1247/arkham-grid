class_name BlockData extends Resource

# 方塊的唯一 ID (例如 "shape_L")
@export var id: String
@export var display_name: String = ""
# 方塊顯示的顏色
@export var color: Color = Color.ORANGE
# 核心資料：用座標來定義形狀
# 以 (0, 0) 為中心抓取點
@export var cells: Array[Vector2i] = [Vector2i(0, 0)]
@export var tier: int = 1
@export var weight: float = 1.0
@export var tags: Array[String] = []
@export var is_special: bool = false
@export_range(1, 4) var complexity: int = 1
@export var smart_score_bonus: int = 0
@export var spell: BattleItem
@export var effect_cell: Vector2i = Vector2i(0, 0)


func rotated(steps: int) -> BlockData:
	var normalized_steps := posmod(steps, 4)
	var result := duplicate(true) as BlockData
	var rotated_cells: Array[Vector2i] = cells.duplicate()
	var rotated_effect_cell := effect_cell
	for _step in range(normalized_steps):
		for i in range(rotated_cells.size()):
			var cell := rotated_cells[i]
			rotated_cells[i] = Vector2i(-cell.y, cell.x)
		rotated_effect_cell = Vector2i(-rotated_effect_cell.y, rotated_effect_cell.x)
	result.cells = rotated_cells
	result.effect_cell = rotated_effect_cell
	result.set_meta("rotation_steps", normalized_steps)
	return result


func with_spell(value: BattleItem, marked_cell: Vector2i) -> BlockData:
	var result := duplicate(true) as BlockData
	result.spell = value
	result.effect_cell = marked_cell
	return result


func get_rotation_steps() -> int:
	return int(get_meta("rotation_steps", 0))
