# 內容範本

這裡的 `*.example.json` 是可複製的 schema v1 範例，不會被 `ContentRegistry` 載入。請只複製 `entries` 內的物件到對應正式檔案，換成新的穩定 ID，再執行資料驗證與 headless 測試。

- `block.example.json` → `data/blocks.json`
- `item.example.json` → `data/items.json`
- `intent.example.json` → `data/intents.json`
- `enemy.example.json` → `data/enemies.json`
- `encounter.example.json` → `data/encounters.json`
- `reward.example.json` → `data/rewards.json`
- `event.example.json` → `data/events.json`

商店與休息目前仍只有地圖內容 ID 和佔位結算；正式資料範本等待 `CONTENT-007` 決定是否使用專用互動結構。
