#!/bin/bash
# Liga, só neste boot, a RTX desenhando o painel da Intel: o NVAccel ganha o NMIntelFB (cabeça 0 desde intelfb-0010) e copia cada
# quadro para o painel. Um reboot desfaz. Depois disto, reiniciar o WindowServer (sai da sessão):
#   sudo killall WindowServer
#   sudo bash tools/intelfb/enable.sh status   só mostra o estado
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
if [ "${1:-}" != status ]; then
  ioreg -r -c NMIntelFB -d1 2>/dev/null | grep -q NMIntelFB || { echo "o NMIntelFB não está ativo neste boot; nada feito"; exit 1; }
  # nvaccel_iop=1: display-pipe transactions, the copy into the panel (NVRM's auto-go sets it only when a head
  # published in time, which the 45 s delay prevents)
  sysctl -w debug.nvaccel_igpu=1 && sysctl -w debug.nvaccelfb=3 && sysctl -w debug.nvaccel_iop=1
fi
echo "== NMIntelFB"; ioreg -r -c NMIntelFB -d1 -w0 2>/dev/null | grep -E "NMIntelFB|IOFBDependent|NMIntelFBPipe" | head -6
echo "== sysctl"; sysctl debug.nvaccel_igpu debug.nvaccelfb debug.nvaccel_iop debug.nvaccel_headless debug.nvaccel_heads_published debug.nvaccel_heads_piped debug.nvaccel_iop_ok debug.nvaccel_iop_fail debug.nvaccel_iop_ok_h0 debug.nvaccel_iop_ok_h4 2>&1
