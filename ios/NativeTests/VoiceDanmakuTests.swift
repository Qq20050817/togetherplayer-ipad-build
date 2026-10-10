import XCTest
import AVFoundation
@testable import TogetherPoC

final class VoiceDanmakuTests:XCTestCase {
 func testPauseStartsNewWindowWithoutLosingEarlierWords() {
  var draft=VoiceRecognitionDraft()
  draft.accept("我觉得",final:false,start:0.2,end:1.0)
  draft.accept("我觉得这个人",final:false,start:0.2,end:2.0)
  draft.accept("不太对",final:false,start:4.0,end:5.0)
  draft.accept("不太对劲",final:false,start:4.0,end:5.4)
  draft.accept("",final:true)
  XCTAssertEqual(draft.text,"我觉得这个人 不太对劲")
 }
 func testSameWindowCorrectionsDoNotDuplicateText() {
  var draft=VoiceRecognitionDraft()
  draft.accept("明天",final:false,start:0.2,end:1.0)
  draft.accept("今天",final:false,start:0.3,end:1.1)
  draft.accept("今天晚上",final:true,start:0.3,end:2.0)
  draft.accept("一起看",final:false,start:0.1,end:1.1)
  XCTAssertEqual(draft.text,"今天晚上 一起看")
 }
 @MainActor func testRapidPressDuringRestoreKeepsUserVolume() async throws {
  let player=AVPlayer();player.volume=0.8
  let ducker=VoiceVolumeDucker(player:player);ducker.begin()
  try await Task.sleep(nanoseconds:550_000_000)
  ducker.end();try await Task.sleep(nanoseconds:50_000_000)
  ducker.begin();ducker.end();ducker.end()
  try await Task.sleep(nanoseconds:650_000_000)
  XCTAssertEqual(ducker.userVolume,0.8,accuracy:0.001)
  XCTAssertEqual(player.volume,0.8,accuracy:0.001)
 }
 func testRecognitionAndReleaseNeverSendUntilConfirmation() {
  var gate=VoiceSendGate();var sent:[String]=[]
  gate.begin(room:"r");gate.text="正在说话"
  XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
  gate.finish();XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
  gate.review("结果");XCTAssertTrue(sent.isEmpty)
  gate.text="修改后的结果"
  XCTAssertTrue(gate.confirm(room:"r",send:{sent.append($0);return true}))
  XCTAssertEqual(sent,["修改后的结果"])
  XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
 }
 func testCancellationAndRoomChangesPreventAccidentalSend() {
  var gate=VoiceSendGate();gate.begin(room:"old");gate.finish();gate.review("hello")
  XCTAssertFalse(gate.confirm(room:"new",send:{_ in XCTFail("wrong room");return true}))
  gate.cancel();gate.review("late callback")
  XCTAssertFalse(gate.confirm(room:"old",send:{_ in XCTFail("cancelled");return true}))
 }
 func testEmptyLongAndFailedTransportRemainUnsent() {
  var gate=VoiceSendGate();gate.begin(room:"r");gate.finish();gate.review(" ")
  XCTAssertFalse(gate.confirm(room:"r",send:{_ in XCTFail("empty");return true}))
  gate.text=String(repeating:"字",count:301)
  XCTAssertFalse(gate.confirm(room:"r",send:{_ in XCTFail("long");return true}))
  gate.text="valid";XCTAssertFalse(gate.confirm(room:"r",send:{_ in false}))
  XCTAssertEqual(gate.phase,.review)
 }
 func testTwentyConfirmedMessagesAreSentOnce() {
  var gate=VoiceSendGate();var sent:[String]=[]
  for n in 0..<20 {
   gate.begin(room:"r");gate.finish();gate.review("message \(n)")
   XCTAssertTrue(gate.confirm(room:"r",send:{sent.append($0);return true}))
   XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
  }
  XCTAssertEqual(sent.count,20);XCTAssertEqual(Set(sent).count,20)
 }
 func testThresholdBlocksQuietInputAndPreservesShortSpeechTail() {
  var gate=VoiceNoiseGate(threshold:0.02)
  XCTAssertFalse(gate.accepts(rms:0.005,now:1))
  XCTAssertTrue(gate.accepts(rms:0.02,now:2))
  XCTAssertTrue(gate.accepts(rms:0.001,now:2.1))
  XCTAssertFalse(gate.accepts(rms:0.001,now:2.21))
  XCTAssertFalse(gate.accepts(rms:.nan,now:3))
 }
 func testBlankFinalPreservesQuietSpeechHypothesis() {
  var draft=VoiceRecognitionDraft()
  draft.accept("他在说谎",final:false)
  draft.accept("",final:true)
  XCTAssertEqual(draft.text,"他在说谎")
 }
 func testLongSpeechSegmentsAndRevisedHypothesesDoNotDuplicate() {
  var draft=VoiceRecognitionDraft()
  draft.accept("我觉",final:false);draft.accept("我觉得",final:false)
  draft.accept("我觉得这个人",final:true)
  draft.accept("不对",final:false);draft.accept("不太对",final:false)
  XCTAssertEqual(draft.text,"我觉得这个人 不太对")
  draft.accept("",final:true)
  XCTAssertEqual(draft.text,"我觉得这个人 不太对")
 }
 func testBlankPartialDoesNotErasePreviouslyRecognizedWords() {
  var draft=VoiceRecognitionDraft()
  draft.accept("这是刚才那个人",final:false)
  draft.accept("   ",final:false)
  XCTAssertEqual(draft.text,"这是刚才那个人")
 }
 @MainActor func testSmoothVolumeRestoreDoesNotStartOrSeekPlayer() async throws {
  let player=AVPlayer();player.volume=0.8
  let ducker=VoiceVolumeDucker(player:player);ducker.begin()
  try await Task.sleep(nanoseconds:120_000_000)
  XCTAssertGreaterThan(player.volume,0.176);XCTAssertLessThan(player.volume,0.8)
  XCTAssertEqual(player.rate,0)
  ducker.end();try await Task.sleep(nanoseconds:650_000_000)
  XCTAssertEqual(player.volume,0.8,accuracy:0.001);XCTAssertEqual(player.rate,0)
 }
 @MainActor func testVoiceMarkersUseExistingAuthenticatedTextTransportAndFiveSecondRenderer() throws {
  let credentials:[String:Any]=["roomId":"voice-test","userId":"host","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  defer {UserDefaults.standard.removeObject(forKey:"credentials")}
  var sent:[[String:Any]]=[]
  let client=TestClient(automaticallyConnect:false,messageSender:{sent.append($0)})
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  let room:[String:Any]=["roomId":"voice-test","hostId":"host","mediaUrl":"https://example.org/test.mp4","version":1,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]
  XCTAssertFalse(client.sendVoiceDanmaku("未连接"))
  client.receive(["type":"WELCOME","room":room,"lastSequence":0],t4:0)
  for n in 0..<20 {XCTAssertTrue(client.sendVoiceDanmaku("语音 \(n)"))}
  let commands=sent.filter {$0["type"] as? String == "CHAT_MESSAGE"}
  XCTAssertEqual(commands.count,20)
  var ids=Set<String>()
  for value in commands {
   let data=try XCTUnwrap(value["data"] as? [String:Any])
   XCTAssertEqual(data["source"] as? String,"voice")
   let id=try XCTUnwrap(data["clientMessageId"] as? String)
   XCTAssertTrue(id.hasPrefix("voice:"));ids.insert(id)
   XCTAssertEqual(Set(data.keys),Set(["source","text","clientMessageId"]))
  }
  XCTAssertEqual(ids.count,20)
  let chat=ChatEngine();chat.reset("voice-test")
  let message=ChatMessage(id:1,userId:"guest",name:"好友",text:"语音",clientMessageId:"voice:unique",timestamp:0)
  chat.accept(message,mine:false,live:true,now:1000);chat.accept(message,mine:false,live:true,now:1100)
  XCTAssertEqual(chat.danmaku.count,1);XCTAssertEqual(chat.danmaku.first?.expiresAt,6000)
  chat.tick(6001);XCTAssertTrue(chat.danmaku.isEmpty)
 }

 @MainActor func testUserVolumeChangeDuringRecordingRestoresNewValue() async throws {
  let player=AVPlayer();player.volume=0.8
  let ducker=VoiceVolumeDucker(player:player);ducker.begin()
  try await Task.sleep(nanoseconds:650_000_000)
  ducker.setUserVolume(0.4);try await Task.sleep(nanoseconds:650_000_000)
  let gain:Float=AVAudioSession.sharedInstance().currentRoute.outputs.contains {[AVAudioSession.Port.headphones,.bluetoothA2DP,.bluetoothLE,.bluetoothHFP].contains($0.portType)} ? 0.22 : 0
  XCTAssertEqual(player.volume,0.4*gain,accuracy:0.001)
  ducker.end();try await Task.sleep(nanoseconds:650_000_000)
  XCTAssertEqual(player.volume,0.4,accuracy:0.001);XCTAssertEqual(player.rate,0)
 }

}
