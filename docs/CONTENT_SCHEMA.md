# 內容 Schema 與相容性規範

## 現行邊界

正式資料位於 `data/*.json`，根節點必須是物件並包含 `schema_version`。目前 runtime 只接受 schema v1；`ContentRegistry` 與 `tools/validate_data.py` 都會拒絕版本不符、值域錯誤或引用失效的內容。

目前已註冊的內容清單是方塊、道具、敵人意圖、敵人、遭遇、獎勵與事件。可複製範例位於 `data/templates/`。玩家、Run、地圖與 Sanity 是系統設定文件，不把整份文件當成可重複內容項目。

事件依 `CONTENT-006` 使用 `events.json`：每筆事件至少兩個選項，選項以 `costs`／`results` 定義 HP、Sanity、金錢的非負整數變化。商店與休息仍以地圖 `content_id` 進入佔位流程；在 `CONTENT-007` 決定互動結構前不建立正式 schema。

## ID 規則

- ID 使用小寫 snake_case，只表達內容身份，不嵌入顯示名稱、數值、稀有度或排序。
- ID 一旦進入可保存的 RunState 或已發布資料，就不可重新指派給另一個內容概念。
- 顯示名稱可修改，ID 不跟著改名。真的必須改 ID 時，需視為資料遷移，而不是普通內容編輯。
- 刪除被其他內容、地圖或存檔引用的 ID 前，必須先移除引用並提供遷移或明確的不相容版本策略。
- 升級鏈與獎勵前置只可引用穩定 ID，必須保持無循環，並由驗證器檢查。

## 欄位生命週期

1. 新增欄位優先採可選欄位與明確預設值，並同步更新兩套驗證器、runtime builder、範本與資料說明。
2. 欄位要廢棄時，先停止新內容使用並在文件標為 deprecated；至少保留一個 schema 遷移週期的讀取相容。
3. 移除欄位、改變既有欄位語意或型別、改變 ID 指向，皆屬 breaking change，必須提高 `schema_version`。
4. `item_type` 是目前已知的相容欄位；正式 slot 規則以 `axis_type` 的 `physical`／`magic` 為準。在實作 schema 遷移前仍保留並驗證 `item_type`。
5. 不允許 loader 對未知 enum、intent action、效果行為或失效引用靜默 fallback；資料錯誤應在進入遊戲流程前失敗。

## Schema 升版流程

1. 先新增舊版 fixture 與預期新版 fixture，寫出可重現遷移測試。
2. 實作純資料轉換，禁止在遷移期間載入場景或執行遊戲效果。
3. 轉換完成後以新版 `ContentRegistry` 驗證，再建立 runtime Resource。
4. 同步更新所有正式 JSON、`data/templates/`、`data/README.md`、本文件與開發紀錄。
5. 執行 Python 驗證、全部 Godot headless 測試、棋盤模擬與戰鬥批次基線。
6. 若版本已發布，保留原始存檔備份；轉換失敗不可覆寫來源。

## RunState 相容性

`RunState.schema_version` 和內容文件版本是不同責任：前者描述存檔結構，後者描述內容資料。還原順序應是「解析存檔 → 結構遷移 → 內容 ID 遷移 → `validate_run_state_references()` → 套用 runtime」。

目前只有記憶體快照。`SAVE-004` 已決定正式版本採自動遷移並保留失敗備份；遷移器尚未接線前維持 fail-fast，任何方塊、道具、獎勵、事件、Sanity 效果或地圖引用失效都拒絕還原，不自動替換或丟棄。
