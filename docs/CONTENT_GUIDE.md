# 內容新增指南

## 設計順序

新增內容前先確認：它服務哪種構築、在普通戰鬥中預期觸發幾次、MP 效率是否落在同 tier 範圍。規則未確認且會改變整體方向時，先登錄 `OPEN_QUESTIONS.md`。

## 方塊與效果格

- `blocks.json` 定義可用形狀與 1–4 的 `complexity`；實際構築單位是 `{slate_uid, shape_id, spell_id, effect_cell}` 完整石板。
- 起始石板在 `run_config.json.starter_slates` 固定配對。獎勵生成時才從合法形狀中選定配對與效果格；玩家取得後永久保存，抽牌與讀檔都不可重抽。
- 特殊形狀使用 `special: true`，同一特殊形狀在一局中只可取得一次。
- `weight` 控制跨手出現率，`smart_score_bonus` 控制盤面候選排名。低格數特殊形狀兩者都應偏低。
- 同一手在池內種類足夠時不重複形狀 ID；池少於手牌數時才允許 fallback 重複。
- `small`、`wide`、`tall`、`awkward`、`combo` 等 tags 用於內容篩選與未來連動，不直接決定咒文。
- 咒文 `balance_cost ≤ 9`／`10–13`／`≥ 14` 分別視為強度 1／2／3；強度越高，最低合法形狀複雜度越高。咒文可用 `allowed_shape_ids` 或 `blocked_shape_ids` 覆寫候選。

智慧手牌優先提供能直接消除或推進接近完成 Row／Col 的形狀，但不保證每手消除。開局與死盤後使用程序友善盤面。

## 咒文

所有可觸發效果都稱為「咒文」，不區分裝備、武器、祈禱或詛咒，也不配置 Row／Col 槽。

- `logic`：`attack`、`conditional_attack`、`support`、`status`。
- `effect_scope`：`single`、`spread`、`all`、`self`。
- `mp_cost`：一般約 2–8；範圍更廣、傷害更高或效果更穩定時應提高。
- `category_id`：必須引用七種咒文分類之一；同類咒文共用大型分類符文，範圍差異由角落標記補充。
- `icon_text`：僅保留相容與輔助文字用途，不再是主要辨識方式。
- 攻擊型使用 `damage`／`hit_count`；支援型使用 `armor_gain`／`heal_amount`；狀態使用 `status_effects_self`／`status_effects_target`。
- 常規咒文不得提供直接治療或再生；以護甲、堅硬、弱化敵人等方式處理戰鬥內防禦。
- `rarity`、`tier`、`balance_cost` 管理取得階段；`trigger_hint` 必須明確寫出 MP 成本與效果。

目前推薦的 combo 是同輪咒文鏈、範圍選擇、狀態搭配與效果格位置規劃。不要再新增依 Row／Col 裝備種類判斷的效果。

## MP、HP 與 Sanity

- 調查員原型：HP 80、Sanity 70/100、MP 70/100、AP 5。
- 每完成節點回復 50 MP；MP 不足時照常消除並觸發咒文，改以完整成本等量支付 Sanity。
- 正常情況由 MP 支付常規咒文；Sanity 同時承擔代付、死盤、事件與未來高代價特殊能力。
- 普通三選一不提供 HP／Sanity 回復或上限，也不提高 AP 上限。

## 敵人與意圖

- 目前敵人基礎攻擊為 10–15。多敵人 encounter 必須以總攻擊頻率及預期存活回合估算。
- `intent_pattern` 應以可讀的攻擊節奏為主，再穿插防禦、Sanity 攻擊、buff、debuff、`watch` 與 `brace`；不要只用提高單次傷害製造難度。
- `intent_rules` 可用 `turn_gte` 或 `hp_ratio_lte` 切換 pattern；規則依資料順序判定，預告與執行必須得到相同結果。
- `watch` 使用 `idle`，保留給需要喘息窗口的未來 pattern；`brace` 施加堅硬。
- 鎖定敵人死亡後會自動鎖定原始 encounter 順序中的第一名存活敵人。
- Encounter 最多 5 名敵人；速度越高越早行動，同速依生成順序。

## 獎勵

- 戰鬥獎勵會把資料候選轉成完整石板；同一咒文可出現在多種形狀，但同輪不得重複相同 `shape_id + spell_id + effect_cell`。
- 效果格使用 reward RNG 在生成候選時決定，並立即寫入 `pending_slate_rewards`；重新載入獎勵畫面不可改變候選。
- 菁英候選若仍有未取得特殊形狀，第一格保證為使用該形狀的完整石板；特殊形狀已取得後不再出現。
- 商店與事件不使用隱藏重配，必須在資料中指定可預覽的完整 `slate` grant。
- 玩家可以跳過三選一換取局內金錢。
- 獎勵 tier 由 encounter 整體強度決定，不放在敵人資料上。

## JSON 欄位

- `spell_categories.json`：分類 ID、圖示、分類色與顯示順序。
- `spells.json`：`category_id`、`logic`、`mp_cost`、`effect_scope`、效果數值、狀態、rarity、tier、tags、trigger_hint、balance_cost，以及選用的形狀覆寫。
- `blocks.json`：cells、complexity、tier、weight、tags、special、smart_score_bonus。
- `run_config.json.starter_slates`：穩定 `slate_uid`、shape、spell 與 effect cell。
- `enemies.json`：hp、attack、tier、speed、intent_pattern、intent_rules、sanity_pressure。
- `intents.json` action：damage、armor、sanity_damage、status_player、status_self、idle。

每次改內容後執行 `tools/validate_all.sh`，並將有意義的平衡變動記入 `BALANCE_LOG.md`。
