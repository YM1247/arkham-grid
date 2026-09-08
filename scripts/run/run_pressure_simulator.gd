class_name RunPressureSimulator
extends RefCounted

const BattleBatchSimulatorScript = preload("res://scripts/battle/battle_batch_simulator.gd")
const BoardSimulatorScript = preload("res://scripts/board/board_simulator.gd")
const LayeredMapGeneratorScript = preload("res://scripts/run/layered_map_generator.gd")
const RewardCandidateSelectorScript = preload("res://scripts/growth/reward_candidate_selector.gd")
const EncounterDifficultyCalculatorScript = preload("res://scripts/growth/encounter_difficulty_calculator.gd")
const EventChoiceResolverScript = preload("res://scripts/run/event_choice_resolver.gd")

const DEFAULT_RUNS := 10
const DEFAULT_MAX_TURNS := 12

var _battle_simulator = BattleBatchSimulatorScript.new()
var _board_simulator = BoardSimulatorScript.new()
var _map_generator = LayeredMapGeneratorScript.new()
var _reward_selector = RewardCandidateSelectorScript.new()
var _difficulty_calculator = EncounterDifficultyCalculatorScript.new()
var _choice_resolver = EventChoiceResolverScript.new()


func simulate(content: ContentRegistry, options: Dictionary = {}) -> Dictionary:
	if content == null or content.errors.size() > 0:
		return {"error": "完整 Run 模擬需要已通過驗證的 ContentRegistry"}
	var runs := maxi(int(options.get("runs", DEFAULT_RUNS)), 1)
	var max_turns := maxi(int(options.get("max_turns", DEFAULT_MAX_TURNS)), 1)
	var run_config := content.get_document("run_config")
	var base_seed := int(options.get("seed", run_config.get("seed", 424242)))
	var results: Array[Dictionary] = []
	for run_index in range(runs):
		results.append(_simulate_once(content, base_seed + run_index * 104729, max_turns))
	return _summarize(results, base_seed, max_turns)


func _simulate_once(content: ContentRegistry, seed: int, max_turns: int) -> Dictionary:
	var run_config := content.get_document("run_config")
	var player_document := content.get_document("player")
	var map_data := _map_generator.generate(seed, content.get_document("map"))
	if not _map_generator.verify_connectivity(map_data):
		return {"outcome": "invalid_map", "seed": seed, "battle_curve": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var route := _pick_route(map_data, rng)
	var spell_ids := RunState._strings(run_config.get("spell_pool", []))
	var board_session := _board_simulator.create_session(
		content.get_blocks(run_config.get("block_pool", [])),
		run_config.get("board_growth_rules", {}),
		{
			"mode": BoardSimulatorScript.SMART_MODE,
			"seed": seed,
			"hand_size": 3,
			"action_points": int(player_document.get("action_points", 5)),
			"spell_pool": content.get_spells(spell_ids),
		}
	)
	if board_session.is_empty():
		return {"outcome": "invalid_board", "seed": seed, "battle_curve": []}
	var player_state := player_document.duplicate(true)
	player_state["currency"] = 0
	var selected_reward_ids: Array[String] = []
	var battle_curve: Array[Dictionary] = []
	var battles_won := 0
	var rests := 0
	var rewards_taken := 0
	var spells_taken := 0
	var special_blocks := 0
	var outcome := "route_incomplete"
	var failed_encounter_id := ""
	var enemy_index: Dictionary = content.indexes.get("enemies", {})
	var intent_index: Dictionary = content.indexes.get("intents", {})
	var mp_restore_per_node := maxi(int(run_config.get("mp_restore_per_node", 35)), 0)
	for node in route:
		var node_type := str(node.get("type", ""))
		if node_type in ["event", "shop", "rest"]:
			if not _apply_first_affordable_choice(content, node, player_state):
				outcome = "invalid_node_content"
				break
			if node_type == "rest":
				rests += 1
			_restore_mp(player_state, mp_restore_per_node)
			continue
		if node_type not in ["normal_battle", "elite", "boss"]:
			outcome = "invalid_node_type"
			break
		var encounter := content.get_definition("encounters", str(node.get("content_id", "")))
		if encounter.is_empty():
			outcome = "invalid_encounter"
			break
		var battle_result := _battle_simulator.simulate_encounter_with_session(
			encounter,
			enemy_index,
			intent_index,
			player_state,
			board_session,
			content.get_document("sanity"),
			seed,
			max_turns
		)
		player_state.hp = int(battle_result.get("player_hp_end", player_state.get("hp", 0)))
		player_state.sanity = int(battle_result.get("player_sanity_end", player_state.get("sanity", 0)))
		player_state.mp = int(battle_result.get("player_mp_end", player_state.get("mp", 0)))
		battle_curve.append({
			"battle": battle_curve.size() + 1,
			"encounter_id": str(encounter.get("id", "")),
			"node_type": node_type,
			"outcome": str(battle_result.get("outcome", "invalid")),
			"turns": int(battle_result.get("turns", 0)),
			"hp": int(player_state.hp),
			"sanity": int(player_state.sanity),
			"mp": int(player_state.mp),
			"damage_taken": int(battle_result.get("damage_taken", 0)),
			"sanity_spent": int(battle_result.get("sanity_spent", 0)),
		})
		if str(battle_result.get("outcome", "")) != "victory":
			outcome = str(battle_result.get("outcome", "invalid"))
			failed_encounter_id = str(encounter.get("id", ""))
			break
		battles_won += 1
		if node_type == "boss":
			_restore_mp(player_state, mp_restore_per_node)
			outcome = "victory"
			break
		var enemy_defs := _get_enemy_definitions(encounter, enemy_index)
		var difficulty := _difficulty_calculator.calculate(enemy_defs, run_config.get("difficulty_model", {}))
		var candidates := _reward_selector.pick(
			content.get_entries("rewards"),
			content.indexes.get("spells", {}),
			content.indexes.get("blocks", {}),
			{
				"battles_won": battles_won,
				"reward_tier": int(difficulty.get("reward_tier", 1)),
				"unlocked_reward_ids": selected_reward_ids,
			},
			3,
			rng
		)
		if candidates.is_empty():
			_restore_mp(player_state, mp_restore_per_node)
			continue
		# 自動測試採中性的固定政策：選擇候選列表第一項，不推定玩家流派偏好。
		var reward: Dictionary = candidates[0]
		var reward_id := str(reward.get("id", ""))
		selected_reward_ids.append(reward_id)
		rewards_taken += 1
		if str(reward.get("type", "")) == "block":
			if _board_simulator.add_session_block(board_session, content.get_block(reward_id)):
				special_blocks += 1
		else:
			if _board_simulator.add_session_spell(board_session, content.get_spell(reward_id)):
				spell_ids.append(reward_id)
				spells_taken += 1
		_restore_mp(player_state, mp_restore_per_node)
	return {
		"seed": seed,
		"outcome": outcome,
		"failed_encounter_id": failed_encounter_id,
		"route_nodes": route.size(),
		"battles_won": battles_won,
		"battles_reached": battle_curve.size(),
		"rests": rests,
		"rewards_taken": rewards_taken,
		"spells_taken": spells_taken,
		"special_blocks": special_blocks,
		"hp_end": int(player_state.get("hp", 0)),
		"sanity_end": int(player_state.get("sanity", 0)),
		"mp_end": int(player_state.get("mp", 0)),
		"board_placements": int(board_session.get("placements", 0)),
		"dead_boards": int(board_session.get("dead_boards", 0)),
		"battle_curve": battle_curve,
	}


func _pick_route(map_data: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var index := {}
	for node in map_data.get("nodes", []):
		index[str(node.get("id", ""))] = node
	var starts: Array = map_data.get("start_node_ids", [])
	if starts.is_empty():
		return []
	var current_id := str(starts[rng.randi_range(0, starts.size() - 1)])
	var boss_id := str(map_data.get("boss_node_id", ""))
	var route: Array[Dictionary] = []
	var guard := index.size() + 1
	while index.has(current_id) and guard > 0:
		guard -= 1
		var node: Dictionary = index[current_id]
		route.append(node)
		if current_id == boss_id:
			break
		var next_ids: Array = node.get("next_ids", [])
		if next_ids.is_empty():
			break
		current_id = str(next_ids[rng.randi_range(0, next_ids.size() - 1)])
	return route


func _get_enemy_definitions(encounter: Dictionary, enemy_index: Dictionary) -> Array:
	var result: Array = []
	for enemy_id in encounter.get("enemy_ids", []):
		var definition: Dictionary = enemy_index.get(str(enemy_id), {})
		if not definition.is_empty():
			result.append(definition)
	return result


func _restore_mp(player_state: Dictionary, amount: int) -> void:
	player_state.mp = mini(int(player_state.get("mp", 0)) + amount, int(player_state.get("max_mp", 100)))


func _apply_first_affordable_choice(content: ContentRegistry, node: Dictionary, player_state: Dictionary) -> bool:
	var node_type := str(node.get("type", ""))
	var definition_kind: String = {"event": "events", "shop": "shops", "rest": "rests"}.get(node_type, "")
	var definition := content.get_definition(definition_kind, str(node.get("content_id", "")))
	if definition.is_empty():
		return false
	for preview in _choice_resolver.preview_choices(definition, player_state):
		if not bool(preview.get("valid", false)) or not bool(preview.get("affordable", false)):
			continue
		for key in preview.get("changes", {}):
			player_state[key] = int(preview.changes[key])
		return true
	return false


func _summarize(results: Array[Dictionary], seed: int, max_turns: int) -> Dictionary:
	var totals := {
		"victories": 0,
		"hp_defeats": 0,
		"sanity_defeats": 0,
		"timeouts": 0,
		"invalid": 0,
		"battles_won": 0,
		"battles_reached": 0,
		"rests": 0,
		"rewards_taken": 0,
		"spells_taken": 0,
		"special_blocks": 0,
		"hp_end": 0,
		"sanity_end": 0,
		"mp_end": 0,
		"board_placements": 0,
		"dead_boards": 0,
	}
	var maximum_battles := 0
	for result in results:
		maximum_battles = maxi(maximum_battles, result.get("battle_curve", []).size())
		match str(result.get("outcome", "invalid")):
			"victory": totals.victories = int(totals.victories) + 1
			"hp_defeat": totals.hp_defeats = int(totals.hp_defeats) + 1
			"sanity_defeat": totals.sanity_defeats = int(totals.sanity_defeats) + 1
			"timeout": totals.timeouts = int(totals.timeouts) + 1
			_: totals.invalid = int(totals.invalid) + 1
		for key in ["battles_won", "battles_reached", "rests", "rewards_taken", "spells_taken", "special_blocks", "hp_end", "sanity_end", "mp_end", "board_placements", "dead_boards"]:
			totals[key] = int(totals[key]) + int(result.get(key, 0))
	var pressure_curve: Array[Dictionary] = []
	for battle_index in range(maximum_battles):
		var reached := 0
		var wins := 0
		var hp_total := 0
		var sanity_total := 0
		var mp_total := 0
		var turns_total := 0
		for result in results:
			var curve: Array = result.get("battle_curve", [])
			if battle_index >= curve.size():
				continue
			var battle: Dictionary = curve[battle_index]
			reached += 1
			wins += 1 if str(battle.get("outcome", "")) == "victory" else 0
			hp_total += int(battle.get("hp", 0))
			sanity_total += int(battle.get("sanity", 0))
			mp_total += int(battle.get("mp", 0))
			turns_total += int(battle.get("turns", 0))
		pressure_curve.append({
			"battle": battle_index + 1,
			"reached_rate": _ratio(reached, results.size()),
			"win_rate_when_reached": _ratio(wins, reached),
			"average_hp_after": float(hp_total) / float(maxi(reached, 1)),
			"average_sanity_after": float(sanity_total) / float(maxi(reached, 1)),
			"average_mp_after": float(mp_total) / float(maxi(reached, 1)),
			"average_turns": float(turns_total) / float(maxi(reached, 1)),
		})
	var count := maxi(results.size(), 1)
	return {
		"seed": seed,
		"runs": results.size(),
		"max_turns_per_battle": max_turns,
		"policy": "隨機合法路線；獎勵與非戰鬥節點取第一個可用選項；咒文直接加入抽取池；每完成節點回復固定 MP",
		"victory_rate": _ratio(int(totals.victories), count),
		"hp_defeats": int(totals.hp_defeats),
		"sanity_defeats": int(totals.sanity_defeats),
		"timeouts": int(totals.timeouts),
		"invalid_runs": int(totals.invalid),
		"average_battles_won": float(totals.battles_won) / float(count),
		"average_battles_reached": float(totals.battles_reached) / float(count),
		"average_rests": float(totals.rests) / float(count),
		"average_rewards": float(totals.rewards_taken) / float(count),
		"average_spells_taken": float(totals.spells_taken) / float(count),
		"average_special_blocks": float(totals.special_blocks) / float(count),
		"average_hp_end": float(totals.hp_end) / float(count),
		"average_sanity_end": float(totals.sanity_end) / float(count),
		"average_mp_end": float(totals.mp_end) / float(count),
		"average_board_placements": float(totals.board_placements) / float(count),
		"average_dead_boards": float(totals.dead_boards) / float(count),
		"pressure_curve": pressure_curve,
		"runs_detail": results,
	}


func _ratio(numerator: int, denominator: int) -> float:
	return 0.0 if denominator <= 0 else float(numerator) / float(denominator)
