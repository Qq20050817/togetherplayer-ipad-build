import XCTest
@testable import TogetherPoC

@MainActor final class WatchMemoryTests:XCTestCase {
 func testCatalogAndDeletedSourceSurviveRelaunch() throws {
  let name="watch-tests-"+UUID().uuidString,defaults=UserDefaults(suiteName:"watch-tests-"+UUID().uuidString)!
  defer {defaults.removeObject(forKey:"watch-memory-v1")}
  let memory=WatchMemory(defaults:defaults,onlineEnabled:false)
  XCTAssertGreaterThanOrEqual(memory.catalog.count,48)
  let file=FileManager.default.temporaryDirectory.appendingPathComponent(name+".mkv")
  try Data([1,2,3]).write(to:file)
  memory.record("The.Guilty.2018.DANISH.1080p.BluRay.mkv")
  XCTAssertEqual(memory.records.first?.id,"guilty2018")
  memory.feedback("guilty2018",rating:5,tags:["悬疑","低血腥"],note:"喜欢电话推理")
  try FileManager.default.removeItem(at:file)
  let restored=WatchMemory(defaults:defaults,onlineEnabled:false)
  XCTAssertEqual(restored.records.count,1)
  XCTAssertEqual(restored.records.first?.rating,5)
  XCTAssertEqual(restored.records.first?.note,"喜欢电话推理")
  XCTAssertFalse(restored.suggestions.contains{$0.id=="guilty2018"})
  restored.record("罪人")
  XCTAssertEqual(restored.records.count,1)
 }
 func testColdStartAndRemakeIdentity() {
  XCTAssertTrue(FilmTaste.suggestions([],catalog:[],dismissed:[]).isEmpty)
  let f=WatchFilm(id:"g",title:"罪人",year:2018,aliases:["The Guilty"],tags:["悬疑"],synopsis:"电话案件")
  XCTAssertNil(FilmTaste.match("The Guilty 2021",catalog:[f]))
  XCTAssertEqual(FilmTaste.match("The.Guilty.2018.DANISH.1080p.mkv",catalog:[f])?.id,"g")
 }
 func testRatingsChangeRankingWithoutCallingUnratedLiked() {
  let mystery=WatchFilm(id:"m",title:"悬疑候选",year:2000,aliases:[],tags:["悬疑"],synopsis:"查案")
  let comedy=WatchFilm(id:"c",title:"喜剧候选",year:2001,aliases:[],tags:["喜剧"],synopsis:"日常")
  let liked=WatchRecord(id:"seen",title:"看过的电影",completedAt:Date(),rating:5,tags:["悬疑"],note:"")
  XCTAssertEqual(FilmTaste.suggestions([liked],catalog:[mystery,comedy],dismissed:[]).first?.id,"m")
  var disliked=liked;disliked.rating=1
  XCTAssertEqual(FilmTaste.suggestions([disliked],catalog:[mystery,comedy],dismissed:[]).first?.id,"c")
  var unrated=liked;unrated.rating=nil
  XCTAssertFalse(FilmTaste.suggestions([unrated],catalog:[mystery],dismissed:[])[0].reason.contains("较高评价"))
  XCTAssertTrue(FilmTaste.suggestions([liked],catalog:[mystery],dismissed:["m"]).isEmpty)
 }
 func testScrubBufferingAndSourceSwitchNeverComplete() {
  var c=WatchCoverage()
  XCTAssertFalse(c.sample(source:"a",position:0,duration:100,playing:true,now:0))
  XCTAssertFalse(c.sample(source:"a",position:100,duration:100,playing:true,now:1))
  for t in 2...100 {XCTAssertFalse(c.sample(source:"a",position:100,duration:100,playing:false,now:Double(t)))}
  XCTAssertFalse(c.sample(source:"b",position:100,duration:100,playing:true,now:101))
 }
 func testContinuousPlaybackCompletesAtEnding() {
  var c=WatchCoverage()
  for t in 0...96 {XCTAssertFalse(c.sample(source:"a",position:Double(t),duration:100,playing:true,now:Double(t)))}
  XCTAssertTrue(c.sample(source:"a",position:97,duration:100,playing:true,now:97))
 }
 func testRepeatedShortSectionDoesNotInflateCoverage() {
  var c=WatchCoverage()
  for lap in 0..<5 {for p in 0...20 {_=c.sample(source:"a",position:Double(p),duration:100,playing:true,now:Double(lap*21+p))}}
  XCTAssertFalse(c.sample(source:"a",position:100,duration:100,playing:true,now:106))
 }
 func testCorruptArchiveRemainsUntouched() {
  let defaults=UserDefaults(suiteName:"corrupt-"+UUID().uuidString)!
  let data=Data("broken archive".utf8);defaults.set(data,forKey:"watch-memory-v1")
  let memory=WatchMemory(defaults:defaults,onlineEnabled:false)
  XCTAssertFalse(memory.storageError.isEmpty)
  memory.record("罪人")
  XCTAssertEqual(defaults.data(forKey:"watch-memory-v1"),data)
  defaults.removeObject(forKey:"watch-memory-v1")
 }
}
