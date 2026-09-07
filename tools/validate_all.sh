#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_EXECUTABLE=${GODOT_BIN:-}

if [ -z "$GODOT_EXECUTABLE" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_EXECUTABLE=$(command -v godot)
	elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
		GODOT_EXECUTABLE="/Applications/Godot.app/Contents/MacOS/Godot"
	else
		echo "找不到 Godot。請設定 GODOT_BIN 指向 Godot 4.x 執行檔。" >&2
		exit 1
	fi
fi

run_godot_check() {
	name=$1
	script_path=$2
	log_path="/tmp/arkham-grid-${name}.log"
	"$GODOT_EXECUTABLE" --headless --path "$PROJECT_DIR" --log-file "$log_path" --script "$script_path"
	if grep -Eq "SCRIPT ERROR|TEST FAILED|SIMULATION FAILED" "$log_path"; then
		echo "Godot 驗證失敗：$script_path（見 $log_path）" >&2
		exit 1
	fi
}

cd "$PROJECT_DIR"
python3 tools/validate_data.py
run_godot_check "tests" "res://tests/test_runner.gd"
run_godot_check "board-simulation" "res://tools/simulate_board.gd"
run_godot_check "battle-batch" "res://tools/simulate_battles.gd"
run_godot_check "run-simulation" "res://tools/simulate_runs.gd"
run_godot_check "sanity-simulation" "res://tools/simulate_sanity.gd"
run_godot_check "balance-report" "res://tools/generate_balance_report.gd"

echo "ALL VALIDATIONS OK"
