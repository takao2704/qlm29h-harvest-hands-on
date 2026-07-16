#!/usr/bin/env bash

# コマンドの失敗、未設定変数、パイプ途中の失敗を検出する
set -euo pipefail

# どのディレクトリから実行しても共通処理を読み込めるよう、
# このスクリプト自身が置かれているディレクトリを取得する
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# NMEA表示に必要なコマンドが使えることを確認する
require_command timeout
require_command stty

# 読み取り時間は環境変数で変更でき、未指定時は5秒とする
read_timeout=${SERIAL_READ_TIMEOUT:-5}
require_positive_number "$read_timeout" SERIAL_READ_TIMEOUT

# QLM29Hのシリアルポートを特定し、既定115200 bpsのrawモードに設定する
port=$(resolve_serial_port)
configure_serial_port "$port"

# 使用するポート、通信速度、読み取り時間を表示する
info "${port} を ${SERIAL_BAUD:-115200} bpsで ${read_timeout}秒間読み取ります。"
printf '%s\n' '--- NMEA受信開始 ---'

# timeoutによる予定どおりの終了（終了コード124）を自分で判定するため、
# この区間だけエラー時の自動終了を無効にする
set +e
# シリアルから届く文字を表示し、NMEA行末のCRを取り除く
timeout "${read_timeout}s" cat "$port" | sed 's/\r$//'
# パイプ左側にあるtimeoutコマンドの終了コードを保存する
read_status=${PIPESTATUS[0]}
set -e

printf '%s\n' '--- NMEA受信終了 ---'
# 0（通常終了）と124（時間切れ）以外は読み取りエラーとして終了する
if ((read_status != 0 && read_status != 124)); then
  error "シリアル読み取りに失敗しました（終了コード: ${read_status}）。"
  exit 1
fi
