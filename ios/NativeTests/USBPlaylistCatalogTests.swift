import XCTest
@testable import TogetherPoC

final class USBPlaylistCatalogTests: XCTestCase {
 func testMovieTitleIsReadableAndPlaybackAddressUnchanged() {
  let movie=USBMovie(name:"The.Guilty.2018.DANISH.1080p.BluRay.REMUX.AVC.DTS-HD.MA.5.1-FGT.mkv",
   path:"高速下载/The.Guilty.2018.DANISH.1080p.BluRay.REMUX.AVC.DTS-HD.MA.5.1-FGT.mkv",
   size:21460382029,
   url:"/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/The.Guilty.2018.DANISH.1080p.BluRay.REMUX.AVC.DTS-HD.MA.5.1-FGT.mkv")
  XCTAssertEqual(movie.displayTitle,"The Guilty (2018)")
  XCTAssertFalse(movie.isEpisode)
  XCTAssertEqual(movie.releaseYear,2018)
  XCTAssertEqual(movie.savedMedia?.title,"The Guilty (2018)")
  XCTAssertTrue(movie.savedMedia?.url.contains("/usb-files/")==true)
  XCTAssertFalse(movie.savedMedia?.url.contains("sig=")==true)
 }
 func testAnimeSeasonAndEpisodesAreRecognized() {
  let cartoon=USBMovie(name:"第十二季  台配  001-003 小葵的王子哦 采梨子哦 猜拳老爸哦.mp4",
   path:"高速下载/第十二季  台配  001-003 小葵的王子哦 采梨子哦 猜拳老爸哦.mp4",
   size:105542685,url:"/usb-files/%E9%AB%98%E9%80%9F%E4%B8%8B%E8%BD%BD/test.mp4")
  XCTAssertTrue(cartoon.isEpisode)
  XCTAssertTrue(cartoon.displayTitle.contains("第十二季"))
  XCTAssertTrue(cartoon.displayTitle.contains("001-003"))
 }
 func testShareableMovieLinkIsBoundToTrustedRouterAndExtension() {
  XCTAssertNil(USBMovieLibrary.playableURL("https://elsewhere.invalid/usb-files/film.mkv"))
  XCTAssertNil(USBMovieLibrary.playableURL("/usb-files/film.srt"))
  XCTAssertNil(USBMovieLibrary.playableURL("/usb-files/film.mkv?sig=abc"))
  XCTAssertNotNil(USBMovieLibrary.playableURL("/usb-files/film.mkv"))
 }
}
