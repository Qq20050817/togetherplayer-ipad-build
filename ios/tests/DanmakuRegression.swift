import Foundation

@main struct DanmakuRegression {
 static func main() {
  var queue=DanmakuQueue()
  for id in 1...5 {queue.enqueue(id:Int64(id),text:"message \(id)",now:1000)}
  precondition(queue.active.count==3 && Set(queue.active.map(\.lane)).count==3)
  queue.advance(8999)
  precondition(queue.active.map(\.id)==[1,2,3])
  queue.advance(9000)
  precondition(queue.active.map(\.id)==[4,5])
  queue.advance(17000)
  precondition(queue.active.isEmpty)
  queue.enqueue(id:6,text:String(repeating:"字",count:1000),now:20000)
  precondition(queue.active[0].text.count==120)
  queue.reset();precondition(queue.active.isEmpty)
  for id in 10...50 {queue.enqueue(id:Int64(id),text:"burst",now:30000)}
  queue.advance(70000);precondition(queue.active.isEmpty)
  print("PASS: three independent danmaku lanes, bounded queue, expiry, text limit and room reset")
 }
}
