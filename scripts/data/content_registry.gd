class_name ContentRegistry
extends RefCounted

const SlatePairingRulesScript = preload("res://scripts/growth/slate_pairing_rules.gd")

const SCHEMA_VERSION := 1
const DATA_PATHS := {
	"blocks": "res://data/blocks.json",
	"spells": "res://data/spells.json",
	"spell_categories": "res://data/spell_categories.json",
	"enemies": "res://data/enemies.json",
	"intents": "res://data/intents.json",
	"encounters": "res://data/encounters.json",
	"rewards": "res://data/rewards.json",
	"events": "res://data/events.json",
	"shops": "res://data/shops.json",
	"rests": "res://data/rests.json",
	"player": "res://data/player.json",
	"run_config": "res://data/run_config.json",
	"map": "res://data/map.json",
	"sanity": "res://data/sanity.json",
	"meta_progression": "res://data/meta_progression.json",
	"ui_theme": "res://data/ui_theme.json",
}
const ITEM_LOGICS := ["attack", "conditional_attack", "support", "status"]
const RARITIES := ["common", "uncommon", "rare"]
const RARITY_RANK := {"common": 1, "uncommon": 2, "rare": 3}
const SCOPES := ["single", "spread", "all", "self"]
const SPELL_CATEGORIES := ["single_attack", "spread_attack", "all_attack", "defense", "empower", "poison", "weaken"]
const STATUSES := ["strength", "weak", "hard", "fragile", "regen", "poison"]
const INTENTS := ["attack", "heavy_attack", "guard", "sanity_attack", "debuff_player", "buff_self", "watch", "brace"]
const INTENT_ACTIONS := ["damage", "armor", "sanity_damage", "status_player", "status_self", "idle"]

var errors: Array[String] = []
var documents: Dictionary = {}
var definitions: Dictionary = {}
var indexes: Dictionary = {}
var block_resources: Dictionary = {}
var spell_resources: Dictionary = {}


func load_all() -> bool:
	errors.clear()
	documents.clear()
	definitions.clear()
	indexes.clear()
	block_resources.clear()
	spell_resources.clear()
	for kind in DATA_PATHS:
		var document = _load_document(str(DATA_PATHS[kind]))
		if document != null:
			documents[kind] = document
	if not errors.is_empty():
		return false
	for kind in ["blocks", "spells", "spell_categories", "enemies", "intents", "encounters", "rewards", "events", "shops", "rests"]:
		var entries = documents[kind].get("entries", [])
		if not entries is Array:
			errors.append("%s.entries 必須是陣列" % kind)
			continue
		definitions[kind] = entries
		indexes[kind] = _build_id_index(kind, entries)
	if not errors.is_empty():
		return false
	_validate_references()
	_validate_values()
	if not errors.is_empty():
		return false
	block_resources = _build_block_resources(definitions.get("blocks", []))
	spell_resources = _build_spell_resources(definitions.get("spells", []))
	return errors.is_empty()


func get_entries(kind: String) -> Array:
	return definitions.get(kind, []).duplicate(true)


func get_definition(kind: String, id: String) -> Dictionary:
	var value = indexes.get(kind, {}).get(id, {})
	return value.duplicate(true) if value is Dictionary else {}


func get_document(kind: String) -> Dictionary:
	var value = documents.get(kind, {})
	return value.duplicate(true) if value is Dictionary else {}


func get_block(id: String) -> BlockData:
	return block_resources.get(id) as BlockData


func get_spell(id: String) -> BattleItem:
	return spell_resources.get(id) as BattleItem


func get_blocks(ids: Array) -> Array[BlockData]:
	var result: Array[BlockData] = []
	for id in ids:
		var block = get_block(str(id))
		if block != null:
			result.append(block)
	return result


func get_spells(ids: Array) -> Array[BattleItem]:
	var result: Array[BattleItem] = []
	for id in ids:
		var item = get_spell(str(id))
		if item != null:
			result.append(item)
	return result


func create_slate(state: Dictionary) -> BlockData:
	var base := get_block(str(state.get("shape_id", "")))
	var spell := get_spell(str(state.get("spell_id", "")))
	var effect_cell = state.get("effect_cell", [0, 0])
	if base == null or spell == null or not effect_cell is Array or effect_cell.size() != 2:
		return null
	var marked := Vector2i(int(effect_cell[0]), int(effect_cell[1]))
	if marked not in base.cells:
		return null
	return base.as_slate(str(state.get("slate_uid", "")), spell, marked)


func create_slates(states: Array) -> Array[BlockData]:
	var result: Array[BlockData] = []
	for state in states:
		if state is Dictionary:
			var slate := create_slate(state)
			if slate != null:
				result.append(slate)
	return result


func validate_run_state_references(state: RunState) -> Array[String]:
	var result: Array[String] = []
	if state == null:
		result.append("RunState 不可為 null")
		return result
	var slate_uids := {}
	var special_shapes := {}
	for slate in state.slate_pool:
		_validate_slate_reference(slate, "RunState.slate_pool", result)
		var uid := str(slate.get("slate_uid", ""))
		if uid.is_empty() or slate_uids.has(uid):
			result.append("RunState.slate_pool slate_uid 為空或重複：%s" % uid)
		slate_uids[uid] = true
		var shape_id := str(slate.get("shape_id", ""))
		if bool(get_definition("blocks", shape_id).get("special", false)):
			if special_shapes.has(shape_id):
				result.append("RunState.slate_pool 特殊形狀不可重複：%s" % shape_id)
			special_shapes[shape_id] = true
	for slate in state.pending_slate_rewards:
		_validate_slate_reference(slate, "RunState.pending_slate_rewards", result)
	for hand_entry in state.hand_state:
		if not hand_entry is Dictionary:
			result.append("RunState.hand_state 含有非物件資料")
			continue
		var uid := str(hand_entry.get("slate_uid", ""))
		if not slate_uids.has(uid):
			result.append("RunState.hand_state 引用不存在的 slate_uid：%s" % uid)
		var rotation := int(hand_entry.get("rotation_steps", -1))
		if rotation < 0 or rotation > 3:
			result.append("RunState.hand_state rotation_steps 必須介於 0–3")
	for spell_id in state.board_spell_ids:
		if not spell_id.is_empty() and not indexes.get("spells", {}).has(spell_id):
			result.append("RunState.board_spell_ids 引用不存在的 spell：%s" % spell_id)
	if not state.board_spell_ids.is_empty() and state.board_spell_ids.size() != 64:
		result.append("RunState.board_spell_ids 必須為空或剛好有 64 格")
	if state.board_cells.size() == 64 and state.board_spell_ids.size() == 64:
		for index in range(64):
			if not state.board_spell_ids[index].is_empty() and state.board_cells[index].is_empty():
				result.append("RunState.board_spell_ids 不可附著於空白盤面格 %d" % index)
	var sanity_effect_ids := {}
	for effect in documents.get("sanity", {}).get("effects", []):
		sanity_effect_ids[str(effect.get("id", ""))] = true
	for effect_id in state.sanity_effect_ids:
		if not sanity_effect_ids.has(effect_id):
			result.append("RunState.sanity_effect_ids 引用不存在的 effect：%s" % effect_id)
	if not state.board_cells.is_empty() and state.board_cells.size() != 64:
		result.append("RunState.board_cells 必須為空或剛好有 64 格")
	_validate_saved_map_references(state, result)
	return result


func _validate_slate_reference(slate: Dictionary, source: String, result: Array[String]) -> void:
	var shape_id := str(slate.get("shape_id", ""))
	var spell_id := str(slate.get("spell_id", ""))
	if not indexes.get("blocks", {}).has(shape_id):
		result.append("%s 引用不存在的 shape：%s" % [source, shape_id])
	if not indexes.get("spells", {}).has(spell_id):
		result.append("%s 引用不存在的 spell：%s" % [source, spell_id])
	var effect_cell = slate.get("effect_cell", [])
	var block := get_block(shape_id)
	if not effect_cell is Array or effect_cell.size() != 2:
		result.append("%s effect_cell 必須是兩個整數" % source)
	elif block != null and Vector2i(int(effect_cell[0]), int(effect_cell[1])) not in block.cells:
		result.append("%s effect_cell 不在形狀內：%s" % [source, shape_id])


func validate_meta_state_references(state: MetaState) -> Array[String]:
	var result: Array[String] = []
	if state == null:
		return ["MetaState 不可為 null"]
	var player_profession := str(documents.get("player", {}).get("profession_id", ""))
	for profession_id in state.unlocked_profession_ids:
		if profession_id != player_profession:
			result.append("MetaState 引用不存在的 profession：%s" % profession_id)
	_append_unknown_ids(result, "blocks", "MetaState.unlocked_block_ids", state.unlocked_block_ids)
	_append_unknown_ids(result, "spells", "MetaState.unlocked_spell_ids", state.unlocked_spell_ids)
	return result


func _append_unknown_ids(result: Array[String], kind: String, source: String, ids: Array) -> void:
	for id in ids:
		if not indexes.get(kind, {}).has(str(id)):
			result.append("%s 引用不存在的 %s：%s" % [source, kind, id])


func _validate_saved_map_references(state: RunState, result: Array[String]) -> void:
	if state.map_data.is_empty():
		if not state.current_node_id.is_empty() or not state.completed_node_ids.is_empty() or not state.available_node_ids.is_empty():
			result.append("RunState 有節點進度但缺少 map_data")
		return
	var node_index := {}
	var nodes = state.map_data.get("nodes", [])
	if not nodes is Array or nodes.is_empty():
		result.append("RunState.map_data.nodes 必須是非空陣列")
		return
	var content_pools: Dictionary = documents.get("map", {}).get("content_pools", {})
	var node_pool_names := {
		"event": "event",
		"shop": "shop",
		"rest": "rest",
	}
	var node_definition_kinds := {
		"event": "events",
		"shop": "shops",
		"rest": "rests",
	}
	for node in nodes:
		if not node is Dictionary:
			result.append("RunState.map_data.nodes 含有非物件資料")
			continue
		var node_id := str(node.get("id", ""))
		if node_id.is_empty() or node_index.has(node_id):
			result.append("RunState.map_data node id 為空或重複：%s" % node_id)
		else:
			node_index[node_id] = node
		var node_type := str(node.get("type", ""))
		var content_id := str(node.get("content_id", ""))
		if node_type in ["normal_battle", "elite", "boss"]:
			if not indexes.get("encounters", {}).has(content_id):
				result.append("RunState.map_data node %s 引用不存在的 encounter：%s" % [node_id, content_id])
		elif node_definition_kinds.has(node_type):
			var definition_kind := str(node_definition_kinds[node_type])
			if not indexes.get(definition_kind, {}).has(content_id):
				result.append("RunState.map_data node %s 引用不存在的 %s：%s" % [node_id, node_type, content_id])
		elif node_pool_names.has(node_type):
			var pool = content_pools.get(node_pool_names[node_type], [])
			if not pool is Array or content_id not in pool:
				result.append("RunState.map_data node %s 引用不存在的 %s 內容：%s" % [node_id, node_type, content_id])
		else:
			result.append("RunState.map_data node %s type 不合法：%s" % [node_id, node_type])
	for node in nodes:
		if not node is Dictionary:
			continue
		for next_id in node.get("next_ids", []):
			if not node_index.has(str(next_id)):
				result.append("RunState.map_data node %s 指向不存在節點：%s" % [node.get("id", ""), next_id])
	var progress_ids: Array = state.completed_node_ids.duplicate()
	progress_ids.append_array(state.available_node_ids)
	if not state.current_node_id.is_empty():
		progress_ids.append(state.current_node_id)
	for node_id in progress_ids:
		if not node_index.has(str(node_id)):
			result.append("RunState 節點進度引用不存在節點：%s" % node_id)
	var boss_id := str(state.map_data.get("boss_node_id", ""))
	if not node_index.has(boss_id) or str(node_index.get(boss_id, {}).get("type", "")) != "boss":
		result.append("RunState.map_data.boss_node_id 必須引用 boss 節點")
	for start_id in state.map_data.get("start_node_ids", []):
		if not node_index.has(str(start_id)):
			result.append("RunState.map_data.start_node_ids 引用不存在節點：%s" % start_id)


func _load_document(path: String):
	if not FileAccess.file_exists(path):
		errors.append("找不到資料檔：%s" % path)
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("無法開啟資料檔：%s" % path)
		return null
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		errors.append("JSON 解析失敗：%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		errors.append("資料根節點必須是物件：%s" % path)
		return null
	var document: Dictionary = json.data
	var version = document.get("schema_version")
	if not version is float and not version is int:
		errors.append("缺少整數 schema_version：%s" % path)
	elif int(version) != SCHEMA_VERSION:
		errors.append("不支援 schema_version %s：%s（目前支援 %d）" % [version, path, SCHEMA_VERSION])
	return document


func _build_id_index(kind: String, entries: Array) -> Dictionary:
	var index := {}
	for entry in entries:
		if not entry is Dictionary:
			errors.append("%s.entries 含有非物件資料" % kind)
			continue
		var id := str(entry.get("id", ""))
		if id.is_empty():
			errors.append("%s 有空 id" % kind)
		elif index.has(id):
			errors.append("%s id 重複：%s" % [kind, id])
		else:
			index[id] = entry
	return index


func _validate_references() -> void:
	var run_config: Dictionary = documents.get("run_config", {})
	for id in run_config.get("block_pool", []):
		_require_id("blocks", str(id), "run_config.block_pool")
	for id in run_config.get("spell_pool", []):
		_require_id("spells", str(id), "run_config.spell_pool")
	for slate in run_config.get("starter_slates", []):
		if slate is Dictionary:
			_require_id("blocks", str(slate.get("shape_id", "")), "run_config.starter_slates")
			_require_id("spells", str(slate.get("spell_id", "")), "run_config.starter_slates")
	for spell in definitions.get("spells", []):
		_require_id("spell_categories", str(spell.get("category_id", "")), "spell %s.category_id" % spell.get("id", ""))
	for encounter in definitions.get("encounters", []):
		for enemy_id in encounter.get("enemy_ids", []):
			_require_id("enemies", str(enemy_id), "encounter %s" % encounter.get("id", ""))
	for enemy in definitions.get("enemies", []):
		for intent_id in enemy.get("intent_pattern", []):
			_require_id("intents", str(intent_id), "enemy %s.intent_pattern" % enemy.get("id", ""))
		for rule in enemy.get("intent_rules", []):
			if rule is Dictionary:
				for intent_id in rule.get("pattern", []):
					_require_id("intents", str(intent_id), "enemy %s.intent_rules" % enemy.get("id", ""))
	for reward in definitions.get("rewards", []):
		var reward_type := str(reward.get("type", ""))
		if reward_type == "spell":
			_require_id("spells", str(reward.get("id", "")), "reward")
		elif reward_type == "block":
			_require_id("blocks", str(reward.get("id", "")), "reward")
		else:
			errors.append("reward type 不合法：%s" % reward_type)
	var map_document: Dictionary = documents.get("map", {})
	for node in map_document.get("nodes", []):
		var node_type := str(node.get("type", ""))
		if node_type in ["normal_battle", "elite", "boss"]:
			_require_id("encounters", str(node.get("content_id", "")), "map node %s" % node.get("id", ""))
		elif node_type in ["event", "shop", "rest"]:
			var definition_kind: String = str({"event": "events", "shop": "shops", "rest": "rests"}[node_type])
			_require_id(definition_kind, str(node.get("content_id", "")), "map node %s" % node.get("id", ""))
	var content_pools: Dictionary = map_document.get("content_pools", {})
	for pool_name in ["normal_encounters", "elite_encounters", "boss_encounters"]:
		for encounter_id in content_pools.get(pool_name, []):
			_require_id("encounters", str(encounter_id), "map.content_pools.%s" % pool_name)
	for event_id in content_pools.get("event", []):
		_require_id("events", str(event_id), "map.content_pools.event")
	for shop_id in content_pools.get("shop", []):
		_require_id("shops", str(shop_id), "map.content_pools.shop")
	for rest_id in content_pools.get("rest", []):
		_require_id("rests", str(rest_id), "map.content_pools.rest")
	for kind in ["events", "shops", "rests"]:
		for definition in definitions.get(kind, []):
			for option in definition.get("options", []):
				if not option is Dictionary:
					continue
				var grant = option.get("grant", {})
				if not grant is Dictionary or grant.is_empty():
					continue
				var grant_type := str(grant.get("type", ""))
				if grant_type == "slate":
					var shape_id := str(grant.get("shape_id", ""))
					_require_id("spells", str(grant.get("spell_id", "")), "%s option slate grant" % kind)
					_require_id("blocks", shape_id, "%s option slate grant" % kind)
					if str(grant.get("slate_uid", "")).is_empty():
						errors.append("%s option slate grant 缺少 slate_uid" % kind)
					var effect_cell = grant.get("effect_cell", [])
					var shape := get_definition("blocks", shape_id)
					if not effect_cell is Array or effect_cell.size() != 2 or not shape.is_empty() and effect_cell not in shape.get("cells", []):
						errors.append("%s option slate grant effect_cell 不在形狀內" % kind)
				else:
					errors.append("%s option grant type 不合法：%s" % [kind, grant_type])
	var meta_config: Dictionary = documents.get("meta_progression", {})
	for block_id in meta_config.get("initial_unlocked_block_ids", []):
		_require_id("blocks", str(block_id), "meta_progression.initial_unlocked_block_ids")
	for spell_id in meta_config.get("initial_unlocked_spell_ids", []):
		_require_id("spells", str(spell_id), "meta_progression.initial_unlocked_spell_ids")


func _require_id(kind: String, id: String, source: String) -> void:
	if not indexes.get(kind, {}).has(id):
		errors.append("%s 引用不存在的 %s：%s" % [source, kind, id])


func _validate_values() -> void:
	_validate_ui_theme()
	for block in definitions.get("blocks", []):
		var id := str(block.get("id", ""))
		var cells = block.get("cells")
		if not cells is Array or cells.is_empty():
			errors.append("block %s cells 必須是非空陣列" % id)
		elif not _are_coordinate_pairs(cells):
			errors.append("block %s cells 必須是兩個整數的座標" % id)
		if float(block.get("weight", 0.0)) <= 0.0:
			errors.append("block %s weight 必須大於 0" % id)
		if int(block.get("tier", 0)) <= 0:
			errors.append("block %s tier 必須是正整數" % id)
		if int(block.get("complexity", 0)) < 1 or int(block.get("complexity", 0)) > 4:
			errors.append("block %s complexity 必須介於 1–4" % id)
	for category in definitions.get("spell_categories", []):
		var category_id := str(category.get("id", ""))
		if category_id not in SPELL_CATEGORIES:
			errors.append("spell category id 不合法：%s" % category_id)
		if str(category.get("name", "")).is_empty() or str(category.get("glyph", "")).is_empty():
			errors.append("spell category %s 缺少 name / glyph" % category_id)
		if not Color.html_is_valid(str(category.get("color", ""))):
			errors.append("spell category %s color 不合法" % category_id)
	for spell in definitions.get("spells", []):
		var id := str(spell.get("id", ""))
		_validate_allowed(spell, "logic", ITEM_LOGICS, "spell %s" % id)
		_validate_allowed(spell, "rarity", RARITIES, "spell %s" % id)
		_validate_allowed(spell, "effect_scope", SCOPES, "spell %s" % id)
		_validate_allowed(spell, "category_id", SPELL_CATEGORIES, "spell %s" % id)
		if str(spell.get("icon_text", "")).is_empty() or str(spell.get("icon_text", "")).length() > 2:
			errors.append("spell %s icon_text 必須是 1–2 個可見字元" % id)
		if int(spell.get("mp_cost", -1)) < 0 or int(spell.get("balance_cost", -1)) < 0:
			errors.append("spell %s 的 mp_cost / balance_cost 不可為負數" % id)
		if int(spell.get("tier", 0)) <= 0:
			errors.append("spell %s tier 必須是正整數" % id)
		var upgrade_from := str(spell.get("upgrade_from", ""))
		var upgrade_to := str(spell.get("upgrade_to", ""))
		if not upgrade_from.is_empty():
			_require_id("spells", upgrade_from, "spell %s.upgrade_from" % id)
		if not upgrade_to.is_empty():
			_require_id("spells", upgrade_to, "spell %s.upgrade_to" % id)
			if int(spell.get("combine_count", 0)) <= 1:
				errors.append("spell %s 有 upgrade_to 時 combine_count 必須大於 1" % id)
		for field in ["status_effects_self", "status_effects_target"]:
			_validate_status_effects(spell, field)
		for field in ["allowed_shape_ids", "blocked_shape_ids"]:
			var overrides = spell.get(field, [])
			if not overrides is Array:
				errors.append("spell %s.%s 必須是陣列" % [id, field])
				continue
			for shape_id in overrides:
				_require_id("blocks", str(shape_id), "spell %s.%s" % [id, field])
	_validate_spell_upgrade_chains()
	for enemy in definitions.get("enemies", []):
		var id := str(enemy.get("id", ""))
		var art_path := str(enemy.get("art_path", ""))
		if art_path.is_empty() or not ResourceLoader.exists(art_path):
			errors.append("enemy %s.art_path 引用不存在：%s" % [id, art_path])
		if int(enemy.get("hp", 0)) <= 0 or int(enemy.get("attack", -1)) < 0 or int(enemy.get("tier", 0)) <= 0 or int(enemy.get("speed", 0)) <= 0:
			errors.append("enemy %s 的 hp / attack / tier / speed 超出值域" % id)
		var pattern = enemy.get("intent_pattern")
		if not pattern is Array or pattern.is_empty():
			errors.append("enemy %s intent_pattern 必須是非空陣列" % id)
		else:
			for intent in pattern:
				if str(intent) not in INTENTS:
					errors.append("enemy %s 使用未知 intent：%s" % [id, intent])
		var rule_ids := {}
		for rule in enemy.get("intent_rules", []):
			if not rule is Dictionary or str(rule.get("id", "")).is_empty() or rule_ids.has(str(rule.get("id", ""))):
				errors.append("enemy %s intent_rules 必須包含唯一非空 id" % id)
				continue
			rule_ids[str(rule.get("id", ""))] = true
			var has_condition: bool = rule.has("turn_gte") or rule.has("hp_ratio_lte")
			if not has_condition or (rule.has("turn_gte") and int(rule.get("turn_gte", 0)) <= 0) or (rule.has("hp_ratio_lte") and (float(rule.get("hp_ratio_lte", 0.0)) <= 0.0 or float(rule.get("hp_ratio_lte", 0.0)) > 1.0)):
				errors.append("enemy %s intent rule %s 條件不合法" % [id, rule.get("id", "")])
			var rule_pattern = rule.get("pattern", [])
			if not rule_pattern is Array or rule_pattern.is_empty():
				errors.append("enemy %s intent rule %s pattern 必須是非空陣列" % [id, rule.get("id", "")])
	for intent in definitions.get("intents", []):
		var id := str(intent.get("id", ""))
		var action := str(intent.get("action", ""))
		if action not in INTENT_ACTIONS:
			errors.append("intent %s action 不合法：%s" % [id, action])
		if str(intent.get("display_name", "")).is_empty():
			errors.append("intent %s 缺少 display_name" % id)
		if action in ["armor", "sanity_damage", "status_player", "status_self"] and int(intent.get("amount", 0)) <= 0:
			errors.append("intent %s amount 必須是正整數" % id)
		if action in ["status_player", "status_self"] and str(intent.get("status_id", "")) not in STATUSES:
			errors.append("intent %s 使用未知 status_id" % id)
	for encounter in definitions.get("encounters", []):
		var enemy_ids = encounter.get("enemy_ids")
		if not enemy_ids is Array or enemy_ids.is_empty():
			errors.append("encounter %s enemy_ids 必須是非空陣列" % encounter.get("id", ""))
		elif enemy_ids.size() > 5:
			errors.append("encounter %s 超過 5 名敵人上限" % encounter.get("id", ""))
	for reward in definitions.get("rewards", []):
		if float(reward.get("weight", 0.0)) <= 0.0:
			errors.append("reward %s weight 必須大於 0" % reward.get("id", ""))
		if int(reward.get("min_reward_tier", 1)) <= 0:
			errors.append("reward %s min_reward_tier 必須是正整數" % reward.get("id", ""))
		if str(reward.get("type", "")) not in ["spell", "block"]:
			errors.append("reward %s type 必須為 spell 或 block" % reward.get("id", ""))
	_validate_reward_pool()
	_validate_choice_definitions()
	var player: Dictionary = documents.get("player", {})
	var player_art_path := str(player.get("art_path", ""))
	if player_art_path.is_empty() or not ResourceLoader.exists(player_art_path):
		errors.append("player.art_path 引用不存在：%s" % player_art_path)
	if str(player.get("profession_id", "")).is_empty():
		errors.append("player.profession_id 必須是非空字串")
	if str(player.get("name", "")).is_empty() or int(player.get("max_hp", 0)) <= 0 or int(player.get("action_points", 0)) <= 0:
		errors.append("player 的 name / max_hp / action_points 不合法")
	if int(player.get("hp", 0)) <= 0 or int(player.get("hp", 0)) > int(player.get("max_hp", 0)):
		errors.append("player.hp 必須介於 1 與 max_hp")
	if int(player.get("sanity", 0)) <= 0 or int(player.get("sanity", 0)) > int(player.get("max_sanity", 0)):
		errors.append("player.sanity 必須介於 1 與 max_sanity")
	if int(player.get("max_mp", 0)) <= 0 or int(player.get("mp", -1)) < 0 or int(player.get("mp", 0)) > int(player.get("max_mp", 0)):
		errors.append("player.mp 必須介於 0 與 max_mp")
	var config: Dictionary = documents.get("run_config", {})
	var effect_resources = config.get("effect_resources")
	if not effect_resources is Dictionary:
		errors.append("run_config.effect_resources 必須是物件")
	else:
		for logic in ITEM_LOGICS:
			var path := str(effect_resources.get(logic, ""))
			if path.is_empty() or not ResourceLoader.exists(path):
				errors.append("effect_resources.%s 引用不存在：%s" % [logic, path])
				continue
			var prototype := load(path) as BattleItem
			if prototype == null or prototype.logic != logic:
				errors.append("effect_resources.%s 必須是 logic=%s 的 BattleItem" % [logic, logic])
			elif logic == "conditional_attack" and not prototype is EffectConditionalAttack:
				errors.append("effect_resources.conditional_attack 必須使用 EffectConditionalAttack")
	if not config.get("spell_pool", []) is Array or config.get("spell_pool", []).is_empty():
		errors.append("run_config.spell_pool 必須是非空陣列")
	var starter_slates = config.get("starter_slates", [])
	if not starter_slates is Array or starter_slates.is_empty():
		errors.append("run_config.starter_slates 必須是非空陣列")
	else:
		var starter_uids := {}
		var pairing_rules = SlatePairingRulesScript.new()
		for slate in starter_slates:
			if not slate is Dictionary:
				errors.append("run_config.starter_slates 只能包含物件")
				continue
			var uid := str(slate.get("slate_uid", ""))
			if uid.is_empty() or starter_uids.has(uid):
				errors.append("starter slate_uid 為空或重複：%s" % uid)
			starter_uids[uid] = true
			var shape := get_definition("blocks", str(slate.get("shape_id", "")))
			var spell := get_definition("spells", str(slate.get("spell_id", "")))
			if not shape.is_empty() and not spell.is_empty() and not pairing_rules.is_allowed(shape, spell):
				errors.append("starter slate 配對不合法：%s + %s" % [shape.get("id", ""), spell.get("id", "")])
	if int(config.get("mp_restore_per_node", -1)) < 0:
		errors.append("run_config.mp_restore_per_node 不可為負數")
	if str(config.get("runtime_seed_mode", "")) not in RunSeedPolicy.MODES:
		errors.append("run_config.runtime_seed_mode 必須是 random 或 fixed")
	if not config.get("editor_start_fresh") is bool:
		errors.append("run_config.editor_start_fresh 必須是布林值")
	if int(config.get("run_history_limit", 0)) <= 0:
		errors.append("run_config.run_history_limit 必須是正整數")
	var tutorials = config.get("tutorials")
	if not tutorials is Dictionary or str(tutorials.get("battle_time_pressure", "")).is_empty():
		errors.append("run_config.tutorials.battle_time_pressure 必須是非空字串")
	var time_pressure = config.get("difficulty_model", {}).get("time_pressure", {})
	if not time_pressure is Dictionary:
		errors.append("run_config.difficulty_model.time_pressure 必須是物件")
	elif bool(time_pressure.get("enabled", false)):
		for field in ["base_turns", "strength_per_bonus_turn", "depth_penalty_interval", "minimum_turn_limit", "maximum_turn_limit", "sanity_loss_base", "sanity_loss_growth"]:
			if int(time_pressure.get(field, -1)) < 0:
				errors.append("time_pressure.%s 必須是非負整數" % field)
		if int(time_pressure.get("strength_per_bonus_turn", 0)) <= 0 or int(time_pressure.get("depth_penalty_interval", 0)) <= 0:
			errors.append("time_pressure 強度與深度除數必須大於 0")
		if int(time_pressure.get("maximum_turn_limit", 0)) < int(time_pressure.get("minimum_turn_limit", 0)):
			errors.append("time_pressure 最大時限不得小於最小時限")
	for reward in definitions.get("rewards", []):
		if str(reward.get("type", "")) == "block":
			var block := get_definition("blocks", str(reward.get("id", "")))
			if not bool(block.get("special", false)):
				errors.append("方塊獎勵只能引用 special 方塊：%s" % reward.get("id", ""))
	_validate_map_document(documents.get("map", {}))
	_validate_sanity_document(documents.get("sanity", {}))
	_validate_meta_progression(documents.get("meta_progression", {}))


func _validate_meta_progression(config: Dictionary) -> void:
	if int(config.get("initial_shared_currency", -1)) < 0:
		errors.append("meta_progression.initial_shared_currency 必須是非負整數")
	for key in ["initial_unlocked_profession_ids", "initial_unlocked_block_ids", "initial_unlocked_spell_ids"]:
		var values = config.get(key)
		if not values is Array or values.is_empty():
			errors.append("meta_progression.%s 必須是非空陣列" % key)
			continue
		var seen := {}
		for value in values:
			if not value is String or str(value).is_empty() or seen.has(str(value)):
				errors.append("meta_progression.%s 只能包含唯一非空字串" % key)
				break
			seen[str(value)] = true
	var player_profession := str(documents.get("player", {}).get("profession_id", ""))
	if player_profession not in config.get("initial_unlocked_profession_ids", []):
		errors.append("player.profession_id 必須存在於初始 Meta 職業解鎖")


func _validate_choice_definitions() -> void:
	var allowed_resources := ["hp", "sanity", "mp", "currency"]
	for kind in ["events", "shops", "rests"]:
		var label: String = str(kind).trim_suffix("s")
		for definition in definitions.get(kind, []):
			var definition_id := str(definition.get("id", ""))
			if str(definition.get("title", "")).is_empty() or str(definition.get("description", "")).is_empty():
				errors.append("%s %s 的 title / description 不可為空" % [label, definition_id])
			var options = definition.get("options", [])
			if not options is Array or options.size() < 2:
				errors.append("%s %s.options 至少需要兩個選項" % [label, definition_id])
				continue
			var option_ids := {}
			for option in options:
				if not option is Dictionary:
					errors.append("%s %s.options 含有非物件資料" % [label, definition_id])
					continue
				var option_id := str(option.get("id", ""))
				if option_id.is_empty() or option_ids.has(option_id):
					errors.append("%s %s 的 option id 為空或重複：%s" % [label, definition_id, option_id])
				option_ids[option_id] = true
				if str(option.get("label", "")).is_empty() or str(option.get("result_text", "")).is_empty():
					errors.append("%s %s option %s 的 label / result_text 不可為空" % [label, definition_id, option_id])
				var grant = option.get("grant", {})
				if not grant is Dictionary:
					errors.append("%s %s option %s.grant 必須是物件" % [label, definition_id, option_id])
				for field in ["costs", "results"]:
					var resources = option.get(field)
					if not resources is Dictionary:
						errors.append("%s %s option %s.%s 必須是物件" % [label, definition_id, option_id, field])
						continue
					for key in resources:
						if str(key) not in allowed_resources:
							errors.append("%s %s option %s.%s 使用未知資源：%s" % [label, definition_id, option_id, field, key])
						elif not resources[key] is float and not resources[key] is int:
							errors.append("%s %s option %s.%s.%s 必須是整數" % [label, definition_id, option_id, field, key])
						elif int(resources[key]) < 0 or float(resources[key]) != float(int(resources[key])):
							errors.append("%s %s option %s.%s.%s 必須是非負整數" % [label, definition_id, option_id, field, key])


func _validate_spell_upgrade_chains() -> void:
	var edges := {}
	for spell in definitions.get("spells", []):
		var spell_id := str(spell.get("id", ""))
		var upgrade_from := str(spell.get("upgrade_from", ""))
		var upgrade_to := str(spell.get("upgrade_to", ""))
		edges[spell_id] = [upgrade_to] if indexes.get("spells", {}).has(upgrade_to) else []
		if not upgrade_from.is_empty():
			var source: Dictionary = indexes.get("spells", {}).get(upgrade_from, {})
			if not source.is_empty() and str(source.get("upgrade_to", "")) != spell_id:
				errors.append("spell %s.upgrade_from=%s 未被來源的 upgrade_to 對應" % [spell_id, upgrade_from])
		if upgrade_to.is_empty():
			continue
		var target: Dictionary = indexes.get("spells", {}).get(upgrade_to, {})
		if target.is_empty():
			continue
		if str(target.get("upgrade_from", "")) != spell_id:
			errors.append("spell %s.upgrade_to=%s 未被目標的 upgrade_from 對應" % [spell_id, upgrade_to])
		if int(target.get("tier", 0)) <= int(spell.get("tier", 0)):
			errors.append("spell %s 的 tier 必須高於升級來源 %s" % [upgrade_to, spell_id])
		if int(RARITY_RANK.get(str(target.get("rarity", "")), 0)) < int(RARITY_RANK.get(str(spell.get("rarity", "")), 0)):
			errors.append("spell %s 的 rarity 不可低於升級來源 %s" % [upgrade_to, spell_id])
	_validate_acyclic_edges(edges, "咒文升級鏈", errors)


func _validate_reward_pool() -> void:
	var edges := {}
	for reward in definitions.get("rewards", []):
		var reward_id := str(reward.get("id", ""))
		var required_ids = reward.get("requires_rewards", [])
		if not required_ids is Array:
			errors.append("reward %s.requires_rewards 必須是陣列" % reward_id)
			edges[reward_id] = []
			continue
		edges[reward_id] = []
		for required_id in required_ids:
			if not indexes.get("rewards", {}).has(str(required_id)):
				errors.append("reward %s 引用不存在的前置獎勵：%s" % [reward_id, required_id])
			else:
				edges[reward_id].append(str(required_id))
	_validate_acyclic_edges(edges, "獎勵前置關係", errors)
	for reward_tier in range(1, 4):
		var eligible_count := 0
		for reward in definitions.get("rewards", []):
			if int(reward.get("min_reward_tier", 1)) > reward_tier:
				continue
			if str(reward.get("type", "")) == "spell":
				var item: Dictionary = indexes.get("spells", {}).get(str(reward.get("id", "")), {})
				if int(RARITY_RANK.get(str(item.get("rarity", "")), 0)) > reward_tier:
					continue
			elif str(reward.get("type", "")) == "block":
				var block: Dictionary = indexes.get("blocks", {}).get(str(reward.get("id", "")), {})
				if int(block.get("tier", 0)) > reward_tier:
					continue
			eligible_count += 1
		if eligible_count < 3:
			errors.append("reward tier %d 在全解鎖時仍不足三選一：只有 %d 項" % [reward_tier, eligible_count])


func _validate_acyclic_edges(edges: Dictionary, label: String, output: Array[String]) -> void:
	var incoming := {}
	for node_id in edges:
		incoming[str(node_id)] = 0
	for node_id in edges:
		for next_id in edges[node_id]:
			if incoming.has(str(next_id)):
				incoming[str(next_id)] = int(incoming[str(next_id)]) + 1
	var pending: Array[String] = []
	for node_id in incoming:
		if int(incoming[node_id]) == 0:
			pending.append(str(node_id))
	var visited := 0
	while not pending.is_empty():
		var current: String = pending.pop_front()
		visited += 1
		for next_id in edges.get(current, []):
			incoming[str(next_id)] = int(incoming[str(next_id)]) - 1
			if int(incoming[str(next_id)]) == 0:
				pending.append(str(next_id))
	if visited != incoming.size():
		output.append("%s 含有循環" % label)


func _validate_sanity_document(sanity_document: Dictionary) -> void:
	var last_threshold := 101
	var last_count := 0
	for stage in sanity_document.get("stages", []):
		var threshold := int(stage.get("threshold", -1))
		var effect_count := int(stage.get("effect_count", 0))
		if threshold < 0 or threshold >= last_threshold:
			errors.append("sanity stages 必須依 threshold 由高至低排列")
		if effect_count <= last_count:
			errors.append("sanity stages 的 effect_count 必須逐階增加")
		last_threshold = threshold
		last_count = effect_count
	var effect_ids := {}
	for effect in sanity_document.get("effects", []):
		var effect_id := str(effect.get("id", ""))
		if effect_id.is_empty() or effect_ids.has(effect_id):
			errors.append("sanity effect id 為空或重複：%s" % effect_id)
		effect_ids[effect_id] = true
		var path := str(effect.get("behavior_resource", ""))
		var behavior = load(path) if ResourceLoader.exists(path) else null
		if path.is_empty() or behavior == null or not behavior.has_method("apply_to_entity"):
			errors.append("sanity effect %s 的 behavior_resource 不合法" % effect_id)
	if last_count > effect_ids.size():
		errors.append("sanity effects 數量不足以供應最高階段")


func _validate_map_document(map_document: Dictionary) -> void:
	var generation: Dictionary = map_document.get("generation", {})
	if bool(generation.get("enabled", false)):
		if str(generation.get("algorithm", "")) != "layered_dag":
			errors.append("map.generation.algorithm 目前只支援 layered_dag")
		for field in ["floors", "columns", "start_count", "min_nodes_per_floor", "max_nodes_per_floor", "max_links_per_node"]:
			if int(generation.get(field, 0)) <= 0:
				errors.append("map.generation.%s 必須是正整數" % field)
		if int(generation.get("floors", 0)) < 3:
			errors.append("map.generation.floors 至少為 3")
		var columns := int(generation.get("columns", 0))
		var min_nodes := int(generation.get("min_nodes_per_floor", 0))
		var max_nodes := int(generation.get("max_nodes_per_floor", 0))
		var start_count := int(generation.get("start_count", 0))
		if min_nodes < 1 or min_nodes > max_nodes or max_nodes > columns:
			errors.append("map.generation 必須符合 1 <= min_nodes_per_floor <= max_nodes_per_floor <= columns")
		if start_count > columns:
			errors.append("map.generation.start_count 不可大於 columns")
		var type_weights = generation.get("type_weights", {})
		if not type_weights is Dictionary:
			errors.append("map.generation.type_weights 必須是物件")
		else:
			var total_weight := 0.0
			for type in ["normal_battle", "elite", "event", "shop", "rest"]:
				if not type_weights.has(type) or float(type_weights.get(type, -1.0)) < 0.0:
					errors.append("map type weight 不可為負數：%s" % type)
				else:
					total_weight += float(type_weights[type])
			if total_weight <= 0.0:
				errors.append("map.generation.type_weights 總和必須大於 0")
		if bool(generation.get("structured_node_types", false)):
			var floors := int(generation.get("floors", 0))
			var structured_floors := [int(generation.get("event_floor", -1)), int(generation.get("elite_floor", -1)), floors / 2]
			var seen_floors := {}
			for floor in structured_floors:
				if int(floor) < 1 or int(floor) >= floors - 2:
					errors.append("結構化 event／elite／shop 樓層必須位於起點與 Boss 前休息之間")
				if seen_floors.has(int(floor)):
					errors.append("結構化 event／elite／shop 不可使用同一樓層")
				seen_floors[int(floor)] = true
	var nodes = map_document.get("nodes", [])
	if not nodes is Array or nodes.is_empty():
		errors.append("map.nodes 必須是非空陣列")
		return
	var node_index := _build_id_index("map.nodes", nodes)
	var allowed_types := ["normal_battle", "elite", "boss", "event", "shop", "rest"]
	var edges := {}
	var incoming := {}
	for node in nodes:
		var node_id := str(node.get("id", ""))
		edges[node_id] = []
		incoming[node_id] = 0
	for node in nodes:
		var node_id := str(node.get("id", ""))
		if str(node.get("type", "")) not in allowed_types:
			errors.append("map node %s type 不合法" % node_id)
		var next_ids = node.get("next_ids", [])
		if not next_ids is Array:
			errors.append("map node %s.next_ids 必須是陣列" % node_id)
			continue
		var seen_next_ids := {}
		for next_id in next_ids:
			if seen_next_ids.has(str(next_id)):
				errors.append("map node %s.next_ids 含有重複節點：%s" % [node_id, next_id])
			seen_next_ids[str(next_id)] = true
			if not node_index.has(str(next_id)):
				errors.append("map node %s 指向不存在節點：%s" % [node_id, next_id])
			else:
				edges[node_id].append(str(next_id))
				incoming[str(next_id)] = int(incoming.get(str(next_id), 0)) + 1
	_validate_acyclic_edges(edges, "地圖路線", errors)
	var starts = map_document.get("start_node_ids", [])
	if not starts is Array or starts.is_empty():
		errors.append("map.start_node_ids 必須是非空陣列")
	else:
		var seen_starts := {}
		for start_id in starts:
			if seen_starts.has(str(start_id)):
				errors.append("map.start_node_ids 含有重複節點：%s" % start_id)
			seen_starts[str(start_id)] = true
			if not node_index.has(str(start_id)):
				errors.append("map start node 不存在：%s" % start_id)
	var boss_id := str(map_document.get("boss_node_id", ""))
	if not node_index.has(boss_id) or str(node_index.get(boss_id, {}).get("type", "")) != "boss":
		errors.append("map.boss_node_id 必須引用 boss 節點")
	elif not node_index.get(boss_id, {}).get("next_ids", []).is_empty():
		errors.append("map Boss 必須是唯一終點，next_ids 必須為空")
	var boss_count := 0
	for node_id in node_index:
		if str(node_index[node_id].get("type", "")) == "boss":
			boss_count += 1
		if node_id in starts and int(incoming.get(node_id, 0)) > 0:
			errors.append("map start node %s 不可有前置連線" % node_id)
		if node_id not in starts and int(incoming.get(node_id, 0)) == 0:
			errors.append("map node %s 無法從任一前置節點進入" % node_id)
		if node_id != boss_id and node_index[node_id].get("next_ids", []).is_empty():
			errors.append("map node %s 是 Boss 以外的死路" % node_id)
	if boss_count != 1:
		errors.append("map 必須剛好有 1 個 boss 節點，目前為 %d" % boss_count)
	for start_id in starts:
		if not _can_reach_node(str(start_id), boss_id, node_index):
			errors.append("map 起點 %s 無法抵達 Boss %s" % [start_id, boss_id])
	var content_pools = map_document.get("content_pools", {})
	if not content_pools is Dictionary:
		errors.append("map.content_pools 必須是物件")
		return
	var node_pool_names := {
		"normal_battle": "normal_encounters",
		"elite": "elite_encounters",
		"boss": "boss_encounters",
		"event": "event",
		"shop": "shop",
		"rest": "rest",
	}
	for pool_name in ["normal_encounters", "elite_encounters", "boss_encounters", "event", "shop", "rest"]:
		var pool = content_pools.get(pool_name, [])
		if not pool is Array or pool.is_empty():
			errors.append("map.content_pools.%s 必須是非空陣列" % pool_name)
			continue
		var seen := {}
		for content_id in pool:
			if seen.has(str(content_id)):
				errors.append("map.content_pools.%s 含有重複 ID：%s" % [pool_name, content_id])
			seen[str(content_id)] = true
	if bool(generation.get("structured_node_types", false)):
		var normal_sequence = generation.get("normal_encounter_indices", [])
		var normal_pool = content_pools.get("normal_encounters", [])
		var expected_normal_floors := maxi(int(generation.get("floors", 0)) - 5, 0)
		if not normal_sequence is Array or normal_sequence.size() != expected_normal_floors:
			errors.append("map.generation.normal_encounter_indices 必須逐一對應結構化普通戰鬥樓層")
		elif normal_pool is Array:
			for index in normal_sequence:
				if not (index is int or index is float) or int(index) < 0 or int(index) >= normal_pool.size():
					errors.append("map.generation.normal_encounter_indices 含有超出普通遭遇池的索引")
					break
	for node in nodes:
		var pool_name: String = node_pool_names.get(str(node.get("type", "")), "")
		var pool = content_pools.get(pool_name, [])
		if pool is Array and str(node.get("content_id", "")) not in pool:
			errors.append("map node %s 的 content_id 不在 %s 內：%s" % [node.get("id", ""), pool_name, node.get("content_id", "")])


func _can_reach_node(start_id: String, target_id: String, node_index: Dictionary) -> bool:
	var pending: Array[String] = [start_id]
	var visited := {}
	while not pending.is_empty():
		var current: String = pending.pop_front()
		if current == target_id:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for next_id in node_index.get(current, {}).get("next_ids", []):
			pending.append(str(next_id))
	return false


func _validate_allowed(entry: Dictionary, field: String, allowed: Array, source: String) -> void:
	var value := str(entry.get(field, ""))
	if value not in allowed:
		errors.append("%s 的 %s 不合法：%s" % [source, field, value])


func _validate_ui_theme() -> void:
	var document: Dictionary = documents.get("ui_theme", {})
	var palette: Dictionary = document.get("palette", {})
	for key in ["background", "surface", "panel", "panel_hover", "border", "text", "muted", "accent", "danger", "warning", "success", "hp", "sanity", "mp", "focus"]:
		var value := str(palette.get(key, ""))
		if not Color.html_is_valid(value):
			errors.append("ui_theme.palette.%s 必須是有效的 HTML 色碼" % key)
	for group_name in ["typography", "spacing", "shape", "motion"]:
		var group: Dictionary = document.get(group_name, {})
		if group.is_empty():
			errors.append("ui_theme.%s 不可為空" % group_name)
		continue
		for key in group:
			if not group[key] is float and not group[key] is int or float(group[key]) <= 0.0:
				errors.append("ui_theme.%s.%s 必須大於 0" % [group_name, key])


func _validate_status_effects(spell: Dictionary, field: String) -> void:
	var effects = spell.get(field, [])
	if not effects is Array:
		errors.append("spell %s 的 %s 必須是陣列" % [spell.get("id", ""), field])
		return
	for effect in effects:
		if not effect is Dictionary or str(effect.get("id", "")) not in STATUSES or int(effect.get("amount", 0)) <= 0:
			errors.append("spell %s 的 %s 含未知狀態或非正數 amount" % [spell.get("id", ""), field])


func _are_coordinate_pairs(values: Array) -> bool:
	for value in values:
		if not value is Array or value.size() != 2:
			return false
		for component in value:
			if not component is float and not component is int:
				return false
	return true


func _build_block_resources(block_defs: Array) -> Dictionary:
	var resources := {}
	for block_def in block_defs:
		var block_data := BlockData.new()
		block_data.id = str(block_def.get("id", ""))
		block_data.display_name = str(block_def.get("name", block_data.id))
		block_data.color = Color.html(str(block_def.get("color", "#ff8c00")))
		var cells: Array[Vector2i] = []
		for cell in block_def.get("cells", []):
			if cell is Array and cell.size() >= 2:
				cells.append(Vector2i(int(cell[0]), int(cell[1])))
		block_data.cells = cells
		block_data.tier = int(block_def.get("tier", 1))
		block_data.weight = float(block_def.get("weight", 1.0))
		block_data.is_special = bool(block_def.get("special", false))
		block_data.complexity = int(block_def.get("complexity", 1))
		block_data.smart_score_bonus = int(block_def.get("smart_score_bonus", 0))
		var tags: Array[String] = []
		for tag in block_def.get("tags", []):
			tags.append(str(tag))
		block_data.tags = tags
		resources[block_data.id] = block_data
	return resources


func _build_spell_resources(item_defs: Array) -> Dictionary:
	var resources := {}
	for item_def in item_defs:
		var item = _create_spell_resource(item_def)
		if item != null:
			resources[str(item_def.get("id", ""))] = item
	return resources


func _create_spell_resource(item_def: Dictionary) -> BattleItem:
	var logic := str(item_def.get("logic", "attack"))
	var effect_resources: Dictionary = documents.get("run_config", {}).get("effect_resources", {})
	var resource_path := str(effect_resources.get(logic, ""))
	var prototype := load(resource_path) as BattleItem
	if prototype == null:
		errors.append("spell %s 無法載入效果原型：%s" % [item_def.get("id", ""), resource_path])
		return null
	var item := prototype.duplicate(true) as BattleItem
	if item is EffectSupport:
		item.armor_gain = int(item_def.get("armor_gain", 0))
		item.heal_amount = int(item_def.get("heal_amount", 0))
	if item is EffectAttack:
		item.damage = int(item_def.get("damage", 10))
		item.bonus_damage = int(item_def.get("bonus_damage", 0))
		item.hit_count = int(item_def.get("hit_count", 1))
	item.content_id = str(item_def.get("id", ""))
	item.icon_text = str(item_def.get("icon_text", "✦"))
	item.category_id = str(item_def.get("category_id", "single_attack"))
	var category: Dictionary = get_definition("spell_categories", item.category_id)
	item.category_name = str(category.get("name", item.category_id))
	item.category_glyph = str(category.get("glyph", item.icon_text))
	item.category_color = Color.html(str(category.get("color", "#d7c77b")))
	item.spell_name = str(item_def.get("name", "未命名咒文"))
	item.logic = logic
	item.rarity = str(item_def.get("rarity", "common"))
	item.tier = int(item_def.get("tier", 1))
	item.balance_cost = int(item_def.get("balance_cost", 0))
	item.upgrade_from = str(item_def.get("upgrade_from", ""))
	item.upgrade_to = str(item_def.get("upgrade_to", ""))
	item.combine_count = int(item_def.get("combine_count", 0))
	item.mp_cost = int(item_def.get("mp_cost", 0))
	item.effect_scope = str(item_def.get("effect_scope", "single"))
	item.status_effects_self = _parse_status_effects(item_def.get("status_effects_self", []))
	item.status_effects_target = _parse_status_effects(item_def.get("status_effects_target", []))
	item.description = str(item_def.get("description", ""))
	for tag in item_def.get("tags", []):
		item.tags.append(str(tag))
	return item


func _parse_status_effects(raw_effects) -> Array[Dictionary]:
	var parsed: Array[Dictionary] = []
	if raw_effects is Array:
		for effect in raw_effects:
			if effect is Dictionary:
				parsed.append({"id": str(effect.get("id", "")), "amount": int(effect.get("amount", 0))})
	return parsed
