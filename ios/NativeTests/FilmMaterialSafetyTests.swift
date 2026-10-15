import XCTest
import CryptoKit
import UIKit
import Darwin
@testable import TogetherPoC

@MainActor final class FilmMaterialSafetyTests:XCTestCase {
 private func directory()throws->URL {
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
 }
 private nonisolated static func residentBytes()->UInt64? {
  var info=mach_task_basic_info()
  var count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<integer_t>.size)
  let result=withUnsafeMutablePointer(to:&info) {pointer in
   pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
    task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)
   }
  }
  return result==KERN_SUCCESS ? UInt64(info.resident_size) : nil
 }
 func testIndependentFourKHEVC10BitMKVFrameSamplingKeepsRealTimestamps() throws {
  let movie=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"bank-uhd10",withExtension:"mkv"),
   "CI must generate the 3840x2160 HEVC Main10 Matroska fixture before xcodegen")
  let sampler=try XCTUnwrap(FilmFFmpegFrameSampler(url:movie),
   "HEVC Main10 Matroska stream must open an independent video decoder")
  let thumbnail=try XCTUnwrap(sampler.image(at:10),
   "4K HEVC sampled frame failed: \(sampler.lastFailure ?? "unknown")")
  XCTAssertLessThanOrEqual(thumbnail.width,480)
  XCTAssertLessThanOrEqual(thumbnail.height,270)
  let timestamp=try XCTUnwrap(sampler.lastDecodedTime)
  XCTAssertLessThanOrEqual(abs(timestamp-10),5)
  XCTAssertGreaterThanOrEqual(timestamp,0)
  // Seeking backward must not poison the decoder after a prior request.
  let again=try XCTUnwrap(sampler.image(at:2),
   "HEVC backward seek failed: \(sampler.lastFailure ?? "unknown")")
  XCTAssertGreaterThan(again.width,0)
  XCTAssertLessThanOrEqual(abs((sampler.lastDecodedTime ?? -100)-2),5)
 }
 func testFrameFailureDiagnosticPreservesActualError() {
  let description=FilmMaterialExportFailure.frameExtractionDiagnostic("实际画面0/120；HEVC解码失败").localizedDescription
  XCTAssertTrue(description.contains("0/120"))
  XCTAssertTrue(description.contains("HEVC解码失败"))
 }
 func testLargeFingerprintHasBoundedResidentMemoryAndReportsProgress() async throws {
  let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
  let file=root.appendingPathComponent("large-sparse.mkv")
  FileManager.default.createFile(atPath:file.path,contents:nil)
  let handle=try FileHandle(forWritingTo:file);try handle.truncate(atOffset:512*1024*1024);try handle.close()
  let result=try await Task.detached(priority:.utility) {() throws->(String,String,UInt64,[Double]) in
   // Warm up CryptoKit before comparing residency. Sparse bytes are real
   // reads/hash input, not a mocked fingerprint or a real film format test.
   _=SHA256.hash(data:Data(repeating:0,count:1024))
   let before=try XCTUnwrap(Self.residentBytes());var peak=before,values:[Double]=[]
   let hash=try FilmMaterialFingerprint.source(file,progress:{value in
    values.append(value);if let current=Self.residentBytes() {peak=max(peak,current)}
   })
   var expected=SHA256();let block=Data(repeating:0,count:1024*1024)
   for _ in 0..<512 {expected.update(data:block)}
   return (hash,expected.finalize().map{String(format:"%02x",$0)}.joined(),peak>before ? peak-before : 0,values)
  }.value
  XCTAssertEqual(result.0,result.1)
  XCTAssertEqual(result.3.last,1);XCTAssertGreaterThan(result.3.count,10);XCTAssertLessThanOrEqual(result.3.count,101)
  XCTAssertEqual(result.3,result.3.sorted())
  XCTAssertLessThan(result.2,96*1024*1024,"512 MiB input must not be retained in memory")
  print("Film export hash 512MiB: observed resident growth \(result.2) bytes")
 }
 func testStreamedZIPMatchesUTF8FormatAndExactPayload() async throws {
  let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
  let a=root.appendingPathComponent("a"),b=root.appendingPathComponent("b"),zip=root.appendingPathComponent("out.zip")
  let first=Data("完整字幕\n00:01:03".utf8),second=Data(repeating:37,count:200_003)
  try first.write(to:a);try second.write(to:b)
  try await Task.detached {try FilmMaterialZip.write([("字幕/完整.srt",a),("分镜/01.jpg",b)],to:zip)}.value
  XCTAssertEqual(try Data(contentsOf:zip),FilmMaterialZip.make([("字幕/完整.srt",first),("分镜/01.jpg",second)]))
 }
 func testArchiveStreamsManySheetsWithoutReadingWholeArchive() async throws {
  let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
  let image=root.appendingPathComponent("sheet.jpg"),zip=root.appendingPathComponent("out.zip")
  try Data(repeating:42,count:1024*1024).write(to:image)
  let entries=(0..<32).map{("sheets/\($0).jpg",image)}
  let chunks=try await Task.detached {() throws->Int in
   var count=0;try FilmMaterialZip.write(entries,to:zip,onChunk:{count+=1});return count
  }.value
  XCTAssertEqual(chunks,32*16*2,"CRC and output each stream 64KiB blocks")
  let size=try zip.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
  XCTAssertGreaterThan(size,32*1024*1024);XCTAssertLessThan(size,33*1024*1024)
 }
 func testCancelledArchiveRemovesPartialFile() async throws {
  let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
  let image=root.appendingPathComponent("sheet.jpg"),zip=root.appendingPathComponent("out.zip")
  try Data(repeating:0,count:200_000).write(to:image)
  let job=Task.detached {
   try FilmMaterialZip.write([("sheet.jpg",image)],to:zip,onChunk:{withUnsafeCurrentTask{$0?.cancel()}})
  }
  do {try await job.value;XCTFail("Cancelled packing must fail")}catch is CancellationError{}catch{XCTFail("Unexpected \(error)")}
  XCTAssertFalse(FileManager.default.fileExists(atPath:zip.path))
 }
 func testExportGatePreventsOverlappingDecoderAndReleasesAfterFailure() throws {
  try FilmMaterialExportGate.exclusively {
   XCTAssertThrowsError(try FilmMaterialExportGate.exclusively{XCTFail("Second decoder must not start")}) {error in
    XCTAssertEqual(error.localizedDescription,FilmMaterialExportFailure.busy.localizedDescription)
   }
  }
  XCTAssertThrowsError(try FilmMaterialExportGate.exclusively {throw CancellationError()})
  XCTAssertEqual(try FilmMaterialExportGate.exclusively{42},42)
 }
 func testSystemMemoryWarningStopsLargeFileScanAndPreservesOriginal() async throws {
  let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
  let file=root.appendingPathComponent("large.mkv")
  FileManager.default.createFile(atPath:file.path,contents:nil)
  let writer=try FileHandle(forWritingTo:file);try writer.truncate(atOffset:20*1024*1024*1024);try writer.close()
  let suite="export-test-"+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
  defer{defaults.removePersistentDomain(forName:suite)}
  let session=FilmMaterialExportSession(defaults:defaults);defer{session.cancel()}
  session.begin(url:file,title:"memory",external:nil,allowOCR:true)
  XCTAssertTrue(session.status.contains("核对原片"))
  NotificationCenter.default.post(name:UIApplication.didReceiveMemoryWarningNotification,object:nil)
  for _ in 0..<100 {if !session.working {break};try await Task.sleep(nanoseconds:10_000_000)}
  XCTAssertFalse(session.working);XCTAssertNil(session.file);XCTAssertTrue(session.individualFiles.isEmpty)
  XCTAssertTrue(session.status.contains("内存紧张"),session.status)
  XCTAssertEqual(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,20*1024*1024*1024)
 }
}
