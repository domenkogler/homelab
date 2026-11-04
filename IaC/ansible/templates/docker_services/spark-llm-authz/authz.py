#!/usr/bin/env python3
"""authz.py — spark's inference-edge forwardAuth verifier.

WHAT IT DECIDES, in one line: the bearer a client presented to Traefik is compared against a
rendered set of CLIENT tokens, and on a match the RESPONSE carries
`Authorization: Bearer <internal engine key>` — the header Traefik's `authResponseHeaders` copies
onto the forwarded request, so the engine authenticates its one internal key and never a client's.
That swap is the service: rotating a client credential becomes a config render instead of an engine
restart, because client credentials are no longer in the engine's argv.

THE CONTRACT other files depend on:
  * Any method on any path except `/healthz` IS the auth endpoint. Which path Traefik dials is the
    route table's decision and not this program's, so no path is hardcoded here; answering every
    method is required because the pin sends the subrequest with the ORIGINAL method unless
    `forwardAuth.authMethod` says otherwise. `/healthz` answers unauthenticated for the compose
    healthcheck.
  * 200 = allow, and an allow is the only answer that carries the Authorization response header.
    Every other answer (401) denies at the edge: unknown token, absent header, malformed header, or
    config this program cannot read. FAIL CLOSED is the rule — a config problem is a denial, never
    an allow — and "verifier down means inference dark" is the accepted cost of that rule, not an
    accident of this implementation.
  * Comparison is constant-time against EVERY entry, so neither a miss nor which entry hit leaks
    through timing.
  * The config is re-read on every request: a rendered rotation reaches the next request without a
    restart, and a config that vanishes or stops parsing fails closed immediately instead of
    surviving in a cached copy. `/healthz` reads it too and prints only the verdict word, which is
    what makes "this verifier is dark because its config is broken" visible before any router
    points at it.
  * DISCLOSURE BUDGET (CONVENTIONS §6): a log line carries the verdict, the forwarded path, method
    and host, and at most `sha256[:12]` of the PRESENTED token. Never a token, a length, a prefix
    or the Authorization header — and never a digest of the engine key either, since a hash of a
    secret is a disclosure too. BaseHTTPRequestHandler's own request-line logging is silenced on
    purpose: a credential carried in a query string would otherwise reach the log through the
    standard library's courtesy.

RUN:
  python3 authz.py                   serve; env AUTHZ_CONFIG, AUTHZ_BIND, AUTHZ_PORT
  python3 authz.py --healthcheck     exit 0 iff this host's own /healthz answers 200
  python3 authz.py --self-test       fixture arms over loopback, ZERO vault and ZERO egress; it can fail

CONFIG FILE (rendered from the vault by Ansible, 0600 root:root, bind-mounted read-only):
  {"engine_token": "<internal engine key>", "client_tokens": ["<client bearer>", ...]}
A missing or empty `client_tokens` admits nobody. That is a refusal, not an open door.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import shutil
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import StringIO
from pathlib import Path

CONFIG_ENV = "AUTHZ_CONFIG"
CONFIG_DEFAULT = "/config/authz-config.json"
BIND_ENV = "AUTHZ_BIND"
# Loopback by default so a run outside the compose cannot open a socket on a LAN address; the
# compose renders the same value explicitly. The host-facing boundary is the same story: this
# service runs on the host network and publishes NOTHING, so 127.0.0.1 is the only address it has.
BIND_DEFAULT = "127.0.0.1"
PORT_ENV = "AUTHZ_PORT"
HEALTH_PATH = "/healthz"
# Log-field caps: a forwarded URI is client-chosen, so it is bounded before it reaches the log.
FIELD_MAX = 160
FP_LEN = 12      # sha256 hex prefix length — an id, never a value (CONVENTIONS §6)


def emit(line: str) -> None:
    """The one log writer. stdout, because the json-file driver timestamps it for us; a module
    function so the self-test can capture it through `redirect_stdout`."""
    print(line, flush=True)


def field(value: str | None) -> str:
    """A log field from client-controlled input: bounded, single-token, never empty."""
    if not value:
        return "-"
    text = " ".join(str(value).split())
    return text[:FIELD_MAX] if text else "-"


def fingerprint(token: str | None) -> str:
    """sha256[:12] of the presented token — the most it may ever say about a credential."""
    if not token:
        return "-"
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:FP_LEN]


def load_config(path: str) -> tuple[list[str], str, str]:
    """(client_tokens, engine_token, reason). Never raises: a config problem is the caller's
    fail-closed answer, and `reason` is a verdict word — it carries no path, no value, no length."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except FileNotFoundError:
        return [], "", "config_missing"
    except IsADirectoryError:
        return [], "", "config_is_a_directory"
    except OSError:
        return [], "", "config_unreadable"
    except (ValueError, UnicodeError):
        return [], "", "config_invalid_json"
    if not isinstance(raw, dict):
        return [], "", "config_not_an_object"
    engine = raw.get("engine_token")
    if not isinstance(engine, str) or not engine:
        return [], "", "config_engine_key_absent"
    clients = raw.get("client_tokens")
    if not isinstance(clients, list):
        return [], engine, "config_client_tokens_absent"
    usable = [token for token in clients if isinstance(token, str) and token]
    if not usable:
        return [], engine, "config_client_tokens_empty"
    return usable, engine, ""


def presented_token(header: str | None) -> tuple[str, str]:
    """(token, reason) for an `Authorization` header. The scheme is case-insensitive (RFC 6750 §2.1);
    anything that is not exactly one bearer value is a refusal, not a best-effort parse."""
    if not header:
        return "", "no_authorization_header"
    parts = header.split()
    if len(parts) != 2:
        return "", "malformed_authorization_header"
    scheme, token = parts
    if scheme.lower() != "bearer":
        return "", "not_a_bearer_credential"
    return (token, "") if token else ("", "malformed_authorization_header")


def matches(presented: str, clients: list[str]) -> bool:
    target = presented.encode("utf-8")
    found = False
    for client in clients:
        # Every entry is compared, and compare_digest does not short-circuit on length the way `==`
        # does: which entry matched is not a timing question.
        if hmac.compare_digest(client.encode("utf-8"), target):
            found = True
    return found


class Verifier(BaseHTTPRequestHandler):
    server_version = "spark-llm-authz"
    sys_version = ""          # the interpreter version belongs in no response header
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):    # noqa: A003 - the name is the library's
        """Silence the standard library's request-line logging: the request line is client-chosen
        bytes, so it is the one place a query-string credential would reach the log unasked."""

    def respond(self, status: int, body: bytes = b"", authorization: str | None = None) -> None:
        self._answered = True
        self.send_response(status)
        if authorization is not None:
            # The exact header name is the mechanism: Traefik copies the response header named in
            # `forwardAuth.authResponseHeaders` onto the forwarded request, replacing the client's.
            self.send_header("Authorization", authorization)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        # Close, not keep-alive: a subrequest that carried a body would leave those bytes in the
        # socket, and HTTP/1.1 would then read them as the NEXT subrequest. Costless at subrequest
        # rates, and it is why this program never has to drain a request body to stay in sync.
        self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD" and body:
            self.wfile.write(body)
        self.close_connection = True

    def authorize(self) -> None:
        self._answered = False
        note = (f"method={field(self.headers.get('X-Forwarded-Method') or self.command)} "
                f"path={field((self.headers.get('X-Forwarded-Uri') or self.path).split('?', 1)[0])} "
                f"host={field(self.headers.get('X-Forwarded-Host'))}")
        try:
            config = os.environ.get(CONFIG_ENV, CONFIG_DEFAULT)
            if self.path.split("?", 1)[0] == HEALTH_PATH:
                # Liveness of the process and its listener only — never of the credential set. The
                # config verdict rides along as a word so a broken config is visible in the log
                # while no router points at this service yet; the auth path below is what denies.
                _, _, why = load_config(config)
                emit(f"health {note} config={why or 'ok'}")
                self.respond(200, b"ok\n")
                return
            clients, engine, why = load_config(config)
            if why:
                self.deny(why, note, "")
                return
            presented, why = presented_token(self.headers.get("Authorization"))
            if why:
                self.deny(why, note, "")
                return
            if matches(presented, clients):
                emit(f"allow reason=matched {note} client={fingerprint(presented)}")
                self.respond(200, b"", f"Bearer {engine}")
                return
            self.deny("unknown_client_token", note, presented)
        except Exception as exc:      # noqa: BLE001 - fail closed means ANY failure denies
            why = f"handler_error_{type(exc).__name__}"
            emit(f"deny reason={why} {note} client=-")
            if not getattr(self, "_answered", False):
                self.respond(401)

    def deny(self, reason: str, note: str, presented: str) -> None:
        emit(f"deny reason={reason} {note} client={fingerprint(presented)}")
        self.respond(401)

    # Any method on the auth endpoint: Traefik forwards the ORIGINAL method unless the route says
    # otherwise, so a GET-only verifier would deny every POST the moment a router is attached.
    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = do_TRACE = authorize


def serve(bind: str, port: int) -> ThreadingHTTPServer:
    server = ThreadingHTTPServer((bind, port), Verifier)
    server.daemon_threads = True      # a stuck subrequest must not block shutdown
    return server


def healthcheck() -> int:
    """Compose healthcheck: ask this host's own listener. 127.0.0.1 is probed regardless of
    AUTHZ_BIND because that is the address the edge dials too, and it keeps the probe local."""
    port = os.environ.get(PORT_ENV)
    if not port:
        emit(f"health: {PORT_ENV} is unset — the compose renders it, so the probe cannot answer")
        return 2
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{HEALTH_PATH}", timeout=3) as reply:
            ok = reply.status == 200
    except Exception as exc:      # noqa: BLE001 - a health probe reports, it does not raise
        emit(f"health: FAIL {type(exc).__name__}")
        return 1
    emit(f"health: {'ok' if ok else 'FAIL'}")
    return 0 if ok else 1


# ---- self-test: fixtures over loopback, ZERO vault and ZERO egress (CONVENTIONS §6, todo-table.md §C rule 7) ----

# Fixture bytes, not credentials: unique, non-secret, and greppable so the log-capture arm can
# prove THESE strings never reach the log.
CLIENT_A = "SELFTEST-CLIENT-A-0123456789abcdef0123456789abcdef"
CLIENT_B = "SELFTEST-CLIENT-B-0123456789abcdef0123456789abcdef"
CLIENT_NO = "SELFTEST-CLIENT-X-0123456789abcdef0123456789abcdef"
ENGINE_KEY = "SELFTEST-ENGINEKEY-0123456789abcdef0123456789abcdef"
# The token the fail-closed arms present: valid-looking, configured in the GOOD fixture, and refused
# the moment the config stops carrying it. That pair of verdicts is what makes this suite non-vacuous.
VALID_LOOKING = CLIENT_A


def _write(path: Path, payload) -> Path:
    path.write_text(payload if isinstance(payload, str) else json.dumps(payload), encoding="utf-8")
    return path


def _ask(port: int, method: str = "GET", path: str = "/authz", bearer: str | None = None):
    """One request. Returns (status, headers-lowercased, body)."""
    request = urllib.request.Request(f"http://127.0.0.1:{port}{path}", method=method)
    if bearer is not None:
        request.add_header("Authorization", f"Bearer {bearer}")
    try:
        with urllib.request.urlopen(request, timeout=5) as reply:
            return reply.status, {k.lower(): v for k, v in reply.headers.items()}, reply.read()
    except urllib.error.HTTPError as exc:
        return exc.code, {k.lower(): v for k, v in exc.headers.items()}, exc.read()


def self_test() -> int:
    fixture = Path(tempfile.mkdtemp(prefix="spark-llm-authz-selftest-"))
    results: list[tuple[str, bool, str]] = []
    saved_config = os.environ.get(CONFIG_ENV)
    server = None

    def record(name: str, ok: bool, detail: str = "") -> None:
        results.append((name, bool(ok), detail))

    try:
        good = _write(fixture / "good.json", {"engine_token": ENGINE_KEY,
                                              "client_tokens": [CLIENT_A, CLIENT_B]})
        empty = _write(fixture / "empty.json", {"engine_token": ENGINE_KEY, "client_tokens": []})
        no_engine = _write(fixture / "no-engine.json", {"client_tokens": [CLIENT_A]})
        broken = _write(fixture / "broken.json", "{ this is not json")
        absent = fixture / "absent.json"

        server = serve("127.0.0.1", 0)      # port 0 = an ephemeral loopback port, nothing external
        port = server.server_address[1]
        threading.Thread(target=server.serve_forever, daemon=True).start()

        def asked(config: Path, method: str = "GET", bearer: str | None = CLIENT_A,
                  header: str | None = None):
            """One request against one fixture, with the log captured."""
            os.environ[CONFIG_ENV] = str(config)
            log = StringIO()
            with redirect_stdout(log):
                if header is not None:
                    request = urllib.request.Request(f"http://127.0.0.1:{port}/authz", method=method)
                    request.add_header("Authorization", header)
                    try:
                        with urllib.request.urlopen(request, timeout=5) as reply:
                            status, headers = reply.status, {k.lower(): v for k, v in reply.headers.items()}
                    except urllib.error.HTTPError as exc:
                        status, headers = exc.code, {k.lower(): v for k, v in exc.headers.items()}
                else:
                    status, headers, _ = _ask(port, method=method, bearer=bearer)
            return status, headers, log.getvalue()

        # 1 — the arm the whole service exists for.
        status, headers, _ = asked(good)
        record("valid-client-token-allows-with-engine-key",
               status == 200 and headers.get("authorization") == f"Bearer {ENGINE_KEY}",
               f"status={status} authorization={headers.get('authorization', '<absent>')}")

        # 2 — a LIST is iterated, not compared to entry zero.
        status, headers, _ = asked(good, bearer=CLIENT_B)
        record("second-configured-client-allows",
               status == 200 and headers.get("authorization") == f"Bearer {ENGINE_KEY}",
               f"status={status}")

        # 3 — an unknown token denies AND leaks no engine key on the way out.
        status, headers, _ = asked(good, bearer=CLIENT_NO)
        record("unknown-token-denies-with-no-engine-key",
               status == 401 and "authorization" not in headers,
               f"status={status} authorization={'PRESENT' if 'authorization' in headers else 'absent'}")

        # 4 — no header at all.
        status, headers, _ = asked(good, bearer=None)
        record("missing-authorization-header-denies",
               status == 401 and "authorization" not in headers, f"status={status}")

        # 5 — malformed shapes: a scheme with nothing, a bearer with two words, the wrong scheme.
        malformed = ["Bearer", "Basic " + CLIENT_A, "Token=" + CLIENT_A, f"Bearer {CLIENT_A} extra"]
        bad = []
        for form in malformed:
            status, headers, _ = asked(good, header=form)
            if status != 401 or "authorization" in headers:
                bad.append(f"{form!r}->{status}")
        record("malformed-authorization-denies", not bad, f"accepted: {bad}")

        # 6 — RFC 6750 makes the scheme case-insensitive; pinning it keeps a client library's
        #     `bearer` spelling from becoming an outage.
        status, headers, _ = asked(good, header=f"bearer {CLIENT_A}")
        record("bearer-scheme-case-is-honoured",
               status == 200 and headers.get("authorization") == f"Bearer {ENGINE_KEY}",
               f"status={status}")

        # 7 — THE fail-closed arm: the same token that was allowed one arm ago is refused by an
        #     allow-list with no entries. If this ever returns 200, every allow above is a lie.
        status, headers, _ = asked(empty, bearer=VALID_LOOKING)
        record("empty-client-list-refuses-a-valid-looking-token",
               status == 401 and "authorization" not in headers,
               f"status={status} authorization={'PRESENT' if 'authorization' in headers else 'absent'}")

        # 8/9/10 — the other ways a config is not a config: all three must deny a valid token.
        for name, config in (("absent", absent), ("unparsable", broken), ("no-engine-key", no_engine)):
            status, headers, _ = asked(config, bearer=VALID_LOOKING)
            record(f"{name}-config-refuses-a-valid-token",
                   status == 401 and "authorization" not in headers, f"status={status}")

        # 11 — the healthcheck path, with no credential and a broken config: still 200, because the
        #      probe reports the listener and the denial is the auth path's answer.
        os.environ[CONFIG_ENV] = str(broken)
        log = StringIO()
        with redirect_stdout(log):
            status, headers, _ = _ask(port, path=HEALTH_PATH, bearer=None)
        record("healthz-answers-unauthenticated", status == 200, f"status={status}")
        record("healthz-logs-the-config-verdict", "config=config_invalid_json" in log.getvalue(),
               log.getvalue().strip())

        # 12 — any method answers on the auth endpoint (the pin forwards the original method).
        wrong = [m for m in ("POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD")
                 if asked(good, method=m)[0] != 200]
        record("any-method-on-the-auth-endpoint-allows", not wrong, f"did not allow: {wrong}")

        # 13 — a rotation reaches the NEXT request with no restart, and so does a withdrawal. This
        #      is the property that replaces the engine restart; it is proved by mutating the file
        #      the running server reads, not by pointing at a second fixture.
        os.environ[CONFIG_ENV] = str(good)
        probe_log = StringIO()
        with redirect_stdout(probe_log):
            before = _ask(port, method="POST", bearer=CLIENT_A)[0]
            _write(good, {"engine_token": ENGINE_KEY, "client_tokens": [CLIENT_B]})
            after = _ask(port, method="POST", bearer=CLIENT_A)[0]
            back = _ask(port, method="POST", bearer=CLIENT_B)[0]
        record("config-is-re-read-per-request", (before, after, back) == (200, 401, 200),
               f"before={before} withdrawn={after} retained={back}")
        _write(good, {"engine_token": ENGINE_KEY, "client_tokens": [CLIENT_A, CLIENT_B]})

        # 14 — the disclosure budget, measured on the real writer: no fixture credential, no engine
        #      key, no `Bearer ` echo anywhere in what these arms logged; and the fingerprint IS
        #      present, so this arm proves a policy rather than an empty log.
        captured = []
        for config, method, bearer in ((good, "POST", CLIENT_A), (good, "GET", CLIENT_NO),
                                       (good, "GET", None), (empty, "GET", VALID_LOOKING),
                                       (broken, "GET", VALID_LOOKING)):
            captured.append(asked(config, method=method, bearer=bearer)[2])
        log = "".join(captured)
        leaks = [name for name, value in (("client-a", CLIENT_A), ("client-b", CLIENT_B),
                                          ("client-x", CLIENT_NO), ("engine-key", ENGINE_KEY))
                 if value in log]
        leaked_header = "bearer " in log.lower()
        printed_fp = fingerprint(CLIENT_A) in log
        record("no-credential-bytes-ever-reach-the-log",
               not leaks and not leaked_header and printed_fp,
               f"leaked={leaks} header_echo={leaked_header} fingerprint={printed_fp}")
        # A deny must still name the presenter by hash and nothing else.
        record("a-deny-identifies-the-presenter-by-hash-only",
               f"client={fingerprint(CLIENT_NO)}" in log and CLIENT_NO not in log)

        # 15 — the header fields the log carries come from Traefik's X-Forwarded-* set, so a route
        #      table that renames them cannot silently blank the audit trail's path column.
        os.environ[CONFIG_ENV] = str(good)
        request = urllib.request.Request(f"http://127.0.0.1:{port}/authz", method="POST")
        request.add_header("Authorization", f"Bearer {CLIENT_A}")
        request.add_header("X-Forwarded-Method", "POST")
        request.add_header("X-Forwarded-Uri", "/v1/chat/completions")
        request.add_header("X-Forwarded-Host", "llm.kogler.si")
        log = StringIO()
        with redirect_stdout(log):
            with urllib.request.urlopen(request, timeout=5):
                pass
        recorded = log.getvalue()
        record("forwarded-request-line-is-logged",
               all(token in recorded for token in
                   ("path=/v1/chat/completions", "method=POST", "host=llm.kogler.si")),
               recorded.strip())
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        if saved_config is None:
            os.environ.pop(CONFIG_ENV, None)
        else:
            os.environ[CONFIG_ENV] = saved_config
        shutil.rmtree(fixture, ignore_errors=True)

    failed = [name for name, ok, _ in results if not ok]
    for name, ok, detail in results:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if not ok else ""))
    print(f"self-test: {len(results) - len(failed)}/{len(results)} arms passed")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    if "--healthcheck" in argv:
        return healthcheck()
    port = os.environ.get(PORT_ENV)
    if not port:
        emit(f"error: {PORT_ENV} is unset — the compose renders it from spark_llm_authz_port")
        return 2
    bind = os.environ.get(BIND_ENV, BIND_DEFAULT)
    config = os.environ.get(CONFIG_ENV, CONFIG_DEFAULT)
    server = serve(bind, int(port))
    # The config is NOT read here on purpose: startup answers "the listener is up", and the first
    # request is what discovers a config problem — as a denial, with the reason in its own line.
    emit(f"serve bind={bind} port={port} config={config}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
