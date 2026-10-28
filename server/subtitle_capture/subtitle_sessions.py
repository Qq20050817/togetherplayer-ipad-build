"""Expiring memory-only nine-clip + candidate-subtitle session for ASR staging.

This code never saves film/audio/subtitle data. It requires a paired TLS
gateway and a one-time upload grant. Test listener is not production.
"""
from dataclasses import dataclass,field
from math import isfinite
import hmac
import secrets
import time

from subtitle_alignment import SpeechAnchor,verify_nine_anchors
from semantic_matcher import validate_cues


class SubtitleSessionError(Exception):
    pass


@dataclass
class _Session:
    owner: str
    token: str
    expires: float
    transcripts: dict[int,dict] = field(default_factory=dict)
    anchors: dict[int,SpeechAnchor] = field(default_factory=dict)
    received: set[int] = field(default_factory=set)
    attempts: dict[int,int] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    subtitle_cues: list[dict] = field(default_factory=list)
    duration: float = 0.0


class SubtitleSessions:
    def __init__(self,speech_matcher=None,semantic_matcher=None,clock=time.time):
        self._matcher=speech_matcher
        self._semantic=semantic_matcher
        self._clock=clock
        self._jobs={}
        self._reports={}

    def _prune(self):
        now=self._clock()
        self._jobs={k:v for k,v in self._jobs.items() if v.expires>now}
        self._reports={k:v for k,v in self._reports.items()
                       if v["finished_at"]+600>now}

    def _get(self,job_id,grant):
        self._prune()
        job=self._jobs.get(job_id)
        if not job or not isinstance(grant,str) or not hmac.compare_digest(job.token,grant):
            raise SubtitleSessionError("invalid_or_expired_grant")
        return job

    def start(self,authenticated_subject):
        self._prune()
        if not isinstance(authenticated_subject,str) or len(authenticated_subject)<3:
            raise SubtitleSessionError("authentication_required")
        jid=secrets.token_urlsafe(18)
        token=secrets.token_urlsafe(32)
        self._jobs[jid]=_Session(authenticated_subject,token,self._clock()+900)
        return {"job_id":jid,"upload_grant":token,
                "expires_in_seconds":900,"required_samples":9}

    def set_subtitles(self,job_id,grant,items,duration):
        job=self._get(job_id,grant)
        if job.received or job.subtitle_cues:
            raise SubtitleSessionError("subtitle_cues_already_set")
        if not isinstance(duration,(float,int)) or not isfinite(duration) or not 90<=duration<=21600:
            raise SubtitleSessionError("invalid_film_duration")
        parsed=validate_cues(items)
        if parsed[-1].start>duration+300:
            raise SubtitleSessionError("subtitle_exceeds_film")
        # Keep only normalized cues and timings in this expiring in-memory job.
        job.subtitle_cues=[{"start":x.start,"end":x.end,"text":x.text} for x in parsed]
        job.duration=float(duration)
        return {"status":"subtitles_received","cue_count":len(parsed),
                "subtitles_persisted":False}

    def upload(self,job_id,upload_grant,index,pcm16_mono_16khz,
               subtitle_seconds,actual_start_seconds):
        job=self._get(job_id,upload_grant)
        if index not in range(1,10) or index in job.received:
            raise SubtitleSessionError("sample_index_invalid_or_reused")
        if not isinstance(pcm16_mono_16khz,bytes) or not 8*32000<=len(pcm16_mono_16khz)<=12*32000:
            raise SubtitleSessionError("invalid_pcm_length")
        if not all(isfinite(v) for v in (subtitle_seconds,actual_start_seconds)):
            raise SubtitleSessionError("invalid_sample_timestamp")
        if not 0<=subtitle_seconds<=actual_start_seconds+120 or actual_start_seconds<0:
            raise SubtitleSessionError("invalid_sample_timestamp")
        attempt=job.attempts.get(index,0)+1
        if attempt>3:
            raise SubtitleSessionError("retry_limit_reached")
        job.attempts[index]=attempt
        recognized=False
        if self._matcher is not None:
            try:
                anchor=self._matcher(index,pcm16_mono_16khz,
                                     subtitle_seconds,actual_start_seconds)
            except Exception:
                anchor=None
                job.errors.append("sample_%d_asr_error_attempt_%d"%(index,attempt))
            if isinstance(anchor,SpeechAnchor) and anchor.sample_index==index:
                job.anchors[index]=anchor
                recognized=True
            elif (isinstance(anchor,dict) and anchor.get("sample_index")==index
                    and isinstance(anchor.get("segments"),list)
                    and len(anchor["segments"])<=24
                    and isinstance(anchor.get("language"),str)):
                job.transcripts[index]=anchor
                recognized=bool(anchor["segments"])
            else:
                job.errors.append("sample_%d_speech_unavailable_attempt_%d"%(index,attempt))
        else:
            job.errors.append("multilingual_asr_not_configured")
        # The server asks the iPad to sample a different dialogue window.
        # No audio is retained for retries. After three tries, the slot is
        # finalized as unrecognized rather than faking a 9/9 success.
        if not recognized and attempt<3:
            return {"status":"retry_needed","count":len(job.received),
                    "attempt":attempt,"audio_persisted":False}
        job.received.add(index)
        if not recognized:
            job.errors.append("sample_%d_no_reliable_speech"%index)
        return {"status":"received","count":len(job.received),
                "attempt":attempt,"recognized":recognized,
                "audio_persisted":False}

    def finish(self,job_id,upload_grant):
        job=self._get(job_id,upload_grant)
        if len(job.received)!=9:
            raise SubtitleSessionError("nine_samples_required")
        recognized=sum(bool(job.transcripts.get(i,{}).get("segments")) or i in job.anchors
                       for i in range(1,10))
        report={"asr_status":"complete" if recognized==9 else "partial",
                "recognized_samples":recognized,
                "recognized_indices":[i for i in range(1,10)
                                      if bool(job.transcripts.get(i,{}).get("segments")) or i in job.anchors],
                "retry_attempts":[{"sample_index":i,"attempts":job.attempts.get(i,0)}
                                  for i in range(1,10) if job.attempts.get(i,0)>1],
                "error_reasons":job.errors[-18:],
                "audio_persisted":False,"subtitles_persisted":False}
        if len(job.anchors)==9:
            report.update(verify_nine_anchors([job.anchors[i] for i in range(1,10)]))
        elif not job.subtitle_cues:
            report.update({"status":"unavailable",
                           "reason":"subtitle_cues_required_for_alignment",
                           "auto_correct":False})
        elif self._semantic is None:
            report.update({"status":"unavailable",
                           "reason":"offline_multilingual_semantics_unavailable",
                           "auto_correct":False})
        else:
            try:
                report.update(self._semantic.match(job.transcripts,job.subtitle_cues,job.duration))
            except Exception:
                report.update({"status":"unavailable",
                               "reason":"cross_language_match_failed",
                               "auto_correct":False})
        report["received"]=len(job.received)
        report["finished_at"]=self._clock()
        self._reports[job_id]=report
        del self._jobs[job_id]
        return report

    def report(self,job_id,authenticated_subject):
        raise SubtitleSessionError("report_oauth_ownership_not_implemented")
