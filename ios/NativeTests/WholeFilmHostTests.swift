import XCTest
import Libavcodec
@testable import TogetherPoC

@MainActor final class WholeFilmHostTests:XCTestCase {
 private func document()->SubtitleDocument {
  SubtitleDocument([
   SubtitleCue(start:1,end:3,text:"守门人说旧门已经锁好了。"),
   SubtitleCue(start:20,end:23,text:"访客问那把银色钥匙去哪了。"),
   SubtitleCue(start:30,end:33,text:"守门人说他没有碰过那把钥匙。"),
   SubtitleCue(start:80,end:83,text:"PRIVATE_FUTURE：守门人承认是为了保护证人而藏了钥匙。")])
 }
 private func ids(_ value:String)->[String] {
  let expression=try! NSRegularExpression(pattern:"[a-f0-9]{64}")
  let ns=value as NSString
  return expression.matches(in:value,range:NSRange(location:0,length:ns.length)).map{ns.substring(with:$0.range)}
 }
 private func host()->WholeFilmHost {
  let host=WholeFilmHost(archive:WholeFilmArchive(directory:nil));host.available={true}
  host.inference={ [self] instruction,input in
   let evidence=Array(Set(ids(input))).sorted()
   if instruction==WholeFilmPlan.mapInstructions {
    return WholeFilmPlan.json(WholeFilmMap(synopsis:"完整故事：守门人藏起钥匙是为了保护证人；PRIVATE_FUTURE 不应显示给观众。",threads:["钥匙失踪与保护证人的动机相连"],evidenceIDs:evidence))
   }
   return WholeFilmPlan.json(WholeFilmSection(index:0,summary:"守门人先否认移动钥匙，后承认自己在保护证人。",evidenceIDs:Array(evidence.prefix(2))))
  }
  return host
 }
 func testEverySubtitleIncludingEndingEntersFullAnalysisBeforeReady() async {
  let host=host();var sawEnding=false;let inference=host.inference
  host.inference={instruction,input in if input.contains("PRIVATE_FUTURE") {sawEnding=true};return try await inference(instruction,input)}
  host.accept(document(),film:"film",source:"embedded-subtitle",embedded:true)
  XCTAssertFalse(host.ready(for:"film"))
  await host.waitForAnalysis()
  XCTAssertTrue(sawEnding);XCTAssertTrue(host.ready(for:"film"));XCTAssertEqual(host.completed,host.total)
  XCTAssertFalse(host.status.contains("PRIVATE_FUTURE"));XCTAssertFalse(host.ready(for:"different-film"))
 }
 func testChunkingDoesNotSampleAwayLinesOrEnding()throws {
  let text=String(repeating:"长对白没有被丢弃",count:300)
  let document=SubtitleDocument([SubtitleCue(start:0,end:10,text:text),SubtitleCue(start:999,end:1000,text:"最后一句")])
  let chunks=try WholeFilmPlan.chunks(document,source:"embedded-subtitle")
  XCTAssertEqual(chunks.flatMap(\.evidence).map(\.text).joined(),text+"最后一句")
 }
 func testFailedSectionCannotMarkWholeFilmReady() async {
  let host=host();host.inference={_,_ in "{}"}
  host.accept(document(),film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  XCTAssertFalse(host.ready(for:"film"));XCTAssertFalse(host.busy);XCTAssertTrue(host.status.contains("未通过"))
 }
 func testEmbeddedTranscriptKeepsPriorityOverExternalSubtitle() async {
  let host=host();host.accept(document(),film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  let external=SubtitleDocument([SubtitleCue(start:1,end:2,text:"EXTERNAL_SHOULD_NOT_REPLACE")])
  host.supplyExternal(external,film:"film")
  XCTAssertTrue(host.ready(for:"film"))
  let context=PlotContext(cutoff:40,recent:[],earlier:[],predictions:[])
  XCTAssertFalse(host.questionInput(context,film:"film")!.contains("EXTERNAL_SHOULD_NOT_REPLACE"))
 }
 func testPrivateFutureAnswerCannotEscapeIntoQuestionJSON() async throws {
  let host=host();let doc=document();host.accept(doc,film:"film",source:"embedded-subtitle",embedded:true);await host.waitForAnalysis()
  let watched=doc.cues.filter{$0.end<40}.map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:"embedded-subtitle")}
  let context=PlotContext(cutoff:40,recent:watched,earlier:[],predictions:[])
  let future=try WholeFilmPlan.chunks(doc,source:"embedded-subtitle").flatMap(\.evidence).last!
  let object:[String:Any]=["question":"钥匙失踪后，守门人接下来可能怎么做？","options":["承认自己移动过钥匙","请访客继续寻找钥匙"],"evidenceIDs":[watched.last!.id],"kind":"prediction","privateAnswerIndex":0,"privateFutureEvidenceIDs":[future.id]]
  let answer=String(data:try JSONSerialization.data(withJSONObject:object),encoding:.utf8)!
  let question=try XCTUnwrap(host.parseQuestion(answer,context:context,film:"film"))
  let publicJSON=WholeFilmPlan.json(question)
  XCTAssertFalse(publicJSON.contains("privateAnswerIndex"));XCTAssertFalse(publicJSON.contains(future.id));XCTAssertFalse(publicJSON.contains("PRIVATE_FUTURE"))
  let safe=try await host.verify(question,context:context,film:"film",audit:{_,input in
   XCTAssertFalse(input.contains("PRIVATE_FUTURE"));return "{\"safe\":true}"
  })
  XCTAssertTrue(safe)
  let unsafe=try await host.verify(question,context:context,film:"film",audit:{_,_ in "{\"safe\":false}"})
  XCTAssertFalse(unsafe)
 }
 func testCompleteFilmRequirementBlocksGenericQuestionUntilAnalysisReady() {
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:UserDefaults(suiteName:UUID().uuidString)!,requireCompleteFilm:true)
  controller.frame={PlotFrame(key:"film",position:40,evidence:[])}
  controller.generate();XCTAssertNil(controller.result);XCTAssertFalse(controller.working);XCTAssertEqual(controller.requests,0)
  XCTAssertEqual(controller.selectedModel,"全片分析尚未完成")
 }
 func testActualLocalMovieWithUnicodePathUsesCoordinatedOriginalFile() async throws {
  let bundled=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"whole-film-tiny",withExtension:"mkv"))
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent("本地影片-字幕-\(UUID().uuidString)",isDirectory:true)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:folder)}
  let local=folder.appendingPathComponent("影片内置字幕.mkv")
  try FileManager.default.copyItem(at:bundled,to:local)
  let output=try await Task.detached(priority:.utility) {
   try FullFilmTranscriptReader.extract(local,preferredTitle:nil,allowOCR:true,progress:{_ in})
  }.value
  XCTAssertEqual(output.document.cues.count,3)
  XCTAssertFalse(output.ocr)
  XCTAssertGreaterThan(output.document.cues.last!.start,150)
 }
 func testRealEmbeddedTextReaderReachesEndingWithoutPlayingMovie() async throws {
  let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"whole-film-tiny",withExtension:"mkv"))
  let output=try await Task.detached {try FullFilmTranscriptReader.extract(url,preferredTitle:nil,allowOCR:true,progress:{_ in})}.value
  XCTAssertEqual(output.document.cues.count,3);XCTAssertFalse(output.ocr)
  XCTAssertTrue(output.document.cues.last!.text.contains("protect the witness"));XCTAssertGreaterThan(output.document.cues.last!.start,150)
 }
 func testRealPGSOCRReadsWholeTrackWithoutChangingPlayer() async throws {
  let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"whole-film-pgs-text",withExtension:"mkv"))
  let output=try await Task.detached {try FullFilmTranscriptReader.extract(url,preferredTitle:nil,allowOCR:true,progress:{_ in})}.value
  XCTAssertTrue(output.ocr);XCTAssertGreaterThanOrEqual(output.document.cues.count,3);XCTAssertGreaterThan(output.document.cues.last!.start,15)
 }
 func testUnreadablePGSBitmapNeverClaimsWholeFilmWasRead() async throws {
  let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"whole-film-pgs",withExtension:"mkv"))
  do {
   let output=try await Task.detached {try FullFilmTranscriptReader.extract(url,preferredTitle:nil,allowOCR:true,progress:{_ in})}.value
   XCTFail("Unrecognizable solid bitmap must not claim \(output.document.cues.count) complete OCR lines")
  } catch let error as FullFilmTranscriptReader.Failure {
   XCTAssertEqual(error.localizedDescription,FullFilmTranscriptReader.Failure.decode.localizedDescription)
  }
 }
 func testRemoteStreamingSourceDoesNotAttemptUnsupportedFullMovieDemux() {
  let host=host()
  host.readLocalMovie(URL(string:"https://example.com/online/movie.m3u8")!,film:"remote-movie",title:nil,allowOCR:true)
  XCTAssertFalse(host.readingActive)
  XCTAssertFalse(host.busy)
  XCTAssertFalse(host.ready(for:"remote-movie"))
  XCTAssertTrue(host.status.contains("在线播放"))
  XCTAssertTrue(host.status.contains("SRT"))
 }
 func testAIOnlyImportedTranscriptSurvivesMissingOriginalAndDoesNotSwitchToDemux() async {
  let host=host()
  let missing=URL(fileURLWithPath:"/tmp/togetherplayer-no-such-local-movie-20261015.mkv")
  host.readLocalMovie(missing,film:"film",title:nil,allowOCR:true)
  host.useExternalForAI(document(),film:"film")
  host.readLocalMovie(missing,film:"film",title:nil,allowOCR:true)
  await host.waitForAnalysis()
  XCTAssertTrue(host.ready(for:"film"))
  XCTAssertEqual(host.completed,host.total)
  XCTAssertFalse(host.readingActive)
  XCTAssertTrue(host.subtitleSource.contains("外置"))
  XCTAssertFalse(host.status.contains("无法打开原始影片"))
 }
 func testSelectedTrackOverridesDefaultChinesePriority() {
  let tracks=[FullFilmTranscriptReader.Track(index:1,language:"eng",title:"",codec:AV_CODEC_ID_SUBRIP),FullFilmTranscriptReader.Track(index:2,language:"chi",title:"简体中文",codec:AV_CODEC_ID_HDMV_PGS_SUBTITLE)]
  XCTAssertEqual(FullFilmTranscriptReader.preferred(tracks,title:nil)?.index,2)
  XCTAssertEqual(FullFilmTranscriptReader.preferred(tracks,title:nil,language:"en-US")?.index,1)
  XCTAssertEqual(FullFilmTranscriptReader.preferred(tracks,title:nil,streamIndex:2)?.index,2)
 }
}
