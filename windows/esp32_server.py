#!/usr/bin/env python3
"""Simple HTTP test server for ESP32 -> Windows Mobile Hotspot -> Windows.
Only suitable for trusted demo networks; no authentication/TLS is provided.
"""
import json
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = 8080


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def send_json(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/health"):
            self.send_json(200, {"ok": True, "server": "Windows", "port": self.server.server_port})
        else:
            self.send_json(404, {"error": "Not found"})

    def do_POST(self):
        if self.path != "/data":
            self.send_json(404, {"error": "Not found"})
            return
        if self.headers.get('Transfer-Encoding') is not None:
            self.send_json(400, {"error": "Transfer-Encoding is not supported; send Content-Length"})
            return
        lengths = self.headers.get_all('Content-Length', [])
        if len(lengths) != 1:
            self.send_json(400, {"error": "One Content-Length header is required"})
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_json(400, {"error": "Invalid Content-Length"})
            return
        if size <= 0 or size > 4096:
            self.send_json(413, {"error": "Body length must be 1..4096 bytes"})
            return
        try:
            body = self.rfile.read(size)
            if len(body) != size:
                self.send_json(400, {"error": "Incomplete request body"})
                return
            payload = json.loads(body)
        except socket.timeout:
            self.send_json(408, {"error": "Request body timed out"})
            return
        except (ValueError, UnicodeDecodeError):
            self.send_json(400, {"error": "Invalid JSON"})
            return
        print("ESP32 data:", payload, flush=True)
        self.send_json(200, {"ok": True, "received": payload})


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Windows test server listening on http://{HOST}:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping server...")
    finally:
        server.server_close()
