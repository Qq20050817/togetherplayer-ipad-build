import XCTest
import UIKit
@testable import TogetherPoC

@MainActor final class LocalMovieDocumentPickerTests:XCTestCase {
 private func root()throws->URL {
  let url=FileManager.default.temporaryDirectory.appendingPathComponent("MoviePicker-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
 }
 private func inbox(_ root:URL)throws->(URL,URL) {
  let documents=root.appendingPathComponent("App/Documents"),folder=documents.appendingPathComponent("Inbox")
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let file=folder.appendingPathComponent("movie.mkv");try Data(repeating:9,count:2_097_157).write(to:file)
  return(documents,file)
 }
 func testCompatibilityUsesSystemImportAndDirectModeUsesOpen() {
  XCTAssertEqual(LocalMovieDocumentPicker.makeController(asCopy:true).documentPickerMode,.import)
  XCTAssertEqual(LocalMovieDocumentPicker.makeController(asCopy:false).documentPickerMode,.open)
 }
 func testCompatibilityReportsSelectionBeforeAsyncDurableDeliveryAndOnlyOnce()async throws {
  let folder=try root();defer{try? FileManager.default.removeItem(at:folder)}
  let (documents,file)=try inbox(folder),done=expectation(description:"durable copy")
  var picked=[URL](),status=[String](),cancelled=0
  let coordinator=LocalMovieDocumentPicker.Coordinator(asCopy:true,documents:documents,onPick:{url in
   picked.append(url);XCTAssertTrue(FileManager.default.isReadableFile(atPath:url.path));done.fulfill()
  },onCancel:{cancelled+=1},onFailure:{XCTFail($0)},onProcessing:{status.append($0)})
  let view=LocalMovieDocumentPicker.makeController(asCopy:true)
  coordinator.documentPicker(view,didPickDocumentsAt:[file])
  XCTAssertEqual(picked.count,0);XCTAssertTrue(status.first?.contains("已收到影片：movie.mkv")==true)
  coordinator.documentPicker(view,didPickDocumentsAt:[file])
  // Picker dismissal can deliver Cancel after the accepted URL. It must not
  // discard an in-progress copy or turn its result into a silent cancellation.
  coordinator.documentPickerWasCancelled(view)
  await fulfillment(of:[done],timeout:8)
  XCTAssertEqual(picked.count,1);XCTAssertEqual(cancelled,0)
  XCTAssertTrue(picked[0].path.contains("/ImportedMovies/"))
  XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
  XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,1)
  XCTAssertTrue(status.last?.contains("影片副本已保存")==true)
 }
 func testRepeatedSystemInboxSelectionReusesExistingCopy()async throws {
  let folder=try root();defer{try? FileManager.default.removeItem(at:folder)}
  let (documents,file)=try inbox(folder)
  let existing=try LocalMovieCopyStore.persist(file,documents:documents)
  try Data(repeating:9,count:2_097_157).write(to:file)
  let done=expectation(description:"reuse"),view=LocalMovieDocumentPicker.makeController(asCopy:true)
  var picked:URL?,status=[String]()
  let coordinator=LocalMovieDocumentPicker.Coordinator(asCopy:true,documents:documents,onPick:{picked=$0;done.fulfill()},onCancel:{XCTFail("Unexpected cancel")},onFailure:{XCTFail($0)},onProcessing:{status.append($0)})
  coordinator.documentPicker(view,didPickDocumentsAt:[file]);await fulfillment(of:[done],timeout:8)
  XCTAssertEqual(picked,existing);XCTAssertTrue(status.last?.contains("已复用已有文件")==true)
  XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,1)
  XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
 }
 func testUnreadableSystemSelectionReportsFailureInsteadOfRemainingSilent()async throws {
  let folder=try root();defer{try? FileManager.default.removeItem(at:folder)}
  let done=expectation(description:"failure"),view=LocalMovieDocumentPicker.makeController(asCopy:true)
  var failed=[String](),selected=0
  let coordinator=LocalMovieDocumentPicker.Coordinator(asCopy:true,documents:folder.appendingPathComponent("Documents"),onPick:{_ in selected+=1},onCancel:{XCTFail("Unexpected cancel")},onFailure:{failed.append($0);done.fulfill()},onProcessing:{_ in})
  coordinator.documentPicker(view,didPickDocumentsAt:[folder.appendingPathComponent("missing.mkv")])
  await fulfillment(of:[done],timeout:8)
  XCTAssertEqual(failed.count,1);XCTAssertTrue(failed[0].contains("兼容导入失败"));XCTAssertEqual(selected,0)
 }
 func testExplicitCancelBeforeSelectionBlocksLateURL()throws {
  let folder=try root();defer{try? FileManager.default.removeItem(at:folder)}
  let (documents,file)=try inbox(folder),view=LocalMovieDocumentPicker.makeController(asCopy:true)
  var cancelled=0,picked=0,reading=0
  let coordinator=LocalMovieDocumentPicker.Coordinator(asCopy:true,documents:documents,onPick:{_ in picked+=1},onCancel:{cancelled+=1},onFailure:{XCTFail($0)},onProcessing:{_ in reading+=1})
  coordinator.documentPickerWasCancelled(view);coordinator.documentPickerWasCancelled(view)
  coordinator.documentPicker(view,didPickDocumentsAt:[file])
  XCTAssertEqual(cancelled,1);XCTAssertEqual(picked,0);XCTAssertEqual(reading,0)
  XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
 }
 func testDirectSelectionReturnsOriginalWithoutCopying()throws {
  let folder=try root();defer{try? FileManager.default.removeItem(at:folder)}
  let (documents,file)=try inbox(folder),view=LocalMovieDocumentPicker.makeController(asCopy:false)
  var picked=[URL](),reading=0
  let coordinator=LocalMovieDocumentPicker.Coordinator(asCopy:false,documents:documents,onPick:{picked.append($0)},onCancel:{XCTFail("Unexpected cancel")},onFailure:{XCTFail($0)},onProcessing:{_ in reading+=1})
  coordinator.documentPicker(view,didPickDocumentsAt:[file]);coordinator.documentPicker(view,didPickDocumentsAt:[file])
  XCTAssertEqual(picked,[file]);XCTAssertEqual(reading,0)
  XCTAssertTrue(FileManager.default.fileExists(atPath:file.path));XCTAssertEqual(try LocalMovieCopyStore.entries(documents:documents).count,0)
 }
}
