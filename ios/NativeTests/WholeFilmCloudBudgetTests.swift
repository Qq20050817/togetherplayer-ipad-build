import XCTest
@testable import TogetherPoC

@MainActor final class WholeFilmCloudBudgetTests:XCTestCase {
 private func document(_ count:Int=449)->SubtitleDocument {
  SubtitleDocument((0..<count).map{SubtitleCue(start:Double($0*5),end:Double($0*5+3),text:"第\($0)条：守门人否认自己移动过银色钥匙。")})
 }
 private func batchAnswer(_ input:String)throws->String {
  let marker="完整字幕分段："
  let range=try XCTUnwrap(input.range(of:marker))
  let values=try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(input[range.upperBound...].utf8)) as? [[String:Any]])
  let result=try values.map {value -> WholeFilmSection in
   let index=try XCTUnwrap(value["index"] as? Int)
   let evidence=try XCTUnwrap(value["evidence"] as? [[String:Any]])
   let ids=try evidence.prefix(2).map{try XCTUnwrap($0["id"] as? String)}
   return WholeFilmSection(index:index,summary:"守门人的解释与此前说法存在矛盾，银色钥匙的去向仍然需要核对。",evidenceIDs:ids)
  }
  return "{\"sections\":"+WholeFilmPlan.json(result)+"}"
 }
 private func mapAnswer(_ input:String)throws->String {
  let values=try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(input.utf8)) as? [[String:Any]])
  let ids=values.flatMap{($0["evidenceIDs"] as? [String]) ?? []}
  return WholeFilmPlan.json(WholeFilmMap(synopsis:"完整故事中，守门人围绕银色钥匙的多次解释存在联系，最终相关说法仍需以对白证据核对。",threads:[],evidenceIDs:ids))
 }
 func test449CuesAreAllAnalyzedWithAtMostSixCloudCalls() async throws {
  let host=WholeFilmHost(archive:WholeFilmArchive(directory:nil));host.available={true};host.cloudBatching={true}
  var calls=0,inputs="";var estimates:[Int]=[]
  host.cloudPreflight={estimates.append($0)}
  host.inference={ [self] instruction,input in
   calls+=1;inputs+=input
   if instruction==WholeFilmCloudPlan.instructions {return try batchAnswer(input)}
   return try mapAnswer(input)
  }
  let doc=document(),plan=try WholeFilmPlan.chunks(doc,source:"embedded-subtitle")
  host.accept(doc,film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  XCTAssertTrue(host.ready(for:"film"),host.status)
  XCTAssertEqual(host.completed,plan.count);XCTAssertEqual(estimates.count,1)
  XCTAssertLessThanOrEqual(calls,6);XCTAssertLessThanOrEqual(calls,estimates.first ?? 0)
  for cue in doc.cues {XCTAssertTrue(inputs.contains(cue.text),cue.text)}
  print("QUOTA_BATCH_449: canonical=\(plan.count), stubCalls=\(calls), preflightUpper=\(estimates.first ?? 0); not a live ChatGPT call")
 }
 func testExistingSmallChunkArchiveIsReusedWithoutReanalyzingOldSubtitles() async throws {
  let doc=document(),plan=try WholeFilmPlan.chunks(doc,source:"embedded-subtitle")
  // Use a disk-backed archive because nil intentionally disables persistence.
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:folder)}
  let disk=WholeFilmArchive(directory:folder)
  let completed=plan.dropLast().map{WholeFilmSection(index:$0.index,summary:"守门人的说法需要与钥匙的去向核对。",evidenceIDs:[$0.evidence[0].id])}
  try await disk.write(WholeFilmArchiveValue(sections:completed,map:nil),key:WholeFilmPlan.signature(plan,film:"film"))
  let host=WholeFilmHost(archive:disk);host.available={true};host.cloudBatching={true}
  var calls=0,requested=""
  host.inference={ [self] instruction,input in
   calls+=1;if instruction==WholeFilmCloudPlan.instructions {requested+=input;return try batchAnswer(input)}
   return try mapAnswer(input)
  }
  host.accept(doc,film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  XCTAssertTrue(host.ready(for:"film"),host.status);XCTAssertEqual(calls,2)
  XCTAssertFalse(requested.contains(doc.cues[0].text))
  let restored=WholeFilmHost(archive:disk);restored.available={true};restored.cloudBatching={true}
  restored.inference={_,_ in XCTFail("Completed analysis must not request again");return "{}"}
  restored.accept(doc,film:"film",source:"embedded-subtitle",embedded:true);await restored.waitForAnalysis()
  XCTAssertTrue(restored.ready(for:"film"))
 }
 func testPreflightRejectsInsufficientBudgetBeforeAnyInference() async {
  let host=WholeFilmHost(archive:WholeFilmArchive(directory:nil));host.available={true};host.cloudBatching={true}
  var calls=0
  host.cloudPreflight={_ in throw NSError(domain:"TestBudget",code:1,userInfo:[NSLocalizedDescriptionKey:"预算不足，尚未发送新请求"])}
  host.inference={_,_ in calls+=1;return "{}"}
  host.accept(document(),film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  XCTAssertEqual(calls,0);XCTAssertGreaterThan(host.estimatedCloudRequests,0)
  XCTAssertFalse(host.ready(for:"film"));XCTAssertTrue(host.status.contains("预算不足"))
 }
 func testDuplicateMetadataCannotRetryAFailedBatch() async {
  let host=WholeFilmHost(archive:WholeFilmArchive(directory:nil));host.available={true};host.cloudBatching={true}
  var calls=0;host.inference={_,_ in calls+=1;return "{}"}
  let doc=document()
  host.accept(doc,film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  host.accept(doc,film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  XCTAssertEqual(calls,1);XCTAssertFalse(host.ready(for:"film"))
 }
 func testMissingDuplicateOrCrossChunkEvidenceIsRejected()throws {
  let plan=try WholeFilmPlan.chunks(document(),source:"embedded-subtitle")
  let chunks=Array(plan.prefix(2))
  let first=WholeFilmSection(index:chunks[0].index,summary:"守门人否认了自己曾移动过银色钥匙。",evidenceIDs:[chunks[0].evidence[0].id])
  let foreign=WholeFilmSection(index:chunks[1].index,summary:first.summary,evidenceIDs:first.evidenceIDs)
  XCTAssertNil(WholeFilmCloudPlan.sections("{\"sections\":"+WholeFilmPlan.json([first])+"}",chunks:chunks))
  XCTAssertNil(WholeFilmCloudPlan.sections("{\"sections\":"+WholeFilmPlan.json([first,first])+"}",chunks:chunks))
  XCTAssertNil(WholeFilmCloudPlan.sections("{\"sections\":"+WholeFilmPlan.json([first,foreign])+"}",chunks:chunks))
 }
 func testBatchInputsAreBoundedAndKeepEveryCanonicalEvidenceID()throws {
  let plan=try WholeFilmPlan.chunks(document(1500),source:"embedded-subtitle")
  let batches=WholeFilmCloudPlan.batches(plan)
  XCTAssertEqual(batches.flatMap{$0}.flatMap(\.evidence).map(\.id),plan.flatMap(\.evidence).map(\.id))
  for batch in batches {
   XCTAssertLessThanOrEqual(batch.count,WholeFilmCloudPlan.maxChunksPerRequest)
   XCTAssertLessThanOrEqual(WholeFilmCloudPlan.input(batch,previous:String(repeating:"界",count:600)).count,WholeFilmCloudPlan.inputLimit)
  }
 }
 func testLegacyBudgetDecodesWithoutResettingTwentyPreviousRequests()throws {
  let data=Data("{\"automatic\":20,\"manual\":2,\"lastRequest\":1000,\"failedSegments\":[3]}".utf8)
  let budget=try JSONDecoder().decode(PlotBudget.self,from:data)
  XCTAssertEqual(budget.automatic,20);XCTAssertEqual(budget.total,22);XCTAssertEqual(budget.legacyRequests,22)
  XCTAssertFalse(budget.canPrepareWholeFilm(requests:2,totalLimit:20,analysisLimit:8))
  XCTAssertEqual(try JSONDecoder().decode(PlotBudget.self,from:JSONEncoder().encode(budget)),budget)
 }
 func testSeparateAnalysisLimitStillRespectsTotalAndDoesNotDelayQuestions() {
  var budget=PlotBudget()
  XCTAssertTrue(budget.canPrepareWholeFilm(requests:2,totalLimit:4,analysisLimit:2))
  XCTAssertFalse(budget.canPrepareWholeFilm(requests:2,totalLimit:4,analysisLimit:2,questionReserve:4))
  XCTAssertTrue(budget.reserve(segment:-1,now:1000,manualRequest:false,limit:4,interval:0,purpose:.wholeFilm,purposeLimit:2))
  XCTAssertTrue(budget.reserve(segment:-2,now:1001,manualRequest:false,limit:4,interval:0,purpose:.wholeFilm,purposeLimit:2))
  XCTAssertFalse(budget.reserve(segment:-3,now:1002,manualRequest:false,limit:4,interval:0,purpose:.wholeFilm,purposeLimit:2))
  XCTAssertTrue(budget.reserve(segment:1,now:1002,manualRequest:false,limit:4,interval:180,purpose:.question))
  XCTAssertTrue(budget.reserve(segment:1,now:1003,manualRequest:false,limit:4,interval:0,purpose:.spoilerAudit))
  XCTAssertFalse(budget.reserve(segment:2,now:1400,manualRequest:false,limit:4,interval:180,purpose:.question))
  XCTAssertEqual(budget.automatic,4);XCTAssertEqual(budget.wholeFilmRequests,2)
  XCTAssertEqual(budget.questionRequests,1);XCTAssertEqual(budget.auditRequests,1);XCTAssertEqual(budget.legacyRequests,0)
 }
 func testInterruptedAnalysisRestoresCompletedBatchFromDisk() async throws {
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:folder)}
  let archive=WholeFilmArchive(directory:folder),doc=document()
  let plan=try WholeFilmPlan.chunks(doc,source:"embedded-subtitle"),key=WholeFilmPlan.signature(plan,film:"film")
  let host=WholeFilmHost(archive:archive);host.available={true};host.cloudBatching={true}
  var started=0
  let secondStarted=expectation(description:"Second cloud batch starts only after first batch is persisted")
  host.inference={ [self] instruction,input in
   started+=1
   if started>1 {secondStarted.fulfill();try await Task.sleep(nanoseconds:30_000_000_000)}
   return try batchAnswer(input)
  }
  host.accept(doc,film:"film",source:"embedded-subtitle",embedded:true)
  // Wait for a causal checkpoint instead of racing a 2-second polling loop
  // against a background-priority analysis task on a shared CI simulator.
  await fulfillment(of:[secondStarted],timeout:15)
  XCTAssertGreaterThanOrEqual(started,2,"status=\(host.status), completed=\(host.completed)")
  host.cancel()
  let saved=await archive.read(key)
  XCTAssertFalse(saved.sections.isEmpty,"status=\(host.status), started=\(started), completed=\(host.completed)");XCTAssertLessThan(saved.sections.count,plan.count)
  let restored=WholeFilmHost(archive:WholeFilmArchive(directory:folder));restored.available={true};restored.cloudBatching={true}
  var requested=""
  restored.inference={ [self] instruction,input in
   if instruction==WholeFilmCloudPlan.instructions {requested+=input;return try batchAnswer(input)}
   return try mapAnswer(input)
  }
  restored.accept(doc,film:"film",source:"embedded-subtitle",embedded:true);await restored.waitForAnalysis()
  XCTAssertTrue(restored.ready(for:"film"),restored.status)
  XCTAssertFalse(requested.contains(doc.cues[0].text))
 }
 func testConfirmedCacheRemovalOnlyDeletesCurrentFilmsRecords() async throws {
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:folder)}
  let archive=WholeFilmArchive(directory:folder)
  let current=PlotMemoryStore.key("current"),legacy=PlotMemoryStore.key("legacy"),other=PlotMemoryStore.key("other")
  let section=WholeFilmSection(index:0,summary:"私有剧情记录不应泄露。",evidenceIDs:["one"])
  try await archive.write(WholeFilmArchiveValue(sections:[section],map:nil,filmKey:"film"),key:current)
  try await archive.write(WholeFilmArchiveValue(sections:[section],map:nil),key:legacy)
  try await archive.write(WholeFilmArchiveValue(sections:[section],map:nil,filmKey:"other"),key:other)
  let deleted=try await archive.remove(film:"film",legacyKey:legacy)
  XCTAssertEqual(deleted,2)
  let a=await archive.read(current),b=await archive.read(legacy),c=await archive.read(other)
  XCTAssertTrue(a.sections.isEmpty);XCTAssertTrue(b.sections.isEmpty);XCTAssertEqual(c.sections,[section])
 }
 func testCleanupRefusesAChangedFilmAndSavedLimitCanReach200() async throws {
  let host=WholeFilmHost(archive:WholeFilmArchive(directory:nil));host.reset(film:"new-film")
  do {_ = try await host.clearSavedAnalysis(expectedFilm:"old-film");XCTFail("Wrong film cache must stay intact")}
  catch {XCTAssertTrue(error.localizedDescription.contains("影片已改变"))}
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  preferences.set(50,forKey:"plot-cloud-limit")
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertEqual(controller.limit,50)
  controller.limit=200;controller.analysisLimit=12
  let restored=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertEqual(restored.limit,200);XCTAssertEqual(restored.analysisLimit,12)
 }

 func testCancelledQueuedWriterCannotRecreateACleanedCache() async throws {
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:folder)}
  let archive=WholeFilmArchive(directory:folder),key=PlotMemoryStore.key("cancelled-write")
  let value=WholeFilmArchiveValue(sections:[WholeFilmSection(index:0,summary:"已清理的资料不能被旧任务写回来。",evidenceIDs:["one"])],map:nil,filmKey:"film")
  try await archive.write(value,key:key)
  _ = try await archive.remove(film:"film",legacyKey:key)
  let writer=Task {
   withUnsafeCurrentTask{$0?.cancel()}
   try await archive.write(value,key:key)
  }
  do {try await writer.value;XCTFail("Cancelled write must be rejected")}
  catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
  let saved=await archive.read(key);XCTAssertTrue(saved.sections.isEmpty)
 }

}
