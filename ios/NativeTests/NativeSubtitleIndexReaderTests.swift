import XCTest
@testable import TogetherPoC

final class NativeSubtitleIndexReaderTests:XCTestCase {
 func testOnlySelectedSubtitleRenditionIsIndexedAndCannotCrossOrigin() throws {
  let master=try XCTUnwrap(URL(string:"http://127.0.0.1:8123/movie/master.m3u8"))
  let manifest="""
  #EXTM3U
  #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Chinese",URI="chinese/index.m3u8"
  #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",URI="english/index.m3u8"
  #EXT-X-STREAM-INF:BANDWIDTH=9000000,SUBTITLES="subs"
  movie.m3u8
  """
  XCTAssertEqual(NativeSubtitleIndexReader.subtitleURL(master:manifest,base:master,track:0)?.path,"/movie/chinese/index.m3u8")
  XCTAssertEqual(NativeSubtitleIndexReader.subtitleURL(master:manifest,base:master,track:1)?.path,"/movie/english/index.m3u8")
  XCTAssertNil(NativeSubtitleIndexReader.subtitleURL(master:manifest,base:master,track:2))
  XCTAssertNil(NativeSubtitleIndexReader.subtitleURL(
   master:"#EXT-X-MEDIA:TYPE=SUBTITLES,URI=\"https://another.example/secret.vtt\"",
   base:master,track:0))
 }
 func testSegmentPositionsAndLocalRelativeCueTimes() throws {
  let playlist=try XCTUnwrap(URL(string:"http://127.0.0.1:8123/sub/index.m3u8"))
  let body="""
  #EXTM3U
  #EXTINF:12.0,
  first.vtt
  #EXTINF:12.0,
  second.vtt
  #EXT-X-ENDLIST
  """
  let parts=try XCTUnwrap(NativeSubtitleIndexReader.segments(playlist:body,base:playlist))
  XCTAssertEqual(parts.count,2)
  XCTAssertEqual(parts[1].start,12,accuracy:0.001)
  let local="""
  WEBVTT

  00:00:02.000 --> 00:00:04.000
  发现新线索
  """
  let parsed=NativeSubtitleIndexReader.parseSegment(local,segment:parts[1])
  XCTAssertEqual(parsed.count,1)
  XCTAssertEqual(parsed[0].start,14,accuracy:0.001)
  XCTAssertEqual(parsed[0].end,16,accuracy:0.001)
 }
 func testTimestampMapAndDuplicateSegmentBoundaryAreHandled() throws {
  let url=try XCTUnwrap(URL(string:"http://127.0.0.1:8123/sub/part.vtt"))
  let part=NativeSubtitleIndexReader.Segment(url:url,start:10,duration:6)
  let vtt="""
  WEBVTT
  X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:900000

  00:00:01.000 --> 00:00:03.000
  这个人隐瞒了什么
  """
  let cues=NativeSubtitleIndexReader.parseSegment(vtt,segment:part)
  XCTAssertEqual(cues.first?.start,11)
  XCTAssertEqual(cues.first?.end,13)
  let duplicate=NativeSubtitleIndexReader.merge(cues+cues)
  XCTAssertEqual(duplicate?.cues.count,1)
 }
}
