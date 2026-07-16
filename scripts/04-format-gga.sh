#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

input_file=''
if (($# > 0)); then
  if [[ ${1:-} == '--input' && $# == 2 ]]; then
    input_file=$2
  else
    error '使い方: 04-format-gga.sh [--input FILE]'
    exit 2
  fi
fi

if [[ -n "$input_file" ]]; then
  gga=$(extract_first_gga_from_file "$input_file")
else
  gga=''
  while IFS= read -r line; do
    line=${line//$'\r'/}
    if [[ "$line" =~ ^\$[[:alnum:]]{2}GGA, ]]; then
      gga=$line
      break
    fi
  done
  if [[ -z "$gga" ]]; then
    error '標準入力にGGAセンテンスがありません。'
    exit 2
  fi
fi

printf '%s\n' "$gga" | awk -F, '
function fail(message, code) {
  print "[エラー] " message > "/dev/stderr"
  exit code
}

function is_number(value) {
  return value ~ /^-?[0-9]+([.][0-9]+)?$/
}

function coordinate(value, direction, degree_digits, max_degrees, label, degrees, minutes, result) {
  if (value == "" || !is_number(value)) {
    fail(label "が数値ではありません: " value, 2)
  }
  degrees = substr(value, 1, degree_digits) + 0
  minutes = substr(value, degree_digits + 1) + 0
  if (degrees > max_degrees || minutes >= 60 || (degrees == max_degrees && minutes > 0)) {
    fail(label "の範囲が不正です: " value, 2)
  }
  result = degrees + minutes / 60
  if (direction == "S" || direction == "W") {
    result = -result
  }
  return result
}

function optional_number(value, label) {
  if (value == "") {
    return "null"
  }
  if (!is_number(value)) {
    fail(label "が数値ではありません: " value, 2)
  }
  return value
}

function quality_label(quality) {
  if (quality == 1) return "GPS SPS Mode"
  if (quality == 2) return "Differential GPS / SPS / SBAS Mode"
  if (quality == 4) return "Fixed RTK"
  if (quality == 5) return "Float RTK"
  if (quality == 6) return "Estimated / Dead Reckoning"
  return "Unknown(" quality ")"
}

{
  sub(/\r$/, "")
  if ($1 !~ /^\$[[:alnum:]][[:alnum:]]GGA$/) {
    fail("GGAセンテンスではありません: " $1, 2)
  }
  if (NF < 10) {
    fail("GGAのフィールド数が不足しています。", 2)
  }

  utc = $2
  lat_raw = $3
  north_south = $4
  lng_raw = $5
  east_west = $6
  quality = $7
  satellites = $8
  hdop = $9
  altitude = $10

  if (quality !~ /^[0-9]+$/) {
    fail("qualityが整数ではありません: " quality, 2)
  }
  if (quality + 0 == 0) {
    fail("quality=0（No Fix）のため送信データを作成しません。", 3)
  }
  if (north_south !~ /^[NS]$/ || east_west !~ /^[EW]$/) {
    fail("緯度・経度の方位が不正です: " north_south "/" east_west, 2)
  }
  if (utc !~ /^[0-9][0-9][0-9][0-9][0-9][0-9]([.][0-9]+)?$/) {
    fail("UTC時刻の形式が不正です: " utc, 2)
  }

  hours = substr(utc, 1, 2) + 0
  minutes = substr(utc, 3, 2) + 0
  seconds = substr(utc, 5) + 0
  if (hours > 23 || minutes > 59 || seconds >= 60) {
    fail("UTC時刻の範囲が不正です: " utc, 2)
  }

  lat = coordinate(lat_raw, north_south, 2, 90, "緯度")
  lng = coordinate(lng_raw, east_west, 3, 180, "経度")
  satellites_json = optional_number(satellites, "satellites")
  hdop_json = optional_number(hdop, "hdop")
  altitude_json = optional_number(altitude, "altitude_m")
  utc_formatted = substr(utc, 1, 2) ":" substr(utc, 3, 2) ":" substr(utc, 5) "Z"

  printf "{\"source\":\"qlm29h-gga\",\"lat\":%.8f,\"lng\":%.8f,", lat, lng
  printf "\"quality\":%d,\"quality_label\":\"%s\",", quality, quality_label(quality)
  printf "\"satellites\":%s,\"hdop\":%s,\"altitude_m\":%s,", satellites_json, hdop_json, altitude_json
  printf "\"utc_time\":\"%s\"}\n", utc_formatted
}
'
