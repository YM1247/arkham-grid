# 局內成長與獎勵規格

## 資料責任

- `data/spells.json` 保存咒文的效果數值、`mp_cost`、`rarity`、`tier`、`balance_cost` 與可選升級鏈。
- `data/blocks.json` 只定義形狀、權重與盤面評分，不固定綁定咒文。
- `data/rewards.json` 保存 `spell`／`block` 候選、權重、最小勝場與 reward tier。
- `data/run_config.json` 保存起始形狀池、咒文池、每節點 MP 回復與 encounter 強度模型。
- JSON 決定內容與數值；`resources/effects/*.tres` 及其 GDScript 類別負責效果行為。

## 咒文與形狀成長

1. 咒文獎勵直接加入 `RunState.spell_pool_ids`。重複咒文代表更高的附著權重，不使用裝備槽或背包。
2. 每次抽方塊時獨立選擇形狀、旋轉、咒文與一個效果格，因此任何咒文都可能出現在任何形狀上。
3. 特殊形狀獎勵加入 `block_pool_ids`，每種只解鎖一次；已取得的特殊形狀不再進入候選池。
4. 星點、雙星與十字等特殊形狀使用較低 `weight` 與 `smart_score_bonus`，避免低格數形狀壟斷手牌。
5. 同一手在池內至少有三種形狀時不會重複 ID；只有池過小時才允許重複以補滿手牌。

目前咒文仍可用 `upgrade_from`／`upgrade_to` 描述內容關係，但舊裝備合成服務不在正式 Run 流程中。是否提供玩家主動合成咒文，應在未來另立企劃問題後才接入介面。

## 關卡強度與獎勵候選

強度值由敵人總 HP、總攻擊、tier 與 Sanity 壓力數量計算。候選器依最小勝場、reward tier、前置條件與內容 tier 篩選，再依 `weight` 無放回抽取三項。

- 同一次三選一不重複。
- 特殊形狀取得後不再出現；咒文可在後續戰鬥重複出現。
- 玩家可跳過整次獎勵換取局內金錢。
- 常規戰鬥獎勵不包含 HP、Sanity、AP 或其上限。

## 戰鬥統計與驗證

每場 `BattleResult.statistics` 與 `RunState.battle_reports` 記錄回合、Row／Col 消除、咒文觸發、MP 消耗、Sanity 代付、真正的咒文失敗、傷害、護甲、Sanity、死盤、結果、強度、reward tier 與獎勵。

固定 seed 模擬入口：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/simulate_battles.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/simulate_runs.gd
```

目前 10-run 基準為 80% 通關、0 次 HP／Sanity 死亡、2 次超時。這是自動策略回歸基準，仍需以實際遊玩驗證手感。
