#!/usr/bin/env python3
import json
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"

ITEM_TYPES = {"WEAPON", "EQUIPMENT", "PRAYER", "CURSE"}
ITEM_LOGICS = {"attack", "conditional_attack", "support", "status"}
RARITIES = {"common", "uncommon", "rare"}
RARITY_RANK = {"common": 1, "uncommon": 2, "rare": 3}
SCOPES = {"single", "spread", "all", "self"}
STATUSES = {"strength", "weak", "hard", "fragile", "regen", "poison"}
INTENTS = {"attack", "heavy_attack", "guard", "sanity_attack", "debuff_player", "buff_self"}
INTENT_ACTIONS = {"damage", "armor", "sanity_damage", "status_player", "status_self"}
SCHEMA_VERSION = 1
TEMPLATE_FILES = {
    "block.example.json",
    "item.example.json",
    "intent.example.json",
    "enemy.example.json",
    "encounter.example.json",
    "reward.example.json",
    "event.example.json",
}
EVENT_RESOURCES = {"hp", "sanity", "currency"}


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


def validate_status_effects(item, field, errors):
    effects = item.get(field, [])
    if effects is None:
        return
    if not isinstance(effects, list):
        errors.append(f"item {item.get('id')} 的 {field} 必須是陣列")
        return
    for effect in effects:
        if not isinstance(effect, dict):
            errors.append(f"item {item.get('id')} 的 {field} 內含非物件資料")
            continue
        status_id = effect.get("id")
        amount = effect.get("amount")
        if status_id not in STATUSES:
            errors.append(f"item {item.get('id')} 使用未知狀態：{status_id}")
        if not isinstance(amount, int) or amount <= 0:
            errors.append(f"item {item.get('id')} 狀態 {status_id} 的 amount 必須是正整數")


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


def validate_upgrade_chains(items, item_by_id, errors):
    edges = {}
    for item in items:
        item_id = item.get("id")
        upgrade_from = item.get("upgrade_from") or ""
        upgrade_to = item.get("upgrade_to") or ""
        edges[item_id] = [upgrade_to] if upgrade_to in item_by_id else []

        if upgrade_from:
            source = item_by_id.get(upgrade_from)
            if source is not None and (source.get("upgrade_to") or "") != item_id:
                errors.append(
                    f"item {item_id}.upgrade_from={upgrade_from} 未被來源的 upgrade_to 對應"
                )
        if not upgrade_to:
            continue
        target = item_by_id.get(upgrade_to)
        if target is None:
            continue
        if (target.get("upgrade_from") or "") != item_id:
            errors.append(
                f"item {item_id}.upgrade_to={upgrade_to} 未被目標的 upgrade_from 對應"
            )
        if target.get("item_type") != item.get("item_type"):
            errors.append(f"item {item_id} 與升級目標 {upgrade_to} 的 item_type 不一致")
        if target.get("axis_type") != item.get("axis_type"):
            errors.append(f"item {item_id} 與升級目標 {upgrade_to} 的 axis_type 不一致")
        if int(target.get("tier", 0)) <= int(item.get("tier", 0)):
            errors.append(f"item {upgrade_to} 的 tier 必須高於升級來源 {item_id}")
        source_rarity = RARITY_RANK.get(item.get("rarity"), 0)
        target_rarity = RARITY_RANK.get(target.get("rarity"), 0)
        if target_rarity < source_rarity:
            errors.append(f"item {upgrade_to} 的 rarity 不可低於升級來源 {item_id}")

    validate_acyclic_edges(edges, "道具升級鏈", errors)


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


def validate_events(events, errors):
    for event in events:
        event_id = event.get("id")
        if not isinstance(event.get("title"), str) or not event.get("title"):
            errors.append(f"event {event_id}.title 必須是非空字串")
        if not isinstance(event.get("description"), str) or not event.get("description"):
            errors.append(f"event {event_id}.description 必須是非空字串")
        options = event.get("options")
        if not isinstance(options, list) or len(options) < 2:
            errors.append(f"event {event_id}.options 至少需要兩個選項")
            continue
        collect_ids(options, f"event {event_id}.options", errors)
        for option in options:
            if not isinstance(option, dict):
                errors.append(f"event {event_id}.options 含有非物件資料")
                continue
            option_id = option.get("id")
            if not isinstance(option.get("label"), str) or not option.get("label"):
                errors.append(f"event {event_id} option {option_id}.label 必須是非空字串")
            if not isinstance(option.get("result_text"), str) or not option.get("result_text"):
                errors.append(f"event {event_id} option {option_id}.result_text 必須是非空字串")
            for field in ("costs", "results"):
                resources = option.get(field)
                if not isinstance(resources, dict):
                    errors.append(f"event {event_id} option {option_id}.{field} 必須是物件")
                    continue
                for resource, amount in resources.items():
                    if resource not in EVENT_RESOURCES:
                        errors.append(f"event {event_id} option {option_id}.{field} 使用未知資源：{resource}")
                    if isinstance(amount, bool) or not isinstance(amount, int) or amount < 0:
                        errors.append(f"event {event_id} option {option_id}.{field}.{resource} 必須是非負整數")


def main():
    errors = []
    warnings = []
    validate_templates(errors)

    blocks = load_json("blocks.json").get("entries")
    items = load_json("items.json").get("entries")
    enemies = load_json("enemies.json").get("entries")
    intents = load_json("intents.json").get("entries")
    encounters = load_json("encounters.json").get("entries")
    rewards = load_json("rewards.json").get("entries")
    events = load_json("events.json").get("entries")
    run_config = load_json("run_config.json")
    player = load_json("player.json")
    map_document = load_json("map.json")
    sanity_document = load_json("sanity.json")

    for name, entries in {
        "blocks.json": blocks,
        "items.json": items,
        "enemies.json": enemies,
        "intents.json": intents,
        "encounters.json": encounters,
        "rewards.json": rewards,
        "events.json": events,
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
    item_ids = collect_ids(items, "items.json", errors)
    enemy_ids = collect_ids(enemies, "enemies.json", errors)
    intent_ids = collect_ids(intents, "intents.json", errors)
    encounter_ids = collect_ids(encounters, "encounters.json", errors)
    reward_ids = collect_ids(rewards, "rewards.json", errors)
    event_ids = collect_ids(events, "events.json", errors)
    item_by_id = {item.get("id"): item for item in items}

    validate_events(events, errors)

    for block_id in run_config.get("block_pool", []):
        if block_id not in block_ids:
            errors.append(f"run_config.block_pool 引用不存在方塊：{block_id}")

    if not isinstance(player.get("name"), str) or not player.get("name"):
        errors.append("player.name 必須是非空字串")
    for field in ("max_hp", "hp", "max_sanity", "sanity", "action_points"):
        if not isinstance(player.get(field), int):
            errors.append(f"player.{field} 必須是整數")
    if int(player.get("max_hp", 0)) <= 0 or not 0 < int(player.get("hp", 0)) <= int(player.get("max_hp", 0)):
        errors.append("player.hp 必須介於 1 與 max_hp")
    if int(player.get("max_sanity", 0)) <= 0 or not 0 < int(player.get("sanity", 0)) <= int(player.get("max_sanity", 0)):
        errors.append("player.sanity 必須介於 1 與 max_sanity")
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

    item_type_counts = Counter()
    for item in items:
        item_id = item.get("id")
        item_type = item.get("item_type")
        axis_type = item.get("axis_type")
        logic = item.get("logic")
        rarity = item.get("rarity")
        scope = item.get("effect_scope", "single")
        item_type_counts[item_type] += 1
        if item_type not in ITEM_TYPES:
            errors.append(f"item {item_id} 的 item_type 不合法：{item_type}")
        if axis_type not in {"physical", "magic"}:
            errors.append(f"item {item_id} 的 axis_type 不合法：{axis_type}")
        if logic not in ITEM_LOGICS:
            errors.append(f"item {item_id} 的 logic 不合法：{logic}")
        if rarity not in RARITIES:
            errors.append(f"item {item_id} 的 rarity 不合法：{rarity}")
        if not isinstance(item.get("tier"), int) or item.get("tier", 0) <= 0:
            errors.append(f"item {item_id} 的 tier 必須是正整數")
        if scope not in SCOPES:
            errors.append(f"item {item_id} 的 effect_scope 不合法：{scope}")
        if not isinstance(item.get("tags", []), list):
            errors.append(f"item {item_id} 的 tags 必須是陣列")
        if not isinstance(item.get("balance_cost"), int) or item.get("balance_cost", -1) < 0:
            errors.append(f"item {item_id} 的 balance_cost 必須是非負整數")
        if not isinstance(item.get("sanity_cost", 0), int) or item.get("sanity_cost", 0) < 0:
            errors.append(f"item {item_id} 的 sanity_cost 必須是非負整數")
        validate_status_effects(item, "status_effects_self", errors)
        validate_status_effects(item, "status_effects_target", errors)

        upgrade_from = item.get("upgrade_from", "")
        upgrade_to = item.get("upgrade_to", "")
        if upgrade_from and upgrade_from not in item_ids:
            errors.append(f"item {item_id} upgrade_from 引用不存在道具：{upgrade_from}")
        if upgrade_to:
            if upgrade_to not in item_ids:
                errors.append(f"item {item_id} upgrade_to 引用不存在道具：{upgrade_to}")
            if not isinstance(item.get("combine_count"), int) or item.get("combine_count", 0) <= 1:
                errors.append(f"item {item_id} 有 upgrade_to 時 combine_count 必須大於 1")

    for item_type in sorted(ITEM_TYPES):
        if item_type_counts[item_type] < 4:
            errors.append(f"{item_type} 道具少於 4 件：目前 {item_type_counts[item_type]} 件")

    if len(enemy_ids) < 6:
        errors.append(f"敵人少於 6 種：目前 {len(enemy_ids)} 種")

    validate_upgrade_chains(items, item_by_id, errors)

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

    for field, allowed_axis in (("row_items", "physical"), ("col_items", "magic")):
        ids = run_config.get(field)
        if not isinstance(ids, list) or len(ids) != 8:
            errors.append(f"run_config.{field} 必須剛好有 8 個 ID")
            continue
        for item_id in ids:
            item = next((entry for entry in items if entry.get("id") == item_id), None)
            if item is None:
                errors.append(f"run_config.{field} 引用不存在道具：{item_id}")
            elif item.get("axis_type") != allowed_axis:
                errors.append(f"run_config.{field} 的 {item_id} axis_type 不合法：{item.get('axis_type')}")

    for reward in rewards:
        reward_type = reward.get("type")
        reward_id = reward.get("id")
        if not isinstance(reward.get("weight"), (int, float)) or reward.get("weight", 0) <= 0:
            errors.append(f"reward {reward_id} weight 必須大於 0")
        if not isinstance(reward.get("min_reward_tier"), int) or reward.get("min_reward_tier", 0) <= 0:
            errors.append(f"reward {reward_id} min_reward_tier 必須是正整數")
        if reward_type == "item":
            if reward_id not in item_ids:
                errors.append(f"reward 引用不存在道具：{reward_id}")
            slot_kind = reward.get("slot_kind")
            slot_index = int(reward.get("slot_index", -1))
            if slot_kind not in {"row", "col"}:
                errors.append(f"reward {reward_id} slot_kind 不合法：{slot_kind}")
            if slot_index < 0 or slot_index > 7:
                errors.append(f"reward {reward_id} slot_index 超出 0-7：{slot_index}")
            item = next((entry for entry in items if entry.get("id") == reward_id), None)
            if item is not None:
                axis_type = item.get("axis_type")
                if slot_kind == "row" and axis_type != "physical":
                    errors.append(f"reward {reward_id} 是 {axis_type}，不能放入 Row")
                if slot_kind == "col" and axis_type != "magic":
                    errors.append(f"reward {reward_id} 是 {axis_type}，不能放入 Col")
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
            if reward.get("type") == "item":
                definition = item_by_id.get(reward.get("id"), {})
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
    print(f"- items: {len(item_ids)} ({dict(sorted(item_type_counts.items()))})")
    print(f"- enemies: {len(enemy_ids)}")
    print(f"- intents: {len(intent_ids)}")
    print(f"- encounters: {len(encounters)}")
    print(f"- rewards: {len(rewards)}")
    print(f"- events: {len(events)}")
    print(f"- map nodes: {len(map_ids)}")
    print(f"- sanity effects: {len(sanity_effect_ids)}")
    if warnings:
        print("WARNINGS")
        for warning in warnings:
            print(f"- {warning}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
