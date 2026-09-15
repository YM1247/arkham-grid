# Q 版像素美術更新

本輪以內建圖像生成流程建立新版原創素材，採用固定的午夜藍、石板藍、青綠、羊皮紙、黃銅與珊瑚色盤，並在 Godot 中使用 nearest filter。

- `assets/art/characters/investigator_chibi.png`：Q 版調查員；由純黑背景來源去背。
- `assets/art/characters/cultist_chibi.png`：Q 版邪教徒；供後續敵人立繪逐張替換時使用。
- `assets/art/backgrounds/ritual_chibi_stage.png`：Q 版儀式室戰鬥舞台。

生成提示重點：16-bit、粗顆粒方形像素、3 頭身、粗深色輪廓、平面 8–10 色陰影、禁止漸層、禁止反鋸齒、禁止文字與浮水印。角色來源採平面色去背後輸出透明 PNG。

## 後續資產

現有六種敵人的專屬新版立繪仍應逐張替換，需保留各敵人剪影與辨識差異；在此之前，以統一 UI 色盤、像素化舞台和 Q 版調查員先建立主視覺基調。
