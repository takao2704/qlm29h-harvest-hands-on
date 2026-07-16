#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FORMATTER="$ROOT_DIR/scripts/04-format-gga.sh"
passed=0
failed=0

pass() {
  printf 'ok - %s\n' "$1"
  passed=$((passed + 1))
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failed=$((failed + 1))
}

assert_output_contains() {
  local name=$1
  local sample=$2
  shift 2

  local output
  if ! output=$("$FORMATTER" --input "$ROOT_DIR/samples/$sample" 2>&1); then
    fail "$name（変換が失敗）"
    printf '%s\n' "$output" >&2
    return
  fi

  local expected
  for expected in "$@"; do
    if [[ "$output" != *"$expected"* ]]; then
      fail "$name（不足: $expected）"
      printf '%s\n' "$output" >&2
      return
    fi
  done
  pass "$name"
}

assert_fails() {
  local name=$1
  local sample=$2
  local expected_status=$3
  local expected_message=$4

  local output
  local status
  set +e
  output=$("$FORMATTER" --input "$ROOT_DIR/samples/$sample" 2>&1)
  status=$?
  set -e

  if ((status != expected_status)); then
    fail "$name（終了コード: expected=$expected_status actual=$status）"
    printf '%s\n' "$output" >&2
    return
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    fail "$name（エラーメッセージ不一致）"
    printf '%s\n' "$output" >&2
    return
  fi
  pass "$name"
}

assert_output_contains \
  'Fixed RTKを十進数度へ変換できる' \
  fixed-rtk.nmea \
  '"lat":35.68123600' \
  '"lon":139.76712500' \
  '"quality":4' \
  '"quality_label":"Fixed RTK"' \
  '"utc_time":"03:04:05.000Z"'

assert_output_contains \
  'Float RTKを識別できる' \
  float-rtk.nmea \
  '"quality":5' \
  '"quality_label":"Float RTK"'

assert_output_contains \
  '通常Fixを識別できる' \
  standard-fix.nmea \
  '"quality":1' \
  '"quality_label":"GPS SPS Mode"'

assert_output_contains \
  '南緯・西経を負数へ変換できる' \
  south-west.nmea \
  '"lat":-33.43500000' \
  '"lon":-70.65000000'

assert_output_contains \
  '任意フィールドの空欄をnullへ変換できる' \
  empty-optional-fields.nmea \
  '"satellites":null' \
  '"hdop":null' \
  '"altitude_m":null'

assert_fails 'No Fixを送信対象にしない' no-fix.nmea 3 'quality=0'
assert_fails '短いGGAを拒否する' malformed.nmea 2 'フィールド数が不足'
assert_fails '不正な数値を拒否する' invalid-number.nmea 2 '緯度が数値ではありません'

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
