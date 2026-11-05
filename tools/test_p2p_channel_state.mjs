import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const files=process.argv.slice(2);
for(const file of files.length ? files : ['ios/TogetherPoC/P2PTransport.html']) {
 const events=[],peers=[];
 class Peer {
  connectionState='new';localDescription=null;
  constructor(){peers.push(this)}
  createDataChannel(){return this.channel={readyState:'connecting',close(){this.readyState='closed'},send(){}}}
  async createOffer(){return {type:'offer',sdp:'synthetic'}}
  async setLocalDescription(value){this.localDescription=value}
  close(){this.connectionState='closed'}
 }
 const window={TogetherP2PAndroid:{postMessage(raw){events.push(JSON.parse(raw))}}};
 const html=fs.readFileSync(file,'utf8');
 vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],{window,RTCPeerConnection:Peer});
 await window.TogetherRTC.start({role:'host',peerId:'synthetic-peer'});
 const p=peers[0],channel=p.channel;
 const state=()=>events.filter(x=>x.event==='status').at(-1)?.state;
 channel.readyState='open';channel.onopen();assert.equal(state(),'open');
 p.connectionState='connected';p.onconnectionstatechange();
 assert.equal(state(),'open','late peer-connection connected must retain an open DataChannel');
 assert.equal(peers.length,1);
 p.connectionState='disconnected';p.onconnectionstatechange();assert.equal(state(),'disconnected');
 p.connectionState='connected';p.onconnectionstatechange();assert.equal(state(),'open');
 channel.readyState='closed';channel.onclose();assert.equal(state(),'closed');
 p.onconnectionstatechange();assert.notEqual(state(),'open','closed DataChannel must not be trusted from peer state alone');
 const stale=p.onconnectionstatechange;
 await window.TogetherRTC.start({role:'host',peerId:'replacement-peer'});
 const count=events.length;stale();assert.equal(events.length,count,'retired peer callbacks must be ignored');
 console.log(`${file}: channel ordering, fallback, recovery and stale-generation checks passed`);
}
