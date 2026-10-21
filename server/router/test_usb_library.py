"""Regression tests for unsigned USB media serving and traversal protections."""
import io
from pathlib import Path
import tempfile
import unittest
from urllib.parse import quote
import usb_library
from media_server import byte_range

class Response:
    def __init__(self, headers=None):
        self.headers = headers or {}
        self.status = None
        self.headers_out = {}
        self.wfile = io.BytesIO()

    def send_response(self, code):
        self.status = code

    def send_header(self, key, value):
        self.headers_out[key] = value

    def end_headers(self):
        pass

    def empty(self, status, extra=None):
        self.status = status
        self.headers_out.update(extra or {})

class USBMediaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.movies = self.base / "电影"
        folder = self.movies / "片源"
        folder.mkdir(parents=True)
        self.file = folder / "测试影片.mkv"
        self.file.write_bytes(b"0123456789ABCDEF")
        (folder / "测试影片.zh.srt").write_bytes(b"subtitle text")
        (folder / "another.srt").write_bytes(b"unrelated")
        (self.base / ".volume-identity").write_text("test")
        self.config = {"root": str(self.base), "uuid": "test"}
        self.url = "/usb-files/" + quote("片源/测试影片.mkv")

    def request(self, url, headers=None):
        from urllib.parse import urlsplit
        parts = urlsplit(url)
        out = Response(headers)
        claimed = usb_library.handle(out, parts.path, parts.query, True, self.config, byte_range)
        self.assertTrue(claimed)
        return out

    def test_catalog_and_non_expiring_address(self):
        import json
        result = self.request("/usb-library.json")
        self.assertEqual(result.status, 200)
        movie = json.loads(result.wfile.getvalue())["items"][0]
        self.assertEqual(movie["name"], "测试影片.mkv")
        self.assertNotIn("?", movie["url"])

    def test_byte_ranges(self):
        result = self.request(self.url, {"Range": "bytes=2-5"})
        self.assertEqual(result.status, 206)
        self.assertEqual(result.wfile.getvalue(), b"2345")
        self.assertEqual(result.headers_out["Content-Range"], "bytes 2-5/16")
        self.assertEqual(self.request(self.url).wfile.getvalue(), self.file.read_bytes())

    def test_subtitles(self):
        import json
        result = self.request(self.url + "?subtitles=1")
        self.assertEqual(result.status, 200)
        tracks = json.loads(result.wfile.getvalue())["subtitles"]
        self.assertEqual([t["name"] for t in tracks], ["测试影片.zh.srt"])
        self.assertEqual(self.request(tracks[0]["url"]).wfile.getvalue(), b"subtitle text")

    def test_traversal_and_other_files(self):
        self.assertEqual(self.request("/usb-files/../secret.mkv").status, 404)
        self.assertEqual(self.request("/usb-files/%2E%2E/secret.mkv").status, 404)
        self.assertEqual(self.request("/usb-files/片源/private.txt").status, 404)
        self.assertEqual(self.request(self.url + "?key=anything").status, 404)
        self.assertEqual(self.request("/usb-files/片源/not-found.mp4").status, 404)
        target = self.base / "other.mkv"
        target.write_bytes(b"private")
        (self.movies / "链接.mkv").symlink_to(target)
        self.assertEqual(self.request("/usb-files/" + quote("链接.mkv")).status, 404)

if __name__ == "__main__":
    unittest.main()
