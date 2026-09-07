# 局內成長與獎勵規格

## 資料責任

- `data/items.json` 保存 `rarity`、`tier`、`balance_cost`、`upgrade_from`、`upgrade_to` 與 `combine_count`；runtime `BattleItem` 只承接資料，不自行推導升級數值。
- `data/rewards.json` 保存候選權重、最小勝場、最小 reward tier 與解鎖引用。
- `data/run_config.json.difficulty_model` 保存 encounter 強度公式權重、reward tier 門檻與跳過獎勵所得金錢。
- 效果行為仍由 `.tres` 原型及其 GDScript 策略負責。

## 裝備取得、合成與配置

1. 道具獎勵先加入 `RunState.item_inventory`，不直接覆蓋裝備槽。
2. 若同一 ID 的數量達 `combine_count`，依 `upgrade_to` 消耗舊道具並產生一件升級道具；沒有升級鏈的重複道具保留在背包。
3. 獎勵後進入戰鬥外配置畫面，只列出相容軸的 8 個槽位，tooltip 同時顯示目前裝備與新裝備的完整效果、稀有度、tier 與 balance cost。
4. 玩家可以不替換，保留道具在背包後繼續前進。

目前第一批合成鏈為：左輪手槍 → 銘刻左輪、防彈背心 → 強化防彈背心、暗影刺 → 深淵暗影刺；兩件 Tier 1 合成一件 Tier 2。新增鏈時必須在 JSON 提供最終數值。

資料驗證會要求升級前後雙向引用一致、軸與舊分類不變、tier 上升、rarity 不下降，並拒絕循環升級鏈。

## 關卡強度與獎勵候選

強度值由敵人總 HP、總攻擊、tier 與 Sanity 壓力數量計算。公式係數與 reward tier 門檻由 `run_config.json` 提供。相同 encounter 資料必定得到相同強度。

候選器依序套用最小勝場、reward tier、解鎖引用、內容稀有度／方塊 tier，之後依 `weight` 無放回抽取三項。同一次候選不重複；同一內容可在後續戰鬥再次出現。固定 seed 與相同 RunState 會得到相同候選。

玩家可跳過整次獎勵換取局內金錢；普通戰鬥獎勵不包含 HP、Sanity、AP 或其上限。

## 戰鬥統計

每場 `BattleResult.statistics` 與 `RunState.battle_reports` 記錄：回合數、Row／Col 消除數、造成傷害、承受傷害、護甲抵擋、取得護甲、Sanity 消耗、死盤次數、結果、關卡強度、reward tier 與最後獎勵。

固定六場報告可用以下命令重建：

```bash
godot --headless --path . --script res://tools/generate_balance_report.gd
```

## 棋盤成長入口

- `BOARD-001`：每手前一張智慧方塊優先直接消除；沒有直接消除時，必須能推進接近完成的 Row／Col。
- `BOARD-002`：開局與死盤後的友善盤面由 JSON 參數控制的程序生成器建立，不再使用固定座標模板。
- `BOARD-004`：特殊方塊可重複取得；方塊池保留重複 ID，每一份都增加該方塊的總抽取權重。獎勵 tooltip 顯示取得後持有份數。

依 `BOARD-005`、`BOARD-006`，抽入手牌時由系統決定方塊方向，玩家不能手動旋轉；回合末保留未使用手牌及方向，下一回合只補足缺額。棄置或指定保留能力只由未來特殊道具／效果提供。
