#!/usr/bin/env bash
# dup-export-gate-selftest.sh — prove Gate Layer 5 (lib/dup_export_check.py) passes on the
# stock symvers and FAILS when vmlinux exports a name a stock module also exports.
set -uo pipefail
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/.build"; PY="${GATE_PYTHON:-python3}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
run_case() {
  local name="$1" want="$2"; shift 2
  local out rc; out="$("$@" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" ]]; then printf "  [PASS] %-62s (exit %s)\n" "$name" "$rc"; pass=$((pass+1))
  else printf "  [FAIL] %-62s (exit %s, wanted %s)\n" "$name" "$rc" "$want"; echo "$out" | sed 's/^/         /'; fail=$((fail+1)); fi
}
echo "=== Gate Layer 5 Self-Test (lib/dup_export_check.py) ==="
run_case "POS-1: stock vmlinux exports vs stock modules passes" 0 \
  "$PY" "$PROJ/lib/dup_export_check.py" "$B/stock/stock.symvers" "$B/kmi-ref" "$B/kmi-ref-system"
cp "$B/stock/stock.symvers" "$TMP/dup.symvers"
printf '0x00000000\tzs_malloc\tvmlinux\tEXPORT_SYMBOL\n' >> "$TMP/dup.symvers"   # zsmalloc.ko exports it
run_case "NEG-1: vmlinux also exporting zs_malloc fails" 1 \
  "$PY" "$PROJ/lib/dup_export_check.py" "$TMP/dup.symvers" "$B/kmi-ref" "$B/kmi-ref-system"
mkdir -p "$TMP/empty"
run_case "NEG-2: a reference without exports.tsv is an error" 2 \
  "$PY" "$PROJ/lib/dup_export_check.py" "$B/stock/stock.symvers" "$TMP/empty"
: > "$TMP/none.symvers"
run_case "NEG-3: an empty symvers is vacuous, not a pass" 2 \
  "$PY" "$PROJ/lib/dup_export_check.py" "$TMP/none.symvers" "$B/kmi-ref"
echo "Gate Layer 5 Self-Test: passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
