#!/bin/bash
# build.sh: builds NVAccel (nullmoth's accelerator kext) from our branch nmx-accel (based on v2.1.0, the release the
# 1401 app installed) into ~/nmx-build/accel/out/NVAccel.kext. Needs NVIDIA open-gpu-kernel-modules at tag 610.57.04
# in ~/ogkm610 (git clone --depth 1 --branch 610.57.04 https://github.com/NVIDIA/open-gpu-kernel-modules ~/ogkm610).
# nullmoth's build reads the RM -D flags from a Darwin RM build (_out/Darwin_x86_64/compile_cmds.sh) that is not
# public; this writes one with the defines of upstream src/nvidia/Makefile for x86_64. Built from v2.1.0 the result
# has the release's strings, symbols, __const and __data byte-for-byte equal in size; __text differs by 112 B (compiler).
set -uo pipefail
SRC=${SRC:-$HOME/nmx-build/accel/src}; OUT=${OUT:-$HOME/nmx-build/accel/out}; OGKM=${OGKM:-$HOME/ogkm610}
[ -d "$OGKM/src/nvidia" ] || { echo "missing $OGKM (open-gpu-kernel-modules 610.57.04)"; exit 1; }
[ -d "$SRC/kexts/NVRM/accel" ] || { echo "missing $SRC (git worktree add -b nmx-accel ~/nmx-build/accel/src v2.1.0)"; exit 1; }
CC=$OGKM/src/nvidia/_out/Darwin_x86_64/compile_cmds.sh
if [ ! -f "$CC" ]; then
  mkdir -p "$(dirname "$CC")"
  echo "cc -D_LANGUAGE_C -D__NO_CTYPE -DNVRM -DLOCK_VAL_ENABLED=0 -DPORT_ATOMIC_64_BIT_SUPPORTED=1 -DPORT_IS_KERNEL_BUILD=1 -DPORT_IS_CHECKED_BUILD=0 -DPORT_MODULE_atomic=1 -DPORT_MODULE_core=1 -DPORT_MODULE_cpu=1 -DPORT_MODULE_crypto=1 -DPORT_MODULE_debug=1 -DPORT_MODULE_memory=1 -DPORT_MODULE_safe=1 -DPORT_MODULE_string=1 -DPORT_MODULE_sync=1 -DPORT_MODULE_thread=1 -DPORT_MODULE_time=1 -DPORT_MODULE_util=1 -DPORT_MODULE_example=0 -DPORT_MODULE_mmio=0 -DRS_STANDALONE=0 -DRS_STANDALONE_TEST=0 -DRS_COMPATABILITY_MODE=1 -DRS_PROVIDES_API_STATE=0 -DNV_CONTAINERS_NO_TEMPLATES -DNV_PRINTF_STRINGS_ALLOWED=1 -DNV_ASSERT_FAILED_USES_STRINGS=1 -DPORT_ASSERT_FAILED_USES_STRINGS=1 -DNV_X86_64 -DNV_ARCH_BITS=64 -DNVCPU_X86_64 -DNV_UNIX" > "$CC"
fi
rm -rf "$OUT"
( cd "$SRC" && OGKM="$OGKM" bash build/accel_build.sh kexts/NVRM "$OUT" ) || { echo "build failed: $OUT/accel.err"; exit 1; }
B=$OUT/NVAccel.kext/Contents/MacOS/NVAccel
echo "NVAccel $(shasum -a 256 "$B" | cut -c1-8)  branch $(git -C "$SRC" rev-parse --short HEAD)"
