#!/usr/bin/env bash
# cfi-gate-selftest.sh — prove Gate Layer 6 (lib/cfi_typeid_check.py, from the RS4) passes for the
# stock-compiler reference against itself and FAILS for a "kernel" that does not accept the
# vendor-shared CFI type ids, or has no __cfi_check at all.
set -uo pipefail
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/.build"; PY="${GATE_PYTHON:-python3}"
source "$PROJ/device.conf"
OBJDUMP="$CLANG_DIR/bin/llvm-objdump"; REF="$B/cfi-ref/vmlinux"; KOS="$B/kmi-ref-all"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
run_case() {
  local name="$1" want="$2"; shift 2
  local out rc; out="$("$@" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" ]]; then printf "  [PASS] %-62s (exit %s)\n" "$name" "$rc"; pass=$((pass+1))
  else printf "  [FAIL] %-62s (exit %s, wanted %s)\n" "$name" "$rc" "$want"; echo "$out" | tail -5 | sed 's/^/         /'; fail=$((fail+1)); fi
}
echo "=== Gate Layer 6 Self-Test (lib/cfi_typeid_check.py) ==="
run_case "POS-1: reference vs itself vs 562 vendor modules" 0 "$PY" "$PROJ/lib/cfi_typeid_check.py" "$OBJDUMP" "$REF" "$REF" "$KOS"
run_case "NEG-1: a module's __cfi_check as the 'kernel' loses ids" 1 "$PY" "$PROJ/lib/cfi_typeid_check.py" "$OBJDUMP" "$REF" "$KOS/dlkm-msm_drm.ko" "$KOS"
run_case "NEG-2: an ELF without __cfi_check is not a pass" 2 "$PY" "$PROJ/lib/cfi_typeid_check.py" "$OBJDUMP" "$REF" /bin/true "$KOS"
run_case "NEG-3: a file objdump cannot read is an input error" 2 "$PY" "$PROJ/lib/cfi_typeid_check.py" "$OBJDUMP" "$REF" "$PROJ/lib/kmi_check.py" "$KOS"
echo "Gate Layer 6 Self-Test: passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
