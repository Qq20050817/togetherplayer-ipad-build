"""Optional offline, CPU-only transcription of nine short movie audio clips.

Only enabled in the separate Singapore test receiver with CAPTURE_ASR_ENABLED=1.
Audio is read as PCM16LE mono 16 kHz, never saved to disk. Speech recognition
does not establish a subtitle match without actual candidate subtitle cues.
"""
import math
import os
import threading


class OfflineClipTranscriber:
    def __init__(self, model_name="tiny", cache_dir=None, beam_size=1):
        import numpy
        from faster_whisper import WhisperModel

        self._task=os.environ.get("CAPTURE_ASR_TASK","transcribe")
        if self._task not in ("transcribe","translate"):raise ValueError("invalid_asr_task")
        self._beam_size=beam_size
        self._numpy = numpy
        self._lock = threading.Lock()
        self._model = WhisperModel(
            model_name,
            device="cpu",
            compute_type="int8",
            cpu_threads=1,
            num_workers=1,
            download_root=cache_dir,
            local_files_only=True,
        )

    def __call__(self, index, pcm16_mono_16khz, subtitle_seconds, actual_start_seconds):
        if not 8 * 32000 <= len(pcm16_mono_16khz) <= 12 * 32000:
            raise ValueError("invalid_pcm_length")
        if not math.isfinite(actual_start_seconds) or actual_start_seconds < 0:
            raise ValueError("invalid_audio_start")

        audio = self._numpy.frombuffer(pcm16_mono_16khz, dtype="<i2").astype(self._numpy.float32)
        audio /= 32768.0
        with self._lock:
            segments, info = self._model.transcribe(
                audio,
                beam_size=self._beam_size,
                task=self._task,
                vad_filter=True,
                condition_on_previous_text=False,
            )
            recognized = list(segments)

        cues = []
        remaining_chars = 270  # nine-clip finish report stays below the iPad 16 KB limit
        for segment in recognized[:6]:
            words = segment.text.strip()[:min(180, remaining_chars)]
            first = max(0.0, actual_start_seconds + float(segment.start))
            last = actual_start_seconds + float(segment.end)
            if not words or not math.isfinite(first) or not math.isfinite(last):
                continue
            if last <= first or last > actual_start_seconds + 12.5:
                continue
            cues.append({
                "start_seconds": round(first, 3),
                "end_seconds": round(last, 3),
                "text": words,
            })
            remaining_chars -= len(words)
            if remaining_chars <= 0:
                break
        return {
            "sample_index": index,
            "audio_start_seconds": actual_start_seconds,
            "language": str(info.language)[:16],
            "language_probability": round(float(info.language_probability), 3),
            "segments": cues,
        }
