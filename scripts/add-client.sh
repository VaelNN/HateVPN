#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'Запустите с sudo.' >&2
  exit 1
fi
if [[ $# -ne 1 || ! $1 =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
  echo 'Использование: sudo bash scripts/add-client.sh ИМЯ_УСТРОЙСТВА' >&2
  exit 1
fi
name=$1
config=/etc/wireguard/hatevpn.conf
client_dir=/etc/wireguard/hatevpn-clients
client_file=$client_dir/$name.conf
if [[ ! -f $config || ! -f /etc/wireguard/hatevpn-server.pub || ! -f /etc/wireguard/hatevpn-endpoint ]]; then
  echo 'Сначала запустите install-server.sh.' >&2
  exit 1
fi
if [[ -e $client_file ]] || grep -Fqx "# BEGIN CLIENT $name" "$config"; then
  echo "Устройство $name уже существует." >&2
  exit 1
fi

address=''
for n in $(seq 2 254); do
  if ! grep -Fq "AllowedIPs = 10.77.0.$n/32" "$config"; then
    address="10.77.0.$n"
    break
  fi
done
if [[ -z $address ]]; then
  echo 'Свободных адресов не осталось.' >&2
  exit 1
fi

umask 077
private_key=$(wg genkey)
public_key=$(printf '%s' "$private_key" | wg pubkey)
server_public_key=$(cat /etc/wireguard/hatevpn-server.pub)
endpoint=$(cat /etc/wireguard/hatevpn-endpoint)
cat > "$client_file" <<EOF
[Interface]
PrivateKey = $private_key
Address = $address/32
DNS = 1.1.1.1

[Peer]
PublicKey = $server_public_key
Endpoint = $endpoint:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 "$client_file"
cat >> "$config" <<EOF

# BEGIN CLIENT $name
[Peer]
PublicKey = $public_key
AllowedIPs = $address/32
# END CLIENT $name
EOF
systemctl reload wg-quick@hatevpn
echo "Профиль создан: $client_file"
