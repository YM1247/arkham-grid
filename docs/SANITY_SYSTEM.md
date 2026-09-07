# Sanity 與瘋狂系統

## 資料責任

- `data/sanity.json`：階段門檻、效果池組合、數值、來源顯示名稱與模擬基準。
- `resources/sanity/*.tres`：魔法成本、死盤懲罰、攻擊與護甲修正的行為種類。
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

魔法欄位 tooltip 顯示調整後成本、施放後 Sanity、跨越門檻時新增的瘋狂，以及歸零失敗。戰鬥 HUD 顯示目前階段、效果與最近一次變化；RunState 保存完整來源歷史。正式來源包含魔法、死盤、敵人意圖、事件與休息。

## 完整 Run 基準

基準路徑共 6 場戰鬥，Boss 前有休息。休息前 5 場各使用魔法 2 次，整趟發生 1 次死盤與 2 次精神攻擊：`70 - 30 - 10 - 12 = 18`。驗收區間為 15–55，因此玩家會經歷兩段低理智但仍有機會抵達休息點；休息後恢復 100，再承受 Boss 戰的壓力。

可重跑：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/arkham-grid-sanity.log --path . --script res://tools/simulate_sanity.gd
```
