import XCTest
import SwiftUI
import UIKit
import AVFoundation
@testable import TogetherPoC

@MainActor final class PlaybackPresentationPerformanceTests:XCTestCase {
 func testChatTrafficDoesNotRebuildWatchOrMovieLayout() async throws {
  let model=TestClient(automaticallyConnect:false)
  let host=UIHostingController(rootView:WatchScreen(model:model,chat:model.chat))
  let previousKeyWindow=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.flatMap(\.windows).first{ $0.isKeyWindow }
  let window:UIWindow
  if let scene=previousKeyWindow?.windowScene {window=UIWindow(windowScene:scene)}
  else {window=UIWindow(frame:.zero)}
  window.frame=CGRect(x:0,y:0,width:1024,height:768)
  var renders:[String:Int]=[:]
  InterfaceRenderTrace.onRender={renders[$0,default:0]+=1}
  window.rootViewController=host;window.makeKeyAndVisible();host.view.layoutIfNeeded()
  defer {InterfaceRenderTrace.onRender=nil;window.isHidden=true;window.rootViewController=nil;previousKeyWindow?.makeKeyAndVisible()}
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
 func testOfflineBankAndBackgroundReleaseExtraPixelOutputWithoutChangingPreference() {
  let defaults=UserDefaults(suiteName:UUID().uuidString)!
  defaults.set(true,forKey:"plot-visual-ondevice-enabled")
  let player=AVPlayer(),item=AVPlayerItem(url:URL(fileURLWithPath:"/sampling-fixture.mp4"))
  player.replaceCurrentItem(with:item)
  let sampler=PlotVisualSampler(player:player,preferences:defaults)
  sampler.attach(to:item)
  XCTAssertTrue(item.outputs.contains{$0 is AVPlayerItemVideoOutput})
  sampler.setContextAllowsSampling(false)
  XCTAssertFalse(item.outputs.contains{$0 is AVPlayerItemVideoOutput})
  XCTAssertTrue(sampler.enabled);XCTAssertTrue(defaults.bool(forKey:"plot-visual-ondevice-enabled"))
  XCTAssertTrue(player.currentItem === item,"sampling must not replace or pause the movie")
  sampler.setContextAllowsSampling(true)
  XCTAssertTrue(item.outputs.contains{$0 is AVPlayerItemVideoOutput})
  sampler.setForeground(false)
  XCTAssertFalse(item.outputs.contains{$0 is AVPlayerItemVideoOutput})
  sampler.setForeground(true)
  XCTAssertTrue(item.outputs.contains{$0 is AVPlayerItemVideoOutput})
  sampler.enabled=false;sampler.setContextAllowsSampling(false);sampler.setContextAllowsSampling(true)
  XCTAssertFalse(item.outputs.contains{$0 is AVPlayerItemVideoOutput})
 }

}
