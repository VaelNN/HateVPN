#!/usr/bin/env bash
# Read-only check for the HateVPN Xray service. It does not change the VPN or firewall.
set -u

xray=/opt/hatevpn-xray/xray
config=/etc/hatevpn-xray/config.json
client=/etc/hatevpn-xray/client.txt

printf 'XRAY_BINARY=%s\n' "$(test -x "$xray" && echo present || echo missing)"
if test -x "$xray" && test -f "$config" && "$xray" run -test -config "$config" >/dev/null 2>&1; then
  echo XRAY_CONFIG=valid
else
  echo XRAY_CONFIG=missing_or_invalid
fi
if command -v systemctl >/dev/null && systemctl is-active --quiet hatevpn-xray; then
  echo XRAY_SERVICE=active
else
  echo XRAY_SERVICE=inactive
fi

if command -v ss >/dev/null; then
  listener="$(ss -ltnpH '( sport = :443 )' 2>/dev/null || true)"
  if [[ "$listener" == *xray* ]]; then echo TCP_443_OWNER=xray
  elif [[ -n "$listener" ]]; then echo TCP_443_OWNER=another_process
  else echo TCP_443_OWNER=none
  fi
else
  echo TCP_443_OWNER=unknown
fi

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
  if ufw status 2>/dev/null | grep -Eq '^443/tcp[[:space:]]+ALLOW'; then
    echo UFW_443=allowed
  else
    echo UFW_443=no_allow_rule
  fi
else
  echo UFW_443=inactive_or_unavailable
fi

if command -v curl >/dev/null && curl --silent --show-error --head --max-time 8 https://www.microsoft.com/ >/dev/null 2>&1; then
  echo REALITY_TARGET=reachable
else
  echo REALITY_TARGET=unreachable
fi

if ! test -x "$xray" || ! test -f "$config" || ! test -f "$client" || ! command -v curl >/dev/null; then
  echo REALITY_LOOPBACK=not_run
  exit 0
fi
if ! systemctl is-active --quiet hatevpn-xray; then
  echo REALITY_LOOPBACK=service_inactive
  exit 0
fi

temp="$(mktemp -d /tmp/hatevpn-xray-check.XXXXXX)" || exit 1
pid=''
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  if [[ "$temp" == /tmp/hatevpn-xray-check.* ]]; then
    rm -f -- "$temp/client.json" "$temp/client.log" "$temp/curl.err"
    rmdir -- "$temp" 2>/dev/null || true
  fi
}
trap cleanup EXIT

uuid="$(sed -n '1p' "$client")"
public_key="$(sed -n '2p' "$client")"
short_id="$(sed -n '3p' "$client")"
sni="$(sed -n '4p' "$client")"
if [[ -z "$uuid" || -z "$public_key" || -z "$short_id" || -z "$sni" ]]; then
  echo REALITY_LOOPBACK=client_profile_invalid
  exit 0
fi

proxy_port="$(shuf -i 30000-50000 -n 1)"
cat > "$temp/client.json" <<JSON
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":$proxy_port,"protocol":"http"}],"outbounds":[{"tag":"proxy","protocol":"vless","settings":{"address":"127.0.0.1","port":443,"id":"$uuid","encryption":"none","flow":"xtls-rprx-vision"},"streamSettings":{"network":"raw","security":"reality","realitySettings":{"serverName":"$sni","fingerprint":"chrome","password":"$public_key","shortId":"$short_id"}}}]}
JSON
chmod 600 "$temp/client.json"
"$xray" run -config "$temp/client.json" >"$temp/client.log" 2>&1 &
pid=$!
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
  echo REALITY_LOOPBACK=client_failed_to_start
  exit 0
fi
status="$(curl --proxy "http://127.0.0.1:$proxy_port" --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 18 https://www.example.com/ 2>"$temp/curl.err")"
curl_exit=$?
if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
  echo REALITY_LOOPBACK=ok
else
  echo REALITY_LOOPBACK=failed
  echo "REALITY_CURL_EXIT=$curl_exit"
  echo "REALITY_HTTP_STATUS=$status"
  sed -E 's/[A-Za-z0-9+\/_=-]{40,}/[redacted]/g' "$temp/curl.err" | tail -n 3
  grep -Ei 'failed|rejected|error|eof|timeout|invalid' "$temp/client.log" | tail -n 4 | sed -E 's/[A-Za-z0-9+\/_=-]{40,}/[redacted]/g' || true
fi
