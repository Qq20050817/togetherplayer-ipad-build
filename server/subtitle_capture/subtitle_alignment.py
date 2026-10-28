"""Ordinary nine-anchor subtitle timing check, independent of Windows V7.

An anchor may be supplied only after real audio ASR and cross-language semantic
matching identify a particular subtitle dialogue cue. No ASR, no match, no
"verified" result. The API intentionally does not accept VAD-only timestamps.
"""
from dataclasses import dataclass
from math import isfinite, sqrt
from statistics import median


@dataclass(frozen=True)
class SpeechAnchor:
    sample_index: int
    subtitle_seconds: float
    matched_speech_seconds: float
    semantic_confidence: float


def verify_nine_anchors(anchors: list[SpeechAnchor]) -> dict:
    if len(anchors) != 9 or sorted(x.sample_index for x in anchors) != list(range(1,10)):
        return {'status':'unavailable','reason':'nine_real_speech_anchors_required'}
    if any(not all(isfinite(v) for v in (a.subtitle_seconds,a.matched_speech_seconds,
                                          a.semantic_confidence))
           or a.semantic_confidence < 0.75 or a.semantic_confidence > 1
           or a.subtitle_seconds < 0 or a.matched_speech_seconds < 0 for a in anchors):
        return {'status':'unavailable','reason':'unreliable_speech_or_translation'}
    xs = [a.subtitle_seconds for a in anchors]
    if max(xs)-min(xs) < 600:
        return {'status':'unavailable','reason':'samples_do_not_cover_film'}
    ys = [a.matched_speech_seconds-a.subtitle_seconds for a in anchors]
    midx = sum(xs)/9
    midy = sum(ys)/9
    variance = sum((x-midx)**2 for x in xs)
    slope = sum((x-midx)*(y-midy) for x,y in zip(xs,ys))/variance
    intercept = midy-slope*midx
    residual = sqrt(sum((y-(intercept+slope*x))**2 for x,y in zip(xs,ys))/9)
    # Consistency of each third matters: a single wrong edition may line up
    # around an opening but fail later, so never auto-correct that case.
    thirds = [median(ys[i:i+3]) for i in (0,3,6)]
    report = {'matched_anchors':9,'offset_at_start_seconds':round(intercept,3),
              'linear_drift_seconds_per_hour':round(slope*3600,3),
              'residual_seconds':round(residual,3),
              'segment_offsets_seconds':[round(v,3) for v in thirds],
              'minimum_semantic_confidence':round(min(x.semantic_confidence for x in anchors),3)}
    if residual > 1.1:
        return {'status':'version_might_differ','auto_correct':False,**report}
    if abs(slope*3600) >= 1.5:
        # Only gradual drift with low residual supports a linear correction.
        return {'status':'drift_detected','auto_correct':residual<0.45,**report}
    if abs(median(ys)) >= 0.65:
        return {'status':'offset_detected','auto_correct':residual<0.45,**report}
    return {'status':'verified','auto_correct':False,**report}


def corrected_srt_cue(start: float, end: float, report: dict) -> tuple[float,float]:
    """Apply only well-supported offset/linear drift to a single text cue."""
    if report.get('status') not in ('offset_detected','drift_detected') or not report.get('auto_correct'):
        raise ValueError('correction_not_verified')
    intercept=report['offset_at_start_seconds']
    slope=report['linear_drift_seconds_per_hour']/3600
    first=start+intercept+slope*start
    last=end+intercept+slope*end
    if not all(isfinite(t) for t in (first,last)) or first<0 or last<=first:
        raise ValueError('invalid_corrected_cue')
    return first,last


def verify_real_anchors(anchors: list[SpeechAnchor]) -> dict:
    """Conservative multi-section semantic verification, no false accuracy claim."""
    anchors=sorted(anchors,key=lambda a:a.sample_index)
    present={a.sample_index for a in anchors}
    base={'matched_anchors':len(anchors),'auto_correct':False,
          'score_kind':'evidence_reliability_not_absolute_accuracy'}
    if len(anchors)<7 or len(present)!=len(anchors) or any(
        sum(1 for x in present if (x-1)//3==part)<2 for part in range(3)):
        return {'status':'unavailable','reason':'insufficient_cross_language_anchors',**base}
    if any(not all(isfinite(v) for v in
        (a.subtitle_seconds,a.matched_speech_seconds,a.semantic_confidence))
        or a.subtitle_seconds<0 or a.matched_speech_seconds<0
        or isinstance(a.sample_index,bool) or a.sample_index not in range(1,10)
        or not 0.83<=a.semantic_confidence<=1 for a in anchors):
        return {'status':'unavailable','reason':'weak_semantic_evidence',**base}
    xs=[a.subtitle_seconds for a in anchors]
    ys=[a.matched_speech_seconds-a.subtitle_seconds for a in anchors]
    if max(xs)-min(xs)<600:
        return {'status':'unavailable','reason':'anchors_do_not_cover_film',**base}
    slopes=[(ys[j]-ys[i])/(xs[j]-xs[i])
            for i in range(len(xs)) for j in range(i+1,len(xs))
            if xs[j]-xs[i]>=180]
    if not slopes:
        return {'status':'unavailable','reason':'anchors_too_close',**base}
    slope=median(slopes)
    intercept=median([y-slope*x for x,y in zip(xs,ys)])
    inliers=[i for i,(x,y) in enumerate(zip(xs,ys))
             if abs(y-(intercept+slope*x))<=1.4]
    if len(inliers)<7 or any(sum(1 for i in inliers if
        (anchors[i].sample_index-1)//3==part)<2 for part in range(3)):
        return {'status':'version_might_differ',
                'reason':'timing_inconsistent_between_film_sections',**base}
    if len(inliers) != len(anchors):
        return {'status':'version_might_differ',
                'reason':'inconsistent_matched_anchors',
                'rejected_samples':[a.sample_index for i,a in enumerate(anchors) if i not in inliers],
                **base}
    x=[xs[i] for i in inliers];y=[ys[i] for i in inliers]
    xbar=sum(x)/len(x);ybar=sum(y)/len(y)
    var=sum((q-xbar)**2 for q in x)
    if var<=0:
        return {'status':'unavailable','reason':'anchors_too_close',**base}
    slope=sum((p-xbar)*(q-ybar) for p,q in zip(x,y))/var
    intercept=ybar-slope*xbar
    residual=sqrt(sum((q-intercept-slope*p)**2 for p,q in zip(x,y))/len(x))
    min_conf=min(anchors[i].semantic_confidence for i in inliers)
    reliability=int(max(0,min(99,round(100*len(inliers)/9*min_conf*
                                     max(0,1-min(residual,2)/3)))))
    base.update({'matched_anchors':len(inliers),
                 'offset_at_start_seconds':round(intercept,3),
                 'linear_drift_seconds_per_hour':round(slope*3600,3),
                 'residual_seconds':round(residual,3),
                 'minimum_semantic_confidence':round(min_conf,3),
                 'reliability_score':reliability,
                 'segment_offsets_seconds':[
                     round(median([ys[i] for i in inliers if
                           (anchors[i].sample_index-1)//3==part]),3)
                     for part in range(3)]})
    if residual>0.8:
        return {'status':'version_might_differ','reason':'timing_residual_too_high',**base}
    base['auto_correct']=len(inliers)>=8 and min_conf>=0.88 and residual<0.35
    if abs(slope*3600)>=1.5:
        return {'status':'drift_detected',**base}
    if abs(median(y))>=0.65:
        return {'status':'offset_detected',**base}
    return {'status':'verified','auto_correct':False,**base}

