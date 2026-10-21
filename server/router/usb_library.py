"""Unsigned, read-only HTTP catalog limited to the USB movie directory."""
import json
import os
from pathlib import Path, PurePosixPath
import stat
from urllib.parse import quote, unquote
from html import escape

MOVIES = frozenset((".mkv", ".mp4", ".m4v", ".mov", ".webm", ".avi", ".ts"))
SUBS = frozenset((".srt", ".ass", ".ssa", ".vtt"))
PREFIX = "/usb-files/"
LIMIT = 5000

def root_from(config):
    root = Path(config["root"]).resolve(strict=True)
    mount = config.get("mount")
    if mount:
        if not os.path.ismount(mount) or (root / ".volume-identity").read_text().strip() != config.get("uuid"):
            raise OSError("USB media unavailable")
    target = root / "电影"
    if target.is_symlink() or not target.is_dir():
        raise OSError("movie directory unavailable")
    return target.resolve(strict=True)

def resolve_file(root, name):
    if not name or "\\" in name or "\x00" in name or len(name) > 1800:
        return None
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or any(x in (".", "..") or x.startswith(".") for x in path.parts):
        return None
    if path.suffix.lower() not in MOVIES | SUBS:
        return None
    candidate = root
    for part in path.parts:
        candidate = candidate / part
        if candidate.is_symlink():
            return None
    try:
        if not candidate.resolve(strict=True).is_relative_to(root):
            return None
        if not stat.S_ISREG(candidate.stat(follow_symlinks=False).st_mode):
            return None
    except OSError:
        return None
    return candidate

def catalog(root):
    movies = []
    inspected = 0
    for directory, folders, files in os.walk(root, followlinks=False):
        folders[:] = sorted([d for d in folders if not d.startswith(".") and not (Path(directory)/d).is_symlink()], key=str.casefold)
        for name in sorted(files, key=str.casefold):
            inspected += 1
            if inspected > LIMIT:
                return movies
            if name.startswith(".") or Path(name).suffix.lower() not in MOVIES:
                continue
            file = Path(directory) / name
            relative = file.relative_to(root).as_posix()
            if resolve_file(root, relative) is None:
                continue
            info = file.stat()
            movies.append({"name": name, "path": relative, "size": info.st_size,
                           "url": PREFIX + quote(relative, safe="/")})
    return movies

def respond(handler, data, mime, body):
    handler.send_response(200)
    handler.send_header("Content-Type", mime)
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.send_header("Connection", "close")
    handler.end_headers()
    if body:
        handler.wfile.write(data)

def html_page(items):
    parts = ['<!doctype html><html lang="zh"><meta charset="utf-8">',
             '<meta name="viewport" content="width=device-width,initial-scale=1">',
             '<title>TogetherPlayer U盘影视库</title>',
             '<style>body{font:16px sans-serif;max-width:920px;margin:2em auto;padding:0 16px;background:#101827;color:#fff}a{color:#78bdff;overflow-wrap:anywhere}li{padding:10px 0;border-bottom:1px solid #445}</style>',
             '<h1>U盘影视库</h1><p>未加密 HTTP 链接，知道地址的人可以直接读取。</p><ul>']
    parts += ['<li><a href="' + escape(it["url"], quote=True) + '">' + escape(it["path"]) + '</a></li>' for it in items]
    return ("\n".join(parts) + "</ul></html>").encode()

def subtitle_catalog(root, file):
    if file.suffix.lower() not in MOVIES:
        return []
    prefix = file.stem.casefold() + "."
    options = []
    for item in file.parent.iterdir():
        if len(options) >= 24:
            break
        if not item.name.casefold().startswith(prefix) or item.suffix.lower() not in SUBS:
            continue
        rel = item.relative_to(root).as_posix()
        checked = resolve_file(root, rel)
        if checked is not None and 0 < checked.stat().st_size <= 5*1024*1024:
            options.append({"name": item.name, "url": PREFIX + quote(rel, safe="/")})
    return sorted(options, key=lambda x: x["name"].casefold())

def handle(handler, path, query, body, config, byte_range):
    if path not in ("/usb-library", "/usb-library/", "/usb-library.json") and not path.startswith(PREFIX):
        return False
    if query and (query != "subtitles=1" or not path.startswith(PREFIX)):
        handler.empty(404)
        return True
    try:
        root = root_from(config)
    except (OSError, ValueError):
        handler.empty(503, {"Retry-After": "5"})
        return True
    if not path.startswith(PREFIX):
        items = catalog(root)
        if path == "/usb-library.json":
            respond(handler, json.dumps({"version": 1, "items": items}, ensure_ascii=False).encode(),
                    "application/json; charset=utf-8", body)
        else:
            respond(handler, html_page(items), "text/html; charset=utf-8", body)
        return True
    try:
        name = unquote(path[len(PREFIX):], encoding="utf-8", errors="strict")
        file = resolve_file(root, name)
        if file is None:
            handler.empty(404)
            return True
        if query == "subtitles=1":
            respond(handler, json.dumps({"subtitles": subtitle_catalog(root, file)}, ensure_ascii=False).encode(),
                    "application/json; charset=utf-8", body)
            return True
        with file.open("rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
                handler.empty(404)
                return True
            try:
                start, end, status = byte_range(handler.headers.get("Range"), info.st_size)
            except ValueError:
                handler.empty(416, {"Content-Range": f"bytes */{info.st_size}"})
                return True
            import mimetypes
            mime = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
            if file.suffix.lower() == ".mkv":
                mime = "video/x-matroska"
            handler.send_response(status)
            handler.send_header("Content-Type", mime)
            handler.send_header("Content-Length", str(end-start+1))
            handler.send_header("Accept-Ranges", "bytes")
            handler.send_header("Cache-Control", "no-store")
            handler.send_header("X-Content-Type-Options", "nosniff")
            handler.send_header("Connection", "close")
            if status == 206:
                handler.send_header("Content-Range", f"bytes {start}-{end}/{info.st_size}")
            handler.end_headers()
            if body:
                source.seek(start)
                left = end - start + 1
                while left:
                    data = source.read(min(left, 131072))
                    if not data:
                        break
                    handler.wfile.write(data)
                    left -= len(data)
    except (BrokenPipeError, ConnectionResetError, TimeoutError):
        pass
    except (OSError, UnicodeError, ValueError):
        handler.empty(404)
    return True
