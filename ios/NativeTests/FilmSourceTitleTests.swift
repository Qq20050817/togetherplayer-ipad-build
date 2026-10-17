import XCTest
@testable import TogetherPoC

@MainActor final class FilmSourceTitleTests:XCTestCase {
 private func room(_ url:String,title:String)->[String:Any] {
  let t:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  return ["roomId":"film-title-room","hostId":"someone-else",
          "mediaUrl":url,"title":title,"version":1,"duration":1000,
          "executeAt":0,"state":"paused","position":0,"updatedAt":0,
          "playbackRate":1,"before":t]
 }
 private func client()->TestClient {
  TestClient(automaticallyConnect:false,messageSender:{_ in})
 }
 func testUSBVideoTitleIgnoresSignedURLAndExtension() {
  let raw="http://usb.example.invalid:49185/media/usb-id/Extreme.Job.2019.KOREAN.1080p.BluRay.REMUX.mkv?expires=999&sig=secret"
  XCTAssertEqual(FilmSourceTitle.fromMediaURL(raw),"Extreme.Job.2019.KOREAN.1080p.BluRay.REMUX")
  XCTAssertEqual(FilmSourceTitle.fromMediaURL("https://usb.example.invalid/media/%E6%9E%81%E9%99%90%E8%81%8C%E4%B8%9A.mp4?sig=a"),"极限职业")
  XCTAssertNil(FilmSourceTitle.fromMediaURL("https://usb.example.invalid/health?sig=a"))
  XCTAssertNil(FilmSourceTitle.fromMediaURL("https://usb.example.invalid/watch/master.m3u8"))
 }
 func testManuallyEditedRoomMovieLinkUpdatesDraftName() {
  let model=client();model.movieTitle="上一部电影"
  let url="https://usb.example.invalid/media/usb-id/New.Film.2026.mkv?sig=xyz"
  model.updateRoomMediaDraft(url)
  XCTAssertEqual(model.mediaURL,url,"Signed URL must remain unchanged")
  XCTAssertEqual(model.movieTitle,"New.Film.2026")
  model.movieTitle="我自己设置的片名"
  XCTAssertEqual(model.movieTitle,"我自己设置的片名")
  model.updateRoomMediaDraft("not a movie URL")
  XCTAssertEqual(model.movieTitle,"我自己设置的片名")
 }
 func testLocalURLShowsSelectedFilmInsteadOfStaleRoomTitle() async throws {
  let model=client()
  model.receive(["type":"WELCOME","room":room("https://example.invalid/older-film.mp4",title:"旧影片")],t4:0)
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:dir)}
  let film=dir.appendingPathComponent("新影片.2026.mp4")
  try TestMovieFixture.mp4.write(to:film)
  model.beginLocalFileSelection();model.useLocalFile(film)
  for _ in 0..<150 {
   if model.usingLocalFile {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertTrue(model.usingLocalFile)
  XCTAssertEqual(model.playbackTitle,"新影片.2026")
  XCTAssertEqual(model.movieTitle,"新影片.2026","Current source title should update the editable name field")
  XCTAssertEqual(model.roomTitle,"旧影片","Guest cannot rename shared room metadata")
 }
 func testLocalUSBOverrideUsesOwnFilenameWithoutChangingRoomTitle() {
  let model=client()
  model.receive(["type":"WELCOME","room":room("https://example.invalid/room.mp4",title:"房间原片")],t4:0)
  model.localMediaURL="https://usb.example.invalid/media/usb-id/Selected.USB.Movie.mkv?sig=q"
  model.applyLocalSource()
  XCTAssertEqual(model.playbackTitle,"Selected.USB.Movie")
  XCTAssertEqual(model.movieTitle,"Selected.USB.Movie")
  XCTAssertEqual(model.roomTitle,"房间原片")
  XCTAssertEqual(model.mediaURL,"https://example.invalid/room.mp4")
 }
}
