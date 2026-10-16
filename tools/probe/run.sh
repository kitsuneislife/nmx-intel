#!/bin/bash
# Roda no boot pelo LaunchDaemon com.kitsune.nmxprobe: espera o WindowServer subir e grava o que o caminho do
# Metal da Intel vê em /Users/Shared/nmx-probe.txt (o boot anterior fica em nmx-probe.prev.txt).
OUT=/Users/Shared/nmx-probe.txt
[ -f "$OUT" ] && mv -f "$OUT" /Users/Shared/nmx-probe.prev.txt
for t in 45 120; do
  sleep $(( t == 45 ? 45 : 75 ))
  {
    echo "===== $(date) (t=${t}s), boot $(sysctl -n kern.boottime)"
    echo "boot-args: $(nvram boot-args 2>&1)"
    nvram nullmoth-gpu-trail 2>&1; nvram nullmoth-gpu-beat 2>&1; nvram nullmoth-gpu-fb 2>&1
    MESA_LOG_LEVEL=debug /usr/local/nmx-probe/nmx-probe 2>&1
    echo "== IOAccelerator / IOFramebuffer"
    ioreg -w0 -r -c IOAccelerator 2>&1 | grep -E '^\+-o|"IOClass"|MetalPluginName|"PerformanceStatistics"' | head -20
    ioreg -w0 -r -c IOFramebuffer 2>&1 | grep -E '^\+-o' | head
    echo "== WindowServer"
    pgrep -l WindowServer; pgrep -l loginwindow
  } >> "$OUT" 2>&1
done
