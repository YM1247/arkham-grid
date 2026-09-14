# Phase 12 戰鬥系統規格

## 回合結算時序

一個完整敵我輪固定依序執行：

1. 玩家回合開始：回合數加一；若超過本場時限，先扣除遞增 Sanity，再清空玩家護甲、補滿 AP、更新所有敵人目前意圖。
2. 玩家放置方塊；完整 Row／Col 消除，被清除的咒文圖標格支付 MP，MP 不足時改付等量 Sanity，再觸發咒文；玩家主動結束回合。
3. 玩家回合末：觸發玩家再生與中毒，立即檢查戰鬥結果。
4. 敵人依隱藏 `speed` 由高至低逐一行動；同速依生成順序。
5. 每名敵人行動前清空自己的舊護甲，執行自己的目前意圖，再觸發自己的再生與中毒並前進意圖索引。
6. 所有敵人完成後，玩家與所有敵人的狀態統一衰減 1。
7. 檢查戰鬥結果，延遲 0.4 秒後進入下一個玩家回合。

任何結算邊界都依序判定 Sanity 失敗、HP 失敗、勝利；因此同一結算序列敵我同時死亡時玩家失敗。

## 敵人意圖

`data/intents.json` 定義意圖顯示名稱、通用 action 與數值；`enemies.json.intent_pattern` 引用基礎循環，`intent_rules` 可依敵人 HP 比例或戰鬥回合切換循環。每名敵人持有獨立 `EnemyIntentState`，不共用全域索引。

| 意圖 | Action | 原型數值 |
| --- | --- | --- |
| attack | damage | 攻擊力 × 1.0 |
| heavy_attack | damage | 攻擊力 × 1.5 |
| guard | armor | 護甲 8 |
| sanity_attack | sanity_damage | Sanity 傷害 5 |
| debuff_player | status_player | 玩家虛弱 2 |
| buff_self | status_self | 自身力量 2 |
| watch | idle | 不造成直接傷害 |
| brace | status_self | 自身堅硬 2 |

UI 只顯示意圖類型，不顯示速度或精確數值。未知 intent ID、未知 action 或錯誤引用會在資料驗證或戰鬥啟動時失敗，不退回普通攻擊。

條件式意圖在執行與預告時使用同一規則解析器。規則依資料順序取第一個符合者；現行條件為 `turn_gte` 與 `hp_ratio_lte`，因此玩家可從回合數與敵人血量理解轉換原因。

## 目標解析

- `single`：目前鎖定且存活的敵人。
- `spread`：鎖定目標與存活敵人序列中左右各一名，跳過死亡空位。
- `all`：全部存活敵人。
- `self`：玩家自身。
- 鎖定目標死亡後，自動鎖定 encounter 原始順序中的第一名存活敵人；同一次消除後續咒文會使用新鎖定。

`TargetResolver` 是唯一的敵人目標解析入口。`BattleEffectContext` 提供使用者、主要目標、目標集合、效果格、本回合咒文觸發紀錄及戰鬥狀態；條件效果不得直接寫成 `BattleManager` 的內容 ID 特例。

## 效果格與 MP

- 每張石板恰有一格帶分類符文；形狀、咒文與標記位置由 `slate_uid` 永久綁定並同步旋轉。同類咒文共用分類圖標，範圍由角標區分。
- 同一格同時被 Row 與 Col 清除時只結算一次。
- 咒文依 `mp_cost` 支付 MP；MP 不足時改以完整成本等量支付 Sanity，仍照常觸發並獨立記錄代付次數。
- 調查員原型 MP 為 70/100；每完成一個地圖節點回復 50。
- 放置預覽會依實際 Row 後 Col 的去重順序列出將觸發的咒文，並計算 MP 與 Sanity 支付；可能耗盡 Sanity 時顯示紅色警告。

## 戰鬥時限

`EncounterDifficultyCalculator` 先以敵人總 HP、攻擊、tier 與精神壓力計算強度，再結合節點深度得到本場回合時限。現行時限介於 4–7 個玩家回合；節點每深入 2 層會收緊 1 回合，但高強度 encounter 可獲得額外回合。

超過時限後，第 1／2／3… 個逾時回合分別扣除 2／4／6… Sanity。扣除發生在玩家取得 AP 前，可能直接造成戰敗；HUD 顯示目前回合、時限及下一次壓力。

## 敵人實例與 UI

- Encounter 最多 5 名敵人；資料驗證與 runtime 都會拒絕超額 encounter。
- `EnemyFactory` 建立敵人與獨立意圖狀態。
- `EnemyRosterPresenter` 只在 roster 成員改變時建立／移除 `EnemyCard`。
- HP、護甲、狀態、意圖與鎖定更新只刷新既有卡片，不重建控制項。

## 驗證

`tests/test_runner.gd` 涵蓋意圖索引、條件式意圖、速度順序、自動換鎖、效果格交叉去重、MP／Sanity 支付、戰鬥時限、咒文圖標、狀態時序、勝敗、五敵人 UI 穩定性與完整流程 smoke test。
