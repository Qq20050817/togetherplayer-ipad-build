#!/usr/bin/env python3
"""Summarize device telemetry. No input => no invented measurements.
Canonical error is each client's distance from the server timeline.
Pair error uses interpolation only between same-version playing, ready samples.
"""
import argparse, bisect, collections, json, math, statistics
p=argparse.ArgumentParser();p.add_argument('telemetry');p.add_argument('--room',required=True);a=p.parse_args()
samples=collections.defaultdict(list);controls=[];segments=collections.defaultdict(int)
for line in open(a.telemetry):
    item=json.loads(line)
    if item.get('roomId')!=a.room: continue
    if item.get('kind')=='control': controls.append(item); continue
    d=item.get('data',{})
    if not isinstance(d,dict): continue
    if d.get('diagnostic'): continue
    uid=item['userId']
    if not isinstance(d.get('serverTimeMs'),(float,int)):
        segments[uid]+=1
        continue
    d=dict(d);d['positionMs']=d.get('positionMs',0)-d.get('timelineOffsetMs',0);d['t']=d['serverTimeMs'];d['segment']=segments[uid];samples[uid].append(d)
for group in samples.values(): group.sort(key=lambda x:x['t'])
def good(d):
    return d.get('ready') and not d.get('buffering') and isinstance(d.get('errorMs'),(int,float))
errors=[abs(d['errorMs']) for group in samples.values() for d in group if good(d)]
rtts=[d['rttMs'] for group in samples.values() for d in group if isinstance(d.get('rttMs'),(int,float))]
pairs=[]
execute_times={c['room']['version']:c['room']['executeAt'] for c in controls}
if len(samples)==2:
    first,second=samples.values();times=[d['t'] for d in second]
    for d in first:
        i=bisect.bisect_left(times,d['t'])
        if not good(d) or not d.get('playing') or i==0 or i==len(second): continue
        left,right=second[i-1],second[i]
        if not all(good(v) and v.get('playing') and v.get('version')==d.get('version') for v in (left,right)): continue
        if right['t']-left['t']>2500 or right['t']==left['t']: continue
        if left['segment']!=right['segment']: continue
        # A version is received BEFORE executeAt. Never interpolate across the
        # scheduled Seek, or across a later automatic hard resynchronization.
        at=max(execute_times.get(d.get('version'),-math.inf),d.get('executeAtMs',-math.inf),left.get('executeAtMs',-math.inf),right.get('executeAtMs',-math.inf))
        if left.get('timelineOffsetMs',0)!=right.get('timelineOffsetMs',0):continue
        if min(d['t'],left['t'])<at: continue
        delta=right['positionMs']-left['positionMs'];elapsed=right['t']-left['t']
        if delta<0 or abs(delta-elapsed)>0.1*elapsed+200: continue
        position=left['positionMs']+(right['positionMs']-left['positionMs'])*(d['t']-left['t'])/(right['t']-left['t'])
        pairs.append((d['t'],abs(d['positionMs']-position),d['version']))
recoveries=[]
for c in controls:
    if c['type']!='SEEK': continue
    version=c['room']['version'];at=c['room']['executeAt']
    # First sustained 2-second window of device pairs below 500 ms in this version.
    window=[]
    recovered=None
    for t,error,v in pairs:
        if v!=version or t<at: continue
        if error>=500: window=[];continue
        if window and t-window[-1]>2500:window=[]
        window.append(t)
        if t-window[0]>=2000:recovered=window[0]-at;break
    recoveries.append({'version':version,'recoveryMs':recovered})
def mean(v):return statistics.mean(v) if v else None
alltimes=[d['t'] for g in samples.values() for d in g]
span=(max(alltimes)-min(alltimes))/1000 if alltimes else 0
playing_seconds={uid:sum((b['t']-a['t'])/1000 for a,b in zip(group,group[1:])
    if good(a) and good(b) and a.get('playing') and b.get('playing')
    and a['segment']==b['segment'] and 0<b['t']-a['t']<=2500)
    for uid,group in samples.items()}
result={'kind':'device_telemetry','roomId':a.room,'users':list(samples),'observedSeconds':span,
 'estimatedReadyPlayingSecondsByUser':playing_seconds,
 'meanCanonicalErrorMs':mean(errors),'maxCanonicalErrorMs':max(errors,default=None),
 'meanInterpolatedPairErrorMs':mean([v[1] for v in pairs]),'maxInterpolatedPairErrorMs':max([v[1] for v in pairs],default=None),
 'pairSamples':len(pairs),'pairBelow500Percent':100*sum(v[1]<500 for v in pairs)/len(pairs) if pairs else None,
 'meanWebSocketRttMs':mean(rtts),'maxWebSocketRttMs':max(rtts,default=None),
 'seekRecoveries':recoveries,'finalPairErrorMs':pairs[-1][1] if pairs else None,
 'hasThirtyMinuteTelemetry':span>=1800,
 'note':'Interpolated pair estimates require two foreground devices and same-version READY samples; inspect raw traces for buffer/seek gaps. Span alone does not certify continuous playback.'}
print(json.dumps(result,ensure_ascii=False,indent=2))
