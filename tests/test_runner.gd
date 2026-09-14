extends SceneTree

const SpellUpgradeServiceScript = preload("res://scripts/growth/spell_upgrade_service.gd")
const EncounterDifficultyCalculatorScript = preload("res://scripts/growth/encounter_difficulty_calculator.gd")
const RewardCandidateSelectorScript = preload("res://scripts/growth/reward_candidate_selector.gd")
const SlatePairingRulesScript = preload("res://scripts/growth/slate_pairing_rules.gd")
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
const ProfileSaveServiceScript = preload("res://scripts/save/profile_save_service.gd")
const RunSeedPolicyScript = preload("res://scripts/run/run_seed_policy.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_content_registry()
	_test_run_state_round_trip()
	_test_phase_18_save_foundation()
	_test_phase_18_profile_foundation()
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
		print("TESTS OK (19 suites)")
		quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILED: %s" % failure)
		quit(1)


func _test_content_registry() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "ContentRegistry 應載入並驗證全部資料：%s" % [registry.errors])
	_expect(registry.get_entries("blocks").size() == 11, "應索引 11 種方塊")
	_expect(registry.get_entries("intents").size() == 8, "應索引 8 種敵人意圖")
	_expect(registry.get_definition("enemies", "abyss_thrall").get("hp") == 35.0, "應可依 ID 查詢敵人")
	_expect(registry.get_block("shape_L") != null, "應建立 BlockData runtime Resource")
	_expect(registry.get_spell("pistol") != null, "應建立咒文 runtime Resource")
	_expect(registry.get_spell("pistol") is EffectAttack, "attack JSON 應使用 attack.tres 行為")
	_expect(registry.get_spell("burst_pistol") is EffectConditionalAttack, "conditional_attack JSON 應使用 conditional_attack.tres 行為")
	_expect(registry.get_spell("vest") is EffectSupport, "support JSON 應使用 support.tres 行為")
	_expect(registry.get_spell("poison_spell") is EffectStatus, "status JSON 應使用 status.tres 行為")
	_expect(registry.get_spell("pistol").mp_cost == 3 and registry.get_spell("dark_spike").mp_cost == 6, "所有咒文應以 MP 成本取代軸與類型")
	var slate := registry.create_slate({"slate_uid": "stable_slate", "shape_id": "shape_L", "spell_id": "poison_spell", "effect_cell": [0, 1]})
	var rotated_slate := slate.rotated(1) if slate != null else null
	_expect(rotated_slate != null and rotated_slate.slate_uid == "stable_slate" and rotated_slate.spell.content_id == "poison_spell" and rotated_slate.effect_cell == Vector2i(-1, 0), "同一 slate_uid 旋轉時形狀、咒文與效果格應同步且不重新配對")
	var pairing_rules = SlatePairingRulesScript.new()
	_expect(not pairing_rules.is_allowed(registry.get_definition("blocks", "shape_short_I"), registry.get_definition("spells", "dark_spike")), "高強度咒文不得搭配低複雜度形狀")
	var override_spell := registry.get_definition("spells", "dark_spike")
	override_spell.allowed_shape_ids = ["shape_short_I"]
	_expect(pairing_rules.is_allowed(registry.get_definition("blocks", "shape_short_I"), override_spell), "allowed_shape_ids 應可明確覆寫公式")
	var seed_policy = RunSeedPolicyScript.new()
	_expect(seed_policy.choose_seed({"runtime_seed_mode": "fixed", "seed": 13579}) == 13579, "固定 seed 模式應保留可重現的除錯入口")
	var seed_source := RandomNumberGenerator.new()
	seed_source.seed = 24680
	var first_runtime_seed: int = seed_policy.choose_seed({"runtime_seed_mode": "random"}, 0, seed_source)
	var second_runtime_seed: int = seed_policy.choose_seed({"runtime_seed_mode": "random"}, first_runtime_seed, seed_source)
	_expect(first_runtime_seed > 0 and second_runtime_seed > 0 and first_runtime_seed != second_runtime_seed, "一般 runtime 每次新 Run 應取得不同的正整數 seed")
	_expect(registry.get_spell("pistol").category_id == "single_attack" and registry.get_spell("poison_spell").category_id == "poison", "咒文應使用資料化的七類符文")
	var icon_cell := GridCell.new()
	icon_cell.init(0, 0, null)
	icon_cell.set_spell(registry.get_spell("poison_spell"))
	_expect(icon_cell.spell_marker.text == registry.get_spell("poison_spell").category_glyph and icon_cell.spell_marker.custom_minimum_size.x >= 46.0, "盤面效果格應直接顯示清楚的大型分類符文，不需依賴 hover")
	icon_cell.free()
	for spell in registry.get_entries("spells"):
		var has_regen: bool = spell.get("status_effects_self", []).any(func(effect): return str(effect.get("id", "")) == "regen")
		_expect(int(spell.get("heal_amount", 0)) == 0 and not has_regen, "常規咒文不得提供直接或持續 HP 回復：%s" % spell.get("id", ""))
	var conditional := registry.get_spell("burst_pistol") as EffectConditionalAttack
	var target := _make_entity("條件目標", 30)
	var user := _make_entity("使用者", 30)
	var context := BattleEffectContext.new()
	context.spell_trigger_count = 1
	conditional.execute_with_context(target, user, context)
	_expect(target.hp == 17, "條件攻擊應從效果上下文讀取咒文觸發紀錄")
	target.free()
	user.free()


func _test_run_state_round_trip() -> void:
	var original := RunState.new()
	original.seed = 4242
	original.profession_id = "investigator"
	original.hp = 51
	original.board_cells.resize(64)
	original.board_cells.fill("")
	original.board_cells[7] = "ff0000ff"
	original.board_spell_ids.resize(64)
	original.board_spell_ids.fill("")
	original.board_spell_ids[7] = "pistol"
	original.slate_pool = [
		{"slate_uid": "test_l", "shape_id": "shape_L", "spell_id": "pistol", "effect_cell": [0, 0]},
		{"slate_uid": "test_t", "shape_id": "shape_T", "spell_id": "vest", "effect_cell": [0, 0]},
	]
	original.hand_state = [{"slate_uid": "test_l", "rotation_steps": 2}, {"slate_uid": "test_t", "rotation_steps": 0}]
	original.pending_slate_rewards = [{"slate_uid": "pending_one", "shape_id": "shape_O", "spell_id": "vest", "effect_cell": [1, 1]}]
	original.selected_reward_ids = ["special_dot"]
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
	_expect(restored.seed == 4242 and restored.hp == 51 and restored.profession_id == "investigator", "RunState 應保留職業、玩家與種子")
	_expect(restored.board_cells[7] == "ff0000ff", "RunState 應保留盤面")
	_expect(restored.hand_state == original.hand_state, "RunState 應保留手牌旋轉狀態")
	_expect(restored.slate_pool == original.slate_pool and restored.pending_slate_rewards == original.pending_slate_rewards and restored.currency == 20, "RunState 應保留完整石板池、待選獎勵與局內金錢")
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
	var legacy_directory := "/tmp/arkham_grid_v5_archive_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(legacy_directory)
	var legacy_service = SaveGameServiceScript.new(legacy_directory)
	var legacy_file := FileAccess.open(legacy_service.get_run_path(), FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify({"save_schema_version": 1, "kind": "run_autosave", "checkpoint": "node_completed", "run_state": {"schema_version": 5}}))
		legacy_file = null
	var profile_marker_path := "%s/profile_marker.json" % legacy_directory
	var profile_marker := FileAccess.open(profile_marker_path, FileAccess.WRITE)
	if profile_marker != null:
		profile_marker.store_string("preserve")
		profile_marker = null
	var legacy_result: Dictionary = legacy_service.load_run()
	_expect(not legacy_result.get("ok", false) and legacy_result.get("restart_required", false), "v5 進行中 Run 不應近似遷移")
	_expect(FileAccess.file_exists(legacy_service.get_pre_slate_archive_path()) and not FileAccess.file_exists(legacy_service.get_run_path()), "v5 Run 應封存為 pre_slate_v5 並騰出新版自動槽")
	_expect(FileAccess.file_exists(profile_marker_path), "封存舊 Run 不得影響設定、Meta 或歷史檔")
	var invalid := first.to_dict()
	invalid.player.hp = invalid.player.max_hp + 1
	_expect(not service.validate_run_state_payload(invalid).is_empty(), "嚴格解析應拒絕超出上限的玩家資源")
	invalid = first.to_dict()
	invalid.player.mp = invalid.player.max_mp + 1
	_expect(not service.validate_run_state_payload(invalid).is_empty(), "嚴格解析應拒絕超出上限的 MP")
	invalid = first.to_dict()
	invalid.board_spell_ids = ["pistol"]
	_expect(not service.validate_run_state_payload(invalid).is_empty(), "嚴格解析應拒絕非 64 格的盤面咒文狀態")
	invalid = first.to_dict()
	invalid.battle_reports = ["broken"]
	_expect(not service.validate_run_state_payload(invalid).is_empty(), "嚴格解析應拒絕會被靜默丟棄的報告項目")
	for path in [service.get_run_path(), service.get_backup_path(), service.get_temp_path(), rejected_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory))
	for path in [legacy_service.get_run_path(), legacy_service.get_backup_path(), legacy_service.get_pre_slate_archive_path(), profile_marker_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(legacy_directory)


func _test_phase_18_profile_foundation() -> void:
	var test_directory := "/tmp/arkham_grid_test_profile_%d" % Time.get_ticks_usec()
	var service = ProfileSaveServiceScript.new(test_directory)
	var settings := SettingsState.new()
	_expect(service.save_settings(settings), "設定檔應可原子寫入：%s" % service.last_error)
	settings.locale = "en"
	settings.music_volume = 0.4
	_expect(service.save_settings(settings), "設定檔第二次保存應建立備份")
	_expect(FileAccess.file_exists(service.get_backup_path("settings")), "設定檔應保留 last-known-good 備份")
	var loaded_settings: Dictionary = service.load_settings()
	_expect(loaded_settings.get("ok", false) and loaded_settings.state.locale == "en" and is_equal_approx(loaded_settings.state.music_volume, 0.4), "設定檔 round-trip 應保留語言與音量")
	var broken := FileAccess.open(service.get_primary_path("settings"), FileAccess.WRITE)
	if broken != null:
		broken.store_string("{broken")
		broken = null
	var recovered_settings: Dictionary = service.load_settings()
	_expect(recovered_settings.get("ok", false) and recovered_settings.get("source") == "backup" and recovered_settings.state.locale == "zh_TW", "設定主檔損壞時應回退至上一份有效備份")

	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "Meta 預設內容測試前資料應有效：%s" % [registry.errors])
	var meta := MetaState.from_defaults(registry.get_document("meta_progression"))
	_expect(meta != null and meta.unlocked_profession_ids == ["investigator"] and meta.unlocked_spell_ids.size() == 20, "Meta 預設值應解鎖現有職業與內容，不改變當前平衡池")
	_expect(meta.unlock_spell("future_spell") and not meta.unlock_spell("future_spell"), "共享解鎖應只新增一次")
	_expect(not registry.validate_meta_state_references(meta).is_empty(), "ContentRegistry 應拒絕 Meta 中不存在的內容引用")
	meta.unlocked_spell_ids.erase("future_spell")
	meta.shared_currency = 25
	meta.runs_started = 2
	meta.record_run({"seed": 111, "victory": false, "reason": "測試敗北", "completed_nodes": 2, "battles_won": 1, "currency": 4, "hp": 0, "sanity": 30, "mp": 5, "finished_at_unix": 100}, 1)
	meta.record_run({"seed": 222, "victory": true, "reason": "測試勝利", "completed_nodes": 10, "battles_won": 7, "currency": 20, "hp": 12, "sanity": 18, "mp": 3, "finished_at_unix": 200, "defeat_source": ""}, 1)
	_expect(meta.mark_tutorial_seen("battle_time_pressure") and not meta.mark_tutorial_seen("battle_time_pressure"), "首次教學紀錄應只新增一次")
	_expect(service.save_meta(meta), "Meta 進度應可獨立保存：%s" % service.last_error)
	var loaded_meta: Dictionary = service.load_meta()
	_expect(loaded_meta.get("ok", false) and loaded_meta.state.shared_currency == 25 and loaded_meta.state.runs_started == 2, "Meta round-trip 應保留共享貨幣與 Run 統計")
	_expect(loaded_meta.get("ok", false) and loaded_meta.state.run_history.size() == 1 and loaded_meta.state.run_history[0].seed == 222, "Meta 應保存有上限的近期 Run 摘要")
	_expect(loaded_meta.get("ok", false) and loaded_meta.state.has_seen_tutorial("battle_time_pressure"), "Meta 應跨 Run 保存已顯示的教學")
	var legacy_meta := meta.to_dict()
	legacy_meta["schema_version"] = 1
	legacy_meta.erase("run_history")
	var legacy_meta_file := FileAccess.open(service.get_primary_path("meta"), FileAccess.WRITE)
	if legacy_meta_file != null:
		legacy_meta_file.store_string(JSON.stringify(legacy_meta))
		legacy_meta_file = null
	var migrated_meta: Dictionary = service.load_meta()
	_expect(migrated_meta.get("ok", false) and migrated_meta.get("migrated", false) and migrated_meta.state.run_history.is_empty() and migrated_meta.state.seen_tutorial_ids.is_empty(), "MetaState v1 應連續遷移至含 Run 歷史與教學進度的 v3")
	var version_two_meta := meta.to_dict()
	version_two_meta["schema_version"] = 2
	version_two_meta.erase("seen_tutorial_ids")
	for summary in version_two_meta.run_history:
		summary.erase("defeat_source")
	var version_two_file := FileAccess.open(service.get_primary_path("meta"), FileAccess.WRITE)
	if version_two_file != null:
		version_two_file.store_string(JSON.stringify(version_two_meta))
		version_two_file = null
	var migrated_version_two: Dictionary = service.load_meta()
	_expect(migrated_version_two.get("ok", false) and migrated_version_two.get("migrated", false) and migrated_version_two.state.run_history[0].defeat_source == "", "MetaState v2 應為既有歷史補上死因並遷移至 v3")
	var invalid_settings := settings.to_dict()
	invalid_settings.master_volume = 1.5
	_expect(not service.validate_settings_payload(invalid_settings).is_empty(), "設定驗證應拒絕超出範圍的音量")
	var invalid_meta := meta.to_dict()
	invalid_meta.unlocked_spell_ids.append(invalid_meta.unlocked_spell_ids[0])
	_expect(not service.validate_meta_payload(invalid_meta).is_empty(), "Meta 驗證應拒絕重複解鎖 ID")
	invalid_meta = meta.to_dict()
	invalid_meta.run_history[0].erase("reason")
	_expect(not service.validate_meta_payload(invalid_meta).is_empty(), "Meta 驗證應拒絕缺少結束原因的 Run 摘要")
	invalid_meta = meta.to_dict()
	invalid_meta.seen_tutorial_ids.append("battle_time_pressure")
	_expect(not service.validate_meta_payload(invalid_meta).is_empty(), "Meta 驗證應拒絕重複的教學進度 ID")
	for kind in ["settings", "meta"]:
		for path in [service.get_primary_path(kind), service.get_backup_path(kind), service.get_temp_path(kind)]:
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
	var conditional := EnemyIntentState.new()
	conditional.configure(["attack", "guard"], 0, [
		{"id": "wounded", "hp_ratio_lte": 0.5, "pattern": ["heavy_attack"]},
		{"id": "late", "turn_gte": 4, "pattern": ["buff_self"]},
	])
	_expect(conditional.current_intent_id(80, 100, 1) == "attack", "條件未成立時應使用基礎意圖")
	_expect(conditional.current_intent_id(40, 100, 1) == "heavy_attack", "低生命時應切換可預告的條件意圖")
	_expect(conditional.current_intent_id(80, 100, 4) == "buff_self", "指定回合後應切換條件意圖")

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
	_expect(actor.armor == 8, "防禦意圖應依資料獲得護甲")
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
	var pistol := registry.get_spell("pistol")
	_expect(pistol.tier == 1 and pistol.balance_cost == 10 and pistol.upgrade_to == "pistol_engraved", "runtime 咒文應包含 tier、balance_cost 與升級關係")
	var upgraded := registry.get_spell("pistol_engraved")
	_expect(upgraded != null and upgraded.tier == 2 and upgraded.rarity == "uncommon", "升級結果應建立為獨立 runtime Resource")

	var growth = SpellUpgradeServiceScript.new()
	var inventory := {"pistol": 1}
	var growth_result := growth.add_to_collection("pistol", inventory, registry.indexes.get("spells", {}))
	_expect(growth_result.get("spell_id") == "pistol_engraved", "兩份相同咒文應依 JSON 關係合成升級")
	_expect(int(inventory.get("pistol", 0)) == 0 and int(inventory.get("pistol_engraved", 0)) == 1, "合成應正確消耗背包數量")

	var encounter_defs: Array = [registry.get_definition("enemies", "rotting_hound"), registry.get_definition("enemies", "abyss_thrall")]
	var calculator = EncounterDifficultyCalculatorScript.new()
	var metrics := calculator.calculate(encounter_defs, registry.get_document("run_config").get("difficulty_model", {}))
	var early_pressure := calculator.calculate(encounter_defs, registry.get_document("run_config").get("difficulty_model", {}), {"node_depth": 0})
	var late_pressure := calculator.calculate(encounter_defs, registry.get_document("run_config").get("difficulty_model", {}), {"node_depth": 9})
	_expect(int(early_pressure.get("turn_limit", 0)) > int(late_pressure.get("turn_limit", 0)) and int(late_pressure.get("turn_limit", 0)) >= 4, "後段節點的戰鬥時限應更嚴格且保留最低行動窗口")
	_expect(int(metrics.get("strength", 0)) > 0 and int(metrics.get("reward_tier", 0)) >= 1, "encounter 應產生可解釋的強度與獎勵 tier")

	var selector = RewardCandidateSelectorScript.new()
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 777
	second_rng.seed = 777
	var context := {"battles_won": 3, "reward_tier": 2, "unlocked_reward_ids": []}
	var first := selector.pick(registry.get_entries("rewards"), registry.indexes.get("spells", {}), registry.indexes.get("blocks", {}), context, 3, first_rng)
	var second := selector.pick(registry.get_entries("rewards"), registry.indexes.get("spells", {}), registry.indexes.get("blocks", {}), context, 3, second_rng)
	_expect(first == second and first.size() == 3, "相同強度與種子應產生可重現的三選一")
	var candidate_pairs: Array[String] = []
	var unique_candidate_pairs := {}
	for reward in first:
		var candidate_pair := "%s|%s" % [reward.get("spell_id", ""), reward.get("shape_id", "")]
		candidate_pairs.append(candidate_pair)
		unique_candidate_pairs[candidate_pair] = true
		var shape := registry.get_definition("blocks", str(reward.get("shape_id", "")))
		var spell := registry.get_definition("spells", str(reward.get("spell_id", "")))
		_expect(SlatePairingRulesScript.new().is_allowed(shape, spell), "獎勵石板必須符合咒文強度與形狀複雜度規則")
	_expect(candidate_pairs.size() == unique_candidate_pairs.size(), "同一次三選一不應出現完全相同的咒文＋形狀")
	var elite_context := context.duplicate(true)
	elite_context.reward_tier = 3
	elite_context.force_block_reward = true
	var elite_rewards := selector.pick(registry.get_entries("rewards"), registry.indexes.get("spells", {}), registry.indexes.get("blocks", {}), elite_context, 3, first_rng)
	_expect(elite_rewards.any(func(reward): return bool(registry.get_definition("blocks", str(reward.get("shape_id", ""))).get("special", false))), "菁英獎勵候選應保底包含一個未取得的特殊形狀")
	var owned_block_context := context.duplicate(true)
	owned_block_context.owned_special_shape_ids = ["special_dot"]
	var owned_block_rewards := selector.pick(registry.get_entries("rewards"), registry.indexes.get("spells", {}), registry.indexes.get("blocks", {}), owned_block_context, 20, first_rng)
	_expect(not owned_block_rewards.any(func(reward): return str(reward.get("shape_id", "")) == "special_dot"), "已取得的特殊形狀不應再次進入獎勵池")
	var meta_limited_context := context.duplicate(true)
	meta_limited_context.meta_unlocked_spell_ids = ["pistol"]
	meta_limited_context.meta_unlocked_block_ids = ["shape_T", "shape_O", "special_dot"]
	var meta_limited_rewards := selector.pick(registry.get_entries("rewards"), registry.indexes.get("spells", {}), registry.indexes.get("blocks", {}), meta_limited_context, 20, first_rng)
	_expect(meta_limited_rewards.all(func(reward): return str(reward.get("spell_id", "")) == "pistol" and str(reward.get("shape_id", "")) in ["shape_T", "shape_O"]), "獎勵石板的咒文與形狀都應受到共享 Meta 解鎖池限制")

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
	var normal_content_by_floor := {}
	for node in generated_a.get("nodes", []):
		generated_types[str(node.get("type", ""))] = true
		if str(node.get("type", "")) == "normal_battle":
			normal_floors[int(node.get("floor", -1))] = true
			normal_content_by_floor[int(node.get("floor", -1))] = str(node.get("content_id", ""))
	for required_type in ["normal_battle", "elite", "event", "shop", "rest", "boss"]:
		_expect(generated_types.has(required_type), "生成路線應包含節點類型：%s" % required_type)
	var battle_range := _generated_path_battle_range(generated_a)
	_expect(int(map_document.get("generation", {}).get("floors", 0)) == 10 and boss_floor == 9, "程序地圖深度應固定為 10 層")
	_expect(int(battle_range.get("min", 0)) == 7 and int(battle_range.get("max", 0)) == 7, "10 層路線應固定包含 7 場戰鬥")
	_expect(normal_floors.size() == 5, "10 層地圖應包含五層普通戰鬥")
	var ordered_normal_floors: Array = normal_content_by_floor.keys()
	ordered_normal_floors.sort()
	var ordered_normal_content: Array[String] = []
	for floor in ordered_normal_floors:
		ordered_normal_content.append(str(normal_content_by_floor[floor]))
	_expect(ordered_normal_content == ["encounter_01", "encounter_02", "encounter_04", "encounter_07", "encounter_08"], "10 層地圖的普通遭遇應依進度輪替且不重複後段編成")
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
	_expect(rules.modify_spell_mp_cost(3) == 4, "儀式執著行為 Resource 應增加咒文 MP 成本")
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
	_expect(rules.get_source_label("spell:fallback:pistol") == "咒文", "MP 不足的 Sanity 代付應使用可讀的咒文來源標籤")
	var loss_history: Array[Dictionary] = [
		{"source": "spell:fallback:pistol", "delta": -3, "after": 4},
		{"source": "battle_time:encounter_01", "delta": -4, "after": 0},
		{"source": "rest:boss_rest", "delta": 5, "after": 5},
	]
	var losses := rules.summarize_losses(loss_history)
	var depletion := rules.get_depletion_source(loss_history)
	_expect(losses == {"spell": 3, "battle_time": 4}, "Sanity 統計應依來源前綴彙總實際損失")
	_expect(depletion.key == "battle_time" and depletion.label == "戰鬥超時", "Sanity 歸零應記錄最後致死來源與可讀標籤")
	player.free()
	var simulation: Dictionary = registry.get_document("sanity").get("simulation", {})
	var before_rest := 70 - int(simulation.get("dead_boards_per_run", 1)) * 10 - int(simulation.get("enemy_sanity_hits_per_run", 2)) * int(simulation.get("enemy_sanity_hit", 4)) - int(simulation.get("time_pressure_sanity_per_run", 0))
	_expect(before_rest >= int(simulation.get("acceptance_min_sanity_before_rest", 15)) and before_rest <= int(simulation.get("acceptance_max_sanity_before_rest", 55)), "完整 Run 基準情境的休息前 Sanity 應落在驗收區間")


func _test_phase_16_content_integrity() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "Phase 16 內容關係應通過完整驗證：%s" % [registry.errors])
	if not registry.errors.is_empty():
		return
	var state := RunState.new()
	var config := registry.get_document("run_config")
	state.slate_pool = RunState._dictionaries(config.get("starter_slates", []))
	state.board_spell_ids.resize(64)
	state.board_spell_ids.fill("")
	var generator = LayeredMapGeneratorScript.new()
	state.map_data = generator.generate(13579, registry.get_document("map"))
	state.available_node_ids = RunState._strings(state.map_data.get("start_node_ids", []))
	_expect(registry.validate_run_state_references(state).is_empty(), "現行內容建立的 RunState 引用應全部有效")

	var invalid := RunState.from_dict(state.to_dict())
	invalid.slate_pool[0].shape_id = "missing_block"
	invalid.slate_pool[1].spell_id = "missing_spell"
	invalid.sanity_effect_ids.append("missing_effect")
	invalid.available_node_ids.append("missing_node")
	invalid.map_data.nodes[0].content_id = "missing_encounter"
	var reference_errors := registry.validate_run_state_references(invalid)
	_expect(reference_errors.size() >= 5, "RunState 還原前應捕獲石板形狀、咒文、Sanity、節點與 encounter 失效引用")


func _test_phase_16_data_driven_events() -> void:
	var registry := ContentRegistry.new()
	_expect(registry.load_all(), "事件測試前內容資料應有效：%s" % [registry.errors])
	if not registry.errors.is_empty():
		return
	var event_definition := registry.get_definition("events", "prototype_event")
	_expect(event_definition.get("options", []).size() == 3, "原型事件應提供三個資料化選項")
	var shop_definition := registry.get_definition("shops", "prototype_shop")
	var rest_definition := registry.get_definition("rests", "boss_rest")
	_expect(shop_definition.get("options", []).size() == 5, "商店應提供資源交易、咒文購買與離開選項")
	_expect(rest_definition.get("options", []).size() == 3, "休息應提供身心休養、MP 專注與離開選項")
	var resolver = EventChoiceResolverScript.new()
	var state := {"hp": 40, "max_hp": 80, "sanity": 70, "max_sanity": 100, "mp": 25, "max_mp": 100, "currency": 20}
	var snapshot := state.duplicate(true)
	var study: Dictionary = resolver.resolve_choice(event_definition, "study_fragments", state)
	_expect(study.get("valid", false) and study.get("affordable", false), "資源足夠時事件選項應可執行")
	_expect(study.get("changes", {}).get("sanity") == 64 and study.get("changes", {}).get("currency") == 38, "事件應依資料同時套用代價與結果")
	_expect(state == snapshot, "事件預覽與結算不應直接修改輸入狀態")
	var healed: Dictionary = resolver.resolve_choice(event_definition, "bind_the_wound", {"hp": 40, "max_hp": 80, "sanity": 95, "max_sanity": 100, "currency": 0})
	_expect(healed.get("changes", {}).get("hp") == 32 and healed.get("changes", {}).get("sanity") == 100, "事件回復應受到資源上限限制")
	var unaffordable: Dictionary = resolver.resolve_choice(event_definition, "study_fragments", {"hp": 40, "max_hp": 80, "sanity": 6, "max_sanity": 100, "currency": 0})
	_expect(not unaffordable.get("affordable", true), "事件不得讓 HP 或 Sanity 因支付代價降至零")
	_expect(not resolver.resolve_choice(event_definition, "missing_option", state).get("valid", true), "未知事件選項應明確失敗")
	var mana_purchase: Dictionary = resolver.resolve_choice(shop_definition, "buy_mana_vial", state)
	_expect(mana_purchase.get("affordable", false) and mana_purchase.get("changes", {}).get("currency") == 8 and mana_purchase.get("changes", {}).get("mp") == 60, "商店應以金錢交換 MP 並保留其他資源")
	var poor_purchase: Dictionary = resolver.resolve_choice(shop_definition, "buy_tonic", {"hp": 40, "max_hp": 80, "sanity": 70, "max_sanity": 100, "mp": 25, "max_mp": 100, "currency": 14})
	_expect(not poor_purchase.get("affordable", true), "金錢不足時商店商品應禁用")
	var spell_purchase: Dictionary = resolver.resolve_choice(shop_definition, "buy_ward_script", {"hp": 40, "max_hp": 80, "sanity": 70, "max_sanity": 100, "mp": 25, "max_mp": 100, "currency": 30})
	_expect(spell_purchase.get("affordable", false) and spell_purchase.get("changes", {}).get("currency") == 5, "資源足夠時商店應可購買咒文")
	_expect(spell_purchase.get("grant", {}).get("type") == "slate" and spell_purchase.get("grant", {}).get("spell_id") == "heal_light" and spell_purchase.get("grant", {}).get("shape_id") == "shape_T", "商店商品應在選擇前提供固定形狀、咒文與效果格")
	var deep_rest: Dictionary = resolver.resolve_choice(rest_definition, "deep_rest", state)
	_expect(deep_rest.get("changes", {}).get("hp") == 80 and deep_rest.get("changes", {}).get("sanity") == 100 and deep_rest.get("changes", {}).get("mp") == 25, "安穩休養應回滿 HP／Sanity 且不額外更動 MP")
	var focus_rest: Dictionary = resolver.resolve_choice(rest_definition, "focus_ritual", state)
	_expect(focus_rest.get("changes", {}).get("mp") == 100 and focus_rest.get("changes", {}).get("hp") == 40, "專注冥想應回滿 MP 且不額外更動 HP")


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

	var special := registry.get_block("special_dot")
	var special_draw_counts: Array[int] = []
	for copies in [1]:
		var grown_pool: Array[BlockData] = []
		grown_pool.assign(blocks)
		for _copy in range(copies):
			grown_pool.append(special)
		var special_draws := 0
		for sample in range(120):
			var session := simulator.create_session(grown_pool, rules, {
				"mode": BoardSimulatorScript.SMART_MODE,
				"seed": 50000 + sample,
				"hand_size": 3,
				"action_points": 5,
			})
			_expect(simulator.begin_session_turn(session), "特殊方塊分布測試應可產生手牌")
			var hand_ids := {}
			for drawn in session.get("hand", []):
				hand_ids[drawn.id] = true
				if drawn.id == "special_dot":
					special_draws += 1
			_expect(hand_ids.size() == 3, "候選種類足夠時，同一手牌不可出現重複方塊 ID")
		special_draw_counts.append(special_draws)
	_expect(special_draw_counts[0] > 0 and special_draw_counts[0] < 45, "一份星點石板應偶爾出現，但不可支配 360 張樣本手牌")

	var spell := registry.get_spell("pistol")
	var board_spells := {
		Vector2i(2, 2): spell,
		Vector2i(5, 2): registry.get_spell("vest"),
	}
	var intersection_spells: Array[BattleItem] = simulator._collect_cleared_spells(board_spells, [2], [2])
	_expect(intersection_spells.size() == 2 and board_spells.is_empty(), "Row／Col 交叉消除時，每個效果格只能觸發一次")
	var marked := blocks[0].with_spell(spell, blocks[0].cells.back())
	var marked_rotated := marked.rotated(1)
	_expect(marked_rotated.spell.content_id == spell.content_id and marked_rotated.effect_cell == Vector2i(-marked.effect_cell.y, marked.effect_cell.x), "方塊旋轉應同步旋轉效果格，且形狀與咒文保持獨立")

	var tiny_pool: Array[BlockData] = [blocks[0], blocks[1]]
	var tiny_session := simulator.create_session(tiny_pool, rules, {"mode": BoardSimulatorScript.SMART_MODE, "seed": 9876, "hand_size": 3, "action_points": 5})
	_expect(simulator.begin_session_turn(tiny_session) and tiny_session.get("hand", []).size() == 3, "方塊種類少於手牌數時應允許 fallback 重複以補滿手牌")


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
	var options := {"seed": 97531, "battles": 2, "max_turns": 4, "difficulty_model": config.get("difficulty_model", {})}
	var arguments := [
		[registry.get_entries("encounters")[0]],
		enemy_index,
		intent_index,
		registry.get_document("player"),
		registry.get_spells(config.get("spell_pool", [])),
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
	_expect(report.has("average_mp_spent") and report.has("average_spell_fizzles"), "戰鬥批次應量測咒文 MP 消耗與不足失敗")
	_expect(report.has("sanity_defeat_sources"), "戰鬥批次應輸出 Sanity 死因分項")

	var manager := preload("res://scripts/battle_manager.gd").new()
	manager.player = _make_entity("MP 測試玩家", 40, 70)
	manager.enemies = [_make_entity("MP 測試敵人", 40)]
	manager.enemy = manager.enemies[0]
	manager.battle_active = true
	manager._battle_stats.reset("mp_test")
	manager.sanity_rules.configure(registry.get_document("sanity"), 1)
	manager.mp = 0
	var hp_before := manager.enemy.hp
	_expect(manager.execute_spell(registry.get_spell("pistol")) and manager.enemy.hp == hp_before - 10 and manager.player.sanity == 67, "MP 不足時應改以同額 Sanity 支付並照常發動咒文")
	_expect(int(manager._battle_stats.values.get("spells_paid_with_sanity", 0)) == 1 and int(manager._battle_stats.values.get("spell_fizzles", 0)) == 0, "Sanity 代付應獨立記錄且不算咒文失敗")
	manager.mp = 3
	_expect(manager.execute_spell(registry.get_spell("pistol")) and manager.mp == 0 and manager.player.sanity == 67 and manager.enemy.hp == hp_before - 20, "MP 足夠時應優先扣除 MP，不消耗 Sanity")
	manager.turn_limit = 1
	manager.time_pressure_sanity_base = 2
	manager.time_pressure_sanity_growth = 2
	manager._battle_stats.values.turns = 2
	manager._apply_time_pressure_if_needed()
	manager._battle_stats.values.turns = 3
	manager._apply_time_pressure_if_needed()
	_expect(manager.player.sanity == 61 and int(manager._battle_stats.values.get("time_pressure_sanity", 0)) == 6 and int(manager._battle_stats.values.get("overdue_turns", 0)) == 2, "超過戰鬥時限後應每回合以 2、4…加速扣除 Sanity")
	manager.sanity_history = [{"source": "battle_time:mp_test", "source_label": "戰鬥超時", "delta": -2, "before": 2, "after": 0, "active_effect_ids": []}]
	manager._battle_sanity_history_start = 0
	manager.player.sanity = 0
	manager.battle_active = true
	var captured_result := {}
	manager.battle_finished.connect(func(result: BattleResult): captured_result["value"] = result)
	manager._finish_battle(false, "Sanity 歸零")
	var defeat_result := captured_result.get("value") as BattleResult
	_expect(defeat_result != null and defeat_result.reason == "Sanity 歸零（戰鬥超時）", "Sanity 敗北結算應顯示實際致死來源")
	_expect(defeat_result != null and defeat_result.statistics.get("sanity_defeat_source") == "battle_time" and defeat_result.statistics.get("sanity_loss_by_source") == {"battle_time": 2}, "戰鬥報告應保存 Sanity 死因與分項損失")
	manager.player.free()
	manager.enemy.free()
	manager.free()


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
	_expect(first.has("average_mp_end") and not first.get("pressure_curve", []).is_empty(), "完整 Run 模擬應輸出逐場 HP／Sanity／MP 壓力曲線")


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
	var tablet_ui = instance.get_node("UILayer/ScreenMargin/Screen/Layout/BoardPanel/BoardVBox/TabletSection")
	var grid := tablet_ui.get_node("Body/GridCells") as Control
	var stable_board_position := grid.global_position
	for held in tablet_ui._get_hand_blocks():
		held.queue_free()
		await process_frame
		_expect(grid.global_position.distance_to(stable_board_position) <= 0.5, "手牌由三張降至零張時棋盤位置不得位移")
	tablet_ui.refill_hand()
	var graph = instance.get_node_or_null("UILayer/MapContainer/Margin/Panel/VBox/Scroll/Center/Graph")
	_expect(graph != null and graph.get_edge_count() > 0, "地圖畫布應建立可見的節點連線資料")
	_expect(FileAccess.file_exists(run_manager.save_service.get_run_path()), "新 Run 建立後應寫入單一自動存檔槽")
	var player_hud := instance.get_node_or_null("UILayer/ScreenMargin/Screen/Layout/InfoSection/PlayerHUD") as PlayerHUD
	var system_menu := instance.get_node_or_null("UILayer/SystemMenu") as SystemMenu
	_expect(player_hud != null and player_hud.hp_bar.value == manager.player.hp, "正式 HUD 應以資源條呈現玩家狀態")
	_expect(system_menu != null and system_menu.visible, "啟動時應顯示可繼續、新遊戲與設定的主選單")
	_expect(InputMap.has_action("hand_slot_1") and InputMap.has_action("place_selected") and InputMap.has_action("toggle_pause"), "PC 鍵盤操作應完成輸入映射")
	instance._resume_game()
	var payment_label := instance.get_node_or_null("UILayer/ScreenMargin/Screen/Layout/InfoSection/Actions/VBox/PaymentPreviewLabel") as Label
	var legend_label := instance.get_node_or_null("UILayer/ScreenMargin/Screen/Layout/InfoSection/SpellLegendLabel") as Label
	var original_mp: int = manager.mp
	var original_sanity: int = manager.player.sanity
	manager.mp = 0
	manager.player.sanity = 2
	manager._on_payment_preview_changed([run_manager.content.get_spell("pistol")])
	_expect(payment_label != null and "代付 SAN" in payment_label.text and "理智歸零" in payment_label.text, "支付預覽應顯示 MP 不足的 Sanity 代付與致死警告")
	manager.mp = original_mp
	manager.player.sanity = original_sanity
	manager._toggle_spell_legend()
	_expect(legend_label != null and legend_label.visible and "秘銀飛矢" in legend_label.text, "咒文圖例應可展開並顯示目前池中的圖標、名稱與效果")
	manager._toggle_spell_legend()
	var build_pool_view := instance.get_node_or_null("UILayer/BuildPoolView") as Control
	run_manager._show_build_pool()
	var spell_grid := build_pool_view.get_node_or_null("Background/Margin/Panel/VBox/Scroll/Content/SpellGrid") if build_pool_view != null else null
	_expect(build_pool_view != null and build_pool_view.visible and spell_grid != null and spell_grid.get_child_count() > 0, "地圖應可開啟戰鬥外咒文與方塊構築檢視")
	build_pool_view.hide_pool()
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
			# 程序地圖會在事件池抽取內容；smoke test 固定為既有事件以驗證指定選項與來源記錄。
			event_node["content_id"] = "prototype_event"
			run_manager.map_node_index[str(event_node.get("id", ""))]["content_id"] = "prototype_event"
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
		var shop_node := {}
		for candidate in run_manager.runtime_map.get("nodes", []):
			if str(candidate.get("type", "")) == "shop":
				shop_node = candidate
				break
		_expect(not shop_node.is_empty(), "程序地圖應包含可操作的商店節點")
		if not shop_node.is_empty():
			run_manager.run_state.currency = 20
			manager.mp = 20
			run_manager.flow.transition(run_manager.flow.State.NODE)
			run_manager.run_state.flow_state = run_manager.flow.current_state
			run_manager.run_state.current_node_id = str(shop_node.get("id", ""))
			run_manager._show_choice_node(shop_node)
			_expect(event_view.visible and event_view.get_option_buttons().size() == 5, "商店節點應使用共用選項介面並顯示五個選項")
			run_manager._on_event_choice_selected("buy_mana_vial")
			_expect(run_manager.run_state.currency == 8 and run_manager.run_state.mp == 100, "商店購買應扣除金錢、回復 MP，再套用固定節點 MP 回復")
			run_manager.start_new_run()
		var rest_node := {}
		for candidate in run_manager.runtime_map.get("nodes", []):
			if str(candidate.get("type", "")) == "rest":
				rest_node = candidate
				break
		_expect(not rest_node.is_empty(), "程序地圖應包含可操作的休息節點")
		if not rest_node.is_empty():
			manager.player.hp = 30
			manager.player.sanity = 40
			manager.mp = 10
			run_manager.flow.transition(run_manager.flow.State.NODE)
			run_manager.run_state.flow_state = run_manager.flow.current_state
			run_manager.run_state.current_node_id = str(rest_node.get("id", ""))
			run_manager._show_choice_node(rest_node)
			_expect(event_view.visible and event_view.get_option_buttons().size() == 3, "休息節點應使用共用選項介面並顯示三個選項")
			run_manager._on_event_choice_selected("deep_rest")
			_expect(run_manager.run_state.hp == 80 and run_manager.run_state.sanity == 100 and run_manager.run_state.mp == 60, "安穩休養應回滿 HP／Sanity，並保留節點完成的固定 MP 回復")
			run_manager.start_new_run()
	var tablet = manager.tablet
	var special_block: BlockData = run_manager.content.get_block("special_dot").as_slate("test_special_dot", run_manager.content.get_spell("poison_spell"), Vector2i.ZERO)
	var special_count_before: int = tablet.get_block_pool_count("special_dot")
	tablet.add_slate(special_block)
	tablet.add_slate(special_block.duplicate(true))
	_expect(tablet.get_block_pool_count("special_dot") == maxi(special_count_before, 1), "同一特殊形狀不得重複加入方塊池")
	_expect(run_manager.flow.current_state == run_manager.flow.State.MAP, "新 Run 應先進入地圖選擇")
	var first_node_id: String = run_manager.run_state.available_node_ids[0]
	_expect(run_manager.select_map_node(first_node_id), "玩家應可選擇生成地圖的起點")
	_expect(run_manager.meta_state.has_seen_tutorial("battle_time_pressure"), "第一次進入限時戰鬥應顯示並保存時限教學")
	_expect(run_manager.result_label.text.contains("時限提示"), "首次時限教學應以非阻斷文字顯示在戰鬥資訊區")
	tablet._select_hand_index(0)
	_expect(tablet._keyboard_selected_block != null and not tablet._current_preview_cells.is_empty(), "數字鍵選取流程應建立可見的鍵盤放置預覽")
	var origin_before_input: Vector2i = tablet._keyboard_origin
	var move_event := InputEventAction.new()
	move_event.action = "board_right"
	move_event.pressed = true
	tablet._unhandled_input(move_event)
	_expect(tablet._keyboard_origin.x >= origin_before_input.x, "WASD 操作應可移動鍵盤放置位置")
	tablet._select_block(null)
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
	_expect(manager.player.hp == hp_before - 10, "核心迴圈應依調整後的資料化 attack 意圖完成敵人回合")
	_expect(int(manager._battle_stats.values.get("damage_taken", 0)) == 10, "戰鬥統計應記錄調整後的承受傷害")
	_expect(manager.current_turn == manager.TurnState.PLAYER_TURN, "敵人回合結束後應回到玩家回合")
	_expect(tablet.get_hand_state() == hand_before_turn, "回合結束時未使用的手牌與旋轉方向應保留")
	var board_before_reward: Array[String] = tablet.get_board_state()
	manager.start_encounter([
		run_manager.content.get_definition("enemies", "rotting_hound"),
		run_manager.content.get_definition("enemies", "abyss_thrall"),
	])
	manager.enemies[0].take_damage(9999)
	await process_frame
	_expect(manager.selected_enemy_index == 1 and manager._get_targets_for_scope("single") == [manager.enemies[1]], "鎖定目標死亡後應自動改鎖第一名存活敵人")
	for active_enemy in manager.enemies:
		if active_enemy != null and not active_enemy.is_dead:
			active_enemy.take_damage(9999)
	await process_frame
	await process_frame
	_expect(run_manager.flow.current_state == run_manager.flow.State.REWARD, "普通戰鬥勝利後應由狀態機進入獎勵")
	var mp_before_node_completion: int = manager.mp
	run_manager._on_reward_skipped(10)
	await process_frame
	_expect(run_manager.flow.current_state == run_manager.flow.State.MAP, "獎勵結算後應返回地圖")
	_expect(manager.mp == mini(mp_before_node_completion + 50, manager.max_mp), "完成節點後應依設定固定回復 50 MP")
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
