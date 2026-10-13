import XCTest
@testable import TogetherPoC

final class PlotGroundingTests:XCTestCase {
 private func cue(_ time:Double,_ text:String)->PlotEvidence {
  PlotEvidence.cue(start:time,end:time+3,text:text,source:"embedded-subtitle")
 }
 func testSpecificAutomaticQuestionMustQuoteRecentlyWatchedDialogue() {
  let first=cue(50,"我们必须摧毁这家公司保存的秘密实验资料")
  let second=cue(76,"他们说病毒已经发生变异，下一步非常危险")
  let third=cue(90,"负责人突然改变了撤离计划，大家很不理解")
  let ctx=PlotContext(cutoff:95,recent:[first,second,third],earlier:[],predictions:[])
  var question=PlotQuestion(text:"刚才提到‘病毒已经发生变异’，你觉得这一变化会如何影响撤离计划？",
   choices:["迫使大家提前离开","可能让行动延迟","仍需要更多线索"],
   source:"Apple 设备端 AI",evidenceIDs:[second.id,third.id],
   anchorQuote:"病毒已经发生变异",kind:"prediction")
  XCTAssertTrue(PlotGrounding.verified(question,context:ctx))
  question=PlotQuestion(text:"你觉得后续剧情会怎么发展？",
   choices:["意外情况","新的线索","无法判断"],
   source:"Apple 设备端 AI",evidenceIDs:[second.id],anchorQuote:"病毒已经发生变异",kind:"prediction")
  XCTAssertFalse(PlotGrounding.verified(question,context:ctx),
   "A correct evidence ID cannot excuse an unrelated generic question")
 }
 func testFutureOldAndMadeUpSubtitleAnchorsAreRejected() {
  let shown=cue(5,"我们发现了当年遗失的录像资料")
  let future=cue(120,"下一场剧情透露了隐秘计划")
  let ctx=PlotContext(cutoff:50,recent:[shown],earlier:[],predictions:[])
  let futureQ=PlotQuestion(text:"隐秘计划会如何影响他们？",choices:["不确定","发生变化"],source:"AI",
   evidenceIDs:[future.id],anchorQuote:"隐秘计划",kind:"prediction")
  XCTAssertFalse(PlotGrounding.verified(futureQ,context:ctx))
  let fake=PlotQuestion(text:"录像资料证明一切了吗？",choices:["是","否"],source:"AI",
   evidenceIDs:[shown.id],anchorQuote:"录像资料证明",kind:"discussion")
  XCTAssertFalse(PlotGrounding.verified(fake,context:ctx))
 }
 func testNativeSubtitleQuoteCanGroundButCoarseVisionLabelsCannot() {
  let visual=PlotEvidence.cue(start:10,end:11,text:"室内环境",source:"ondevice-vision")
  let native=cue(20,"我们现在必须找到实验室最后一份报告")
  let ctx=PlotContext(cutoff:30,recent:[visual,native,cue(23,"你确定它就在这里吗")],earlier:[],predictions:[])
  let q=PlotQuestion(text:"既然有人提到‘实验室最后一份报告’，你认为它能提供什么信息？",
    choices:["新的线索","现有判断的证据"],source:"AI",evidenceIDs:[native.id],
    anchorQuote:"实验室最后一份报告",kind:"prediction")
  XCTAssertTrue(PlotGrounding.verified(q,context:ctx))
 }
 func testWholeFilmWindowAndSpoilerGate() {
  let cues=(0..<64).map {n in SubtitleCue(start:Double(n)*18,end:Double(n)*18+3,text:"时间线字幕 \(n) 事件线索")}
  let windows=PlotFullFilmIndex.windows(cues,size:360)
  XCTAssertGreaterThanOrEqual(windows.count,2)
  XCTAssertTrue(windows.allSatisfy{$0.cues.count>3})
  XCTAssertTrue(windows.allSatisfy{$0.cues.allSatisfy{$0.end<=($0.end)}})
  let excerpt=PlotFullFilmIndex.excerpt(windows[0])
  XCTAssertTrue(excerpt.contains("0s："))
  XCTAssertFalse(excerpt.contains("999999"))
  let last=windows[0].cues.last!
  let quote="事件线索"
  XCTAssertNotNil(PlotFullFilmIndex.anchor(quote,window:windows[0]))
  let beat=PlotClue(id:"beat",kind:"inference",text:"刚才发现新的任务",evidenceIDs:["id"],
    end:last.end,confidence:0.5)
  XCTAssertFalse(PlotFullFilmIndex.visible(beat,at:10,evidenceIDs:["id"],watchedFraction:1))
  XCTAssertFalse(PlotFullFilmIndex.visible(beat,at:1200,evidenceIDs:[],watchedFraction:1))
  XCTAssertFalse(PlotFullFilmIndex.visible(beat,at:1200,evidenceIDs:["id"],watchedFraction:0.1))
  XCTAssertTrue(PlotFullFilmIndex.visible(beat,at:1200,evidenceIDs:["id"],watchedFraction:0.98))
 }
 func testNativeTimelineAllowsOutOfOrderSubtitlePackets() {
  var native=NativeSubtitleTimeline()
  native.receive(text:"第三句",time:30)
  native.receive(text:"",time:35)
  native.receive(text:"第一句",time:10)
  native.receive(text:"",time:15)
  native.receive(text:"第二句",time:20)
  native.receive(text:"",time:25)
  XCTAssertEqual(native.completedText(before:32),["第一句","第二句"])
  XCTAssertEqual(native.text(at:21),"第二句")
  XCTAssertEqual(native.text(at:33),"第三句")
 }
}
