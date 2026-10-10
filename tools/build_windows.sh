#!/usr/bin/env bash
# Windows 向けの配布物を作る：  tools/build_windows.sh
#   GODOT=/path/to/godot tools/build_windows.sh   （godot が PATH に無いとき）
# できるもの：
#   build/windows/OnionTears.exe              単一の実行ファイル（データ込み）
#   build/windows/THIRD_PARTY_LICENSES.txt    エンジン・フォントのライセンス表記（同梱が必要）
#   build/OnionTears-windows-<バージョン>.zip  上の2つをまとめたもの
# 事前に Godot の「エクスポートテンプレート 4.4.1」を入れておくこと
# （Linux なら ~/.local/share/godot/export_templates/4.4.1.stable/ に windows_release_x86_64.exe が必要）。
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
VERSION="$(grep -oE 'GAME_VERSION := "[^"]+"' scripts/ui.gd | cut -d'"' -f2)"
OUT=build/windows

rm -rf build
mkdir -p "$OUT"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/OnionTears.exe"
"$GODOT" --headless --path . -s tools/make_licenses.gd -- "$OUT/THIRD_PARTY_LICENSES.txt"
test -s "$OUT/OnionTears.exe" || { echo "書き出しに失敗しました" >&2; exit 1; }
(cd "$OUT" && zip -q -9 "../OnionTears-windows-${VERSION}.zip" OnionTears.exe THIRD_PARTY_LICENSES.txt)
ls -lh "$OUT" build/*.zip
