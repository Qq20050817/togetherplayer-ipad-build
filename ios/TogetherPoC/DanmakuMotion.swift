import Foundation

struct DanmakuMotion {
 let fromX: Double
 let toX: Double
 let remaining: Double
 init(width: Double,textWidth: Double,expiresAt: Double,now: Double,durationSeconds:Double=8) {
  let duration=max(0.1,durationSeconds)
  remaining=max(0,min(duration,(expiresAt-now)/1000))
  toX = -textWidth
  fromX = -textWidth+(width+textWidth)*(remaining/duration)
 }
}
