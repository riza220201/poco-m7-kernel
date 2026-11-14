# Riza Kernel — Xiaomi POCO M7 (`creek`)

A GKI build-and-gate pipeline for the **Xiaomi POCO M7 (`creek`, Qualcomm Snapdragon 685 `SM6225` "khaje", `android13-5.15`)**, stock firmware HyperOS 3 `OS3.0.305.0.WBOMIXM` (Android 16, global).

> **Status:** built from Google ACK `android13-5.15-lts` (**Linux 5.15.223**, 29 LTS releases ahead of stock `5.15.194`) with **Neutron Clang 24**, gated clean across all **564 device modules** (`562 vendor + 2 system_dlkm`), all **8,575 stock `vmlinux` exports**, and the vendor modules' **CFI type ids**, and run under QEMU. **Not yet booted on a phone.**

## Variants & Features

| Variant | What | `uname -r` |
|---|---|---|
| **vanilla** | BORE 7.0.0 + BBRv3 + Reflex 0.4.0 + `creek_balance` + ADIOS 3.3.0 + Kcompressd 0.5 + le9uo 1.14 + ntsync + MGLRU + LZ4HC + DS4 clone fix, no root | `5.15.223-Riza-vanilla` |
| **ksunext** | vanilla + KernelSU-Next **33553** (`v3.4.2-198-g7ccf6147`, **uapi 6**) + SuSFS **v2.4.0** | `5.15.223-Riza-ksunext` |

* **Scheduler:** **BORE 7.0.0** on 5.15's CFS, its state in `struct sched_entity`'s four KABI-reserved slots. Toggle live: `sysctl kernel.sched_bore=0`.
* **CPUFreq:** **Reflex 0.4.0** (selectable per policy, `latency_weight` default 300; Energy Model read in µW — 5.15's is mW) + **`creek_balance`** (boot boost, touch floor, screen-off cap from the `panel0-backlight` device; `policy0` = 4× A53, `policy4` = 4× A73). Tunables: `/sys/module/creek_balance/parameters/`. The stock vendor governor stays the default.
* **Memory:** **MGLRU on**, **Kcompressd 0.5** (`vm.kcompressd`), **le9uo 1.14** (dormant: `vm.workingset_protection=0`), **LZ4HC** for the stock `zram.ko` (`echo lz4hc > /sys/block/zram0/comp_algorithm`).
* **Storage:** **ADIOS 3.3.0** (opt-in) + BFQ + Kyber + mq-deadline.
* **Network:** **Google BBRv3** default + **fq** default qdisc + CAKE + Westwood / Vegas / H-TCP + TTL/HL targets. Every struct size and offset the stock modules see is unchanged (pinned by `BUILD_BUG_ON`s).
* **Compat:** **ntsync** (`/dev/ntsync`, Wine / Winlator), **DualShock 4 clones** over USB, `epoll_pwait2` (native in 5.15).
* **ksunext manager (uapi 6):** install the KernelSU-Next CI manager of `7ccf6147` (versionCode `33553`, Actions run `43601257081`), not the v3.4.2 release APK. Uninstall an older manager first.

## The Point of This Repo

Not "a kernel with tweaks": **six gates that refuse to ship a kernel that would break the phone's modules**, each proven able to fail.

```text
layer 1  symbol CRCs & module_layout (0x0222dd63) against 562 vendor + 2 system_dlkm modules
layer 2  5.15 GKI module protection tables (export- and access-protected) vs every stock module
layer 3  28,693 vendor + 151 system_dlkm import edges: 0 unresolved, 0 CRC mismatch, 0 unwhitelisted
layer 4  8,575 / 8,575 stock vmlinux exports with identical CRCs
layer 5  no stock module exports a name vmlinux exports (5.15 refuses such a module)
layer 6  CFI type ids: every id the vendor modules share with the kernel hashes as with Google's own clang
```

```bash
bash test/kmi-gate-selftest.sh          # layer 1
bash test/protect-gate-selftest.sh      # layer 2
bash test/import-gate-selftest.sh       # layer 3
bash test/stock-symvers-gate-selftest.sh  # layer 4
bash test/dup-export-gate-selftest.sh   # layer 5
bash test/cfi-gate-selftest.sh          # layer 6
test/runtime-qemu-selftest.sh           # boots the Image: BORE, ntsync, MGLRU, le9uo, BBRv3, stock zram + Kcompressd
test/adios-qemu-selftest.sh             # boots the Image: flush/FUA I/O through ADIOS
```

## Build, Gate & Package

Put the stock `boot.img`, `vendor_boot.img`, `vendor_dlkm.img`, `system_dlkm.img` in the repository root, then:

```bash
./tools/fetch-kernel-source.sh       # ACK android13-5.15-lts @ sources.lock, imported as a reproducible commit
./tools/extract-device-material.sh   # stock config, stock.symvers, KMI reference trees
./build.sh --stock                   # control build: pristine ACK + the six gates
./build.sh vanilla                   # patches/series + config/vanilla_defconfig + the six gates
./build.sh ksunext                   # vanilla + KernelSU-Next + SuSFS + the six gates
./package.sh vanilla|ksunext         # AnyKernel3 zip + repacked boot.img, self-tested against the stock boot.img
```

Layer 6 needs a reference `vmlinux` built from the pristine tree with Google's clang-r450784e at `.build/cfi-ref/vmlinux`. On a shared build host, run scripts through `tools/hive-run.sh` (a clean environment).

## Credits

GKI is Google's. BORE, Reflex, ADIOS, Kcompressd-Unofficial and le9uo are firelzrd's (Kcompressd after Qun-Wei Lin, MediaTek); BBRv3 is Google's (Neal Cardwell et al.); ntsync is Elizabeth Figura's (CodeWeavers). KernelSU-Next, pershoot's `dev-susfs`, simonpunk's SuSFS. Neutron Clang is Neutron-Toolchains'. AnyKernel3 is osm0sis'.
