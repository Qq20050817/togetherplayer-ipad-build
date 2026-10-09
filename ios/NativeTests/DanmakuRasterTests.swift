import XCTest
import UIKit
import CoreText
@testable import TogetherPoC

final class DanmakuRasterTests:XCTestCase {
 @MainActor func testLastChineseGlyphHasUnclippedInkAndTransparentTrailingMargin() throws {
  // Check actual pixels, not just the width formula. The same glyph at the end
  // must retain its full width at all supported sizes and both screen densities.
  for size:CGFloat in [14,24,44] {
   for scale:CGFloat in [2,3] {
    let lone=DanmakuTextRaster.image("啊",fontSize:size,scale:scale)
    let message=DanmakuTextRaster.image("小爱：话说这个人为什么不是啊",fontSize:size,scale:scale)
    let a=try whiteInk(lone),b=try whiteInk(message)
    XCTAssertFalse(a.columns.isEmpty);XCTAssertFalse(b.columns.isEmpty)
    let lastWidth=a.columns.last!-a.columns.first!
    let lastStart=b.columns.last!-lastWidth
    let lastColumns=b.columns.filter {$0>=lastStart}
    XCTAssertLessThanOrEqual(abs(lastColumns.count-a.columns.count),2)
    XCTAssertGreaterThanOrEqual(b.width-1-b.columns.last!,Int(3*scale),"Trailing glyph/shadow must not touch the image edge")
    XCTAssertGreaterThan(message.size.width,lone.size.width)
   }
  }
 }
 @MainActor func testMixedFontsEmojiAndLongTextHaveClearEdges() throws {
  for text in ["小爱：Hello AV 你好👀",String(repeating:"弹幕字幕",count:60)+"啊","电影 🎬 family 👨‍👩‍👧‍👦"] {
   let image=DanmakuTextRaster.image(text,fontSize:44,scale:2)
   let ink=try whiteInk(image)
   XCTAssertFalse(ink.columns.isEmpty)
   XCTAssertGreaterThanOrEqual(ink.columns.first!,6)
   XCTAssertGreaterThanOrEqual(ink.width-1-ink.columns.last!,6)
  }
 }
 private func whiteInk(_ image:UIImage)throws->(width:Int,columns:[Int]) {
  let cg=try XCTUnwrap(image.cgImage);let w=cg.width,h=cg.height
  var pixels=[UInt8](repeating:0,count:w*h*4)
  let context=try XCTUnwrap(CGContext(data:&pixels,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
  context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
  let columns=(0..<w).filter {x in (0..<h).contains {y in let i=(y*w+x)*4;return pixels[i]>40 && pixels[i+1]>40 && pixels[i+2]>40 && pixels[i+3]>40}}
  return (w,columns)
 }
}
