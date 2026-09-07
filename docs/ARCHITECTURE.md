# Phase 11 架構與資料流

## 責任邊界

- `ContentRegistry` 是唯一的 JSON 讀取入口。它負責 schema 版本、必要值域、唯一 ID、跨檔案引用、ID 查詢，以及建立 runtime `BlockData` / `BattleItem`。
- `RunManager` 只協調 Run 流程、獎勵與 `RunState`，不解析 JSON，也不建立內容 Resource。
- `RunState` 是可序列化的局內狀態邊界；目前保存玩家資源、AP 基準、盤面、手牌方向、方塊池、Row/Col 裝備、背包、地圖進度、已選獎勵、Sanity 效果與隨機種子。`ContentRegistry.validate_run_state_references()` 在還原前阻擋失效內容 ID。
- `SaveGameService` 是磁碟存檔邊界。它使用單一 Run 自動槽與版本 envelope，先嚴格驗證、寫入同目錄暫存檔，再輪替 last-known-good 備份；主檔損壞時可只讀回退，遷移失敗時不覆寫來源。服務可注入路徑以隔離測試。
- `RunState` v4 另保存獎勵與 Tablet 抽牌 RNG 的當前 state（以整數字串避免 JSON 精度損失），讓 v4 快照恢復後的下一個隨機結果與不中斷流程一致。舊 v3 只有 seed，遷移時只能建立穩定的 fallback 起點，無法重建當時已消耗的 RNG 位置；此前尚無正式磁碟存檔，因此不另保留不安全的舊流程。
- `BattleStartInput` 是 Run 進入戰鬥的唯一資料包；`BattleResult` 透過 `battle_finished` 回傳結果。戰鬥控制器不決定下一個場景。
- `EnemyFactory` 建立敵人實例並套用內容資料；`EnemyRosterPresenter` 建立與更新目前原型敵人 UI；`BattleManager` 保留回合與效果規則。
- `EnemyIntentState`／`EnemyIntentExecutor`、`TargetResolver`、`BattleEffectContext` 與 `BattleOutcomeResolver` 分別承擔意圖、目標、效果輸入與結果判定；詳細時序見 `docs/COMBAT_SYSTEM.md`。
- `BattleBatchSimulator` 使用相同的 Entity、道具 Resource、意圖執行器、目標與勝敗規則消耗棋盤事件，提供不建立 UI 場景的固定 seed 戰鬥回歸報告。
- `RunPressureSimulator` 在程序地圖上串接持久化棋盤／手牌、玩家 HP／Sanity、獎勵、背包合成與自動裝備政策，量測完整路線的累積壓力；它只是一套明示策略的測試代理，不代表玩家選擇。
- `BoardModel` 保存 8x8 盤面與純放置／消除規則；`SmartHandScorer` 只負責候選評分；`BoardSimulator` 以固定 seed 重播補牌、AP、消線與死盤重建；`TabletGenerator` 是 Control 視覺、拖放與動畫轉接層。
- `scenes/battle_scene.tscn`、`reward_scene.tscn`、`map_container.tscn`、`settlement_scene.tscn` 提供獨立場景邊界；地圖與結算已由 Phase 14 接入 Run 狀態機。
- `LayeredMapGenerator` 以 Run seed 和 `data/map.json` 生成可重現 DAG；`RunMapView` 只呈現目前可達節點，節點結果統一由 `RunNodeResult` 修改 RunState。

## 資料流

```text
versioned JSON -> ContentRegistry -> definitions / runtime Resources
                                      |
                                      v
RunState -> BattleStartInput -> BattleManager -> BattleResult -> RunManager
   |               |                     |
   |               |                     +-> EnemyFactory / EnemyRosterPresenter
   |               +-> loadout / player / encounter
   +-> BoardModel / hand / pool / progress
```

## JSON 與 `.tres`

`ARCH-001` 已定案：

- JSON 管理內容 ID、名稱、組合、數值、標籤與資源引用。
- `.tres` 管理效果行為原型，也就是實際執行效果的 GDScript Resource 類別。
- `run_config.json.effect_resources` 將每個 `logic` 對應到正式 `.tres`。`ContentRegistry` 載入並複製原型，再套用 `items.json` 的數值建立 runtime `BattleItem`。
- JSON 不直接決定 GDScript 類別；`.tres` 不保存正式內容數值。舊 `resources/items/*.tres` 僅為場景 fallback，正式效果原型位於 `resources/effects/`。
- 新增效果行為時，先建立新的 `BattleItem` 子類別與 `.tres` 原型，再加入 `effect_resources` 與驗證允許值；新增同一行為的數值變體只需修改 JSON。

## 驗證入口

- `tools/validate_all.sh`：依序執行以下資料、測試與固定 seed 模擬；也可用 `GODOT_BIN` 指定 Godot 4.x 執行檔。
- `python3 tools/validate_data.py`：不啟動 Godot 的完整內容、升級鏈、獎勵池與地圖關係驗證。
- `godot --headless --path . --log-file /tmp/arkham-grid-tests.log --script res://tests/test_runner.gd`：18 組資料、RunState、磁碟存檔／遷移、事件、棋盤／戰鬥／完整 Run 模擬與主場景測試。
- `godot --headless --path . --log-file /tmp/arkham-grid-board-simulation.log --script res://tools/simulate_board.gd`：以現行起始池比較智慧手牌與權重隨機，輸出合法手牌／卡片、直接消線、盤面佔用與死盤率。
- `godot --headless --path . --log-file /tmp/arkham-grid-battle-batch.log --script res://tools/simulate_battles.gd`：以相同棋盤序列跑六個遭遇，輸出勝率、回合、傷害、護甲、Sanity 與敵人存活曲線。
- `godot --headless --path . --log-file /tmp/arkham-grid-run-simulation.log --script res://tools/simulate_runs.gd`：跨六場保留棋盤、手牌、HP、Sanity、獎勵與裝備成長，輸出通關率及逐場壓力曲線。
- 遊戲啟動時 `ContentRegistry.load_all()` 會再次驗證 schema、值域與引用；失敗時不會進入第一場戰鬥。
