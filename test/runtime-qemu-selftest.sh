#!/usr/bin/env bash
# runtime-qemu-selftest.sh — boot a built creek Image under QEMU and RUN the features the
# gates can only see as symbols. (The gates prove the ABI; the POCO X7's v1 passed all of
# them and still panicked on the first fsync with ADIOS selected.)
#
#   test/runtime-qemu-selftest.sh [Image]        # default: out/ksunext/Image, else out/vanilla/Image
#   KEEP=1 test/runtime-qemu-selftest.sh         # keep the work dir (serial log)
#
# In the guest (ARM32 busybox from anykernel/, AArch32 EL0 via cortex-a76):
#   R1  BORE        kernel.sched_bore toggles; a CPU hog accumulates a burst score
#   R2  ntsync      /dev/ntsync registered and openable
#   R3  MGLRU       /sys/kernel/mm/lru_gen/enabled is on (LRU_GEN_ENABLED=y)
#   R4  le9uo       vm.workingset_protection READS BACK what was written — 5.15's
#                   proc_dobool counts maxlen/sizeof(int); sizeof(bool) made it dead
#   R5  BBRv3 + fq  default cc = bbr, default qdisc = fq, all cc built in; a 64 MiB
#                   loopback TCP transfer arrives intact (exercises tcp_rate / tx.in_flight /
#                   delivered_ce, i.e. the 5.15 tcp_skb_cb rework)
#   R6  zram + Kcompressd   the STOCK system_dlkm zsmalloc.ko + zram.ko load into this kernel
#                   (a runtime KMI check of real stock modules), lz4hc selected (via the crypto API),
#                   then 5 x 96 MB of anonymous memory in 384 MiB RAM: kswapd swaps through
#                   kcompressd, and every byte comes back (md5 per process)
#   R7  creek_balance  initialised; with no backlight here the screen-off cap must stay disarmed
#   R8  ksunext only: KernelSU-Next + SusFS initialised
# Fails on any Oops / BUG / WARNING / CFI failure in the serial log.
set -uo pipefail
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${1:-}"
if [[ -z "$IMAGE" ]]; then
  for c in "$PROJ/out/ksunext/Image" "$PROJ/out/vanilla/Image"; do [[ -f "$c" ]] && { IMAGE="$c"; break; }; done
fi
[[ -f "$IMAGE" ]] || { echo "no Image to test (build first, or pass a path)"; exit 2; }
BUSYBOX="$PROJ/anykernel/tools/busybox"
SDLKM="${SDLKM:-$PROJ/.build/kmi-ref-system/system_dlkm}"
for t in qemu-system-aarch64 cpio gzip md5sum; do command -v "$t" >/dev/null || { echo "missing host tool: $t"; exit 2; }; done
for f in "$BUSYBOX" "$SDLKM/zsmalloc.ko" "$SDLKM/zram.ko"; do [[ -f "$f" ]] || { echo "missing $f"; exit 2; }; done
KREL="$(LC_ALL=C grep -aom1 'Linux version [0-9][^ ]*' "$IMAGE" | awk '{print $3}')"

TMP="$(mktemp -d)"
trap '[[ "${KEEP:-0}" == 1 ]] && echo "work dir kept: $TMP" || rm -rf "$TMP"' EXIT
R="$TMP/root"; mkdir -p "$R"/{bin,dev,proc,sys,tmp,lib/modules}
cp "$BUSYBOX" "$R/bin/busybox"; chmod 755 "$R/bin/busybox"
cp "$SDLKM/zsmalloc.ko" "$SDLKM/zram.ko" "$R/lib/modules/"
# md5 of the 96 MB each memory hog holds, computed here so the guest needs no second copy
HOGMD5="$(head -c 100663296 /dev/zero | tr '\0' 'a' | md5sum | cut -d' ' -f1)"

cat > "$R/init" <<EOF
#!/bin/busybox sh
HOGMD5=$HOGMD5
EOF
cat >> "$R/init" <<'EOF'
/bin/busybox --install -s /bin
export PATH=/bin
mknod /dev/kmsg c 1 11; mknod /dev/null c 1 3; mknod /dev/zero c 1 5; mknod /dev/urandom c 1 9
exec 0</dev/null 1>/dev/null 2>/dev/kmsg
mount -t proc proc /proc; mount -t sysfs sysfs /sys
say(){ echo "RIG: $*" >/dev/kmsg; }
FAILED=0; fail(){ say "FAIL: $*"; FAILED=1; }
want(){ [ "$2" = "$3" ] && say "$1 = $2" || fail "$1 = '$2', wanted '$3'"; }
say "kernel $(uname -r) cpus=$(grep -c ^processor /proc/cpuinfo) mem=$(sed -n 's/MemTotal: *//p' /proc/meminfo)"

say "R1 BORE"
want kernel.sched_bore "$(cat /proc/sys/kernel/sched_bore)" 1
echo 0 > /proc/sys/kernel/sched_bore; want "sched_bore after 0" "$(cat /proc/sys/kernel/sched_bore)" 0
echo 1 > /proc/sys/kernel/sched_bore; want "sched_bore after 1" "$(cat /proc/sys/kernel/sched_bore)" 1
( while :; do :; done ) & HOG=$!
sleep 3
SCORE=$(sed -n 's/^se\.burst_score *: *//p' /proc/$HOG/sched)
kill $HOG; wait $HOG 2>/dev/null
[ -n "$SCORE" ] && [ "$SCORE" -gt 0 ] 2>/dev/null && say "busy loop burst_score = $SCORE" || fail "busy loop burst_score '$SCORE' (wanted > 0)"

say "R2 ntsync"
if [ -r /sys/class/misc/ntsync/dev ]; then
  D=$(cat /sys/class/misc/ntsync/dev); mknod /dev/ntsync c ${D%:*} ${D#*:}
  ( exec 3</dev/ntsync ) && say "/dev/ntsync $D opens" || fail "/dev/ntsync does not open"
else fail "no /sys/class/misc/ntsync"; fi

say "R3 MGLRU"
L=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null)
[ -n "$L" ] && [ "$L" != "0x0000" ] && say "lru_gen/enabled = $L" || fail "lru_gen/enabled = '$L'"

say "R4 le9uo sysctls"
want vm.workingset_protection "$(cat /proc/sys/vm/workingset_protection)" 0
echo 1 > /proc/sys/vm/workingset_protection; want "workingset_protection after 1" "$(cat /proc/sys/vm/workingset_protection)" 1
echo 0 > /proc/sys/vm/workingset_protection; want "workingset_protection after 0" "$(cat /proc/sys/vm/workingset_protection)" 0
for s in anon_min_ratio clean_low_ratio clean_min_ratio; do
  v=$(cat /proc/sys/vm/$s); echo 7 > /proc/sys/vm/$s; want "vm.$s after 7" "$(cat /proc/sys/vm/$s)" 7; echo $v > /proc/sys/vm/$s
done

say "R5 BBRv3 + fq"
want tcp_congestion_control "$(cat /proc/sys/net/ipv4/tcp_congestion_control)" bbr
want default_qdisc "$(cat /proc/sys/net/core/default_qdisc)" fq
A=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control); say "available: $A"
for c in bbr cubic westwood htcp vegas; do case " $A " in *" $c "*) ;; *) fail "cc $c missing";; esac; done
ip link set lo up
dd if=/dev/urandom of=/tmp/send bs=1M count=64 2>/dev/null
( nc -l -p 5001 > /tmp/recv ) & L=$!; sleep 1
nc 127.0.0.1 5001 < /tmp/send; sleep 1; kill $L 2>/dev/null; wait $L 2>/dev/null
S=$(md5sum < /tmp/send); Rr=$(md5sum < /tmp/recv)
[ "$S" = "$Rr" ] && say "64 MiB over loopback with bbr: intact" || fail "loopback transfer corrupt or short ($(wc -c < /tmp/recv) bytes)"
rm -f /tmp/send /tmp/recv

say "R6 stock zram + Kcompressd"
insmod /lib/modules/zsmalloc.ko && insmod /lib/modules/zram.ko num_devices=1 || fail "stock zsmalloc/zram did not load"
if [ -d /sys/block/zram0 ]; then
  C=$(cat /sys/block/zram0/comp_algorithm); say "zram lists: $C"
  # The stock zram.ko was built without LZ4HC, so it does not LIST it; 5.15's zcomp accepts any
  # algorithm the crypto API has (crypto_has_comp), and CRYPTO_LZ4HC=y puts lz4hc in vmlinux.
  echo lz4hc > /sys/block/zram0/comp_algorithm || fail "zram refused lz4hc"
  C=$(cat /sys/block/zram0/comp_algorithm)
  case "$C" in *"[lz4hc]"*) say "zram selected: $C" ;; *) fail "lz4hc not selected: $C";; esac
  echo 1G > /sys/block/zram0/disksize
  mknod /dev/zram0 b $(cat /sys/block/zram0/dev | tr ':' ' ')
  mkswap /dev/zram0 >/dev/null && swapon /dev/zram0 || fail "swapon zram0"
  want vm.kcompressd "$(cat /proc/sys/vm/kcompressd)" 24
  KC=$(for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = kcompressd0 ] && echo ${p#/proc/}; done)
  [ -n "$KC" ] && say "kcompressd0 is pid $KC" || fail "no kcompressd0 thread"
  for i in 1 2 3 4 5; do
    ( x=$(head -c 100663296 /dev/zero | tr '\0' 'a'); sleep 12
      [ "$(echo -n "$x" | md5sum | cut -d' ' -f1)" = "$HOGMD5" ] && echo ok > /tmp/hog$i || echo bad > /tmp/hog$i ) &
    sleep 2
  done
  wait
  for i in 1 2 3 4 5; do [ "$(cat /tmp/hog$i 2>/dev/null)" = ok ] || fail "hog $i memory came back wrong ($(cat /tmp/hog$i 2>/dev/null))"; done
  OUT=$(sed -n 's/^pswpout //p' /proc/vmstat); IN=$(sed -n 's/^pswpin //p' /proc/vmstat)
  say "pswpout=$OUT pswpin=$IN zram mm_stat: $(cat /sys/block/zram0/mm_stat)"
  [ "$OUT" -gt 1000 ] 2>/dev/null || fail "almost no swap-out ($OUT): the test did not reach reclaim"
  if [ -n "$KC" ]; then
    T=$(awk '{print $14+$15}' /proc/$KC/stat); say "kcompressd0 cpu ticks = $T"
    [ "$T" -gt 0 ] || fail "kcompressd0 never ran (0 ticks)"
  fi
  swapoff /dev/zram0 || fail "swapoff"
fi

say "R7 creek_balance"
P=/sys/module/creek_balance/parameters
if [ -d $P ]; then
  say "boot_boost_active=$(cat $P/boot_boost_active) backlight_tracks_panel=$(cat $P/backlight_tracks_panel) screen_cap_active=$(cat $P/screen_cap_active)"
  want "screen_cap_active (no backlight here)" "$(cat $P/screen_cap_active)" N
else fail "no $P"; fi

case "$(uname -r)" in *ksunext*)
  say "R8 KernelSU-Next + SusFS"
  dmesg | grep -qi "kernelsu" && say "KernelSU in dmesg: $(dmesg | grep -i kernelsu | head -1 | cut -c1-90)" || fail "no KernelSU init line"
  dmesg | grep -qi "susfs" && say "SusFS in dmesg: $(dmesg | grep -i susfs | head -1 | cut -c1-90)" || fail "no SusFS init line" ;;
esac

[ "$FAILED" = 0 ] && say "ALL TESTS PASSED" || say "SOME TESTS FAILED"
echo o > /proc/sysrq-trigger; sleep 30
EOF
chmod 755 "$R/init"
( cd "$R" && find . | cpio -o -H newc --quiet | gzip -1 ) > "$TMP/initramfs.cpio.gz" || { echo "cpio failed"; exit 2; }

LOG="$TMP/serial.log"
timeout 900 qemu-system-aarch64 -machine virt,gic-version=3 -cpu cortex-a76 -smp 4 -m 384 \
  -nographic -no-reboot -monitor none -serial "file:$LOG" \
  -kernel "$IMAGE" -initrd "$TMP/initramfs.cpio.gz" \
  -append "console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init printk.devkmsg=on nokaslr loglevel=7" \
  </dev/null >/dev/null 2>&1
BAD='Unable to handle|Internal error|Kernel panic|kernel BUG|BUG:|WARNING:|CFI failure|Call trace|RIG: FAIL|SOME TESTS FAILED'
echo "=== runtime self-test (QEMU) — $KREL ==="
grep -a "RIG:" "$LOG" | sed 's/^.*RIG: /  /'
if grep -aEq "$BAD" "$LOG"; then echo "--- problems:"; grep -aE "$BAD|pc :|lr :" "$LOG" | head -20; echo "RESULT: FAIL"; exit 1; fi
grep -aq "RIG: ALL TESTS PASSED" "$LOG" || { echo "RESULT: FAIL (guest never finished)"; tail -5 "$LOG"; exit 1; }
echo "RESULT: PASS"
