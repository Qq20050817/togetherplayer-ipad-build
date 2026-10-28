import http.client
import json
import threading
import unittest

from subtitle_capture_http import create_server


class AudioCaptureHTTPTests(unittest.TestCase):
    def setUp(self):
        self.secret = "test-audio-capture-pairing-secret-32-chars!"
        self.server = create_server(self.secret, 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.conn = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=5)
        self.prefix = "/v1/audio-capture/sessions"

    def tearDown(self):
        self.conn.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)

    def request(self, route, token, body=b"", headers=None):
        h = {"Authorization": "Bearer " + token, "Content-Length": str(len(body))}
        h.update(headers or {})
        self.conn.request("POST", route, body=body, headers=h)
        response = self.conn.getresponse()
        return response.status, json.loads(response.read().decode("utf-8"))

    def test_full_nine_clip_transfer_memory_only_one_time(self):
        status, grant = self.request(self.prefix, self.secret)
        self.assertEqual(status, 201)
        self.assertEqual(grant["required_samples"], 9)
        self.assertLessEqual(grant["expires_in_seconds"], 900)
        self.assertNotIn("pairing_secret", str(grant))
        pcm = b"\x01\x00" * (8 * 16000)
        for i in range(1, 10):
            for attempt in range(1, 4):
                status, receipt = self.request(
                    self.prefix + "/" + grant["job_id"] + "/clips/" + str(i),
                    grant["upload_grant"], pcm,
                    {"Content-Type": "application/octet-stream",
                     "X-Audio-Sample-Rate": "16000", "X-Audio-Channels": "1",
                     "X-Subtitle-Seconds": str(i * 50),
                     "X-Audio-Start-Seconds": str(i * 50)})
                self.assertEqual(status, 200)
                self.assertEqual(receipt["attempt"], attempt)
                self.assertEqual(receipt["status"],
                                 "retry_needed" if attempt < 3 else "received")
                self.assertEqual(receipt["count"], i-1 if attempt < 3 else i)
                self.assertFalse(receipt["audio_persisted"])
        status, report = self.request(
            self.prefix + "/" + grant["job_id"] + "/finish", grant["upload_grant"])
        self.assertEqual(status, 200)
        self.assertEqual(report["received"], 9)
        self.assertFalse(report["audio_persisted"])
        self.assertEqual(report["status"], "unavailable")  # no real ASR
        self.assertEqual(report["recognized_samples"], 0)
        self.assertEqual(len(report["retry_attempts"]), 9)
        status, _ = self.request(
            self.prefix + "/" + grant["job_id"] + "/finish", grant["upload_grant"])
        self.assertEqual(status, 422)

    def test_funnel_stripped_mount_prefix_supported(self):
        status, grant = self.request('/sessions', self.secret)
        self.assertEqual(status, 201)
        self.assertEqual(grant['required_samples'], 9)

    def test_invalid_pairing_and_grant_rejected(self):
        status, _ = self.request(self.prefix, "wrong")
        self.assertEqual(status, 401)
        status, grant = self.request(self.prefix, self.secret)
        self.assertEqual(status, 201)
        status, _ = self.request(self.prefix + "/" + grant["job_id"] + "/clips/1",
                                 "wrong", b"\x00" * (8 * 16000 * 2),
                                 {"Content-Type": "application/octet-stream",
                                  "X-Audio-Sample-Rate": "16000", "X-Audio-Channels": "1",
                                  "X-Subtitle-Seconds": "10",
                                  "X-Audio-Start-Seconds": "10"})
        self.assertEqual(status, 422)

    def test_subtitle_upload_auth_single_use_and_no_disk(self):
        status, grant = self.request(self.prefix, self.secret)
        self.assertEqual(status, 201)
        cues = [{"start": i*600.0, "end": i*600.0+4.0,
                 "text": "中文字幕内容%d" % i} for i in range(10)]
        body = json.dumps({"film_duration_seconds": 6500,
                           "cues": cues}, ensure_ascii=False).encode("utf-8")
        path = self.prefix + "/" + grant["job_id"] + "/subtitles"
        headers = {"Content-Type": "application/json"}
        status, _ = self.request(path, "unpaired", body, headers)
        self.assertEqual(status, 422)
        self.conn.close()
        self.conn = http.client.HTTPConnection("127.0.0.1",
                                               self.server.server_address[1], timeout=5)
        status, receipt = self.request(path, grant["upload_grant"], body, headers)
        self.assertEqual(status, 200)
        self.assertEqual(receipt["cue_count"], 10)
        self.assertFalse(receipt["subtitles_persisted"])
        self.assertNotIn("中文字幕内容", str(receipt))
        status, _ = self.request(path, grant["upload_grant"], body, headers)
        self.assertEqual(status, 422)

    def test_subtitle_upload_rejects_malformed_and_huge_cues(self):
        status, grant = self.request(self.prefix, self.secret)
        self.assertEqual(status, 201)
        route = self.prefix + "/" + grant["job_id"] + "/subtitles"
        headers = {"Content-Type": "application/json"}
        status, _ = self.request(route, grant["upload_grant"],
                                 b'{"cues":[],"film_duration_seconds":3600}', headers)
        self.assertEqual(status, 422)
        self.conn.close()
        self.conn = http.client.HTTPConnection("127.0.0.1",
                                               self.server.server_address[1], timeout=5)
        # Check early rejection using headers only: sending a huge body can
        # race the server closing the connection and yield BrokenPipe instead.
        self.conn.putrequest("POST", route)
        self.conn.putheader("Authorization", "Bearer " + grant["upload_grant"])
        self.conn.putheader("Content-Type", "application/json")
        self.conn.putheader("Content-Length", str(512 * 1024 + 1))
        self.conn.endheaders()
        response = self.conn.getresponse()
        self.assertEqual(response.status, 422)
        response.read()

    def test_invalid_or_oversized_payload_and_nonfinite_time(self):
        status, grant = self.request(self.prefix, self.secret)
        self.assertEqual(status, 201)
        path = self.prefix + "/" + grant["job_id"] + "/clips/1"
        required = {"Content-Type": "application/octet-stream",
                    "X-Audio-Sample-Rate": "16000", "X-Audio-Channels": "1",
                    "X-Subtitle-Seconds": "20", "X-Audio-Start-Seconds": "20"}
        status, _ = self.request(path, grant["upload_grant"],
                                 b"\x00" * (12 * 16000 * 2 + 2), required)
        self.assertEqual(status, 422)
        # Oversized body is rejected before being read; open a new connection.
        self.conn.close()
        self.conn = http.client.HTTPConnection("127.0.0.1",
                                                self.server.server_address[1], timeout=5)
        required["X-Audio-Start-Seconds"] = "NaN"
        status, _ = self.request(path, grant["upload_grant"],
                                 b"\x00" * (8 * 16000 * 2), required)
        self.assertEqual(status, 422)


if __name__ == "__main__":
    unittest.main()
