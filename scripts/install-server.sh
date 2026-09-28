#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'Запустите с sudo.' >&2
  exit 1
fi
if [[ $# -ne 1 || ! $1 =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo 'Использование: sudo bash scripts/install-server.sh ПУБЛИЧНЫЙ_IP_ИЛИ_ДОМЕН' >&2
  exit 1
fi
endpoint=$1
config=/etc/wireguard/hatevpn.conf
if [[ -e $config ]]; then
  echo "Конфигурация уже существует: $config" >&2
  exit 1
fi
if ! command -v apt-get >/dev/null || ! command -v systemctl >/dev/null; then
  echo 'Требуется Ubuntu или Debian с systemd.' >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard iptables qrencode
wan_if=$(ip -4 route show default | awk '/^default / {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')
if [[ -z $wan_if || ! $wan_if =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo 'Не удалось определить внешний сетевой интерфейс.' >&2
  exit 1
fi

umask 077
install -d -m 700 /etc/wireguard /etc/wireguard/hatevpn-clients
private_key=$(wg genkey)
public_key=$(printf '%s' "$private_key" | wg pubkey)
printf '%s\n' "$public_key" > /etc/wireguard/hatevpn-server.pub
printf '%s\n' "$endpoint" > /etc/wireguard/hatevpn-endpoint
cat > "$config" <<EOF
[Interface]
Address = 10.77.0.1/24
ListenPort = 51820
PrivateKey = $private_key
PostUp = iptables -I FORWARD 1 -i %i -o $wan_if -j ACCEPT; iptables -I FORWARD 1 -i $wan_if -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -I POSTROUTING 1 -s 10.77.0.0/24 -o $wan_if -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -o $wan_if -j ACCEPT; iptables -D FORWARD -i $wan_if -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.77.0.0/24 -o $wan_if -j MASQUERADE
EOF
chmod 600 "$config" /etc/wireguard/hatevpn-server.pub /etc/wireguard/hatevpn-endpoint
printf 'net.ipv4.ip_forward = 1\n' > /etc/sysctl.d/70-hatevpn.conf
sysctl -p /etc/sysctl.d/70-hatevpn.conf
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  ufw allow 51820/udp
fi
systemctl enable --now wg-quick@hatevpn
echo "HateVPN запущен. Откройте UDP 51820 в панели VPS, если нужен отдельный сетевой firewall."
