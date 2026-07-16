#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "$SCRIPT_DIR/lib/http.sh"

input_file=''
if (($# > 0)); then
  if [[ ${1:-} == '--input' && $# == 2 ]]; then
    input_file=$2
  else
    error '使い方: 05-send-position-once.sh [--input FILE]'
    exit 2
  fi
fi

require_command curl

if [[ -n "$input_file" ]]; then
  payload=$("$SCRIPT_DIR/04-format-gga.sh" --input "$input_file")
else
  gga=$("$SCRIPT_DIR/03-show-gga.sh")
  payload=$(printf '%s\n' "$gga" | "$SCRIPT_DIR/04-format-gga.sh")
fi

post_json "$payload"
