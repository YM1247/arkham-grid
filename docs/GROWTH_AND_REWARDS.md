# 局內成長與獎勵規格

## 資料責任

- `data/spells.json` 保存咒文的效果數值、`mp_cost`、`rarity`、`tier`、`balance_cost` 與可選升級鏈。
- `data/blocks.json` 定義形狀、1–4 複雜度、權重與盤面評分；runtime 石板再引用形狀。
- `data/rewards.json` 保存 `spell`／`block` 候選、權重、最小勝場與 reward tier。
- `data/run_config.json` 的 `starter_slates` 保存起始八塊完整石板；舊形狀／咒文清單只供目前模擬器相容。
- JSON 決定內容與數值；`resources/effects/*.tres` 及其 GDScript 類別負責效果行為。

## 咒文與形狀成長

1. 構築單位為 `{slate_uid, shape_id, spell_id, effect_cell}`；抽牌只隨機旋轉完整石板，三者不重配。
2. 咒文強度由 `balance_cost` 分成 1／2／3，形狀以 `complexity` 1–4 表示操作難度；預設要求形狀複雜度不低於咒文強度，並以距離加權。
3. `allowed_shape_ids`／`blocked_shape_ids` 可覆寫公式。相同咒文可出現在不同合法形狀，同一輪不出現完全相同的咒文＋形狀。
4. 特殊形狀每種只取得一次；菁英獎勵保證至少一個尚未取得的合法特殊形狀候選。
5. 星點、雙星與十字等特殊形狀使用較低權重與智慧加成；同一手仍優先避免重複形狀。

目前咒文仍可用 `upgrade_from`／`upgrade_to` 描述內容關係，但舊裝備合成服務不在正式 Run 流程中。是否提供玩家主動合成咒文，應在未來另立企劃問題後才接入介面。

## 關卡強度與獎勵候選

強度值由敵人總 HP、總攻擊、tier 與 Sanity 壓力數量計算。候選器先選合法咒文，再依配對公式選形狀與效果格，生成三張完整石板卡。候選存入 `pending_slate_rewards`，讀檔不得重抽。

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
