class_name BattleBatchSimulator
extends RefCounted

const BoardSimulatorScript = preload("res://scripts/board/board_simulator.gd")
const DEFAULT_BATTLES := 10
const DEFAULT_MAX_TURNS := 12

var _board_simulator = BoardSimulatorScript.new()
var _intent_executor := EnemyIntentExecutor.new()
var _target_resolver := TargetResolver.new()
var _outcome_resolver := BattleOutcomeResolver.new()


func simulate_encounter_with_session(
	encounter: Dictionary,
	enemy_definitions: Dictionary,
	intent_definitions: Dictionary,
	player_state: Dictionary,
	row_items: Array[BattleItem],
	col_items: Array[BattleItem],
	board_session: Dictionary,
	sanity_document: Dictionary,
	seed: int,
	max_turns: int = DEFAULT_MAX_TURNS
) -> Dictionary:
	if board_session.is_empty():
		return {"outcome": "invalid_board", "turns": 0}
	return _simulate_once(
		encounter,
		enemy_definitions,
		intent_definitions,
		player_state,
		row_items,
		col_items,
		[],
		sanity_document,
		seed,
		maxi(max_turns, 1),
		board_session
	)


func simulate(
	encounters: Array,
	enemy_definitions: Dictionary,
	intent_definitions: Dictionary,
	player_config: Dictionary,
	row_items: Array[BattleItem],
	col_items: Array[BattleItem],
	block_pool: Array[BlockData],
	board_rules: Dictionary,
	sanity_document: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	if row_items.size() != 8 or col_items.size() != 8:
		return {"error": "戰鬥批次模擬需要各 8 個 Row／Col 道具"}
	if block_pool.is_empty():
		return {"error": "戰鬥批次模擬的方塊池不可為空"}
	var battles := maxi(int(options.get("battles", DEFAULT_BATTLES)), 1)
	var max_turns := maxi(int(options.get("max_turns", DEFAULT_MAX_TURNS)), 1)
	var action_points := maxi(int(player_config.get("action_points", 5)), 1)
	var seed := int(options.get("seed", 424242))
	var event_sequences: Array[Array] = []
	for battle_index in range(battles):
		var events := _board_simulator.generate_events(block_pool, board_rules, {
			"mode": BoardSimulatorScript.SMART_MODE,
			"seed": seed + battle_index * 104729,
			"placements": max_turns * action_points,
			"hand_size": 3,
			"action_points": action_points,
		})
		if events.is_empty():
			return {"error": "無法產生棋盤事件序列"}
		event_sequences.append(events)
	var reports: Array[Dictionary] = []
	for encounter in encounters:
		if not encounter is Dictionary:
			continue
		var trials: Array[Dictionary] = []
		for battle_index in range(battles):
			trials.append(_simulate_once(
				encounter,
				enemy_definitions,
				intent_definitions,
				player_config,
				row_items,
				col_items,
				event_sequences[battle_index],
				sanity_document,
				seed + battle_index * 104729,
				max_turns
			))
		reports.append(_summarize_encounter(encounter, trials, max_turns))
	return {
		"seed": seed,
		"battles_per_encounter": battles,
		"max_turns": max_turns,
		"policy": "智慧手牌最高分放置；每次放置前手動鎖定第一名存活敵人",
		"encounters": reports,
	}


func _simulate_once(
	encounter: Dictionary,
	enemy_definitions: Dictionary,
	intent_definitions: Dictionary,
	player_config: Dictionary,
	row_items: Array[BattleItem],
	col_items: Array[BattleItem],
	events: Array,
	sanity_document: Dictionary,
	seed: int,
	max_turns: int,
	board_session: Dictionary = {}
) -> Dictionary:
	var stats := {
		"outcome": "timeout",
		"turns": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"damage_blocked": 0,
		"armor_gained": 0,
		"sanity_spent": 0,
		"rows_cleared": 0,
		"cols_cleared": 0,
		"dead_boards": 0,
		"survival_curve": {},
	}
	var player := Entity.new()
	player.set_meta("simulation_quiet", true)
	player.reset_entity(
		str(player_config.get("name", "調查員")),
		int(player_config.get("max_hp", 80)),
		int(player_config.get("hp", 80)),
		int(player_config.get("max_sanity", 100)),
		int(player_config.get("sanity", 70))
	)
	player.damage_resolved.connect(func(_entity: Entity, hp_damage: int, blocked_damage: int):
		stats.damage_taken = int(stats.damage_taken) + hp_damage
		stats.damage_blocked = int(stats.damage_blocked) + blocked_damage
	)
	player.armor_gained.connect(func(_entity: Entity, amount: int): stats.armor_gained = int(stats.armor_gained) + amount)
	player.sanity_spent.connect(func(_entity: Entity, amount: int): stats.sanity_spent = int(stats.sanity_spent) + amount)
	var enemies := _create_enemies(encounter, enemy_definitions, stats)
	var sanity_rules := SanityRuleEngine.new()
	sanity_rules.configure(sanity_document, seed)
	_sync_sanity_rules(sanity_rules, player)
	var trigger_history: Array[Dictionary] = []
	var event_index := 0
	for turn in range(1, max_turns + 1):
		stats.turns = turn
		player.clear_armor()
		var weapon_triggers := 0
		if not board_session.is_empty() and not _board_simulator.begin_session_turn(board_session):
			stats.outcome = "invalid_board"
			break
		var event_guard := 100
		while event_guard > 0:
			event_guard -= 1
			var event: Dictionary
			if board_session.is_empty():
				if event_index >= events.size() or int(events[event_index].get("turn", 0)) != turn:
					break
				event = events[event_index]
				event_index += 1
			else:
				if int(board_session.get("action_points_left", 0)) <= 0:
					break
				event = _board_simulator.next_session_event(board_session)
				if str(event.get("type", "")) in ["invalid", "turn_complete"]:
					stats.outcome = "invalid_board"
					break
			if str(event.get("type", "")) == "dead_board":
				player.spend_sanity(sanity_rules.modify_dead_board_penalty(10), "dead_board")
				stats.dead_boards = int(stats.dead_boards) + 1
				_sync_sanity_rules(sanity_rules, player)
			else:
				# 同一次放置造成的 Col → Row 連續效果共用鎖定；目標死亡後不在序列中自動改鎖。
				var selected_index := _first_living_index(enemies)
				for col in event.get("cols", []):
					var col_index := int(col)
					if col_index < 0 or col_index >= col_items.size() or col_items[col_index] == null:
						continue
					var magic_item := col_items[col_index]
					var base_cost := magic_item.sanity_cost if magic_item.sanity_cost > 0 else 3
					player.spend_sanity(sanity_rules.modify_magic_cost(base_cost), "magic:%s" % magic_item.content_id)
					_sync_sanity_rules(sanity_rules, player)
					if _outcome_name(player, enemies) != "active":
						break
					_execute_item(magic_item, player, enemies, selected_index, "col", col_index, weapon_triggers, trigger_history, turn)
					stats.cols_cleared = int(stats.cols_cleared) + 1
					if _outcome_name(player, enemies) != "active":
						break
				if _outcome_name(player, enemies) == "active":
					for row in event.get("rows", []):
						var row_index := int(row)
						if row_index < 0 or row_index >= row_items.size() or row_items[row_index] == null:
							continue
						_execute_item(row_items[row_index], player, enemies, selected_index, "row", row_index, weapon_triggers, trigger_history, turn)
						stats.rows_cleared = int(stats.rows_cleared) + 1
						weapon_triggers += 1
						if _outcome_name(player, enemies) != "active":
							break
			if _outcome_name(player, enemies) != "active":
				break
		if str(stats.outcome) == "invalid_board":
			_record_survival(stats, turn, enemies)
			break
		var outcome := _outcome_name(player, enemies)
		if outcome != "active":
			stats.outcome = outcome
			_record_survival(stats, turn, enemies)
			break
		player.trigger_end_of_turn_statuses()
		outcome = _outcome_name(player, enemies)
		if outcome == "active":
			for active_enemy in _enemy_action_order(enemies):
				if active_enemy.is_dead:
					continue
				active_enemy.clear_armor()
				var intent_state := active_enemy.get_meta("intent_state") as EnemyIntentState
				var intent_id := intent_state.current_intent_id()
				var intent: Dictionary = intent_definitions.get(intent_id, {})
				if intent.is_empty():
					stats.outcome = "invalid_intent"
					break
				_intent_executor.execute(intent, active_enemy, player)
				intent_state.advance()
				_sync_sanity_rules(sanity_rules, player)
				active_enemy.trigger_end_of_turn_statuses()
				outcome = _outcome_name(player, enemies)
				if outcome != "active":
					stats.outcome = outcome
					break
		if str(stats.outcome) == "invalid_intent":
			_record_survival(stats, turn, enemies)
			break
		if _outcome_name(player, enemies) == "active":
			player.decay_statuses()
			for active_enemy in enemies:
				active_enemy.decay_statuses()
		else:
			stats.outcome = _outcome_name(player, enemies)
		_record_survival(stats, turn, enemies)
		if str(stats.outcome) != "timeout":
			break
	stats.player_hp_end = player.hp
	stats.player_sanity_end = player.sanity
	stats.enemies_alive_end = _living_count(enemies)
	for active_enemy in enemies:
		active_enemy.free()
	player.free()
	return stats


func _create_enemies(encounter: Dictionary, enemy_definitions: Dictionary, stats: Dictionary) -> Array[Entity]:
	var enemies: Array[Entity] = []
	for enemy_id in encounter.get("enemy_ids", []):
		var enemy_def: Dictionary = enemy_definitions.get(str(enemy_id), {})
		if enemy_def.is_empty():
			continue
		var enemy := Entity.new()
		enemy.set_meta("simulation_quiet", true)
		enemy.reset_entity(str(enemy_def.get("name", enemy_id)), int(enemy_def.get("hp", 1)))
		enemy.set_meta("content_id", str(enemy_id))
		enemy.set_meta("attack_damage", int(enemy_def.get("attack", 0)))
		enemy.set_meta("speed", int(enemy_def.get("speed", 0)))
		enemy.set_meta("spawn_index", enemies.size())
		var intent_state := EnemyIntentState.new()
		intent_state.configure(enemy_def.get("intent_pattern", []))
		enemy.set_meta("intent_state", intent_state)
		enemy.damage_resolved.connect(func(_entity: Entity, hp_damage: int, _blocked_damage: int): stats.damage_dealt = int(stats.damage_dealt) + hp_damage)
		enemies.append(enemy)
	return enemies


func _execute_item(
	item: BattleItem,
	player: Entity,
	enemies: Array[Entity],
	selected_index: int,
	axis: String,
	index: int,
	weapon_triggers: int,
	trigger_history: Array[Dictionary],
	turn: int
) -> void:
	var context := BattleEffectContext.new()
	context.user = player
	context.trigger_axis = axis
	context.trigger_index = index
	context.weapon_trigger_count = weapon_triggers
	context.trigger_history = trigger_history.duplicate(true)
	context.battle_state = {"turn": turn, "action_points": 0, "encounter_id": "batch"}
	if item.effect_scope == "self":
		context.primary_target = player
		context.targets = [player]
		item.execute_with_context(player, player, context)
	else:
		context.primary_target = enemies[selected_index] if selected_index >= 0 else null
		context.targets = _target_resolver.resolve(item.effect_scope, enemies, selected_index)
		for target in context.targets:
			if target != null and not target.is_dead:
				item.execute_with_context(target, player, context)
	trigger_history.append({"item_id": item.content_id, "axis": axis, "index": index, "target_count": context.targets.size()})


func _sync_sanity_rules(rules: SanityRuleEngine, player: Entity) -> void:
	rules.synchronize(player.sanity)
	rules.apply_entity_modifiers(player)


func _outcome_name(player: Entity, enemies: Array[Entity]) -> String:
	match _outcome_resolver.resolve(player, enemies):
		BattleOutcomeResolver.Outcome.VICTORY:
			return "victory"
		BattleOutcomeResolver.Outcome.HP_DEFEAT:
			return "hp_defeat"
		BattleOutcomeResolver.Outcome.SANITY_DEFEAT:
			return "sanity_defeat"
	return "active"


func _enemy_action_order(enemies: Array[Entity]) -> Array[Entity]:
	var order: Array[Entity] = []
	for enemy in enemies:
		if enemy != null and not enemy.is_dead:
			order.append(enemy)
	order.sort_custom(func(a: Entity, b: Entity):
		var a_speed := int(a.get_meta("speed", 0))
		var b_speed := int(b.get_meta("speed", 0))
		if a_speed == b_speed:
			return int(a.get_meta("spawn_index", 0)) < int(b.get_meta("spawn_index", 0))
		return a_speed > b_speed
	)
	return order


func _first_living_index(enemies: Array[Entity]) -> int:
	for index in range(enemies.size()):
		if enemies[index] != null and not enemies[index].is_dead:
			return index
	return -1


func _living_count(enemies: Array[Entity]) -> int:
	var count := 0
	for enemy in enemies:
		if enemy != null and not enemy.is_dead:
			count += 1
	return count


func _record_survival(stats: Dictionary, turn: int, enemies: Array[Entity]) -> void:
	stats.survival_curve[turn] = _living_count(enemies)


func _summarize_encounter(encounter: Dictionary, trials: Array[Dictionary], max_turns: int) -> Dictionary:
	var totals := {
		"victories": 0,
		"hp_defeats": 0,
		"sanity_defeats": 0,
		"timeouts": 0,
		"turns": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"damage_blocked": 0,
		"armor_gained": 0,
		"sanity_spent": 0,
		"rows_cleared": 0,
		"cols_cleared": 0,
		"dead_boards": 0,
		"player_hp_end": 0,
		"player_sanity_end": 0,
	}
	var survival_sum := {}
	for turn in range(1, max_turns + 1):
		survival_sum[turn] = 0
	for trial in trials:
		match str(trial.outcome):
			"victory": totals.victories = int(totals.victories) + 1
			"hp_defeat": totals.hp_defeats = int(totals.hp_defeats) + 1
			"sanity_defeat": totals.sanity_defeats = int(totals.sanity_defeats) + 1
			_: totals.timeouts = int(totals.timeouts) + 1
		for key in ["turns", "damage_dealt", "damage_taken", "damage_blocked", "armor_gained", "sanity_spent", "rows_cleared", "cols_cleared", "dead_boards", "player_hp_end", "player_sanity_end"]:
			totals[key] = int(totals[key]) + int(trial.get(key, 0))
		var final_alive := int(trial.get("enemies_alive_end", 0))
		for turn in range(1, max_turns + 1):
			var alive := int(trial.survival_curve.get(turn, final_alive))
			survival_sum[turn] = int(survival_sum[turn]) + alive
	var count := maxi(trials.size(), 1)
	var survival_curve: Array[float] = []
	for turn in range(1, max_turns + 1):
		survival_curve.append(float(survival_sum[turn]) / float(count))
	return {
		"encounter_id": str(encounter.get("id", "")),
		"name": str(encounter.get("name", "")),
		"battles": trials.size(),
		"win_rate": float(totals.victories) / float(count),
		"hp_defeats": int(totals.hp_defeats),
		"sanity_defeats": int(totals.sanity_defeats),
		"timeouts": int(totals.timeouts),
		"average_turns": float(totals.turns) / float(count),
		"average_damage_dealt": float(totals.damage_dealt) / float(count),
		"average_damage_taken": float(totals.damage_taken) / float(count),
		"average_damage_blocked": float(totals.damage_blocked) / float(count),
		"average_armor_gained": float(totals.armor_gained) / float(count),
		"average_sanity_spent": float(totals.sanity_spent) / float(count),
		"average_rows_cleared": float(totals.rows_cleared) / float(count),
		"average_cols_cleared": float(totals.cols_cleared) / float(count),
		"average_dead_boards": float(totals.dead_boards) / float(count),
		"average_player_hp_end": float(totals.player_hp_end) / float(count),
		"average_player_sanity_end": float(totals.player_sanity_end) / float(count),
		"enemy_survival_curve": survival_curve,
	}
