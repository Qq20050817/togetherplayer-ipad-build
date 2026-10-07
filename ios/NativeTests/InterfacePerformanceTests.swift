import XCTest
import Combine
import UIKit
@testable import TogetherPoC

final class InterfacePerformanceTests: XCTestCase {
 @MainActor func testTypingAndFeedbackDoNotRefreshPlaybackController() {
  UserDefaults.standard.removeObject(forKey:"credentials")
  let model=TestClient()
  var controllerUpdates=0
  let subscription=model.objectWillChange.sink {controllerUpdates += 1}
  for index in 0..<1000 {model.chatDraft.text="输入测试 \(index) 👀"}
  model.status="位置与时钟更新"
  model.requestStatus="等待好友准备"
  XCTAssertEqual(controllerUpdates,0)
  XCTAssertEqual(model.chatDraft.text,"输入测试 999 👀")
  XCTAssertEqual(model.feedback.status,"位置与时钟更新")
  model.roomID="changed-room"
  XCTAssertEqual(controllerUpdates,1,"Room changes must still refresh the interface")
  withExtendedLifetime(subscription) {}
 }

 @MainActor func testRepeatedUpdatesKeepAnimationAndResizePreservesLifetime() throws {
  let view=DanmakuSurface(frame:CGRect(x:0,y:0,width:1024,height:180))
  var time=0.0
  view.now={time}
  let items=[DanmakuItem(id:1,text:"一起看 👀",lane:0,expiresAt:8000)]
  view.update(items:items,fontSize:24)
  let bubble=try XCTUnwrap(view.layer.sublayers?.first)
  let initial=try XCTUnwrap(bubble.animation(forKey:"travel") as? CABasicAnimation)
  XCTAssertEqual(initial.duration,8,accuracy:0.001)
  time=4000
  for _ in 0..<1000 {view.update(items:items,fontSize:24)}
  let unchanged=try XCTUnwrap(bubble.animation(forKey:"travel") as? CABasicAnimation)
  XCTAssertEqual(unchanged.beginTime,initial.beginTime)
  XCTAssertEqual(view.layer.sublayers?.count,1)
  view.frame=CGRect(x:0,y:0,width:2048,height:180)
  view.layoutSubviews()
  let resized=try XCTUnwrap(bubble.animation(forKey:"travel") as? CABasicAnimation)
  XCTAssertEqual(resized.duration,4,accuracy:0.001)
  let motion=DanmakuMotion(width:2048,textWidth:Double(bubble.bounds.width),expiresAt:8000,now:4000)
  XCTAssertEqual(try XCTUnwrap(resized.fromValue as? Double),motion.fromX,accuracy:0.001)
  time=6000
  view.update(items:items,fontSize:36)
  XCTAssertEqual(bubble.animation(forKey:"travel")?.duration ?? 0,2,accuracy:0.001)
  view.clear()
  XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true)
  XCTAssertNil(bubble.animation(forKey:"travel"))
 }
}
