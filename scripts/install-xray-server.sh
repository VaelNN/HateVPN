#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

HOST="${1:?Server address required}"
temp_dir=''
probe_dir=''
probe_pid=''
cleanup() {
  if [[ -n "$probe_pid" ]]; then kill "$probe_pid" 2>/dev/null || true; wait "$probe_pid" 2>/dev/null || true; fi
  if [[ "$probe_dir" == /tmp/hatevpn-xray-probe.* ]]; then rm -rf -- "$probe_dir"; fi
  if [[ "$temp_dir" == /tmp/hatevpn-xray-download.* ]]; then rm -rf -- "$temp_dir"; fi
}
trap cleanup EXIT
if [[ ! "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.:-]{0,252}$ ]]; then echo 'Invalid server address' >&2; exit 2; fi
if [[ "$(id -u)" -ne 0 ]]; then echo 'Root SSH access is required' >&2; exit 2; fi
if [[ ! -f /etc/os-release ]] || ! grep -Eq '^ID=(ubuntu|debian)$' /etc/os-release; then
  echo 'Ubuntu or Debian is required' >&2; exit 2
fi
if [[ -n "$(ss -ltnH '( sport = :443 )')" && ! -f /etc/hatevpn-xray/config.json ]]; then
  echo 'TCP port 443 is already in use. Free it before setup.' >&2; exit 2
fi

apt-get update -qq
apt-get install -y -qq ca-certificates curl unzip openssl >/dev/null
mkdir -p /opt/hatevpn-xray /etc/hatevpn-xray
chmod 700 /etc/hatevpn-xray

current_version=''
if [[ -x /opt/hatevpn-xray/xray ]]; then
  current_version="$(/opt/hatevpn-xray/xray version | awk 'NR == 1 {print $2}')"
fi
updated_binary=0
had_binary=0
if [[ "$current_version" != '26.9.9' ]]; then
  temp_dir="$(mktemp -d /tmp/hatevpn-xray-download.XXXXXX)"
  curl -fLsS --retry 3 --connect-timeout 10 -o "$temp_dir/xray.zip" \
    'https://github.com/XTLS/Xray-core/releases/download/v26.9.9/Xray-linux-64.zip'
  printf '%s  %s\n' '1eb9175d0f0a8f8149c9230a7fc5ae66ce332ed20a53155ce61fe62e3f58b7df' "$temp_dir/xray.zip" | sha256sum -c - >/dev/null
  unzip -p "$temp_dir/xray.zip" xray > "$temp_dir/xray"
  chmod 755 "$temp_dir/xray"
  if [[ -f /etc/hatevpn-xray/config.json ]]; then
    "$temp_dir/xray" run -test -config /etc/hatevpn-xray/config.json >/dev/null
  fi
  if [[ -x /opt/hatevpn-xray/xray ]]; then
    cp -p /opt/hatevpn-xray/xray /opt/hatevpn-xray/xray.previous
    had_binary=1
  fi
  install -m 755 "$temp_dir/xray" /opt/hatevpn-xray/xray.new
  mv -f /opt/hatevpn-xray/xray.new /opt/hatevpn-xray/xray
  updated_binary=1
fi

created_config=0
if [[ ! -f /etc/hatevpn-xray/config.json ]]; then
  uuid="$(/opt/hatevpn-xray/xray uuid)"
  key_pair="$(/opt/hatevpn-xray/xray x25519)"
  private_key="$(printf '%s\n' "$key_pair" | sed -n 's/^PrivateKey: //p')"
  public_key="$(printf '%s\n' "$key_pair" | sed -n 's/^Password (PublicKey): //p')"
  short_id="$(openssl rand -hex 8)"
  sni='www.microsoft.com'
  if [[ -z "$uuid" || -z "$private_key" || -z "$public_key" ]]; then echo 'Could not generate Xray keys' >&2; exit 3; fi
  cat > /etc/hatevpn-xray/config.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0", "port": 443, "protocol": "vless",
    "settings": { "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }], "decryption": "none" },
    "streamSettings": { "network": "raw", "security": "reality", "realitySettings": {
      "show": false, "target": "$sni:443", "xver": 0,
      "serverNames": ["$sni"], "privateKey": "$private_key", "shortIds": ["$short_id"]
    }}
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
  chmod 600 /etc/hatevpn-xray/config.json
  printf '%s\n%s\n%s\n%s\n' "$uuid" "$public_key" "$short_id" "$sni" > /etc/hatevpn-xray/client.txt
  chmod 600 /etc/hatevpn-xray/client.txt
  created_config=1
fi

/opt/hatevpn-xray/xray run -test -config /etc/hatevpn-xray/config.json >/dev/null
cat > /etc/systemd/system/hatevpn-xray.service <<'UNIT'
[Unit]
Description=HateVPN Xray server
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=/opt/hatevpn-xray/xray run -config /etc/hatevpn-xray/config.json
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now hatevpn-xray >/dev/null
if [[ "$updated_binary" -eq 1 || "$created_config" -eq 1 ]]; then systemctl restart hatevpn-xray; fi
if ! systemctl is-active --quiet hatevpn-xray; then
  if [[ "$updated_binary" -eq 1 && "$had_binary" -eq 1 ]]; then
    cp -p /opt/hatevpn-xray/xray.previous /opt/hatevpn-xray/xray
    systemctl restart hatevpn-xray || true
  fi
  journalctl -u hatevpn-xray -n 15 --no-pager >&2
  exit 4
fi
listener=''
for attempt in {1..20}; do
  listener="$(ss -ltnpH '( sport = :443 )')"
  if [[ "$listener" == *'"xray"'* ]]; then break; fi
  sleep 0.5
done
if [[ "$listener" != *'"xray"'* ]]; then
  echo 'Xray is active but is not listening on TCP port 443.' >&2
  exit 4
fi
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then ufw allow 443/tcp >/dev/null; fi
read -r uuid < /etc/hatevpn-xray/client.txt
public_key="$(sed -n '2p' /etc/hatevpn-xray/client.txt)"
short_id="$(sed -n '3p' /etc/hatevpn-xray/client.txt)"
sni="$(sed -n '4p' /etc/hatevpn-xray/client.txt)"
probe_dir="$(mktemp -d /tmp/hatevpn-xray-probe.XXXXXX)"
probe_port="$(shuf -i 30000-50000 -n 1)"
cat > "$probe_dir/client.json" <<JSON
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":$probe_port,"protocol":"http"}],"outbounds":[{"tag":"proxy","protocol":"vless","settings":{"address":"127.0.0.1","port":443,"id":"$uuid","encryption":"none","flow":"xtls-rprx-vision"},"streamSettings":{"network":"raw","security":"reality","realitySettings":{"serverName":"$sni","fingerprint":"chrome","password":"$public_key","shortId":"$short_id"}}}]}
JSON
chmod 600 "$probe_dir/client.json"
/opt/hatevpn-xray/xray run -config "$probe_dir/client.json" >"$probe_dir/client.log" 2>&1 &
probe_pid=$!
sleep 1
if ! kill -0 "$probe_pid" 2>/dev/null; then
  echo 'Xray client self-test could not start.' >&2
  exit 5
fi
probe_status="$(curl --proxy "http://127.0.0.1:$probe_port" --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 18 https://www.example.com/ 2>/dev/null || true)"
if [[ ! "$probe_status" =~ ^[23][0-9][0-9]$ ]]; then
  echo 'Xray REALITY self-test failed. The profile was not returned.' >&2
  exit 5
fi
printf 'HATEVPN_LINK=vless://%s@%s:443?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s#My-VPS\n' \
  "$uuid" "$HOST" "$sni" "$public_key" "$short_id"
