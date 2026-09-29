#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

HOST="${1:?Server address required}"
if [[ ! "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]]; then echo 'Invalid server address' >&2; exit 2; fi
if [[ "$(id -u)" -ne 0 ]]; then echo 'Root SSH access is required' >&2; exit 2; fi
if [[ ! -f /etc/os-release ]]; then echo 'Не удалось определить ОС VPS.' >&2; exit 2; fi
. /etc/os-release
if [[ "${ID:-}" != 'ubuntu' || ( "${VERSION_ID:-}" != '22.04' && "${VERSION_ID:-}" != '24.04' ) ]]; then
  echo "На VPS обнаружена ${PRETTY_NAME:-неизвестная ОС}. Автоустановка доступна для Ubuntu 22.04 и 24.04." >&2
  echo 'Автоматическая настройка этого VPS недоступна.' >&2
  exit 2
fi
if [[ ! -f /etc/hatevpn-amneziawg/client.conf ]] && ss -lunH '( sport = :443 )' | grep -q .; then
  echo 'UDP-порт 443 уже занят другой службой. Освободите порт перед настройкой VPN.' >&2; exit 2
fi

apt-get update -qq
apt-get install -y -qq ca-certificates software-properties-common python3-launchpadlib gnupg2 "linux-headers-$(uname -r)" iptables >/dev/null
if ! grep -Rq 'ppa.launchpadcontent.net/amnezia/ppa' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  add-apt-repository -y ppa:amnezia/ppa >/dev/null
fi
apt-get update -qq
apt-get install -y -qq amneziawg >/dev/null
modprobe amneziawg || { echo 'Модуль AmneziaWG не загрузился. Проверьте ядро и Secure Boot.' >&2; exit 3; }
command -v awg >/dev/null && command -v awg-quick >/dev/null ||
  { echo 'Пакет AmneziaWG не установил awg и awg-quick.' >&2; exit 3; }

install -d -m 700 /etc/hatevpn-amneziawg
install -d -m 700 /etc/amnezia/amneziawg
if [[ ! -f /etc/hatevpn-amneziawg/client.conf ]]; then
  server_private="$(awg genkey)"
  server_public="$(printf '%s' "$server_private" | awg pubkey)"
  client_private="$(awg genkey)"
  client_public="$(printf '%s' "$client_private" | awg pubkey)"
  random_header() { local n; n="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"; echo $((5 + n % 2147483643)); }
  h1="$(random_header)"
  h2="$(random_header)"; while [[ "$h2" == "$h1" ]]; do h2="$(random_header)"; done
  h3="$(random_header)"; while [[ "$h3" == "$h1" || "$h3" == "$h2" ]]; do h3="$(random_header)"; done
  h4="$(random_header)"; while [[ "$h4" == "$h1" || "$h4" == "$h2" || "$h4" == "$h3" ]]; do h4="$(random_header)"; done
  cat > /etc/amnezia/amneziawg/hatevpn.conf <<CONF
[Interface]
Address = 10.88.0.1/24
ListenPort = 443
PrivateKey = $server_private
Jc = 5
Jmin = 40
Jmax = 70
S1 = 20
S2 = 40
H1 = $h1
H2 = $h2
H3 = $h3
H4 = $h4
PostUp = iptables -t nat -A POSTROUTING -s 10.88.0.0/24 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.88.0.0/24 -j MASQUERADE

[Peer]
PublicKey = $client_public
AllowedIPs = 10.88.0.2/32
CONF
  cat > /etc/hatevpn-amneziawg/client.conf <<CONF
[Interface]
PrivateKey = $client_private
Address = 10.88.0.2/32
DNS = 1.1.1.1, 9.9.9.9
Jc = 5
Jmin = 40
Jmax = 70
S1 = 20
S2 = 40
H1 = $h1
H2 = $h2
H3 = $h3
H4 = $h4

[Peer]
PublicKey = $server_public
Endpoint = $HOST:443
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CONF
  chmod 600 /etc/amnezia/amneziawg/hatevpn.conf /etc/hatevpn-amneziawg/client.conf
fi

printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/90-hatevpn-amneziawg.conf
sysctl -q -p /etc/sysctl.d/90-hatevpn-amneziawg.conf
awg-quick strip hatevpn >/dev/null
systemctl enable --now awg-quick@hatevpn >/dev/null
systemctl is-active --quiet awg-quick@hatevpn ||
  { journalctl -u awg-quick@hatevpn -n 20 --no-pager >&2; exit 4; }
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then ufw allow 443/udp >/dev/null; fi
printf 'HATEVPN_AWG_CONFIG_BASE64=%s\n' "$(base64 -w0 /etc/hatevpn-amneziawg/client.conf)"
