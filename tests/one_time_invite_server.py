"""Run with Python 3 to check first-use and replay behavior of the embedded VPS endpoint."""
import base64
import hashlib
import io
import pathlib
import sys
import tempfile
import types

if sys.platform == 'win32':
    sys.modules['fcntl'] = types.SimpleNamespace(LOCK_EX=1, flock=lambda *_: None)

script = (pathlib.Path(__file__).parent.parent / 'scripts' / 'install-one-time-invites.sh').read_text()
start = "cat > /usr/local/lib/hatevpn-invite-claim.py <<'PY'\n"
code = script.split(start, 1)[1].split('\nPY\n', 1)[0].split('\nserver = ', 1)[0]
namespace = {}
exec(compile(code, '<invite-claim-server>', 'exec'), namespace)
namespace['subprocess'].run = lambda *_, **__: types.SimpleNamespace(returncode=0)

def claim(token):
    request = ('{"token":"' + token + '"}').encode()
    handler = namespace['Handler'].__new__(namespace['Handler'])
    handler.path = '/claim'
    handler.headers = {'Content-Length': str(len(request))}
    handler.rfile = io.BytesIO(request)
    handler.wfile = io.BytesIO()
    handler.send_response = lambda status: setattr(handler, 'status', status)
    handler.send_header = lambda *_: None
    handler.end_headers = lambda: None
    handler.do_POST()
    return handler.status, handler.wfile.getvalue()

with tempfile.TemporaryDirectory() as root:
    namespace['ROOT'] = root
    token = 'a' * 64
    invite_id = 'hv-' + 'b' * 32
    config = base64.b64encode(b'example configuration').decode()
    path = pathlib.Path(root) / hashlib.sha256(token.encode()).hexdigest()
    path.write_text(invite_id + '\n' + config + '\n')
    first = claim(token)
    second = claim(token)
    assert first[0] == 200 and config.encode() in first[1]
    assert second[0] == 410 and not path.exists()
print('One-time invitation: first claim succeeds, replay is rejected.')
