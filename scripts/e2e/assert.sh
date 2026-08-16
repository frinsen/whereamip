#!/bin/bash
# jq-based assertions over whereamip JSON. Sourced. Never exits on failure —
# a leak-detection bug must not strand the machine mid-suite (spec §6).
set -euo pipefail
E2E_FAILED=0

_a_result() {  # STATUS LABEL DETAIL
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$E2E_LOG_DIR/assertions.tsv"
  e2e_log "ASSERT $1: $2 ($3)"
  [ "$1" = FAIL ] && E2E_FAILED=1 || true
}

a_json_eq() {  # FILE JQ_EXPR EXPECTED LABEL
  local got
  if ! got="$(jq -r "$2" "$1" 2>/dev/null)"; then
    _a_result FAIL "$4" "jq failed on $1 ($2)"
    return 0
  fi
  [ "$got" = "$3" ] && _a_result PASS "$4" "$2=$got" || _a_result FAIL "$4" "$2: want $3, got $got"
}

a_json_contains() {  # FILE JQ_EXPR NEEDLE LABEL
  local got
  if ! got="$(jq -r "$2" "$1" 2>/dev/null)"; then
    _a_result FAIL "$4" "jq failed on $1 ($2)"
    return 0
  fi
  case "$got" in *"$3"*) _a_result PASS "$4" "found $3";; *) _a_result FAIL "$4" "$3 not in: $got";; esac
}

a_json_in() {  # FILE JQ_EXPR "v1|v2" LABEL
  local got
  if ! got="$(jq -r "$2" "$1" 2>/dev/null)"; then
    _a_result FAIL "$4" "jq failed on $1 ($2)"
    return 0
  fi
  case "|$3|" in *"|$got|"*) _a_result PASS "$4" "$2=$got";; *) _a_result FAIL "$4" "$2=$got not in {$3}";; esac
}

a_record() {  # FILE JQ_EXPR LABEL   (calibration data, never fails)
  local got
  if ! got="$(jq -r "$2" "$1" 2>/dev/null)"; then
    got="JQ-ERROR"
  fi
  printf '%s\t%s\t%s\n' "$3" "$2" "$got" >> "$E2E_LOG_DIR/calibration.tsv"
  e2e_log "RECORD: $3 $2=$got"
}

if [ "${1:-}" = "--selftest" ]; then
  E2E_LOG_DIR="$(mktemp -d)"; e2e_log() { :; }
  echo '{"route":{"isVPN":true,"vpnName":"PureVPN"},"dns":{"leak":"none","resolvers":[{"address":"9.9.9.9"}]}}' > "$E2E_LOG_DIR/t.json"
  a_json_eq "$E2E_LOG_DIR/t.json" '.route.isVPN' true t1
  a_json_contains "$E2E_LOG_DIR/t.json" '.dns.resolvers[].address' 9.9.9.9 t2
  a_json_in "$E2E_LOG_DIR/t.json" '.dns.leak' 'none|unknown' t3
  a_json_eq "$E2E_LOG_DIR/t.json" '.route.vpnName' WRONG t4-mustfail || true
  a_json_eq /nonexistent '.foo' bar t5-jqfail || true
  cut -f1 "$E2E_LOG_DIR/assertions.tsv" | grep -cx PASS | grep -qx 3 && cut -f1 "$E2E_LOG_DIR/assertions.tsv" | grep -cx FAIL | grep -qx 2 \
    && echo "selftest OK" || { echo "selftest FAILED"; exit 1; }
fi
