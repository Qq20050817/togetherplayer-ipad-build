import SwiftUI
import UIKit
import QuartzCore
import CoreText

@MainActor struct DanmakuLayerView: UIViewRepresentable {
 let items: [DanmakuItem]
 let fontSize: Double
 func makeUIView(context: Context) -> DanmakuSurface {DanmakuSurface()}
 func updateUIView(_ view: DanmakuSurface,context: Context) {view.update(items:items,fontSize:fontSize)}
 static func dismantleUIView(_ view: DanmakuSurface,coordinator: ()) {view.clear()}
}

// Core Animation moves prerendered text without SwiftUI layout on every frame.
// Identical updates leave active animations untouched, including during typing.
@MainActor final class DanmakuSurface: UIView {
 private var items: [DanmakuItem]=[]
 private var fontSize=24.0
 private var renderedItems: [DanmakuItem]=[]
 private var renderedFont=0.0
 private var renderedSize=CGSize.zero
 private var bubbles: [Int64:CALayer]=[:]
 var now: ()->Double = {ProcessInfo.processInfo.systemUptime*1000}
 override init(frame: CGRect) {
  super.init(frame:frame);backgroundColor = .clear;isUserInteractionEnabled=false;layer.masksToBounds=true
 }
 required init?(coder: NSCoder) {fatalError("init(coder:) is not supported")}
 func update(items: [DanmakuItem],fontSize: Double) {
  self.items=items;self.fontSize=min(44,max(14,fontSize));renderIfNeeded()
 }
 override func layoutSubviews() {super.layoutSubviews();renderIfNeeded()}
 func clear() {
  for bubble in bubbles.values {bubble.removeAllAnimations();bubble.removeFromSuperlayer()}
  bubbles=[:];items=[];renderedItems=[];renderedSize = .zero
 }
 private func renderIfNeeded() {
  guard bounds.width>0,bounds.height>0 else {return}
  guard items != renderedItems || fontSize != renderedFont || bounds.size != renderedSize else {return}
  let rebuild=fontSize != renderedFont || bounds.size != renderedSize
  let previous=Dictionary(uniqueKeysWithValues:renderedItems.map {($0.id,$0)})
  renderedItems=items;renderedFont=fontSize;renderedSize=bounds.size
  let wanted=Set(items.map(\.id));let time=now()
  CATransaction.begin();CATransaction.setDisableActions(true)
  for id in Array(bubbles.keys) where !wanted.contains(id) {bubbles[id]?.removeAllAnimations();bubbles[id]?.removeFromSuperlayer();bubbles.removeValue(forKey:id)}
  for item in items {
   guard rebuild || previous[item.id] != item || bubbles[item.id]==nil else {continue}
   let motionTime=item.expiresAt-time
   guard motionTime>0 else {bubbles[item.id]?.removeFromSuperlayer();bubbles.removeValue(forKey:item.id);continue}
   // Measure and draw the very same Core Text line, including fallback glyphs.
   // CATextLayer's plain-string font fallback differed from NSString measurement
   // and clipped the final Chinese glyph inside its own text rectangle.
   let image=DanmakuTextRaster.image(item.text,fontSize:CGFloat(fontSize),scale:max(1,traitCollection.displayScale))
   let textWidth=image.size.width+16
   let height=image.size.height
   let bubble=bubbles[item.id] ?? CALayer();bubble.removeAllAnimations();bubble.sublayers?.forEach {$0.removeFromSuperlayer()}
   bubble.anchorPoint = .zero;bubble.bounds=CGRect(x:0,y:0,width:textWidth,height:height)
   bubble.backgroundColor=UIColor.black.withAlphaComponent(0.25).cgColor;bubble.cornerRadius=height/2
   let text=CALayer();text.contents=image.cgImage;text.contentsScale=image.scale
   text.frame=CGRect(x:8,y:0,width:image.size.width,height:height);bubble.addSublayer(text)
   if bubbles[item.id]==nil {layer.addSublayer(bubble);bubbles[item.id]=bubble}
   let motion=DanmakuMotion(width:Double(bounds.width),textWidth:Double(textWidth),expiresAt:item.expiresAt,now:time,durationSeconds:item.durationMs/1000)
   bubble.position=CGPoint(x:CGFloat(motion.toX),y:CGFloat(item.lane)*(CGFloat(fontSize)+14))
   let animation=CABasicAnimation(keyPath:"position.x");animation.fromValue=motion.fromX;animation.toValue=motion.toX;animation.duration=motion.remaining;animation.beginTime=CACurrentMediaTime();animation.timingFunction=CAMediaTimingFunction(name:.linear);bubble.add(animation,forKey:"travel")
  }
  CATransaction.commit()
 }
}

// Rasterize once per message/size change; Core Animation still handles travel.
@MainActor enum DanmakuTextRaster {
 static func image(_ text:String,fontSize:CGFloat,scale:CGFloat)->UIImage {
  let font=UIFont.systemFont(ofSize:fontSize,weight:.semibold)
  let string=NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:UIColor.white])
  let line=CTLineCreateWithAttributedString(string as CFAttributedString)
  var ascent:CGFloat=0,descent:CGFloat=0,leading:CGFloat=0
  let advance=CGFloat(CTLineGetTypographicBounds(line,&ascent,&descent,&leading))
  let ink=CTLineGetBoundsWithOptions(line,.useGlyphPathBounds)
  let padding:CGFloat=6
  let left=min(0,ink.minX),right=max(advance,ink.maxX)
  let top=max(ascent,ink.maxY),bottom=max(descent,-ink.minY)
  let size=CGSize(width:max(1,ceil(right-left)+padding*2),height:max(1,ceil(top+bottom)+padding*2))
  let format=UIGraphicsImageRendererFormat();format.scale=scale;format.opaque=false
  return UIGraphicsImageRenderer(size:size,format:format).image {renderer in
   let context=renderer.cgContext
   context.translateBy(x:0,y:size.height);context.scaleBy(x:1,y:-1)
   context.textMatrix = .identity;context.textPosition=CGPoint(x:padding-left,y:padding+bottom)
   context.setShadow(offset:CGSize(width:0,height:-1),blur:2,color:UIColor.black.cgColor)
   CTLineDraw(line,context)
  }
 }
}
