import XCTest
@testable import TogetherPoC
final class VideoRotationTests:XCTestCase {
 func testQuarterTurnsAndPortraitFitWithoutCropping() {
  var turns=0
  for expected in [90,180,270,0] {turns=VideoRotation.next(turns);XCTAssertEqual(VideoRotation.degrees(turns),expected)}
  let container=CGSize(width:1920,height:1080)
  let presentation=VideoRotation.presentation(CGSize(width:1920,height:1080),turns:1)
  let picture=SubtitlePictureLayout.picture(container:container,presentation:presentation)
  XCTAssertEqual(picture.height,1080,accuracy:0.01)
  XCTAssertEqual(picture.width,607.5,accuracy:0.01)
  let rendering=VideoRotation.renderingSize(picture:picture,turns:1)
  XCTAssertEqual(rendering.width,picture.height);XCTAssertEqual(rendering.height,picture.width)
  XCTAssertLessThanOrEqual(picture.width,container.width);XCTAssertLessThanOrEqual(picture.height,container.height)
 }
}
