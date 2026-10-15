import XCTest
@testable import TogetherPoC

final class WatchedFileCleanupTests:XCTestCase {
 private func fixture(_ body:(URL)throws->Void)throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:root)}
  try body(root)
 }
 private func file(_ name:String,in root:URL,_ value:String="movie")throws->URL {
  let url=root.appendingPathComponent(name);try Data(value.utf8).write(to:url);return url
 }
 func testDeleteOnlyReviewedMovieAndAssociatedSubtitles()throws {
  try fixture {root in
   let movie=try file("Movie.mkv",in:root)
   _=try file("Movie.zh-Hans.srt",in:root)
   _=try file("Movie.en.forced.ass",in:root)
   let other=try file("Movie.part2.mkv",in:root)
   let otherSubtitle=try file("Movie.part2.srt",in:root)
   let generic=try file("unrelated.srt",in:root)
   let plan=try WatchedFileCleanup.plan(source:movie,folder:root)
   XCTAssertEqual(Set(plan.files.map(\.name)),["Movie.mkv","Movie.zh-Hans.srt","Movie.en.forced.ass"])
   let result=WatchedFileCleanup.remove(plan.files,in:root)
   XCTAssertEqual(result.deleted.count,3);XCTAssertTrue(result.failed.isEmpty)
   for url in [other,otherSubtitle,generic] {XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))}
  }
 }
 func testReplacedFileIsRetainedAfterPreview()throws {
  try fixture {root in
   let movie=try file("Movie.mkv",in:root)
   let plan=try WatchedFileCleanup.plan(source:movie,folder:root)
   try FileManager.default.removeItem(at:movie)
   _=try file("Movie.mkv",in:root,"replacement is different")
   let result=WatchedFileCleanup.remove(plan.files,in:root)
   XCTAssertTrue(result.deleted.isEmpty);XCTAssertEqual(result.failed.count,1)
   XCTAssertEqual(try String(contentsOf:movie,encoding:.utf8),"replacement is different")
  }
 }
 func testWrongFolderWithIdenticalFileNameCannotAuthorizeDeletion()throws {
  try fixture {root in
   let movie=try file("Movie.mkv",in:root)
   let other=root.appendingPathComponent("other")
   try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
   _=try file("Movie.mkv",in:other)
   XCTAssertThrowsError(try WatchedFileCleanup.plan(source:movie,folder:other))
  }
 }
 func testSymbolicSubtitleCannotDeleteItsTarget()throws {
  try fixture {root in
   let movie=try file("Movie.mkv",in:root)
   let target=try file("keep.srt",in:root)
   let link=root.appendingPathComponent("Movie.srt")
   try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
   let plan=try WatchedFileCleanup.plan(source:movie,folder:root)
   XCTAssertEqual(plan.files.count,1)
   XCTAssertThrowsError(try CleanupFileStamp.read(link))
  }
 }
 func testExplicitImportedSubtitleAndUncheckedMovieAreIndependent()throws {
  try fixture {root in
   let movie=try file("Movie.mkv",in:root)
   let imported=try file("中文字幕.srt",in:root)
   let plan=try WatchedFileCleanup.plan(source:movie,folder:root,importedSubtitle:imported)
   let result=WatchedFileCleanup.remove(plan.files.filter{!$0.isMovie},in:root)
   XCTAssertEqual(result.deleted,["中文字幕.srt"])
   XCTAssertTrue(FileManager.default.fileExists(atPath:movie.path))
  }
 }
 func testForeignFolderAndRemoteURLAreRejected()throws {
  try fixture {root in
   let movie=try file("Movie.mkv",in:root)
   let plan=try WatchedFileCleanup.plan(source:movie,folder:root)
   let wrong=root.appendingPathComponent("other")
   let result=WatchedFileCleanup.remove(plan.files,in:wrong)
   XCTAssertTrue(result.deleted.isEmpty);XCTAssertEqual(result.failed.count,1)
   XCTAssertThrowsError(try WatchedFileCleanup.plan(source:URL(string:"https://example.com/Movie.mkv")!,folder:root))
  }
 }
}
