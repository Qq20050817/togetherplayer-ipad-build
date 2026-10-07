import XCTest
@testable import TogetherPoC

final class WatchQualityTests: XCTestCase {
 override func tearDown() {UserDefaults.standard.removeObject(forKey:"credentials");super.tearDown()}
 func testRemainingTimeIncludesHoursAndHandlesSeekingAndUnknownDuration() {
  XCTAssertEqual(PlaybackTime.remaining(duration:9030,position:3600),"剩余 1:30:30")
  XCTAssertEqual(PlaybackTime.remaining(duration:600,position:61),"剩余 08:59")
  XCTAssertEqual(PlaybackTime.remaining(duration:600,position:601),"剩余 00:00")
  XCTAssertEqual(PlaybackTime.remaining(duration:60,position:-1),"剩余 01:00")
  XCTAssertEqual(PlaybackTime.remaining(duration:0,position:0),"剩余 --:--")
  XCTAssertEqual(PlaybackTime.remaining(duration:.infinity,position:0),"剩余 --:--")
  XCTAssertEqual(PlaybackTime.remaining(duration:60,position:.nan),"剩余 --:--")
 }
 func testQualityNamesAreOnlySuggestionsAndPreserveCutYearAndEpisode() {
  XCTAssertTrue(MovieVariantPolicy.namesSuggestSameMovie("Movie.2020.mkv","【高清】Movie.2020_720p.mp4"))
  XCTAssertTrue(MovieVariantPolicy.namesSuggestSameMovie("电影.mkv","电影.mkv_1080p.mp4"))
  XCTAssertTrue(MovieVariantPolicy.namesSuggestSameMovie("电影.mp4","电影（流畅）.mp4"))
  XCTAssertFalse(MovieVariantPolicy.namesSuggestSameMovie("Movie.2020.mkv","Movie.2021_720p.mp4"))
  XCTAssertFalse(MovieVariantPolicy.namesSuggestSameMovie("Movie.extended.mkv","Movie_720p.mp4"))
  XCTAssertFalse(MovieVariantPolicy.namesSuggestSameMovie("Show.S01E01.mkv","Show.S01E02_720p.mp4"))
  XCTAssertFalse(MovieVariantPolicy.namesSuggestSameMovie("",""))
 }
 func testVariantWaitsForDurationAndChecksOffsetAndFiveSecondBoundary() {
  XCTAssertEqual(MovieVariantPolicy.duration(localMs:0,offsetMs:0,roomMs:120000),.waiting)
  XCTAssertEqual(MovieVariantPolicy.duration(localMs:120000,offsetMs:0,roomMs:0),.waiting)
  XCTAssertEqual(MovieVariantPolicy.duration(localMs:.nan,offsetMs:0,roomMs:120000),.waiting)
  XCTAssertEqual(MovieVariantPolicy.duration(localMs:128000,offsetMs:8000,roomMs:120000),.compatible)
  XCTAssertEqual(MovieVariantPolicy.duration(localMs:125000,offsetMs:0,roomMs:120000),.compatible)
  XCTAssertEqual(MovieVariantPolicy.duration(localMs:125001,offsetMs:0,roomMs:120000),.different)
 }
 @MainActor func testBaiduVariantRequiresConfirmationAndDoesNotChangeRoomMedia() throws {
  var sent:[[String:Any]]=[]
  let model=try client(host:false,sender:{sent.append($0)})
  let media=reference();model.receive(["type":"WELCOME","room":room(media:media)],t4:0)
  let file=BaiduFile(id:1,name:"Movie_720p.mp4",path:"/Movie_720p.mp4",size:1000,fingerprint:String(repeating:"b",count:32),isDirectory:false)
  let url=URL(string:"https://cdn.baidupcs.com/movie.mp4")!
  XCTAssertFalse(model.useBaiduSource(url,file:file))
  XCTAssertTrue(model.useBaiduSource(url,file:file,confirmedRoomID:"quality-room",confirmedMediaURL:media))
  XCTAssertTrue(model.usingDifferentQuality);XCTAssertEqual(model.variantDurationCheck,.waiting)
  XCTAssertEqual(model.engine.room?.mediaUrl,media)
  XCTAssertFalse(sent.contains {$0["type"] as? String=="ROOM_MEDIA"})
  model.clearBaiduSource();XCTAssertFalse(model.usingDifferentQuality)
 }
 @MainActor func testVariantRejectsChangedRoomAndUntrustedURL() throws {
  let model=try client(host:false);let media=reference()
  model.receive(["type":"WELCOME","room":room(media:media)],t4:0)
  let file=BaiduFile(id:1,name:"Movie_720p.mp4",path:"/movie.mp4",size:1000,fingerprint:String(repeating:"b",count:32),isDirectory:false)
  XCTAssertFalse(model.useBaiduSource(URL(string:"https://cdn.baidupcs.com/movie.mp4")!,file:file,confirmedRoomID:"old-room",confirmedMediaURL:media))
  XCTAssertFalse(model.useBaiduSource(URL(string:"https://untrusted.example/movie.mp4")!,file:file,confirmedRoomID:"quality-room",confirmedMediaURL:media))
  XCTAssertFalse(model.usingDifferentQuality)
 }
 @MainActor func testHostVariantDoesNotPublishReplacement() throws {
  var sent:[[String:Any]]=[];let model=try client(host:true,sender:{sent.append($0)})
  let media=reference();model.receive(["type":"WELCOME","room":room(media:media)],t4:0)
  let file=BaiduFile(id:1,name:"Movie_480p.mp4",path:"/movie.mp4",size:1000,fingerprint:String(repeating:"b",count:32),isDirectory:false)
  XCTAssertTrue(model.useBaiduSource(URL(string:"https://cdn.baidupcs.com/movie.mp4")!,file:file,confirmedRoomID:"quality-room",confirmedMediaURL:media))
  XCTAssertTrue(model.usingDifferentQuality)
  XCTAssertFalse(sent.contains {$0["type"] as? String=="ROOM_MEDIA"})
 }
 @MainActor func testLocalVariantPromptsBeforeMatchingAndCanBeCancelled() async throws {
  let model=try client(host:false);let media=reference();model.receive(["type":"WELCOME","room":room(media:media)],t4:0)
  let url=FileManager.default.temporaryDirectory.appendingPathComponent("Movie_720p-"+UUID().uuidString+".mp4")
  try Data("different encode".utf8).write(to:url);defer {try? FileManager.default.removeItem(at:url)}
  model.beginLocalFileSelection();model.useLocalFile(url)
  for _ in 0..<100 {if model.localQualityCandidate != nil {break};try await Task.sleep(nanoseconds:10_000_000)}
  XCTAssertNotNil(model.localQualityCandidate);XCTAssertFalse(model.usingDifferentQuality)
  model.confirmLocalQuality()
  for _ in 0..<100 {if model.usingDifferentQuality {break};try await Task.sleep(nanoseconds:10_000_000)}
  XCTAssertTrue(model.usingDifferentQuality);XCTAssertEqual(model.variantDurationCheck,.waiting)
  XCTAssertEqual(model.engine.room?.mediaUrl,media)
  model.clearLocalFileSource();XCTAssertFalse(model.usingDifferentQuality)
  model.beginLocalFileSelection();model.useLocalFile(url)
  for _ in 0..<100 {if model.localQualityCandidate != nil {break};try await Task.sleep(nanoseconds:10_000_000)}
  model.cancelLocalQuality();XCTAssertNil(model.localQualityCandidate);XCTAssertFalse(model.usingLocalFile)
 }
 @MainActor func testLocalConfirmationCannotCrossRoomMediaChange() async throws {
  let model=try client(host:false);model.receive(["type":"WELCOME","room":room(media:reference())],t4:0)
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try Data("different encode".utf8).write(to:url);defer {try? FileManager.default.removeItem(at:url)}
  model.beginLocalFileSelection();model.useLocalFile(url)
  for _ in 0..<100 {if model.localQualityCandidate != nil {break};try await Task.sleep(nanoseconds:10_000_000)}
  XCTAssertNotNil(model.localQualityCandidate)
  model.receive(["type":"STATE","room":room(media:BaiduMediaReference.create(fingerprint:String(repeating:"c",count:32),size:9000)!.value)],t4:0)
  model.confirmLocalQuality();XCTAssertFalse(model.usingDifferentQuality);XCTAssertFalse(model.usingLocalFile)
 }
 @MainActor func testHostMismatchedVariantPreservesCanonicalDurationAndStaysUnready() async throws {
  var sent:[[String:Any]]=[];let model=try client(host:true,sender:{sent.append($0)})
  try LocalPickerUITestFixture.install(into:model)
  let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LOCAL-PICKER-TEST.MP4")
  let media=reference();model.receive(["type":"WELCOME","room":room(media:media)],t4:0)
  model.beginLocalFileSelection();model.useLocalFile(url)
  for _ in 0..<100 {if model.localQualityCandidate != nil {break};try await Task.sleep(nanoseconds:10_000_000)}
  let reviewed=try XCTUnwrap(model.localQualityCandidate)
  // Exercise dismissal-before-action as well as the real player's duration.
  model.cancelLocalQuality();model.confirmLocalQuality(reviewed)
  for _ in 0..<500 {
   if model.adapter.duration>0,sent.contains(where:{$0["type"] as? String=="PLAYER_STATUS"}) {break}
   try await Task.sleep(nanoseconds:10_000_000)
  }
  XCTAssertTrue(model.usingDifferentQuality);XCTAssertGreaterThan(model.adapter.duration,0)
  XCTAssertEqual(model.variantDurationCheck,.different)
  let statuses=sent.filter {$0["type"] as? String=="PLAYER_STATUS"}.compactMap {$0["data"] as? [String:Any]}
  XCTAssertFalse(statuses.isEmpty)
  XCTAssertTrue(statuses.allSatisfy {$0["ready"] as? Bool==false})
  XCTAssertTrue(statuses.allSatisfy {$0["duration"] as? Double==120000})
  XCTAssertEqual(model.adapter.player.rate,0)
  model.clearLocalFileSource()
 }
 @MainActor private func client(host:Bool,sender: @escaping ([String:Any])->Void = {_ in}) throws -> TestClient {
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:["roomId":"quality-room","userId":host ? "host" : "guest","token":String(repeating:"a",count:64)]),forKey:"credentials")
  return TestClient(automaticallyConnect:false,messageSender:sender)
 }
 private func reference() -> String {BaiduMediaReference.create(fingerprint:String(repeating:"a",count:32),size:2000)!.value}
 private func room(media:String) -> [String:Any] {
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  return ["roomId":"quality-room","hostId":"host","title":"Movie.mkv","mediaUrl":media,"duration":120000,"version":1,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]
 }
}
