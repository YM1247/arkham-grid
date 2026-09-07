# Arkham Grid

## 🎮 遊戲核心概念
這是一款結合「方塊放置（類似俄羅斯方塊）」與「RPG 戰鬥」的策略遊戲。玩家透過在 8x8 的棋盤上放置不同形狀的方塊，湊齊完整的橫列 (Row) 或直行 (Col) 來觸發裝備與技能，藉此與敵人戰鬥。

## 📐 棋盤與裝備規則 (8x8 Grid)
棋盤的行與列對應兩種正式裝備軸：
* **橫列 (Row 0-7)**：物理軸，可配置輸出或防禦道具。
* **直行 (Col 0-7)**：魔法軸，可配置治療、輔助、減益或魔法傷害。
* Weapon／Equipment／Prayer／Curse 四分類只作為資料相容與內容標籤，不限制固定索引區間。

## 🏗️ 系統架構設計 (Data-Driven Architecture)
本專案嚴格遵守物件導向與資料驅動設計，請在此架構下進行擴充，**切勿將資料寫死 (Hard-code) 於管理節點中**。

### 1. 方塊系統 (Block System)
* `BlockData` (Resource): 定義方塊形狀 (Vector2i 陣列) 與顏色。
* `Block` (Control): 讀取 `BlockData` 生成視覺，處理 Drag & Drop (包含抓取點偏移校正)。
* `GridCell` (Control): 棋盤單格，負責接收 Drop 數據並呼叫 Manager。
* `TableGenerator`: 負責生成 8x8 棋盤、檢查放置合法性、高亮預覽、消除判定，並發送 `row_activated` 與 `col_activated` 信號。

### 2. 戰鬥系統 (Battle System - Strategy Pattern)
* `BattleItem` (Resource): 所有道具的抽象基底，定義 `ItemType` 標籤與 `execute(target, user)` 虛擬函數。
* `EffectAttack` / `EffectSupport` 等: 繼承自 `BattleItem` 的具體邏輯實作。
* `BattleManager` (Node): 
  * 儲存 8x8 的裝備陣列 (`row_items`, `col_items`)。
  * 接收 TableGenerator 的消除信號。
  * 驗證欄位規則（例如 Row 0-3 只能裝 Weapon）。
  * 呼叫道具的 `execute()`，並傳入 Player 與 Enemy 實體。

## ✅ 當前開發進度 (Current State)
- [x] UI 佈局 (MarginContainer 安全邊距、左右區域比例)。
- [x] 方塊拖曳系統 (精準抓取偏移、無效區域裁切處理)。
- [x] 棋盤放置邏輯 (邊界與重疊檢查、動態高亮預覽)。
- [x] 消除演算法 (滿行/列判定、延遲 0.3 秒閃爍特效、資料重置)。
- [x] 信號發送與戰鬥大腦連線。
- [x] 基於 Resource 的策略模式裝備系統架構。
- [x] 多敵人、資料化意圖、狀態時序、目標範圍與勝敗規則。
- [x] 背包、裝備合成／配置、獎勵 tier 與特殊方塊成長。
- [x] 可重現程序地圖、完整 Run 狀態機、Boss、通關／失敗與重新開始。
- [x] 兩段低 Sanity、跨系統瘋狂效果、來源記錄與後果預覽。
- [x] 版本化內容註冊、完整引用驗證、資料化多選項事件、棋盤／戰鬥／完整 Run 批次基線、Run 磁碟存檔基礎、現行內容範本及 18 組自動測試。

## 開發強烈要求
- 你的任務不是自由開發一個遊戲，而是在現有框架下逐步將項目實現為可運行的原型
- 使用 Godot 4.X 以及 GDScript
- 妥善管理遊戲內數值，建立 /data/*.json 管理
- 先保證可運行，再優化增強
- 每一次提交都要詳細說明改了什麼、新增了什麼、如何實現與驗證
- 發現設計不清楚時，請先建立 docs/OPEN_QUESTIONS.md 紀錄，不要擅自修改核心方向
- 在 docs/ 下方開設 md 檔紀錄遊戲企劃的詳細文件、開發過程等
