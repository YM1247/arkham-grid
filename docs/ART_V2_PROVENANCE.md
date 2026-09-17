# Q 版像素美術更新

本輪以內建圖像生成流程建立新版原創素材，採用固定的午夜藍、石板藍、青綠、羊皮紙、黃銅與珊瑚色盤，並在 Godot 中使用 nearest filter。

- `assets/art/characters/investigator_chibi.png`：Q 版調查員；由純黑背景來源去背。
- `assets/art/characters/investigator_chibi_opaque.png`：以既有調查員為編修目標，重新生成純綠去背來源後使用本地 chroma-key 工具輸出；角色本體改為完全實色，僅輪廓保留必要的透明邊緣。
- `assets/art/characters/cultist_chibi.png`：Q 版邪教徒；供後續敵人立繪逐張替換時使用。
- `assets/art/backgrounds/ritual_chibi_stage.png`：Q 版儀式室戰鬥舞台。
- `assets/art/backgrounds/ritual_arena_v2.png`：本輪戰鬥用的 2.5D 儀式圓台與前景石板桌背景；以內建圖像生成流程產生的原創素材，不含既有作品角色、標誌或素材。
- `assets/art/backgrounds/observatory_map_v2.png`：與戰鬥場共用像素比例、色盤與光向的浮空觀星城；中央保留低對比區域，供主頁與十層路線地圖共用。

生成提示重點：16-bit、粗顆粒方形像素、3 頭身、粗深色輪廓、平面 8–10 色陰影、禁止漸層、禁止反鋸齒、禁止文字與浮水印。角色來源採平面色去背後輸出透明 PNG。

`ritual_arena_v2.png` 的提示另明定：橫向 16:9、克蘇魯風 Q 版儀式室、後景拱門與月光、中景環形儀式地磚、下方獨立書桌／石板桌、午夜藍與黃銅色盤、前中後景明確分層；最終在 Godot 內以 nearest filter 顯示。

`observatory_map_v2.png` 以 `ritual_arena_v2.png` 作 style-transfer 參考，要求同一製作規格的 32-bit 粗像素、午夜藍／石板藍／象牙雲層／舊黃銅／暗酒紅色盤，並排除舊港口、寫實細節、道路、節點、文字與 UI。

`investigator_chibi_opaque.png` 使用內建圖片編修流程：固定原角色的姿勢、剪影、比例、表情、裝備與像素色盤，要求所有可見角色像素為實色；來源背景指定為單一 `#00ff00`，再以 `remove_chroma_key.py` 的 soft matte、despill 與 12／220 透明門檻移除背景。未採用首次產生、含烘焙棋盤格的失敗版本。

## 後續資產

現有六種敵人的專屬新版立繪仍應逐張替換，需保留各敵人剪影與辨識差異；在此之前，以統一 UI 色盤、像素化舞台和 Q 版調查員先建立主視覺基調。
