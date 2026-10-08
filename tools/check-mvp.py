#!/usr/bin/env python3
"""Real HTTP/WS MVP protocol regression. No media decoding or mobile benchmark."""
import argparse,json,time,urllib.request,urllib.error
import websocket
p=argparse.ArgumentParser();p.add_argument('--server',required=True);p.add_argument('--output',required=True);a=p.parse_args();base=a.server.rstrip('/')
def post(path,data):
 q=urllib.request.Request(base+path,json.dumps(data).encode(),{'Content-Type':'application/json'})
 with urllib.request.urlopen(q,timeout=10) as r:return json.load(r)
def dial(auth):return websocket.create_connection(base.replace('http','ws',1)+'/ws',header=['Authorization: Bearer '+auth['token']],suppress_origin=True,timeout=7,http_no_proxy=['127.0.0.1','localhost'])
def send(c,kind,**data):c.send(json.dumps(dict(type=kind,**data),ensure_ascii=False))
def until(c,predicate):
 end=time.monotonic()+8
 while time.monotonic()<end:
  o=json.loads(c.recv())
  if predicate(o):return o
 raise AssertionError('expected event missing')
def event(c,kind):return until(c,lambda o:o.get('type')==kind)
host=post('/rooms',{'mediaUrl':'https://example.com/licensed.mp4','title':'同步测试'});guest=post('/rooms/'+host['roomId']+'/join',{})
try:post('/rooms/'+host['roomId']+'/join',{});raise AssertionError('third member accepted')
except urllib.error.HTTPError as e:assert e.code==409
h=g=None
try:
 h=dial(host);g=dial(guest);welcome=event(h,'WELCOME');event(g,'WELCOME');assert welcome['room']['waitForPeer']
 send(g,'PROFILE_UPDATE',data={'name':'好友','timelineOffset':8000});assert any(m['timelineOffset']==8000 for m in event(h,'PRESENCE')['members'])
 for auth,c,duration in [(host,h,600000),(guest,g,608000)]:send(c,'PLAYER_STATUS',data={'ready':True,'buffering':False,'position':0,'duration':duration})
 send(h,'SYNC');r=event(h,'SYNC')['room'];assert r['duration']==600000
 def control(kind,seq,**kw):
  send(h,kind,sequence=seq,baseVersion=r['version'],**kw)
  return until(h,lambda o:o.get('ackUserId')==host['userId'] and o.get('ackSequence')==seq)['room']
 r=control('PLAY',1,position=0);assert r['state']=='playing'
 send(g,'CHAT_MESSAGE',data={'text':'😂'*1000,'clientMessageId':'long1'});one=event(h,'CHAT_MESSAGE')['message'];assert len(one['text'])==1000
 send(g,'CHAT_MESSAGE',data={'text':'😂'*1000,'clientMessageId':'long1'});assert event(h,'CHAT_MESSAGE')['message']['id']==one['id']
 send(g,'CHAT_MESSAGE',data={'text':'😱'*1000,'clientMessageId':'long2'});event(h,'CHAT_MESSAGE')
 send(g,'REACTION',data={'emoji':'❤️'});assert event(h,'REACTION')['emoji']=='❤️'
 send(g,'CHAT_TYPING');assert event(h,'CHAT_TYPING')['name']=='好友'
 send(g,'PLAYER_STATUS',data={'ready':False,'buffering':True,'position':0,'duration':608000})
 time.sleep(4.0)
 send(h,'SYNC');r=event(h,'SYNC')['room'];assert r['state']=='paused' and r['autoResume'] and r['pauseReason']=='buffering'
 for c,d in [(h,600000),(g,608000)]:send(c,'PLAYER_STATUS',data={'ready':True,'buffering':False,'position':0,'duration':d})
 r=until(h,lambda o:o.get('type')=='STATE' and o.get('room',{}).get('state')=='playing' and o['room']['version']>r['version'])['room']
 assert not r.get('autoResume')
 r=control('PAUSE',2,position=0);r=control('SEEK',3,position=120000);assert r['position']==120000
 g.close();g=dial(guest);w=event(g,'WELCOME');assert w['room']['version']==r['version'];assert len(json.dumps(w,ensure_ascii=False).encode())<=8192 and w['messages'][-1]['clientMessageId']=='long2'
 r=control('ROOM_MEDIA',4,data={'mediaUrl':'https://example.com/new.m3u8','title':'下一部'});assert r['title']=='下一部' and r['state']=='paused' and r['position']==0
 send(h,'ROOM_CLOSE');event(h,'ROOM_CLOSE');event(g,'ROOM_CLOSE')
 try:
  c=dial(guest);c.close();raise AssertionError('closed token still valid')
 except websocket.WebSocketBadStatusException as e:assert e.status_code==401
 result={'kind':'mvp_http_websocket_regression','server':base,'passed':True,'checks':['two-person limit','timeline offset','canonical duration','host acknowledgement','chat deduplication','long UTF-8 history frame cap','emoji','typing','buffer pause and scheduled resume','manual pause/seek','reconnect','source change','room close and token revocation'],'videoDecoded':False,'hardwareAcceptance':False}
 with open(a.output,'w') as f:json.dump(result,f,ensure_ascii=False,indent=2)
 print(json.dumps(result,ensure_ascii=False,indent=2))
finally:
 for c in (h,g):
  if c:c.close()
