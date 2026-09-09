# Sanity 與瘋狂系統

## 資料責任

- `data/sanity.json`：階段門檻、效果池組合、數值、來源顯示名稱與模擬基準。
- `resources/sanity/*.tres`：咒文 MP 成本、死盤懲罰、攻擊與護甲修正的行為種類。
- `SanityRuleEngine`：依 Run seed 決定效果順序、處理不可重複疊加、解除、預覽與數值彙整。
- `Entity.change_sanity(delta, source)`：所有理智增減的唯一入口；保留實際變化、前後值與來源。

## 階段

| 階段 | Sanity | 同時生效效果 |
| --- | ---: | ---: |
| 穩定 | 46–100 | 0 |
| 不安 | 26–45 | 1 |
| 崩解 | 1–25 | 2 |
| 失敗 | 0 | Run 失敗 |

理智回升超過對應門檻時，最後加入的效果會依序解除。效果可疊加，但同一 ID 不會重複。

## 資訊揭露與來源

咒文 tooltip 顯示 MP 成本與 MP 不足時的等量 Sanity 代付；消除預覽會先列出咒文及總支付，致死風險以紅字警告。瘋狂「儀式執著」會讓咒文成本增加 1，代付時也包含增加後的完整成本。戰鬥 HUD 顯示目前階段、效果、戰鬥回合時限與最近一次理智變化；RunState 保存完整來源歷史。正式 Sanity 來源包含咒文代付、戰鬥逾時、死盤、敵人意圖、事件與休息。

## 戰鬥時間壓力

每場戰鬥依敵人總強度與地圖深度計算 4–7 回合的時限。越後段的節點時限越嚴格；超過後每個玩家回合依序扣除 2、4、6… Sanity。此壓力不阻止玩家繼續操作，但會讓拖延與過度防守快速變得危險。

## 完整 Run 基準

10 層基準路徑共 7 場戰鬥，Boss 前有休息。一般情況先支付 MP，只有 MP 不足才讓 Sanity 成為備用燃料。2026-09-09 的 40 Run 測試中，平均逾時 3.02 回合、因時間壓力損失 9.5 Sanity；完整 Run 通關率為 77.5%，HP／Sanity 失敗為 5／4。

可重跑：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/arkham-grid-sanity.log --path . --script res://tools/simulate_sanity.gd
```
