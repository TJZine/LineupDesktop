#!/usr/bin/env python3
"""Loopback-only synthetic HTTPS fixture server, safe boolean-only request audit."""
import argparse, hmac, http.server, json, pathlib, re, ssl, threading, urllib.parse
TOKEN = 'lineup-synthetic-fixture-only'
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self, *_): pass
    def do_HEAD(self): self.serve(False)
    def do_GET(self): self.serve(True)
    def serve(self, body):
        path=urllib.parse.urlsplit(self.path).path
        route=path.split('/')[-1]
        known_routes={p.name for p in self.server.root.iterdir() if p.suffix in ('.mp4','.mkv')} | {'same','cross-host','cross-port','downgrade','loop','nested.m3u8','sink'}
        valid=hmac.compare_digest(self.headers.get('X-Plex-Token',''),TOKEN)
        # Do not store raw request targets, query strings, or header values.
        entry={'route':route if route in known_routes else 'other','token_header':bool(self.headers.get('X-Plex-Token')),'token_valid':valid,'token_in_url':TOKEN in self.path or 'x-plex-token' in self.path.lower(),'range':bool(self.headers.get('Range')),'port':self.server.server_port}
        with self.server.audit_lock:
            with self.server.audit.open('a') as log: log.write(json.dumps(entry)+'\n')
        if path.startswith('/auth/') and not valid: return self.empty(401)
        redirects={'same':f'https://localhost:{self.server.server_port}/auth/h264.mp4','cross-host':f'https://127.0.0.1:{self.server.server_port}/sink','cross-port':f'https://localhost:{self.server.other_port}/sink','downgrade':f'http://localhost:{self.server.other_port}/sink','loop':f'https://localhost:{self.server.server_port}/auth/loop'}
        if route in redirects:
            self.send_response(302); self.send_header('Location',redirects[route]); self.send_header('Content-Length','0'); self.end_headers(); return
        if route=='nested.m3u8':
            data=f'#EXTM3U\n#EXTINF:120,\nhttps://localhost:{self.server.server_port}/auth/h264.mp4\n'.encode()
            self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers()
            if body: self.wfile.write(data)
            return
        file=self.server.root/route
        if not file.is_file() or file.suffix not in ('.mp4','.mkv'): return self.empty(404)
        size=file.stat().st_size; first=0; last=size-1
        value=self.headers.get('Range')
        if value:
            match=re.fullmatch(r'bytes=(\d+)-(\d*)',value)
            if not match: return self.empty(416)
            first=int(match[1]); last=min(int(match[2]),last) if match[2] else last
            if first>last: return self.empty(416)
        self.send_response(206 if value else 200)
        self.send_header('Accept-Ranges','bytes'); self.send_header('Content-Type','video/mp4' if file.suffix=='.mp4' else 'video/x-matroska')
        self.send_header('Content-Length',str(last-first+1))
        if value: self.send_header('Content-Range',f'bytes {first}-{last}/{size}')
        self.end_headers()
        if body:
            try:
                with file.open('rb') as source:
                    source.seek(first); remaining=last-first+1
                    while remaining:
                        data=source.read(min(65536,remaining))
                        if not data: break
                        self.wfile.write(data); remaining-=len(data)
            except (BrokenPipeError,ConnectionResetError,ssl.SSLError): pass
    def empty(self,status):
        self.send_response(status); self.send_header('Content-Length','0'); self.end_headers()
class Server(http.server.ThreadingHTTPServer):
    daemon_threads=True
    def handle_error(self,*_): pass
if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--root',type=pathlib.Path,default=pathlib.Path(__file__).parent/'fixtures'); parser.add_argument('--audit',type=pathlib.Path,required=True); args=parser.parse_args()
    cert=pathlib.Path.home()/'.config/lineup-android/fixture-ca'
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(cert/'localhost.crt',cert/'localhost.key')
    servers=[]
    for port,other in [(18443,18444),(18444,18443)]:
        server=Server(('127.0.0.1',port),Handler); server.root=args.root; server.audit=args.audit; server.audit_lock=threading.Lock(); server.other_port=other; server.socket=context.wrap_socket(server.socket,server_side=True); servers.append(server)
    threading.Thread(target=servers[1].serve_forever,daemon=True).start()
    print('loopback fixture server ready',flush=True)
    servers[0].serve_forever()
