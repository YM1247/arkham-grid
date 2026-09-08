extends Node
class_name RunManager

const EncounterDifficultyCalculatorScript = preload("res://scripts/growth/encounter_difficulty_calculator.gd")
const RewardCandidateSelectorScript = preload("res://scripts/growth/reward_candidate_selector.gd")
const RunStateMachineScript = preload("res://scripts/run/run_state_machine.gd")
const LayeredMapGeneratorScript = preload("res://scripts/run/layered_map_generator.gd")
const RunNodeResultScript = preload("res://scripts/run/run_node_result.gd")
const EventChoiceResolverScript = preload("res://scripts/run/event_choice_resolver.gd")
const SaveGameServiceScript = preload("res://scripts/save/save_game_service.gd")
const ProfileSaveServiceScript = preload("res://scripts/save/profile_save_service.gd")

@export var battle_manager_path: NodePath
@export var tablet_path: NodePath
@export var result_label_path: NodePath
@export var reward_panel_path: NodePath
@export var reward_buttons_container_path: NodePath
@export var map_container_path: NodePath
@export var event_view_path: NodePath
@export var settlement_screen_path: NodePath
@export var save_directory := "user://saves"

var battle_manager: Node
var tablet: Node
var result_label: Label
var reward_panel: Control
var reward_buttons_container: BoxContainer
var map_container: Control
var event_view: Control
var settlement_screen: Control

var enemies: Array = []
var encounters: Array = []
var reward_pool: Array = []
var block_resources := {}
var spell_resources := {}
var current_enemy_index := 0
var current_encounter_index := 0
var battles_won := 0
var current_rewards: Array = []
var rng := RandomNumberGenerator.new()
var content := ContentRegistry.new()
var run_state := RunState.new()
var difficulty_calculator = EncounterDifficultyCalculatorScript.new()
var reward_selector = RewardCandidateSelectorScript.new()
var current_difficulty: Dictionary = {}
var _latest_report_index := -1
var flow = RunStateMachineScript.new()
var map_generator = LayeredMapGeneratorScript.new()
var runtime_map: Dictionary = {}
var map_node_index: Dictionary = {}
var event_choice_resolver = EventChoiceResolverScript.new()
var save_service
var profile_service
var settings_state := SettingsState.new()
var meta_state := MetaState.new()

func _ready() -> void:
	var configured_save_directory := str(ProjectSettings.get_setting("arkham_grid/testing/save_directory", save_directory))
	save_service = SaveGameServiceScript.new(configured_save_directory)
	profile_service = ProfileSaveServiceScript.new(configured_save_directory)
	battle_manager = get_node_or_null(battle_manager_path)
	tablet = get_node_or_null(tablet_path)
	result_label = get_node_or_null(result_label_path) as Label
	reward_panel = get_node_or_null(reward_panel_path) as Control
	reward_buttons_container = get_node_or_null(reward_buttons_container_path) as BoxContainer
	map_container = get_node_or_null(map_container_path) as Control
	event_view = get_node_or_null(event_view_path) as Control
	settlement_screen = get_node_or_null(settlement_screen_path) as Control
	
	if battle_manager == null or tablet == null:
		push_error("RunManager 設定錯誤：缺少 BattleManager 或 TabletSection。")
		return
	
	if not content.load_all():
		for error in content.errors:
			push_error("資料驗證失敗：%s" % error)
		_set_result_text("資料載入失敗，請查看錯誤輸出。")
		return
	_load_profile_data()
	if battle_manager.has_signal("battle_finished"):
		battle_manager.battle_finished.connect(_on_battle_finished)
	else:
		battle_manager.battle_won.connect(_on_battle_won)
		battle_manager.battle_lost.connect(_on_battle_lost)
	_load_run_data()
	if map_container != null and map_container.has_signal("node_selected"):
		map_container.node_selected.connect(select_map_node)
	if event_view != null and event_view.has_signal("choice_selected"):
		event_view.choice_selected.connect(_on_event_choice_selected)
	if settlement_screen != null and settlement_screen.has_signal("restart_requested"):
		settlement_screen.restart_requested.connect(start_new_run)
	if not continue_autosave():
		start_new_run()

func _load_run_data() -> void:
	enemies = content.get_entries("enemies")
	encounters = content.get_entries("encounters")
	reward_pool = content.get_entries("rewards")
	block_resources = content.block_resources
	spell_resources = content.spell_resources


func _load_profile_data() -> void:
	var settings_result: Dictionary = profile_service.load_settings()
	if bool(settings_result.get("ok", false)) and settings_result.get("state") is SettingsState:
		settings_state = settings_result.state
	else:
		settings_state = SettingsState.new()
		if not profile_service.save_settings(settings_state):
			push_warning("無法建立設定檔：%s" % profile_service.last_error)
	var meta_result: Dictionary = profile_service.load_meta()
	if bool(meta_result.get("ok", false)) and meta_result.get("state") is MetaState:
		var loaded_meta: MetaState = meta_result.state
		var reference_errors := content.validate_meta_state_references(loaded_meta)
		if reference_errors.is_empty():
			meta_state = loaded_meta
		else:
			push_warning("Meta 內容引用失效，本次使用預設值且不覆寫來源：%s" % "; ".join(reference_errors))
			meta_state = MetaState.from_defaults(content.get_document("meta_progression"))
	else:
		meta_state = MetaState.from_defaults(content.get_document("meta_progression"))
		if not profile_service.save_meta(meta_state):
			push_warning("無法建立 Meta 存檔：%s" % profile_service.last_error)
	_apply_settings()


func _apply_settings() -> void:
	TranslationServer.set_locale(settings_state.locale)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings_state.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			continue
		var linear := settings_state.master_volume
		if bus_name == "Music":
			linear *= settings_state.music_volume
		elif bus_name == "SFX":
			linear *= settings_state.sfx_volume
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear, 0.0001)))


func save_settings() -> bool:
	_apply_settings()
	return profile_service.save_settings(settings_state)


func unlock_meta_content(kind: String, id: String) -> bool:
	var valid := false
	match kind:
		"profession": valid = id == str(content.get_document("player").get("profession_id", ""))
		"block": valid = content.get_block(id) != null
		"spell": valid = content.get_spell(id) != null
	if not valid:
		return false
	var changed := meta_state.unlock_profession(id) if kind == "profession" else meta_state.unlock_block(id) if kind == "block" else meta_state.unlock_spell(id)
	return profile_service.save_meta(meta_state) if changed else true

func _apply_run_config() -> void:
	var config := content.get_document("run_config")
	var player_config := content.get_document("player")
	run_state.seed = int(config.get("seed", Time.get_unix_time_from_system()))
	run_state.player_name = str(player_config.get("name", "調查員"))
	run_state.profession_id = str(player_config.get("profession_id", "investigator"))
	if run_state.profession_id not in meta_state.unlocked_profession_ids and not meta_state.unlocked_profession_ids.is_empty():
		run_state.profession_id = meta_state.unlocked_profession_ids[0]
	run_state.max_hp = int(player_config.get("max_hp", 80))
	run_state.hp = int(player_config.get("hp", run_state.max_hp))
	run_state.max_sanity = int(player_config.get("max_sanity", 100))
	run_state.sanity = int(player_config.get("sanity", 70))
	run_state.max_mp = int(player_config.get("max_mp", 100))
	run_state.mp = int(player_config.get("mp", 70))
	run_state.action_points = int(player_config.get("action_points", 5))
	run_state.block_pool_ids = _filter_meta_unlocked(config.get("block_pool", []), meta_state.unlocked_block_ids)
	run_state.spell_pool_ids = _filter_meta_unlocked(config.get("spell_pool", []), meta_state.unlocked_spell_ids)
	if battle_manager.has_method("configure_player"):
		battle_manager.configure_player(
			run_state.player_name, run_state.max_hp, run_state.hp,
			run_state.max_sanity, run_state.sanity, run_state.action_points,
			run_state.max_mp, run_state.mp
		)
	if battle_manager.has_method("configure_sanity_rules"):
		battle_manager.configure_sanity_rules(content.get_document("sanity"), run_state.seed, run_state.sanity_effect_ids, run_state.sanity_history)
	
	if tablet.has_method("set_block_pool"):
		tablet.set_block_pool(content.get_blocks(run_state.block_pool_ids))
	if tablet.has_method("set_spell_pool"):
		tablet.set_spell_pool(content.get_spells(run_state.spell_pool_ids))
	if tablet.has_method("set_board_growth_rules"):
		tablet.set_board_growth_rules(config.get("board_growth_rules", {}))
	

func start_new_run() -> void:
	run_state = RunState.new()
	current_encounter_index = 0
	battles_won = 0
	_latest_report_index = -1
	_apply_run_config()
	meta_state.runs_started += 1
	if not profile_service.save_meta(meta_state):
		push_warning("無法更新 Meta Run 計數：%s" % profile_service.last_error)
	rng.seed = run_state.seed
	if tablet.has_method("set_rng_seed"):
		tablet.set_rng_seed(run_state.seed ^ 0x41C64E6D)
	if tablet.has_method("reset_tablet"):
		tablet.reset_tablet()
	flow.reset()
	var map_template := content.get_document("map")
	runtime_map = map_generator.generate(run_state.seed, map_template) if bool(map_template.get("generation", {}).get("enabled", false)) else map_template
	if not map_generator.verify_connectivity(runtime_map):
		push_error("生成地圖無法從所有起點抵達 Boss。")
		_finish_run(false, "地圖生成失敗")
		return
	_index_runtime_map()
	run_state.map_data = runtime_map.duplicate(true)
	run_state.available_node_ids = _strings(runtime_map.get("start_node_ids", []))
	run_state.completed_node_ids.clear()
	run_state.current_node_id = ""
	if battle_manager != null:
		battle_manager.battle_active = false
	flow.transition(flow.State.MAP)
	run_state.flow_state = flow.current_state
	if settlement_screen != null and settlement_screen.has_method("hide_result"):
		settlement_screen.hide_result()
	_show_map()
	_autosave("new_run")

func _index_runtime_map() -> void:
	map_node_index.clear()
	for node in runtime_map.get("nodes", []):
		map_node_index[str(node.get("id", ""))] = node

func _show_map() -> void:
	_hide_rewards()
	_hide_event()
	if tablet.has_method("set_placement_enabled"):
		tablet.set_placement_enabled(false)
	if map_container != null and map_container.has_method("render"):
		map_container.render(runtime_map, run_state.available_node_ids, run_state.completed_node_ids, run_state.current_node_id)
	_set_result_text("選擇下一個路線節點。")

func select_map_node(node_id: String) -> bool:
	if flow.current_state != flow.State.MAP or node_id not in run_state.available_node_ids:
		return false
	var node: Dictionary = map_node_index.get(node_id, {})
	if node.is_empty() or not flow.transition(flow.State.NODE):
		return false
	run_state.flow_state = flow.current_state
	run_state.current_node_id = node_id
	_autosave("node_entered")
	if map_container != null and map_container.has_method("hide_map"):
		map_container.hide_map()
	var node_type := str(node.get("type", ""))
	if node_type in ["normal_battle", "elite", "boss"]:
		flow.transition(flow.State.BATTLE)
		run_state.flow_state = flow.current_state
		_start_encounter(str(node.get("content_id", "")))
	else:
		_execute_nonbattle_node(node)
	return true

func _execute_nonbattle_node(node: Dictionary) -> void:
	var node_type := str(node.get("type", ""))
	if node_type in ["event", "shop", "rest"]:
		_show_choice_node(node)
		return
	push_error("未知的非戰鬥節點類型：%s" % node_type)
	_complete_current_node()


func _show_event_node(node: Dictionary) -> void:
	_show_choice_node(node)


func _show_choice_node(node: Dictionary) -> void:
	var node_type := str(node.get("type", ""))
	var definition_kind: String = {"event": "events", "shop": "shops", "rest": "rests"}.get(node_type, "")
	var definition := content.get_definition(definition_kind, str(node.get("content_id", "")))
	if definition_kind.is_empty() or definition.is_empty() or event_view == null or not event_view.has_method("render"):
		push_error("%s 節點內容或介面不存在：%s" % [node_type, node.get("content_id", "")])
		_complete_current_node()
		return
	var state := _get_event_resource_state()
	var previews: Array[Dictionary] = event_choice_resolver.preview_choices(definition, state)
	event_view.render(definition, previews, state)


func _on_event_choice_selected(option_id: String) -> void:
	if flow.current_state != flow.State.NODE:
		return
	var node: Dictionary = map_node_index.get(run_state.current_node_id, {})
	var node_type := str(node.get("type", ""))
	var definition_kind: String = {"event": "events", "shop": "shops", "rest": "rests"}.get(node_type, "")
	if definition_kind.is_empty():
		return
	var definition := content.get_definition(definition_kind, str(node.get("content_id", "")))
	var result: Dictionary = event_choice_resolver.resolve_choice(definition, option_id, _get_event_resource_state())
	if not bool(result.get("valid", false)) or not bool(result.get("affordable", false)):
		_set_result_text("節點選項無法執行：%s" % result.get("reason", "未知原因"))
		return
	var result_text := str(result.get("result_text", "節點已完成。"))
	var changes: Dictionary = result.get("changes", {}).duplicate(true)
	var sanity_delta := int(result.get("deltas", {}).get("sanity", 0))
	if sanity_delta != 0 and battle_manager.has_method("change_player_sanity"):
		battle_manager.change_player_sanity(sanity_delta, "%s:%s:%s" % [node_type, definition.get("id", ""), option_id])
		changes.erase("sanity")
	_hide_event()
	_complete_current_node(changes)
	_set_result_text("%s結果：%s" % [_node_type_label(node_type), result_text])


func _get_event_resource_state() -> Dictionary:
	_capture_runtime_state()
	return {
		"hp": run_state.hp,
		"max_hp": run_state.max_hp,
		"sanity": run_state.sanity,
		"max_sanity": run_state.max_sanity,
		"mp": run_state.mp,
		"max_mp": run_state.max_mp,
		"currency": run_state.currency,
	}


func _node_type_label(node_type: String) -> String:
	return {"event": "事件", "shop": "商店", "rest": "休息"}.get(node_type, "節點")


func _hide_event() -> void:
	if event_view != null:
		if event_view.has_method("hide_event"):
			event_view.hide_event()
		else:
			event_view.visible = false


func apply_event_sanity(delta: int, event_id: String) -> Dictionary:
	if battle_manager == null or not battle_manager.has_method("change_player_sanity"):
		return {}
	var preview: Dictionary = battle_manager.get_sanity_preview(delta) if battle_manager.has_method("get_sanity_preview") else {}
	battle_manager.change_player_sanity(delta, "event:%s" % event_id)
	_capture_runtime_state()
	return preview

func _complete_current_node(changes: Dictionary = {}) -> void:
	var node: Dictionary = map_node_index.get(run_state.current_node_id, {})
	var result = RunNodeResultScript.create(run_state.current_node_id, str(node.get("type", "")), RunNodeResultScript.Outcome.COMPLETED, changes, _strings(node.get("next_ids", [])))
	_apply_node_result(result)

func _apply_node_result(result) -> void:
	_capture_runtime_state()
	for key in result.state_changes:
		match str(key):
			"hp": run_state.hp = clampi(int(result.state_changes[key]), 0, run_state.max_hp)
			"sanity": run_state.sanity = clampi(int(result.state_changes[key]), 0, run_state.max_sanity)
			"mp": run_state.mp = clampi(int(result.state_changes[key]), 0, run_state.max_mp)
			"currency": run_state.currency = maxi(int(result.state_changes[key]), 0)
	var mp_restore := int(content.get_document("run_config").get("mp_restore_per_node", 35))
	run_state.mp = mini(run_state.mp + mp_restore, run_state.max_mp)
	battle_manager.configure_player(run_state.player_name, run_state.max_hp, run_state.hp, run_state.max_sanity, run_state.sanity, run_state.action_points, run_state.max_mp, run_state.mp)
	var node_id := str(result.node_id)
	var node: Dictionary = map_node_index.get(node_id, {})
	if node_id not in run_state.completed_node_ids:
		run_state.completed_node_ids.append(node_id)
	if str(node.get("type", "")) == "boss":
		_finish_run(true, "最終目標已擊敗")
		return
	run_state.available_node_ids = result.next_node_ids.duplicate()
	if not flow.transition(flow.State.MAP):
		push_error("Run 狀態無法返回地圖：%s" % flow.current_state)
		return
	run_state.flow_state = flow.current_state
	_show_map()
	_autosave("node_completed")

func _finish_run(victory: bool, reason: String) -> void:
	_capture_runtime_state()
	var target_state = flow.State.VICTORY if victory else flow.State.DEFEAT
	if flow.current_state != target_state:
		flow.transition(target_state)
	run_state.flow_state = flow.current_state
	meta_state.runs_completed += 1
	if not profile_service.save_meta(meta_state):
		push_warning("無法更新 Meta 完成計數：%s" % profile_service.last_error)
	_hide_rewards()
	_hide_event()
	if map_container != null:
		map_container.visible = false
	if tablet.has_method("set_placement_enabled"):
		tablet.set_placement_enabled(false)
	if settlement_screen != null and settlement_screen.has_method("show_result"):
		settlement_screen.show_result(victory, "%s\n完成節點：%d｜戰鬥勝利：%d｜金錢：%d\nSeed：%d" % [reason, run_state.completed_node_ids.size(), battles_won, run_state.currency, run_state.seed])
	_autosave("run_finished")

func _start_encounter(encounter_id: String) -> void:
	_hide_rewards()
	var encounter := content.get_definition("encounters", encounter_id)
	if encounter.is_empty():
		_finish_run(false, "找不到遭遇：%s" % encounter_id)
		return
	var encounter_enemies = _build_encounter_enemies(encounter)
	current_difficulty = difficulty_calculator.calculate(encounter_enemies, content.get_document("run_config").get("difficulty_model", {}))
	_set_result_text("遭遇：%s｜強度 %d｜獎勵 Tier %d" % [str(encounter.get("name", "未知遭遇")), int(current_difficulty.get("strength", 0)), int(current_difficulty.get("reward_tier", 1))])
	battle_manager.start_from_input(BattleStartInput.create(encounter_id, encounter_enemies, run_state, content.get_entries("intents")))

func _on_battle_won() -> void:
	battles_won += 1
	run_state.battles_won = battles_won
	_capture_runtime_state()
	var current_node: Dictionary = map_node_index.get(run_state.current_node_id, {})
	if str(current_node.get("type", "")) == "boss":
		_complete_current_node()
		return
	if not flow.transition(flow.State.REWARD):
		push_error("戰鬥勝利後無法進入獎勵狀態。")
		return
	run_state.flow_state = flow.current_state
	_set_result_text("勝利！選擇一項獎勵。")
	_show_reward_choices()

func _on_battle_lost(reason: String) -> void:
	_set_result_text("探索失敗：%s" % reason)
	_finish_run(false, reason)


func _on_battle_finished(result: BattleResult) -> void:
	if result == null:
		return
	_apply_player_result(result.player_state)
	var report := result.statistics.duplicate(true)
	report.merge(current_difficulty, true)
	report["outcome"] = "victory" if result.outcome == BattleResult.Outcome.VICTORY else "defeat"
	run_state.battle_reports.append(report)
	_latest_report_index = run_state.battle_reports.size() - 1
	if result.outcome == BattleResult.Outcome.VICTORY:
		_on_battle_won()
	else:
		_on_battle_lost(result.reason)

func _show_reward_choices() -> void:
	if reward_panel != null:
		reward_panel.visible = true
	_clear_reward_buttons()
	current_rewards = _pick_rewards(3)
	for i in range(current_rewards.size()):
		var reward = current_rewards[i]
		var button = Button.new()
		button.text = _get_reward_label(reward)
		button.tooltip_text = _get_reward_tooltip(reward)
		button.pressed.connect(_on_reward_selected.bind(i))
		reward_buttons_container.add_child(button)
	var skip_button := Button.new()
	var skip_currency := int(content.get_document("run_config").get("skip_reward_currency", 10))
	skip_button.text = "跳過獎勵｜獲得 %d 金錢" % skip_currency
	skip_button.pressed.connect(_on_reward_skipped.bind(skip_currency))
	reward_buttons_container.add_child(skip_button)

func _on_reward_selected(index: int) -> void:
	if index < 0 or index >= current_rewards.size():
		return
	var reward = current_rewards[index]
	_apply_reward(reward)
	_record_reward(str(reward.get("id", "")))
	_complete_current_node()

func _apply_reward(reward: Dictionary) -> String:
	var reward_type = str(reward.get("type", ""))
	var reward_id = str(reward.get("id", ""))
	var resource = block_resources.get(reward_id) if reward_type == "block" else spell_resources.get(reward_id)
	if reward_type == "block" and resource is BlockData:
		if tablet.has_method("add_block_to_pool"):
			tablet.add_block_to_pool(resource)
		_set_result_text("獲得特殊形狀：%s｜已加入方塊池。" % resource.display_name)
		if resource.id not in run_state.block_pool_ids:
			run_state.block_pool_ids.append(resource.id)
	elif reward_type == "spell" and resource is BattleItem:
		if tablet.has_method("add_spell_to_pool"):
			tablet.add_spell_to_pool(resource)
		run_state.spell_pool_ids.append(reward_id)
		_set_result_text("獲得咒文：%s｜加入方塊咒文池。" % resource.spell_name)
	run_state.selected_reward_ids.append(reward_id)
	return ""

func _pick_rewards(count: int) -> Array:
	return reward_selector.pick(
		reward_pool,
		content.indexes.get("spells", {}),
		content.indexes.get("blocks", {}),
		{
			"battles_won": battles_won,
			"reward_tier": int(current_difficulty.get("reward_tier", 1)),
			"unlocked_reward_ids": run_state.selected_reward_ids,
			"meta_unlocked_spell_ids": meta_state.unlocked_spell_ids,
			"meta_unlocked_block_ids": meta_state.unlocked_block_ids,
		},
		count,
		rng
	)

func _get_eligible_reward_pool() -> Array:
	var eligible: Array = []
	for reward in reward_pool:
		if not reward is Dictionary:
			continue
		var min_battles = int(reward.get("min_battles_won", 0))
		if battles_won >= min_battles:
			eligible.append(reward)
	return eligible

func _get_reward_label(reward: Dictionary) -> String:
	var title = str(reward.get("title", "未知獎勵"))
	var reward_type = str(reward.get("type", ""))
	if reward_type == "spell":
		var item := spell_resources.get(str(reward.get("id", ""))) as BattleItem
		return "%s\n%s｜Tier %d" % [title, item.rarity if item != null else "common", item.tier if item != null else 1]
	return title

func _get_reward_tooltip(reward: Dictionary) -> String:
	var reward_type = str(reward.get("type", ""))
	var reward_id = str(reward.get("id", ""))
	if reward_type == "spell":
		var item = spell_resources.get(reward_id)
		if item is BattleItem:
			return item.get_effect_tooltip("獎勵預覽")
	if reward_type == "block":
		var block = block_resources.get(reward_id)
		if block is BlockData:
			return "特殊形狀\n%s\n取得後加入方塊池；同一形狀不重複取得。\n標籤：%s" % [block.display_name if block.display_name != "" else block.id, ", ".join(block.tags)]
	return str(reward.get("title", "未知獎勵"))

func _hide_rewards() -> void:
	if reward_panel != null:
		reward_panel.visible = false
	_clear_reward_buttons()

func _clear_reward_buttons() -> void:
	if reward_buttons_container == null:
		return
	for child in reward_buttons_container.get_children():
		child.queue_free()

func _on_reward_skipped(currency_amount: int) -> void:
	run_state.currency += currency_amount
	_record_reward("currency:%d" % currency_amount)
	_complete_current_node()

func _record_reward(reward_id: String) -> void:
	if _latest_report_index >= 0 and _latest_report_index < run_state.battle_reports.size():
		run_state.battle_reports[_latest_report_index]["reward_id"] = reward_id

func _set_result_text(text: String) -> void:
	if result_label != null:
		result_label.text = text

func _build_encounter_enemies(encounter: Dictionary) -> Array:
	var encounter_enemies: Array = []
	var enemy_ids = encounter.get("enemy_ids", [])
	if not enemy_ids is Array:
		return encounter_enemies
	for enemy_id in enemy_ids:
		var enemy_def = content.get_definition("enemies", str(enemy_id))
		if not enemy_def.is_empty():
			encounter_enemies.append(enemy_def)
	return encounter_enemies

func get_run_state_snapshot() -> Dictionary:
	_capture_runtime_state()
	return run_state.to_dict()


func restore_run_state(snapshot: Dictionary) -> bool:
	if save_service != null:
		var structure_errors: Array[String] = save_service.validate_run_state_payload(snapshot)
		if not structure_errors.is_empty():
			for error in structure_errors:
				push_error("無法還原 RunState：%s" % error)
			return false
	var restored := RunState.from_dict(snapshot)
	if restored == null:
		return false
	var reference_errors := content.validate_run_state_references(restored)
	if not reference_errors.is_empty():
		for error in reference_errors:
			push_error("無法還原 RunState：%s" % error)
		return false
	run_state = restored
	current_encounter_index = run_state.encounter_index
	battles_won = run_state.battles_won
	if run_state.reward_rng_state.is_valid_int():
		rng.state = int(run_state.reward_rng_state)
	else:
		rng.seed = run_state.seed
	if tablet.has_method("set_rng_state"):
		if not tablet.set_rng_state(run_state.tablet_rng_state):
			return false
	runtime_map = run_state.map_data.duplicate(true) if not run_state.map_data.is_empty() else map_generator.generate(run_state.seed, content.get_document("map"))
	_index_runtime_map()
	flow.current_state = clampi(run_state.flow_state, flow.State.START, flow.State.DEFEAT)
	if tablet.has_method("set_block_pool"):
		tablet.set_block_pool(content.get_blocks(run_state.block_pool_ids))
	if tablet.has_method("set_spell_pool"):
		tablet.set_spell_pool(content.get_spells(run_state.spell_pool_ids))
	if tablet.has_method("restore_board_state") and not run_state.board_cells.is_empty():
		tablet.restore_board_state(run_state.board_cells)
	if tablet.has_method("restore_board_spell_state") and not run_state.board_spell_ids.is_empty():
		tablet.restore_board_spell_state(run_state.board_spell_ids, content.spell_resources)
	if tablet.has_method("restore_hand_state") and not run_state.hand_state.is_empty():
		tablet.restore_hand_state(run_state.hand_state, content.block_resources)
	elif tablet.has_method("restore_hand") and not run_state.hand_ids.is_empty():
		tablet.restore_hand(content.get_blocks(run_state.hand_ids))
	elif tablet.has_method("restore_hand_state"):
		tablet.restore_hand_state([], content.block_resources)
	if battle_manager.has_method("configure_player"):
		battle_manager.configure_player(run_state.player_name, run_state.max_hp, run_state.hp, run_state.max_sanity, run_state.sanity, run_state.action_points, run_state.max_mp, run_state.mp)
	if battle_manager.has_method("configure_sanity_rules"):
		battle_manager.configure_sanity_rules(content.get_document("sanity"), run_state.seed, run_state.sanity_effect_ids, run_state.sanity_history)
	_restore_saved_flow()
	return true


func continue_autosave() -> bool:
	if save_service == null or not save_service.has_run_save():
		return false
	var loaded: Dictionary = save_service.load_run()
	if _restore_loaded_save(loaded):
		return true
	var backup: Dictionary = save_service.load_backup_run()
	if str(loaded.get("source", "")) != "backup" and _restore_loaded_save(backup):
		push_warning("主存檔內容引用無效，已回退至 last-known-good 備份。")
		return true
	push_warning("自動存檔無法繼續：%s" % loaded.get("error", "內容引用或流程無效"))
	return false


func _restore_loaded_save(loaded: Dictionary) -> bool:
	if not bool(loaded.get("ok", false)) or not loaded.get("state") is RunState:
		return false
	var state: RunState = loaded.get("state")
	if not restore_run_state(state.to_dict()):
		return false
	if str(loaded.get("source", "")) == "backup":
		if not save_service.recover_primary_from_backup():
			push_warning("已載入備份，但主存檔修復失敗：%s" % save_service.last_error)
		elif flow.current_state == flow.State.MAP:
			_autosave("node_completed")
		elif flow.current_state in [flow.State.VICTORY, flow.State.DEFEAT]:
			_autosave("run_finished")
	if bool(loaded.get("migrated", false)):
		_autosave("migrated")
	return true


func _restore_saved_flow() -> void:
	if settlement_screen != null and settlement_screen.has_method("hide_result"):
		settlement_screen.hide_result()
	match flow.current_state:
		flow.State.MAP:
			_show_map()
		flow.State.NODE, flow.State.BATTLE, flow.State.REWARD:
			_resume_locked_node()
		flow.State.VICTORY, flow.State.DEFEAT:
			var victory: bool = flow.current_state == flow.State.VICTORY
			if map_container != null:
				map_container.visible = false
			if tablet.has_method("set_placement_enabled"):
				tablet.set_placement_enabled(false)
			if settlement_screen != null and settlement_screen.has_method("show_result"):
				settlement_screen.show_result(victory, "%s\n完成節點：%d｜戰鬥勝利：%d｜金錢：%d\nSeed：%d" % ["已完成的探索" if victory else "已結束的探索", run_state.completed_node_ids.size(), battles_won, run_state.currency, run_state.seed])
		_:
			_show_map()


func _resume_locked_node() -> void:
	var node: Dictionary = map_node_index.get(run_state.current_node_id, {})
	if node.is_empty() or run_state.current_node_id in run_state.completed_node_ids:
		push_error("存檔中的已鎖定節點無法恢復：%s" % run_state.current_node_id)
		_finish_run(false, "存檔節點無效")
		return
	flow.current_state = flow.State.NODE
	run_state.flow_state = flow.current_state
	if map_container != null and map_container.has_method("hide_map"):
		map_container.hide_map()
	var node_type := str(node.get("type", ""))
	if node_type in ["normal_battle", "elite", "boss"]:
		if flow.transition(flow.State.BATTLE):
			run_state.flow_state = flow.current_state
			_start_encounter(str(node.get("content_id", "")))
	else:
		_execute_nonbattle_node(node)


func _autosave(checkpoint: String) -> bool:
	if save_service == null:
		return false
	_capture_runtime_state()
	var reference_errors := content.validate_run_state_references(run_state)
	if not reference_errors.is_empty():
		push_warning("自動存檔前內容引用驗證失敗：%s" % "; ".join(reference_errors))
		return false
	var saved: bool = save_service.save_run(run_state, checkpoint, _content_versions())
	if not saved:
		push_warning("自動存檔失敗：%s" % save_service.last_error)
	return saved


func _content_versions() -> Dictionary:
	var versions := {}
	for kind in ContentRegistry.DATA_PATHS:
		versions[kind] = int(content.get_document(kind).get("schema_version", 1))
	return versions


func _capture_runtime_state() -> void:
	run_state.reward_rng_state = str(rng.state)
	if tablet.has_method("get_rng_state"):
		run_state.tablet_rng_state = tablet.get_rng_state()
	var player_state: Dictionary = battle_manager.get_player_state() if battle_manager.has_method("get_player_state") else {}
	_apply_player_result(player_state)
	if tablet.has_method("get_board_state"):
		run_state.board_cells = tablet.get_board_state()
	if tablet.has_method("get_board_spell_state"):
		run_state.board_spell_ids = tablet.get_board_spell_state()
	if tablet.has_method("get_hand_ids"):
		run_state.hand_ids = tablet.get_hand_ids()
	if tablet.has_method("get_hand_state"):
		run_state.hand_state = tablet.get_hand_state()
	if tablet.has_method("get_block_pool_ids"):
		run_state.block_pool_ids = tablet.get_block_pool_ids()
	if tablet.has_method("get_spell_pool_ids"):
		run_state.spell_pool_ids = tablet.get_spell_pool_ids()
	if not player_state.is_empty():
		run_state.sanity_effect_ids = _strings(player_state.get("sanity_effect_ids", []))
		if player_state.get("sanity_history", []) is Array:
			run_state.sanity_history = player_state.get("sanity_history", []).duplicate(true)


func _apply_player_result(state: Dictionary) -> void:
	run_state.hp = int(state.get("hp", run_state.hp))
	run_state.max_hp = int(state.get("max_hp", run_state.max_hp))
	run_state.sanity = int(state.get("sanity", run_state.sanity))
	run_state.max_sanity = int(state.get("max_sanity", run_state.max_sanity))
	run_state.mp = int(state.get("mp", run_state.mp))
	run_state.max_mp = int(state.get("max_mp", run_state.max_mp))


func _strings(values) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _filter_meta_unlocked(values, unlocked: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var id := str(value)
		if id in unlocked:
			result.append(id)
	return result
