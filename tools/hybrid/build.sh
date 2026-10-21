#!/bin/zsh
# Builds the hybrid route's Iris Xe stack for Sequoia: JulioNectar's NootedGreen fork plus its user-space Metal pieces,
# pinned to $XPS_REV, with our diffs from source-fixes/hybrid/*.patch. Apple's 16.0.32 driver bundles come from
# NootedGreen's sle_Internal at $NG_REV. Output stays in ~/nmx-build/hybrid (TSNPL code and Apple binaries: never
# versioned here). Nothing is installed. Patches: source-fixes/hybrid/*.patch on Julio's tree, ng/*.patch on NootedGreen.
set -euo pipefail
HERE=${0:A:h:h:h}
W=$HOME/nmx-build/hybrid; XPS=$W/xps
XPS_REPO=https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe.git; XPS_REV=356c818
NG_REPO=https://github.com/sgiammori/NootedGreen.git; NG_REV=95f81898be65cb9f7b3d370ca78054be4cc8a62d
NG=$XPS/build/deps/NootedGreen

[[ -d $XPS/.git ]] || git clone -q $XPS_REPO $XPS
git -C $XPS checkout -q -f $XPS_REV   # -f drops a previous run's patches
[[ -d $NG/.git ]] || git clone -q $NG_REPO $NG
git -C $NG checkout -q -f $NG_REV
for p in $HERE/source-fixes/hybrid/*.patch(N); do
  git -C $XPS apply $p
  echo "patch: ${p:t}"
done
for p in $HERE/source-fixes/hybrid/ng/*.patch(N); do
  git -C $NG apply $p
  echo "patch (NootedGreen): ${p:t}"
done

(cd $XPS && zsh build-nootedgreen.sh)
zsh $XPS/macos/build-all.sh $NG/sle_Internal/sle

# HookCase.kext: NootedGreen's symbol library (org.smichaud.HookCase), a dependency of both TGL kexts. Its kern_start
# does nothing; it exports the register/DSB helpers and probePortMode the framebuffer imports. Built without Xcode
# like NootedGreen, with no IOKit personality (as Julio's build-hookcase.sh, which is not in his public repo).
HC=$NG/HookCase-master/HookCase; HCK=$XPS/build/HookCase.kext; SDK=$NG/MacKernelSDK; T=$(mktemp -d)
rm -rf $HCK; mkdir -p $HCK/Contents/MacOS $T/inc
# the SDK declares strnstr(char *, ...), HookCase defines its own const variant: hide the SDK's declaration
printf '#define strnstr nmx_sdk_strnstr\n#include_next <string.h>\n#undef strnstr\n' > $T/inc/string.h
HF=(-arch x86_64 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector -mmacosx-version-min=13.0
    -mmmx -msse -msse2 -msse3 -mssse3 -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
    -D__null_terminated= -D__stateful_pure= -isystem $T/inc -isystem $SDK/Headers -O2 -Wno-vla -Wno-unknown-warning-option)
cat > $T/info.c <<'EOC'
#include <mach/mach_types.h>
extern kern_return_t HookCase_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t HookCase_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(org.smichaud.HookCase, "8.0.1", HookCase_kern_start, HookCase_kern_stop)
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOC
clang $HF -c $T/info.c -o $T/info.o
clang $HF -c $HC/HookCase.s -o $T/HookCaseS.o
clang++ $HF -std=gnu++17 -nostdinc++ -fno-exceptions -fno-rtti -fapple-kext -fno-asynchronous-unwind-tables \
  -w -c $HC/HookCase.cpp -o $T/HookCase.o
clang++ -arch x86_64 -mkernel -nostdlib -static -Xlinker -kext -Xlinker -export_dynamic -mmacosx-version-min=13.0 \
  $T/*.o $SDK/Library/x86_64/libkmod.a -lcc_kext -o $HCK/Contents/MacOS/HookCase 2>/dev/null
sed -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/org.smichaud.HookCase/g' -e 's/$(EXECUTABLE_NAME)/HookCase/g' \
    -e 's/$(PRODUCT_NAME[^)]*)/HookCase/g' -e 's/$(MODULE_VERSION)/8.0.1/g' $HC/Info.plist > $HCK/Contents/Info.plist
plutil -remove IOKitPersonalities $HCK/Contents/Info.plist
HCX=$(nm -gU $HCK/Contents/MacOS/HookCase)   # once: grep -q on a pipe can SIGPIPE nm and trip pipefail
for s in __ZN17AppleIntelPortHAL13probePortModeEv __ZN24AppleIntelBaseController14ReadRegister32Em _strnstr _gpu_describe; do
  [[ $HCX == *" $s"$'\n'* || $HCX == *" $s" ]] || { echo "HookCase does not export $s"; exit 1; }
done
codesign -f -s - $HCK >/dev/null 2>&1 || true
rm -rf $T

for f in $XPS/build/NootedGreen.kext/Contents/MacOS/NootedGreen $HCK/Contents/MacOS/HookCase $XPS/macos/out/libxedrv.dylib \
         $XPS/macos/out/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver; do
  echo "${f:t} $(shasum -a 256 $f | cut -c1-8)"
done
