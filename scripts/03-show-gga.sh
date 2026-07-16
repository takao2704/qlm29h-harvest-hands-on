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
    error '使い方: 03-show-gga.sh [--input FILE]'
    exit 2
  fi
fi

if [[ -n "$input_file" ]]; then
  extract_first_gga_from_file "$input_file"
else
  require_command timeout
  require_command stty
  port=$(resolve_serial_port)
  extract_first_gga_from_serial "$port"
fi
