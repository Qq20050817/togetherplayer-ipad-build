import XCTest
@testable import TogetherPoC

@MainActor final class WatchAIRecommendationTests:XCTestCase {
 private func memory()->WatchMemory {WatchMemory(defaults:UserDefaults(suiteName:"watch-ai-tests-"+UUID().uuidString)!,onlineEnabled:false)}
 private func response(_ input:String)throws->String {
  let root=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(input.utf8)) as? [String:Any])
  let candidate=try XCTUnwrap((root["candidates"] as? [[String:Any]])?.first)
  let record=try XCTUnwrap((root["history"] as? [[String:Any]])?.first)
  let object:[String:Any]=["recommendations":[["filmID":candidate["id"]!,"synopsis":"人物在事件中面对选择，围绕线索展开故事。","reason":"这部电影提供了相近的叙事体验。","connection":"根据你的已看记录尝试推荐，尚未评分不代表喜欢。","watchedIDs":[record["id"]!]]]]
  return String(data:try JSONSerialization.data(withJSONObject:object),encoding:.utf8)!
 }
 private func settle(_ ai:WatchChatGPTRecommendations) async throws {
  for _ in 0..<100 {try await Task.sleep(nanoseconds:10_000_000);if !ai.loading {return}}
  XCTFail("Inference should finish")
 }
 func testInputMinimizesDataAndUsesActualNotes()throws {
  let m=memory();m.record("罪人");m.feedback("guilty2018",rating:2,tags:["悬疑"],note:"不喜欢压抑，想看轻松一点")
  let candidates=WatchAIInput.candidates(records:m.records,catalog:m.catalog,dismissed:m.dismissed)
  let input=try XCTUnwrap(WatchAIInput.input(records:m.records,candidates:candidates))
  XCTAssertTrue(input.contains("想看轻松一点"));XCTAssertFalse(input.contains("sourceURL"));XCTAssertFalse(input.contains("http"))
  XCTAssertFalse(candidates.contains{$0.id=="guilty2018"})
  XCTAssertTrue(WatchAIInput.instructions.contains("null只表示看过"))
 }
 func testRejectsInventedFilmsReferencesAndDuplicates()throws {
  let m=memory();m.record("罪人")
  let films=WatchAIInput.candidates(records:m.records,catalog:m.catalog,dismissed:[])
  let input=try XCTUnwrap(WatchAIInput.input(records:m.records,candidates:films)),text=try response(input)
  XCTAssertNotNil(WatchAIInput.parse(text,records:m.records,candidates:films))
  XCTAssertNil(WatchAIInput.parse(text.replacingOccurrences(of:films[0].id,with:"made-up-film"),records:m.records,candidates:films))
  XCTAssertNil(WatchAIInput.parse(text.replacingOccurrences(of:"guilty2018",with:"invented-watch"),records:m.records,candidates:films))
  let parsed=try XCTUnwrap(WatchAIInput.parse(text,records:m.records,candidates:films))
  let duplicate=try JSONSerialization.data(withJSONObject:["recommendations":Array(repeating:["filmID":parsed[0].id,"synopsis":"一些影片信息","reason":"推荐这部影片","connection":"已有观影关联","watchedIDs":["guilty2018"]],count:2)])
  XCTAssertNil(WatchAIInput.parse(String(data:duplicate,encoding:.utf8)!,records:m.records,candidates:films))
 }
 func testGeneratedCacheSurvivesRelaunchAndDoesNotResend() async throws {
  let defaults=UserDefaults(suiteName:"watch-ai-cache-"+UUID().uuidString)!
  let m=WatchMemory(defaults:defaults,onlineEnabled:false);m.record("罪人");m.chatGPT.automatic=false;m.chatGPT.enabled=true
  var calls=0
  m.chatGPT.configure(allowed:{true},provider:{_,input,canSend in XCTAssertTrue(canSend());calls+=1;return (try self.response(input),"fixture-model")})
  m.chatGPT.refresh();try await settle(m.chatGPT)
  XCTAssertEqual(calls,1);XCTAssertEqual(m.chatGPT.cards.count,1)
  let restored=WatchMemory(defaults:defaults,onlineEnabled:false)
  restored.chatGPT.configure(allowed:{true},provider:{_,_,_ in calls+=1;throw CancellationError()})
  XCTAssertEqual(restored.chatGPT.cards.count,1)
  restored.chatGPT.refresh(force:false);try await settle(restored.chatGPT)
  XCTAssertEqual(calls,1);XCTAssertEqual(restored.chatGPT.batch?.model,"fixture-model")
 }
 func testConsentAndAccountGateBlockRequests() async throws {
  let m=memory();m.record("罪人");m.chatGPT.automatic=false
  var calls=0
  m.chatGPT.configure(allowed:{true},provider:{_,_,_ in calls+=1;return ("","")})
  m.chatGPT.refresh();try await settle(m.chatGPT);XCTAssertEqual(calls,0)
  m.chatGPT.enabled=true
  m.chatGPT.configure(allowed:{false},provider:{_,_,_ in calls+=1;return ("","")})
  m.chatGPT.refresh();try await settle(m.chatGPT);XCTAssertEqual(calls,0)
 }
 func testProfileChangeDiscardsInFlightResponseAndCache() async throws {
  let m=memory();m.record("罪人");m.chatGPT.automatic=false;m.chatGPT.enabled=true
  m.chatGPT.configure(allowed:{true},provider:{_,input,_ in
   try await Task.sleep(nanoseconds:100_000_000);return (try self.response(input),"fixture")
  })
  m.chatGPT.refresh();try await Task.sleep(nanoseconds:30_000_000)
  m.forget("guilty2018");try await Task.sleep(nanoseconds:160_000_000)
  XCTAssertNil(m.chatGPT.batch);XCTAssertTrue(m.chatGPT.cards.isEmpty)
 }
 func testFailureRetainsLastValidResultAndNoAutomaticRetry() async throws {
  let m=memory();m.record("罪人");m.chatGPT.automatic=false;m.chatGPT.enabled=true
  m.chatGPT.configure(allowed:{true},provider:{_,input,_ in (try self.response(input),"fixture")})
  m.chatGPT.refresh();try await settle(m.chatGPT)
  m.chatGPT.configure(allowed:{true},provider:{_,_,_ in throw NSError(domain:"offline",code:1)})
  m.chatGPT.refresh();try await settle(m.chatGPT)
  XCTAssertEqual(m.chatGPT.cards.count,1)
  XCTAssertTrue(m.chatGPT.status.contains("未自动重试"))
 }
}
