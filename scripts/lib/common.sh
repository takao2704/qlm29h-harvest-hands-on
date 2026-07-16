#!/usr/bin/env bash

# This file is sourced by the hands-on scripts.

error() {
  printf '[エラー] %s\n' "$*" >&2
}

warn() {
  printf '[警告] %s\n' "$*" >&2
}

info() {
  printf '[確認] %s\n' "$*"
}

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    error "必要なコマンドが見つかりません: ${command_name}"
    return 1
  fi
}

require_positive_number() {
  local value=$1
  local name=$2

  if ! awk -v value="$value" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value > 0) }'; then
    error "${name} には0より大きい数値を指定してください: ${value}"
    return 1
  fi
}

serial_candidates() {
  local candidate
  local found_by_id=0

  shopt -s nullglob
  for candidate in /dev/serial/by-id/*; do
    if [[ -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      found_by_id=1
    fi
  done

  if ((found_by_id == 0)); then
    for candidate in /dev/ttyUSB* /dev/ttyACM*; do
      [[ -e "$candidate" ]] && printf '%s\n' "$candidate"
    done
  fi
  shopt -u nullglob
}

resolve_serial_port() {
  local -a candidates=()

  if [[ -n "${SERIAL_PORT:-}" ]]; then
    if [[ ! -e "$SERIAL_PORT" ]]; then
      error "SERIAL_PORT が見つかりません: ${SERIAL_PORT}"
      return 1
    fi
    printf '%s\n' "$SERIAL_PORT"
    return 0
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  done < <(serial_candidates)

  case ${#candidates[@]} in
    0)
      error 'シリアルポートを検出できません。QLM29HのUSB接続を確認してください。'
      error '必要に応じて export SERIAL_PORT=/dev/serial/by-id/... を設定してください。'
      return 1
      ;;
    1)
      printf '%s\n' "${candidates[0]}"
      ;;
    *)
      error 'シリアルポートが複数あります。次の候補から使用するポートを指定してください。'
      printf '  %s\n' "${candidates[@]}" >&2
      error '例: export SERIAL_PORT=/dev/serial/by-id/...'
      return 1
      ;;
  esac
}

configure_serial_port() {
  local port=$1
  local baud=${SERIAL_BAUD:-115200}

  require_positive_number "$baud" SERIAL_BAUD

  if [[ ! -r "$port" || ! -w "$port" ]]; then
    error "シリアルポートの読み書き権限がありません: ${port}"
    error "sudo usermod -aG dialout \"$USER\" を実行し、ログインし直してください。"
    return 1
  fi

  stty -F "$port" "$baud" raw -echo -ixon -ixoff
}

extract_first_gga_from_file() {
  local input_file=$1

  if [[ ! -r "$input_file" ]]; then
    error "入力ファイルを読み取れません: ${input_file}"
    return 1
  fi

  local gga
  local status
  set +e
  gga=$(grep -m 1 -E '^\$[[:alnum:]]{2}GGA,' "$input_file")
  status=$?
  set -e

  if ((status != 0)) || [[ -z "$gga" ]]; then
    error "GGAセンテンスが見つかりません: ${input_file}"
    return 1
  fi

  gga=${gga//$'\r'/}
  printf '%s\n' "$gga"
}

extract_first_gga_from_serial() {
  local port=$1
  local read_timeout=${SERIAL_READ_TIMEOUT:-5}

  require_positive_number "$read_timeout" SERIAL_READ_TIMEOUT
  configure_serial_port "$port"

  local gga
  local status
  set +e
  gga=$(timeout "${read_timeout}s" grep -m 1 -E '^\$[[:alnum:]]{2}GGA,' "$port")
  status=$?
  set -e

  if ((status == 124)); then
    error "${read_timeout}秒以内にGGAを受信できませんでした。"
    error 'アンテナ、配線、ポート、ボーレート、他プロセスとの競合を確認してください。'
    return 1
  fi
  if ((status != 0)) || [[ -z "$gga" ]]; then
    error "シリアルポートからGGAを読み取れませんでした: ${port}"
    return 1
  fi

  gga=${gga//$'\r'/}
  printf '%s\n' "$gga"
}
