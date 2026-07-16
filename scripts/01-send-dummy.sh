#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "$SCRIPT_DIR/lib/http.sh"

require_command curl

temperature=${1:-20}
if ! awk -v value="$temperature" 'BEGIN { exit !(value ~ /^-?[0-9]+([.][0-9]+)?$/) }'; then
  error "temperatureには数値を指定してください: ${temperature}"
  exit 2
fi

payload=$(printf '{"temperature":%s}' "$temperature")
post_json "$payload"
