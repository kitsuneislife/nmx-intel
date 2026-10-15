#!/bin/bash
# Build completo do NMXGPU, na ordem dos scripts do nullmoth. Log em ~/nmx-build/build-all.log
# Uso: build-all.sh [etapas], ex.: build-all.sh xe kext  (padrão: todas)
export NMX_SRC=$HOME/nmx-build/gpu-src
cd $NMX_SRC/xkpi || exit 1
steps=${*:-amd rt i915 xe kext}
for s in $steps; do
  echo "== $s"; date
  case $s in
    amd)  ./all.sh 20 ;;
    rt)   ./rt.sh
          # rt.sh compila todo xnu/*.cpp; o do NMXNPU não entra no NMXGPU (o kext-npu/build.sh tira ele assim)
          mkdir -p obj-npu-glue && mv -f xnuobj/nmx_npu_kext.o obj-npu-glue/ ;;
    i915) ./all-i915.sh 20 ;;
    xe)   ./all-xe.sh 20 ;;
    kext) mkdir -p $HOME/nmx-build/out && ./kext/build.sh $HOME/nmx-build/out ;;
  esac
done
date
