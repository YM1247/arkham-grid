# Phase 11 架構與資料流

## 責任邊界

- `ContentRegistry` 是唯一的 JSON 讀取入口。它負責 schema 版本、必要值域、唯一 ID、跨檔案引用、ID 查詢，以及建立 runtime `BlockData` / `BattleItem`。
- `RunManager` 只協調 Run 流程、獎勵與 `RunState`，不解析 JSON，也不建立內容 Resource。
- `RunState` 是可序列化的局內狀態邊界；v6 以 `slate_pool` 保存永久綁定的形狀、咒文與效果格，以 `pending_slate_rewards` 保存尚未選擇的候選，手牌只保存 `slate_uid` 與旋轉方向。
- `SaveGameService` 是磁碟存檔邊界。它使用單一 Run 自動槽與版本 envelope，先嚴格驗證、寫入同目錄暫存檔，再輪替 last-known-good 備份；主檔損壞時可只讀回退，遷移失敗時不覆寫來源。服務可注入路徑以隔離測試。
- `ProfileSaveService` 將 `SettingsState` 與共享 `MetaState` 分成兩份獨立版本檔案，沿用原子寫入與 last-known-good 備份；設定保存語言、視窗、音量與匿名回報偏好，Meta v3 保存共享貨幣、Run 統計、首次教學進度、最近 20 局結算摘要及職業／方塊／咒文解鎖。
- `RunState` v6 因核心組合語意已改變，不近似遷移 v5 進行中 Run；`SaveGameService` 先封存舊自動槽，再由 RunManager 建立新版新局。Profile／Meta 檔案不受影響。
- `BattleStartInput` 是 Run 進入戰鬥的唯一資料包；`BattleResult` 透過 `battle_finished` 回傳結果。戰鬥控制器不決定下一個場景。
- `EnemyFactory` 建立敵人實例並套用內容資料；`EnemyRosterPresenter` 建立與更新目前原型敵人 UI；`BattleManager` 保留回合與效果規則。
- `EnemyIntentState`／`EnemyIntentExecutor`、`TargetResolver`、`BattleEffectContext` 與 `BattleOutcomeResolver` 分別承擔意圖、目標、效果輸入與結果判定；詳細時序見 `docs/COMBAT_SYSTEM.md`。
- `BattleBatchSimulator` 使用相同 Entity、咒文 Resource、MP、意圖、目標與勝敗規則消耗棋盤事件，提供無 UI 的固定 seed 戰鬥回歸報告。
- `RunPressureSimulator` 串接持久化盤面／手牌、HP／Sanity／MP、咒文與形狀獎勵，以及每節點 MP 回復，量測完整路線壓力；它是測試代理，不代表玩家選擇。
- `BoardModel` 保存 8x8 盤面與純放置／消除規則；`SmartHandScorer` 只負責候選評分；`BoardSimulator` 以固定 seed 重播補牌、AP、消線與死盤重建；`TabletGenerator` 是 Control 視覺、拖放與動畫轉接層。
- `scenes/battle_scene.tscn`、`reward_scene.tscn`、`map_container.tscn`、`settlement_scene.tscn` 提供獨立場景邊界；地圖與結算已由 Phase 14 接入 Run 狀態機。
- `LayeredMapGenerator` 以 Run seed 和 `data/map.json` 生成可重現 DAG；`RunMapView` 只呈現目前可達節點，節點結果統一由 `RunNodeResult` 修改 RunState。
- `RunSeedPolicy` 區分一般遊玩的隨機 seed 與測試／除錯的固定 seed，並保證同一 runtime 連續新局不重複上一個 seed。

## 資料流

```text
versioned JSON -> ContentRegistry -> definitions / runtime Resources
                                      |
                                      v
RunState -> BattleStartInput -> BattleManager -> BattleResult -> RunManager
   |               |                     |
   |               |                     +-> EnemyFactory / EnemyRosterPresenter
   |               +-> player / encounter / spell pool
   +-> BoardModel / effect cells / hand / slate pool / progress
```

## JSON 與 `.tres`

`ARCH-001` 已定案：

- JSON 管理內容 ID、名稱、組合、數值、標籤與資源引用。
- `.tres` 管理效果行為原型，也就是實際執行效果的 GDScript Resource 類別。
- `run_config.json.effect_resources` 將每個 `logic` 對應到正式 `.tres`。`ContentRegistry` 載入並複製原型，再套用 `spells.json` 數值建立 runtime `BattleItem`（內部相容類名；玩家可見概念一律為咒文）。
- JSON 不直接決定 GDScript 類別；`.tres` 不保存正式內容數值。正式效果原型位於 `resources/effects/`。
- 新增效果行為時，先建立 `BattleItem` 子類別與 `.tres` 原型，再加入 `effect_resources` 與驗證允許值；同一行為的數值變體只需修改 JSON。

## 驗證入口

- `tools/validate_all.sh`：依序執行以下資料、測試與固定 seed 模擬；也可用 `GODOT_BIN` 指定 Godot 4.x 執行檔。
- `python3 tools/validate_data.py`：不啟動 Godot 的完整內容、升級鏈、獎勵池與地圖關係驗證。
- `godot --headless --path . --log-file /tmp/arkham-grid-tests.log --script res://tests/test_runner.gd`：19 組資料、RunState、Run／設定／Meta 磁碟存檔、遷移、非戰鬥節點、棋盤／戰鬥／完整 Run 模擬與主場景測試。
- `godot --headless --path . --log-file /tmp/arkham-grid-board-simulation.log --script res://tools/simulate_board.gd`：以現行起始池比較智慧手牌與權重隨機，輸出合法手牌／卡片、直接消線、盤面佔用與死盤率。
- `godot --headless --path . --log-file /tmp/arkham-grid-battle-batch.log --script res://tools/simulate_battles.gd`：跑八個遭遇，輸出勝率、HP／Sanity／MP、咒文觸發、時間壓力與敵人存活曲線。
- `godot --headless --path . --log-file /tmp/arkham-grid-run-simulation.log --script res://tools/simulate_runs.gd`：跨節點保留盤面、手牌、HP、Sanity、MP 與構築，輸出完整 Run 壓力曲線。
- 遊戲啟動時 `ContentRegistry.load_all()` 會再次驗證 schema、值域與引用；失敗時不會進入第一場戰鬥。
