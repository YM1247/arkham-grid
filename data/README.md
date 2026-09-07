# 資料表說明

目前遊戲啟動時會由 `ContentRegistry` 集中讀取這些 JSON，先完成 schema、值域與引用驗證，再建立 runtime 方塊與道具 Resource。`RunManager` 只透過註冊層查詢資料。

所有 JSON 根節點都必須是物件並包含 `"schema_version": 1`。內容清單檔使用 `entries` 陣列；`player.json` 與 `run_config.json` 則直接在根節點保存設定欄位。

可複製的現行內容範例位於 `data/templates/`；ID、欄位廢棄與升版流程見 `docs/CONTENT_SCHEMA.md`。事件已依 `CONTENT-006` 使用多選項、資料化代價／結果；商店與休息的正式資料結構等待 `CONTENT-007`。

Phase 13 成長欄位：

- 道具：`rarity`、`tier`、`balance_cost`；可合成項目另填 `upgrade_to` 與大於 1 的 `combine_count`，升級結果以 `upgrade_from` 反向引用來源。
- 獎勵：`weight`、`min_reward_tier`，以及選用的 `min_battles_won`、`requires_rewards`。
- 關卡難度：`run_config.json.difficulty_model` 保存公式係數與 reward tier 門檻。
- 棋盤成長：`run_config.json.board_growth_rules` 保存智慧手牌方向保證數與程序友善盤面參數。
- 程序路線：`map.json.generation` 保存分層 DAG 參數與類型權重，`content_pools` 保存 encounter 引用；固定 `nodes` 作為 fallback。Run seed 決定完整地圖。
- JSON 決定組合與數值；`.tres` 只選擇效果行為原型。

## 檔案用途

- `player.json`：玩家初始生命、理智與 AP。
- `enemies.json`：普通戰鬥會輪流使用的敵人資料。
- `intents.json`：敵人意圖顯示名稱、action 與數值。
- `encounters.json`：每場戰鬥會出現的敵人組合。
- `blocks.json`：方塊形狀、顏色與格子座標。
- `items.json`：裝備、祈禱、詛咒與武器效果數值。
- `run_config.json`：開局方塊池與 8 個 Row / 8 個 Col 的初始裝備 ID。
- `rewards.json`：戰鬥勝利後三選一獎勵池。
- `events.json`：事件標題、場景描述、多個選項，以及各選項的資源代價與結果。

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

驗證會檢查 JSON schema、內容範本語法、值域與唯一 ID、Row / Col slot、效果 Resource、跨檔引用、升級鏈雙向對應與循環、獎勵前置與各 tier 三選一容量、地圖內容池與 DAG 拓撲、Sanity 效果資源，以及現行最低內容數量。Godot 啟動層會重複檢查相同關係，並在還原 RunState 前拒絕已失效的方塊、道具、獎勵、地圖與 Sanity 引用。

## 新增方塊

1. 在 `blocks.json` 新增一筆唯一 `id`。
2. `cells` 使用 `[x, y]` 座標，以 `[0, 0]` 為方塊原點。
3. 若要讓它出現在開局方塊池，將 `id` 加入 `run_config.json` 的 `block_pool`。
4. 普通方塊不放入 `rewards.json`；方塊獎勵只保留給未來的特殊方塊。
5. 若要作為方塊獎勵，必須設定 `special: true`。
6. `weight` 會影響一般抽牌權重；`smart_score_bonus` 會影響智慧手牌評分。

## 新增道具

1. 在 `items.json` 新增唯一 `id`。
2. `logic` 可為 `attack`、`conditional_attack`、`support` 或 `status`，並必須在 `run_config.json.effect_resources` 有對應的 `.tres` 行為原型。
3. `axis_type` 是正式 slot 分類：`physical` 只能放 Row、`magic` 只能放 Col；`item_type` 四分類只保留給舊資料相容。
4. 攻擊型使用 `damage`、`hit_count`；支援型使用 `armor_gain`、`heal_amount`。
5. `magic` 道具可設定 `sanity_cost`，若未設定，戰鬥邏輯會以 3 作為預設成本。
6. `effect_scope` 可使用 `single`、`spread`、`all`、`self`。
7. `status_effects_self` / `status_effects_target` 用來描述異常狀態。
8. `tags` 只留給特殊流派或 combo 道具；普通數值道具應使用空陣列。
9. `rarity` 用來標記稀有度，`trigger_hint` 用來描述觸發條件。
10. `balance_cost` 是內部平衡分數，用來比較道具是否過強。
11. 若要放入初始裝備，將 `id` 填入 `run_config.json` 的 `row_items` 或 `col_items`。
12. 若要成為獎勵，將 `id` 加入 `rewards.json`，並設定 `slot_kind` 與 `slot_index`。
13. 升級鏈的 `upgrade_to` / `upgrade_from` 必須雙向對應，不得成環；升級後必須保持 `item_type` 與 `axis_type`，且 tier 必須上升、rarity 不得下降。

## 角色資源成長限制

普通戰鬥的 `rewards.json` 不支援 HP 回復、Sanity 回復、HP / Sanity 上限增加或 AP 上限增加。

這些效果屬於非常稀有的特殊獎勵，應未來放在事件、休息、Boss 後或高代價節點中另外設計，不進入常規三選一獎勵池。

## 新增事件

1. 在 `events.json` 新增唯一 `id`、`title`、`description` 與至少兩個 `options`。
2. 每個選項需要唯一 `id`、`label`、`result_text`，並以 `costs`、`results` 物件定義數值。
3. 第一版資源鍵只接受 `hp`、`sanity`、`currency`，數量必須是非負整數。
4. HP 或 Sanity 不可因支付代價降至 0；不足的選項會在介面中禁用。回復不超過對應上限。
5. 將事件 ID 加入 `map.json.content_pools.event`；固定地圖節點若使用該事件，`content_id` 也必須引用同一 ID。
6. 選擇前會顯示成本與收益；事件完成後透過 `RunNodeResult` 修改 RunState，盤面保持不變。

## 新增敵人

1. 在 `enemies.json` 新增唯一 `id`。
2. `hp` 與 `attack` 需符合 `docs/NUMERIC_MODEL.md` 的戰鬥序列曲線。
3. `speed` 是不顯示給玩家的正整數，越高越早行動；同速依 encounter 生成順序。
4. `intent_pattern` 必須引用 `intents.json` 的有效 ID，每名敵人會獨立循環自己的索引。
5. Encounter 最多同時引用 5 名敵人。
6. `sanity_pressure` 標記該敵人是否會施加 Sanity 壓力。
7. 敵人不記錄 `reward_tier`；獎勵級別由關卡難度決定。

## 新增敵人意圖

1. 在 `intents.json` 新增唯一 `id`、玩家可見 `display_name` 與 action。
2. action 可為 `damage`、`armor`、`sanity_damage`、`status_player`、`status_self`。
3. 傷害使用 `multiplier`／`flat_bonus`；其他 action 使用正整數 `amount`；狀態 action 還需要合法 `status_id`。
4. 將新 ID 加入驗證允許值後，才可由敵人的 `intent_pattern` 引用；未知意圖不得 fallback。

## 新增 Sanity 效果

1. `sanity.json.stages` 依 threshold 由高至低排列，`effect_count` 必須逐階增加。
2. 效果的 ID、顯示、描述與 `amount` 放在 JSON；實際運作類型由 `behavior_resource` 指向 `.tres`。
3. `.tres` 必須使用 `MadnessEffect` 行為，管理節點不得依效果 ID 寫特例。
4. 新增來源時同步補上 `source_labels`，並一律呼叫 `Entity.change_sanity(delta, source)`。
