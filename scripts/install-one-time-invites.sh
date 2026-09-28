#!/usr/bin/env bash
set -euo pipefail
umask 077

HOST="${1:?Server address required}"
INVITE_ID="${2:?Invitation id required}"
TOKEN="${3:?Claim token required}"
[[ "$(id -u)" -eq 0 ]] || { echo 'Root SSH access is required.' >&2; exit 2; }
[[ "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]] || exit 2
[[ "$INVITE_ID" =~ ^hv-[0-9a-f]{32}$ && "$TOKEN" =~ ^[0-9a-f]{64}$ ]] || exit 2
command -v python3 >/dev/null || { echo 'Python 3 is required for one-time invitations.' >&2; exit 2; }
command -v openssl >/dev/null || { echo 'OpenSSL is required for one-time invitations.' >&2; exit 2; }
command -v systemctl >/dev/null || { echo 'systemd is required for one-time invitations.' >&2; exit 2; }
[[ "$(docker inspect -f '{{.State.Running}}' amnezia-awg2 2>/dev/null || true)" == true ]] ||
  { echo 'The AmneziaWG container is not running.' >&2; exit 2; }
docker exec amnezia-awg2 test -f "/opt/amnezia/awg/hatevpn-clients/$INVITE_ID.invite"
docker exec amnezia-awg2 test -f "/opt/amnezia/awg/hatevpn-clients/$INVITE_ID.conf"

install -d -m 700 /var/lib/hatevpn-invites
install -d -m 700 /etc/hatevpn
if [[ ! -f /etc/hatevpn/claim.crt || ! -f /etc/hatevpn/claim.key ]]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -sha256 -days 3650 \
    -subj '/CN=HateVPN invitations' -keyout /etc/hatevpn/claim.key -out /etc/hatevpn/claim.crt >/dev/null 2>&1
  chmod 600 /etc/hatevpn/claim.key
fi

cat > /usr/local/lib/hatevpn-invite-claim.py <<'PY'
import fcntl
import hashlib
import http.server
import json
import os
import re
import ssl
import subprocess

ROOT = '/var/lib/hatevpn-invites'

class Handler(http.server.BaseHTTPRequestHandler):
    def setup(self):
        self.request.settimeout(5)
        super().setup()

    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        body = json.dumps(payload, separators=(',', ':')).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != '/claim':
            self.reply(404, {'error': 'not_found'})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size < 1 or size > 512:
                self.reply(400, {'error': 'invalid_request'})
                return
            token = json.loads(self.rfile.read(size)).get('token', '')
            if not isinstance(token, str) or re.fullmatch('[0-9a-f]{64}', token) is None:
                self.reply(400, {'error': 'invalid_request'})
                return
            path = os.path.join(ROOT, hashlib.sha256(token.encode()).hexdigest())
            with open(os.path.join(ROOT, '.lock'), 'a+b') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                try:
                    with open(path, encoding='ascii') as item:
                        invite_id = item.readline().strip()
                        config = item.readline().strip()
                except FileNotFoundError:
                    self.reply(410, {'error': 'used_or_revoked'})
                    return
                if re.fullmatch('hv-[0-9a-f]{32}', invite_id) is None:
                    self.reply(500, {'error': 'server_error'})
                    return
                active = subprocess.run(['docker', 'exec', 'amnezia-awg2', 'test', '-f',
                    '/opt/amnezia/awg/hatevpn-clients/' + invite_id + '.conf'],
                    capture_output=True, timeout=5).returncode == 0
                if not active:
                    os.unlink(path)
                    self.reply(410, {'error': 'used_or_revoked'})
                    return
                os.unlink(path)
                self.reply(200, {'id': invite_id, 'config': config})
        except (ValueError, TypeError, json.JSONDecodeError):
            self.reply(400, {'error': 'invalid_request'})
        except Exception:
            self.reply(503, {'error': 'server_error'})

server = http.server.ThreadingHTTPServer(('0.0.0.0', 8443), Handler)
server.daemon_threads = True
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain('/etc/hatevpn/claim.crt', '/etc/hatevpn/claim.key')
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
chmod 700 /usr/local/lib/hatevpn-invite-claim.py
cat > /etc/systemd/system/hatevpn-invite-claim.service <<'UNIT'
[Unit]
Description=HateVPN one-time invitation claims
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/lib/hatevpn-invite-claim.py
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now hatevpn-invite-claim.service >/dev/null
systemctl restart hatevpn-invite-claim.service
sleep 0.3
systemctl is-active --quiet hatevpn-invite-claim.service ||
  { echo 'The invitation service could not start. Check TCP port 8443.' >&2; exit 3; }
if command -v ufw >/dev/null; then ufw allow 8443/tcp >/dev/null; fi

config="$(docker exec amnezia-awg2 base64 -w0 "/opt/amnezia/awg/hatevpn-clients/$INVITE_ID.conf")"
[[ "$config" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || { echo 'The invite config is invalid.' >&2; exit 3; }
digest="$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')"
pending="$(mktemp /var/lib/hatevpn-invites/.pending.XXXXXX)"
printf '%s\n%s\n' "$INVITE_ID" "$config" > "$pending"
chmod 600 "$pending"
mv -T "$pending" "/var/lib/hatevpn-invites/$digest"
fingerprint="$(openssl x509 -in /etc/hatevpn/claim.crt -outform DER | sha256sum | awk '{print $1}')"
printf 'HATEVPN_CLAIM_CERT_SHA256=%s\n' "$fingerprint"
