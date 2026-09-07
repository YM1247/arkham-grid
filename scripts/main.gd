extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_tablet_section_col_activated(col_index: int) -> void:
	$BattleManager.execute_col_effect(col_index)


func _on_tablet_section_row_activated(row_index: int) -> void:
	$BattleManager.execute_row_effect(row_index)
