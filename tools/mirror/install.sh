#!/bin/bash
# install.sh [remove]: instala o nmx-mirror como LaunchAgent (tela de login e sessão). Ver nmx-mirror.c.
set -e
cd "$(dirname "$0")"
BIN=/usr/local/libexec/nmx-mirror
PL=/Library/LaunchAgents/com.nmxintel.mirror.plist
if [ "$1" = remove ]; then
    rm -f "$PL" "$BIN"
    echo "removido (vale no próximo login)"
    exit 0
fi
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
rm -f /tmp/nmx-mirror.log  # old versions logged here; a root-owned copy blocks the user-session agent
mkdir -p /usr/local/libexec
clang -O2 -o "$BIN" nmx-mirror.c -framework CoreGraphics -framework IOKit -framework CoreFoundation
cp com.nmxintel.mirror.plist "$PL"
chown root:wheel "$PL" "$BIN"
chmod 644 "$PL"
chmod 755 "$BIN"
echo "instalado: $BIN e $PL (vale a partir do próximo boot)"
