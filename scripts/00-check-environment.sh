#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

printf 'QLM29H × SORACOM Harvest Data ハンズオン 事前確認\n\n'

missing=0
for command_name in bash awk grep sed timeout stty curl getent; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '[OK]   %-8s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf '[NG]   %-8s 見つかりません\n' "$command_name"
    missing=1
  fi
done

if ((missing != 0)); then
  error '不足しているコマンドをインストールしてから再実行してください。'
fi

printf '\nSORACOM Unified Endpointの名前解決を確認します。\n'
endpoint_host=${SORACOM_ENDPOINT:-http://uni.soracom.io}
endpoint_host=${endpoint_host#*://}
endpoint_host=${endpoint_host%%/*}
endpoint_host=${endpoint_host%%:*}

resolved=''
if command -v getent >/dev/null 2>&1; then
  resolved=$(getent ahostsv4 "$endpoint_host" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)
fi
if [[ -z "$resolved" ]]; then
  warn "${endpoint_host} を名前解決できません。SORACOM Airの通信経路を確認してください。"
  missing=1
else
  printf '[OK]   %s -> %s\n' "$endpoint_host" "$resolved"
  if [[ "$resolved" != 100.127.* ]]; then
    warn 'SORACOMプラットフォームのプライベートアドレス（100.127.x.x）ではありません。'
    warn 'Raspberry Piの通信がSORACOM Air経由か確認してください。'
  fi
fi

printf '\nシリアルポートを確認します。\n'
mapfile -t ports < <(serial_candidates)
if ((${#ports[@]} == 0)); then
  warn 'シリアルポートが見つかりません。QLM29HのUSB接続を確認してください。'
  missing=1
else
  for port in "${ports[@]}"; do
    access='read/write OK'
    [[ -r "$port" && -w "$port" ]] || access='権限不足'
    printf '[候補] %s (%s)\n' "$port" "$access"
    if [[ "$access" == '権限不足' ]]; then
      missing=1
    fi
    if command -v fuser >/dev/null 2>&1; then
      users=$(fuser "$port" 2>/dev/null || true)
      [[ -n "$users" ]] && warn "${port} は別プロセスが使用中です（PID:${users}）。"
    fi
  done
fi

printf '\n'
if ((missing != 0)); then
  error '事前確認で問題が見つかりました。docs/troubleshooting.mdを参照してください。'
  exit 1
fi

info 'ハンズオンを開始できる状態です。'
