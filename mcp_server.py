import json, ssl
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def reply(self, code, body=None):
        data = json.dumps(body).encode() if body else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply(405)

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        method, rid = req.get("method"), req.get("id")
        if rid is None:  # 通知には 202 だけ返す
            return self.reply(202)
        if method == "initialize":
            result = {"protocolVersion": req["params"].get("protocolVersion", "2025-06-18"),
                      "capabilities": {"tools": {}},
                      "serverInfo": {"name": "private-ca-demo", "version": "0.1.0"}}
        elif method == "tools/list":
            result = {"tools": [{"name": "get_internal_status",
                                 "description": "社内システムのステータスを返す",
                                 "inputSchema": {"type": "object", "properties": {}}}]}
        elif method == "tools/call":
            result = {"content": [{"type": "text", "text": "OK: VPC 内のプライベート CA 署名サーバーから応答しました"}]}
        else:
            return self.reply(200, {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "not found"}})
        self.reply(200, {"jsonrpc": "2.0", "id": rid, "result": result})

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("/opt/mcp/server.pem", "/opt/mcp/server.key")
srv = HTTPServer(("0.0.0.0", 443), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
