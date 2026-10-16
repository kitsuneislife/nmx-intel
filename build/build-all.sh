#!/bin/bash
# Build completo do NMXGPU, na ordem dos scripts do nullmoth. Log em ~/nmx-build/build-all.log
# Uso: build-all.sh [etapas], ex.: build-all.sh xe kext  (padrão: todas, sem debug)
# debug: recompila só drm_print.c com o debug do DRM ligado (DRIVER+KMS, source-fixes/0005). Rodar antes de kext;
#        um 'amd' ou 'nodebug' depois desfaz (nodebug recompila só o drm_print.c sem a flag).  Build de diagnóstico completo: build-all.sh amd rt i915 xe debug kext
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
    debug) ./cc.sh $NMX_SRC/kpi/drm-kmod/drivers/gpu/drm/drm_print.c -DNMX_DRM_DEBUG && echo "drm debug 0x6 ligado" ;;
    nodebug) ./cc.sh $NMX_SRC/kpi/drm-kmod/drivers/gpu/drm/drm_print.c && echo "drm debug desligado" ;;
    kext) mkdir -p $HOME/nmx-build/out && ./kext/build.sh $HOME/nmx-build/out ;;
  esac
done
date
