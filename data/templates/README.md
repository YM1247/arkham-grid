# 內容範本

這裡的 `*.example.json` 是可複製的 schema v1 範例，不會被 `ContentRegistry` 載入。請只複製 `entries` 內的物件到對應正式檔案，換成新的穩定 ID，再執行資料驗證與 headless 測試。方塊只定義形狀與複雜度、咒文必須指定分類；實際取得內容一律是永久綁定的完整石板。

- `block.example.json` → `data/blocks.json`
- `spell.example.json` → `data/spells.json`
- `intent.example.json` → `data/intents.json`
- `enemy.example.json` → `data/enemies.json`
- `encounter.example.json` → `data/encounters.json`
- `reward.example.json` → `data/rewards.json`
- `event.example.json` → `data/events.json`
- `shop.example.json` → `data/shops.json`
- `rest.example.json` → `data/rests.json`

事件、商店與休息共用選項 schema；可用資源鍵為 HP、Sanity、MP 與金錢。
