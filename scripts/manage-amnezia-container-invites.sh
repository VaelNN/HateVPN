#!/usr/bin/env bash
set -euo pipefail
umask 077

ACTION="${1:?Action required}"
DEVICE="${2:-}"
[[ "$ACTION" == list || "$ACTION" == revoke ]] || { echo 'Invalid action.' >&2; exit 2; }
if [[ "$ACTION" == revoke ]]; then
  [[ "$DEVICE" =~ ^hv-[0-9a-f]{32}$ ]] || { echo 'Invalid invite id.' >&2; exit 2; }
fi

if [[ "${HATEVPN_IN_CONTAINER:-0}" != 1 ]]; then
  [[ "$(id -u)" -eq 0 ]] || { echo 'Root SSH access is required.' >&2; exit 2; }
  [[ "$(docker inspect -f '{{.State.Running}}' amnezia-awg2 2>/dev/null || true)" == true ]] ||
    { echo 'The AmneziaWG container is not running.' >&2; exit 2; }
  docker exec -i -e HATEVPN_IN_CONTAINER=1 amnezia-awg2 bash -s -- "$ACTION" "$DEVICE" < "$0"
  if [[ "$ACTION" == revoke && -d /var/lib/hatevpn-invites ]]; then
    exec 9> /var/lib/hatevpn-invites/.lock
    flock -x 9
    shopt -s nullglob
    for pending in /var/lib/hatevpn-invites/[0-9a-f]*; do
      [[ -f "$pending" ]] || continue
      read -r pending_id < "$pending" || true
      if [[ "$pending_id" == "$DEVICE" ]]; then rm -f -- "$pending"; fi
    done
  fi
  exit
fi

client_dir=/opt/amnezia/awg/hatevpn-clients
server_conf=/opt/amnezia/awg/awg0.conf
[[ -d "$client_dir" && -f "$server_conf" ]] || { echo 'Invite storage is unavailable.' >&2; exit 2; }

if [[ "$ACTION" == list ]]; then
  shopt -s nullglob
  for marker in "$client_dir"/hv-*.invite; do
    id="${marker##*/}"
    id="${id%.invite}"
    [[ "$id" =~ ^hv-[0-9a-f]{32}$ ]] || continue
    [[ -f "$client_dir/$id.conf" ]] || continue
    label="$(tr -d '\r\n' < "$marker")"
    [[ "$label" =~ ^[A-Za-z0-9+/]{1,128}={0,2}$ ]] || continue
    printf 'HATEVPN_INVITE=%s:%s\n' "$id" "$label"
  done
  exit
fi

marker="$client_dir/$DEVICE.invite"
client_conf="$client_dir/$DEVICE.conf"
[[ -f "$marker" && -f "$client_conf" ]] || { echo 'Invitation is already revoked or does not exist.' >&2; exit 3; }
client_private="$(awk '/^[[:space:]]*PrivateKey[[:space:]]*=/ {sub(/^[^=]*=/, ""); gsub(/[[:space:]]/, ""); print; exit}' "$client_conf")"
[[ "$client_private" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo 'Invalid client private key.' >&2; exit 3; }
client_public="$(printf '%s\n' "$client_private" | awg pubkey)"
[[ "$client_public" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo 'Invalid client key.' >&2; exit 3; }
allowed_ip="$(awk -F= '/^[[:space:]]*Address[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$client_conf")"
[[ "$allowed_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/32$ ]] || { echo 'Invalid client address.' >&2; exit 3; }

next_conf="$(mktemp /opt/amnezia/awg/.hatevpn-revoke.XXXXXX)"
backup="$(mktemp /opt/amnezia/awg/.hatevpn-backup.XXXXXX)"
committed=0
cleanup() {
  if ((committed == 0)) && [[ -s "$backup" ]]; then cp -p "$backup" "$server_conf" || true; fi
  rm -f "$next_conf" "$backup"
}
trap cleanup EXIT
cp -p "$server_conf" "$backup"
awk -v id="$DEVICE" -v pub="$client_public" -v ip="$allowed_ip" '
  $0 == "# HateVPN " id {
    found++
    if (getline <= 0 || $0 != "[Peer]") exit 3
    if (getline <= 0 || $0 != "PublicKey = " pub) exit 3
    if (getline <= 0 || $0 !~ /^PresharedKey = /) exit 3
    if (getline <= 0 || $0 != "AllowedIPs = " ip) exit 3
    next
  }
  { print }
  END { if (found != 1) exit 3 }
' "$server_conf" > "$next_conf" || { echo 'Server peer block did not match this invitation.' >&2; exit 3; }
chmod 600 "$next_conf"
mv -f "$next_conf" "$server_conf"
if ! awg set awg0 peer "$client_public" remove; then
  echo 'Could not revoke the live VPN peer.' >&2
  exit 3
fi
live_peers="$(awg show awg0 peers)" || { echo 'Could not verify the live VPN peer list.' >&2; exit 3; }
if grep -Fxq -- "$client_public" <<< "$live_peers"; then
  echo 'The revoked VPN peer is still active.' >&2
  exit 3
fi
committed=1
rm -f "$client_conf" "$marker"
printf 'HATEVPN_REVOKED=%s\n' "$DEVICE"
