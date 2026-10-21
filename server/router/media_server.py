#!/usr/bin/env python3
"""Small, allowlisted USB file server. No directory browsing or public writes."""
import argparse
import hashlib
import hmac
import http.server
import json
import mimetypes
import os
from pathlib import Path
import re
import socket
import ssl
import stat
import threading
import time
from urllib.parse import parse_qs, quote, urlsplit
import usb_library


def signed_path(media_id, entry, expires, filename=None):
    name = filename or Path(entry['file']).name
    path = '/media/' + media_id + '/' + quote(name, safe='')
    signature = hmac.new(bytes.fromhex(entry['key']),
                         (path + '\n' + str(expires)).encode(), hashlib.sha256).hexdigest()
    return path + '?expires=' + str(expires) + '&sig=' + signature


def subtitle_sidecars(root, entry):
    # Only allow same-directory, same-film text subtitle sidecars.
    video = root / entry['file']
    prefix = video.stem.casefold() + '.'
    results = []
    with os.scandir(video.parent) as entries:
        for number, candidate in enumerate(entries):
            if number >= 1500:
                break
            name = candidate.name
            if (not name.casefold().startswith(prefix) or
                    Path(name).suffix.casefold() not in ('.srt', '.vtt', '.ass', '.ssa')):
                continue
            try:
                info = candidate.stat(follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISREG(info.st_mode) and 0 < info.st_size <= 5 * 1024 * 1024:
                results.append(name)
    return sorted(results, key=str.casefold)[:24]


def byte_range(value, size):
    if not value:
        return 0, size - 1, 200
    match = re.fullmatch(r'bytes=(\d*)-(\d*)', value)
    if not match or not any(match.groups()) or size <= 0:
        raise ValueError('invalid range')
    first, last = match.groups()
    if first:
        start = int(first)
        end = min(int(last) if last else size - 1, size - 1)
    else:
        suffix = int(last)
        if suffix == 0:
            raise ValueError('empty suffix')
        start, end = max(0, size - suffix), size - 1
    if start >= size or start > end:
        raise ValueError('unsatisfiable range')
    return start, end, 206


class MediaServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, config_path, address=None, plain=False, port=None):
        self.config_path = Path(config_path)
        self.config = self.read_config()
        self.slots = threading.BoundedSemaphore(8)
        super().__init__(address or ('::', port or self.config.get('port', 49183)), Handler)
        if self.config.get('certificate') and not plain:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            # MT7621 has no AES acceleration. Prefer ChaCha on capable clients;
            # retain AES-128/256 GCM for platform TLS stacks without ChaCha.
            context.set_ciphers('ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:'
                                'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:'
                                'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384')
            context.load_cert_chain(self.config['certificate'], self.config['privateKey'])
            self.socket = context.wrap_socket(self.socket, server_side=True)

    def read_config(self):
        return json.loads(self.config_path.read_text())

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        super().server_bind()

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            try:
                request.sendall(b'HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\nRetry-After: 2\r\n\r\n')
            except OSError:
                pass
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

    def handle_error(self, request, address):
        # Never print a request URL, signature, local path or peer address.
        print('media_request_failed', flush=True)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.settimeout(120)

    def log_message(self, *args):
        pass

    def empty(self, status, extra=None):
        self.send_response(status)
        self.send_header('Content-Length', '0')
        self.send_header('Connection', 'close')
        self.send_header('Cache-Control', 'no-store')
        for name, value in (extra or {}).items():
            self.send_header(name, value)
        self.end_headers()

    def do_HEAD(self):
        self.respond(False)

    def do_GET(self):
        self.respond(True)

    def do_POST(self):
        self.close_connection = True
        self.empty(405)

    def respond(self, body):
        self.close_connection = True
        started = False
        try:
            if len(self.path) > 4096:
                self.empty(414)
                return
            target = urlsplit(self.path)
            config = self.server.read_config()
            if usb_library.handle(self, target.path, target.query, body, config, byte_range):
                return
            if target.path == '/health' and not target.query:
                self.empty(204)
                return
            parts = target.path.split('/')
            if len(parts) != 4 or parts[1] != 'media':
                self.empty(404)
                return
            entry = config.get('media', {}).get(parts[2])
            query = parse_qs(target.query, strict_parsing=True, max_num_fields=3)
            listing = query.get('subtitles') == ['1']
            if (not entry or set(query) not in ({'expires', 'sig'}, {'expires', 'sig', 'subtitles'})
                    or ('subtitles' in query and not listing)
                    or any(len(v) != 1 for v in query.values())):
                self.empty(404)
                return
            expiry = int(query['expires'][0])
            now = time.time()
            if expiry <= now or expiry > now + 7 * 86400:
                self.empty(403)
                return
            expected = signed_path(parts[2], entry, expiry)
            expected_path, expected_query = expected.split('?', 1)
            signature = parse_qs(expected_query)['sig'][0]
            video_authorized = (target.path == expected_path and
                                hmac.compare_digest(signature, query['sig'][0]))
            if listing and not video_authorized:
                self.empty(403)
                return
            root = Path(config['root']).resolve(strict=True)
            if config.get('mount'):
                mount = config['mount']
                mounted = any(p[1] == mount and p[2] in ('ntfs3', 'ext4')
                              for p in (line.split() for line in Path('/proc/mounts').read_text().splitlines()))
                if not mounted or (root / '.volume-identity').read_text().strip() != config['uuid']:
                    self.empty(503, {'Retry-After': '5'})
                    return
            video_file = root / entry['file']
            if video_file.is_symlink() or not video_file.resolve(strict=True).is_relative_to(root):
                self.empty(404)
                return
            sidecars = subtitle_sidecars(root, entry) if listing or not video_authorized else []
            if listing:
                tracks = [{'name': name, 'url': signed_path(parts[2], entry, expiry, name)}
                          for name in sidecars]
                payload = json.dumps({'subtitles': tracks}, ensure_ascii=False).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Content-Length', str(len(payload)))
                self.send_header('Connection', 'close')
                self.send_header('Cache-Control', 'private, no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                if body:
                    self.wfile.write(payload)
                return
            filename = video_file
            if not video_authorized:
                matched = next((name for name in sidecars
                                if target.path == signed_path(parts[2], entry, expiry, name).split('?', 1)[0]
                                and hmac.compare_digest(
                                    query['sig'][0],
                                    parse_qs(signed_path(parts[2], entry, expiry, name).split('?', 1)[1])['sig'][0])),
                               None)
                if matched is None:
                    self.empty(403)
                    return
                filename = video_file.parent / matched
                if filename.is_symlink() or not filename.resolve(strict=True).is_relative_to(root):
                    self.empty(404)
                    return
            descriptor = os.open(filename, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
            with os.fdopen(descriptor, 'rb') as source:
                info = os.fstat(source.fileno())
                if not stat.S_ISREG(info.st_mode):
                    self.empty(404)
                    return
                size = info.st_size
                try:
                    start, end, status = byte_range(self.headers.get('Range'), size)
                except ValueError:
                    self.empty(416, {'Content-Range': 'bytes */' + str(size)})
                    return
                count = max(0, end - start + 1)
                self.send_response(status)
                self.send_header('Content-Type', mimetypes.guess_type(entry['file'])[0] or 'application/octet-stream')
                self.send_header('Content-Length', str(count))
                self.send_header('Connection', 'close')
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Cache-Control', 'private, no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                if status == 206:
                    self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
                self.end_headers()
                started = True
                if body:
                    source.seek(start)
                    while count:
                        chunk = source.read(min(count, 131072))
                        if not chunk:
                            self.close_connection = True
                            return
                        self.wfile.write(chunk)
                        count -= len(chunk)
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            self.close_connection = True
        except (ValueError, KeyError, UnicodeError):
            self.empty(404)
        except OSError:
            if started:
                self.close_connection = True
            else:
                self.empty(503, {'Retry-After': '5'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['serve', 'link'])
    parser.add_argument('--config', default='/etc/together-media/config.json')
    parser.add_argument('--id')
    parser.add_argument('--base')
    parser.add_argument('--hours', type=int, default=24)
    parser.add_argument('--plain', action='store_true')
    parser.add_argument('--port', type=int)
    args = parser.parse_args()
    if args.action == 'link':
        config = json.loads(Path(args.config).read_text())
        if not args.base or args.id not in config['media'] or not 1 <= args.hours <= 168:
            parser.error('valid base, media id and 1..168 hours required')
        print(args.base.rstrip('/') + signed_path(args.id, config['media'][args.id], int(time.time()) + args.hours * 3600))
    else:
        MediaServer(args.config, plain=args.plain, port=args.port).serve_forever(poll_interval=0.5)


if __name__ == '__main__':
    main()
