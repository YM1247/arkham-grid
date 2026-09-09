# Arkham Grid

## 🎮 遊戲核心概念
這是一款結合方塊放置與 RPG 戰鬥的策略遊戲。玩家在 8x8 棋盤完成 Row／Col；被消除的咒文圖標格會支付 MP，MP 不足則支付等量 Sanity，再觸發咒文。

## 📐 棋盤與咒文規則 (8x8 Grid)
* 方塊形狀與咒文獨立抽取；每塊恰有一個效果格。
* Row／Col 交叉消除時，同一效果格只觸發一次。
* 所有效果一律稱為咒文，不存在裝備、武器、祈禱或詛咒分類與槽位。
* MP 不足仍會消除棋盤並觸發咒文，完整成本改由 Sanity 等量代付。

## 🏗️ 系統架構設計 (Data-Driven Architecture)
本專案嚴格遵守物件導向與資料驅動設計，請在此架構下進行擴充，**切勿將資料寫死 (Hard-code) 於管理節點中**。

### 1. 方塊系統 (Block System)
* `BlockData` (Resource): 定義方塊形狀、顏色，以及抽到手上後附著的咒文與效果格。
* `Block` (Control): 讀取 `BlockData` 生成視覺，處理 Drag & Drop (包含抓取點偏移校正)。
* `GridCell` (Control): 棋盤單格，負責接收 Drop 數據並呼叫 Manager。
* `TabletGenerator`: 負責棋盤、放置、預覽、消除，並發送 `spell_activated`。

### 2. 戰鬥系統 (Battle System - Strategy Pattern)
* `BattleItem` (Resource): 咒文的內部相容基底，定義 MP、範圍與 `execute(target, user)`。
* `EffectAttack` / `EffectSupport` 等: 繼承自 `BattleItem` 的具體邏輯實作。
* `BattleManager` (Node): 接收效果格咒文、支付 MP、解析目標並執行效果；不保存 Row／Col 裝備。

## ✅ 當前開發進度 (Current State)
- [x] UI 佈局 (MarginContainer 安全邊距、左右區域比例)。
- [x] 方塊拖曳系統 (精準抓取偏移、無效區域裁切處理)。
- [x] 棋盤放置邏輯 (邊界與重疊檢查、動態高亮預覽)。
- [x] 消除演算法 (滿行/列判定、延遲 0.3 秒閃爍特效、資料重置)。
- [x] 信號發送與戰鬥大腦連線。
- [x] 基於 Resource 的統一咒文策略架構。
- [x] 多敵人、資料化意圖、狀態時序、目標範圍與勝敗規則。
- [x] 咒文池、獎勵 tier、特殊形狀與效果格成長。
- [x] MP 100 上限、每節點回復 50、Sanity 代付與依強度／深度計算的戰鬥時間壓力。
- [x] 可重現 10 層程序地圖、完整 Run 狀態機、Boss、通關／失敗與重新開始。
- [x] 消除支付預覽、咒文圖例、條件式敵人意圖與菁英特殊形狀候選保底。
- [x] 兩段低 Sanity、跨系統瘋狂效果、來源記錄與後果預覽。
- [x] 版本化內容註冊、完整引用驗證、資料化非戰鬥節點、棋盤／戰鬥／完整 Run 批次基線、Run／設定／Meta 磁碟存檔、現行內容範本及 19 組自動測試。

## 開發強烈要求
- 你的任務不是自由開發一個遊戲，而是在現有框架下逐步將項目實現為可運行的原型
- 使用 Godot 4.X 以及 GDScript
- 妥善管理遊戲內數值，建立 /data/*.json 管理
- 先保證可運行，再優化增強
- 每一次提交都要詳細說明改了什麼、新增了什麼、如何實現與驗證
- 發現設計不清楚時，請先建立 docs/OPEN_QUESTIONS.md 紀錄，不要擅自修改核心方向
- 在 docs/ 下方開設 md 檔紀錄遊戲企劃的詳細文件、開發過程等
- 定期維護git版本，保持推送變更到github
