"""Isolated in-memory cross-language sentence matching. No external inference."""
from dataclasses import dataclass
from math import isfinite
import re

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer


@dataclass(frozen=True)
class Cue:
    start: float
    end: float
    text: str


def validate_cues(items):
    if not isinstance(items,list) or not 9<=len(items)<=3500:
        raise ValueError("invalid_subtitle_cue_count")
    cues=[]
    for raw in items:
        if not isinstance(raw,dict):
            raise ValueError("invalid_cue")
        a,b,text=raw.get("start"),raw.get("end"),raw.get("text")
        if (isinstance(a,bool) or isinstance(b,bool) or
            not isinstance(a,(int,float)) or not isinstance(b,(int,float)) or
            not isfinite(a) or not isfinite(b) or a<0 or b<=a or b-a>40 or
            not isinstance(text,str) or len(text)>220):
            raise ValueError("invalid_cue")
        clean=" ".join(text.split())
        if clean:
            cues.append(Cue(float(a),float(b),clean))
    if len(cues)<9:
        raise ValueError("not_enough_cues")
    return sorted(cues,key=lambda c:c.start)


class MultilingualSemanticMatcher:
    def __init__(self,model_dir):
        options=ort.SessionOptions()
        options.intra_op_num_threads=1
        options.inter_op_num_threads=1
        self.model=ort.InferenceSession(model_dir+"/model_quantized.onnx",
            sess_options=options,providers=["CPUExecutionProvider"])
        self.tokenizer=Tokenizer.from_file(model_dir+"/tokenizer.json")
        self.tokenizer.enable_truncation(max_length=128)
        self.tokenizer.enable_padding()
        self.inputs={v.name for v in self.model.get_inputs()}

    def embed(self,texts):
        result=[]
        for offset in range(0,len(texts),20):
            encoded=self.tokenizer.encode_batch(texts[offset:offset+20])
            data={"input_ids":np.array([v.ids for v in encoded],dtype=np.int64),
                  "attention_mask":np.array([v.attention_mask for v in encoded],dtype=np.int64),
                  "token_type_ids":np.array([v.type_ids for v in encoded],dtype=np.int64)}
            hidden=self.model.run(None,{k:v for k,v in data.items() if k in self.inputs})[0]
            mask=data["attention_mask"][...,None]
            vec=(hidden*mask).sum(axis=1)/np.maximum(mask.sum(axis=1),1)
            vec/=np.maximum(np.linalg.norm(vec,axis=1,keepdims=True),1e-8)
            result.append(vec)
        return np.concatenate(result,axis=0) if result else np.empty((0,384))

    @staticmethod
    def meaningful(text):
        content="".join(c for c in text if c.isalnum())
        cjk=bool(re.search(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]",content))
        return len(content)>=(2 if cjk else 6)

    @staticmethod
    def windows(items):
        # Each item carries start, end, text, and original cue identity.
        out=[]
        for i in range(len(items)):
            for n in range(1,4):
                group=items[i:i+n]
                if len(group)!=n:break
                if any(b[0]-a[1]>2 or b[0]<a[0] for a,b in zip(group,group[1:])):break
                text=" ".join(x[2] for x in group)
                if group[-1][1]-group[0][0]>18 or len(text)>180:break
                out.append((group[0][0],group[-1][1],text,
                            frozenset(x[3] for x in group)))
        return out

    def match(self,transcripts,items,duration):
        from subtitle_alignment import SpeechAnchor,verify_real_anchors
        if isinstance(duration,bool) or not isinstance(duration,(int,float)) or not isfinite(duration) or not 90<=duration<=21600:
            raise ValueError("invalid_film_duration")
        cues=validate_cues(items)
        # Form windows before filtering so a short phrase can join its context.
        candidates=[c for c in self.windows([(c.start,c.end,c.text,i) for i,c in enumerate(cues)])
                    if self.meaningful(c[2])]
        if not candidates:
            return {"status":"unavailable","reason":"not_enough_text","matched_anchors":0,"auto_correct":False}
        vectors=self.embed([c[2] for c in candidates])
        anchors=[];matches=[];issues=[];used_cues=set()
        for index in range(1,10):
            transcript=transcripts.get(index)
            if not isinstance(transcript,dict):
                issues.append({"sample_index":index,"reason":"no_transcript"});continue
            lines=[]
            for j,raw in enumerate(transcript.get("segments",[])[:6]):
                text=raw.get("text","").strip();pos=raw.get("start_seconds")
                end=raw.get("end_seconds",pos)
                if (not isinstance(pos,bool) and isinstance(pos,(int,float)) and isfinite(pos)
                    and isinstance(end,(int,float)) and isfinite(end) and end>=pos and text):
                    lines.append((float(pos),float(end),text[:180],j))
            windows=[c for c in self.windows(lines) if self.meaningful(c[2])]
            if not windows:
                issues.append({"sample_index":index,"reason":"no_reliable_dialogue"});continue
            embeddings=self.embed([c[2] for c in windows]);best=None;ambiguous=False
            for spoken,embedding in zip(windows,embeddings):
                scores=vectors@embedding
                ranked=sorted((i for i,c in enumerate(candidates) if abs(c[0]-spoken[0])<=600),
                              key=lambda i:float(scores[i]),reverse=True)
                if not ranked:continue
                winner=ranked[0];cue=candidates[winner];similarity=float(scores[winner])
                # Overlapping windows are alternative segmentation of the same
                # evidence. Other occurrences of repeated dialogue still compete.
                second=max((float(score) for j,score in enumerate(scores)
                            if not candidates[j][3].intersection(cue[3])),default=-1)
                margin=similarity-second
                if similarity<0.83:continue
                if margin<0.055:
                    ambiguous=True;continue
                if best is None or similarity>best[0]:best=(similarity,margin,spoken,cue)
            if best is None:
                issues.append({"sample_index":index,"reason":"ambiguous_subtitle_match" if ambiguous else "low_semantic_similarity"});continue
            similarity,margin,spoken,cue=best
            if cue[3].intersection(used_cues):
                issues.append({"sample_index":index,"reason":"subtitle_cue_reused"});continue
            if spoken[0]<0 or spoken[0]>duration or cue[0]>duration:
                issues.append({"sample_index":index,"reason":"anchor_outside_film"});continue
            used_cues.update(cue[3]);anchors.append(SpeechAnchor(index,cue[0],spoken[0],similarity))
            matches.append({"sample_index":index,"subtitle_seconds":round(cue[0],3),
                "speech_seconds":round(spoken[0],3),"semantic_similarity":round(similarity,3),
                "uniqueness_margin":round(margin,3),"subtitle_cue_count":len(cue[3]),
                "speech_segment_count":len(spoken[3])})
        result=verify_real_anchors(anchors)
        if result["status"] in ("verified","offset_detected","drift_detected"):
            positions=[a.matched_speech_seconds for a in anchors]
            if (min(positions)>duration/3 or max(positions)<duration*2/3
                    or max(positions)-min(positions)<duration*0.6):
                result.update(status="unavailable",reason="anchors_do_not_cover_film",auto_correct=False)
        result["unmatched_samples"]=issues
        result["matched_samples"]=[x["sample_index"] for x in matches]
        result["sample_matches"]=matches
        return result
