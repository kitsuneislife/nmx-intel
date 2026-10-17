#!/bin/bash
# auto.sh: liga sozinho, a cada boot, o desktop acelerado (RTX compõe, NMIntelFB mostra no painel) — o que enable.sh +
# killall faziam à mão (RTX-15). Roda como LaunchDaemon: espera o NMIntelFB e roda enable.sh; o WindowServer adota a
# RTX sozinho (RTX-16). Só se nenhum quadro chegar em 90 s na tela de login ele reinicia o WindowServer.
#   sudo bash tools/intelfb/auto.sh install    instala (vale no próximo boot)
#   sudo bash tools/intelfb/auto.sh remove     remove
#   sudo nvram nullmoth-intelfb-auto=0          desliga sem remover (apagar a variável religa)
# Log: /usr/bin/log show --last 10m --predicate 'eventMessage CONTAINS "nmx-intelfb-auto"'
LABEL=com.nmxintel.intelfb-auto
BIN=/usr/local/libexec/nmx-intelfb-auto.sh
EN=/usr/local/libexec/nmx-intelfb-enable.sh
PL=/Library/LaunchDaemons/$LABEL.plist
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
say() { logger -t nmx-intelfb-auto "$*"; echo "$*"; }

case "${1:-run}" in
install)
    cd "$(dirname "$0")" || exit 1
    bash -n enable.sh || exit 1
    mkdir -p /usr/local/libexec
    cp "$0" "$BIN" && cp enable.sh "$EN" || exit 1
    chown root:wheel "$BIN" "$EN" && chmod 755 "$BIN" "$EN"
    cat > "$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$BIN</string>
		<string>run</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
    chown root:wheel "$PL" && chmod 644 "$PL"
    echo "instalado: $BIN e $PL (vale a partir do próximo boot)"
    ;;
remove)
    launchctl bootout system "$PL" 2>/dev/null
    rm -f "$PL" "$BIN" "$EN"
    echo "removido"
    ;;
run)
    [ "$(nvram nullmoth-intelfb-auto 2>/dev/null | awk '{print $2}')" = 0 ] && { say "off (nullmoth-intelfb-auto=0)"; exit 0; }
    # NMIntelFB takes the panel nullmoth-intelfb-delay seconds after start, under NVRM; give it up to 5 minutes
    for i in $(seq 1 150); do
        ioreg -r -c NMIntelFB -d1 2>/dev/null | grep -q NMIntelFB && sysctl -n debug.nmintelfb_agdc >/dev/null 2>&1 && break
        sleep 2
    done
    ioreg -r -c NMIntelFB -d1 2>/dev/null | grep -q NMIntelFB || { say "no NMIntelFB this boot; nothing done"; exit 0; }
    [ "$(sysctl -n debug.nvaccel_iop 2>/dev/null)" = 1 ] && { say "already on"; exit 0; }
    # the manual runs (RTX-15) enabled about a minute after NMIntelFB came up; keep that margin
    sleep 15
    ok=0
    for i in 1 2 3; do bash "$EN" >/dev/null 2>&1 && { ok=1; break; }; sleep 10; done
    [ $ok = 1 ] || { say "enable.sh failed 3 times; WindowServer left alone"; exit 1; }
    say "enabled: agdc $(sysctl -n debug.nmintelfb_agdc) iop $(sysctl -n debug.nvaccel_iop)"
    # RTX-16: the running WindowServer took the accelerated panel by itself ~45 s after enabling (no restart). Restart
    # it only if no frame arrived in 90 s and nobody is logged in yet (the login window's console owner is
    # _windowserver, or root early on).
    for i in $(seq 1 45); do [ "$(sysctl -n debug.nvaccel_iop_ok)" != 0 ] && break; sleep 2; done
    owner=$(stat -f %Su /dev/console)
    if [ "$(sysctl -n debug.nvaccel_iop_ok)" != 0 ]; then
        say "frames reach the panel (iop_ok $(sysctl -n debug.nvaccel_iop_ok)); no restart"
    elif [ "$owner" = root ] || [ "$owner" = _windowserver ]; then
        say "no frame after 90 s at the login window: restarting WindowServer onto the RTX"
        killall -9 WindowServer
    else
        say "no frame after 90 s and $owner is logged in: accelerated after the next WindowServer restart"
    fi
    ;;
*) echo "uso: auto.sh install|remove"; exit 1 ;;
esac
