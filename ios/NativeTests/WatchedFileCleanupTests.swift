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
 func testOriginalAndImportCopyAreBothReviewedAndDeleted()throws {
  try fixture {root in
   let original=root.appendingPathComponent("Original"),copies=root.appendingPathComponent("Copy")
   for folder in [original,copies] {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
   let movie=try file("Movie.mkv",in:original,"identical full movie bytes")
   let copy=try file("Movie.mkv",in:copies,"identical full movie bytes")
   let originalSubtitle=try file("Movie.zh-Hans.srt",in:original)
   let copySubtitle=try file("Movie.zh-Hans.srt",in:copies)
   let keep=try file("Other.srt",in:original)
   let plan=try WatchedFileCleanup.planOriginalAndCopy(source:copy,folder:original)
   XCTAssertEqual(plan.files.count,2);XCTAssertEqual(plan.appCopyFiles.count,2)
   let result=WatchedFileCleanup.remove(plan.allFiles,from:plan)
   XCTAssertEqual(result.deleted.count,4);XCTAssertTrue(result.failed.isEmpty)
   for url in [movie,copy,originalSubtitle,copySubtitle] {XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))}
   XCTAssertTrue(FileManager.default.fileExists(atPath:keep.path))
  }
 }
 func testSameNameAndSizeButDifferentContentCannotDeleteOriginal()throws {
  try fixture {root in
   let original=root.appendingPathComponent("Original"),copies=root.appendingPathComponent("Copy")
   for folder in [original,copies] {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
   let movie=try file("Movie.mkv",in:original,"abcXdef")
   let copy=try file("Movie.mkv",in:copies,"abcYdef")
   XCTAssertThrowsError(try WatchedFileCleanup.planOriginalAndCopy(source:copy,folder:original))
   for url in [movie,copy] {XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))}
  }
 }
 func testSilentNoOpDeletionCannotReportSuccess()throws {
  try fixture {root in
   let movie=try file("Movie.mkv",in:root)
   let plan=try WatchedFileCleanup.plan(source:movie,folder:root)
   let result=WatchedFileCleanup.remove(plan.files,in:root,performRemoval:{_ in})
   XCTAssertTrue(result.deleted.isEmpty);XCTAssertEqual(result.failed.count,1)
   XCTAssertTrue(FileManager.default.fileExists(atPath:movie.path))
  }
 }
 func testOriginalCanBeUncheckedWhileDeletingOnlyImportCopy()throws {
  try fixture {root in
   let original=root.appendingPathComponent("Original"),copies=root.appendingPathComponent("Copy")
   for folder in [original,copies] {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
   let movie=try file("Movie.mkv",in:original),copy=try file("Movie.mkv",in:copies)
   let plan=try WatchedFileCleanup.planOriginalAndCopy(source:copy,folder:original)
   let result=WatchedFileCleanup.remove(plan.appCopyFiles,from:plan)
   XCTAssertEqual(result.deleted.count,1);XCTAssertTrue(result.failed.isEmpty)
   XCTAssertTrue(FileManager.default.fileExists(atPath:movie.path));XCTAssertFalse(FileManager.default.fileExists(atPath:copy.path))
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
