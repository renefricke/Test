# WLAN-Diagnose fuer Windows. Nur lesend, aendert nichts.
# Aufruf in PowerShell:  powershell -ExecutionPolicy Bypass -File .\wlan-check.ps1
function HR($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function WARN($t){ Write-Host "  [!] $t" -ForegroundColor Yellow }

HR "1. Verbindung (Signal, Kanal, Band, Datenrate)"
$i = netsh wlan show interfaces; $i
$sig = ($i | Select-String 'Signal\s*:\s*(\d+)%').Matches.Groups[1].Value
if ($sig -and [int]$sig -lt 60) { WARN "Schwaches Signal ($sig %). Naeher an den Router oder einen Repeater/Mesh nutzen." }
if ($i -match '802\.11n' -or $i -match '2[,.]4 GHz') { WARN "Wahrscheinlich 2,4 GHz/WLAN 4: langsam. 5 GHz bevorzugen." }

HR "2. Nachbarnetze und Kanaele"
$n = netsh wlan show networks mode=bssid
$n | Select-String 'SSID|Signal|Kanal|Channel'
Write-Host "Netze je Kanal:"
$n | Select-String '(Kanal|Channel)\s*:\s*(\d+)' | ForEach-Object { $_.Matches.Groups[2].Value } | Group-Object | Sort-Object Count -Descending | Format-Table Count,Name -AutoSize

HR "3. Latenz und Paketverlust: Router gegen Internet"
$gw = (Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1).NextHop
"Router: $gw"
foreach ($h in @($gw,'1.1.1.1')) {
  $r = Test-Connection $h -Count 20 -ErrorAction SilentlyContinue
  $ms = ($r | ForEach-Object { if ($_.Latency -ne $null) { $_.Latency } else { $_.ResponseTime } } | Measure-Object -Average -Maximum)
  "{0,-15} Mittel {1:N0} ms  Max {2} ms  Verlust {3} %" -f $h, $ms.Average, $ms.Maximum, (100 - $r.Count*5)
}
Write-Host "  Deutung: Ist schon der Router schlecht, liegt es am WLAN. Ist nur 1.1.1.1 schlecht, liegt es am Internetanschluss."

HR "4. DNS-Antwortzeit"
foreach ($d in 'google.com','wikipedia.org') { $t = Measure-Command { Resolve-DnsName $d -DnsOnly -ErrorAction SilentlyContinue | Out-Null }; "  {0}: {1:N0} ms" -f $d,$t.TotalMilliseconds }

HR "5. Programme mit vielen Netzwerkverbindungen (Bandbreitenfresser)"
Get-NetTCPConnection -State Established | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 10 |
  ForEach-Object { "{0,4}  {1}" -f $_.Count, (Get-Process -Id $_.Name -ErrorAction SilentlyContinue).ProcessName }
Write-Host "  Typisch: OneDrive, Windows Update/Uebermittlungsoptimierung, Steam, Teams, Backups."

HR "6. Treiber, Energiesparen, VPN"
Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11' } | Format-Table Name,InterfaceDescription,DriverVersion,DriverDate,LinkSpeed -AutoSize
powercfg /query SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 2>$null | Select-String 'Aktuelle|Current' | Select-Object -First 2
Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'VPN|TAP|WireGuard|Tunnel' -and $_.Status -eq 'Up' } | ForEach-Object { WARN "VPN aktiv: $($_.InterfaceDescription)" }
Write-Host "  Ein Treiber, der aelter als 2 Jahre ist, verdient ein Update beim Hersteller (Intel, Realtek, ...)."

HR "Fertig"
Write-Host "Andere Geraete im Netz (Smart-TV, Konsolen) siehst du nur im Router, z. B. bei der FRITZ!Box unter http://fritz.box > Heimnetz."
