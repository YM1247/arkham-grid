extends SceneTree

const EquipmentGrowthServiceScript = preload("res://scripts/growth/equipment_growth_service.gd")
const EncounterDifficultyCalculatorScript = preload("res://scripts/growth/encounter_difficulty_calculator.gd")
const RewardCandidateSelectorScript = preload("res://scripts/growth/reward_candidate_selector.gd")
const FriendlyBoardGeneratorScript = preload("res://scripts/board/friendly_board_generator.gd")
const RunStateMachineScript = preload("res://scripts/run/run_state_machine.gd")
const RunNodeResultScript = preload("res://scripts/run/run_node_result.gd")
const LayeredMapGeneratorScript = preload("res://scripts/run/layered_map_generator.gd")
const SanityRuleEngineScript = preload("res://scripts/sanity/sanity_rule_engine.gd")
const BoardSimulatorScript = preload("res://scripts/board/board_simulator.gd")
const BattleBatchSimulatorScript = preload("res://scripts/battle/battle_batch_simulator.gd")
const RunPressureSimulatorScript = preload("res://scripts/run/run_pressure_simulator.gd")
const EventChoiceResolverScript = preload("res://scripts/run/event_choice_resolver.gd")
const SaveGameServiceScript = preload("res://scripts/save/save_game_service.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_content_registry()
	_test_run_state_round_trip()
	_test_phase_18_save_foundation()
	_test_board_model()
	_test_enemy_intents_and_speed()
	_test_target_resolver()
	_test_status_timing_and_outcomes()
	_test_phase_13_growth_and_rewards()
	_test_phase_14_run_foundation()
	_test_phase_15_sanity_rules()
	_test_phase_16_content_integrity()
	_test_phase_16_data_driven_events()
	_test_phase_16_board_simulation()
	_test_phase_16_battle_batch()
	_test_phase_19_full_run_pressure()
	await _test_five_enemy_roster()
	await _test_drag_source_visibility()
	await _test_main_scene_smoke()
	if failures.is_empty():
		print("TESTS OK (18 suites)")
		quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILED: %s" % failure)
		quit(1)


func _test_content_registry() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "ContentRegistry 應載入並驗證全部資料：%s" % [registry.errors])
	_expect(registry.get_entries("blocks").size() == 11, "應索引 11 種方塊")
	_expect(registry.get_entries("intents").size() == 6, "應索引 6 種敵人意圖")
	_expect(registry.get_definition("enemies", "abyss_thrall").get("hp") == 30.0, "應可依 ID 查詢敵人")
	_expect(registry.get_block("shape_L") != null, "應建立 BlockData runtime Resource")
	_expect(registry.get_item("pistol") != null, "應建立 BattleItem runtime Resource")
	_expect(registry.get_item("pistol") is EffectAttack, "attack JSON 應使用 attack.tres 行為")
	_expect(registry.get_item("burst_pistol") is EffectConditionalAttack, "conditional_attack JSON 應使用 conditional_attack.tres 行為")
	_expect(registry.get_item("vest") is EffectSupport, "support JSON 應使用 support.tres 行為")
	_expect(registry.get_item("poison_spell") is EffectStatus, "status JSON 應使用 status.tres 行為")
	_expect(registry.get_item("pistol").axis_type == BattleItem.AxisType.PHYSICAL, "Row 道具應使用 physical axis_type")
	_expect(registry.get_item("dark_spike").axis_type == BattleItem.AxisType.MAGIC, "Col 道具應使用 magic axis_type")
	var conditional := registry.get_item("burst_pistol") as EffectConditionalAttack
	var target := _make_entity("條件目標", 30)
	var user := _make_entity("使用者", 30)
	var context := BattleEffectContext.new()
	context.weapon_trigger_count = 1
	conditional.execute_with_context(target, user, context)
	_expect(target.hp == 16, "條件攻擊應從效果上下文讀取武器觸發紀錄")
	target.free()
	user.free()


func _test_run_state_round_trip() -> void:
	var original := RunState.new()
	original.seed = 4242
	original.hp = 51
	original.board_cells.resize(64)
	original.board_cells.fill("")
	original.board_cells[7] = "ff0000ff"
	original.hand_ids = ["shape_L", "shape_T"]
	original.hand_state = [{"id": "shape_L", "rotation_steps": 2}, {"id": "shape_T", "rotation_steps": 0}]
	original.block_pool_ids = ["shape_L"]
	original.row_item_ids = ["pistol"]
	original.selected_reward_ids = ["special_dot"]
	original.item_inventory = {"pistol": 2}
	original.currency = 20
	original.battle_reports = [{"turns": 3}]
	original.flow_state = 2
	original.current_node_id = "event_archive"
	original.completed_node_ids = ["start_a"]
	original.available_node_ids = ["event_archive"]
	original.map_data = {"map_id": "saved_map", "nodes": []}
	original.reward_rng_state = "123456789"
	original.tablet_rng_state = "987654321"
	var restored := RunState.from_dict(original.to_dict())
	_expect(restored != null, "RunState 應可反序列化")
	_expect(restored.seed == 4242 and restored.hp == 51, "RunState 應保留玩家與種子")
	_expect(restored.board_cells[7] == "ff0000ff", "RunState 應保留盤面")
	_expect(restored.hand_ids == original.hand_ids, "RunState 應保留手牌 ID")
	_expect(restored.hand_state == original.hand_state, "RunState 應保留手牌旋轉狀態")
	_expect(restored.item_inventory.get("pistol") == 2 and restored.currency == 20, "RunState 應保留背包與局內金錢")
	_expect(restored.battle_reports.size() == 1, "RunState 應保留戰鬥統計")
	_expect(restored.flow_state == 2 and restored.current_node_id == "event_archive", "RunState 應保留流程與目前節點")
	_expect(restored.available_node_ids == ["event_archive"] and restored.map_data.get("map_id") == "saved_map", "RunState 應保留生成地圖與可選節點")
	_expect(restored.reward_rng_state == "123456789" and restored.tablet_rng_state == "987654321", "RunState 應保留獎勵與抽牌 RNG 狀態")


func _test_phase_18_save_foundation() -> void:
	var test_directory := "/tmp/arkham_grid_test_saves_%d" % Time.get_ticks_usec()
	var service = SaveGameServiceScript.new(test_directory)
	var first := RunState.new()
	first.seed = 424242
	first.hp = 61
	first.reward_rng_state = "12345"
	first.tablet_rng_state = "67890"
	_expect(service.save_run(first, "node_completed"), "Run 自動存檔應可寫入：%s" % service.last_error)
	_expect(not FileAccess.file_exists(service.get_temp_path()), "成功保存後不應殘留暫存檔")
	var loaded: Dictionary = service.load_run()
	_expect(loaded.get("ok", false), "主存檔應可載入：%s" % loaded.get("error", ""))
	if loaded.get("state") is RunState:
		_expect(loaded.state.hp == 61 and loaded.state.reward_rng_state == "12345", "磁碟 round-trip 應保留 Run 與 RNG 狀態")
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.state = int(first.reward_rng_state)
		var restored_rng := RandomNumberGenerator.new()
		restored_rng.state = int(loaded.state.reward_rng_state)
		_expect(expected_rng.randi() == restored_rng.randi(), "讀檔後的下一個隨機結果應與不中斷流程一致")
	var second := RunState.from_dict(first.to_dict())
	second.hp = 40
	_expect(service.save_run(second, "node_entered"), "第二次保存應輪替 last-known-good 備份")
	_expect(FileAccess.file_exists(service.get_backup_path()), "覆寫主存檔前應保留備份")
	var broken_file := FileAccess.open(service.get_run_path(), FileAccess.WRITE)
	if broken_file != null:
		broken_file.store_string("{truncated")
		broken_file = null
	var recovered: Dictionary = service.load_run()
	_expect(recovered.get("ok", false) and recovered.get("source") == "backup", "主檔損壞時應只讀回退至備份")
	if recovered.get("state") is RunState:
		_expect(recovered.state.hp == 61, "備份應是上一份已知有效 RunState")
	var corrupt_before := "{truncated"
	_expect(not service.save_run(first, "manual"), "現有主檔無效時應拒絕覆寫")
	var corrupt_reader := FileAccess.open(service.get_run_path(), FileAccess.READ)
	_expect(corrupt_reader != null and corrupt_reader.get_as_text() == corrupt_before, "拒絕保存後應完整保留無法遷移的來源檔")
	corrupt_reader = null
	_expect(service.recover_primary_from_backup(), "讀取有效備份後應隔離壞主檔並恢復可寫狀態：%s" % service.last_error)
	var rejected_path: String = service.last_rejected_path
	_expect(not rejected_path.is_empty() and FileAccess.file_exists(rejected_path), "損壞主檔應保留為 rejected 檔供人工復原")
	_expect(service.save_run(second, "node_entered"), "備份修復後應可繼續自動保存")
	var legacy := first.to_dict()
	legacy.schema_version = 3
	legacy.erase("rng_state")
	var legacy_path := "%s/legacy.json" % test_directory
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify(legacy))
		legacy_file = null
	var legacy_service = SaveGameServiceScript.new(test_directory)
	var migration = legacy_service._load_path(legacy_path, "legacy")
	_expect(migration.get("ok", false) and migration.get("migrated", false), "RunState v3 應可遷移至目前版本")
	if migration.get("state") is RunState:
		_expect(migration.state.reward_rng_state.is_valid_int() and migration.state.tablet_rng_state.is_valid_int(), "v3 遷移應建立可重現 RNG 狀態")
	for old_version in [1, 2]:
		var old_payload := first.to_dict()
		old_payload.schema_version = old_version
		old_payload.erase("rng_state")
		old_payload.erase("sanity_effect_ids")
		old_payload.erase("sanity_history")
		old_payload.erase("hand_state")
		if old_version == 1:
			for key in ["item_inventory", "currency", "battle_reports", "flow_state", "current_node_id", "completed_node_ids", "available_node_ids", "map_data"]:
				old_payload.erase(key)
		var old_migration: Dictionary = service._migrate_run_state(old_payload)
		_expect(old_migration.get("ok", false) and service.validate_run_state_payload(old_migration.get("data", {})).is_empty(), "RunState v%d fixture 應可逐版遷移並通過目前驗證" % old_version)
	var invalid := first.to_dict()
	invalid.player.hp = invalid.player.max_hp + 1
	_expect(not service.validate_run_state_payload(invalid).is_empty(), "嚴格解析應拒絕超出上限的玩家資源")
	invalid = first.to_dict()
	invalid.item_inventory = {"pistol": -1}
	_expect(not service.validate_run_state_payload(invalid).is_empty(), "嚴格解析應拒絕負數背包數量")
	invalid = first.to_dict()
	invalid.battle_reports = ["broken"]
	_expect(not service.validate_run_state_payload(invalid).is_empty(), "嚴格解析應拒絕會被靜默丟棄的報告項目")
	for path in [service.get_run_path(), service.get_backup_path(), service.get_temp_path(), legacy_path, rejected_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory))


func _test_board_model() -> void:
	var board := BoardModel.new(8)
	var single: Array[Vector2i] = [Vector2i.ZERO]
	_expect(board.can_place(0, 0, single), "空盤原點應可放置")
	board.place(0, 0, single, Color.RED)
	_expect(not board.can_place(0, 0, single), "重疊位置不可放置")
	for x in range(1, 8):
		board.place(x, 0, single, Color.RED)
	var lines := board.get_full_lines()
	_expect(lines.rows == [0], "填滿第一列應偵測 Row 0")
	board.clear_lines(lines.rows, lines.cols)
	_expect(board.can_place(0, 0, single), "清除後應可再次放置")
	var saved := board.serialize_cells()
	_expect(saved.size() == 64, "8x8 盤面應序列化為 64 格")
	var restored := BoardModel.new(8)
	_expect(restored.restore_cells(saved), "合法的 64 格盤面應可還原")
	_expect(restored.serialize_cells() == saved, "盤面序列化 round-trip 應一致")
	var shape := BlockData.new()
	shape.cells = [Vector2i(1, 0), Vector2i(0, 1)]
	var rotated := shape.rotated(1)
	_expect(rotated.cells == [Vector2i(0, 1), Vector2i(-1, 0)] and rotated.get_rotation_steps() == 1, "抽牌旋轉應建立獨立 BlockData 方向")
	_expect(shape.rotated(4).cells == shape.cells, "旋轉四次應回到原始方向")


func _test_enemy_intents_and_speed() -> void:
	var first := EnemyIntentState.new()
	var second := EnemyIntentState.new()
	first.configure(["attack", "guard"])
	second.configure(["buff_self", "heavy_attack"])
	first.advance()
	_expect(first.current_intent_id() == "guard", "敵人意圖索引應獨立前進")
	_expect(second.current_intent_id() == "buff_self", "其他敵人意圖索引不應一起前進")
	first.advance()
	_expect(first.current_intent_id() == "attack", "意圖 pattern 應循環")

	var slow := _make_entity("慢", 30)
	var fast := _make_entity("快", 30)
	slow.set_meta("speed", 4)
	fast.set_meta("speed", 12)
	slow.set_meta("spawn_index", 0)
	fast.set_meta("spawn_index", 1)
	var manager := preload("res://scripts/battle_manager.gd").new()
	manager.enemies = [slow, fast]
	_expect(manager._get_enemy_action_order() == [fast, slow], "敵人應依隱藏速度由高至低行動")
	manager.free()

	var registry := ContentRegistry.new()
	registry.load_all()
	var executor := EnemyIntentExecutor.new()
	var actor := _make_entity("施術者", 50)
	var player := _make_entity("玩家", 100, 100)
	actor.set_meta("attack_damage", 10)
	executor.execute(registry.get_definition("intents", "heavy_attack"), actor, player)
	_expect(player.hp == 85, "重擊應依資料倍率造成 15 傷害")
	executor.execute(registry.get_definition("intents", "guard"), actor, player)
	_expect(actor.armor == 10, "防禦意圖應依資料獲得護甲")
	executor.execute(registry.get_definition("intents", "debuff_player"), actor, player)
	_expect(player.get_status_amount("weak") == 2, "debuff 意圖應對玩家施加狀態")
	executor.execute(registry.get_definition("intents", "buff_self"), actor, player)
	_expect(actor.get_status_amount("strength") == 2, "buff 意圖應對敵人自身施加狀態")
	for entity in [slow, fast, actor, player]:
		entity.free()


func _test_target_resolver() -> void:
	var a := _make_entity("A", 10)
	var dead := _make_entity("Dead", 1)
	var b := _make_entity("B", 10)
	var c := _make_entity("C", 10)
	dead.take_damage(1)
	var enemies: Array[Entity] = [a, dead, b, c]
	var resolver := TargetResolver.new()
	_expect(resolver.resolve("spread", enemies, 2) == [a, b, c], "擴散應跳過死亡空位尋找存活相鄰者")
	_expect(resolver.resolve("single", enemies, 1).is_empty(), "鎖定目標死亡後，後續單體效果應失效")
	_expect(resolver.resolve("all", enemies, 1) == [a, b, c], "全體效果應只包含存活敵人")
	for entity in enemies:
		entity.free()


func _test_status_timing_and_outcomes() -> void:
	var entity := _make_entity("狀態測試", 10)
	entity.add_status("poison", 3)
	entity.add_status("strength", 2)
	entity.trigger_end_of_turn_statuses()
	_expect(entity.hp == 7, "中毒應在角色回合結束觸發")
	_expect(entity.get_status_amount("poison") == 3, "角色回合結束不應立即衰減狀態")
	entity.decay_statuses()
	_expect(entity.get_status_amount("poison") == 2 and entity.get_status_amount("strength") == 1, "完整輪結束時所有狀態應衰減 1")

	var poison_victim := _make_entity("中毒死亡", 2)
	poison_victim.add_status("poison", 2)
	poison_victim.trigger_end_of_turn_statuses()
	_expect(poison_victim.is_dead, "中毒可在回合結束造成死亡")

	var resolver := BattleOutcomeResolver.new()
	var player := _make_entity("玩家", 10, 10)
	var enemy := _make_entity("敵人", 10)
	_expect(resolver.resolve(player, [enemy]) == BattleOutcomeResolver.Outcome.NONE, "雙方存活時戰鬥應繼續")
	enemy.take_damage(10)
	_expect(resolver.resolve(player, [enemy]) == BattleOutcomeResolver.Outcome.VICTORY, "最後敵人死亡應勝利")
	enemy.reset_entity("敵人", 10)
	player.take_damage(10)
	_expect(resolver.resolve(player, [enemy]) == BattleOutcomeResolver.Outcome.HP_DEFEAT, "玩家 HP 歸零應失敗")
	player.reset_entity("玩家", 10, 10, 10, 10)
	player.spend_sanity(10)
	_expect(resolver.resolve(player, [enemy]) == BattleOutcomeResolver.Outcome.SANITY_DEFEAT, "玩家 Sanity 歸零應失敗")
	player.reset_entity("玩家", 10, 10, 10, 10)
	player.take_damage(10)
	enemy.take_damage(10)
	_expect(resolver.resolve(player, [enemy]) == BattleOutcomeResolver.Outcome.HP_DEFEAT, "同一結算序列敵我同時死亡時玩家應失敗")
	for value in [entity, poison_victim, player, enemy]:
		value.free()


func _test_phase_13_growth_and_rewards() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "Phase 13 成長資料應通過載入：%s" % [registry.errors])
	var pistol := registry.get_item("pistol")
	_expect(pistol.tier == 1 and pistol.balance_cost == 10 and pistol.upgrade_to == "pistol_engraved", "runtime 道具應包含 tier、balance_cost 與升級關係")
	var upgraded := registry.get_item("pistol_engraved")
	_expect(upgraded != null and upgraded.tier == 2 and upgraded.rarity == "uncommon", "升級結果應建立為獨立 runtime Resource")

	var growth = EquipmentGrowthServiceScript.new()
	var inventory := {"pistol": 1}
	var growth_result := growth.add_to_inventory("pistol", inventory, registry.indexes.get("items", {}))
	_expect(growth_result.get("item_id") == "pistol_engraved", "兩件相同裝備應依 JSON 關係合成升級")
	_expect(int(inventory.get("pistol", 0)) == 0 and int(inventory.get("pistol_engraved", 0)) == 1, "合成應正確消耗背包數量")

	var encounter_defs: Array = [registry.get_definition("enemies", "rotting_hound"), registry.get_definition("enemies", "abyss_thrall")]
	var calculator = EncounterDifficultyCalculatorScript.new()
	var metrics := calculator.calculate(encounter_defs, registry.get_document("run_config").get("difficulty_model", {}))
	_expect(int(metrics.get("strength", 0)) > 0 and int(metrics.get("reward_tier", 0)) >= 1, "encounter 應產生可解釋的強度與獎勵 tier")

	var selector = RewardCandidateSelectorScript.new()
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 777
	second_rng.seed = 777
	var context := {"battles_won": 3, "reward_tier": 2, "unlocked_reward_ids": []}
	var first := selector.pick(registry.get_entries("rewards"), registry.indexes.get("items", {}), registry.indexes.get("blocks", {}), context, 3, first_rng)
	var second := selector.pick(registry.get_entries("rewards"), registry.indexes.get("items", {}), registry.indexes.get("blocks", {}), context, 3, second_rng)
	_expect(first == second and first.size() == 3, "相同強度與種子應產生可重現的三選一")
	var candidate_ids: Array[String] = []
	var unique_candidate_ids := {}
	for reward in first:
		var candidate_id := str(reward.get("id", ""))
		candidate_ids.append(candidate_id)
		unique_candidate_ids[candidate_id] = true
	_expect(candidate_ids.size() == unique_candidate_ids.size(), "同一次三選一不應出現重複內容")

	var board_rng := RandomNumberGenerator.new()
	board_rng.seed = 2468
	var generator = FriendlyBoardGeneratorScript.new()
	var rules: Dictionary = registry.get_document("run_config").get("board_growth_rules", {})
	var seed_cells: Array[Vector2i] = generator.generate(8, board_rng, rules)
	var board := BoardModel.new(8)
	for coord in seed_cells:
		board.cells[coord.x][coord.y] = Color.GRAY
	var full_lines := board.get_full_lines()
	_expect(seed_cells.size() == int(rules.get("friendly_seed_cells", 15)), "程序友善盤面應產生資料指定的格數")
	_expect(full_lines.rows.is_empty() and full_lines.cols.is_empty(), "程序友善盤面不可在開局直接完成消除")
	var scorer := SmartHandScorer.new()
	var ranked := scorer.rank(board, registry.get_blocks(registry.get_document("run_config").get("block_pool", [])))
	_expect(not ranked.is_empty() and int(ranked[0].get("direction_score", 0)) > 0, "友善盤面應讓智慧手牌至少提供一張有明確方向的方塊")


func _test_phase_14_run_foundation() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "版本化地圖資料應通過完整驗證：%s" % [registry.errors])
	var map_document := registry.get_document("map")
	_expect(map_document.get("start_node_ids", []).size() == 2, "固定路線應提供多個起點")
	_expect(str(map_document.get("boss_node_id", "")) == "boss_gate", "固定路線應匯聚到單一 Boss")
	var generator = LayeredMapGeneratorScript.new()
	var generated_a: Dictionary = generator.generate(98765, map_document)
	var generated_b: Dictionary = generator.generate(98765, map_document)
	_expect(generated_a == generated_b, "相同 Run seed 應生成完全相同的分層 DAG")
	_expect(generator.verify_connectivity(generated_a), "生成地圖的所有起點都應可抵達 Boss")
	var boss_id := str(generated_a.get("boss_node_id", ""))
	var boss_floor := -1
	var rest_floor_count := 0
	for node in generated_a.get("nodes", []):
		if str(node.get("id", "")) == boss_id:
			boss_floor = int(node.get("floor", -1))
	for node in generated_a.get("nodes", []):
		if int(node.get("floor", -1)) == boss_floor - 1 and str(node.get("type", "")) == "rest":
			rest_floor_count += 1
	_expect(rest_floor_count > 0, "Boss 前一層應固定為休息節點")
	var generated_types := {}
	var normal_floors := {}
	for node in generated_a.get("nodes", []):
		generated_types[str(node.get("type", ""))] = true
		if str(node.get("type", "")) == "normal_battle":
			normal_floors[int(node.get("floor", -1))] = true
	for required_type in ["normal_battle", "elite", "event", "shop", "rest", "boss"]:
		_expect(generated_types.has(required_type), "生成路線應包含節點類型：%s" % required_type)
	var battle_range := _generated_path_battle_range(generated_a)
	_expect(int(battle_range.get("min", 0)) >= 5 and int(battle_range.get("max", 99)) <= 8, "每條生成路徑應維持 5–8 場戰鬥")
	_expect(normal_floors.size() == 4, "生成地圖應只保留四層普通戰鬥，避免普通戰鬥節點過多")
	var state_machine = RunStateMachineScript.new()
	_expect(state_machine.transition(state_machine.State.MAP), "Run 應可從 START 進入 MAP")
	_expect(not state_machine.transition(state_machine.State.REWARD), "Run 狀態機應拒絕 MAP 直接跳到 REWARD")
	_expect(state_machine.transition(state_machine.State.NODE), "Run 應可從 MAP 進入 NODE")
	_expect(state_machine.transition(state_machine.State.BATTLE), "戰鬥節點應可進入 BATTLE")
	_expect(state_machine.transition(state_machine.State.VICTORY), "Boss 戰鬥應可直接進入通關")
	state_machine.reset()
	var result = RunNodeResultScript.create("start_a", "normal_battle", RunNodeResultScript.Outcome.COMPLETED, {"hp": -5}, ["event_archive"])
	_expect(result.node_id == "start_a" and result.next_node_ids == ["event_archive"], "節點結果應封裝狀態變更與下一節點")


func _test_phase_15_sanity_rules() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "Sanity 資料與行為 Resource 應通過驗證：%s" % [registry.errors])
	var rules = SanityRuleEngineScript.new()
	rules.configure(registry.get_document("sanity"), 0)
	_expect(rules.synchronize(70).active.is_empty(), "Sanity 高於門檻時不應有瘋狂效果")
	var uneasy: Dictionary = rules.synchronize(40)
	var unique_effects := {}
	for effect_id in uneasy.active:
		unique_effects[effect_id] = true
	_expect(uneasy.active.size() == 1 and unique_effects.size() == uneasy.active.size(), "第一階段應加入一個且不可重複的效果")
	_expect(rules.modify_magic_cost(3) == 4, "儀式執著行為 Resource 應增加魔法成本")
	var fractured: Dictionary = rules.synchronize(20)
	_expect(fractured.active.size() == 2 and rules.modify_dead_board_penalty(10) == 13, "第二階段應疊加跨系統效果")
	var preview: Dictionary = rules.preview(30, -6)
	_expect(preview.sanity == 24 and preview.effects.size() == 2, "魔法／事件選擇前應完整預覽跨門檻後果")
	_expect(rules.synchronize(60).active.is_empty(), "Sanity 回升至門檻以上應解除對應效果")
	var player := _make_entity("來源測試", 20, 70)
	var record := {"source": ""}
	player.sanity_changed.connect(func(_entity, _delta, source, _before, _after): record.source = source)
	player.spend_sanity(6, "enemy_intent:sanity_attack")
	_expect(record.source == "enemy_intent:sanity_attack", "統一 Sanity 介面應保留敵人意圖來源")
	player.free()
	var simulation: Dictionary = registry.get_document("sanity").get("simulation", {})
	var before_rest := 70 - 5 * int(simulation.get("magic_uses_per_battle", 2)) * 3 - int(simulation.get("dead_boards_per_run", 1)) * 10 - int(simulation.get("enemy_sanity_hits_per_run", 2)) * int(simulation.get("enemy_sanity_hit", 6))
	_expect(before_rest >= int(simulation.get("acceptance_min_sanity_before_rest", 15)) and before_rest <= int(simulation.get("acceptance_max_sanity_before_rest", 55)), "完整 Run 基準情境的休息前 Sanity 應落在驗收區間")


func _test_phase_16_content_integrity() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "Phase 16 內容關係應通過完整驗證：%s" % [registry.errors])
	if not registry.errors.is_empty():
		return
	var state := RunState.new()
	var config := registry.get_document("run_config")
	state.block_pool_ids = RunState._strings(config.get("block_pool", []))
	state.row_item_ids = RunState._strings(config.get("row_items", []))
	state.col_item_ids = RunState._strings(config.get("col_items", []))
	var generator = LayeredMapGeneratorScript.new()
	state.map_data = generator.generate(13579, registry.get_document("map"))
	state.available_node_ids = RunState._strings(state.map_data.get("start_node_ids", []))
	_expect(registry.validate_run_state_references(state).is_empty(), "現行內容建立的 RunState 引用應全部有效")

	var invalid := RunState.from_dict(state.to_dict())
	invalid.block_pool_ids.append("missing_block")
	invalid.row_item_ids[0] = "dark_spike"
	invalid.selected_reward_ids.append("missing_reward")
	invalid.item_inventory["missing_item"] = 1
	invalid.sanity_effect_ids.append("missing_effect")
	invalid.available_node_ids.append("missing_node")
	invalid.map_data.nodes[0].content_id = "missing_encounter"
	var reference_errors := registry.validate_run_state_references(invalid)
	_expect(reference_errors.size() >= 7, "RunState 還原前應捕獲方塊、裝備軸、獎勵、背包、Sanity、節點與 encounter 失效引用")


func _test_phase_16_data_driven_events() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "事件測試前內容資料應有效：%s" % [registry.errors])
	if not registry.errors.is_empty():
		return
	var event_definition := registry.get_definition("events", "prototype_event")
	_expect(event_definition.get("options", []).size() == 3, "原型事件應提供三個資料化選項")
	var resolver = EventChoiceResolverScript.new()
	var state := {"hp": 40, "max_hp": 80, "sanity": 70, "max_sanity": 100, "currency": 2}
	var snapshot := state.duplicate(true)
	var study: Dictionary = resolver.resolve_choice(event_definition, "study_fragments", state)
	_expect(study.get("valid", false) and study.get("affordable", false), "資源足夠時事件選項應可執行")
	_expect(study.get("changes", {}).get("sanity") == 64 and study.get("changes", {}).get("currency") == 20, "事件應依資料同時套用代價與結果")
	_expect(state == snapshot, "事件預覽與結算不應直接修改輸入狀態")
	var healed: Dictionary = resolver.resolve_choice(event_definition, "bind_the_wound", {"hp": 40, "max_hp": 80, "sanity": 95, "max_sanity": 100, "currency": 0})
	_expect(healed.get("changes", {}).get("hp") == 32 and healed.get("changes", {}).get("sanity") == 100, "事件回復應受到資源上限限制")
	var unaffordable: Dictionary = resolver.resolve_choice(event_definition, "study_fragments", {"hp": 40, "max_hp": 80, "sanity": 6, "max_sanity": 100, "currency": 0})
	_expect(not unaffordable.get("affordable", true), "事件不得讓 HP 或 Sanity 因支付代價降至零")
	_expect(not resolver.resolve_choice(event_definition, "missing_option", state).get("valid", true), "未知事件選項應明確失敗")


func _test_phase_16_board_simulation() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "棋盤模擬前內容資料應有效：%s" % [registry.errors])
	if not registry.errors.is_empty():
		return
	var config := registry.get_document("run_config")
	var blocks := registry.get_blocks(config.get("block_pool", []))
	var rules: Dictionary = config.get("board_growth_rules", {})
	var options := {
		"mode": BoardSimulatorScript.SMART_MODE,
		"seed": 24680,
		"runs": 3,
		"placements_per_run": 12,
		"hand_size": 3,
		"action_points": 5,
	}
	var simulator = BoardSimulatorScript.new()
	var first: Dictionary = simulator.simulate(blocks, rules, options)
	var second: Dictionary = simulator.simulate(blocks, rules, options)
	_expect(not first.has("error"), "智慧手牌棋盤模擬應可完成")
	_expect(first == second, "固定種子的棋盤模擬結果應可重現")
	_expect(int(first.get("successful_placements", 0)) == 36, "棋盤模擬應完成指定放置次數")
	for metric in ["completion_rate", "legal_hand_rate", "legal_card_rate", "direct_clear_rate", "average_occupancy_rate", "maximum_occupancy_rate"]:
		var value := float(first.get(metric, -1.0))
		_expect(value >= 0.0 and value <= 1.0, "棋盤模擬比例 %s 應落在 0–1" % metric)
	var random_options := options.duplicate(true)
	random_options.mode = BoardSimulatorScript.RANDOM_MODE
	var random_report: Dictionary = simulator.simulate(blocks, rules, random_options)
	_expect(int(random_report.get("successful_placements", 0)) == 36, "權重隨機基線也應完成指定放置次數")


func _test_phase_16_battle_batch() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "戰鬥批次模擬前內容資料應有效：%s" % [registry.errors])
	if not registry.errors.is_empty():
		return
	var enemy_index := {}
	for enemy in registry.get_entries("enemies"):
		enemy_index[str(enemy.get("id", ""))] = enemy
	var intent_index := {}
	for intent in registry.get_entries("intents"):
		intent_index[str(intent.get("id", ""))] = intent
	var config := registry.get_document("run_config")
	var simulator = BattleBatchSimulatorScript.new()
	var options := {"seed": 97531, "battles": 2, "max_turns": 4}
	var arguments := [
		[registry.get_entries("encounters")[0]],
		enemy_index,
		intent_index,
		registry.get_document("player"),
		registry.get_items(config.get("row_items", [])),
		registry.get_items(config.get("col_items", [])),
		registry.get_blocks(config.get("block_pool", [])),
		config.get("board_growth_rules", {}),
		registry.get_document("sanity"),
		options,
	]
	var first: Dictionary = simulator.callv("simulate", arguments)
	var second: Dictionary = simulator.callv("simulate", arguments)
	_expect(not first.has("error") and first == second, "固定 seed 的無 UI 戰鬥批次應成功且可重現")
	var report: Dictionary = first.get("encounters", [{}])[0]
	var outcomes := int(round(float(report.get("win_rate", 0.0)) * 2.0)) + int(report.get("hp_defeats", 0)) + int(report.get("sanity_defeats", 0)) + int(report.get("timeouts", 0))
	_expect(outcomes == 2, "戰鬥批次每次試驗都應歸入勝利、HP／Sanity 失敗或超時")
	_expect(report.get("enemy_survival_curve", []).size() == 4, "敵人存活曲線應覆蓋指定最大回合數")


func _test_phase_19_full_run_pressure() -> void:
	var content := ContentRegistry.new()
	_expect(content.load_all(), "完整 Run 壓力模擬前內容資料應有效：%s" % [content.errors])
	if not content.errors.is_empty():
		return
	var simulator = RunPressureSimulatorScript.new()
	var options := {"seed": 86420, "runs": 1, "max_turns": 6}
	var first: Dictionary = simulator.simulate(content, options)
	var second: Dictionary = simulator.simulate(content, options)
	_expect(not first.has("error") and first == second, "固定 seed 的完整 Run 壓力模擬應成功且可重現")
	_expect(int(first.get("runs", 0)) == 1 and int(first.get("invalid_runs", 1)) == 0, "完整 Run 模擬應產生一筆有效結果")
	_expect(float(first.get("average_battles_reached", 0.0)) >= 1.0, "完整 Run 模擬至少應抵達第一場戰鬥")
	_expect(float(first.get("average_board_placements", 0.0)) > 0.0, "完整 Run 模擬應透過持久棋盤產生放置")
	_expect(not first.get("pressure_curve", []).is_empty(), "完整 Run 模擬應輸出逐場 HP／Sanity 壓力曲線")


func _test_five_enemy_roster() -> void:
	var host := VBoxContainer.new()
	var label := Label.new()
	host.add_child(label)
	root.add_child(host)
	var enemies: Array[Entity] = []
	for i in range(5):
		var enemy := _make_entity("敵人%d" % i, 10)
		var state := EnemyIntentState.new()
		state.configure(["attack"])
		enemy.set_meta("intent_state", state)
		enemy.set_meta("intent_display", "攻擊")
		enemies.append(enemy)
	var presenter := EnemyRosterPresenter.new()
	presenter.render(label, enemies, 0, func(_index: int): pass)
	var before := presenter.get_card_instance_ids()
	_expect(before.size() == 5, "敵人 UI 應可建立 5 張獨立敵人卡")
	enemies[2].add_armor(3)
	presenter.render(label, enemies, 0, func(_index: int): pass)
	_expect(presenter.get_card_instance_ids() == before, "五敵人數值更新不應重建卡片")
	enemies[0].take_damage(10)
	presenter.render(label, enemies, 1, func(_index: int): pass)
	_expect(presenter.get_card_instance_ids().size() == 4, "死亡敵人應從敵人卡列消失")
	host.queue_free()
	await process_frame
	for enemy in enemies:
		enemy.free()


func _test_drag_source_visibility() -> void:
	var block := preload("res://scripts/block.gd").new() as Block
	root.add_child(block)
	var data := BlockData.new()
	data.id = "drag_test"
	data.cells = [Vector2i.ZERO]
	block.set_data(data)
	block._set_shape_visible(false)
	var source_hidden := true
	for child in block.get_children():
		if child is ColorRect and child.visible:
			source_hidden = false
	_expect(source_hidden, "拖曳時來源位置的方塊圖形應隱藏")
	block._set_shape_visible(true)
	var source_restored := true
	for child in block.get_children():
		if child is ColorRect and not child.visible:
			source_restored = false
	_expect(source_restored, "取消拖曳後來源方塊圖形應恢復")
	block.queue_free()
	await process_frame


func _test_main_scene_smoke() -> void:
	var smoke_save_directory := "/tmp/arkham_grid_smoke_save_%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("arkham_grid/testing/save_directory", smoke_save_directory)
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main.tscn 應可載入")
	if packed == null:
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	_expect(instance.get_node_or_null("RunManager") != null, "核心迴圈應建立 RunManager")
	_expect(instance.get_node_or_null("BattleManager") != null, "核心迴圈應建立 BattleManager")
	var manager = instance.get_node("BattleManager")
	var run_manager = instance.get_node("RunManager")
	var graph = instance.get_node_or_null("UILayer/MapContainer/Margin/Panel/VBox/Scroll/Graph")
	_expect(graph != null and graph.get_edge_count() > 0, "地圖畫布應建立可見的節點連線資料")
	_expect(FileAccess.file_exists(run_manager.save_service.get_run_path()), "新 Run 建立後應寫入單一自動存檔槽")
	var event_view = instance.get_node_or_null("UILayer/EventView")
	_expect(event_view != null, "主場景應掛載事件選項介面")
	if event_view != null:
		var event_node := {}
		for candidate in run_manager.runtime_map.get("nodes", []):
			if str(candidate.get("type", "")) == "event":
				event_node = candidate
				break
		_expect(not event_node.is_empty(), "程序地圖應包含可測試的事件節點")
		if not event_node.is_empty():
			var sanity_before_event: int = run_manager.run_state.sanity
			var currency_before_event: int = run_manager.run_state.currency
			run_manager.flow.transition(run_manager.flow.State.NODE)
			run_manager.run_state.flow_state = run_manager.flow.current_state
			run_manager.run_state.current_node_id = str(event_node.get("id", ""))
			run_manager._show_event_node(event_node)
			_expect(event_view.visible and event_view.get_option_buttons().size() == 3, "事件節點應建立三個可操作選項")
			run_manager._on_event_choice_selected("study_fragments")
			_expect(run_manager.flow.current_state == run_manager.flow.State.MAP, "事件選擇結算後應返回地圖")
			_expect(run_manager.run_state.sanity == sanity_before_event - 6 and run_manager.run_state.currency == currency_before_event + 18, "事件選擇應修改 Run 資源")
			_expect(str(run_manager.run_state.sanity_history.back().get("source", "")).begins_with("event:prototype_event"), "事件 Sanity 變化應記錄資料來源")
			run_manager.start_new_run()
	var tablet = manager.tablet
	var special_block: BlockData = run_manager.content.get_block("special_dot")
	var special_count_before: int = tablet.get_block_pool_count("special_dot")
	tablet.add_block_to_pool(special_block)
	_expect(tablet.get_block_pool_count("special_dot") == special_count_before + 1, "重複特殊方塊應以池內份數增加抽取權重")
	_expect(run_manager.flow.current_state == run_manager.flow.State.MAP, "新 Run 應先進入地圖選擇")
	var first_node_id: String = run_manager.run_state.available_node_ids[0]
	_expect(run_manager.select_map_node(first_node_id), "玩家應可選擇生成地圖的起點")
	var entry_save: Dictionary = run_manager.save_service.load_run()
	_expect(entry_save.get("ok", false) and entry_save.state.flow_state == run_manager.flow.State.NODE and entry_save.state.current_node_id == first_node_id, "節點入口存檔應鎖定已選節點，不允許退回地圖重選")
	_expect(run_manager.continue_autosave() and run_manager.flow.current_state == run_manager.flow.State.BATTLE and run_manager.run_state.current_node_id == first_node_id, "讀取節點入口存檔時應重啟同一已鎖定節點")
	await process_frame
	var card_ids_before: Array[int] = manager._enemy_presenter.get_card_instance_ids()
	_expect(not card_ids_before.is_empty(), "遭遇開始時應建立可重用敵人卡")
	manager.enemies[0].add_armor(1)
	var card_ids_after: Array[int] = manager._enemy_presenter.get_card_instance_ids()
	_expect(card_ids_after == card_ids_before, "敵人數值更新不應重建敵人卡")
	var hp_before: int = manager.player.hp
	var hand_before_turn: Array[Dictionary] = tablet.get_hand_state()
	manager.end_player_turn()
	await create_timer(0.5).timeout
	_expect(manager.player.hp == hp_before - 8, "核心迴圈應依資料化 attack 意圖完成敵人回合")
	_expect(int(manager._battle_stats.values.get("damage_taken", 0)) == 8, "戰鬥統計應記錄承受傷害")
	_expect(manager.current_turn == manager.TurnState.PLAYER_TURN, "敵人回合結束後應回到玩家回合")
	_expect(tablet.get_hand_state() == hand_before_turn, "回合結束時未使用的手牌與旋轉方向應保留")
	var board_before_reward: Array[String] = tablet.get_board_state()
	manager.start_encounter([
		run_manager.content.get_definition("enemies", "rotting_hound"),
		run_manager.content.get_definition("enemies", "abyss_thrall"),
	])
	manager.enemies[0].take_damage(9999)
	await process_frame
	_expect(manager.selected_enemy_index == -1 and manager._get_targets_for_scope("single").is_empty(), "鎖定目標死亡後應保持空目標，不自動改鎖定")
	manager._select_enemy(1)
	_expect(manager._get_targets_for_scope("single") == [manager.enemies[1]], "玩家重新選擇後單體效果應恢復目標")
	for active_enemy in manager.enemies:
		if active_enemy != null and not active_enemy.is_dead:
			active_enemy.take_damage(9999)
	await process_frame
	await process_frame
	_expect(run_manager.flow.current_state == run_manager.flow.State.REWARD, "普通戰鬥勝利後應由狀態機進入獎勵")
	run_manager._on_reward_skipped(10)
	await process_frame
	_expect(run_manager.flow.current_state == run_manager.flow.State.MAP, "獎勵結算後應返回地圖")
	var completion_save: Dictionary = run_manager.save_service.load_run()
	_expect(completion_save.get("ok", false) and completion_save.state.flow_state == run_manager.flow.State.MAP and first_node_id in completion_save.state.completed_node_ids, "節點完成後自動存檔應保存最新地圖進度")
	_expect(tablet.get_board_state() == board_before_reward, "跨戰鬥、獎勵與地圖節點應完整保留盤面")
	run_manager._finish_run(false, "整合測試")
	_expect(run_manager.flow.current_state == run_manager.flow.State.DEFEAT, "Run 失敗應進入結算狀態")
	_expect(run_manager.settlement_screen.visible, "失敗時應顯示結算畫面")
	run_manager.start_new_run()
	_expect(run_manager.flow.current_state == run_manager.flow.State.MAP and run_manager.run_state.completed_node_ids.is_empty(), "重新開始應建立全新 Run 並回到地圖")
	var fresh_snapshot: Dictionary = run_manager.get_run_state_snapshot()
	_expect(run_manager.restore_run_state(fresh_snapshot), "內容引用完整的 RunState 快照應可還原")
	instance.queue_free()
	await process_frame
	var smoke_service = SaveGameServiceScript.new(smoke_save_directory)
	for path in [smoke_service.get_run_path(), smoke_service.get_backup_path(), smoke_service.get_temp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(smoke_save_directory))
	ProjectSettings.set_setting("arkham_grid/testing/save_directory", null)


func _generated_path_battle_range(map_data: Dictionary) -> Dictionary:
	var index := {}
	for node in map_data.get("nodes", []):
		index[str(node.get("id", ""))] = node
	var boss_id := str(map_data.get("boss_node_id", ""))
	var counts: Array[int] = []
	for start_id in map_data.get("start_node_ids", []):
		_collect_path_battle_counts(str(start_id), boss_id, index, 0, counts)
	if counts.is_empty():
		return {"min": 0, "max": 0}
	return {"min": counts.min(), "max": counts.max()}


func _collect_path_battle_counts(node_id: String, boss_id: String, index: Dictionary, count: int, output: Array[int]) -> void:
	var node: Dictionary = index.get(node_id, {})
	var next_count := count + (1 if str(node.get("type", "")) in ["normal_battle", "elite", "boss"] else 0)
	if node_id == boss_id:
		output.append(next_count)
		return
	for next_id in node.get("next_ids", []):
		_collect_path_battle_counts(str(next_id), boss_id, index, next_count, output)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _make_entity(name: String, hp: int, sanity: int = 0) -> Entity:
	var entity := Entity.new()
	entity.reset_entity(name, hp, hp, sanity, sanity)
	return entity
