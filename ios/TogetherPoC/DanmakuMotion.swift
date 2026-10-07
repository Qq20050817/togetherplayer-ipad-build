import Foundation

struct DanmakuMotion {
 let fromX: Double
 let toX: Double
 let remaining: Double
 init(width: Double,textWidth: Double,expiresAt: Double,now: Double) {
  remaining=max(0,min(8,(expiresAt-now)/1000))
  toX = -textWidth
  fromX = -textWidth+(width+textWidth)*(remaining/8)
 }
}
