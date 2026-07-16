#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"$SCRIPT_DIR/test_gga_parser.sh"
"$SCRIPT_DIR/test_http_sender.sh"
