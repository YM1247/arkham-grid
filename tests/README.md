# 測試

執行全部自動測試與核心迴圈 smoke test：

```bash
godot --headless --path . --log-file /tmp/arkham-grid-tests.log --script res://tests/test_runner.gd
```

目前共有 18 suites，涵蓋資料註冊與引用、RunState 序列化與內容引用防護、磁碟存檔／備份／遷移／RNG 延續、資料化事件、純棋盤規則、固定 seed 棋盤／手牌模擬、無 UI 單場與完整 Run 壓力批次、敵人獨立意圖與速度、資料化意圖執行、目標解析、狀態與戰鬥結果、局內成長、程序地圖、Sanity、五敵人 UI 穩定性、拖曳回饋，以及 `main.tscn` 的核心 Run smoke test。

執行智慧手牌與權重隨機的棋盤基線比較：

```bash
godot --headless --path . --log-file /tmp/arkham-grid-board-simulation.log --script res://tools/simulate_board.gd
```

執行六個現行遭遇的無 UI 戰鬥批次：

```bash
godot --headless --path . --log-file /tmp/arkham-grid-battle-batch.log --script res://tools/simulate_battles.gd
```

執行跨戰鬥保留資源、盤面、手牌與成長的完整 Run 壓力批次：

```bash
godot --headless --path . --log-file /tmp/arkham-grid-run-simulation.log --script res://tools/simulate_runs.gd
```
