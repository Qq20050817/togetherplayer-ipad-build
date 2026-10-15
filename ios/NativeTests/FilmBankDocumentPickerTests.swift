import XCTest
import UIKit
@testable import TogetherPoC

@MainActor final class FilmBankDocumentPickerTests:XCTestCase {
 private func root()throws->URL {
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
 }
 private func controller()->UIDocumentPickerViewController {
  UIDocumentPickerViewController(forOpeningContentTypes:FilmBankDocumentPicker.contentTypes,asCopy:true)
 }
 func testPickerCapturesBytesBeforeFileRemovalAndDeliversOnlyOnce() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let file=directory.appendingPathComponent("download.JSON"),bytes=Data("{\"schemaVersion\":1}".utf8)
  try bytes.write(to:file)
  let done=expectation(description:"selected data")
  var documents:[SelectedFilmBankDocument]=[],cancelled=0,reading=0
  let picker=FilmBankDocumentPicker(onPick:{document in
   documents.append(document);try? FileManager.default.removeItem(at:file);done.fulfill()
  },onCancel:{cancelled+=1},onFailure:{XCTFail($0)},onReading:{_ in reading+=1})
  let delegate=picker.makeCoordinator(),view=controller()
  delegate.documentPicker(view,didPickDocumentsAt:[file]);delegate.documentPicker(view,didPickDocumentsAt:[file])
  await fulfillment(of:[done],timeout:5)
  delegate.documentPickerWasCancelled(view)
  XCTAssertEqual(documents.count,1);XCTAssertEqual(documents.first?.data,bytes)
  XCTAssertEqual(documents.first?.name,"download.JSON");XCTAssertEqual(cancelled,0);XCTAssertEqual(reading,1)
  XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
 }
 func testCancelledReadDoesNotPublishLateSelection() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let file=directory.appendingPathComponent("test.json");try Data("{}".utf8).write(to:file)
  var selected=0,cancelled=0,failed=0
  let picker=FilmBankDocumentPicker(onPick:{_ in selected+=1},onCancel:{cancelled+=1},onFailure:{_ in failed+=1})
  let delegate=picker.makeCoordinator(),view=controller()
  delegate.documentPicker(view,didPickDocumentsAt:[file]);delegate.documentPickerWasCancelled(view)
  delegate.documentPickerWasCancelled(view)
  try await Task.sleep(nanoseconds:100_000_000)
  XCTAssertEqual(selected,0);XCTAssertEqual(cancelled,1);XCTAssertEqual(failed,0)
 }
 func testUnreadableSelectionReportsFailureInsteadOfSilence() async throws {
  let done=expectation(description:"visible failure")
  var selections=0,failures:[String]=[]
  let picker=FilmBankDocumentPicker(onPick:{_ in selections+=1},onCancel:{XCTFail("Not a cancellation")},onFailure:{message in failures.append(message);done.fulfill()})
  let delegate=picker.makeCoordinator(),view=controller()
  delegate.documentPicker(view,didPickDocumentsAt:[URL(fileURLWithPath:"/missing-"+UUID().uuidString+".json")])
  await fulfillment(of:[done],timeout:5)
  XCTAssertEqual(selections,0);XCTAssertEqual(failures.count,1);XCTAssertTrue(failures[0].contains("题库读取失败"))
 }
 func testReaderRejectsOversizeEmptyFolderAndRemoteWithoutUnboundedRead() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let empty=directory.appendingPathComponent("empty.json"),large=directory.appendingPathComponent("large.json")
  try Data().write(to:empty);try Data(repeating:32,count:FilmBankCodec.maxBytes+1).write(to:large)
  for url in [empty,large,directory,URL(string:"https://example.org/bank.json")!] {
   let job=Task.detached{try FilmBankDocumentReader.read(url)}
   do {_ = try await job.value;XCTFail("Invalid document must fail")}catch{}
  }
 }
 private func sample(_ hash:String)->FilmQuestionBank {
  FilmQuestionBank(schemaVersion:1,title:"Copied JSON bank",year:nil,edition:nil,durationMs:120_000,sourceFingerprint:hash,subtitleFingerprint:nil,questions:[FilmBankQuestion(id:"q1",triggerAtMs:20_000,revealAtMs:50_000,type:"prediction",question:"守门人藏起钥匙后，访客会向谁求证？",options:["询问在场的证人","寻找购买记录"],answerIndex:0,evidence:[FilmBankEvidence(kind:"subtitle",startMs:10_000,endMs:15_000,text:"守门人否认移动钥匙")],revealEvidence:[FilmBankEvidence(kind:"subtitle",startMs:45_000,endMs:48_000,text:"访客向证人求证")],explanation:"后续对白验证选择。",confidence:0.9,qualityScore:90)])
 }
 func testRuntimeImportsCapturedJSONAfterPickerTemporaryFileIsGone() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let movie=directory.appendingPathComponent("film.mkv"),json=directory.appendingPathComponent("bank.json")
  try Data(repeating:12,count:200_000).write(to:movie)
  let bank=sample(try FilmMaterialFingerprint.source(movie));try JSONEncoder().encode(bank).write(to:json)
  let data=try FilmBankDocumentReader.read(json);try FileManager.default.removeItem(at:json)
  let runtime=FilmQuestionBankRuntime(store:FilmQuestionBankStore(directory:directory.appendingPathComponent("banks")),progressStore:FilmBankProgressStore(directory:directory.appendingPathComponent("progress")))
  runtime.restore(filmKey:"film",source:movie,durationMs:120_000);await runtime.waitForRestore()
  await runtime.importDocument(SelectedFilmBankDocument(name:"bank.json",data:data),filmKey:"film",source:movie,durationMs:120_000)
  XCTAssertEqual(runtime.active,bank);XCTAssertFalse(runtime.importing);XCTAssertTrue(runtime.status.contains("已加载 1 道题"),runtime.status)
 }
 func testInvalidCapturedJSONDisplaysFieldErrorAndDoesNotActivateBank() async throws {
  let directory=try root();defer{try? FileManager.default.removeItem(at:directory)}
  let movie=directory.appendingPathComponent("film.mp4");try Data(repeating:5,count:1000).write(to:movie)
  let runtime=FilmQuestionBankRuntime(store:FilmQuestionBankStore(directory:directory.appendingPathComponent("banks")))
  runtime.restore(filmKey:"film",source:movie,durationMs:120_000);await runtime.waitForRestore()
  await runtime.importDocument(SelectedFilmBankDocument(name:"broken.json",data:Data("{\"schemaVersion\":1}".utf8)),filmKey:"film",source:movie,durationMs:120_000)
  XCTAssertNil(runtime.active);XCTAssertFalse(runtime.importing);XCTAssertTrue(runtime.status.contains("导入失败"),runtime.status)
 }
}
