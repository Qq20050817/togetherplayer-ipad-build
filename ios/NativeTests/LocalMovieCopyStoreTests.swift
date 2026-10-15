import XCTest
@testable import TogetherPoC

final class LocalMovieCopyStoreTests: XCTestCase {
 private func sandbox() throws -> URL {
  let root=FileManager.default.temporaryDirectory
   .appendingPathComponent("LocalMovieCopyTests-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  return root
 }
 func testTemporaryPickerCopyBecomesDurableAndKeepsMovieName() throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("Documents",isDirectory:true)
  let staging=documents.appendingPathComponent("Inbox",isDirectory:true)
  try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
  let picked=staging.appendingPathComponent("电影 UHD.mkv")
  let payload=Data(repeating:0x72,count:1024)
  try payload.write(to:picked)
  let stored=try LocalMovieCopyStore.persist(picked,documents:documents)
  XCTAssertTrue(stored.path.contains("/Documents/ImportedMovies/"))
  XCTAssertEqual(stored.lastPathComponent,picked.lastPathComponent)
  XCTAssertEqual(try Data(contentsOf:stored),payload)
  XCTAssertFalse(FileManager.default.fileExists(atPath:picked.path))
 }
 func testAlreadyDurableDocumentIsKeptUnchanged() throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("Documents",isDirectory:true)
  try FileManager.default.createDirectory(at:documents,withIntermediateDirectories:true)
  let movie=documents.appendingPathComponent("Existing.mkv")
  try Data([1,2,3]).write(to:movie)
  XCTAssertEqual(try LocalMovieCopyStore.persist(movie,documents:documents),movie)
  XCTAssertTrue(FileManager.default.fileExists(atPath:movie.path))
 }
 func testExternalOriginalIsNeverMoved() throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents",isDirectory:true)
  let external=root.appendingPathComponent("OtherProvider/Film.mkv")
  try FileManager.default.createDirectory(at:external.deletingLastPathComponent(),withIntermediateDirectories:true)
  try Data([4,5,6]).write(to:external)
  let copy=try LocalMovieCopyStore.persist(external,documents:documents)
  XCTAssertTrue(FileManager.default.fileExists(atPath:external.path))
  XCTAssertEqual(try Data(contentsOf:copy),try Data(contentsOf:external))
 }
 func testSameNamedImportsRemainDistinct() throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let staging=root.appendingPathComponent("tmp",isDirectory:true)
  let documents=root.appendingPathComponent("Documents",isDirectory:true)
  try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
  let original=staging.appendingPathComponent("film.mkv")
  try Data([1]).write(to:original)
  let first=try LocalMovieCopyStore.persist(original,documents:documents)
  try Data([2]).write(to:original)
  let second=try LocalMovieCopyStore.persist(original,documents:documents)
  XCTAssertNotEqual(first,second)
  XCTAssertEqual(try Data(contentsOf:first),Data([1]))
  XCTAssertEqual(try Data(contentsOf:second),Data([2]))
 }
}
