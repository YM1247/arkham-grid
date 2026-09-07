extends Node

const BattleStatisticsScript = preload("res://scripts/battle/battle_statistics.gd")
const SanityRuleEngineScript = preload("res://scripts/sanity/sanity_rule_engine.gd")

signal battle_won
signal battle_lost(reason: String)
signal battle_finished(result: BattleResult)

enum TurnState {
	PLAYER_TURN,
	ENEMY_TURN
}

const MAX_ENEMIES := 5

# 裝備欄：必須在編輯器設定 Size 為 8
@export var row_items: Array[BattleItem]
@export var col_items: Array[BattleItem]

@export_group("戰鬥對象")
@export var player_path: NodePath
@export var enemy_path: NodePath
@export var tablet_path: NodePath

@export_group("UI")
@export var player_status_label_path: NodePath
@export var enemy_status_label_path: NodePath
@export var turn_status_label_path: NodePath
@export var intent_label_path: NodePath
@export var end_turn_button_path: NodePath
@export var equipment_summary_label_path: NodePath

@export_group("回合設定")
@export var player_max_action_points: int = 3
@export var enemy_attack_damage: int = 8

var player: Entity
var enemy: Entity
var enemies: Array[Entity] = []
var selected_enemy_index := 0
var tablet: Node
var current_turn := TurnState.PLAYER_TURN
var current_action_points := 0
var battle_active := false
var current_turn_weapon_triggers := 0
var _dynamic_enemies: Array[Entity] = []
var _enemy_factory := EnemyFactory.new()
var _enemy_presenter := EnemyRosterPresenter.new()
var _intent_executor := EnemyIntentExecutor.new()
var _target_resolver := TargetResolver.new()
var _outcome_resolver := BattleOutcomeResolver.new()
var _current_encounter_id := ""
var _intent_definitions: Dictionary = {}
var _trigger_history: Array[Dictionary] = []
var _outcome_check_scheduled := false
var _battle_stats = BattleStatisticsScript.new()
var sanity_rules = SanityRuleEngineScript.new()
var sanity_history: Array[Dictionary] = []
var _last_sanity_message := ""

func _ready():
	# 防呆檢查
	if row_items.size() != 8 or col_items.size() != 8:
		push_error("BattleManager 設定錯誤：Row/Col Items 陣列大小必須為 8！")
	
	player = get_node_or_null(player_path) as Entity
	enemy = get_node_or_null(enemy_path) as Entity
	tablet = get_node_or_null(tablet_path)
	
	if player == null:
		push_error("BattleManager 設定錯誤：找不到 Player Entity。")
	else:
		player.stats_changed.connect(_on_entity_stats_changed)
		player.died.connect(_on_entity_died)
		player.combat_feedback.connect(_on_entity_combat_feedback)
		player.sanity_depleted.connect(_on_player_sanity_depleted)
		player.sanity_changed.connect(_on_player_sanity_changed)
		_connect_statistics_signals(player)
	
	if enemy == null:
		push_error("BattleManager 設定錯誤：找不到 Enemy Entity。")
	else:
		enemy.stats_changed.connect(_on_entity_stats_changed)
		enemy.died.connect(_on_entity_died)
		enemy.combat_feedback.connect(_on_entity_combat_feedback)
		_connect_statistics_signals(enemy)
		enemies = [enemy]
	
	if tablet == null:
		push_error("BattleManager 設定錯誤：找不到 TabletSection。")
	else:
		tablet.block_placed.connect(_on_tablet_block_placed)
		tablet.no_valid_moves.connect(_on_tablet_no_valid_moves)
	
	var end_turn_button = get_node_or_null(end_turn_button_path) as Button
	if end_turn_button == null:
		push_error("BattleManager 設定錯誤：找不到 End Turn Button。")
	else:
		end_turn_button.pressed.connect(end_player_turn)
	
	_update_all_status_labels()
	_start_player_turn()

# --- 接收來自 Tablet 的信號 ---

func execute_row_effect(index: int):
	if not battle_active:
		return
	if _are_all_enemies_dead():
		return
	print("\n>> 觸發橫列 ROW ", index + 1) # 顯示 1-8 比較直觀
	
	if index < 0 or index >= row_items.size(): return
	var item = row_items[index]
	
	if item == null:
		print("   (空欄位)")
		return

	if item.axis_type != BattleItem.AxisType.PHYSICAL:
		push_error("Row 只能觸發物理道具：%s" % item.content_id)
		return
		
	_execute_item_on_scope(item, "row", index)
	_battle_stats.add("rows_cleared")
	current_turn_weapon_triggers += 1

func execute_col_effect(index: int):
	if not battle_active:
		return
	if _are_all_enemies_dead():
		return
	print("\n>> 觸發直行 COL ", index + 1)
	
	if index < 0 or index >= col_items.size(): return
	var item = col_items[index]
	
	if item == null:
		print("   (空欄位)")
		return

	if item.axis_type != BattleItem.AxisType.MAGIC:
		push_error("Col 只能觸發魔法道具：%s" % item.content_id)
		return
		
	if player != null and player.has_method("spend_sanity"):
		var base_cost = item.sanity_cost if item.sanity_cost > 0 else 3
		var sanity_cost := sanity_rules.modify_magic_cost(base_cost)
		player.spend_sanity(sanity_cost, "magic:%s" % item.content_id)
		_settle_battle_outcome()
		if not battle_active:
			return
		
	# 通過驗證
	_execute_item_on_scope(item, "col", index)
	_battle_stats.add("cols_cleared")

func _on_entity_stats_changed(_entity: Entity) -> void:
	_update_all_status_labels()

func _on_entity_died(entity: Entity) -> void:
	print("戰鬥事件：", entity.entity_name, " 死亡。")
	if entity != player and _get_selected_enemy() == entity:
		selected_enemy_index = -1
	_update_all_status_labels()
	_schedule_outcome_check()

func _on_player_sanity_depleted(_entity: Entity) -> void:
	_schedule_outcome_check()

func _on_entity_combat_feedback(entity: Entity, message: String, color: Color) -> void:
	var label = _get_status_label_for_entity(entity)
	if label == null:
		return
	_flash_label(label, color)
	_spawn_floating_text(label, message, color)

func _on_tablet_block_placed(_block_data: BlockData) -> void:
	if current_turn != TurnState.PLAYER_TURN:
		return
	current_action_points = maxi(current_action_points - 1, 0)
	if current_action_points <= 0 and tablet != null and tablet.has_method("set_placement_enabled"):
		tablet.set_placement_enabled(false)
	_update_all_status_labels()

func _on_tablet_no_valid_moves(penalty: int) -> void:
	if not battle_active or player == null:
		return
	player.spend_sanity(sanity_rules.modify_dead_board_penalty(penalty), "dead_board")
	_battle_stats.add("dead_boards")
	if battle_active:
		_update_all_status_labels()

func end_player_turn() -> void:
	if current_turn != TurnState.PLAYER_TURN or not battle_active:
		return
	if player != null:
		player.trigger_end_of_turn_statuses()
		_settle_battle_outcome()
		if not battle_active:
			return
	_start_enemy_turn()

func _start_player_turn() -> void:
	if _is_battle_over():
		return
	battle_active = true
	current_turn = TurnState.PLAYER_TURN
	current_action_points = player_max_action_points
	current_turn_weapon_triggers = 0
	_battle_stats.add("turns")
	if player != null:
		player.clear_armor()
	if tablet != null:
		if tablet.has_method("set_placement_enabled"):
			tablet.set_placement_enabled(true)
		if tablet.has_method("refill_hand"):
			tablet.refill_hand()
	_update_all_status_labels()

func _start_enemy_turn() -> void:
	if _is_battle_over():
		return
	current_turn = TurnState.ENEMY_TURN
	current_action_points = 0
	if tablet != null and tablet.has_method("set_placement_enabled"):
		tablet.set_placement_enabled(false)
	_update_all_status_labels()
	_execute_enemy_turn()

func _execute_enemy_turn() -> void:
	if _is_battle_over():
		return
	for active_enemy in _get_enemy_action_order():
		if active_enemy.is_dead:
			continue
		active_enemy.clear_armor()
		var intent_state := active_enemy.get_meta("intent_state") as EnemyIntentState if active_enemy.has_meta("intent_state") else null
		var intent_id := intent_state.current_intent_id() if intent_state != null else ""
		var intent: Dictionary = _intent_definitions.get(intent_id, {})
		if intent.is_empty():
			push_error("敵人 %s 使用未註冊 intent：%s" % [active_enemy.entity_name, intent_id])
			_finish_battle(false, "敵人意圖資料錯誤")
			return
		print(active_enemy.entity_name, " 意圖發動：", intent.get("display_name", intent_id))
		_intent_executor.execute(intent, active_enemy, player)
		if intent_state != null:
			intent_state.advance()
		active_enemy.trigger_end_of_turn_statuses()
		_settle_battle_outcome()
		if not battle_active:
			return
	_decay_round_statuses()
	_settle_battle_outcome()
	if not battle_active:
		return
	await get_tree().create_timer(0.4).timeout
	_start_player_turn()

func _update_all_status_labels() -> void:
	_update_status_label(player_status_label_path, player)
	_update_enemy_status_ui()
	_update_turn_status_label()
	_update_intent_label()
	_update_end_turn_button()
	_update_equipment_summary_label()
	_update_tablet_slot_labels()

func _update_status_label(label_path: NodePath, entity: Entity) -> void:
	var label = get_node_or_null(label_path) as Label
	if label == null or entity == null:
		return
	label.text = "%s HP: %d/%d  ARMOR: %d" % [entity.entity_name, entity.hp, entity.max_hp, entity.armor]
	if entity.max_sanity > 0:
		label.text += "  SAN: %d/%d" % [entity.sanity, entity.max_sanity]
		if entity == player and not sanity_rules.active_effect_ids.is_empty():
			label.text += "  [%s：%s]" % [sanity_rules.get_stage_name(entity.sanity), sanity_rules.get_active_summary()]
	if entity.has_method("get_status_summary"):
		var status_summary = entity.get_status_summary()
		if status_summary != "":
			label.text += "  %s" % status_summary
	if entity == player and not _last_sanity_message.is_empty():
		label.text += "\n最近理智變化：%s" % _last_sanity_message

func _update_turn_status_label() -> void:
	var label = get_node_or_null(turn_status_label_path) as Label
	if label == null:
		return
	if not battle_active:
		label.text = "戰鬥結束"
		return
	if current_turn == TurnState.PLAYER_TURN:
		var sanity_warning = ""
		if player != null and player.max_sanity > 0 and player.sanity > 0 and player.sanity < 30:
			sanity_warning = "  理智不穩"
		label.text = "玩家回合  AP: %d/%d%s" % [current_action_points, player_max_action_points, sanity_warning]
	else:
		label.text = "敵人回合"

func _update_intent_label() -> void:
	var label = get_node_or_null(intent_label_path) as Label
	if label == null:
		return
	if not battle_active:
		label.text = "Intent: --"
		return
	var lines: Array[String] = ["敵人意圖"]
	for active_enemy in _get_enemy_action_order():
		var intent_state := active_enemy.get_meta("intent_state") as EnemyIntentState if active_enemy.has_meta("intent_state") else null
		var intent_id := intent_state.current_intent_id() if intent_state != null else ""
		var intent: Dictionary = _intent_definitions.get(intent_id, {})
		lines.append("%s：%s" % [active_enemy.entity_name, intent.get("display_name", intent_id)])
	label.text = "\n".join(lines)

func _update_end_turn_button() -> void:
	var button = get_node_or_null(end_turn_button_path) as Button
	if button == null:
		return
	button.disabled = current_turn != TurnState.PLAYER_TURN or _is_battle_over()

func _update_equipment_summary_label() -> void:
	var label = get_node_or_null(equipment_summary_label_path) as Label
	if label == null:
		return
	var lines: Array[String] = ["目前裝備"]
	var tooltip_lines: Array[String] = ["目前裝備效果"]
	for i in range(row_items.size()):
		var item = row_items[i]
		var item_name = item.item_name if item != null else "空"
		lines.append("Row %d: %s" % [i + 1, item_name])
		if item != null:
			tooltip_lines.append(item.get_effect_tooltip("Row %d" % (i + 1)))
	for i in range(col_items.size()):
		var item = col_items[i]
		var item_name = item.item_name if item != null else "空"
		lines.append("Col %d: %s" % [i + 1, item_name])
		if item != null:
			tooltip_lines.append(item.get_effect_tooltip("Col %d" % (i + 1)))
	label.text = "\n".join(lines)
	label.tooltip_text = "\n\n".join(tooltip_lines)

func _update_tablet_slot_labels() -> void:
	_update_magic_previews()
	if tablet != null and tablet.has_method("set_slot_items"):
		tablet.set_slot_items(row_items, col_items)

func _is_battle_over() -> bool:
	return (player != null and player.is_dead) or _are_all_enemies_dead() or (player != null and player.max_sanity > 0 and player.sanity <= 0)

func configure_player(player_name: String, max_hp: int, hp: int, max_sanity: int, sanity: int, max_action_points: int) -> void:
	if player == null:
		return
	player.entity_name = player_name
	player.reset_entity(player.entity_name, max_hp, hp, max_sanity, sanity)
	_sync_sanity_effects()
	player_max_action_points = max_action_points
	_update_all_status_labels()

func set_loadout(new_row_items: Array, new_col_items: Array) -> void:
	row_items = _normalize_item_array(new_row_items)
	col_items = _normalize_item_array(new_col_items)
	_update_all_status_labels()

func set_row_item(index: int, item: BattleItem) -> void:
	if index < 0 or index >= row_items.size():
		return
	row_items[index] = item
	_update_all_status_labels()

func set_col_item(index: int, item: BattleItem) -> void:
	if index < 0 or index >= col_items.size():
		return
	col_items[index] = item
	_update_all_status_labels()

func start_battle(enemy_name: String, enemy_hp: int, enemy_attack: int) -> void:
	start_encounter([
		{
			"name": enemy_name,
			"hp": enemy_hp,
			"attack": enemy_attack
		}
	])


func start_from_input(input: BattleStartInput) -> void:
	if input == null:
		push_error("BattleManager 收到空的 BattleStartInput。")
		return
	_current_encounter_id = input.encounter_id
	_intent_definitions = input.intent_definitions.duplicate(true)
	var state := input.player_state
	configure_player(
		str(state.get("name", "調查員")),
		int(state.get("max_hp", 80)),
		int(state.get("hp", 80)),
		int(state.get("max_sanity", 100)),
		int(state.get("sanity", 70)),
		int(state.get("action_points", player_max_action_points))
	)
	start_encounter(input.enemies)

func start_encounter(enemy_defs: Array) -> void:
	if enemy == null:
		return
	if enemy_defs.size() > MAX_ENEMIES:
		push_error("Encounter 超過 %d 名敵人上限。" % MAX_ENEMIES)
		return
	if player != null:
		player.clear_armor()
		if player.has_method("clear_statuses"):
			player.clear_statuses()
	_clear_dynamic_enemies()
	enemies.clear()
	selected_enemy_index = 0
	_trigger_history.clear()
	_battle_stats.reset(_current_encounter_id)
	for i in range(enemy_defs.size()):
		var enemy_def = enemy_defs[i]
		if not enemy_def is Dictionary:
			continue
		var active_enemy := _enemy_factory.create(enemy_def, enemy, self, i)
		if i > 0:
			active_enemy.stats_changed.connect(_on_entity_stats_changed)
			active_enemy.died.connect(_on_entity_died)
			active_enemy.combat_feedback.connect(_on_entity_combat_feedback)
			_connect_statistics_signals(active_enemy)
			_dynamic_enemies.append(active_enemy)
		enemies.append(active_enemy)
	enemy_attack_damage = int(enemies[0].get_meta("attack_damage", 8)) if not enemies.is_empty() else 8
	battle_active = true
	_start_player_turn()

func get_player_state() -> Dictionary:
	if player == null:
		return {}
	return {
		"hp": player.hp,
		"max_hp": player.max_hp,
		"sanity": player.sanity,
		"max_sanity": player.max_sanity,
		"sanity_effect_ids": sanity_rules.active_effect_ids.duplicate(),
		"sanity_history": sanity_history.duplicate(true)
	}


func configure_sanity_rules(document: Dictionary, seed: int, restored_effect_ids: Array[String] = [], restored_history: Array[Dictionary] = []) -> void:
	sanity_rules.configure(document, seed, restored_effect_ids)
	sanity_history = restored_history.duplicate(true)
	_sync_sanity_effects()
	_update_all_status_labels()


func change_player_sanity(delta: int, source: String) -> int:
	if player == null:
		return 0
	return player.change_sanity(delta, source)


func get_sanity_preview(delta: int) -> Dictionary:
	return sanity_rules.preview(player.sanity if player != null else 0, delta)

func _finish_battle(won: bool, reason: String) -> void:
	if not battle_active:
		return
	battle_active = false
	current_action_points = 0
	if tablet != null and tablet.has_method("set_placement_enabled"):
		tablet.set_placement_enabled(false)
	_update_all_status_labels()
	var result := BattleResult.create(won, reason, _current_encounter_id, get_player_state(), _battle_stats.snapshot())
	battle_finished.emit(result)
	if won:
		battle_won.emit()
	else:
		battle_lost.emit(reason)

func _execute_item_on_scope(item: BattleItem, axis: String, index: int) -> void:
	var context := BattleEffectContext.new()
	context.user = player
	context.trigger_axis = axis
	context.trigger_index = index
	context.weapon_trigger_count = current_turn_weapon_triggers
	context.trigger_history = _trigger_history.duplicate(true)
	context.battle_state = {"turn": current_turn, "action_points": current_action_points, "encounter_id": _current_encounter_id}
	if item.effect_scope == "self":
		context.primary_target = player
		context.targets = [player]
		item.execute_with_context(player, player, context)
	else:
		context.primary_target = _get_selected_enemy()
		context.targets = _target_resolver.resolve(item.effect_scope, enemies, selected_enemy_index)
	for target in context.targets:
		if target != null and not target.is_dead:
			if item.effect_scope != "self":
				item.execute_with_context(target, player, context)
	_trigger_history.append({"item_id": item.content_id, "axis": axis, "index": index, "target_count": context.targets.size()})
	_settle_battle_outcome()

func _get_targets_for_scope(scope: String) -> Array[Entity]:
	return _target_resolver.resolve(scope, enemies, selected_enemy_index)

func _get_selected_enemy() -> Entity:
	if selected_enemy_index >= 0 and selected_enemy_index < enemies.size():
		return enemies[selected_enemy_index]
	return null

func _get_living_enemies() -> Array[Entity]:
	var living: Array[Entity] = []
	for active_enemy in enemies:
		if active_enemy != null and not active_enemy.is_dead:
			living.append(active_enemy)
	return living

func _are_all_enemies_dead() -> bool:
	return not enemies.is_empty() and _get_living_enemies().is_empty()

func _get_total_enemy_attack() -> int:
	var total := 0
	for active_enemy in _get_living_enemies():
		total += int(active_enemy.get_meta("attack_damage", enemy_attack_damage))
	return total


func _get_enemy_action_order() -> Array[Entity]:
	var order := _get_living_enemies()
	order.sort_custom(func(a: Entity, b: Entity):
		var a_speed := int(a.get_meta("speed", 0))
		var b_speed := int(b.get_meta("speed", 0))
		if a_speed == b_speed:
			return int(a.get_meta("spawn_index", 0)) < int(b.get_meta("spawn_index", 0))
		return a_speed > b_speed
	)
	return order


func _decay_round_statuses() -> void:
	if player != null:
		player.decay_statuses()
	for active_enemy in enemies:
		if active_enemy != null:
			active_enemy.decay_statuses()


func _schedule_outcome_check() -> void:
	if _outcome_check_scheduled or not battle_active:
		return
	_outcome_check_scheduled = true
	call_deferred("_run_scheduled_outcome_check")


func _run_scheduled_outcome_check() -> void:
	_outcome_check_scheduled = false
	_settle_battle_outcome()


func _settle_battle_outcome() -> void:
	if not battle_active:
		return
	match _outcome_resolver.resolve(player, enemies):
		BattleOutcomeResolver.Outcome.VICTORY:
			_finish_battle(true, "敵人已倒下")
		BattleOutcomeResolver.Outcome.HP_DEFEAT:
			_finish_battle(false, "HP 歸零")
		BattleOutcomeResolver.Outcome.SANITY_DEFEAT:
			_finish_battle(false, "Sanity 歸零")

func _clear_dynamic_enemies() -> void:
	for active_enemy in _dynamic_enemies:
		if is_instance_valid(active_enemy):
			active_enemy.queue_free()
	_dynamic_enemies.clear()

func _update_enemy_status_ui() -> void:
	for active_enemy in enemies:
		if active_enemy == null:
			continue
		var state := active_enemy.get_meta("intent_state") as EnemyIntentState if active_enemy.has_meta("intent_state") else null
		var intent: Dictionary = _intent_definitions.get(state.current_intent_id() if state != null else "", {})
		active_enemy.set_meta("intent_display", str(intent.get("display_name", "--")))
	var label = get_node_or_null(enemy_status_label_path) as Label
	_enemy_presenter.render(label, enemies, selected_enemy_index, _select_enemy)

func _select_enemy(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return
	if enemies[index] == null or enemies[index].is_dead:
		return
	selected_enemy_index = index
	_update_all_status_labels()

func _normalize_item_array(items: Array) -> Array[BattleItem]:
	var normalized: Array[BattleItem] = []
	for i in range(8):
		if i < items.size() and items[i] is BattleItem:
			normalized.append(items[i])
		else:
			normalized.append(null)
	return normalized

func _get_status_label_for_entity(entity: Entity) -> Label:
	if entity == player:
		return get_node_or_null(player_status_label_path) as Label
	return _enemy_presenter.get_feedback_anchor(entity)

func _flash_label(label: Label, color: Color) -> void:
	var tween = create_tween()
	tween.tween_property(label, "modulate", color, 0.08)
	tween.tween_property(label, "modulate", Color.WHITE, 0.22)

func _spawn_floating_text(anchor: Label, message: String, color: Color) -> void:
	var floating_label = Label.new()
	floating_label.text = message
	floating_label.modulate = color
	floating_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.get_parent().add_child(floating_label)
	floating_label.global_position = anchor.global_position + Vector2(220, -4)
	var tween = create_tween()
	tween.parallel().tween_property(floating_label, "global_position", floating_label.global_position + Vector2(0, -36), 0.65)
	tween.parallel().tween_property(floating_label, "modulate:a", 0.0, 0.65)
	tween.tween_callback(floating_label.queue_free)

func _connect_statistics_signals(entity: Entity) -> void:
	if not entity.damage_resolved.is_connected(_on_damage_resolved):
		entity.damage_resolved.connect(_on_damage_resolved)
	if not entity.armor_gained.is_connected(_on_armor_gained):
		entity.armor_gained.connect(_on_armor_gained)
	if not entity.sanity_spent.is_connected(_on_sanity_spent):
		entity.sanity_spent.connect(_on_sanity_spent)

func _on_damage_resolved(entity: Entity, hp_damage: int, blocked_damage: int) -> void:
	if entity == player:
		_battle_stats.add("damage_taken", hp_damage)
		_battle_stats.add("damage_blocked", blocked_damage)
	elif entity in enemies:
		_battle_stats.add("damage_dealt", hp_damage)

func _on_armor_gained(entity: Entity, amount: int) -> void:
	if entity == player:
		_battle_stats.add("armor_gained", amount)

func _on_sanity_spent(entity: Entity, amount: int) -> void:
	if entity == player:
		_battle_stats.add("sanity_spent", amount)


func _on_player_sanity_changed(_entity: Entity, delta: int, source: String, before: int, after: int) -> void:
	var change := sanity_rules.synchronize(after)
	sanity_rules.apply_entity_modifiers(player)
	var source_label := sanity_rules.get_source_label(source)
	_last_sanity_message = "%s %s%d（%d → %d）" % [source_label, "+" if delta > 0 else "", delta, before, after]
	if not change.added.is_empty():
		_last_sanity_message += "；新增 %s" % sanity_rules.get_active_summary()
	elif not change.removed.is_empty():
		_last_sanity_message += "；瘋狂效果已解除"
	sanity_history.append({"source": source, "source_label": source_label, "delta": delta, "before": before, "after": after, "active_effect_ids": sanity_rules.active_effect_ids.duplicate()})
	_update_all_status_labels()


func _sync_sanity_effects() -> void:
	if player == null:
		return
	sanity_rules.synchronize(player.sanity)
	sanity_rules.apply_entity_modifiers(player)


func _update_magic_previews() -> void:
	if player == null:
		return
	for item in col_items:
		if item == null:
			continue
		var base_cost := item.sanity_cost if item.sanity_cost > 0 else 3
		var adjusted_cost := sanity_rules.modify_magic_cost(base_cost)
		item.set_meta("sanity_adjusted_cost", adjusted_cost)
		item.set_meta("sanity_preview", sanity_rules.describe_preview(player.sanity, -adjusted_cost))
