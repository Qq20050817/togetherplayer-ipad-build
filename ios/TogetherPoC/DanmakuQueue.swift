import Foundation

struct DanmakuItem: Identifiable, Equatable {
 let id: Int64
 let text: String
 let lane: Int
 let expiresAt: Double
 var durationMs: Double=10000
}
struct DanmakuQueue {
 private(set) var active: [DanmakuItem]=[]
 private var pending: [(Int64,String,Double,Double)]=[]
 mutating func reset() {active=[];pending=[]}
 mutating func enqueue(id: Int64,text: String,now: Double,durationMs: Double=10000) {
  pending.append((id,String(text.prefix(durationMs<=5000 ? 500 : 120)),now+30000,durationMs))
  if pending.count>20 {pending.removeFirst(pending.count-20)}
  advance(now)
 }
 mutating func advance(_ now: Double) {
  active.removeAll {$0.expiresAt<=now}
  pending.removeAll {$0.2<=now}
  for lane in 0..<3 where !active.contains(where:{$0.lane==lane}) {
   guard !pending.isEmpty else {break}
   let next=pending.removeFirst()
   active.append(DanmakuItem(id:next.0,text:next.1,lane:lane,expiresAt:now+next.3,durationMs:next.3))
  }
 }
}
