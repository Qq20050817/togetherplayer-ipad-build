import XCTest
import UIKit
@testable import TogetherPoC
@MainActor final class PlaybackSeekSliderTests:XCTestCase {
 func testTouchBurstCommitsOnlyFinalValueAndCancellationDoesNotSeek(){
  var commits:[Double]=[];var drafts:[Double]=[];var cancellations=0
  let view=PlaybackSeekSlider(value:1,duration:100,enabled:true,preview:{drafts.append($0)},commit:{commits.append($0)},cancel:{cancellations+=1})
  let c=view.makeCoordinator();let slider=UISlider();slider.maximumValue=100;slider.value=1
  c.begin(slider)
  for v in [20.0,80,50]{slider.value=Float(v);c.changed(slider)}
  XCTAssertTrue(commits.isEmpty);c.end(slider);XCTAssertEqual(commits,[50]);XCTAssertFalse(c.tracking)
  c.begin(slider);slider.value=90;c.changed(slider);c.abort(slider)
  XCTAssertEqual(commits,[50]);XCTAssertEqual(cancellations,1);XCTAssertFalse(c.tracking)
  XCTAssertEqual(drafts.last,90)
 }
 func testAccessibilityValueOnlyChangesCommitWithoutLatchingPreview(){
  var commits:[Double]=[]
  let view=PlaybackSeekSlider(value:1,duration:100,enabled:true,preview:{_ in XCTFail("accessibility changes must not latch dragging")},commit:{commits.append($0)},cancel:{})
  let c=view.makeCoordinator();let slider=UISlider();slider.maximumValue=100;slider.value=50
  c.changed(slider);XCTAssertEqual(commits,[50]);XCTAssertFalse(c.tracking)
  slider.value=75;c.changed(slider);XCTAssertEqual(commits,[50,75]);XCTAssertFalse(c.tracking)
 }
}
