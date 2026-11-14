#!/usr/bin/env bash
# fetch-kernel-source.sh — fetch the pinned Google ACK tree (sources.lock) as a
# +archive tarball and import it as ONE local git commit with a fixed identity
# and fixed dates, so the local commit hash is the same on every machine.
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJ/sources.lock"

REF="$KERNEL_COMMON_UPSTREAM_REF"
KSRC="${KERNEL_SRC:-$PROJ/.build/kernel-src}"
TARBALL="$PROJ/.build/kernel-common-${REF:0:8}.tar.gz"
URL="${KERNEL_COMMON_URL}/+archive/${REF}.tar.gz"

mkdir -p "$PROJ/.build"
if [[ ! -s "$TARBALL" ]]; then
  echo "Downloading ACK ${KERNEL_COMMON_BRANCH} @ ${REF:0:12} ..."
  curl -fL --retry 5 --retry-delay 2 -o "$TARBALL.tmp" "$URL"
  mv "$TARBALL.tmp" "$TARBALL"
fi

echo "Extracting -> $KSRC"
rm -rf "$KSRC"; mkdir -p "$KSRC"
tar -xzf "$TARBALL" -C "$KSRC"

V="$(awk -F' = ' '/^VERSION/{v=$2} /^PATCHLEVEL/{p=$2} /^SUBLEVEL/{s=$2} END{print v"."p"."s}' "$KSRC/Makefile")"
[[ "$V" == "$KERNEL_COMMON_VERSION" ]] || { echo "ERROR: tree is $V, sources.lock says $KERNEL_COMMON_VERSION" >&2; exit 1; }

(
  cd "$KSRC"
  export GIT_AUTHOR_NAME=RizaKernel GIT_AUTHOR_EMAIL=riza@local GIT_COMMITTER_NAME=RizaKernel GIT_COMMITTER_EMAIL=riza@local
  export GIT_AUTHOR_DATE="2000-01-01T00:00:00Z" GIT_COMMITTER_DATE="2000-01-01T00:00:00Z"
  git init -q -b main
  git config user.name RizaKernel; git config user.email riza@local
  git add -A
  git commit -q --no-gpg-sign -m "Import Google ACK ${KERNEL_COMMON_BRANCH} ${REF} (${V})"
)
GOT="$(git -C "$KSRC" rev-parse HEAD)"
echo "Kernel source ready at $KSRC: $V, local import commit $GOT"
if [[ -n "${KERNEL_COMMON_REF:-}" && "$GOT" != "$KERNEL_COMMON_REF" ]]; then
  echo "ERROR: import commit $GOT != sources.lock KERNEL_COMMON_REF $KERNEL_COMMON_REF" >&2
  exit 1
fi
