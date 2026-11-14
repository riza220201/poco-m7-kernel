#!/usr/bin/env bash
# kmi-gate-selftest.sh — Prove Gate Layer 1 (lib/kmi_check.py) passes on
# positive controls and fails on every negative control (CRC mismatch, missing
# symbol, wrong module_layout, wrong vermagic provenance, vacuous reference).
set -uo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/.build"
STOCK_SYMVERS="$B/stock/stock.symvers"
REF_V="$B/kmi-ref"
REF_S="$B/kmi-ref-system"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

run_case() {
  local name="$1" want="$2"
  shift 2
  local out rc
  out="$("$@" 2>&1)"
  rc=$?
  if [[ "$rc" == "$want" ]]; then
    printf "  [PASS] %-58s (exit %s)\n" "$name" "$rc"
    pass=$((pass + 1))
  else
    printf "  [FAIL] %-58s (exit %s, wanted %s)\n" "$name" "$rc" "$want"
    echo "$out" | sed 's/^/         /'
    fail=$((fail + 1))
  fi
}

echo "=== Gate Layer 1 Self-Test (lib/kmi_check.py) ==="
# Every value comes from device.conf: a self-test carried over from another device with
# that device's module_layout once made NEG-1 pass for the wrong reason (it "perturbed"
# a CRC that was not there and failed on the wrong expectation instead).
source "$PROJ/device.conf"
PY="${GATE_PYTHON:-python3}"
grep -qP "^${MODULE_LAYOUT}\tmodule_layout\t" "$STOCK_SYMVERS" \
  || { echo "  [FAIL] stock.symvers has no module_layout ${MODULE_LAYOUT}: wrong reference"; exit 1; }

# run_neg <name> <wanted exit> <substring the failure must name> cmd...
run_neg() {
  local name="$1" want="$2" why="$3"; shift 3
  local out rc; out="$("$@" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" ]] && grep -qF -- "$why" <<<"$out"; then
    printf "  [PASS] %-58s (exit %s: %s)\n" "$name" "$rc" "$why"; pass=$((pass + 1))
  else
    printf "  [FAIL] %-58s (exit %s, wanted %s + '%s')\n" "$name" "$rc" "$want" "$why"
    echo "$out" | sed 's/^/         /'; fail=$((fail + 1))
  fi
}

run_case "POS-1: stock.symvers vs vendor (kmi-ref + system_dlkm exports)" 0 \
  "$PY" "$PROJ/lib/kmi_check.py" "$STOCK_SYMVERS" "$REF_V" \
    --extra-exports "$REF_S/exports.tsv" \
    --expect-vermagic "$KMI_EXPECT_VERMAGIC" --expect-module-layout "$MODULE_LAYOUT"

run_case "POS-2: stock.symvers vs system_dlkm (kmi-ref-system)" 0 \
  "$PY" "$PROJ/lib/kmi_check.py" "$STOCK_SYMVERS" "$REF_S" \
    --expect-vermagic "$KMI_SYSTEM_EXPECT_VERMAGIC" --expect-module-layout "$MODULE_LAYOUT"

sed "s/^${MODULE_LAYOUT}\tmodule_layout/0xdeadbeef\tmodule_layout/" "$STOCK_SYMVERS" > "$TMP/bad_ml.symvers"
cmp -s "$STOCK_SYMVERS" "$TMP/bad_ml.symvers" && { echo "  [FAIL] NEG-1 perturbation changed nothing"; fail=$((fail + 1)); }
run_neg "NEG-1: perturbed module_layout CRC must fail" 1 "module_layout CRC mismatch" \
  "$PY" "$PROJ/lib/kmi_check.py" "$TMP/bad_ml.symvers" "$REF_V" \
    --extra-exports "$REF_S/exports.tsv" --expect-module-layout "$MODULE_LAYOUT"

sed 's/\t__kmalloc\t/\t__kmalloc_gone\t/' "$STOCK_SYMVERS" > "$TMP/missing_sym.symvers"
run_neg "NEG-2: missing vmlinux symbol (__kmalloc) must fail" 1 "__kmalloc" \
  "$PY" "$PROJ/lib/kmi_check.py" "$TMP/missing_sym.symvers" "$REF_V" \
    --extra-exports "$REF_S/exports.tsv" --expect-module-layout "$MODULE_LAYOUT"

awk -F'\t' 'BEGIN{OFS="\t"} $2=="schedule"{$1="0x12345678"} {print}' "$STOCK_SYMVERS" > "$TMP/bad_crc.symvers"
run_neg "NEG-3: single symbol CRC mismatch (schedule) must fail" 1 "schedule" \
  "$PY" "$PROJ/lib/kmi_check.py" "$TMP/bad_crc.symvers" "$REF_V" \
    --extra-exports "$REF_S/exports.tsv" --expect-module-layout "$MODULE_LAYOUT"

run_neg "NEG-4: wrong provenance vermagic must fail" 1 "provenance mismatch" \
  "$PY" "$PROJ/lib/kmi_check.py" "$STOCK_SYMVERS" "$REF_V" \
    --extra-exports "$REF_S/exports.tsv" --expect-vermagic "6.1.115-android14-11"

mkdir -p "$TMP/empty"
run_neg "NEG-5: vacuous empty reference directory must fail" 2 "FAIL [kmi_check]" \
  "$PY" "$PROJ/lib/kmi_check.py" "$STOCK_SYMVERS" "$TMP/empty"

echo "Gate Layer 1 Self-Test: passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
