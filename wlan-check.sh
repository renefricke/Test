#!/usr/bin/env bash
# WLAN-Diagnose fuer Linux und macOS. Nur lesend, aendert nichts.
# Aufruf: bash wlan-check.sh   (einige Werte brauchen sudo)
set -u
OS=$(uname)
hr(){ printf '\n=== %s ===\n' "$1"; }
warn(){ printf '  [!] %s\n' "$1"; }

hr "1. Verbindung (Signal, Kanal, Band, Datenrate)"
if [ "$OS" = "Darwin" ]; then
  system_profiler SPAirPortDataType 2>/dev/null | sed -n '/Current Network Information/,/Other Local/p' | head -20
else
  IF=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')
  if [ -n "${IF:-}" ]; then
    iw dev "$IF" link
    SIG=$(iw dev "$IF" link | awk '/signal/{print $2}')
    [ -n "$SIG" ] && [ "${SIG%.*}" -lt -70 ] && warn "Schwaches Signal ($SIG dBm). Ab -70 dBm wird es langsam: naeher an den Router oder einen Repeater/Mesh nutzen."
    iw dev "$IF" link | grep -q 'freq: 24' && warn "Du bist im 2,4-GHz-Band: langsam und oft ueberfuellt. 5 GHz (oder 6 GHz) ist meist deutlich schneller."
    echo; echo "Energiesparmodus:"; iw dev "$IF" get power_save 2>/dev/null
    iw dev "$IF" get power_save 2>/dev/null | grep -q on && warn "WLAN-Energiesparen ist an. Das kann Latenz und Aussetzer verursachen."
  else
    nmcli -f IN-USE,SSID,CHAN,RATE,SIGNAL dev wifi 2>/dev/null | grep '\*' || echo "Keine WLAN-Schnittstelle gefunden."
  fi
fi

hr "2. Nachbarnetze auf deinem Kanal (Funkstoerungen)"
if [ "$OS" = "Darwin" ]; then
  system_profiler SPAirPortDataType 2>/dev/null | sed -n '/Other Local Wi-Fi Networks/,$p' | grep -E 'Channel' | sort | uniq -c | sort -rn | head
else
  nmcli -f SSID,CHAN,SIGNAL dev wifi list 2>/dev/null | head -30
  echo "Netze je Kanal:"; nmcli -t -f CHAN dev wifi list 2>/dev/null | sort -n | uniq -c | sort -rn | head
fi
echo "  Tipp: Teilen sich viele Netze deinen Kanal, stelle im Router einen freieren ein (2,4 GHz: nur 1, 6 oder 11)."

hr "3. Latenz und Paketverlust: Router gegen Internet"
GW=$( [ "$OS" = "Darwin" ] && route -n get default 2>/dev/null | awk '/gateway/{print $2}' || ip route | awk '/default/{print $3; exit}')
echo "Router: ${GW:-unbekannt}"
[ -n "${GW:-}" ] && ping -c 20 -i 0.3 "$GW" 2>/dev/null | tail -2
ping -c 20 -i 0.3 1.1.1.1 2>/dev/null | tail -2
echo "  Deutung: Ist schon der Router-Ping schlecht (>10 ms oder Verlust), liegt es am WLAN. Ist nur 1.1.1.1 schlecht, liegt es am Internetanschluss."

hr "4. DNS-Antwortzeit"
for d in google.com wikipedia.org; do
  /usr/bin/time -p nslookup "$d" >/dev/null 2>/tmp/.dns_t; awk '/real/{print "  '"$d"': " $2 " s"}' /tmp/.dns_t
done
echo "  Liegt das ueber 0,1 s, kann ein anderer DNS-Server (z. B. 1.1.1.1 oder 9.9.9.9) helfen."

hr "5. Programme mit vielen Netzwerkverbindungen (Bandbreitenfresser)"
if [ "$OS" = "Darwin" ]; then
  lsof -i -n -P 2>/dev/null | awk 'NR>1{print $1}' | sort | uniq -c | sort -rn | head -10
else
  ss -tunp 2>/dev/null | grep -o 'users:(("[^"]*' | cut -d'"' -f2 | sort | uniq -c | sort -rn | head -10
fi
echo "  Typisch: Cloud-Sync (OneDrive, Dropbox, iCloud), Updates, Torrent, Streaming, Backups."

hr "6. VPN/Proxy aktiv?"
( ifconfig 2>/dev/null || ip link ) | grep -Eo '(utun|tun|wg|tap|ppp)[0-9]+' | sort -u | sed 's/^/  VPN-Schnittstelle: /'
env | grep -i _proxy | sed 's/^/  /'

hr "Fertig"
echo "Andere Geraete im Netz (Smart-TV, Konsolen, Kameras) siehst du nur im Router, z. B. bei der FRITZ!Box unter http://fritz.box > Heimnetz."
