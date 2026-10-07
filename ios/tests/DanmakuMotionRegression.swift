import Foundation
@main struct DanmakuMotionRegression {
 static func main() {
  let start=DanmakuMotion(width:1000,textWidth:200,expiresAt:8000,now:0)
  precondition(start.fromX == 1000 && start.toX == -200 && start.remaining == 8)
  let middle=DanmakuMotion(width:1000,textWidth:200,expiresAt:8000,now:4000)
  precondition(middle.fromX == 400 && middle.remaining == 4)
  let resized=DanmakuMotion(width:2000,textWidth:200,expiresAt:8000,now:4000)
  precondition(resized.fromX == 900 && resized.remaining == 4)
  let expired=DanmakuMotion(width:1000,textWidth:200,expiresAt:8000,now:9000)
  precondition(expired.fromX == -200 && expired.remaining == 0)
  print("Danmaku motion regression passed: absolute lifetime, resize and expiry")
 }
}
