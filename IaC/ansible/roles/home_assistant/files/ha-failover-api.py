#!/usr/bin/python3
"""ha-failover-api — local HTTP trigger for /usr/local/sbin/ha-failover.sh (HD-17).

Runs on oldsrv; Homepage cards (homepage_services.yaml.j2) trigger it.

  GET/POST /failover  -> ha-failover.sh forward   (Pi -> oldsrv takeover)
  GET/POST /failback  -> ha-failover.sh reverse   (oldsrv -> Pi failback)
  GET       /health   -> {"ok": true}

Auth: token from HA_FAILOVER_TOKEN (file /etc/ha-failover/api.env). Accepted as
the X-Failover-Token header (POST) or ?token= query (GET, for clickable Homepage
href cards). If the token is empty the endpoint refuses to run (see __main__).

Runs as root via systemd so ha-failover.sh's root check passes, and binds
0.0.0.0:8266 on the Home VLAN — acceptable behind the token; the handler only
ever runs the two fixed commands (no shell interpolation). A failover waits on
the CCU (up to ~2 min) so the request blocks until it finishes, then returns
the exit code + tail of the script log.
"""
import http.server
import json
import logging
import os
import subprocess
import sys

PORT = int(os.environ.get('HA_FAILOVER_PORT', '8266'))
TOKEN = os.environ.get('HA_FAILOVER_TOKEN', '')
SCRIPT = '/usr/local/sbin/ha-failover.sh'
COMMANDS = {'/failover': 'forward', '/failback': 'reverse'}

logging.basicConfig(stream=sys.stdout, level=logging.INFO,
                    format='%(asctime)s ha-failover-api %(message)s')


def run_failover(mode):
    try:
        p = subprocess.run([SCRIPT, mode], capture_output=True, text=True,
                           timeout=900)
        tail = (p.stdout + p.stderr).strip().splitlines()[-20:]
        return p.returncode, tail
    except subprocess.TimeoutExpired:
        return 1, ['timeout: ha-failover.sh exceeded 900s']


class Handler(http.server.BaseHTTPRequestHandler):
    def _path(self):
        return self.path.split('?', 1)[0]

    def _query_token(self):
        if '?' not in self.path:
            return ''
        for part in self.path.split('?', 1)[1].split('&'):
            if part.startswith('token='):
                return part[6:]
        return ''

    def _authorized(self):
        if not TOKEN:
            return False  # fail closed — no token configured, never auto-auth
        return (self.headers.get('X-Failover-Token', '') == TOKEN
                or self._query_token() == TOKEN)

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        path = self._path()
        if path == '/health':
            self._send(200, {'ok': True})
            return
        if not self._authorized():
            self._send(403, {'error': 'forbidden'})
            return
        mode = COMMANDS.get(path)
        if mode is None:
            self._send(404, {'error': 'not found'})
            return
        logging.info('trigger %s from %s', mode, self.client_address[0])
        rc, tail = run_failover(mode)
        self._send(200 if rc == 0 else 500,
                   {'event': mode, 'exit': rc, 'log': tail})

    do_GET = _handle
    do_POST = _handle

    def log_message(self, fmt, *args):  # quiet the default access log
        logging.info('%s %s', self.client_address[0], fmt % args)


if __name__ == '__main__':
    if not TOKEN:
        print('FAIL: HA_FAILOVER_TOKEN is not set — refusing to start', file=sys.stderr)
        sys.exit(1)
    logging.info('listening on 0.0.0.0:%d', PORT)
    http.server.ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()