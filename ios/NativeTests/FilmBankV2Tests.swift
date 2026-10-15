import XCTest
import CryptoKit
import CoreGraphics
import AVFoundation
@testable import TogetherPoC

@MainActor final class FilmBankV2Tests:XCTestCase {
 private func root()throws->URL {let p=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:p,withIntermediateDirectories:true);return p}
 private func sample(_ fingerprint:String)->FilmQuestionBank {
  FilmQuestionBank(schemaVersion:1,title:"合成素材测试影片",year:nil,edition:nil,durationMs:120_000,sourceFingerprint:fingerprint,subtitleFingerprint:nil,questions:[FilmBankQuestion(id:"q1",triggerAtMs:30_000,revealAtMs:60_000,type:"prediction",question:"旧门上锁之后，守门人接下来会怎么做？",options:["解释钥匙的去向","带领访客寻找钥匙"],answerIndex:0,evidence:[FilmBankEvidence(kind:"subtitle",startMs:20_000,endMs:24_000,text:"守门人否认移动钥匙")],revealEvidence:[FilmBankEvidence(kind:"subtitle",startMs:55_000,endMs:58_000,text:"守门人说明藏起钥匙保护证人")],explanation:String(repeating:"对白说明了钥匙去向与保护证人的因果关系。",count:50),confidence:0.9,qualityScore:92)])
 }
 private func zipEntries(_ data:Data)throws->[String:Data] {
  let bytes=[UInt8](data)
  func n(_ offset:Int,_ count:Int)->Int {(0..<count).reduce(0){$0 | Int(bytes[offset+$1]) << ($1*8)}}
  var i=0,result:[String:Data]=[:]
  while i+30<=bytes.count,n(i,4)==0x04034b50 {
   XCTAssertEqual(n(i+6,2)&0x0800,0x0800,"UTF8 paths must be declared")
   let size=n(i+18,4),length=n(i+26,2),extra=n(i+28,2),start=i+30+length+extra
   guard start+size<=bytes.count else{throw FilmBankValidation.invalidFormat}
   let name=String(decoding:bytes[(i+30)..<(i+30+length)],as:UTF8.self)
   result[name]=Data(bytes[start..<(start+size)]);i=start+size
  }
  return result
 }
 func testCompleteFingerprintDetectsChangedMiddleWithSameHeadTailAndSize()throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let a=directory.appendingPathComponent("a.mkv"),b=directory.appendingPathComponent("b.mkv")
  let first=Data(repeating:42,count:200_000);var changed=first;changed[100_000]=43
  try first.write(to:a);try changed.write(to:b)
  let expected=SHA256.hash(data:first).map{String(format:"%02x",$0)}.joined()
  XCTAssertEqual(try FilmMaterialFingerprint.source(a),expected)
  XCTAssertNotEqual(try FilmMaterialFingerprint.source(a),try FilmMaterialFingerprint.source(b))
 }
 func testMP4AndMKVExportRespectsExplicitSpareSubtitleAndMappedSheets() async throws {
  for ext in ["mp4","mkv"] {
   let movie=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"bank-material",withExtension:ext))
   let spare=SubtitleDocument([SubtitleCue(start:1,end:3,text:"SPARE_SUBTITLE_MUST_WIN")])
   let output=try await Task.detached(priority:.utility){try FilmMaterialExporter.create(url:movie,title:"Synthetic scene",external:spare,allowOCR:true,progress:{_ in})}.value
   defer{try? FileManager.default.removeItem(at:output.deletingLastPathComponent())}
   let entries=try zipEntries(Data(contentsOf:output))
   XCTAssertNotNil(entries["manifest.json"]);XCTAssertNotNil(entries["question-bank-v1.schema.json"])
   XCTAssertNotNil(entries["ChatGPT项目指令.txt"])
   let srt=String(decoding:try XCTUnwrap(entries["subtitles/whole-film.srt"]),as:UTF8.self)
   XCTAssertTrue(srt.contains("SPARE_SUBTITLE_MUST_WIN"));XCTAssertFalse(srt.contains("INTERNAL_END"))
   let timeline=try JSONDecoder().decode([FilmFrameRecord].self,from:try XCTUnwrap(entries["frame-timeline.json"]))
   XCTAssertGreaterThanOrEqual(timeline.count,2)
   for frame in timeline {
    XCTAssertNotNil(entries[frame.sheet]);XCTAssertTrue((0..<4).contains(frame.column));XCTAssertGreaterThanOrEqual(frame.actualMs,0);XCTAssertFalse(frame.visualEvidenceComplete)
   }
   let onDisk=output.deletingLastPathComponent().appendingPathComponent("frame-timeline.json")
   XCTAssertEqual(try Data(contentsOf:onDisk),entries["frame-timeline.json"])
  }
 }
 func testCancelledExportDoesNotPublishAnyMaterialAndMovieChangeClearsPreview() async throws {
  let movie=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"bank-material",withExtension:"mkv"))
  let task=Task.detached {() throws->URL in
   withUnsafeCurrentTask{$0?.cancel()}
   return try FilmMaterialExporter.create(url:movie,title:"cancel",external:nil,allowOCR:true,progress:{_ in})
  }
  do {_ = try await task.value;XCTFail("Cancelled export must not publish")}catch is CancellationError{}catch{XCTFail("Unexpected \(error)")}
  let session=FilmMaterialExportSession();session.begin(url:movie,title:"cancel",external:nil,allowOCR:true)
  session.selectMovie(URL(fileURLWithPath:"/different/movie.mkv"))
  XCTAssertFalse(session.working);XCTAssertNil(session.file);XCTAssertTrue(session.individualFiles.isEmpty)
 }
 func testSchemaRejectsUnknownMissingAndWrongTypesAndKeepsNullableFields() throws {
  let original=sample(String(repeating:"a",count:64)),data=try JSONEncoder().encode(original)
  var object=try XCTUnwrap(try JSONSerialization.jsonObject(with:data) as? [String:Any])
  XCTAssertTrue(object["subtitleFingerprint"] is NSNull)
  XCTAssertEqual(FilmBankCodec.identity(original),FilmBankCodec.identity(try FilmBankCodec.decode(data)))
  object["unknown"]=true;XCTAssertThrowsError(try FilmBankCodec.decode(JSONSerialization.data(withJSONObject:object)))
  object.removeValue(forKey:"unknown");object.removeValue(forKey:"subtitleFingerprint")
  XCTAssertThrowsError(try FilmBankCodec.decode(JSONSerialization.data(withJSONObject:object)))
  object["subtitleFingerprint"]=NSNull();object["schemaVersion"]=true
  XCTAssertThrowsError(try FilmBankCodec.decode(JSONSerialization.data(withJSONObject:object))) {error in
   XCTAssertTrue(error.localizedDescription.contains("schemaVersion"),error.localizedDescription)
  }
 }
 func testHDRThumbnailTransformIsMonotonicAndLeavesOpaquePixels() {
  var bytes=Data((0..<256).flatMap{[UInt8($0),UInt8($0),UInt8($0),255]})
  FilmHDRToneMap.apply(&bytes,pq:true,bt2020:true)
  XCTAssertEqual(bytes[0],0);XCTAssertGreaterThan(bytes[bytes.count-2],200)
  for i in 1..<256 {XCTAssertGreaterThanOrEqual(bytes[i*4],bytes[(i-1)*4]);XCTAssertEqual(bytes[i*4+3],255)}
 }
 func testRestartsAndMovedSourceReuseBankAndProgressWithoutRepeat() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let movie=directory.appendingPathComponent("first.mkv"),moved=directory.appendingPathComponent("second.mkv")
  try Data(repeating:45,count:200_000).write(to:movie);try FileManager.default.copyItem(at:movie,to:moved)
  let bank=sample(try FilmMaterialFingerprint.source(movie)),store=FilmQuestionBankStore(directory:directory.appendingPathComponent("bank")),progress=FilmBankProgressStore(directory:directory.appendingPathComponent("progress"))
  try await store.saveForSource(bank,candidate:FilmMaterialFingerprint.candidate(movie))
  let first=FilmQuestionBankRuntime(store:store,progressStore:progress)
  first.restore(filmKey:"room1",source:movie,durationMs:120_000);await first.waitForRestore();XCTAssertNotNil(first.active)
  var sent=0
  first.tick(filmKey:"room1",positionMs:29_500,durationMs:120_000,canPublish:true,publish:{_ in sent+=1})
  first.tick(filmKey:"room1",positionMs:30_500,durationMs:120_000,canPublish:true,publish:{_ in sent+=1})
  await first.waitForProgress();XCTAssertEqual(sent,1)
  first.observePoll(["id":"server-poll-current","question":bank.questions[0].question,"options":bank.questions[0].options,"revealed":false])
  XCTAssertEqual(first.completedCount,0)
  first.observePoll(["id":"server-poll-current","question":bank.questions[0].question,"options":bank.questions[0].options,"revealed":true])
  await first.waitForProgress();XCTAssertEqual(first.completedCount,1)
  let second=FilmQuestionBankRuntime(store:store,progressStore:progress)
  second.restore(filmKey:"other-room",source:moved,durationMs:120_000);await second.waitForRestore()
  XCTAssertNotNil(second.active);XCTAssertEqual(second.publishedCount,1);XCTAssertEqual(second.completedCount,1)
  second.tick(filmKey:"other-room",positionMs:29_500,durationMs:120_000,canPublish:true,publish:{_ in sent+=1})
  second.tick(filmKey:"other-room",positionMs:30_500,durationMs:120_000,canPublish:true,publish:{_ in sent+=1})
  await second.waitForProgress();XCTAssertEqual(sent,1)
  var messages:[FilmBankRevealPart]=[]
  second.tick(filmKey:"other-room",positionMs:59_900,durationMs:120_000,canPublish:false,publish:{_ in},reveal:{messages.append($0)})
  XCTAssertTrue(messages.isEmpty)
  second.tick(filmKey:"other-room",positionMs:60_100,durationMs:120_000,canPublish:false,canReveal:false,publish:{_ in},reveal:{messages.append($0)})
  XCTAssertTrue(messages.isEmpty,"Offline tick cannot consume reveal delivery")
  second.tick(filmKey:"other-room",positionMs:60_200,durationMs:120_000,canPublish:false,publish:{_ in},reveal:{messages.append($0)})
  XCTAssertGreaterThan(messages.count,1,"Long explanations must be split, not truncated")
  XCTAssertTrue(messages.allSatisfy{$0.text.count<1000})
  // Lost acknowledgements after an app restart reuse the same chat IDs;
  // the existing server deduplicates (room,user,clientMessageId).
  let retry=FilmQuestionBankRuntime(store:store,progressStore:progress)
  retry.restore(filmKey:"other-room",source:moved,durationMs:120_000);await retry.waitForRestore()
  var resent:[FilmBankRevealPart]=[]
  retry.tick(filmKey:"other-room",positionMs:61_000,durationMs:120_000,canPublish:false,publish:{_ in},reveal:{resent.append($0)})
  XCTAssertEqual(resent.map(\.id),messages.map(\.id))
  for message in messages {second.acknowledgeReveal(message.id)}
  await second.waitForProgress()
  let third=FilmQuestionBankRuntime(store:store,progressStore:progress)
  third.restore(filmKey:"third-room",source:movie,durationMs:120_000);await third.waitForRestore()
  var duplicates=0
  third.tick(filmKey:"third-room",positionMs:61_000,durationMs:120_000,canPublish:false,publish:{_ in},reveal:{_ in duplicates+=1})
  XCTAssertEqual(duplicates,0)
 }
 func testSubtitleSentenceFinishesBeforeBankPauseAndFastSeekSkipsOldQuestion() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let movie=directory.appendingPathComponent("film.mkv");try Data([1,2,3]).write(to:movie)
  let bank=sample(try FilmMaterialFingerprint.source(movie)),store=FilmQuestionBankStore(directory:directory.appendingPathComponent("bank"))
  try await store.saveForSource(bank,candidate:FilmMaterialFingerprint.candidate(movie))
  let runtime=FilmQuestionBankRuntime(store:store,progressStore:FilmBankProgressStore(directory:directory.appendingPathComponent("progress")))
  runtime.restore(filmKey:"f",source:movie,durationMs:120_000);await runtime.waitForRestore()
  var sent=0
  func tick(_ t:Double,_ seq:Int,_ shown:Bool){runtime.tick(filmKey:"f",positionMs:t,durationMs:120_000,canPublish:true,subtitleShown:shown,captionSequence:seq,publish:{_ in sent+=1})}
  tick(29_000,1,true);tick(31_000,1,true);await runtime.waitForProgress();XCTAssertEqual(sent,0)
  tick(32_000,2,true);await runtime.waitForProgress();XCTAssertEqual(sent,1,"Next sentence may start immediately; do not wait minutes for a silent gap")
  runtime.startNewRound();await runtime.waitForProgress();sent=0
  tick(10_000,1,false);tick(80_000,1,false);await runtime.waitForProgress();XCTAssertEqual(sent,0)
  tick(29_000,1,false);tick(30_500,1,false);await runtime.waitForProgress();XCTAssertEqual(sent,1)
  runtime.observePoll(["id":"old-round-poll","question":bank.questions[0].question,"options":bank.questions[0].options,"revealed":true])
  XCTAssertEqual(runtime.completedCount,0)
  runtime.observePoll(["id":"new-round-poll","question":bank.questions[0].question,"options":bank.questions[0].options,"revealed":false])
  runtime.observePoll(["id":"new-round-poll","question":bank.questions[0].question,"options":bank.questions[0].options,"revealed":true])
  await runtime.waitForProgress();XCTAssertEqual(runtime.completedCount,1)
 }
 func testImportValidatesSourceAndPersistsMatchingBankOnly() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let movie=directory.appendingPathComponent("film.mp4"),json=directory.appendingPathComponent("bank.json")
  try Data([4,5,6]).write(to:movie)
  let store=FilmQuestionBankStore(directory:directory.appendingPathComponent("bank")),progress=FilmBankProgressStore(directory:directory.appendingPathComponent("progress"))
  let runtime=FilmQuestionBankRuntime(store:store,progressStore:progress)
  runtime.restore(filmKey:"f",source:movie,durationMs:120_000);await runtime.waitForRestore();XCTAssertNil(runtime.active)
  let hash=try FilmMaterialFingerprint.source(movie),bank=sample(hash)
  try JSONEncoder().encode(bank).write(to:json)
  await runtime.importFile(json,filmKey:"f",source:movie,durationMs:120_000)
  XCTAssertEqual(runtime.active,bank)
  let saved=await store.loadForSource(hash);XCTAssertEqual(saved,bank)
  try JSONEncoder().encode(sample(String(repeating:"f",count:64))).write(to:json)
  await runtime.importFile(json,filmKey:"f",source:movie,durationMs:120_000)
  XCTAssertEqual(runtime.active,bank);XCTAssertTrue(runtime.status.contains("不匹配"))
  let publicJSON=WholeFilmPlan.json(FilmBankCodec.question(bank.questions[0],blocking:true))
  XCTAssertFalse(publicJSON.contains("answerIndex"));XCTAssertFalse(publicJSON.contains("保护证人"));XCTAssertFalse(publicJSON.contains("revealEvidence"))
 }

 func testDelayedRevealUsesFileTimelineAndWaitsForLaggingPeer() {
  XCTAssertEqual(FilmBankTimeline.safeReveal(playerMs:60_000,roomMs:55_000,hostOffset:5_000,peers:[54_800]),59_800)
  XCTAssertEqual(FilmBankTimeline.safeReveal(playerMs:60_000,roomMs:55_000,hostOffset:5_000,peers:[55_000]),60_000)
  XCTAssertEqual(FilmBankTimeline.safeReveal(playerMs:60_000,roomMs:60_000,hostOffset:0,peers:[]),60_000)
  XCTAssertEqual(FilmBankTimeline.safeReveal(playerMs:.nan,roomMs:60_000,hostOffset:0,peers:[]),0)
 }

 func testVisualChangeHeuristicDistinguishesFlatBlackAndWhiteWithoutSemanticClaims() throws {
  func image(_ white:Bool)throws->CGImage {
   let context=try XCTUnwrap(CGContext(data:nil,width:32,height:18,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
   context.setFillColor(CGColor(gray:white ? 1 : 0,alpha:1));context.fill(CGRect(x:0,y:0,width:32,height:18))
   return try XCTUnwrap(context.makeImage())
  }
  let dark=try image(false),bright=try image(true)
  XCTAssertEqual(FilmSceneChange.distance(FilmSceneChange.signature(dark),FilmSceneChange.signature(dark)),0)
  XCTAssertGreaterThan(try XCTUnwrap(FilmSceneChange.distance(FilmSceneChange.signature(dark),FilmSceneChange.signature(bright))),0.9)
  XCTAssertNil(FilmSceneChange.distance(nil,FilmSceneChange.signature(bright)))
 }

 func testNoBankDoesNotReadCompleteMovieAndCandidateNeverReplacesFullHash() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let movie=directory.appendingPathComponent("first.mkv"),other=directory.appendingPathComponent("changed-middle.mkv")
  let bytes=Data(repeating:8,count:200_000);var different=bytes;different[100_000]=9
  try bytes.write(to:movie);try different.write(to:other)
  let store=FilmQuestionBankStore(directory:directory.appendingPathComponent("bank")),progress=FilmBankProgressStore(directory:directory.appendingPathComponent("progress"))
  let runtime=FilmQuestionBankRuntime(store:store,progressStore:progress);var fullReads=0;runtime.onFullFingerprint={fullReads+=1}
  runtime.restore(filmKey:"f",source:movie,durationMs:120_000);await runtime.waitForRestore()
  XCTAssertNil(runtime.active);XCTAssertEqual(fullReads,0,"No known bank must not cause a full movie scan")
  let candidate=try FilmMaterialFingerprint.candidate(movie)
  XCTAssertEqual(candidate,try FilmMaterialFingerprint.candidate(other))
  try await store.saveForSource(sample(FilmMaterialFingerprint.source(movie)),candidate:candidate)
  runtime.restore(filmKey:"f",source:other,durationMs:120_000);await runtime.waitForRestore()
  XCTAssertEqual(fullReads,1);XCTAssertNil(runtime.active);XCTAssertTrue(runtime.status.contains("不匹配"))
 }

 func testMaterialOnlySubtitleImportDoesNotAnalyzeOrChangePlaybackSubtitles() async throws {
  let movie=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"bank-material",withExtension:"mp4"))
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let subtitle=directory.appendingPathComponent("material-only.srt")
  try Data("1\n00:00:01,000 --> 00:00:03,000\nMaterial evidence only\n\n2\n00:00:20,000 --> 00:00:23,000\nSecond clue\n".utf8).write(to:subtitle)
  let model=TestClient(automaticallyConnect:false)
  model.installCleanupTestSource(movie)
  model.adapter.player.replaceCurrentItem(with:AVPlayerItem(url:movie))
  let previousEnabled=model.externalSubtitles.enabled
  var inferenceCalls=0
  model.plotIntelligence.wholeFilm.available={true}
  model.plotIntelligence.wholeFilm.inference={_,_ in inferenceCalls+=1;return "{}"}
  await model.importFullFilmSubtitleForAI(subtitle)
  await model.plotIntelligence.wholeFilm.waitForAnalysis()
  XCTAssertEqual(model.bankSubtitle?.cues.count,2)
  XCTAssertEqual(model.bankSubtitleSourceLabel,"素材专用备用字幕")
  XCTAssertEqual(inferenceCalls,0,"Importing materials must not start old cloud/local film analysis")
  XCTAssertEqual(model.externalSubtitles.enabled,previousEnabled)
  XCTAssertTrue(model.aiOnlySubtitleImportStatus.contains("不自动调用"))
  model.clearFullFilmSubtitleForAI()
  XCTAssertNil(model.bankSubtitle)
  XCTAssertEqual(model.bankSubtitleSourceLabel,"原片内置字幕（未选备用字幕）")
 }

 func testPlaybackExternalSubtitleOnlyOverridesWhileSelected() async throws {
  let movie=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"bank-material",withExtension:"mp4"))
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let subtitle=directory.appendingPathComponent("playback-spare.srt")
  try Data("1\n00:00:01,000 --> 00:00:03,000\nSelected playback spare\n\n2\n00:00:30,000 --> 00:00:33,000\nSecond cue\n".utf8).write(to:subtitle)
  let model=TestClient(automaticallyConnect:false)
  model.installCleanupTestSource(movie)
  model.adapter.player.replaceCurrentItem(with:AVPlayerItem(url:movie))
  let imported=await model.externalSubtitles.importFile(subtitle)
  XCTAssertTrue(imported)
  XCTAssertEqual(model.bankSubtitle?.cues.first?.text,"Selected playback spare")
  XCTAssertEqual(model.bankSubtitleSourceLabel,"当前播放的外挂字幕")
  model.externalSubtitles.enabled=false
  XCTAssertNil(model.bankSubtitle,"Disabled external subtitle must not override original")
  XCTAssertEqual(model.bankSubtitleSourceLabel,"原片内置字幕（未选备用字幕）")
 }

 func testWithoutSpareSubtitleEmbeddedIsExported() async throws {
  let movie=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"bank-material",withExtension:"mp4"))
  let output=try await Task.detached(priority:.utility){
   try FilmMaterialExporter.create(url:movie,title:"Embedded-only movie",external:nil,allowOCR:true,progress:{_ in})
  }.value
  defer{try? FileManager.default.removeItem(at:output.deletingLastPathComponent())}
  let entries=try zipEntries(Data(contentsOf:output))
  let srt=String(decoding:try XCTUnwrap(entries["subtitles/whole-film.srt"]),as:UTF8.self)
  XCTAssertTrue(srt.contains("INTERNAL_END"))
 }

}
