# Get the Kindle back on Wi-Fi and find its IP (Windows).
# Each try:
#   - if Windows has the Kindle drive mounted (USB Drive Mode = Wi-Fi off), eject it
#     (re-checked every round: after a reboot the drive mounts late, ~1-2 min in);
#   - flush any stale ARP entry for the Kindle, ping-sweep the subnet, look up its MAC;
#   - succeed only when TCP port 22 actually answers.
# Settings: K4_MAC, K4_SUBNET (e.g. 192.168.1), from the environment or the k4.env file
# ($env:K4_ENV, else <devkit>\k4.env, else <devkit>\..\k4.env). The IP found is written
# back to that file as K4_HOST.
param([int]$Tries = 30)
$root = Split-Path $PSScriptRoot -Parent

$envFile = @($env:K4_ENV, (Join-Path $root 'k4.env'), (Join-Path (Split-Path $root -Parent) 'k4.env')) |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$cfg = @{}
if ($envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Z0-9_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() }
    }
}
function Get-Setting($name) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ($v) { return $v } else { return $cfg[$name] }
}
$mac = Get-Setting 'K4_MAC'
$subnet = Get-Setting 'K4_SUBNET'
if (-not $mac -or -not $subnet) { Write-Output 'Set K4_MAC and K4_SUBNET (env vars or k4.env)'; exit 2 }
$mac = $mac.ToUpper().Replace(':', '-')

function Test-Port($ip, $port, $ms = 2000) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { return $c.ConnectAsync($ip, $port).Wait($ms) -and $c.Connected } catch { return $false } finally { $c.Close() }
}

foreach ($i in 1..$Tries) {
    $vol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Kindle' -and $_.Size -gt 0 }
    if ($vol) {
        Write-Output "Kindle drive mounted at $($vol.DriveLetter): - ejecting"
        (New-Object -ComObject Shell.Application).Namespace(17).ParseName("$($vol.DriveLetter):").InvokeVerb('Eject')
        Start-Sleep 10
    }
    Get-NetNeighbor -AddressFamily IPv4 | Where-Object LinkLayerAddress -eq $mac |
        Remove-NetNeighbor -Confirm:$false -ErrorAction SilentlyContinue
    $jobs = 1..254 | ForEach-Object { (New-Object System.Net.NetworkInformation.Ping).SendPingAsync("$subnet.$_", 500) }
    try { [Threading.Tasks.Task]::WaitAll($jobs) } catch {}
    $n = Get-NetNeighbor -AddressFamily IPv4 | Where-Object { $_.LinkLayerAddress -eq $mac -and $_.State -ne 'Unreachable' } | Select-Object -First 1
    if ($n -and (Test-Port $n.IPAddress 22)) {
        if ($envFile) {
            $lines = @(Get-Content $envFile)
            if ($lines -match '^K4_HOST=') { $lines = $lines -replace '^K4_HOST=.*$', "K4_HOST=$($n.IPAddress)" }
            else { $lines += "K4_HOST=$($n.IPAddress)" }
            $lines | Set-Content -Encoding ascii $envFile
        }
        Write-Output "Kindle at $($n.IPAddress) (ssh port open)"
        exit 0
    }
    Start-Sleep 5
}
Write-Output 'Kindle not found (asleep? Wi-Fi off? not joined to the network?)'
exit 1
