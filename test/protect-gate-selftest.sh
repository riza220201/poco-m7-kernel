#!/usr/bin/env bash
# protect-gate-selftest.sh — prove Gate Layer 2 (lib/protect_check.py, android13-5.15)
# passes on empty tables and FAILS when a stock module exports or imports a protected
# name — the two -EACCES paths in kernel/module.c (add_module / simplify_symbols).
set -uo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/.build"
REF_V="$B/kmi-ref"
REF_S="$B/kmi-ref-system"
PY="${GATE_PYTHON:-python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

run_case() {
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" ]]; then
    printf "  [PASS] %-62s (exit %s)\n" "$name" "$rc"; pass=$((pass + 1))
  else
    printf "  [FAIL] %-62s (exit %s, wanted %s)\n" "$name" "$rc" "$want"
    echo "$out" | sed 's/^/         /'; fail=$((fail + 1))
  fi
}

echo "=== Gate Layer 2 Self-Test (lib/protect_check.py, 5.15 two-table form) ==="
: > "$TMP/empty"
run_case "POS-1: both tables empty passes" 0 \
  "$PY" "$PROJ/lib/protect_check.py" - "$REF_V" "$REF_S" --exported-list "$TMP/empty" --protected-list "$TMP/empty"

printf "zs_malloc\n" > "$TMP/exp"   # exported by system_dlkm/zsmalloc.ko -> zram swap would die
run_case "NEG-1: zsmalloc's zs_malloc export-protected fails" 1 \
  "$PY" "$PROJ/lib/protect_check.py" - "$REF_V" "$REF_S" --exported-list "$TMP/exp" --protected-list "$TMP/empty"

printf "PDE_DATA\n" > "$TMP/prot"    # imported by msm_drm.ko -> no display
run_case "NEG-2: PDE_DATA import-protected fails" 1 \
  "$PY" "$PROJ/lib/protect_check.py" - "$REF_V" "$REF_S" --exported-list "$TMP/empty" --protected-list "$TMP/prot"

mkdir -p "$TMP/kout/kernel"
run_case "NEG-3: missing generated headers is an error, not a pass" 2 \
  "$PY" "$PROJ/lib/protect_check.py" "$TMP/kout" "$REF_V"

mkdir -p "$TMP/empty_ref"
run_case "NEG-4: empty reference dir is vacuous, not a pass" 2 \
  "$PY" "$PROJ/lib/protect_check.py" - "$TMP/empty_ref" --exported-list "$TMP/empty" --protected-list "$TMP/empty"

echo "Gate Layer 2 Self-Test: passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
