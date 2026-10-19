import XCTest
import SwiftUI
import UIKit
@testable import TogetherPoC

@MainActor final class PlaybackPresentationPerformanceTests:XCTestCase {
 func testChatTrafficDoesNotRebuildWatchOrMovieLayout() async throws {
  let model=TestClient(automaticallyConnect:false)
  let host=UIHostingController(rootView:WatchScreen(model:model,chat:model.chat))
  let window=UIWindow(frame:CGRect(x:0,y:0,width:1024,height:768))
  var renders:[String:Int]=[:]
  InterfaceRenderTrace.onRender={renders[$0,default:0]+=1}
  window.rootViewController=host;window.makeKeyAndVisible();host.view.layoutIfNeeded()
  defer {InterfaceRenderTrace.onRender=nil;window.isHidden=true;window.rootViewController=nil}
  try await Task.sleep(nanoseconds:300_000_000)
  XCTAssertGreaterThan(renders["watch",default:0],0,"the test must mount a real watch page")
  XCTAssertGreaterThan(renders["canvas",default:0],0,"the movie canvas must be rendered before measuring invalidation")
  renders.removeAll()
  for n in 1...30 {
   model.chat.accept(ChatMessage(id:Int64(n),userId:"peer",name:"好友",text:"一起看电影 \(n)",clientMessageId:"message-\(n)",timestamp:Double(n)),mine:false,live:true,now:Double(n)*100)
   model.chat.reaction("👀",now:Double(n)*100)
   model.chat.typing("好友",now:Double(n)*100)
  }
  model.chat.tick(100_000)
  try await Task.sleep(nanoseconds:200_000_000)
  XCTAssertEqual(model.chat.messages.count,30)
  XCTAssertTrue(model.chat.reactions.isEmpty)
  XCTAssertEqual(renders["watch",default:0],0,"chat/overlay traffic must not recreate the whole scrolling watch page")
  XCTAssertEqual(renders["canvas",default:0],0,"chat must not relayout the movie/subtitle canvas")
 }
 func testBackgroundCollectionSkipsEvidenceButExplicitCollectionRemainsAvailable() async {
  let defaults=UserDefaults(suiteName:UUID().uuidString)!
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let intelligence=PlotIntelligence(memory:PlotMemoryStore(directory:root),preferences:defaults)
  var scans=0
  intelligence.displayPosition={PlotDisplayPosition(key:"film",position:50)}
  intelligence.frame={scans+=1;return PlotFrame(key:"film",position:50,evidence:[])}
  intelligence.backgroundCollectionAllowed={false}
  for _ in 0..<100 {await intelligence.collect(inBackground:true)}
  intelligence.preserveCurrentFilmEvidence();intelligence.playbackJumped()
  XCTAssertEqual(scans,0,"offline banks and backgrounding must avoid legacy scans, even during seek/reconnect")
  await intelligence.collect()
  XCTAssertEqual(scans,1,"an explicit manual collection still works and doesn't rescan just to compare the film key")
  intelligence.backgroundCollectionAllowed={true}
  await intelligence.collect(inBackground:true)
  XCTAssertEqual(scans,2,"returning to legacy/manual mode resumes collection")
 }
}
