import XCTest
import Foundation
import AVFoundation
@testable import TogetherPoC

final class RouterUSBSubtitleCatalogTests:XCTestCase {
 private let movie=URL(string:"https://router.example/media/usb-mount/movie.mkv?expires=12345&sig=validtoken")!
 func testUnsignedUSBMovieAcceptsOnlySameFolderSubtitles() throws {
  let film=URL(string:"http://router.example:49185/usb-files/高清/电影.mkv")!
  let endpoint=RouterUSBSubtitleCatalog.catalogURL(for:film)!
  XCTAssertEqual(URLComponents(url:endpoint,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,"1")
  let rows:[String:Any]=["subtitles":[
   ["name":"电影.zh.srt","url":"/usb-files/%E9%AB%98%E6%B8%85/%E7%94%B5%E5%BD%B1.zh.srt"],
   ["name":"电影 [BD] v2.ass","url":"/usb-files/%E9%AB%98%E6%B8%85/%E7%94%B5%E5%BD%B1%20%5BBD%5D%20v2.ass"],
   ["name":"电影.zh.srt","url":"http://another.example:49185/usb-files/高清/电影.zh.srt"],
   ["name":"skip.srt","url":"/usb-files/other/skip.srt"],
   ["name":"bad.exe","url":"/usb-files/高清/bad.exe"]
  ]]
  let result=try RouterUSBSubtitleCatalog.decodeCatalog(JSONSerialization.data(withJSONObject:rows),movie:film)
  XCTAssertEqual(Set(result.map(\.name)),Set(["电影.zh.srt","电影 [BD] v2.ass"]))
 }
 func testActualUSBManifestWithEncodedChineseFolderAndASS() throws {
  let film=URL(string:"http://router.example:49185/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.mkv")!
  let manifest=#"{"subtitles":[{"name":"The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.ass","url":"/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.ass"}]}"#
  let result=try RouterUSBSubtitleCatalog.decodeCatalog(Data(manifest.utf8),movie:film)
  XCTAssertEqual(result.map(\.name),["The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.ass"])
 }
 func testRealRouterUSBManifestAllowsEllipsisInBasename() throws {
  // Observed room URL and subtitle manifest for the current film.
  let film=URL(string:"http://router.example:49185/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/The%20T...1%5D%20v2.mkv")!
  let manifest=#"{"subtitles":[{"name":"The T...1] v2.ass","url":"/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/The%20T...1%5D%20v2.ass"},{"name":"../escape.ass","url":"/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/escape.ass"},{"name":"other.ass","url":"/usb-files/outside/other.ass"}]}"#
  let found=try RouterUSBSubtitleCatalog.decodeCatalog(Data(manifest.utf8),movie:film)
  XCTAssertEqual(found.map(\.name),["The T...1] v2.ass"])
  XCTAssertEqual(found.first?.url.lastPathComponent,"The T...1] v2.ass")
 }
 func testSignedMovieAcceptsRouterAdvertisedUnsignedSibling() throws {
  let signed=URL(string:"https://router.example/media/usb-mount/The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.mkv?expires=12345&sig=validtoken")!
  let manifest=#"{"subtitles":[{"name":"The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.ass","url":"/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.ass"},{"name":"evil.ass","url":"https://other.example/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/evil.ass"},{"name":"evil2.ass","url":"/media/usb-mount/other/evil2.ass?expires=12345&sig=validtoken"}]}"#
  let result=try RouterUSBSubtitleCatalog.decodeCatalog(Data(manifest.utf8),movie:signed)
  XCTAssertEqual(result.map(\.name),["The.Tunnel.to.Summer.2022.BluRay.REMUX.v2.ass"])
 }
 func testUnsignedMovieAcceptsSignedRouterSubtitleAlias() throws {
  let film=URL(string:"https://router.example/usb-files/高清/film.mkv")!
  let manifest=#"{"subtitles":[{"name":"film.ass","url":"/media/usb-mount/film.ass?expires=12345&sig=validtoken"},{"name":"unsigned-signed.ass","url":"/media/usb-mount/other.ass"}]}"#
  let result=try RouterUSBSubtitleCatalog.decodeCatalog(Data(manifest.utf8),movie:film)
  XCTAssertEqual(result.map(\.name),["film.ass"])
 }
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
  let wrongFolder = #"{"subtitles":[{"name":"outside.ass","url":"/media/usb-mount/other/outside.ass?expires=12345&sig=validtoken"}]}"#
  XCTAssertThrowsError(try RouterUSBSubtitleCatalog.decodeCatalog(Data(wrongFolder.utf8),movie:movie))
  XCTAssertNoThrow(try RouterUSBSubtitleCatalog.decodeCatalog(Data(#"{"subtitles":[]}"#.utf8),movie:movie))
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
 @MainActor func testRemoteSubtitleCanBeUsedForPlaybackWithoutImportingLocalFile() {
  let overlay=ExternalSubtitles(player:AVPlayer())
  let document=SubtitleDocument([SubtitleCue(start:1,end:3,text:"第一句话")])
  overlay.installRemote(document,name:"movie.zh.srt")
  XCTAssertTrue(overlay.available)
  XCTAssertTrue(overlay.enabled)
  XCTAssertEqual(overlay.name,"movie.zh.srt")
  XCTAssertNil(overlay.importedFileURL)
  XCTAssertEqual(overlay.completeExternalForAI?.text(at:2),"第一句话")
 }

}
