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

咒文 tooltip 顯示 MP 成本與 MP 不足時的等量 Sanity 代付；瘋狂「儀式執著」會讓咒文成本增加 1，代付時也包含增加後的完整成本。戰鬥 HUD 顯示目前階段、效果與最近一次理智變化；RunState 保存完整來源歷史。正式 Sanity 來源包含咒文代付、死盤、敵人意圖、事件與休息。

## 完整 Run 基準

基準路徑共 6 場戰鬥，Boss 前有休息。一般情況先支付 MP，只有 MP 不足才讓 Sanity 成為備用燃料。2026-09-08 多種子測試中，第五、六場部分種子的平均代付達 5–6 次，後續需以消除前支付預覽避免玩家在連鎖中意外耗盡 Sanity。

可重跑：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/arkham-grid-sanity.log --path . --script res://tools/simulate_sanity.gd
```
