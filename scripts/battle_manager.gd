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

@export_group("戰鬥對象")
@export var player_path: NodePath
@export var enemy_path: NodePath
@export var tablet_path: NodePath

@export_group("UI")
@export var player_status_label_path: NodePath
@export var player_hud_path: NodePath
@export var enemy_status_label_path: NodePath
@export var turn_status_label_path: NodePath
@export var ap_status_label_path: NodePath
@export var intent_label_path: NodePath
@export var end_turn_button_path: NodePath
@export var spell_summary_label_path: NodePath
@export var payment_preview_label_path: NodePath
@export var spell_legend_button_path: NodePath
@export var spell_legend_label_path: NodePath
@export var battle_stage_path: NodePath

@export_group("回合設定")
@export var player_max_action_points: int = 3
@export var enemy_attack_damage: int = 8

var player: Entity
var enemy: Entity
var enemies: Array[Entity] = []
var selected_enemy_index := 0
var tablet: Node
var battle_stage: BattleStageView
var _pending_enemy_death_presentation := false
var current_turn := TurnState.PLAYER_TURN
var current_action_points := 0
var battle_active := false
var current_turn_spell_triggers := 0
var mp := 0
var max_mp := 100
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
var _battle_sanity_history_start := 0
var turn_limit := 0
var time_pressure_sanity_base := 0
var time_pressure_sanity_growth := 0

func _ready():
	player = get_node_or_null(player_path) as Entity
	enemy = get_node_or_null(enemy_path) as Entity
	tablet = get_node_or_null(tablet_path)
	battle_stage = get_node_or_null(battle_stage_path) as BattleStageView
	
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
		if tablet.has_signal("spell_activated"):
			tablet.spell_activated.connect(execute_spell)
		if tablet.has_signal("spell_announcement_requested"):
			tablet.spell_announcement_requested.connect(_on_spell_announcement_requested)
		if tablet.has_signal("payment_preview_changed"):
			tablet.payment_preview_changed.connect(_on_payment_preview_changed)
	
	var end_turn_button = get_node_or_null(end_turn_button_path) as Button
	if end_turn_button == null:
		push_error("BattleManager 設定錯誤：找不到 End Turn Button。")
	else:
		end_turn_button.pressed.connect(end_player_turn)
	var legend_button := get_node_or_null(spell_legend_button_path) as Button
	if legend_button != null:
		legend_button.pressed.connect(_toggle_spell_legend)
	
	_update_all_status_labels()
	_start_player_turn()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("end_turn") and battle_active and current_turn == TurnState.PLAYER_TURN:
		end_player_turn()
		get_viewport().set_input_as_handled()

# --- 接收來自 Tablet 的信號 ---

func execute_row_effect(index: int):
	if not battle_active:
		return
	_battle_stats.add("rows_cleared")

func execute_col_effect(index: int):
	if not battle_active:
		return
	_battle_stats.add("cols_cleared")


func execute_spell(spell: BattleItem, board_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if not battle_active or spell == null or _are_all_enemies_dead():
		return false
	var cost := sanity_rules.modify_spell_mp_cost(spell.mp_cost)
	if mp < cost:
		player.spend_sanity(cost, "spell:fallback:%s" % spell.content_id)
		_battle_stats.add("spells_paid_with_sanity")
		print("咒文 %s 的 MP 不足，改以 %d Sanity 發動。" % [spell.spell_name, cost])
	else:
		mp -= cost
		_battle_stats.add("mp_spent", cost)
	_battle_stats.add("spells_triggered")
	_execute_spell_on_scope(spell, board_cell)
	current_turn_spell_triggers += 1
	_update_all_status_labels()
	return true


func _on_spell_announcement_requested(spell: BattleItem) -> void:
	if battle_stage != null and spell != null:
		battle_stage.present_spell_trigger(spell.spell_name, spell.category_glyph, spell.get_icon_color())

func _on_entity_stats_changed(_entity: Entity) -> void:
	_update_all_status_labels()

func _on_entity_died(entity: Entity) -> void:
	print("戰鬥事件：", entity.entity_name, " 死亡。")
	if entity != player and _get_selected_enemy() == entity:
		selected_enemy_index = _first_living_enemy_index()
	if entity != player:
		if DisplayServer.get_name() == "headless":
			_enemy_presenter.play_death(entity)
			_update_all_status_labels()
			_schedule_outcome_check()
			return
		_pending_enemy_death_presentation = true
		_enemy_presenter.play_death(entity)
		_finish_enemy_death_presentation_deferred()
	_update_all_status_labels()
	_schedule_outcome_check()

func _on_player_sanity_depleted(_entity: Entity) -> void:
	_schedule_outcome_check()

func _on_entity_combat_feedback(entity: Entity, message: String, color: Color) -> void:
	if entity != player:
		_enemy_presenter.play_hit(entity)
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
	current_turn_spell_triggers = 0
	_battle_stats.add("turns")
	_apply_time_pressure_if_needed()
	_settle_battle_outcome()
	if not battle_active:
		return
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
		var intent_id := intent_state.current_intent_id(active_enemy.hp, active_enemy.max_hp, int(_battle_stats.values.get("turns", 1))) if intent_state != null else ""
		var intent: Dictionary = _intent_definitions.get(intent_id, {})
		if intent.is_empty():
			push_error("敵人 %s 使用未註冊 intent：%s" % [active_enemy.entity_name, intent_id])
			_finish_battle(false, "敵人意圖資料錯誤")
			return
		print(active_enemy.entity_name, " 意圖發動：", intent.get("display_name", intent_id))
		var intent_name := str(intent.get("display_name", intent_id))
		await _present_enemy_windup(active_enemy, intent_name)
		var before := {
			"player_hp": player.hp,
			"player_armor": player.armor,
			"player_sanity": player.sanity,
			"enemy_armor": active_enemy.armor,
		}
		var execution_result := _intent_executor.execute(intent, active_enemy, player)
		var resolution_text := _format_enemy_action_result(intent, execution_result, active_enemy, before)
		await _present_enemy_resolution(active_enemy, intent_name, resolution_text, str(intent.get("action", "")) in ["damage", "sanity_damage", "status_player"])
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


func _present_enemy_windup(active_enemy: Entity, intent_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _enemy_presenter.play_windup(active_enemy)
	if battle_stage != null:
		await battle_stage.present_enemy_windup(active_enemy.entity_name, intent_name)


func _present_enemy_resolution(active_enemy: Entity, intent_name: String, result_text: String, harms_player: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _enemy_presenter.play_resolution(active_enemy)
	if battle_stage != null:
		await battle_stage.present_enemy_resolution(active_enemy.entity_name, intent_name, result_text, harms_player)
	await _enemy_presenter.play_return(active_enemy)
	if battle_stage != null:
		await battle_stage.finish_enemy_action()


func _format_enemy_action_result(intent: Dictionary, execution_result: Dictionary, active_enemy: Entity, before: Dictionary) -> String:
	match str(intent.get("action", "")):
		"damage":
			var hp_damage := maxi(int(before.get("player_hp", player.hp)) - player.hp, 0)
			var blocked := maxi(int(before.get("player_armor", player.armor)) - player.armor, 0)
			return "造成 %d HP 傷害%s" % [hp_damage, "，護甲吸收 %d" % blocked if blocked > 0 else ""]
		"sanity_damage":
			return "侵蝕 %d Sanity" % maxi(int(before.get("player_sanity", player.sanity)) - player.sanity, 0)
		"armor":
			return "取得 %d 護甲" % maxi(active_enemy.armor - int(before.get("enemy_armor", active_enemy.armor)), 0)
		"status_player":
			return "施加 %s ×%d" % [_status_display_name(str(intent.get("status_id", ""))), int(intent.get("amount", 0))]
		"status_self":
			return "獲得 %s ×%d" % [_status_display_name(str(intent.get("status_id", ""))), int(intent.get("amount", 0))]
		"idle":
			return "沒有直接行動"
		_:
			return "行動%s" % ("完成" if bool(execution_result.get("executed", false)) else "失敗")


func _status_display_name(status_id: String) -> String:
	return {"strength": "力量", "weak": "虛弱", "hard": "堅硬", "fragile": "脆弱", "poison": "中毒", "regen": "再生"}.get(status_id, status_id)

func _update_all_status_labels() -> void:
	if tablet != null and tablet.has_method("set_preview_entity"):
		tablet.set_preview_entity(player)
	_update_status_label(player_status_label_path, player)
	_update_player_hud()
	_update_enemy_status_ui()
	_update_turn_status_label()
	_update_ap_status_label()
	_update_intent_label()
	_update_end_turn_button()
	_update_spell_summary_label()
	_update_spell_legend()
	_update_tablet_slot_labels()


func _update_player_hud() -> void:
	var hud := get_node_or_null(player_hud_path) as PlayerHUD
	if hud == null or player == null:
		return
	hud.refresh(
		player,
		mp,
		max_mp,
		sanity_rules.get_stage_name(player.sanity),
		sanity_rules.get_active_summary(),
		current_action_points,
		player_max_action_points
	)

func _update_status_label(label_path: NodePath, entity: Entity) -> void:
	var label = get_node_or_null(label_path) as Label
	if label == null or entity == null:
		return
	label.text = "%s HP: %d/%d  ARMOR: %d" % [entity.entity_name, entity.hp, entity.max_hp, entity.armor]
	if entity.max_sanity > 0:
		label.text += "  SAN: %d/%d" % [entity.sanity, entity.max_sanity]
		if entity == player:
			label.text += "  MP: %d/%d" % [mp, max_mp]
		if entity == player and not sanity_rules.active_effect_ids.is_empty():
			label.text += "  [%s：%s]" % [sanity_rules.get_stage_name(entity.sanity), sanity_rules.get_active_summary()]
	if entity.has_method("get_status_summary"):
		var status_summary = entity.get_status_summary()
		if status_summary != "":
			label.text += "  %s" % status_summary

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
		var current_battle_turn := int(_battle_stats.values.get("turns", 0))
		var deadline_text := ""
		if turn_limit > 0:
			deadline_text = "  時限: %d/%d" % [current_battle_turn, turn_limit]
			if current_battle_turn > turn_limit:
				deadline_text += "（SAN 壓力累積）"
		label.text = "回合 %d%s%s" % [maxi(current_battle_turn, 1), deadline_text, sanity_warning]
	else:
		label.text = "敵方回合"


func _update_ap_status_label() -> void:
	var label := get_node_or_null(ap_status_label_path) as Label
	if label == null:
		return
	label.text = "AP  %d / %d" % [current_action_points, player_max_action_points]
	label.tooltip_text = "剩餘行動點；放置一塊石板消耗 1 點。"

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
		var intent_id := intent_state.current_intent_id(active_enemy.hp, active_enemy.max_hp, int(_battle_stats.values.get("turns", 1))) if intent_state != null else ""
		var intent: Dictionary = _intent_definitions.get(intent_id, {})
		lines.append("%s：%s" % [active_enemy.entity_name, intent.get("display_name", intent_id)])
	label.text = "\n".join(lines)

func _update_end_turn_button() -> void:
	var button = get_node_or_null(end_turn_button_path) as Button
	if button == null:
		return
	button.disabled = current_turn != TurnState.PLAYER_TURN or _is_battle_over()

func _update_spell_summary_label() -> void:
	var label = get_node_or_null(spell_summary_label_path) as Label
	if label == null:
		return
	label.text = "咒文構築｜大型分類符文即為效果格"
	label.tooltip_text = "完成 Row 或 Col 後，被消除的圖標格各觸發一次咒文；MP 不足時改以同額 Sanity 支付。"


func _on_payment_preview_changed(spells: Array) -> void:
	var label := get_node_or_null(payment_preview_label_path) as Label
	if label == null:
		return
	if spells.is_empty():
		label.text = ""
		label.tooltip_text = ""
		label.remove_theme_color_override("font_color")
		_set_payment_preview_visible(label, false)
		return
	_set_payment_preview_visible(label, true)
	label.add_theme_font_size_override("font_size", 15 if spells.size() > 6 else 17)
	var projected_mp := mp
	var projected_sanity := player.sanity if player != null else 0
	var mp_cost := 0
	var sanity_cost := 0
	var lines: Array[String] = ["預計觸發 %d 個咒文" % spells.size()]
	for value in spells:
		if not value is BattleItem:
			continue
		var spell := value as BattleItem
		var projected_effects: Array = sanity_rules.preview(player.sanity, projected_sanity - player.sanity).get("effects", []) if player != null else sanity_rules.active_effect_ids
		var cost := sanity_rules.modify_spell_mp_cost_for_effects(spell.mp_cost, projected_effects)
		if projected_mp >= cost:
			projected_mp -= cost
			mp_cost += cost
		else:
			sanity_cost += cost
			projected_sanity -= cost
		var summary: String = spell.get_runtime_summary(player)
		lines.append("%s  %s｜MP %d%s" % [spell.category_glyph, spell.spell_name, cost, "｜%s" % summary if not summary.is_empty() else ""])
	lines.append("合計：MP %d%s" % [mp_cost, "｜SAN 代付 %d" % sanity_cost if sanity_cost > 0 else ""])
	label.text = "\n".join(lines)
	label.tooltip_text = label.text
	if sanity_cost > 0:
		var fatal := player != null and projected_sanity <= 0
		label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25) if fatal else Color(1.0, 0.65, 0.25))
		if fatal:
			label.text += "｜警告：將導致理智歸零"
	else:
		label.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))


func _set_payment_preview_visible(label: Label, active: bool) -> void:
	label.visible = active
	var clip := label.get_parent() as Control
	if clip != null:
		clip.visible = active
		var title := clip.get_parent().get_node_or_null("PreviewTitle") as Label
		if title != null:
			title.visible = active


func _toggle_spell_legend() -> void:
	var legend := get_node_or_null(spell_legend_label_path) as Label
	var button := get_node_or_null(spell_legend_button_path) as Button
	if legend == null:
		return
	_update_spell_legend()
	legend.visible = not legend.visible
	if button != null:
		button.text = "收合咒文圖例" if legend.visible else "展開咒文圖例"


func _update_spell_legend() -> void:
	var legend := get_node_or_null(spell_legend_label_path) as Label
	if legend == null or tablet == null:
		return
	var unique := {}
	var grouped := {}
	var lines: Array[String] = ["咒文分類圖例"]
	for value in tablet.spell_pool:
		if not value is BattleItem:
			continue
		var spell := value as BattleItem
		if unique.has(spell.content_id):
			continue
		unique[spell.content_id] = true
		if not grouped.has(spell.category_id):
			grouped[spell.category_id] = {"glyph": spell.category_glyph, "name": spell.get_category_label(), "spells": []}
		grouped[spell.category_id].spells.append(spell)
	for category_id in BattleItem.CATEGORY_ORDER:
		if not grouped.has(category_id):
			continue
		var group: Dictionary = grouped[category_id]
		lines.append("%s  %s" % [group.glyph, group.name])
		for spell in group.spells:
			var summary: String = str(spell.get_runtime_summary(player))
			lines.append("　%s｜MP %d%s" % [spell.spell_name, sanity_rules.modify_spell_mp_cost(spell.mp_cost), "｜%s" % summary if not summary.is_empty() else ""])
	legend.text = "\n".join(lines)

func _update_tablet_slot_labels() -> void:
	pass

func _is_battle_over() -> bool:
	return (player != null and player.is_dead) or _are_all_enemies_dead() or (player != null and player.max_sanity > 0 and player.sanity <= 0)

func configure_player(player_name: String, max_hp: int, hp: int, max_sanity: int, sanity: int, max_action_points: int, player_max_mp: int = 100, player_mp: int = 70) -> void:
	if player == null:
		return
	player.entity_name = player_name
	player.reset_entity(player.entity_name, max_hp, hp, max_sanity, sanity)
	_sync_sanity_effects()
	player_max_action_points = max_action_points
	max_mp = maxi(player_max_mp, 1)
	mp = clampi(player_mp, 0, max_mp)
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
	turn_limit = input.turn_limit
	time_pressure_sanity_base = input.time_pressure_sanity_base
	time_pressure_sanity_growth = input.time_pressure_sanity_growth
	_intent_definitions = input.intent_definitions.duplicate(true)
	var state := input.player_state
	configure_player(
		str(state.get("name", "調查員")),
		int(state.get("max_hp", 80)),
		int(state.get("hp", 80)),
		int(state.get("max_sanity", 100)),
		int(state.get("sanity", 70)),
		int(state.get("action_points", player_max_action_points)),
		int(state.get("max_mp", 100)),
		int(state.get("mp", 70))
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
	_battle_sanity_history_start = sanity_history.size()
	_battle_stats.values["turn_limit"] = turn_limit
	_battle_stats.values["time_pressure_sanity"] = 0
	_battle_stats.values["overdue_turns"] = 0
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
	if battle_stage != null:
		battle_stage.begin_encounter(player.entity_name if player != null else "調查員")
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
		"mp": mp,
		"max_mp": max_mp,
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
	var statistics := _battle_stats.snapshot()
	var battle_sanity_history: Array[Dictionary] = []
	for index in range(_battle_sanity_history_start, sanity_history.size()):
		battle_sanity_history.append(sanity_history[index])
	statistics["sanity_loss_by_source"] = sanity_rules.summarize_losses(battle_sanity_history)
	var final_reason := reason
	if not won and player != null and player.sanity <= 0:
		var depletion_source := sanity_rules.get_depletion_source(battle_sanity_history)
		statistics["sanity_defeat_source"] = str(depletion_source.get("key", ""))
		statistics["sanity_defeat_source_label"] = str(depletion_source.get("label", ""))
		if not str(depletion_source.get("label", "")).is_empty():
			final_reason = "Sanity 歸零（%s）" % depletion_source.get("label", "")
	var result := BattleResult.create(won, final_reason, _current_encounter_id, get_player_state(), statistics)
	battle_finished.emit(result)
	if won:
		battle_won.emit()
	else:
		battle_lost.emit(final_reason)

func _execute_spell_on_scope(spell: BattleItem, board_cell: Vector2i) -> void:
	var context := BattleEffectContext.new()
	context.user = player
	context.effect_cell = board_cell
	context.spell_trigger_count = current_turn_spell_triggers
	context.trigger_history = _trigger_history.duplicate(true)
	context.battle_state = {"turn": current_turn, "action_points": current_action_points, "encounter_id": _current_encounter_id}
	if spell.effect_scope == "self":
		context.primary_target = player
		context.targets = [player]
		spell.execute_with_context(player, player, context)
	else:
		context.primary_target = _get_selected_enemy()
		context.targets = _target_resolver.resolve(spell.effect_scope, enemies, selected_enemy_index)
	for target in context.targets:
		if target != null and not target.is_dead:
			if spell.effect_scope != "self":
				spell.execute_with_context(target, player, context)
	_trigger_history.append({"spell_id": spell.content_id, "cell": [board_cell.x, board_cell.y], "target_count": context.targets.size()})
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


func _first_living_enemy_index() -> int:
	for index in range(enemies.size()):
		var active_enemy := enemies[index]
		if active_enemy != null and not active_enemy.is_dead:
			return index
	return -1

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
	# 讓最後一擊的死亡演出完整播放，再切到戰鬥結算畫面。
	if _pending_enemy_death_presentation:
		return
	match _outcome_resolver.resolve(player, enemies):
		BattleOutcomeResolver.Outcome.VICTORY:
			_finish_battle(true, "敵人已倒下")
		BattleOutcomeResolver.Outcome.HP_DEFEAT:
			_finish_battle(false, "HP 歸零")
		BattleOutcomeResolver.Outcome.SANITY_DEFEAT:
			_finish_battle(false, "Sanity 歸零")

func _finish_enemy_death_presentation_deferred() -> void:
	await get_tree().create_timer(0.72).timeout
	_pending_enemy_death_presentation = false
	_settle_battle_outcome()


func _apply_time_pressure_if_needed() -> void:
	if player == null or turn_limit <= 0:
		return
	var battle_turn := int(_battle_stats.values.get("turns", 0))
	if battle_turn <= turn_limit:
		return
	var overdue_turn := battle_turn - turn_limit
	var loss := time_pressure_sanity_base + (overdue_turn - 1) * time_pressure_sanity_growth
	if loss <= 0:
		return
	var sanity_before := player.sanity
	player.spend_sanity(loss, "battle_time:%s" % _current_encounter_id)
	_battle_stats.add("time_pressure_sanity", sanity_before - player.sanity)
	_battle_stats.add("overdue_turns")

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
		var intent: Dictionary = _intent_definitions.get(state.current_intent_id(active_enemy.hp, active_enemy.max_hp, int(_battle_stats.values.get("turns", 1))) if state != null else "", {})
		active_enemy.set_meta("intent_display", str(intent.get("display_name", "--")))
		active_enemy.set_meta("intent_id", str(intent.get("id", "")))
	var label = get_node_or_null(enemy_status_label_path) as Label
	_enemy_presenter.render(label, enemies, selected_enemy_index, _select_enemy)

func _select_enemy(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return
	if enemies[index] == null or enemies[index].is_dead:
		return
	selected_enemy_index = index
	_update_all_status_labels()


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
	floating_label.z_index = 100
	floating_label.size = Vector2(220, 52)
	floating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floating_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	floating_label.add_theme_font_size_override("font_size", 28)
	floating_label.add_theme_constant_override("outline_size", 6)
	floating_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.96))
	var pixel_font := load("res://assets/fonts/fusion-pixel-12px-zh_hant.ttf") as FontFile
	if pixel_font != null:
		floating_label.add_theme_font_override("font", pixel_font)
	anchor.get_parent().add_child(floating_label)
	floating_label.global_position = anchor.global_position + Vector2(anchor.size.x * 0.5 - 110.0, -38.0)
	floating_label.pivot_offset = floating_label.size * 0.5
	floating_label.scale = Vector2(0.72, 0.72)
	var tween = create_tween()
	tween.parallel().tween_property(floating_label, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(floating_label, "global_position", floating_label.global_position + Vector2(0, -16), 0.16)
	tween.tween_interval(0.34)
	tween.parallel().tween_property(floating_label, "global_position", floating_label.global_position + Vector2(0, -62), 0.42)
	tween.parallel().tween_property(floating_label, "modulate:a", 0.0, 0.42)
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
	sanity_rules.synchronize(after)
	sanity_rules.apply_entity_modifiers(player)
	var source_label := sanity_rules.get_source_label(source)
	sanity_history.append({"source": source, "source_label": source_label, "delta": delta, "before": before, "after": after, "active_effect_ids": sanity_rules.active_effect_ids.duplicate()})
	_update_all_status_labels()


func _sync_sanity_effects() -> void:
	if player == null:
		return
	sanity_rules.synchronize(player.sanity)
	sanity_rules.apply_entity_modifiers(player)
