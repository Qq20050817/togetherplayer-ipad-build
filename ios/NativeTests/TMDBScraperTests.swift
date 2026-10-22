import XCTest
@testable import TogetherPoC

final class TMDBScraperTests:XCTestCase {
 private func movie(_ name:String)->USBMovie {
  USBMovie(name:name,path:name,size:100,url:"/usb-files/"+name)
 }
 private func row(_ title:String,_ year:String,id:Int)->TMDBCandidate {
  TMDBCandidate(id:id,title:title,name:nil,originalTitle:nil,originalName:nil,
   releaseDate:year+"-02-01",firstAirDate:nil,posterPath:"/test.jpg")
 }
 func testSameNameRemakeMustMatchOriginalYear() {
  let film=movie("The.Guilty.2018.DANISH.1080p.BluRay.mkv")
  let original=row("罪人","2018",id:1)
  let remake=row("罪人","2021",id:2)
  let known=WatchFilm(id:"guilty2018",title:"罪人",year:2018,
   aliases:["The Guilty","Den skyldige"],tags:[],synopsis:"丹麦电影")
  XCTAssertTrue(TMDBMatcher.aliases(for:film,catalog:[known]).contains("罪人"))
  XCTAssertEqual(TMDBMatcher.score(original,movie:film,catalog:[known]),115)
  XCTAssertEqual(TMDBMatcher.score(remake,movie:film,catalog:[known]),-1)
  XCTAssertFalse(TMDBMatcher.aliases(for:film,catalog:[]).contains("罪人"))
  XCTAssertNil(TMDBMatcher.exactMatch([remake,original],movie:film,catalog:[]))
  XCTAssertEqual(TMDBMatcher.exactMatch([remake,original],movie:film,catalog:[known])?.id,1)
 }
 func testWrongOrAmbiguousTitleRequiresManualConfirmation() {
  let film=movie("Barking.Dogs.Never.Bite.2000.KOREAN.mkv")
  XCTAssertNil(TMDBMatcher.exactMatch([row("随便一部电影","2000",id:9)],movie:film))
  XCTAssertNil(TMDBMatcher.exactMatch([row("绑架门口狗","2000",id:1),row("绑架门口狗","2000",id:2)],movie:film))
 }
 func testUnknownMovieWithMissingYearCannotSilentlyPickRemake() {
  let film=movie("The.Guilty.2018.DANISH.mkv")
  XCTAssertNil(TMDBMatcher.exactMatch([row("罪人","2021",id:2)],movie:film))
 }
 func testArtworkURLsOnlyUseTMDBImageHostAndSafePath() {
  XCTAssertEqual(TMDBImage.url("/one.jpg")?.host,"image.tmdb.org")
  XCTAssertNil(TMDBImage.url("https://bad.example/test.jpg"))
  XCTAssertNil(TMDBImage.url("/../bad.jpg"))
  XCTAssertNil(TMDBImage.url("/bad.svg"))
 }
 func testSearchResponseDecodesTMDBSnakeCase() throws {
  let json=Data(#"{"id":99,"title":"罪人","original_title":"Den skyldige","release_date":"2018-06-14","poster_path":"/a.jpg"}"#.utf8)
  let decoder=JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  let info=try decoder.decode(TMDBCandidate.self,from:json)
  XCTAssertEqual(info.year,2018)
  XCTAssertEqual(info.original,"Den skyldige")
  XCTAssertEqual(info.posterURL?.host,"image.tmdb.org")
 }
 func testCachedRecordSurvivesSerialization() throws {
  let record=TMDBInfo(id:99,isTV:false,title:"罪人",originalTitle:"Den skyldige",year:2018,
    overview:"紧急接线员接到求救电话",posterPath:"/a.jpg",backdropPath:nil,
    genres:["惊悚"],cast:["演员甲"],director:["导演甲"],runtime:85,voteAverage:7.6)
  let decoded=try JSONDecoder().decode(TMDBInfo.self,from:JSONEncoder().encode(record))
  XCTAssertEqual(decoded.title,"罪人")
  XCTAssertEqual(decoded.year,2018)
  XCTAssertEqual(decoded.runtime,85)
 }
}
