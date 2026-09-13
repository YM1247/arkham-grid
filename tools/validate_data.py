#!/usr/bin/env python3
import json
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"

ITEM_LOGICS = {"attack", "conditional_attack", "support", "status"}
RARITIES = {"common", "uncommon", "rare"}
RARITY_RANK = {"common": 1, "uncommon": 2, "rare": 3}
SCOPES = {"single", "spread", "all", "self"}
STATUSES = {"strength", "weak", "hard", "fragile", "regen", "poison"}
INTENTS = {"attack", "heavy_attack", "guard", "sanity_attack", "debuff_player", "buff_self", "watch", "brace"}
INTENT_ACTIONS = {"damage", "armor", "sanity_damage", "status_player", "status_self", "idle"}
SCHEMA_VERSION = 1
TEMPLATE_FILES = {
    "block.example.json",
    "spell.example.json",
    "intent.example.json",
    "enemy.example.json",
    "encounter.example.json",
    "reward.example.json",
    "event.example.json",
    "shop.example.json",
    "rest.example.json",
}
CHOICE_RESOURCES = {"hp", "sanity", "mp", "currency"}


def load_json(name):
    path = DATA / name
    try:
        with path.open(encoding="utf-8") as file:
            document = json.load(file)
            if not isinstance(document, dict):
                return fail(f"data/{name} 根節點必須是物件")
            if document.get("schema_version") != SCHEMA_VERSION:
                return fail(
                    f"data/{name} schema_version 必須是 {SCHEMA_VERSION}，"
                    f"目前為 {document.get('schema_version')}"
                )
            return document
    except FileNotFoundError:
        return fail(f"找不到資料檔：data/{name}")
    except json.JSONDecodeError as error:
        return fail(f"JSON 解析失敗：data/{name}: {error}")


def fail(message):
    raise ValueError(message)


def validate_templates(errors):
    template_root = DATA / "templates"
    for name in sorted(TEMPLATE_FILES):
        path = template_root / name
        try:
            with path.open(encoding="utf-8") as file:
                document = json.load(file)
        except FileNotFoundError:
            errors.append(f"缺少內容範本：data/templates/{name}")
            continue
        except json.JSONDecodeError as error:
            errors.append(f"內容範本 JSON 解析失敗：data/templates/{name}: {error}")
            continue
        if not isinstance(document, dict) or document.get("schema_version") != SCHEMA_VERSION:
            errors.append(f"內容範本 data/templates/{name} 必須是 schema v{SCHEMA_VERSION} 物件")
        if not isinstance(document.get("entries"), list) or len(document.get("entries", [])) != 1:
            errors.append(f"內容範本 data/templates/{name}.entries 必須剛好有一筆可複製範例")


def collect_ids(items, label, errors):
    ids = [str(item.get("id", "")) for item in items if isinstance(item, dict)]
    for item_id, count in Counter(ids).items():
        if item_id == "":
            errors.append(f"{label} 有空 id")
        elif count > 1:
            errors.append(f"{label} id 重複：{item_id}")
    return set(ids)


def validate_status_effects(spell, field, errors):
    effects = spell.get(field, [])
    if effects is None:
        return
    if not isinstance(effects, list):
        errors.append(f"spell {spell.get('id')} 的 {field} 必須是陣列")
        return
    for effect in effects:
        if not isinstance(effect, dict):
            errors.append(f"spell {spell.get('id')} 的 {field} 內含非物件資料")
            continue
        status_id = effect.get("id")
        amount = effect.get("amount")
        if status_id not in STATUSES:
            errors.append(f"spell {spell.get('id')} 使用未知狀態：{status_id}")
        if not isinstance(amount, int) or amount <= 0:
            errors.append(f"spell {spell.get('id')} 狀態 {status_id} 的 amount 必須是正整數")


def validate_acyclic_edges(edges, label, errors):
    visiting = set()
    visited = set()

    def visit(node_id, path):
        if node_id in visiting:
            cycle_start = path.index(node_id) if node_id in path else 0
            errors.append(f"{label} 含有循環：{' -> '.join(path[cycle_start:] + [node_id])}")
            return
        if node_id in visited:
            return
        visiting.add(node_id)
        path.append(node_id)
        for next_id in edges.get(node_id, []):
            visit(next_id, path)
        path.pop()
        visiting.remove(node_id)
        visited.add(node_id)

    for node_id in edges:
        visit(node_id, [])


def validate_upgrade_chains(spells, spell_by_id, errors):
    edges = {}
    for spell in spells:
        spell_id = spell.get("id")
        upgrade_from = spell.get("upgrade_from") or ""
        upgrade_to = spell.get("upgrade_to") or ""
        edges[spell_id] = [upgrade_to] if upgrade_to in spell_by_id else []

        if upgrade_from:
            source = spell_by_id.get(upgrade_from)
            if source is not None and (source.get("upgrade_to") or "") != spell_id:
                errors.append(
                    f"spell {spell_id}.upgrade_from={upgrade_from} 未被來源的 upgrade_to 對應"
                )
        if not upgrade_to:
            continue
        target = spell_by_id.get(upgrade_to)
        if target is None:
            continue
        if (target.get("upgrade_from") or "") != spell_id:
            errors.append(
                f"spell {spell_id}.upgrade_to={upgrade_to} 未被目標的 upgrade_from 對應"
            )
        if int(target.get("tier", 0)) <= int(spell.get("tier", 0)):
            errors.append(f"spell {upgrade_to} 的 tier 必須高於升級來源 {spell_id}")
        source_rarity = RARITY_RANK.get(spell.get("rarity"), 0)
        target_rarity = RARITY_RANK.get(target.get("rarity"), 0)
        if target_rarity < source_rarity:
            errors.append(f"spell {upgrade_to} 的 rarity 不可低於升級來源 {spell_id}")

    validate_acyclic_edges(edges, "咒文升級鏈", errors)


def validate_reward_dependencies(rewards, reward_ids, errors):
    edges = {}
    for reward in rewards:
        reward_id = reward.get("id")
        required_ids = reward.get("requires_rewards", [])
        if not isinstance(required_ids, list):
            errors.append(f"reward {reward_id}.requires_rewards 必須是陣列")
            edges[reward_id] = []
            continue
        edges[reward_id] = []
        for required_id in required_ids:
            if required_id not in reward_ids:
                errors.append(f"reward {reward_id} 引用不存在的前置獎勵：{required_id}")
            else:
                edges[reward_id].append(required_id)
    validate_acyclic_edges(edges, "獎勵前置關係", errors)


def validate_choice_definitions(definitions, label, errors):
    for definition in definitions:
        definition_id = definition.get("id")
        if not isinstance(definition.get("title"), str) or not definition.get("title"):
            errors.append(f"{label} {definition_id}.title 必須是非空字串")
        if not isinstance(definition.get("description"), str) or not definition.get("description"):
            errors.append(f"{label} {definition_id}.description 必須是非空字串")
        options = definition.get("options")
        if not isinstance(options, list) or len(options) < 2:
            errors.append(f"{label} {definition_id}.options 至少需要兩個選項")
            continue
        collect_ids(options, f"{label} {definition_id}.options", errors)
        for option in options:
            if not isinstance(option, dict):
                errors.append(f"{label} {definition_id}.options 含有非物件資料")
                continue
            option_id = option.get("id")
            if not isinstance(option.get("label"), str) or not option.get("label"):
                errors.append(f"{label} {definition_id} option {option_id}.label 必須是非空字串")
            if not isinstance(option.get("result_text"), str) or not option.get("result_text"):
                errors.append(f"{label} {definition_id} option {option_id}.result_text 必須是非空字串")
            for field in ("costs", "results"):
                resources = option.get(field)
                if not isinstance(resources, dict):
                    errors.append(f"{label} {definition_id} option {option_id}.{field} 必須是物件")
                    continue
                for resource, amount in resources.items():
                    if resource not in CHOICE_RESOURCES:
                        errors.append(f"{label} {definition_id} option {option_id}.{field} 使用未知資源：{resource}")
                    if isinstance(amount, bool) or not isinstance(amount, int) or amount < 0:
                        errors.append(f"{label} {definition_id} option {option_id}.{field}.{resource} 必須是非負整數")


def main():
    errors = []
    warnings = []
    validate_templates(errors)

    blocks = load_json("blocks.json").get("entries")
    items = load_json("spells.json").get("entries")
    enemies = load_json("enemies.json").get("entries")
    intents = load_json("intents.json").get("entries")
    encounters = load_json("encounters.json").get("entries")
    rewards = load_json("rewards.json").get("entries")
    events = load_json("events.json").get("entries")
    shops = load_json("shops.json").get("entries")
    rests = load_json("rests.json").get("entries")
    run_config = load_json("run_config.json")
    player = load_json("player.json")
    map_document = load_json("map.json")
    sanity_document = load_json("sanity.json")
    meta_progression = load_json("meta_progression.json")

    for name, entries in {
        "blocks.json": blocks,
        "spells.json": items,
        "enemies.json": enemies,
        "intents.json": intents,
        "encounters.json": encounters,
        "rewards.json": rewards,
        "events.json": events,
        "shops.json": shops,
        "rests.json": rests,
    }.items():
        if not isinstance(entries, list):
            errors.append(f"{name}.entries 必須是陣列")
    if errors:
        print("DATA VALIDATION FAILED")
        for error in errors:
            print(f"- {error}")
        return 1

    effect_resources = run_config.get("effect_resources")
    if not isinstance(effect_resources, dict):
        errors.append("run_config.effect_resources 必須是物件")
    else:
        for logic in sorted(ITEM_LOGICS):
            resource_path = effect_resources.get(logic)
            if not isinstance(resource_path, str) or not resource_path.startswith("res://"):
                errors.append(f"effect_resources.{logic} 必須是 res:// 路徑")
                continue
            filesystem_path = ROOT / resource_path.removeprefix("res://")
            if not filesystem_path.is_file():
                errors.append(f"effect_resources.{logic} 引用不存在：{resource_path}")

    block_ids = collect_ids(blocks, "blocks.json", errors)
    spell_ids = collect_ids(items, "spells.json", errors)
    enemy_ids = collect_ids(enemies, "enemies.json", errors)
    intent_ids = collect_ids(intents, "intents.json", errors)
    encounter_ids = collect_ids(encounters, "encounters.json", errors)
    reward_ids = collect_ids(rewards, "rewards.json", errors)
    event_ids = collect_ids(events, "events.json", errors)
    shop_ids = collect_ids(shops, "shops.json", errors)
    rest_ids = collect_ids(rests, "rests.json", errors)
    spell_by_id = {spell.get("id"): spell for spell in items}

    validate_choice_definitions(events, "event", errors)
    validate_choice_definitions(shops, "shop", errors)
    validate_choice_definitions(rests, "rest", errors)
    for label, definitions in (("event", events), ("shop", shops), ("rest", rests)):
        for definition in definitions:
            for option in definition.get("options", []):
                grant = option.get("grant", {})
                if not isinstance(grant, dict):
                    errors.append(f"{label} {definition.get('id')} option {option.get('id')}.grant 必須是物件")
                    continue
                if not grant:
                    continue
                grant_type = grant.get("type")
                grant_id = grant.get("id")
                if grant_type == "spell" and grant_id not in spell_ids:
                    errors.append(f"{label} option grant 引用不存在咒文：{grant_id}")
                elif grant_type == "block" and grant_id not in block_ids:
                    errors.append(f"{label} option grant 引用不存在方塊：{grant_id}")
                elif grant_type not in {"spell", "block"}:
                    errors.append(f"{label} option grant type 不合法：{grant_type}")

    if not isinstance(meta_progression.get("initial_shared_currency"), int) or meta_progression.get("initial_shared_currency", -1) < 0:
        errors.append("meta_progression.initial_shared_currency 必須是非負整數")
    meta_lists = {
        "initial_unlocked_profession_ids": None,
        "initial_unlocked_block_ids": block_ids,
        "initial_unlocked_spell_ids": spell_ids,
    }
    for key, valid_ids in meta_lists.items():
        values = meta_progression.get(key)
        if not isinstance(values, list) or not values:
            errors.append(f"meta_progression.{key} 必須是非空陣列")
            continue
        if any(not isinstance(value, str) or not value for value in values) or len(values) != len(set(values)):
            errors.append(f"meta_progression.{key} 只能包含唯一非空字串")
            continue
        if valid_ids is not None:
            for value in values:
                if value not in valid_ids:
                    errors.append(f"meta_progression.{key} 引用不存在內容：{value}")
    profession_ids = meta_progression.get("initial_unlocked_profession_ids", [])
    if player.get("profession_id") not in profession_ids:
        errors.append("player.profession_id 必須存在於初始 Meta 職業解鎖")

    for block_id in run_config.get("block_pool", []):
        if block_id not in block_ids:
            errors.append(f"run_config.block_pool 引用不存在方塊：{block_id}")

    if not isinstance(player.get("name"), str) or not player.get("name"):
        errors.append("player.name 必須是非空字串")
    if not isinstance(player.get("profession_id"), str) or not player.get("profession_id"):
        errors.append("player.profession_id 必須是非空字串")
    for field in ("max_hp", "hp", "max_sanity", "sanity", "max_mp", "mp", "action_points"):
        if not isinstance(player.get(field), int):
            errors.append(f"player.{field} 必須是整數")
    if int(player.get("max_hp", 0)) <= 0 or not 0 < int(player.get("hp", 0)) <= int(player.get("max_hp", 0)):
        errors.append("player.hp 必須介於 1 與 max_hp")
    if int(player.get("max_sanity", 0)) <= 0 or not 0 < int(player.get("sanity", 0)) <= int(player.get("max_sanity", 0)):
        errors.append("player.sanity 必須介於 1 與 max_sanity")
    if int(player.get("max_mp", 0)) <= 0 or not 0 <= int(player.get("mp", -1)) <= int(player.get("max_mp", 0)):
        errors.append("player.mp 必須介於 0 與 max_mp")
    if int(player.get("action_points", 0)) <= 0:
        errors.append("player.action_points 必須大於 0")

    block_by_id = {block.get("id"): block for block in blocks}

    for block in blocks:
        block_id = block.get("id")
        cells = block.get("cells")
        if not isinstance(cells, list) or not cells:
            errors.append(f"block {block_id} cells 必須是非空陣列")
        elif any(not isinstance(cell, list) or len(cell) != 2 or any(not isinstance(value, int) for value in cell) for cell in cells):
            errors.append(f"block {block_id} cells 必須是 [整數, 整數]")
        if not isinstance(block.get("tier"), int) or block.get("tier", 0) <= 0:
            errors.append(f"block {block_id} tier 必須是正整數")
        if not isinstance(block.get("weight"), (int, float)) or block.get("weight", 0) <= 0:
            errors.append(f"block {block_id} weight 必須大於 0")
        if not isinstance(block.get("tags"), list):
            errors.append(f"block {block_id} tags 必須是陣列")

    for spell in items:
        spell_id = spell.get("id")
        logic = spell.get("logic")
        rarity = spell.get("rarity")
        scope = spell.get("effect_scope", "single")
        icon_text = spell.get("icon_text")
        if not isinstance(icon_text, str) or not 1 <= len(icon_text) <= 2:
            errors.append(f"spell {spell_id} icon_text 必須是 1–2 個可見字元")
        if logic not in ITEM_LOGICS:
            errors.append(f"spell {spell_id} 的 logic 不合法：{logic}")
        if rarity not in RARITIES:
            errors.append(f"spell {spell_id} 的 rarity 不合法：{rarity}")
        if not isinstance(spell.get("tier"), int) or spell.get("tier", 0) <= 0:
            errors.append(f"spell {spell_id} 的 tier 必須是正整數")
        if scope not in SCOPES:
            errors.append(f"spell {spell_id} 的 effect_scope 不合法：{scope}")
        if not isinstance(spell.get("tags", []), list):
            errors.append(f"spell {spell_id} 的 tags 必須是陣列")
        if not isinstance(spell.get("balance_cost"), int) or spell.get("balance_cost", -1) < 0:
            errors.append(f"spell {spell_id} 的 balance_cost 必須是非負整數")
        if not isinstance(spell.get("mp_cost"), int) or spell.get("mp_cost", -1) < 0:
            errors.append(f"spell {spell_id} 的 mp_cost 必須是非負整數")
        validate_status_effects(spell, "status_effects_self", errors)
        validate_status_effects(spell, "status_effects_target", errors)

        upgrade_from = spell.get("upgrade_from", "")
        upgrade_to = spell.get("upgrade_to", "")
        if upgrade_from and upgrade_from not in spell_ids:
            errors.append(f"spell {spell_id} upgrade_from 引用不存在咒文：{upgrade_from}")
        if upgrade_to:
            if upgrade_to not in spell_ids:
                errors.append(f"spell {spell_id} upgrade_to 引用不存在咒文：{upgrade_to}")
            if not isinstance(spell.get("combine_count"), int) or spell.get("combine_count", 0) <= 1:
                errors.append(f"spell {spell_id} 有 upgrade_to 時 combine_count 必須大於 1")

    if len(enemy_ids) < 6:
        errors.append(f"敵人少於 6 種：目前 {len(enemy_ids)} 種")

    validate_upgrade_chains(items, spell_by_id, errors)

    for enemy in enemies:
        enemy_id = enemy.get("id")
        if "reward_tier" in enemy:
            errors.append(f"enemy {enemy_id} 不應再使用 reward_tier")
        if int(enemy.get("hp", 0)) <= 0:
            errors.append(f"enemy {enemy_id} hp 必須大於 0")
        if int(enemy.get("attack", 0)) < 0:
            errors.append(f"enemy {enemy_id} attack 不可小於 0")
        if not isinstance(enemy.get("speed"), int) or enemy.get("speed", 0) <= 0:
            errors.append(f"enemy {enemy_id} speed 必須是正整數")
        if not isinstance(enemy.get("tier"), int) or enemy.get("tier", 0) <= 0:
            errors.append(f"enemy {enemy_id} tier 必須是正整數")
        intent_pattern = enemy.get("intent_pattern")
        if not isinstance(intent_pattern, list) or not intent_pattern:
            errors.append(f"enemy {enemy_id} intent_pattern 必須是非空陣列")
        else:
            for intent in intent_pattern:
                if intent not in INTENTS:
                    errors.append(f"enemy {enemy_id} 使用未知 intent：{intent}")
                if intent not in intent_ids:
                    errors.append(f"enemy {enemy_id} 引用不存在 intent：{intent}")
        rule_ids = set()
        for rule in enemy.get("intent_rules", []):
            if not isinstance(rule, dict) or not isinstance(rule.get("id"), str) or not rule.get("id") or rule.get("id") in rule_ids:
                errors.append(f"enemy {enemy_id} intent_rules 必須包含唯一非空 id")
                continue
            rule_ids.add(rule["id"])
            has_condition = "turn_gte" in rule or "hp_ratio_lte" in rule
            if not has_condition:
                errors.append(f"enemy {enemy_id} intent rule {rule['id']} 缺少條件")
            if "turn_gte" in rule and (not isinstance(rule["turn_gte"], int) or rule["turn_gte"] <= 0):
                errors.append(f"enemy {enemy_id} intent rule {rule['id']} turn_gte 不合法")
            if "hp_ratio_lte" in rule and (not isinstance(rule["hp_ratio_lte"], (int, float)) or not 0 < rule["hp_ratio_lte"] <= 1):
                errors.append(f"enemy {enemy_id} intent rule {rule['id']} hp_ratio_lte 不合法")
            rule_pattern = rule.get("pattern")
            if not isinstance(rule_pattern, list) or not rule_pattern:
                errors.append(f"enemy {enemy_id} intent rule {rule['id']} pattern 必須是非空陣列")
            else:
                for intent in rule_pattern:
                    if intent not in intent_ids:
                        errors.append(f"enemy {enemy_id} intent rule {rule['id']} 引用不存在 intent：{intent}")
        if not isinstance(enemy.get("sanity_pressure"), bool):
            errors.append(f"enemy {enemy_id} sanity_pressure 必須是布林值")

    for intent in intents:
        intent_id = intent.get("id")
        action = intent.get("action")
        if not isinstance(intent.get("display_name"), str) or not intent.get("display_name"):
            errors.append(f"intent {intent_id} display_name 必須是非空字串")
        if action not in INTENT_ACTIONS:
            errors.append(f"intent {intent_id} action 不合法：{action}")
        if action in {"armor", "sanity_damage", "status_player", "status_self"}:
            if not isinstance(intent.get("amount"), int) or intent.get("amount", 0) <= 0:
                errors.append(f"intent {intent_id} amount 必須是正整數")
        if action in {"status_player", "status_self"} and intent.get("status_id") not in STATUSES:
            errors.append(f"intent {intent_id} status_id 不合法：{intent.get('status_id')}")

    for encounter in encounters:
        enemy_refs = encounter.get("enemy_ids", [])
        if not isinstance(enemy_refs, list) or not enemy_refs:
            errors.append(f"encounter {encounter.get('id')} enemy_ids 必須是非空陣列")
        elif len(enemy_refs) > 5:
            errors.append(f"encounter {encounter.get('id')} 超過 5 名敵人上限")
        for enemy_id in enemy_refs:
            if enemy_id not in enemy_ids:
                errors.append(f"encounter {encounter.get('id')} 引用不存在敵人：{enemy_id}")

    map_nodes = map_document.get("nodes")
    if not isinstance(map_nodes, list) or not map_nodes:
        errors.append("map.json.nodes 必須是非空陣列")
        map_nodes = []
    map_ids = collect_ids(map_nodes, "map.json.nodes", errors)
    map_by_id = {node.get("id"): node for node in map_nodes if isinstance(node, dict)}
    allowed_node_types = {"normal_battle", "elite", "boss", "event", "shop", "rest"}
    for node in map_nodes:
        node_id = node.get("id")
        node_type = node.get("type")
        if node_type not in allowed_node_types:
            errors.append(f"map node {node_id} type 不合法：{node_type}")
        next_ids = node.get("next_ids", [])
        if not isinstance(next_ids, list):
            errors.append(f"map node {node_id}.next_ids 必須是陣列")
            next_ids = []
        elif len(next_ids) != len(set(next_ids)):
            errors.append(f"map node {node_id}.next_ids 含有重複節點")
        for next_id in next_ids:
            if next_id not in map_ids:
                errors.append(f"map node {node_id} 指向不存在節點：{next_id}")
        if node_type in {"normal_battle", "elite", "boss"} and node.get("content_id") not in encounter_ids:
            errors.append(f"map node {node_id} 引用不存在 encounter：{node.get('content_id')}")
        if node_type == "event" and node.get("content_id") not in event_ids:
            errors.append(f"map node {node_id} 引用不存在 event：{node.get('content_id')}")
        if node_type == "shop" and node.get("content_id") not in shop_ids:
            errors.append(f"map node {node_id} 引用不存在 shop：{node.get('content_id')}")
        if node_type == "rest" and node.get("content_id") not in rest_ids:
            errors.append(f"map node {node_id} 引用不存在 rest：{node.get('content_id')}")
    start_ids = map_document.get("start_node_ids", [])
    if not isinstance(start_ids, list) or not start_ids:
        errors.append("map.start_node_ids 必須是非空陣列")
        start_ids = []
    for start_id in start_ids:
        if start_id not in map_ids:
            errors.append(f"map start node 不存在：{start_id}")
    if len(start_ids) != len(set(start_ids)):
        errors.append("map.start_node_ids 含有重複節點")
    boss_id = map_document.get("boss_node_id")
    if boss_id not in map_by_id or map_by_id.get(boss_id, {}).get("type") != "boss":
        errors.append("map.boss_node_id 必須引用 boss 節點")
    elif map_by_id[boss_id].get("next_ids", []):
        errors.append("map Boss 必須是唯一終點，next_ids 必須為空")

    map_edges = {
        node_id: [next_id for next_id in node.get("next_ids", []) if next_id in map_ids]
        if isinstance(node.get("next_ids", []), list)
        else []
        for node_id, node in map_by_id.items()
    }
    validate_acyclic_edges(map_edges, "地圖路線", errors)
    incoming_counts = Counter(next_id for next_ids in map_edges.values() for next_id in next_ids)
    boss_ids = [node_id for node_id, node in map_by_id.items() if node.get("type") == "boss"]
    if len(boss_ids) != 1:
        errors.append(f"map 必須剛好有 1 個 boss 節點，目前為 {len(boss_ids)}")
    for node_id, node in map_by_id.items():
        if node_id in start_ids and incoming_counts[node_id] > 0:
            errors.append(f"map start node {node_id} 不可有前置連線")
        if node_id not in start_ids and incoming_counts[node_id] == 0:
            errors.append(f"map node {node_id} 無法從任一前置節點進入")
        if node_id != boss_id and not node.get("next_ids", []):
            errors.append(f"map node {node_id} 是 Boss 以外的死路")

    def can_reach(start_id, target_id):
        pending = [start_id]
        visited = set()
        while pending:
            current = pending.pop(0)
            if current == target_id:
                return True
            if current in visited:
                continue
            visited.add(current)
            pending.extend(map_by_id.get(current, {}).get("next_ids", []))
        return False

    for start_id in start_ids:
        if boss_id in map_ids and not can_reach(start_id, boss_id):
            errors.append(f"map 起點 {start_id} 無法抵達 Boss {boss_id}")

    generation = map_document.get("generation", {})
    if generation.get("enabled", False):
        if generation.get("algorithm") != "layered_dag":
            errors.append("map.generation.algorithm 目前只支援 layered_dag")
        for field in ("floors", "columns", "start_count", "min_nodes_per_floor", "max_nodes_per_floor", "max_links_per_node"):
            if not isinstance(generation.get(field), int) or generation.get(field, 0) <= 0:
                errors.append(f"map.generation.{field} 必須是正整數")
        if int(generation.get("floors", 0)) < 3:
            errors.append("map.generation.floors 至少為 3")
        columns = int(generation.get("columns", 0))
        min_nodes = int(generation.get("min_nodes_per_floor", 0))
        max_nodes = int(generation.get("max_nodes_per_floor", 0))
        start_count = int(generation.get("start_count", 0))
        if not 1 <= min_nodes <= max_nodes <= columns:
            errors.append("map.generation 必須符合 1 <= min_nodes_per_floor <= max_nodes_per_floor <= columns")
        if start_count > columns:
            errors.append("map.generation.start_count 不可大於 columns")
        type_weights = generation.get("type_weights")
        if not isinstance(type_weights, dict):
            errors.append("map.generation.type_weights 必須是物件")
        elif any(not isinstance(type_weights.get(node_type), (int, float)) or type_weights.get(node_type, -1) < 0 for node_type in ("normal_battle", "elite", "event", "shop", "rest")):
            errors.append("map.generation.type_weights 必須包含所有非 Boss 類型的非負權重")
        elif sum(type_weights[node_type] for node_type in ("normal_battle", "elite", "event", "shop", "rest")) <= 0:
            errors.append("map.generation.type_weights 總和必須大於 0")
        if generation.get("structured_node_types", False):
            floors = int(generation.get("floors", 0))
            structured_floors = [
                int(generation.get("event_floor", -1)),
                int(generation.get("elite_floor", -1)),
                floors // 2,
            ]
            if any(floor < 1 or floor >= floors - 2 for floor in structured_floors):
                errors.append("結構化 event／elite／shop 樓層必須位於起點與 Boss 前休息之間")
            if len(set(structured_floors)) != len(structured_floors):
                errors.append("結構化 event／elite／shop 不可使用同一樓層")
        content_pools = map_document.get("content_pools", {})
        expected_pool_names = (
            "normal_encounters", "elite_encounters", "boss_encounters", "event", "shop", "rest"
        )
        for pool_name in expected_pool_names:
            pool = content_pools.get(pool_name)
            if not isinstance(pool, list) or not pool:
                errors.append(f"map.content_pools.{pool_name} 必須是非空陣列")
                continue
            if len(pool) != len(set(pool)):
                errors.append(f"map.content_pools.{pool_name} 含有重複 ID")
            if pool_name.endswith("_encounters"):
                for encounter_id in pool:
                    if encounter_id not in encounter_ids:
                        errors.append(f"map.content_pools.{pool_name} 引用不存在 encounter：{encounter_id}")
            elif pool_name == "event":
                for event_id in pool:
                    if event_id not in event_ids:
                        errors.append(f"map.content_pools.event 引用不存在 event：{event_id}")
            elif pool_name == "shop":
                for shop_id in pool:
                    if shop_id not in shop_ids:
                        errors.append(f"map.content_pools.shop 引用不存在 shop：{shop_id}")
            elif pool_name == "rest":
                for rest_id in pool:
                    if rest_id not in rest_ids:
                        errors.append(f"map.content_pools.rest 引用不存在 rest：{rest_id}")

        if generation.get("structured_node_types", False):
            normal_sequence = generation.get("normal_encounter_indices", [])
            normal_pool = content_pools.get("normal_encounters", [])
            expected_normal_floors = max(int(generation.get("floors", 0)) - 5, 0)
            if not isinstance(normal_sequence, list) or len(normal_sequence) != expected_normal_floors:
                errors.append("map.generation.normal_encounter_indices 必須逐一對應結構化普通戰鬥樓層")
            elif not isinstance(normal_pool, list) or any(not isinstance(index, int) or index < 0 or index >= len(normal_pool) for index in normal_sequence):
                errors.append("map.generation.normal_encounter_indices 含有超出普通遭遇池的索引")

        node_pool_names = {
            "normal_battle": "normal_encounters",
            "elite": "elite_encounters",
            "boss": "boss_encounters",
            "event": "event",
            "shop": "shop",
            "rest": "rest",
        }
        for node in map_nodes:
            pool_name = node_pool_names.get(node.get("type"))
            pool = content_pools.get(pool_name, [])
            if isinstance(pool, list) and node.get("content_id") not in pool:
                errors.append(
                    f"map node {node.get('id')} 的 content_id 不在 {pool_name} 內：{node.get('content_id')}"
                )

    stages = sanity_document.get("stages", [])
    effects = sanity_document.get("effects", [])
    if not isinstance(stages, list) or len(stages) < 2:
        errors.append("sanity.stages 至少需要兩個階段")
        stages = []
    if not isinstance(effects, list) or not effects:
        errors.append("sanity.effects 必須是非空陣列")
        effects = []
    sanity_effect_ids = collect_ids(effects, "sanity.effects", errors)
    last_threshold = 101
    last_count = 0
    for stage in stages:
        threshold = stage.get("threshold")
        effect_count = stage.get("effect_count")
        if not isinstance(threshold, int) or threshold < 0 or threshold >= last_threshold:
            errors.append("sanity stages 必須依 threshold 由高至低排列")
        if not isinstance(effect_count, int) or effect_count <= last_count:
            errors.append("sanity stages 的 effect_count 必須逐階增加")
        last_threshold = threshold if isinstance(threshold, int) else last_threshold
        last_count = effect_count if isinstance(effect_count, int) else last_count
    if last_count > len(sanity_effect_ids):
        errors.append("sanity effects 數量不足以供應最高階段")
    for effect in effects:
        resource_path = effect.get("behavior_resource")
        if not isinstance(resource_path, str) or not resource_path.startswith("res://"):
            errors.append(f"sanity effect {effect.get('id')} behavior_resource 必須是 res:// 路徑")
        elif not (ROOT / resource_path.removeprefix("res://")).is_file():
            errors.append(f"sanity effect {effect.get('id')} behavior_resource 不存在：{resource_path}")
        if not isinstance(effect.get("amount"), int):
            errors.append(f"sanity effect {effect.get('id')} amount 必須是整數")

    spell_pool = run_config.get("spell_pool")
    if not isinstance(spell_pool, list) or not spell_pool:
        errors.append("run_config.spell_pool 必須是非空陣列")
    else:
        for spell_id in spell_pool:
            if spell_id not in spell_ids:
                errors.append(f"run_config.spell_pool 引用不存在咒文：{spell_id}")
    if not isinstance(run_config.get("mp_restore_per_node"), int) or run_config.get("mp_restore_per_node", -1) < 0:
        errors.append("run_config.mp_restore_per_node 必須是非負整數")
    if run_config.get("runtime_seed_mode") not in ("random", "fixed"):
        errors.append("run_config.runtime_seed_mode 必須是 random 或 fixed")
    if not isinstance(run_config.get("editor_start_fresh"), bool):
        errors.append("run_config.editor_start_fresh 必須是布林值")
    if not isinstance(run_config.get("run_history_limit"), int) or run_config.get("run_history_limit", 0) <= 0:
        errors.append("run_config.run_history_limit 必須是正整數")
    tutorials = run_config.get("tutorials")
    if not isinstance(tutorials, dict) or not isinstance(tutorials.get("battle_time_pressure"), str) or not tutorials.get("battle_time_pressure"):
        errors.append("run_config.tutorials.battle_time_pressure 必須是非空字串")
    time_pressure = run_config.get("difficulty_model", {}).get("time_pressure")
    if not isinstance(time_pressure, dict):
        errors.append("run_config.difficulty_model.time_pressure 必須是物件")
    elif time_pressure.get("enabled", False):
        fields = ("base_turns", "strength_per_bonus_turn", "depth_penalty_interval", "minimum_turn_limit", "maximum_turn_limit", "sanity_loss_base", "sanity_loss_growth")
        for field in fields:
            if not isinstance(time_pressure.get(field), int) or time_pressure.get(field, -1) < 0:
                errors.append(f"time_pressure.{field} 必須是非負整數")
        if time_pressure.get("strength_per_bonus_turn", 0) <= 0 or time_pressure.get("depth_penalty_interval", 0) <= 0:
            errors.append("time_pressure 強度與深度除數必須大於 0")
        if time_pressure.get("maximum_turn_limit", 0) < time_pressure.get("minimum_turn_limit", 0):
            errors.append("time_pressure 最大時限不得小於最小時限")

    for reward in rewards:
        reward_type = reward.get("type")
        reward_id = reward.get("id")
        if not isinstance(reward.get("weight"), (int, float)) or reward.get("weight", 0) <= 0:
            errors.append(f"reward {reward_id} weight 必須大於 0")
        if not isinstance(reward.get("min_reward_tier"), int) or reward.get("min_reward_tier", 0) <= 0:
            errors.append(f"reward {reward_id} min_reward_tier 必須是正整數")
        if reward_type == "spell":
            if reward_id not in spell_ids:
                errors.append(f"reward 引用不存在咒文：{reward_id}")
        elif reward_type == "block":
            if reward_id not in block_ids:
                errors.append(f"reward 引用不存在方塊：{reward_id}")
        else:
            errors.append(f"reward type 不合法：{reward_type}")

        if reward_type == "block":
            block = block_by_id.get(reward_id)
            if block is not None and not bool(block.get("special", False)):
                errors.append(f"方塊獎勵只能引用特殊方塊：{reward_id}")
        if int(reward.get("min_battles_won", 0)) < 0:
            errors.append(f"reward {reward.get('title')} 的 min_battles_won 不可小於 0")

    validate_reward_dependencies(rewards, reward_ids, errors)
    for reward_tier in range(1, 4):
        eligible_count = 0
        for reward in rewards:
            if int(reward.get("min_reward_tier", 1)) > reward_tier:
                continue
            if reward.get("type") == "spell":
                definition = spell_by_id.get(reward.get("id"), {})
                if RARITY_RANK.get(definition.get("rarity"), 0) > reward_tier:
                    continue
            elif reward.get("type") == "block":
                definition = block_by_id.get(reward.get("id"), {})
                if int(definition.get("tier", 0)) > reward_tier:
                    continue
            eligible_count += 1
        if eligible_count < 3:
            errors.append(f"reward tier {reward_tier} 在全解鎖時仍不足三選一：只有 {eligible_count} 項")

    if errors:
        print("DATA VALIDATION FAILED")
        for error in errors:
            print(f"- {error}")
        if warnings:
            print("WARNINGS")
            for warning in warnings:
                print(f"- {warning}")
        return 1

    print("DATA VALIDATION OK")
    print(f"- blocks: {len(block_ids)}")
    print(f"- spells: {len(spell_ids)}")
    print(f"- enemies: {len(enemy_ids)}")
    print(f"- intents: {len(intent_ids)}")
    print(f"- encounters: {len(encounters)}")
    print(f"- rewards: {len(rewards)}")
    print(f"- events: {len(events)}")
    print(f"- shops: {len(shops)}")
    print(f"- rests: {len(rests)}")
    print(f"- map nodes: {len(map_ids)}")
    print(f"- sanity effects: {len(sanity_effect_ids)}")
    print(f"- initial meta unlocks: {len(meta_progression.get('initial_unlocked_block_ids', []))} blocks / {len(meta_progression.get('initial_unlocked_spell_ids', []))} spells")
    if warnings:
        print("WARNINGS")
        for warning in warnings:
            print(f"- {warning}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
