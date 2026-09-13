class_name BattleBatchSimulator
extends RefCounted

const BoardSimulatorScript = preload("res://scripts/board/board_simulator.gd")
const DEFAULT_BATTLES := 10
const DEFAULT_MAX_TURNS := 12

var _board_simulator = BoardSimulatorScript.new()
var _intent_executor := EnemyIntentExecutor.new()
var _target_resolver := TargetResolver.new()
var _outcome_resolver := BattleOutcomeResolver.new()
var _difficulty_calculator := EncounterDifficultyCalculator.new()


func simulate_encounter_with_session(
	encounter: Dictionary,
	enemy_definitions: Dictionary,
	intent_definitions: Dictionary,
	player_state: Dictionary,
	board_session: Dictionary,
	sanity_document: Dictionary,
	seed: int,
	max_turns: int = DEFAULT_MAX_TURNS,
	battle_context: Dictionary = {}
) -> Dictionary:
	if board_session.is_empty():
		return {"outcome": "invalid_board", "turns": 0}
	return _simulate_once(
		encounter,
		enemy_definitions,
		intent_definitions,
		player_state,
		[],
		sanity_document,
		seed,
		maxi(max_turns, 1),
		board_session,
		battle_context
	)


func simulate(
	encounters: Array,
	enemy_definitions: Dictionary,
	intent_definitions: Dictionary,
	player_config: Dictionary,
	spells: Array[BattleItem],
	block_pool: Array[BlockData],
	board_rules: Dictionary,
	sanity_document: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	if spells.is_empty():
		return {"error": "戰鬥批次模擬的咒文池不可為空"}
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
			"spell_pool": spells,
		})
		if events.is_empty():
			return {"error": "無法產生棋盤事件序列"}
		event_sequences.append(events)
	var reports: Array[Dictionary] = []
	for encounter_index in range(encounters.size()):
		var encounter = encounters[encounter_index]
		if not encounter is Dictionary:
			continue
		var enemy_defs: Array = []
		for enemy_id in encounter.get("enemy_ids", []):
			var enemy_def: Dictionary = enemy_definitions.get(str(enemy_id), {})
			if not enemy_def.is_empty():
				enemy_defs.append(enemy_def)
		var depth_by_encounter = options.get("node_depths", [0, 1, 2, 4, 3, 9, 6, 7])
		var node_depth := int(depth_by_encounter[mini(encounter_index, depth_by_encounter.size() - 1)]) if depth_by_encounter is Array and not depth_by_encounter.is_empty() else encounter_index
		var battle_context := _difficulty_calculator.calculate(enemy_defs, options.get("difficulty_model", {}), {"node_depth": node_depth})
		var trials: Array[Dictionary] = []
		for battle_index in range(battles):
			trials.append(_simulate_once(
				encounter,
				enemy_definitions,
				intent_definitions,
				player_config,
				event_sequences[battle_index],
				sanity_document,
				seed + battle_index * 104729,
				max_turns,
				{},
				battle_context
			))
		reports.append(_summarize_encounter(encounter, trials, max_turns))
	return {
		"seed": seed,
		"battles_per_encounter": battles,
		"max_turns": max_turns,
		"policy": "智慧手牌最高分放置；效果格消除支付 MP 觸發咒文；目標死亡自動切換",
		"encounters": reports,
	}


func _simulate_once(
	encounter: Dictionary,
	enemy_definitions: Dictionary,
	intent_definitions: Dictionary,
	player_config: Dictionary,
	events: Array,
	sanity_document: Dictionary,
	seed: int,
	max_turns: int,
	board_session: Dictionary = {},
	battle_context: Dictionary = {}
) -> Dictionary:
	var stats := {
		"outcome": "timeout",
		"turns": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"damage_blocked": 0,
		"armor_gained": 0,
		"sanity_spent": 0,
		"sanity_loss_by_source": {},
		"sanity_defeat_source": "",
		"mp_spent": 0,
		"spell_fizzles": 0,
		"spells_triggered": 0,
		"spells_paid_with_sanity": 0,
		"time_pressure_sanity": 0,
		"overdue_turns": 0,
		"turn_limit": maxi(int(battle_context.get("turn_limit", 0)), 0),
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
	player.sanity_changed.connect(func(_entity: Entity, delta: int, source: String, _before: int, after: int):
		if delta >= 0:
			return
		var source_key := sanity_rules.get_source_key(source)
		stats.sanity_loss_by_source[source_key] = int(stats.sanity_loss_by_source.get(source_key, 0)) - delta
		if after <= 0:
			stats.sanity_defeat_source = source_key
	)
	_sync_sanity_rules(sanity_rules, player)
	var trigger_history: Array[Dictionary] = []
	var mp := int(player_config.get("mp", 70))
	var turn_limit := maxi(int(battle_context.get("turn_limit", 0)), 0)
	var pressure_base := maxi(int(battle_context.get("time_pressure_sanity_base", 0)), 0)
	var pressure_growth := maxi(int(battle_context.get("time_pressure_sanity_growth", 0)), 0)
	var event_index := 0
	for turn in range(1, max_turns + 1):
		stats.turns = turn
		if turn_limit > 0 and turn > turn_limit:
			var overdue_turn := turn - turn_limit
			var pressure_loss := pressure_base + (overdue_turn - 1) * pressure_growth
			var sanity_before := player.sanity
			player.spend_sanity(pressure_loss, "battle_time:%s" % encounter.get("id", ""))
			stats.time_pressure_sanity = int(stats.time_pressure_sanity) + sanity_before - player.sanity
			stats.overdue_turns = int(stats.overdue_turns) + 1
			_sync_sanity_rules(sanity_rules, player)
			if _outcome_name(player, enemies) != "active":
				stats.outcome = _outcome_name(player, enemies)
				_record_survival(stats, turn, enemies)
				break
		player.clear_armor()
		var spell_triggers := 0
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
				stats.rows_cleared = int(stats.rows_cleared) + event.get("rows", []).size()
				stats.cols_cleared = int(stats.cols_cleared) + event.get("cols", []).size()
				for spell in event.get("spells", []):
					if not spell is BattleItem:
						continue
					var cost := sanity_rules.modify_spell_mp_cost(spell.mp_cost)
					if mp < cost:
						player.spend_sanity(cost, "spell:fallback:%s" % spell.content_id)
						stats.spells_paid_with_sanity = int(stats.spells_paid_with_sanity) + 1
					else:
						mp -= cost
						stats.mp_spent = int(stats.mp_spent) + cost
					stats.spells_triggered = int(stats.spells_triggered) + 1
					_execute_spell(spell, player, enemies, _first_living_index(enemies), spell_triggers, trigger_history, turn)
					spell_triggers += 1
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
				var intent_id := intent_state.current_intent_id(active_enemy.hp, active_enemy.max_hp, turn)
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
	stats.player_mp_end = mp
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
		intent_state.configure(enemy_def.get("intent_pattern", []), 0, enemy_def.get("intent_rules", []))
		enemy.set_meta("intent_state", intent_state)
		enemy.damage_resolved.connect(func(_entity: Entity, hp_damage: int, _blocked_damage: int): stats.damage_dealt = int(stats.damage_dealt) + hp_damage)
		enemies.append(enemy)
	return enemies


func _execute_spell(
	spell: BattleItem,
	player: Entity,
	enemies: Array[Entity],
	selected_index: int,
	spell_triggers: int,
	trigger_history: Array[Dictionary],
	turn: int
) -> void:
	if selected_index < 0 or selected_index >= enemies.size() or enemies[selected_index] == null or enemies[selected_index].is_dead:
		selected_index = _first_living_index(enemies)
	var context := BattleEffectContext.new()
	context.user = player
	context.spell_trigger_count = spell_triggers
	context.trigger_history = trigger_history.duplicate(true)
	context.battle_state = {"turn": turn, "action_points": 0, "encounter_id": "batch"}
	if spell.effect_scope == "self":
		context.primary_target = player
		context.targets = [player]
		spell.execute_with_context(player, player, context)
	else:
		context.primary_target = enemies[selected_index] if selected_index >= 0 else null
		context.targets = _target_resolver.resolve(spell.effect_scope, enemies, selected_index)
		for target in context.targets:
			if target != null and not target.is_dead:
				spell.execute_with_context(target, player, context)
	trigger_history.append({"spell_id": spell.content_id, "target_count": context.targets.size()})


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
		"mp_spent": 0,
		"spell_fizzles": 0,
		"spells_triggered": 0,
		"spells_paid_with_sanity": 0,
		"time_pressure_sanity": 0,
		"overdue_turns": 0,
		"rows_cleared": 0,
		"cols_cleared": 0,
		"dead_boards": 0,
		"player_hp_end": 0,
		"player_sanity_end": 0,
		"player_mp_end": 0,
		"sanity_defeat_sources": {},
	}
	var survival_sum := {}
	for turn in range(1, max_turns + 1):
		survival_sum[turn] = 0
	for trial in trials:
		match str(trial.outcome):
			"victory": totals.victories = int(totals.victories) + 1
			"hp_defeat": totals.hp_defeats = int(totals.hp_defeats) + 1
			"sanity_defeat":
				totals.sanity_defeats = int(totals.sanity_defeats) + 1
				var source_key := str(trial.get("sanity_defeat_source", "unknown"))
				totals.sanity_defeat_sources[source_key] = int(totals.sanity_defeat_sources.get(source_key, 0)) + 1
			_: totals.timeouts = int(totals.timeouts) + 1
		for key in ["turns", "damage_dealt", "damage_taken", "damage_blocked", "armor_gained", "sanity_spent", "mp_spent", "spell_fizzles", "spells_triggered", "spells_paid_with_sanity", "time_pressure_sanity", "overdue_turns", "rows_cleared", "cols_cleared", "dead_boards", "player_hp_end", "player_sanity_end", "player_mp_end"]:
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
		"sanity_defeat_sources": totals.sanity_defeat_sources.duplicate(true),
		"timeouts": int(totals.timeouts),
		"average_turns": float(totals.turns) / float(count),
		"average_damage_dealt": float(totals.damage_dealt) / float(count),
		"average_damage_taken": float(totals.damage_taken) / float(count),
		"average_damage_blocked": float(totals.damage_blocked) / float(count),
		"average_armor_gained": float(totals.armor_gained) / float(count),
		"average_sanity_spent": float(totals.sanity_spent) / float(count),
		"average_mp_spent": float(totals.mp_spent) / float(count),
		"average_spell_fizzles": float(totals.spell_fizzles) / float(count),
		"average_spells_triggered": float(totals.spells_triggered) / float(count),
		"average_spells_paid_with_sanity": float(totals.spells_paid_with_sanity) / float(count),
		"average_time_pressure_sanity": float(totals.time_pressure_sanity) / float(count),
		"average_overdue_turns": float(totals.overdue_turns) / float(count),
		"average_rows_cleared": float(totals.rows_cleared) / float(count),
		"average_cols_cleared": float(totals.cols_cleared) / float(count),
		"average_dead_boards": float(totals.dead_boards) / float(count),
		"average_player_hp_end": float(totals.player_hp_end) / float(count),
		"average_player_sanity_end": float(totals.player_sanity_end) / float(count),
		"average_player_mp_end": float(totals.player_mp_end) / float(count),
		"enemy_survival_curve": survival_curve,
	}
