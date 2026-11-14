#!/usr/bin/env python3
"""Gate Layer 5: no stock module may export a symbol the built vmlinux exports.

kernel/module.c verify_exported_symbols() (5.15): a module that exports a name
already exported by vmlinux (or an earlier module) is refused with -ENOEXEC
("exports duplicate symbol ... (owned by kernel)"). Layers 1-4 never see this:
they compare imports and CRCs. It matters whenever a feature pulls a library into
vmlinux (e.g. CONFIG_CRYPTO_LZ4HC=y brings lib/lz4hc) or the whitelist grows: the
5.15.223 tree exports 129 names the stock 5.15.194 kernel did not.

Usage: dup_export_check.py <vmlinux.symvers> <kmi_ref_dir>... [--allow NAME]...
Exit: 0 pass, 1 duplicate, 2 input error / vacuous.
"""
import argparse
import os
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("symvers")
    ap.add_argument("kmi_ref", nargs="+")
    a = ap.parse_args()

    try:
        ours = {ln.split("\t")[1] for ln in open(a.symvers) if ln.count("\t") >= 2}
    except OSError as e:
        sys.stderr.write(f"FAIL [dup_export_check]: {e}\n")
        return 2
    mods = {}
    for ref in a.kmi_ref:
        p = os.path.join(ref, "exports.tsv")
        if not os.path.isfile(p):
            sys.stderr.write(f"FAIL [dup_export_check]: missing {p}\n")
            return 2
        for ln in open(p):
            f = ln.rstrip("\n").split("\t")
            if len(f) >= 3:
                mods.setdefault(f[1], set()).add(f[2])
    if not ours or not mods:
        sys.stderr.write(f"FAIL [dup_export_check]: vacuous (vmlinux exports {len(ours)}, module exports {len(mods)})\n")
        return 2
    dup = sorted(s for s in mods if s in ours)
    if dup:
        sys.stderr.write(f"FAIL [dup_export_check]: {len(dup)} names exported by vmlinux AND a stock module "
                         f"(the module is refused with -ENOEXEC):\n")
        for s in dup[:40]:
            sys.stderr.write(f"  DUPLICATE {s}  (also exported by {', '.join(sorted(mods[s]))})\n")
        return 1
    print(f"PASS [dup_export_check]: vmlinux exports {len(ours)}, stock module exports {len(mods)}, 0 duplicates")
    return 0


if __name__ == "__main__":
    sys.exit(main())
