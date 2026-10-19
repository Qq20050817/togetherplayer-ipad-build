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

extension LocalMovieCopyStoreTests {
 private func legacyCopy(_ documents:URL,name:String,data:Data)throws->URL {
  let dir=documents.appendingPathComponent("ImportedMovies").appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  let file=dir.appendingPathComponent(name);try data.write(to:file);return file
 }
 func testCoordinatedCompatibilityImportKeepsOriginalAndReusesCopy()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),source=root.appendingPathComponent("Provider.mkv")
  try Data([1,2,3]).write(to:source)
  let first=try LocalMovieCopyStore.persistCoordinated(source,documents:documents)
  let second=try LocalMovieCopyStore.persistCoordinated(source,documents:documents)
  XCTAssertFalse(first.reused);XCTAssertTrue(second.reused);XCTAssertEqual(first.url,second.url)
  XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
 }
 func testCoordinatedSystemInboxImportRelocatesOwnedCopyWithoutChangingBytes()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),inbox=documents.appendingPathComponent("Inbox")
  try FileManager.default.createDirectory(at:inbox,withIntermediateDirectories:true)
  let source=inbox.appendingPathComponent("system-copy.mkv"),bytes=Data(repeating:7,count:2_097_157)
  try bytes.write(to:source)
  let result=try LocalMovieCopyStore.persistCoordinated(source,documents:documents)
  XCTAssertFalse(result.reused);XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
  XCTAssertEqual(try Data(contentsOf:result.url),bytes)
  XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,1)
 }
 func testRepeatedAndRenamedContentReusesOneCopyAndKeepsExternalOriginals()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),external=root.appendingPathComponent("original.mkv")
  try Data(repeating:7,count:2_097_155).write(to:external)
  let first=try LocalMovieCopyStore.persistResult(external,documents:documents)
  let renamed=root.appendingPathComponent("renamed.mkv");try FileManager.default.copyItem(at:external,to:renamed)
  let repeatImport=try LocalMovieCopyStore.persistResult(renamed,documents:documents)
  XCTAssertFalse(first.reused);XCTAssertTrue(repeatImport.reused)
  XCTAssertEqual(first.url,repeatImport.url)
  XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,1)
  XCTAssertTrue(FileManager.default.fileExists(atPath:external.path));XCTAssertTrue(FileManager.default.fileExists(atPath:renamed.path))
 }
 func testRepeatedInboxCopyIsDiscardedOnlyAfterFullContentMatch()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),inbox=documents.appendingPathComponent("Inbox")
  try FileManager.default.createDirectory(at:inbox,withIntermediateDirectories:true)
  let first=try legacyCopy(documents,name:"film.mkv",data:Data([4,5,6]))
  let picked=inbox.appendingPathComponent("film.mkv");try Data([4,5,6]).write(to:picked)
  let result=try LocalMovieCopyStore.persistResult(picked,documents:documents)
  XCTAssertTrue(result.reused);XCTAssertEqual(result.url,first)
  XCTAssertFalse(FileManager.default.fileExists(atPath:picked.path))
  XCTAssertTrue(FileManager.default.fileExists(atPath:first.path))
 }
 func testSameSizeAndNameWithMiddleDifferenceNeverReusesWrongMovie()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),source=root.appendingPathComponent("film.mkv")
  var data=Data(repeating:1,count:3*1_048_576)
  try data.write(to:source);let first=try LocalMovieCopyStore.persist(source,documents:documents)
  data[1_048_577]=2;try data.write(to:source)
  let result=try LocalMovieCopyStore.persistResult(source,documents:documents)
  XCTAssertFalse(result.reused);XCTAssertNotEqual(first,result.url)
  XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,2)
 }
 func testLegacyDuplicatesKeepCurrentAndDeletionNeverTouchesOriginal()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),original=root.appendingPathComponent("original.mkv")
  let data=Data([6,7,8]);try data.write(to:original)
  let a=try legacyCopy(documents,name:"a.mkv",data:data),b=try legacyCopy(documents,name:"b.mkv",data:data)
  _=try legacyCopy(documents,name:"different.mkv",data:Data([6,7,9]))
  let protected=Set([b.standardizedFileURL.resolvingSymlinksInPath().path])
  let extras=try LocalMovieCopyStore.duplicateExtras(documents:documents,protected:protected)
  XCTAssertEqual(extras.count,1);XCTAssertEqual(extras[0].url,a)
  try LocalMovieCopyStore.remove(extras[0],documents:documents,protected:protected)
  XCTAssertFalse(FileManager.default.fileExists(atPath:a.path))
  XCTAssertTrue(FileManager.default.fileExists(atPath:b.path));XCTAssertEqual(try Data(contentsOf:original),data)
  let active=try XCTUnwrap(LocalMovieCopyStore.entries(documents:documents).first{$0.url==b})
  XCTAssertThrowsError(try LocalMovieCopyStore.remove(active,documents:documents,protected:protected))
 }
 func testChangedOrExternalEntryCannotBeDeleted()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents")
  let a=try legacyCopy(documents,name:"a.mkv",data:Data([1]))
  let saved=try XCTUnwrap(LocalMovieCopyStore.entries(documents:documents).first)
  try Data([1,2]).write(to:a)
  XCTAssertThrowsError(try LocalMovieCopyStore.remove(saved,documents:documents))
  let external=root.appendingPathComponent("original.mkv");try Data([3]).write(to:external)
  let fake=LocalMovieCopyStore.Entry(url:external,stamp:try CleanupFileStamp.read(external))
  XCTAssertThrowsError(try LocalMovieCopyStore.remove(fake,documents:documents))
  XCTAssertTrue(FileManager.default.fileExists(atPath:external.path));XCTAssertTrue(FileManager.default.fileExists(atPath:a.path))
 }
 func testSymlinkedImportFolderIsNotManaged()throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),outside=root.appendingPathComponent("Outside")
  try FileManager.default.createDirectory(at:documents,withIntermediateDirectories:true)
  try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
  try FileManager.default.createSymbolicLink(at:documents.appendingPathComponent("ImportedMovies"),withDestinationURL:outside)
  XCTAssertThrowsError(try LocalMovieCopyStore.entries(documents:documents))
 }
 func testConcurrentSameMovieImportsProduceOneManagedCopy()async throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents"),external=root.appendingPathComponent("original.mkv")
  try Data(repeating:7,count:2_000_000).write(to:external)
  let a=Task.detached{try LocalMovieCopyStore.persist(external,documents:documents)}
  let b=Task.detached{try LocalMovieCopyStore.persist(external,documents:documents)}
  let first=try await a.value,second=try await b.value
  XCTAssertEqual(first,second);XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,1)
 }
 func testCancelledDuplicateScanPreservesAllCopies()async throws {
  let root=try sandbox();defer{try? FileManager.default.removeItem(at:root)}
  let documents=root.appendingPathComponent("App/Documents")
  _=try legacyCopy(documents,name:"a.mkv",data:Data(repeating:7,count:2_097_152))
  _=try legacyCopy(documents,name:"b.mkv",data:Data(repeating:7,count:2_097_152))
  let job=Task.detached{try LocalMovieCopyStore.duplicateExtras(documents:documents,progress:{_ in withUnsafeCurrentTask{$0?.cancel()}})}
  do {_=try await job.value;XCTFail("Cancelled scan should not finish") }catch is CancellationError {}catch {XCTFail("Unexpected \(error)")}
  XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,2)
 }
}
