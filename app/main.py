#!/usr/bin/env python3
"""Minimal example workload for the platform.

Deliberately small: the point of this repository is the platform around the
application, not the application. It only needs to be a real image that starts,
answers health probes, exposes metrics, and proves that the Secrets Manager ->
External Secrets -> Kubernetes Secret -> pod path actually works.

Endpoints
  GET /         service info as JSON
  GET /healthz  liveness, always 200 while the process is up
  GET /readyz   readiness, 200 only if the database check passes (or is disabled)
  GET /metrics  Prometheus text format, scraped by the VMServiceScrape

Configuration (ConfigMap)
  APP_ENV     environment name, reported in / and in metric labels
  LOG_LEVEL   DEBUG|INFO|WARNING|ERROR
  PORT        listen port, default 8000

Credentials (Kubernetes Secret produced by the ExternalSecret)
  DATABASE_URL    full postgresql:// URL; when unset the database check is skipped
  DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD  same values as separate keys
  APP_SECRET_KEY  application signing key, never logged
"""

import json
import logging
import os
import signal
import threading
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_ENV = os.environ.get("APP_ENV", "unknown")
PORT = int(os.environ.get("PORT", "8000"))
DATABASE_URL = os.environ.get("DATABASE_URL", "")
VERSION = os.environ.get("APP_VERSION", "0.1.0")

# Readiness caches the database result so a probe every few seconds does not open
# a connection every few seconds.
DB_CHECK_TTL_SECONDS = 10

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("example-app")

_requests = Counter()
_lock = threading.Lock()
_db_state = {"checked_at": 0.0, "ok": None, "error": ""}


def check_database():
    """Return (ok, detail). ok is None when no database is configured."""
    if not DATABASE_URL:
        return None, "no DATABASE_URL configured"

    now = time.monotonic()
    with _lock:
        if now - _db_state["checked_at"] < DB_CHECK_TTL_SECONDS and _db_state["ok"] is not None:
            return _db_state["ok"], _db_state["error"]

    ok, detail = False, ""
    try:
        import psycopg

        with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        ok, detail = True, "connected"
    except Exception as exc:  # noqa: BLE001 - the reason is reported, not swallowed
        # Never include DATABASE_URL in the message: it contains the password.
        detail = type(exc).__name__
        log.warning("database check failed: %s", detail)

    with _lock:
        _db_state.update(checked_at=now, ok=ok, error=detail)
    return ok, detail


def render_metrics():
    with _lock:
        counts = dict(_requests)
    lines = [
        "# HELP example_app_up 1 when the process is serving.",
        "# TYPE example_app_up gauge",
        f'example_app_up{{env="{APP_ENV}",version="{VERSION}"}} 1',
        "# HELP example_app_requests_total HTTP requests handled, by path and status.",
        "# TYPE example_app_requests_total counter",
    ]
    for (path, status), value in sorted(counts.items()):
        lines.append(f'example_app_requests_total{{path="{path}",status="{status}"}} {value}')

    ok, _ = check_database()
    lines += [
        "# HELP example_app_database_up 1 when the configured database answers, 0 when it does not.",
        "# TYPE example_app_database_up gauge",
        f"example_app_database_up {1 if ok else 0}",
    ]
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "example-app"
    sys_version = ""

    def log_message(self, fmt, *args):
        log.debug("%s %s", self.address_string(), fmt % args)

    def _respond(self, status, body, content_type="application/json"):
        payload = body.encode()
        with _lock:
            _requests[(self.path.split("?")[0], status)] += 1
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/healthz":
            self._respond(200, json.dumps({"status": "ok"}))
            return

        if path == "/readyz":
            ok, detail = check_database()
            # ok is None when no database is configured, which is a valid setup.
            ready = ok is not False
            self._respond(
                200 if ready else 503,
                json.dumps({"ready": ready, "database": detail}),
            )
            return

        if path == "/metrics":
            self._respond(200, render_metrics(), "text/plain; version=0.0.4")
            return

        if path == "/":
            ok, detail = check_database()
            self._respond(
                200,
                json.dumps(
                    {
                        "app": "example-app",
                        "version": VERSION,
                        "env": APP_ENV,
                        "database": {"configured": bool(DATABASE_URL), "detail": detail},
                    }
                ),
            )
            return

        self._respond(404, json.dumps({"error": "not found"}))


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True

    def shutdown(signum, _frame):
        log.info("received signal %s, shutting down", signum)
        threading.Thread(target=server.shutdown, daemon=True).start()

    # Without a SIGTERM handler the container is SIGKILLed after the grace
    # period and in-flight requests are dropped during every rollout.
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    log.info("example-app %s listening on :%s (env=%s)", VERSION, PORT, APP_ENV)
    server.serve_forever()
    server.server_close()
    log.info("stopped")


if __name__ == "__main__":
    main()
