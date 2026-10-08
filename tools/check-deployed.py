#!/usr/bin/env python3
"""Protocol smoke test against an existing backend; creates a two-member test room.
Requires websocket-client. Does not decode media or certify device synchrony.
"""
import argparse,json,statistics,time,urllib.request
import websocket
p=argparse.ArgumentParser();p.add_argument('--server',required=True);p.add_argument('--media',required=True);p.add_argument('--output',required=True);a=p.parse_args()
base=a.server.rstrip('/')
def post(path,body):
 q=urllib.request.Request(base+path,data=json.dumps(body).encode(),headers={'Content-Type':'application/json'},method='POST')
 with urllib.request.urlopen(q,timeout=15) as r:return json.load(r)
def connect(auth):
 return websocket.create_connection(base.replace('http','ws',1)+'/ws',header=['Authorization: Bearer '+auth['token']],timeout=10,suppress_origin=True)
def receive(c):return json.loads(c.recv())
host=post('/rooms',{'mediaUrl':a.media});guest=post('/rooms/'+host['roomId']+'/join',{})
h,g=connect(host),connect(guest)
assert receive(h)['type']=='WELCOME';assert receive(g)['type']=='WELCOME'
rtts=[]
for _ in range(50):
 start=time.monotonic();h.send(json.dumps({'type':'PING','t1':start*1000}));pong=receive(h);assert pong['type']=='PONG';rtts.append((time.monotonic()-start)*1000)
version=1;broadcast=[]
for sequence in range(1,31):
 kind=['PLAY','PAUSE','SEEK'][(sequence-1)%3]
 start=time.monotonic();h.send(json.dumps({'type':kind,'sequence':sequence,'baseVersion':version,'position':120000}));state=receive(h);other=receive(g)
 assert state['type']=='STATE' and other['type']=='STATE';version=state['room']['version'];assert version==sequence+1;assert other['room']['version']==version
 broadcast.append((time.monotonic()-start)*1000)
g.close();g=connect(guest);welcome=receive(g);assert welcome['room']['version']==version
h.close();g.close()
result={'kind':'deployed_server_protocol_test','server':base,'roomId':host['roomId'],'pingSamples':len(rtts),'meanRttMs':statistics.mean(rtts),'maxRttMs':max(rtts),'controls':30,'meanBroadcastMs':statistics.mean(broadcast),'reconnectRestored':True,'videoDecoded':False,'note':'No device playback; local address means Muse loopback, not public or mobile latency.'}
with open(a.output,'w') as f:json.dump(result,f,indent=2)
print(json.dumps(result,indent=2))
