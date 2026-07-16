#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_command timeout
require_command stty

read_timeout=${SERIAL_READ_TIMEOUT:-15}
require_positive_number "$read_timeout" SERIAL_READ_TIMEOUT
port=$(resolve_serial_port)
configure_serial_port "$port"

info "${port} を ${SERIAL_BAUD:-115200} bpsで ${read_timeout}秒間読み取ります。"
printf '%s\n' '--- NMEA受信開始 ---'

set +e
timeout "${read_timeout}s" cat "$port" | sed 's/\r$//'
read_status=${PIPESTATUS[0]}
set -e

printf '%s\n' '--- NMEA受信終了 ---'
if ((read_status != 0 && read_status != 124)); then
  error "シリアル読み取りに失敗しました（終了コード: ${read_status}）。"
  exit 1
fi
