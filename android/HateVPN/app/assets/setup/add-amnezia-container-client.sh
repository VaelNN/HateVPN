#!/usr/bin/env bash
set -euo pipefail
umask 077

HOST="${1:?Server address required}"
PORT="${2:-}"
DEVICE="${3:?Device id required}"
INVITE_LABEL="${4:-}"
[[ "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]] || { echo 'Invalid server address.' >&2; exit 2; }
[[ "$DEVICE" =~ ^hv-[0-9a-f]{32}$ ]] || { echo 'Invalid device id.' >&2; exit 2; }
[[ -z "$INVITE_LABEL" || "$INVITE_LABEL" =~ ^[A-Za-z0-9+/]{1,128}={0,2}$ ]] || { echo 'Invalid invite label.' >&2; exit 2; }

if [[ "${HATEVPN_IN_CONTAINER:-0}" != 1 ]]; then
  [[ "$(id -u)" -eq 0 ]] || { echo 'Root SSH access is required.' >&2; exit 2; }
  command -v docker >/dev/null || { echo 'Docker is unavailable on this VPS.' >&2; exit 2; }
  [[ "$(docker inspect -f '{{.State.Running}}' amnezia-awg2 2>/dev/null || true)" == true ]] ||
    { echo 'The AmneziaWG container is not running.' >&2; exit 2; }
  server_port="$(docker exec amnezia-awg2 awk -F= '/^[[:space:]]*ListenPort[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' /opt/amnezia/awg/awg0.conf)"
  [[ "$server_port" =~ ^[0-9]+$ ]] || { echo 'The AmneziaWG server port was not found.' >&2; exit 2; }
  PORT="$(docker port amnezia-awg2 "${server_port}/udp" | sed -n '1p' | awk -F: '{print $NF}')"
  [[ "$PORT" =~ ^[0-9]+$ ]] && ((PORT >= 1 && PORT <= 65535)) ||
    { echo 'The AmneziaWG UDP port is not published.' >&2; exit 2; }
  docker exec -i -e HATEVPN_IN_CONTAINER=1 amnezia-awg2 bash -s -- "$HOST" "$PORT" "$DEVICE" "$INVITE_LABEL" < "$0"
  exit
fi

[[ "$PORT" =~ ^[0-9]+$ ]] && ((PORT >= 1 && PORT <= 65535)) || exit 2
server_conf=/opt/amnezia/awg/awg0.conf
client_dir=/opt/amnezia/awg/hatevpn-clients
client_conf="$client_dir/$DEVICE.conf"
invite_marker="$client_dir/$DEVICE.invite"
[[ -f "$server_conf" ]] || { echo 'The AmneziaWG server configuration is missing.' >&2; exit 2; }
command -v awg >/dev/null || { echo 'AmneziaWG tools are unavailable.' >&2; exit 2; }
server_public="$(awg show awg0 public-key)"
[[ "$server_public" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo 'The AmneziaWG interface is not ready.' >&2; exit 2; }
mkdir -p -m 700 "$client_dir"
chmod 700 "$client_dir"

if [[ -f "$client_conf" ]]; then
  if [[ -n "$INVITE_LABEL" && ! -f "$invite_marker" ]]; then echo 'Client id already belongs to a different connection.' >&2; exit 3; fi
  client_private="$(awk '/^[[:space:]]*PrivateKey[[:space:]]*=/ {sub(/^[^=]*=/, ""); gsub(/[[:space:]]/, ""); print; exit}' "$client_conf")"
  client_public="$(printf '%s\n' "$client_private" | awg pubkey)"
  awg show awg0 peers | grep -Fxq "$client_public" ||
    { echo 'The saved HateVPN client is no longer registered on the server.' >&2; exit 3; }
  printf 'HATEVPN_AWG_CONFIG_BASE64=%s\n' "$(base64 -w0 "$client_conf")"
  exit
fi

server_address="$(awk -F= '/^\[Interface\]/{in_interface=1; next} /^\[/{in_interface=0} in_interface && /^[[:space:]]*Address[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); split($2, parts, ","); print parts[1]; exit}' "$server_conf")"
[[ "$server_address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/24$ ]] ||
  { echo 'Automatic client creation requires an AmneziaWG IPv4 /24 subnet.' >&2; exit 2; }
server_ip="${server_address%/*}"
network="${server_ip%.*}"
used="$(awk -F= '/^[[:space:]]*AllowedIPs[[:space:]]*=/ {print $2}' "$server_conf")"
live_used="$(awg show awg0 allowed-ips)"
client_ip=''
for ((number = 2; number <= 254; number++)); do
  candidate="$network.$number"
  [[ "$candidate" == "$server_ip" ]] && continue
  if ! printf '%s\n%s\n' "$used" "$live_used" | grep -Fq "$candidate/32"; then
    client_ip="$candidate"
    break
  fi
done
[[ -n "$client_ip" ]] || { echo 'No free AmneziaWG client address remains.' >&2; exit 3; }

server_parameters="$(awk '
  /^\[Interface\]/{in_interface=1; next}
  /^\[/{in_interface=0}
  in_interface && /^[[:space:]]*[A-Za-z][A-Za-z0-9]*[[:space:]]*=/ {
    key=$1
    if (key ~ /^(Jc|Jmin|Jmax|S[1-4]|H[1-4]|I[1-5]|J[1-3]|ITime|HeaderProtectionKey|ContentPaddingAddition|RekeyAfterTime|RekeyTimeout|RejectAfterTime|KeepaliveTimeout|MaxHandshakeAttempts|RandomTrailers|DisableCookies)$/) print
  }
' "$server_conf")"
[[ "$server_parameters" == *'H1'* && "$server_parameters" == *'H4'* ]] ||
  { echo 'The AmneziaWG obfuscation settings are incomplete.' >&2; exit 3; }

client_private="$(awg genkey)"
client_public="$(printf '%s\n' "$client_private" | awg pubkey)"
preshared="$(awg genpsk)"
psk_file="$(mktemp /tmp/hatevpn-psk.XXXXXX)"
backup="$(mktemp /opt/amnezia/awg/.hatevpn-server.XXXXXX)"
new_server="$(mktemp /opt/amnezia/awg/.hatevpn-next.XXXXXX)"
new_client="$(mktemp "$client_dir/.hatevpn-client.XXXXXX")"
new_invite=''
if [[ -n "$INVITE_LABEL" ]]; then
  new_invite="$(mktemp "$client_dir/.hatevpn-invite.XXXXXX")"
  printf '%s\n' "$INVITE_LABEL" > "$new_invite"
fi
applied=0
committed=0
cleanup() {
  if ((committed == 0)); then
    if ((applied == 1)); then awg set awg0 peer "$client_public" remove >/dev/null 2>&1 || true; fi
    if [[ -s "$backup" ]]; then cp -p "$backup" "$server_conf" || true; fi
    rm -f "$client_conf"
    rm -f "$invite_marker"
  fi
  rm -f "$psk_file" "$backup" "$new_server" "$new_client"
  if [[ -n "$new_invite" ]]; then rm -f "$new_invite"; fi
}
trap cleanup EXIT
cp -p "$server_conf" "$backup"
cp -p "$server_conf" "$new_server"
printf '%s\n' "$preshared" > "$psk_file"
cat >> "$new_server" <<EOF

# HateVPN $DEVICE
[Peer]
PublicKey = $client_public
PresharedKey = $preshared
AllowedIPs = $client_ip/32
EOF
cat > "$new_client" <<EOF
[Interface]
Address = $client_ip/32
DNS = 1.1.1.1, 1.0.0.1
PrivateKey = $client_private
$server_parameters

[Peer]
PublicKey = $server_public
PresharedKey = $preshared
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $HOST:$PORT
PersistentKeepalive = 25
EOF
awg set awg0 peer "$client_public" preshared-key "$psk_file" allowed-ips "$client_ip/32"
applied=1
awg show awg0 peers | grep -Fxq "$client_public" || { echo 'Could not activate the new client.' >&2; exit 3; }
mv -f "$new_server" "$server_conf"
mv -f "$new_client" "$client_conf"
if [[ -n "$new_invite" ]]; then mv -f "$new_invite" "$invite_marker"; chmod 600 "$invite_marker"; fi
chmod 600 "$server_conf" "$client_conf"
committed=1
printf 'HATEVPN_AWG_CONFIG_BASE64=%s\n' "$(base64 -w0 "$client_conf")"
