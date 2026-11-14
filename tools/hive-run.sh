#!/bin/bash
# hive-run.sh [NAME=value ...] <script> [args...] — run a project script on the shared build
# server in a CLEAN environment. The server exports BASH_ENV=/etc/sra_env.sh, which re-sources a
# loader in EVERY non-interactive bash (Kbuild's link-vmlinux.sh etc.) and resets PATH to one where
# /usr/bin/ld.lld is Ubuntu's LLVM 18 — a silent toolchain mix. env -i drops BASH_ENV and every
# RBE/ccache variable; only the NAME=value pairs given here (and JOBS) pass through.
pass=()
while [[ $# -gt 0 && "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do pass+=("$1"); shift; done
exec env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  TERM=dumb PATH="$HOME/bin:/usr/local/bin:/usr/bin:/bin" ${JOBS:+JOBS="$JOBS"} "${pass[@]}" \
  bash --noprofile --norc "$@"
