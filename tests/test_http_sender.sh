#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

cat >"$TEMP_DIR/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -u

previous=''
for argument in "$@"; do
  if [[ "$previous" == '--data-binary' && -n "${FAKE_CURL_LOG:-}" ]]; then
    printf '%s\n' "$argument" >"$FAKE_CURL_LOG"
  fi
  previous=$argument
done

case ${FAKE_CURL_MODE:-success} in
  success)
    printf '{"result":"accepted"}\n201'
    ;;
  http400)
    printf '{"message":"bad request"}\n400'
    ;;
  http500)
    printf '{"message":"server error"}\n500'
    ;;
  connection)
    printf 'curl: (7) Failed to connect\n' >&2
    exit 7
    ;;
  *)
    exit 99
    ;;
esac
FAKE_CURL
chmod +x "$TEMP_DIR/curl"

export PATH="$TEMP_DIR:$PATH"
export SORACOM_ENDPOINT='http://example.invalid'
export FAKE_CURL_LOG="$TEMP_DIR/payload.log"

passed=0
failed=0

expect_success() {
  local name=$1
  shift
  local output
  if output=$("$@" 2>&1); then
    printf 'ok - %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'not ok - %s\n%s\n' "$name" "$output" >&2
    failed=$((failed + 1))
  fi
}

expect_failure() {
  local name=$1
  local expected=$2
  shift 2
  local output
  local status
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  if ((status != 0)) && [[ "$output" == *"$expected"* ]]; then
    printf 'ok - %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'not ok - %s\n%s\n' "$name" "$output" >&2
    failed=$((failed + 1))
  fi
}

export FAKE_CURL_MODE=success
expect_success \
  'サンプルGGAをJSONへ変換して送信できる' \
  "$ROOT_DIR/scripts/05-send-position-once.sh" --input "$ROOT_DIR/samples/fixed-rtk.nmea"
grep -Fq '"lat":35.68123600' "$FAKE_CURL_LOG" || {
  printf 'not ok - 位置JSONがcurlへ渡される\n' >&2
  failed=$((failed + 1))
}

export FAKE_CURL_MODE=http400
expect_failure \
  'HTTP 400を失敗にする' \
  'SIMグループとHarvest Dataの設定' \
  "$ROOT_DIR/scripts/05-send-position-once.sh" --input "$ROOT_DIR/samples/fixed-rtk.nmea"

export FAKE_CURL_MODE=http500
expect_failure \
  'HTTP 500を失敗にする' \
  'サービス状態と通信経路' \
  "$ROOT_DIR/scripts/05-send-position-once.sh" --input "$ROOT_DIR/samples/fixed-rtk.nmea"

export FAKE_CURL_MODE=connection
expect_failure \
  '接続失敗を明示する' \
  '再送は行っていません' \
  "$ROOT_DIR/scripts/05-send-position-once.sh" --input "$ROOT_DIR/samples/fixed-rtk.nmea"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
