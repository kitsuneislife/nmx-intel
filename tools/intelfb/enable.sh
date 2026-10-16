#!/bin/bash
# Liga, só neste boot, a RTX desenhando o painel da Intel: o NVAccel ganha o NMIntelFB como cabeça 4 e copia cada
# quadro para o painel. Um reboot desfaz. Depois disto, reiniciar o WindowServer (sai da sessão):
#   sudo killall WindowServer
#   sudo bash tools/intelfb/enable.sh status   só mostra o estado
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
if [ "${1:-}" != status ]; then
  ioreg -c NMIntelFB -d1 2>/dev/null | grep -q NMIntelFB || { echo "o NMIntelFB não está ativo neste boot; nada feito"; exit 1; }
  sysctl -w debug.nvaccel_igpu=1 && sysctl -w debug.nvaccelfb=3
fi
echo "== NMIntelFB"; ioreg -c NMIntelFB -d1 -w0 2>/dev/null | grep -E "NMIntelFB|IOFBDependent|NMIntelFBPipe" | head -6
echo "== sysctl"; sysctl debug.nvaccel_igpu debug.nvaccelfb debug.nvaccel_headless debug.nvaccel_iop_ok_h4 2>&1
