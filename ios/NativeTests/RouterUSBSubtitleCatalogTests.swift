import XCTest
import Foundation
@testable import TogetherPoC

final class RouterUSBSubtitleCatalogTests:XCTestCase {
 private let movie=URL(string:"https://router.example/media/usb-mount/movie.mkv?expires=12345&sig=validtoken")!
 func testSignedMovieGetsManifestQueryWithoutChangingSignature() {
  let url=RouterUSBSubtitleCatalog.catalogURL(for:movie)
  XCTAssertNotNil(url)
  let parts=URLComponents(url:url!,resolvingAgainstBaseURL:false)!
  XCTAssertEqual(parts.queryItems?.first(where:{$0.name=="subtitles"})?.value,"1")
  XCTAssertEqual(parts.queryItems?.first(where:{$0.name=="sig"})?.value,"validtoken")
  XCTAssertEqual(parts.queryItems?.first(where:{$0.name=="expires"})?.value,"12345")
  XCTAssertNil(RouterUSBSubtitleCatalog.catalogURL(for:URL(fileURLWithPath:"/tmp/movie.mkv")))
  XCTAssertNil(RouterUSBSubtitleCatalog.catalogURL(for:URL(string:"https://router.example/media/usb-mount/movie.mkv")!))
  XCTAssertNil(RouterUSBSubtitleCatalog.catalogURL(for:URL(string:"ftp://router.example/media/usb-mount/movie.mkv?expires=1&sig=2")!))
 }
 func testOnlySignedSameFolderSubtitlesAppear() throws {
  let rows:[String:Any]=["subtitles":[
   ["name":"movie.zh.srt","url":"/media/usb-mount/movie.zh.srt?expires=12345&sig=validtoken"],
   ["name":"movie.en.ass","url":"/media/usb-mount/movie.en.ass?expires=12345&sig=validtoken"],
   ["name":"movie.en.ass","url":"/media/usb-mount/movie.en.ass?expires=12345&sig=validtoken"],
   ["name":"evil.vtt","url":"https://elsewhere.invalid/media/usb-mount/evil.vtt?expires=12345&sig=validtoken"],
   ["name":"other.srt","url":"/media/usb-mount/unrelated/other.srt?expires=12345&sig=validtoken"],
   ["name":"unsigned.srt","url":"/media/usb-mount/unsigned.srt"],
   ["name":"movie.exe","url":"/media/usb-mount/movie.exe?expires=12345&sig=validtoken"],
   ["name":"../escape.srt","url":"/media/escape.srt?expires=12345&sig=validtoken"]
  ]]
  let options=try RouterUSBSubtitleCatalog.decodeCatalog(JSONSerialization.data(withJSONObject:rows),movie:movie)
  XCTAssertEqual(options.map(\.name),["movie.en.ass","movie.zh.srt"])
  XCTAssertTrue(options.allSatisfy{$0.url.host=="router.example"})
 }
 func testInvalidCatalogRejected() {
  XCTAssertThrowsError(try RouterUSBSubtitleCatalog.decodeCatalog(Data("not json".utf8),movie:movie))
  XCTAssertThrowsError(try RouterUSBSubtitleCatalog.decodeCatalog(Data(#"{"subtitles":"bad"}"#.utf8),movie:movie))
 }
 func testSubtitleFilenameKeepsUnicodeSpacesAndTime() throws {
  let json=#"{"subtitles":[{"name":"movie 简体中文.srt","url":"/media/usb-mount/movie%20%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87.srt?expires=12345&sig=validtoken"}]}"#
  let items=try RouterUSBSubtitleCatalog.decodeCatalog(Data(json.utf8),movie:movie)
  XCTAssertEqual(items.map(\.name),["movie 简体中文.srt"])
  let srt="1\n00:00:01,000 --> 00:00:03,000\n第一句话\n\n2\n00:00:05,000 --> 00:00:06,000\n第二句话\n"
  let document=try SubtitleParser.parse(Data(srt.utf8),extension:items[0].url.pathExtension)
  XCTAssertEqual(document.cues.count,2)
  XCTAssertEqual(document.cues.first?.text,"第一句话")
 }
}
