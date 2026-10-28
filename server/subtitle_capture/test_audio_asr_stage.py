"""Offline ASR contract tests; no model download or movie audio required."""
import http.client
import json
import threading
import unittest

from subtitle_capture_http import create_server
from subtitle_sessions import SubtitleSessions


class ASRReportTests(unittest.TestCase):
    def test_nine_clip_transcripts_never_auto_verify_subtitles(self):
        def fake_transcribe(index, _pcm, _subtitle_seconds, start_seconds):
            return {
                "sample_index": index, "audio_start_seconds": start_seconds,
                "language": "en", "language_probability": 0.99,
                "segments": [{"start_seconds": start_seconds + 1,
                              "end_seconds": start_seconds + 4,
                              "text": "Test phrase."}],
            }

        sessions = SubtitleSessions(speech_matcher=fake_transcribe)
        server = create_server("fake-test-token-longer-than-32-characters!", 0, sessions=sessions)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()

        def send(path, token, payload=b"", extra=None):
            conn = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
            headers = {"Authorization": "Bearer " + token,
                       "Content-Length": str(len(payload))}
            headers.update(extra or {})
            conn.request("POST", path, payload, headers)
            result = conn.getresponse()
            code, data = result.status, json.loads(result.read().decode("utf-8"))
            conn.close()
            return code, data

        try:
            secret = "fake-test-token-longer-than-32-characters!"
            code, grant = send("/sessions", secret)
            self.assertEqual(code, 201)
            prefix = "/sessions/" + grant["job_id"]
            clip_headers = {
                "Content-Type": "application/octet-stream",
                "X-Audio-Sample-Rate": "16000", "X-Audio-Channels": "1",
            }
            for index in range(1, 10):
                begin = float(index * 600)
                headers = {**clip_headers, "X-Subtitle-Seconds": str(begin),
                           "X-Audio-Start-Seconds": str(begin)}
                code, data = send(prefix + "/clips/" + str(index),
                                  grant["upload_grant"], b"\x01\x00" * (8 * 16000), headers)
                self.assertEqual(code, 200)
                self.assertEqual(data["count"], index)

            code, report = send(prefix + "/finish", grant["upload_grant"])
            self.assertEqual(code, 200)
            self.assertEqual(report["status"], "unavailable")
            self.assertEqual(report["reason"], "subtitle_cues_required_for_alignment")
            self.assertEqual(report["asr_status"], "complete")
            self.assertEqual(report["recognized_samples"], 9)
            self.assertEqual(report["recognized_indices"], list(range(1, 10)))
            self.assertFalse(report["auto_correct"])
            self.assertFalse(report["audio_persisted"])
            self.assertFalse(report["subtitles_persisted"])
            self.assertEqual(len(sessions._jobs), 0)
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=3)

    def test_partial_recognition_is_not_silently_verified(self):
        sessions = SubtitleSessions(speech_matcher=lambda index, pcm, sub, start: {
            "sample_index": index, "audio_start_seconds": start, "language": "ja",
            "language_probability": 0.9, "segments": [] if index==4 else [
                {"start_seconds": start, "end_seconds": start+1, "text": "example"}],
        })
        grant = sessions.start("paired-ipad")
        for i in range(1,10):
            for _ in range(3):
                receipt=sessions.upload(grant["job_id"], grant["upload_grant"], i,
                          b"\x00\x00" * (8 * 16000), i*500.0, i*500.0)
                if receipt["status"]=="received":
                    break
        report = sessions.finish(grant["job_id"], grant["upload_grant"])
        self.assertEqual(report["asr_status"], "partial")
        self.assertEqual(report["recognized_samples"], 8)
        self.assertFalse(report["auto_correct"])

    def test_asr_exception_does_not_interrupt_session(self):
        def broken_transcribe(*_args):
            raise RuntimeError("private media must never be logged")

        sessions = SubtitleSessions(speech_matcher=broken_transcribe)
        grant = sessions.start("paired-ipad")
        for i in range(1, 10):
            for _ in range(3):
                receipt=sessions.upload(grant["job_id"], grant["upload_grant"], i,
                                        b"\x00\x00"*(8*16000), i*500.0, i*500.0)
                self.assertFalse(receipt["audio_persisted"])
                if receipt["status"]=="received":
                    break
        report = sessions.finish(grant["job_id"], grant["upload_grant"])
        self.assertEqual(report["status"], "unavailable")
        self.assertEqual(report["recognized_samples"], 0)
        self.assertNotIn("private media", str(report))


if __name__ == "__main__":
    unittest.main()
