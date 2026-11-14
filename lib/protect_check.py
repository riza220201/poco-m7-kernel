#!/usr/bin/env python3
"""Gate Layer 2 for android13-5.15: GKI module protection (CONFIG_MODULE_SIG_PROTECT).

On 5.15 the protection is two build-generated tables in kernel/gki_module.o:

  gki_exported_symbols   (kernel/gki_module_exported.h  <- android/abi_gki_modules_exports)
      add_module(): an UNSIGNED module that EXPORTS one of these -> -EACCES
      ("exporting protected symbol").
  gki_protected_symbols  (kernel/gki_module_protected.h <- android/abi_gki_modules_protected)
      simplify_symbols(): an UNSIGNED module that IMPORTS one of these -> -EACCES
      ("is not an Android GKI signed module. It can not access protected symbol").

Our kernel is signed with our own key, so EVERY stock module is unsigned to it:
the vendor modules (never Google-signed) and the system_dlkm ones (Google-signed,
but not with our key). A non-empty intersection means a module that will not load.

The 6.1 gate (POCO X7) looked for `protected_symbol_exports` in vmlinux; on 5.15
that name does not exist, so it would have printed "not present -> PASS": a gate
that checks nothing. This one reads the generated headers (the literal source of
the tables) and REFUSES to pass if they are missing.

Exit: 0 pass, 1 collision, 2 input error / vacuous.
"""
import argparse
import os
import re
import sys

STR_RE = re.compile(r'^\s*"([^"]*)",\s*$')


def read_header(path):
    """Return the list of names inside a gen_gki_modules_headers.sh header."""
    names = []
    seen_array = False
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if "static const char gki_" in line:
                seen_array = True
                continue
            if seen_array:
                m = STR_RE.match(line)
                if m:
                    names.append(m.group(1))
    if not seen_array:
        raise ValueError(f"{path}: no gki_*_symbols array (not a generated GKI header?)")
    return names


def read_list(path):
    with open(path, "r", encoding="utf-8") as f:
        return [ln.strip() for ln in f if ln.strip() and not ln.startswith("[")]


def load_tsv(path, sym_col, ko_col):
    out = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) > max(sym_col, ko_col):
                out.setdefault(p[sym_col], set()).add(p[ko_col])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("kout", help="kernel build output dir (holds kernel/gki_module_*.h), or '-' with both list overrides")
    ap.add_argument("kmi_ref", nargs="+", help="harvested KMI reference dir(s) (exports.tsv + required.tsv)")
    ap.add_argument("--exported-list", help="override: names an unsigned module may not export (selftest)")
    ap.add_argument("--protected-list", help="override: names an unsigned module may not import (selftest)")
    a = ap.parse_args()

    try:
        if a.exported_list is not None:
            exported = read_list(a.exported_list)
        else:
            exported = read_header(os.path.join(a.kout, "kernel", "gki_module_exported.h"))
        if a.protected_list is not None:
            protected = read_list(a.protected_list)
        else:
            protected = read_header(os.path.join(a.kout, "kernel", "gki_module_protected.h"))
    except (OSError, ValueError) as e:
        sys.stderr.write(f"FAIL [protect_check]: cannot read the protection tables: {e}\n")
        return 2

    exports, imports = {}, {}
    for ref in a.kmi_ref:
        e, r = os.path.join(ref, "exports.tsv"), os.path.join(ref, "required.tsv")
        if not (os.path.isfile(e) and os.path.isfile(r)):
            sys.stderr.write(f"FAIL [protect_check]: {ref} lacks exports.tsv / required.tsv\n")
            return 2
        for k, v in load_tsv(e, 1, 2).items():
            exports.setdefault(k, set()).update(v)
        for k, v in load_tsv(r, 1, 3).items():
            imports.setdefault(k, set()).update(v)
    mods = set().union(*exports.values(), *imports.values()) if (exports or imports) else set()
    if not imports or not mods:
        sys.stderr.write("FAIL [protect_check]: vacuous check: 0 stock module imports read\n")
        return 2

    bad = []
    for s in exported:
        for ko in sorted(exports.get(s, ())):
            bad.append(f"  EXPORT-REFUSED {ko} exports protected {s}")
    for s in protected:
        for ko in sorted(imports.get(s, ())):
            bad.append(f"  IMPORT-REFUSED {ko} imports protected {s}")
    if bad:
        sys.stderr.write(f"FAIL [protect_check]: {len(bad)} stock-module loads would be refused with -EACCES:\n")
        sys.stderr.write("\n".join(bad[:40]) + ("\n  ...\n" if len(bad) > 40 else "\n"))
        return 1
    print(f"PASS [protect_check]: gki_exported_symbols={len(exported)} gki_protected_symbols={len(protected)}; "
          f"{len(mods)} stock modules, {len(exports)} exported + {len(imports)} imported names, 0 collisions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
