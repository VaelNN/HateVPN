#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'Запустите с sudo.' >&2
  exit 1
fi
if [[ $# -ne 1 || ! $1 =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
  echo 'Использование: sudo bash scripts/revoke-client.sh ИМЯ_УСТРОЙСТВА' >&2
  exit 1
fi
name=$1
config=/etc/wireguard/hatevpn.conf
client_file=/etc/wireguard/hatevpn-clients/$name.conf
if [[ ! -f $config ]] || ! grep -Fqx "# BEGIN CLIENT $name" "$config"; then
  echo "Устройство $name не найдено." >&2
  exit 1
fi

umask 077
temp=$(mktemp /etc/wireguard/hatevpn.conf.XXXXXX)
trap 'rm -f "$temp"' EXIT
awk -v name="$name" '
  $0 == "# BEGIN CLIENT " name { skip=1; next }
  $0 == "# END CLIENT " name { skip=0; next }
  !skip { print }
' "$config" > "$temp"
chmod 600 "$temp"
mv "$temp" "$config"
systemctl reload wg-quick@hatevpn
rm -f "$client_file"
echo "Доступ устройства $name отозван."
