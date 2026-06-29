#!/usr/bin/env python3
# tests/smoke/mock-snapserver.py
#
# Tiny stand-in for Snapserver used by the CI smoke test for
# forwarder-arecord. It implements just enough of the real server to
# let the forwarder believe the round-trip succeeded:
#
#   * HTTP JSON-RPC on port 1780  (Stream.AddStream, Stream.RemoveStream)
#   * Raw TCP listener on port 5000 (audio byte sink; counts bytes)
#
# Output files (written into the directory given as argv[1], default
# ./smoke-out):
#
#   rpc.log      one line per JSON-RPC request body the forwarder sent
#   bytes.log    a running byte count, one number per accept/read cycle
#
# The script runs until killed (SIGINT/SIGTERM). It is intentionally
# single-file, dependency-free, and uses only the stdlib so the CI
# runner needs nothing extra.
import http.server
import json
import os
import signal
import socket
import socketserver
import sys
import threading
import time

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "smoke-out"
os.makedirs(OUT_DIR, exist_ok=True)

RPC_LOG = open(os.path.join(OUT_DIR, "rpc.log"), "a", buffering=1)
BYTE_LOG = open(os.path.join(OUT_DIR, "bytes.log"), "a", buffering=1)


class RpcHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802  (stdlib API)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", "replace")
        RPC_LOG.write(body + "\n")
        try:
            req = json.loads(body)
        except Exception:
            req = {}
        method = req.get("method", "")
        rid = req.get("id")
        if method == "Stream.AddStream":
            resp = {"id": rid, "jsonrpc": "2.0", "result": {"id": "Tidal"}}
        elif method == "Stream.RemoveStream":
            resp = {"id": rid, "jsonrpc": "2.0", "result": "ok"}
        else:
            resp = {"id": rid, "jsonrpc": "2.0", "result": None}
        data = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_a, **_kw):
        # Silence the default per-request stderr line; rpc.log is the
        # canonical record.
        return


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def serve_rpc():
    try:
        with ReusableTCPServer(("", 1780), RpcHandler) as srv:
            srv.serve_forever()
    except OSError as exc:
        print(f"serve_rpc: bind failed on port 1780: {exc}", file=sys.stderr, flush=True)
        os._exit(2)


def serve_audio():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("", 5000))
    except OSError as exc:
        print(f"serve_audio: bind failed on port 5000: {exc}", file=sys.stderr, flush=True)
        os._exit(2)
    s.listen(1)
    total = 0
    while True:
        conn, _ = s.accept()
        try:
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                total += len(chunk)
                BYTE_LOG.write(str(total) + "\n")
        finally:
            try:
                conn.close()
            except Exception:
                pass


def _stop(_signum, _frame):
    sys.exit(0)


signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

threading.Thread(target=serve_rpc, daemon=True).start()
threading.Thread(target=serve_audio, daemon=True).start()

# Park the main thread until killed.
while True:
    time.sleep(3600)
