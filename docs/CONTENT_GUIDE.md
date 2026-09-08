# 內容新增指南

## 設計順序

新增內容前先確認：它服務哪種構築、在普通戰鬥中預期觸發幾次、MP 效率是否落在同 tier 範圍。規則未確認且會改變整體方向時，先登錄 `OPEN_QUESTIONS.md`。

## 方塊與效果格

- `blocks.json` 只定義形狀。每次抽取再獨立附上一個隨機咒文與一個隨機效果格。
- 普通形狀只放起始池；獎勵形狀必須有 `special: true`，同一特殊形狀只解鎖一次。
- `weight` 控制跨手出現率，`smart_score_bonus` 控制盤面候選排名。低格數特殊形狀兩者都應偏低。
- 同一手在池內種類足夠時不重複形狀 ID；池少於手牌數時才允許 fallback 重複。
- `small`、`wide`、`tall`、`awkward`、`combo` 等 tags 用於內容篩選與未來連動，不直接決定咒文。

智慧手牌優先提供能直接消除或推進接近完成 Row／Col 的形狀，但不保證每手消除。開局與死盤後使用程序友善盤面。

## 咒文

所有可觸發效果都稱為「咒文」，不區分裝備、武器、祈禱或詛咒，也不配置 Row／Col 槽。

- `logic`：`attack`、`conditional_attack`、`support`、`status`。
- `effect_scope`：`single`、`spread`、`all`、`self`。
- `mp_cost`：一般約 2–8；範圍更廣、傷害更高或效果更穩定時應提高。
- `icon_text`：1–2 個可見字元；同一批常用咒文應採不同圖標，並確認在手牌與盤面都可辨識。
- 攻擊型使用 `damage`／`hit_count`；支援型使用 `armor_gain`／`heal_amount`；狀態使用 `status_effects_self`／`status_effects_target`。
- 常規咒文不得提供直接治療或再生；以護甲、堅硬、弱化敵人等方式處理戰鬥內防禦。
- `rarity`、`tier`、`balance_cost` 管理取得階段；`trigger_hint` 必須明確寫出 MP 成本與效果。

目前推薦的 combo 是同輪咒文鏈、範圍選擇、狀態搭配與效果格位置規劃。不要再新增依 Row／Col 裝備種類判斷的效果。

## MP、HP 與 Sanity

- 調查員原型：HP 80、Sanity 70/100、MP 70/100、AP 5。
- 每完成節點回復 35 MP；MP 不足時照常消除並觸發咒文，改以完整成本等量支付 Sanity。
- 正常情況由 MP 支付常規咒文；Sanity 同時承擔代付、死盤、事件與未來高代價特殊能力。
- 普通三選一不提供 HP／Sanity 回復或上限，也不提高 AP 上限。

## 敵人與意圖

- 目前敵人基礎攻擊為 10–15。多敵人 encounter 必須以總攻擊頻率及預期存活回合估算。
- `intent_pattern` 應以可讀的攻擊節奏為主，再穿插防禦、Sanity 攻擊、buff、debuff、`watch` 與 `brace`；不要只用提高單次傷害製造難度。
- `watch` 使用 `idle`，保留給需要喘息窗口的未來 pattern；`brace` 施加堅硬。
- 鎖定敵人死亡後會自動鎖定原始 encounter 順序中的第一名存活敵人。
- Encounter 最多 5 名敵人；速度越高越早行動，同速依生成順序。

## 獎勵

- `type: "spell"`：直接加入咒文池；允許重複，以提高附著機率。
- `type: "block"`：只用於特殊形狀；已取得者不再進入候選。
- 同一次三選一無放回抽取，不重複內容；玩家可以跳過換金錢。
- 獎勵 tier 由 encounter 整體強度決定，不放在敵人資料上。

## JSON 欄位

- `spells.json`：`icon_text`、`logic`、`mp_cost`、`effect_scope`、效果數值、狀態、rarity、tier、tags、trigger_hint、balance_cost。
- `blocks.json`：cells、tier、weight、tags、special、smart_score_bonus。
- `enemies.json`：hp、attack、tier、speed、intent_pattern、sanity_pressure。
- `intents.json` action：damage、armor、sanity_damage、status_player、status_self、idle。

每次改內容後執行 `tools/validate_all.sh`，並將有意義的平衡變動記入 `BALANCE_LOG.md`。
