import XCTest
import AVFoundation
@testable import TogetherPoC

@MainActor final class RoomMovieSelectionTests:XCTestCase {
 private func root()throws->URL {
  let url=FileManager.default.temporaryDirectory.appendingPathComponent("MovieMemory-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
 }
 private func setup(_ root:URL)throws->(RoomMovieSelectionStore,URL) {
  UserDefaults.standard.removeObject(forKey:"credentials")
  let documents=root.appendingPathComponent("App/Documents"),folder=documents.appendingPathComponent("ImportedMovies/"+UUID().uuidString)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let movie=folder.appendingPathComponent("remembered.mp4");try TestMovieFixture.mp4.write(to:movie)
  try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1_700_000_000)],ofItemAtPath:movie.path)
  return(RoomMovieSelectionStore(directory:root.appendingPathComponent("State"),documents:documents),movie)
 }
 private func room(_ media:String,id:String="memory-room",version:Int=1)->[String:Any] {
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  return ["roomId":id,"hostId":"other-host","mediaUrl":media,"version":version,"duration":1000,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]
 }
 private func reference(_ movie:URL)throws->String {
  let identity=try BaiduFileIdentity.localFile(movie)
  return try XCTUnwrap(BaiduMediaReference.create(fingerprint:identity.fingerprint,size:identity.size)).value
 }
 private func model(_ store:RoomMovieSelectionStore)->TestClient {
  TestClient(automaticallyConnect:false,messageSender:{_ in},movieSelectionStore:store)
 }
 private func wait(_ predicate:()->Bool)async throws {
  for _ in 0..<150 {if predicate(){return};try await Task.sleep(nanoseconds:20_000_000)}
  XCTFail("Timed out waiting for persistence/restore")
 }
 private func select(_ client:TestClient,_ movie:URL,_ snapshot:[String:Any])async throws {
  client.receive(["type":"WELCOME","room":snapshot],t4:0)
  client.beginLocalFileSelection();client.useLocalFile(movie)
  try await wait{client.localMoviePersistenceStatus.contains("已记住")}
 }
 func testDocumentsRelativeRecordResolvesAfterContainerRelocation()throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root)
  let context=RoomMovieContext(server:"https://example.org/",roomID:"room",mediaID:"film")
  let record=try RoomMovieSelection.capture(movie,context:context,documents:store.documents,confirmedVariant:false,referenceDuration:0)
  XCTAssertNotNil(record.relativePath);XCTAssertNil(record.bookmark)
  let newDocs=root.appendingPathComponent("NewContainer/Documents"),target=newDocs.appendingPathComponent(try XCTUnwrap(record.relativePath))
  try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
  try FileManager.default.copyItem(at:movie,to:target)
  try FileManager.default.setAttributes([.modificationDate:record.modified],ofItemAtPath:target.path)
  let resolved=try record.resolve(documents:newDocs)
  XCTAssertEqual(resolved.url,target);XCTAssertNotEqual(resolved.url,movie)
 }
 func testExternalFileUsesRealBookmarkAndKeepsOriginal()throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,_)=try setup(root),outside=root.appendingPathComponent("Provider/film.mp4")
  try FileManager.default.createDirectory(at:outside.deletingLastPathComponent(),withIntermediateDirectories:true)
  try TestMovieFixture.mp4.write(to:outside)
  let record=try RoomMovieSelection.capture(outside,context:RoomMovieContext(server:"https://example.org",roomID:"r",mediaID:"film"),documents:store.documents,confirmedVariant:false,referenceDuration:0)
  XCTAssertNotNil(record.bookmark);XCTAssertNil(record.relativePath)
  let resolved=try record.resolve(documents:store.documents)
  XCTAssertEqual(resolved.url.standardizedFileURL.resolvingSymlinksInPath(),outside.standardizedFileURL.resolvingSymlinksInPath())
  XCTAssertTrue(FileManager.default.fileExists(atPath:outside.path))
 }
 func testNewClientRestoresMatchedMovieWithoutImportOrCopy()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room(try reference(movie))
  let credentials:[String:Any]=["roomId":"memory-room","userId":"other-host","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  defer{UserDefaults.standard.removeObject(forKey:"credentials")}
  let first=model(store);try await select(first,movie,snapshot);first.handleBackground()
  var sent=[[String:Any]]()
  let second=TestClient(automaticallyConnect:false,messageSender:{sent.append($0)},movieSelectionStore:RoomMovieSelectionStore(directory:store.directory,documents:store.documents))
  second.receive(["type":"WELCOME","room":snapshot],t4:0)
  try await wait{second.localMoviePersistenceStatus.contains("已自动恢复")}
  XCTAssertTrue(second.isRoomHost);XCTAssertTrue(second.usingLocalFile);XCTAssertEqual(second.cleanupSourceURL,movie)
  XCTAssertNil(second.localQualityCandidate)
  XCTAssertFalse(sent.contains{$0["type"] as? String == "ROOM_MEDIA"},"Restoring the host must not publish a new movie reference")
  XCTAssertEqual(try LocalMovieCopyStore.entries(documents:store.documents).count,1)
 }
 func testLeavingClearsAssociationButKeepsMovieAndCannotBeResavedByLateWork()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room("https://example.invalid/room.mp4")
  let first=model(store);try await select(first,movie,snapshot)
  first.beginLocalFileSelection();first.useLocalFile(movie);first.leaveRoom()
  try await Task.sleep(nanoseconds:200_000_000)
  XCTAssertNil(try store.load());XCTAssertTrue(FileManager.default.fileExists(atPath:movie.path))
  let second=model(store);second.receive(["type":"WELCOME","room":snapshot],t4:0)
  XCTAssertFalse(second.usingLocalFile)
 }
 func testManualSwitchReplacesSavedMovieInSameRoom()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room("https://example.invalid/room.mp4")
  let secondFile=movie.deletingLastPathComponent().appendingPathComponent("second.mp4");try TestMovieFixture.mp4.write(to:secondFile)
  let first=model(store);try await select(first,movie,snapshot)
  first.beginLocalFileSelection();first.useLocalFile(secondFile)
  try await wait{(try? store.load()?.name)=="second.mp4"}
  first.handleBackground()
  let second=model(store);second.receive(["type":"WELCOME","room":snapshot],t4:0)
  try await wait{second.cleanupSourceURL==secondFile}
 }
 func testDifferentRoomOrFilmNeverUsesOldSelection()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room(try reference(movie))
  let first=model(store);try await select(first,movie,snapshot);first.handleBackground()
  let second=model(store);second.receive(["type":"WELCOME","room":room(try reference(movie),id:"other-room")],t4:0)
  XCTAssertFalse(second.usingLocalFile);XCTAssertNil(try store.load())
  try await select(first,movie,snapshot);first.handleBackground()
  let third=model(store);third.receive(["type":"WELCOME","room":room("baidu://"+String(repeating:"b",count:32)+"/"+String(repeating:"a",count:32)+"/5")],t4:0)
  XCTAssertFalse(third.usingLocalFile);XCTAssertNil(try store.load())
 }
 func testServerIdentityMismatchDoesNotRestore()throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),media=try reference(movie)
  let record=try RoomMovieSelection.capture(movie,context:RoomMovieContext(server:"https://different-server.invalid",roomID:"memory-room",mediaID:media),documents:store.documents,confirmedVariant:false,referenceDuration:0)
  try store.save(record)
  let client=model(store);client.receive(["type":"WELCOME","room":room(media)],t4:0)
  XCTAssertFalse(client.usingLocalFile);XCTAssertNil(try store.load())
 }
 func testDeletedOrChangedSavedFileShowsFailureAndDoesNotCrash()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room(try reference(movie))
  let first=model(store);try await select(first,movie,snapshot);first.handleBackground()
  try Data([1,2,3]).write(to:movie)
  let second=model(store);second.receive(["type":"WELCOME","room":snapshot],t4:0)
  try await wait{second.localMoviePersistenceStatus.contains("恢复失败")}
  XCTAssertFalse(second.usingLocalFile)
  try FileManager.default.removeItem(at:movie)
  let third=model(store);third.receive(["type":"WELCOME","room":snapshot],t4:0)
  try await wait{third.localMoviePersistenceStatus.contains("恢复失败")}
  XCTAssertFalse(third.usingLocalFile)
 }
 func testRepeatedWelcomeAndStateKeepSamePlayerItemAfterRestore()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room(try reference(movie))
  let first=model(store);try await select(first,movie,snapshot);first.handleBackground()
  let second=model(store);second.receive(["type":"WELCOME","room":snapshot],t4:0)
  try await wait{second.localMoviePersistenceStatus.contains("已自动恢复")}
  let item=try XCTUnwrap(second.adapter.player.currentItem)
  for _ in 0..<3 {second.receive(["type":"WELCOME","room":snapshot],t4:0);second.receive(["type":"STATE","room":snapshot],t4:0)}
  XCTAssertTrue(second.adapter.player.currentItem === item)
 }
 func testManualClearWhileRestorePendingCannotResurrectSelection()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room(try reference(movie))
  let first=model(store);try await select(first,movie,snapshot);first.handleBackground()
  let second=model(store);second.receive(["type":"WELCOME","room":snapshot],t4:0);second.clearLocalFileSource()
  try await Task.sleep(nanoseconds:200_000_000)
  XCTAssertFalse(second.usingLocalFile);XCTAssertNil(try store.load());XCTAssertTrue(FileManager.default.fileExists(atPath:movie.path))
 }
 func testBackgroundDuringPendingRestoreCanRecoverOnNextWelcome()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room(try reference(movie))
  let first=model(store);try await select(first,movie,snapshot);first.handleBackground()
  let second=model(store);second.receive(["type":"WELCOME","room":snapshot],t4:0);second.handleBackground()
  try await Task.sleep(nanoseconds:200_000_000)
  second.receive(["type":"WELCOME","room":snapshot],t4:0)
  try await wait{second.localMoviePersistenceStatus.contains("已自动恢复")}
  XCTAssertEqual(second.cleanupSourceURL,movie)
 }
 func testConfirmedDifferentQualityIsRestoredWithoutPromptingAgain()async throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root),snapshot=room("baidu://"+String(repeating:"b",count:32)+"/"+String(repeating:"a",count:32)+"/5")
  let first=model(store);first.receive(["type":"WELCOME","room":snapshot],t4:0)
  first.beginLocalFileSelection();first.useLocalFile(movie)
  try await wait{first.localQualityCandidate != nil};first.confirmLocalQuality()
  try await wait{first.localMoviePersistenceStatus.contains("已记住")}
  XCTAssertTrue(try XCTUnwrap(store.load()).confirmedVariant);first.handleBackground()
  var resumed=snapshot;resumed["duration"]=0
  let second=model(store);second.receive(["type":"WELCOME","room":resumed],t4:0)
  try await wait{second.localMoviePersistenceStatus.contains("已自动恢复") && second.adapter.duration>0}
  XCTAssertTrue(second.usingDifferentQuality);XCTAssertNil(second.localQualityCandidate)
  XCTAssertEqual(second.variantDurationCheck,.compatible)
 }
 func testStoreRejectsOversizedCorruptAndEscapingRecord()throws {
  let root=try root();defer{try? FileManager.default.removeItem(at:root)}
  let (store,movie)=try setup(root)
  let record=try RoomMovieSelection.capture(movie,context:RoomMovieContext(server:"https://example.org",roomID:"room",mediaID:"film"),documents:store.documents,confirmedVariant:false,referenceDuration:0)
  let unsafe=RoomMovieSelection(version:1,context:record.context,name:record.name,relativePath:"../outside.mp4",bookmark:nil,size:record.size,modified:record.modified,confirmedVariant:false,referenceDuration:0)
  XCTAssertThrowsError(try unsafe.resolve(documents:store.documents))
  try FileManager.default.createDirectory(at:store.directory,withIntermediateDirectories:true)
  let file=store.directory.appendingPathComponent("selection-v1.json")
  try Data(repeating:32,count:65_537).write(to:file);XCTAssertThrowsError(try store.load())
  try Data("invalid".utf8).write(to:file);XCTAssertThrowsError(try store.load())
 }
}
