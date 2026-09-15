# 美術資產來源與生成紀錄

## 使用範圍

Phase 17.1 的角色與背景由 OpenAI 內建 ImageGen 於 2026-09-14／15 生成，皆為本專案提示詞產生的原創素材；提示詞明確要求不得仿製既有作品、角色或藝術家。最終圖片置於 `assets/art/`，角色採透明 PNG，Godot 以 nearest filter 顯示。

`assets/art/source_chroma/` 保存生成器的原始角色／透明疊層輸出。若原檔已含 Alpha，直接保留原始透明資訊；純綠底輸出則使用 ImageGen 技能隨附的 `remove_chroma_key.py`，以 border 自動取色、soft matte 與 despill 轉為透明 PNG。沒有使用網路素材、第三方角色或外部遊戲資產。

## 角色共同提示規格

每張角色皆以單一資產、單次生成，使用以下共同要求；中段的角色描述依下表替換：

> Create one original full-body [player/enemy] sprite for a cosmic-horror puzzle roguelike, matching a restrained 32-bit pixel-art game cast. [CHARACTER DESCRIPTION] Readable at about 96x128 in-game, chunky intentional pixels, restrained palette of charcoal, aged teal, tarnished brass, muted burgundy, pale warm rim light from upper left, strong silhouette, eerie but no gore. Single isolated character centered with generous empty padding. Flat pure chroma green #00FF00 background, uniform edge to edge; do not use green anywhere on the character. No floor, no shadow, no scenery, no border, no text, no logo, no watermark. Original design, not based on any existing franchise or artist.

| ID | 角色描述摘要 | 原始檔 | 最終檔 |
| --- | --- | --- | --- |
| investigator | determined 1920s Taiwanese investigator；長外套、筆記側包、黃銅提燈，朝右 3/4 警戒姿勢 | `source_chroma/investigator.png` | `characters/investigator.png` |
| abyss_thrall | gaunt amphibious humanoid servant；藍黑皮膚、藤壺狀骨質、佝僂長指，朝左 | `source_chroma/abyss_thrall.png` | `characters/abyss_thrall.png` |
| rotting_hound | lean supernatural graveyard hunting beast；象牙骨板、藍黑皮、琥珀眼、低伏撲擊姿勢 | `source_chroma/rotting_hound.png` | `characters/rotting_hound.png` |
| lightless_priest | tall masked ritual priest；無口裂紋面具、分層長袍、黃銅香爐，朝左施法 | `source_chroma/lightless_priest.png` | `characters/lightless_priest.png` |
| grave_cultist | cemetery caretaker turned occult zealot；石質半面具、舊大衣、鏟槍與酒紅儀式布 | `source_chroma/grave_cultist.png` | `characters/grave_cultist.png` |
| warped_acolyte | distorted ritual attendant；不對稱長袍、陰影帶狀觸肢、黃銅聖物與漂浮瓷片 | `source_chroma/warped_acolyte.png` | `characters/warped_acolyte.png` |
| abyss_guard | massive deep-sea temple sentinel；石金屬重甲、閉合頭盔、矩形儀式盾與錨形鈍器 | `source_chroma/abyss_guard.png` | `characters/abyss_guard.png` |

獵犬與守衛提示分別把建議顯示尺寸調整為約 `112x96` 與 `124x140`，並以 creature／boss enemy 描述取代 character；其餘共同限制不變。

## 背景提示詞

### `backgrounds/ritual_far.png`

> Create an original ultra-wide 16:9 environment background for a cosmic-horror pixel-art puzzle roguelike battle. Far layer only: a vast underground ritual chamber carved from black basalt, distant cyclopean arches, a huge sealed circular gate behind the center, faint amber braziers far away, shafts of dusty cold blue light, symmetrical enough to keep a game board readable in the middle. No people, no creatures, no foreground objects, no UI, no symbols resembling a known franchise, no text, no logo, no watermark. Handcrafted high-detail 32-bit pixel art with intentional crisp pixels, restrained charcoal, aged teal, tarnished brass and muted burgundy palette, upper-left warm light, low contrast in the center for gameplay readability, tileable-feeling edges. Original design, not based on any existing artist or work.

### `backgrounds/ritual_mid.png`

> Create one original ultra-wide 16:9 transparent-ready midground overlay for a cosmic-horror pixel-art ritual chamber game scene. Mid layer only: broken basalt columns at the far left and far right, hanging chains, two small tarnished-brass braziers with muted amber flame, thin curling blue-gray fog wisps around the lower third; leave the entire central 55 percent mostly empty and fully chroma green for a game board. Handcrafted high-detail 32-bit pixel art, crisp intentional pixels, palette charcoal, aged teal, tarnished brass, muted burgundy, warm light from upper left. Everything not part of the overlay must be a flat uniform pure chroma green #00FF00 reaching the image edges; do not use green in the artwork. No people, creatures, floor, distant wall, UI, text, logo, watermark. Original design, not based on any existing work.

### `backgrounds/ritual_fore.png`

> Create one original ultra-wide 16:9 transparent-ready foreground overlay for a cosmic-horror pixel-art ritual chamber game scene. Foreground layer only: very dark chipped stone floor lip along the bottom edge, a few close ritual candles and scattered paper talismans in the bottom corners, subtle curling smoke at the extreme sides; keep the center and upper 70 percent completely clear for gameplay. Handcrafted high-detail 32-bit pixel art, crisp intentional pixels, palette charcoal, aged teal, tarnished brass, muted burgundy, pale warm light from upper left. Everything not part of the foreground must be a flat uniform pure chroma green #00FF00 reaching every uncovered edge; do not use green in the artwork. No people, creatures, walls, UI, text, logo, watermark. Original design, not based on any existing work.

### `backgrounds/harbor_map.png`

> Create an original ultra-wide 16:9 title-and-map background for a cosmic-horror pixel-art puzzle roguelike. A rain-soaked 1920s East Asian harbor city seen from above and at distance, crooked roofs descending toward a black sea, a faint impossible constellation reflected in flooded alleys, one warm lantern path suggesting an expedition route. Reserve calm dark negative space through the center for title or map nodes. No people, no creatures, no UI, no written words, no logo, no watermark. Handcrafted high-detail 32-bit pixel art with crisp intentional pixels, restrained charcoal, midnight blue, aged teal, tarnished brass and muted burgundy palette, moody mist, cinematic depth, original design not based on any existing franchise or artist.

## 顯示與效能規則

- 原始解析度只存一份，Godot 以 TextureRect 縮放，不建立多份同內容貼圖。
- 所有像素圖使用 nearest filter；背景為單張遠景加兩張透明疊層，霧與暗角由低數量、無貼圖的程式繪製完成。
- 本輪不宣稱這些靜態圖是逐格動畫；待機、蓄力、命中與受擊由位移、縮放、閃白及淡色完成。
