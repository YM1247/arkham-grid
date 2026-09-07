extends SceneTree


func _init() -> void:
	var file := FileAccess.open("res://data/sanity.json", FileAccess.READ)
	if file == null:
		push_error("無法讀取 data/sanity.json")
		quit(1)
		return
	var document = JSON.parse_string(file.get_as_text())
	if not document is Dictionary:
		push_error("sanity.json 格式錯誤")
		quit(1)
		return
	var model: Dictionary = document.get("simulation", {})
	var start_sanity := 70
	var battles_before_rest := maxi(int(model.get("path_battles", 6)) - 1, 0)
	var magic_loss := battles_before_rest * int(model.get("magic_uses_per_battle", 2)) * 3
	var dead_board_loss := int(model.get("dead_boards_per_run", 1)) * 10
	var enemy_loss := int(model.get("enemy_sanity_hits_per_run", 2)) * int(model.get("enemy_sanity_hit", 6))
	var before_rest := start_sanity - magic_loss - dead_board_loss - enemy_loss
	var minimum := int(model.get("acceptance_min_sanity_before_rest", 15))
	var maximum := int(model.get("acceptance_max_sanity_before_rest", 55))
	print("SANITY SIMULATION")
	print("- 開始：", start_sanity)
	print("- 休息前戰鬥：", battles_before_rest)
	print("- 魔法損失：", magic_loss, "｜死盤：", dead_board_loss, "｜敵人：", enemy_loss)
	print("- 休息前：", before_rest, "｜驗收區間：", minimum, "–", maximum)
	if before_rest < minimum or before_rest > maximum:
		push_error("SANITY SIMULATION FAILED")
		quit(1)
	else:
		print("SANITY SIMULATION OK")
		quit(0)
