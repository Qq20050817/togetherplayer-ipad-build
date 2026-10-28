"""Loopback-only nine-clip receiver for the isolated Singapore development branch.

The public HTTPS reverse proxy must terminate TLS, forward only the intended
/v1/audio-capture path to this loopback listener, and authenticate the owner
through a separately provisioned high-entropy pairing token. Production movie
MCP routing is untouched. No PCM is written to filesystem or logs.
"""
import hmac
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from subtitle_sessions import SubtitleSessions, SubtitleSessionError

_PREFIX = "/v1/audio-capture/sessions"
_CLIP = re.compile(r"^/v1/audio-capture/sessions/([A-Za-z0-9_-]{16,64})/clips/([1-9])$")
_FINISH = re.compile(r"^/v1/audio-capture/sessions/([A-Za-z0-9_-]{16,64})/finish$")
_SUBTITLES = re.compile(r"^/v1/audio-capture/sessions/([A-Za-z0-9_-]{16,64})/subtitles$")
_MAX_PCM = 12 * 16000 * 2
_MAX_JSON = 8192
_MAX_CUES_JSON = 512 * 1024


def make_handler(sessions: SubtitleSessions, pairing_secret: str):
    if not isinstance(pairing_secret, str) or len(pairing_secret) < 32:
        raise ValueError("CAPTURE_PAIRING_SECRET must be a random secret of >=32 characters")

    class CaptureHandler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_args):
            # Never log bearer tokens, media metadata or audio.
            return

        def _json(self, status, value):
            body = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            if status >= 400:
                self.close_connection = True
                self.send_header("Connection", "close")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _bearer(self):
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Bearer "):
                return ""
            token = auth[7:]
            return token if 1 <= len(token) <= 256 else ""

        def _read(self, maximum):
            if self.headers.get("Transfer-Encoding"):
                raise ValueError("transfer_encoding_not_supported")
            lengths = self.headers.get_all("Content-Length", [])
            if len(lengths) != 1 or not lengths[0].isdigit():
                raise ValueError("content_length_required")
            length = int(lengths[0])
            if length < 0 or length > maximum:
                raise ValueError("body_too_large")
            data = self.rfile.read(length)
            if len(data) != length:
                raise ValueError("truncated_body")
            return data

        def do_POST(self):
            # This process is intentionally reachable through a TLS-terminating
            # reverse proxy on the SAME host, never through a public port.
            if self.client_address[0] not in ("127.0.0.1", "::1"):
                self._json(403, {"error": "loopback_only"})
                return
            parsed = urlsplit(self.path)
            if parsed.query or parsed.fragment:
                self._json(400, {"error": "query_not_allowed"})
                return
            route = parsed.path
            # Tailscale Funnel strips its /v1/audio-capture mount prefix.
            # Accept that loopback proxy form as well as the full canonical path.
            if route == "/sessions" or route.startswith("/sessions/"):
                route = "/v1/audio-capture" + route
            token = self._bearer()
            if route == _PREFIX:
                if not hmac.compare_digest(token, pairing_secret):
                    self._json(401, {"error": "pairing_required"})
                    return
                try:
                    if self._read(_MAX_JSON) not in (b"", b"{}"):
                        raise ValueError("unexpected_metadata")
                    grant = sessions.start("paired-ipad")
                except ValueError:
                    self._json(400, {"error": "invalid_request"})
                    return
                self._json(201, grant)
                return

            match = _SUBTITLES.fullmatch(route)
            if match:
                if self.headers.get("Content-Type") != "application/json":
                    self._json(415, {"error":"subtitle_json_required"})
                    return
                try:
                    source=json.loads(self._read(_MAX_CUES_JSON))
                    if not isinstance(source,dict):
                        raise ValueError("invalid_body")
                    receipt=sessions.set_subtitles(match.group(1),token,
                         source.get("cues"),source.get("film_duration_seconds"))
                except (ValueError,TypeError,SubtitleSessionError):
                    self._json(422, {"error":"subtitle_cues_rejected_or_grant_expired"})
                    return
                self._json(200,receipt)
                return

            match = _CLIP.fullmatch(route)
            if match:
                if self.headers.get("Content-Type") != "application/octet-stream":
                    self._json(415, {"error": "pcm_required"})
                    return
                try:
                    rate = self.headers.get("X-Audio-Sample-Rate")
                    channels = self.headers.get("X-Audio-Channels")
                    if rate != "16000" or channels != "1":
                        raise ValueError("unsupported_audio")
                    subtitle_seconds = float(self.headers.get("X-Subtitle-Seconds", "nan"))
                    audio_start = float(self.headers.get("X-Audio-Start-Seconds", "nan"))
                    # Reject non-finite numeric headers before any upload processing.
                    import math
                    if not math.isfinite(subtitle_seconds) or not math.isfinite(audio_start):
                        raise ValueError("invalid_timestamp")
                    pcm = self._read(_MAX_PCM)
                    receipt = sessions.upload(match.group(1), token, int(match.group(2)),
                                              pcm, subtitle_seconds, audio_start)
                except (ValueError, SubtitleSessionError):
                    self._json(422, {"error": "clip_rejected_or_grant_expired"})
                    return
                self._json(200, receipt)
                return

            match = _FINISH.fullmatch(route)
            if match:
                try:
                    if self._read(_MAX_JSON):
                        raise ValueError("unexpected_body")
                    report = sessions.finish(match.group(1), token)
                except (ValueError, SubtitleSessionError):
                    self._json(422, {"error": "finish_rejected_or_grant_expired"})
                    return
                # The UI never treats this as an automatic subtitle correction.
                self._json(200, report)
                return
            self._json(404, {"error": "not_found"})

        def do_GET(self):
            self._json(405, {"error": "method_not_allowed"})

    return CaptureHandler


def create_server(pairing_secret: str, port: int = 18731, sessions=None):
    # Refuse non-loopback binding by construction. The user must provision HTTPS.
    return ThreadingHTTPServer(("127.0.0.1", port),
                               make_handler(sessions or SubtitleSessions(), pairing_secret))


if __name__ == "__main__":
    secret = os.environ.get("CAPTURE_PAIRING_SECRET", "")
    port = int(os.environ.get("CAPTURE_LOOPBACK_PORT", "18731"))
    matcher = None
    if os.environ.get("CAPTURE_ASR_ENABLED") == "1":
        from audio_asr import OfflineClipTranscriber
        matcher = OfflineClipTranscriber(
            os.environ.get("CAPTURE_ASR_MODEL", "tiny"),
            os.environ.get("CAPTURE_ASR_CACHE_DIR"),
        )
    semantic=None
    if os.environ.get("CAPTURE_SEMANTIC_MODEL_DIR"):
        from semantic_matcher import MultilingualSemanticMatcher
        semantic=MultilingualSemanticMatcher(os.environ["CAPTURE_SEMANTIC_MODEL_DIR"])
    print("Starting isolated audio capture receiver on 127.0.0.1; HTTPS proxy required")
    with create_server(secret, port, sessions=SubtitleSessions(
            speech_matcher=matcher,semantic_matcher=semantic)) as server:
        server.serve_forever()
