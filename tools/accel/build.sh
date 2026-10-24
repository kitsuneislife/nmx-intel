#!/bin/bash
# build.sh: builds NVAccel (nullmoth's accelerator kext) from our branch nmx-accel-254 (worktree ~/nmx-build/accel/src-254,
# based on v2.5.4; patches in source-fixes/accel/v2.5.4) into ~/nmx-build/accel/out/NVAccel.kext. Needs NVIDIA open-gpu-kernel-modules at tag 615.78.08
# in ~/ogkm615 (git clone --depth 1 --branch 615.78.08 https://github.com/NVIDIA/open-gpu-kernel-modules ~/ogkm615).
# nullmoth's build reads the RM -D flags from a Darwin RM build (_out/Darwin_x86_64/compile_cmds.sh) that is not
# public; this writes one with the defines of upstream src/nvidia/Makefile for x86_64. Built from v2.1.0 the result
# has the release's strings, symbols, __const and __data byte-for-byte equal in size; __text differs by 112 B (compiler);
# built from v2.3.6, strings and symbols are identical to the release and __text differs by 128 B; from v2.5.0 the same
# with 144 B, and the 610 and 615 trees give byte-identical output; from v2.5.4 with 128 B. Older branches still build with SRC=… (OGKM=~/ogkm610 before 2.5):
# nmx-accel-250 (~/nmx-build/accel/src-250, v2.5.0), nmx-accel-236 (~/nmx-build/accel/src-236, v2.3.6), nmx-accel (~/nmx-build/accel/src, v2.1.0).
set -uo pipefail
SRC=${SRC:-$HOME/nmx-build/accel/src-254}; OUT=${OUT:-$HOME/nmx-build/accel/out}; OGKM=${OGKM:-$HOME/ogkm615}
[ -d "$OGKM/src/nvidia" ] || { echo "missing $OGKM (open-gpu-kernel-modules 615.78.08)"; exit 1; }
[ -d "$SRC/kexts/NVRM/accel" ] || { echo "missing $SRC (git worktree add -b nmx-accel-254 ~/nmx-build/accel/src-254 v2.5.4, then git am source-fixes/accel/v2.5.4/*)"; exit 1; }
CC=$OGKM/src/nvidia/_out/Darwin_x86_64/compile_cmds.sh
if [ ! -f "$CC" ]; then
  mkdir -p "$(dirname "$CC")"
  echo "cc -D_LANGUAGE_C -D__NO_CTYPE -DNVRM -DLOCK_VAL_ENABLED=0 -DPORT_ATOMIC_64_BIT_SUPPORTED=1 -DPORT_IS_KERNEL_BUILD=1 -DPORT_IS_CHECKED_BUILD=0 -DPORT_MODULE_atomic=1 -DPORT_MODULE_core=1 -DPORT_MODULE_cpu=1 -DPORT_MODULE_crypto=1 -DPORT_MODULE_debug=1 -DPORT_MODULE_memory=1 -DPORT_MODULE_safe=1 -DPORT_MODULE_string=1 -DPORT_MODULE_sync=1 -DPORT_MODULE_thread=1 -DPORT_MODULE_time=1 -DPORT_MODULE_util=1 -DPORT_MODULE_example=0 -DPORT_MODULE_mmio=0 -DRS_STANDALONE=0 -DRS_STANDALONE_TEST=0 -DRS_COMPATABILITY_MODE=1 -DRS_PROVIDES_API_STATE=0 -DNV_CONTAINERS_NO_TEMPLATES -DNV_PRINTF_STRINGS_ALLOWED=1 -DNV_ASSERT_FAILED_USES_STRINGS=1 -DPORT_ASSERT_FAILED_USES_STRINGS=1 -DNV_X86_64 -DNV_ARCH_BITS=64 -DNVCPU_X86_64 -DNV_UNIX" > "$CC"
fi
rm -rf "$OUT"
( cd "$SRC" && OGKM="$OGKM" bash build/accel_build.sh kexts/NVRM "$OUT" ) || { echo "build failed: $OUT/accel.err"; exit 1; }
B=$OUT/NVAccel.kext/Contents/MacOS/NVAccel
echo "NVAccel $(shasum -a 256 "$B" | cut -c1-8)  branch $(git -C "$SRC" rev-parse --short HEAD)"
