# 資料表說明

目前遊戲啟動時會由 `ContentRegistry` 集中讀取這些 JSON，先完成 schema、值域與引用驗證，再建立 runtime 方塊與咒文 Resource。`RunManager` 只透過註冊層查詢資料。

所有 JSON 根節點都必須是物件並包含 `"schema_version": 1`。內容清單檔使用 `entries` 陣列；`player.json` 與 `run_config.json` 則直接在根節點保存設定欄位。

可複製的現行內容範例位於 `data/templates/`；ID、欄位廢棄與升版流程見 `docs/CONTENT_SCHEMA.md`。事件、商店與休息依 `CONTENT-006`／`CONTENT-007` 共用多選項及資料化代價／結果結構。

Phase 13 成長欄位：

- 咒文：`rarity`、`tier`、`balance_cost`、`mp_cost`；可升級項目另填 `upgrade_to` 與 `combine_count`，升級結果以 `upgrade_from` 反向引用來源。
- 獎勵：`weight`、`min_reward_tier`，以及選用的 `min_battles_won`、`requires_rewards`。
- 關卡難度：`run_config.json.difficulty_model` 保存公式係數、reward tier 門檻，以及依強度／節點深度計算的戰鬥時限與逾時 Sanity 壓力。
- 棋盤成長：`run_config.json.board_growth_rules` 保存智慧手牌方向保證數與程序友善盤面參數。
- 程序路線：`map.json.generation` 保存分層 DAG 參數與類型權重，`content_pools` 保存 encounter 引用；固定 `nodes` 作為 fallback。Run seed 決定完整地圖。
- JSON 決定組合與數值；`.tres` 只選擇效果行為原型。

## 檔案用途

- `player.json`：職業 ID、玩家初始生命、理智、MP 與 AP。
- `enemies.json`：敵人數值、基礎意圖循環及依 HP／回合切換的條件式意圖。
- `intents.json`：敵人意圖顯示名稱、action 與數值。
- `encounters.json`：每場戰鬥會出現的敵人組合。
- `blocks.json`：方塊形狀、顏色、格子座標與抽取權重；不綁定咒文。
- `spells.json`：所有咒文的盤面圖標、數值、MP 成本、範圍與效果資料。
- `run_config.json`：開局方塊池、咒文池、每節點 MP 回復與棋盤規則。
- `meta_progression.json`：共享 Meta 貨幣，以及職業、方塊、咒文的初始解鎖白名單。
- `rewards.json`：戰鬥勝利後三選一獎勵池。
- `events.json`：事件標題、場景描述、多個選項，以及各選項的資源代價與結果。
- `shops.json`：商店場景、商品選項、金錢成本、資源補給與咒文／特殊形狀授予。
- `rests.json`：休息場景與 HP／Sanity／MP 恢復選項。

## JSON／`.tres` 責任

- JSON 管內容組合與數值。
- `resources/effects/*.tres` 管效果行為原型。
- `run_config.json.effect_resources` 必須為每個允許的 `logic` 指定一個 `.tres`。
- 啟動時會先驗證路徑與 Resource 類型，再複製 `.tres` 並套用 JSON 數值。

## 驗證資料

執行：

```bash
python3 tools/validate_data.py
```

驗證會檢查 JSON schema、內容範本語法、值域與唯一 ID、咒文效果 Resource、跨檔引用、升級鏈、獎勵前置、地圖內容池與 DAG 拓撲、Sanity 效果資源、Meta 初始解鎖，以及現行最低內容數量。Godot 啟動層會重複檢查相同關係，並在還原 RunState 或 MetaState 前拒絕已失效的內容引用。

玩家磁碟資料分為 `run_autosave.json`、`settings.json` 與 `meta_progress.json`。三者版本與備份互相獨立；設定或 Meta 損壞不會連帶破壞進行中的 Run。

## 新增方塊

1. 在 `blocks.json` 新增一筆唯一 `id`。
2. `cells` 使用 `[x, y]` 座標，以 `[0, 0]` 為方塊原點。
3. 若要讓它出現在開局方塊池，將 `id` 加入 `run_config.json` 的 `block_pool`。
4. 普通方塊不放入 `rewards.json`；方塊獎勵只保留給特殊形狀。
5. 若要作為方塊獎勵，必須設定 `special: true`；每種特殊形狀只解鎖一次。
6. `weight` 影響抽牌權重，`smart_score_bonus` 影響智慧候選排名。特殊形狀應使用低值；同手在池內類型足夠時不重複 ID。

## 新增咒文

1. 在 `spells.json` 新增唯一 `id`。
2. `logic` 可為 `attack`、`conditional_attack`、`support` 或 `status`，並必須在 `run_config.json.effect_resources` 有對應的 `.tres` 行為原型。
3. 每個咒文都必須設定 1–2 個可見字元的 `icon_text` 與非負整數 `mp_cost`；MP 不足時 runtime 會以完整成本等量支付 Sanity。
4. 攻擊型使用 `damage`、`hit_count`；支援型使用 `armor_gain`。常規咒文的 `heal_amount` 必須為 0，也不得給玩家再生。
5. `effect_scope` 可使用 `single`、`spread`、`all`、`self`。
6. `status_effects_self` / `status_effects_target` 用來描述異常狀態。
7. `rarity`、`tier` 與 `balance_cost` 管理取得階段與平衡；`trigger_hint` 必須描述效果格與 MP 成本。
8. 若要放入開局構築，將 ID 加入 `run_config.json.spell_pool`；重複 ID 代表較高附著機率。
9. 若要成為獎勵，將 ID 以 `type: "spell"` 加入 `rewards.json`。
10. 升級鏈的 `upgrade_to` / `upgrade_from` 必須雙向對應、不得成環，且 tier 必須上升、rarity 不得下降。

## 角色資源成長限制

普通戰鬥的 `rewards.json` 不支援 HP 回復、Sanity 回復、HP / Sanity 上限增加或 AP 上限增加。

這些效果屬於非常稀有的特殊獎勵，應未來放在事件、休息、Boss 後或高代價節點中另外設計，不進入常規三選一獎勵池。

## 新增事件、商店或休息

1. 依節點類型在 `events.json`、`shops.json` 或 `rests.json` 新增唯一 `id`、`title`、`description` 與至少兩個 `options`。
2. 每個選項需要唯一 `id`、`label`、`result_text`，並以 `costs`、`results` 物件定義數值；可選 `grant` 以 `type` 與 `id` 授予咒文或特殊形狀。
3. 第一版資源鍵只接受 `hp`、`sanity`、`mp`、`currency`，數量必須是非負整數。
4. HP 或 Sanity 不可因支付代價降至 0；不足的選項會在介面中禁用。HP、Sanity 與 MP 回復不超過對應上限。
5. 將內容 ID 加入 `map.json.content_pools` 的對應類型；固定地圖節點的 `content_id` 也必須引用同一 ID。
6. 選擇前會顯示成本與收益；節點完成後透過 `RunNodeResult` 修改 RunState，套用固定 MP 回復並保留盤面。

## 新增敵人

1. 在 `enemies.json` 新增唯一 `id`。
2. `hp` 與 `attack` 需符合 `docs/NUMERIC_MODEL.md` 的戰鬥序列曲線。
3. `speed` 是不顯示給玩家的正整數，越高越早行動；同速依 encounter 生成順序。
4. `intent_pattern` 必須引用 `intents.json` 的有效 ID，每名敵人會獨立循環自己的索引。可選 `intent_rules` 使用 `turn_gte` 或 `hp_ratio_lte` 與替代 `pattern`；規則依陣列順序判定。
5. Encounter 最多同時引用 5 名敵人。
6. `sanity_pressure` 標記該敵人是否會施加 Sanity 壓力。
7. 敵人不記錄 `reward_tier`；獎勵級別由關卡難度決定。

## 新增敵人意圖

1. 在 `intents.json` 新增唯一 `id`、玩家可見 `display_name` 與 action。
2. action 可為 `damage`、`armor`、`sanity_damage`、`status_player`、`status_self`、`idle`。
3. 傷害使用 `multiplier`／`flat_bonus`；其他 action 使用正整數 `amount`；狀態 action 還需要合法 `status_id`。
4. 將新 ID 加入驗證允許值後，才可由敵人的 `intent_pattern` 引用；未知意圖不得 fallback。

## 新增 Sanity 效果

1. `sanity.json.stages` 依 threshold 由高至低排列，`effect_count` 必須逐階增加。
2. 效果的 ID、顯示、描述與 `amount` 放在 JSON；實際運作類型由 `behavior_resource` 指向 `.tres`。
3. `.tres` 必須使用 `MadnessEffect` 行為，管理節點不得依效果 ID 寫特例。
4. 新增來源時同步補上 `source_labels`，並一律呼叫 `Entity.change_sanity(delta, source)`。
