#!/usr/bin/env bash

# This file is sourced by the hands-on scripts.

post_json() {
  local payload=$1
  local endpoint=${SORACOM_ENDPOINT:-http://uni.soracom.io}

  if [[ ! "$endpoint" =~ ^https?:// ]]; then
    error "SORACOM_ENDPOINT は http:// または https:// で始めてください: ${endpoint}"
    return 2
  fi

  local payload_bytes
  payload_bytes=$(LC_ALL=C printf '%s' "$payload" | wc -c | awk '{print $1}')
  if ((payload_bytes > 1024)); then
    error "JSONがHarvest Dataの上限である1024バイトを超えています: ${payload_bytes}バイト"
    return 2
  fi

  printf '[送信先] %s\n' "$endpoint"
  printf '[送信データ] %s\n' "$payload"

  local response
  local curl_status
  set +e
  response=$(curl \
    --silent \
    --show-error \
    --request POST \
    --connect-timeout 10 \
    --max-time 20 \
    --header 'Content-Type: application/json' \
    --data-binary "$payload" \
    --write-out $'\n%{http_code}' \
    "$endpoint")
  curl_status=$?
  set -e

  if ((curl_status != 0)); then
    error "HTTP送信に失敗しました（curl終了コード: ${curl_status}）。"
    error 'SORACOM Airの通信経路、DNS、アンテナ状態を確認してください。再送は行っていません。'
    return 70
  fi

  local http_code=${response##*$'\n'}
  local response_body=${response%$'\n'*}

  if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    error "HTTPステータスを判定できませんでした: ${http_code}"
    return 70
  fi

  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    printf '[成功] HTTP %s\n' "$http_code"
    [[ -n "$response_body" ]] && printf '[レスポンス] %s\n' "$response_body"
    return 0
  fi

  error "Harvest Dataへの送信が拒否されました（HTTP ${http_code}）。再送は行っていません。"
  [[ -n "$response_body" ]] && printf '[レスポンス] %s\n' "$response_body" >&2
  if [[ "$http_code" =~ ^4 ]]; then
    error 'SIMグループとHarvest Dataの設定、JSON形式を確認してください。'
  else
    error 'サービス状態と通信経路を確認してから、手動で再実行してください。'
  fi
  return 22
}
