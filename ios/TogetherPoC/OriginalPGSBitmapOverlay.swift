import SwiftUI
import CoreGraphics

/// Presentation-only path for *decoded original* PGS bitmap compositions.
/// This view never consumes OCR text, converted SRT or WebVTT. A decoding
/// source must explicitly provide original palette indices and timed frames.
@MainActor struct OriginalPGSBitmapOverlay: View {
 let frame: PGSBitmapFrame
 let container: CGSize
 let picture: CGSize

 var body: some View {
  ZStack(alignment: .topLeading) {
   ForEach(Array(PGSBitmapComposition.layers(for: frame).enumerated()), id: \.offset) { _, layer in
    if let image = Self.makeImage(layer),
       let layout = layer.normalizedRect(videoWidth: frame.videoWidth,
                                         videoHeight: frame.videoHeight) {
     Image(decorative: image, scale: 1)
      .resizable()
      .interpolation(.none)
      .frame(width: picture.width * layout.width,
             height: picture.height * layout.height)
      .position(x: (container.width - picture.width)/2
                     + picture.width * (layout.x + layout.width/2),
                y: (container.height - picture.height)/2
                     + picture.height * (layout.y + layout.height/2))
    }
   }
  }
  .frame(width: container.width, height: container.height)
  .allowsHitTesting(false)
  .accessibilityHidden(true)
 }

 private static func makeImage(_ layer: PGSBitmapLayer) -> CGImage? {
  guard layer.width > 0, layer.height > 0,
        layer.width <= Int.max/4,
        layer.height <= Int.max/(layer.width*4),
        layer.rgba.count == layer.width*layer.height*4 else {return nil}
  let pixels=Data(layer.rgba)
  guard let provider=CGDataProvider(data:pixels as CFData) else{return nil}
  let info=CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue)
   .union(.byteOrder32Big)
  return CGImage(width:layer.width,height:layer.height,
                 bitsPerComponent:8,bitsPerPixel:32,
                 bytesPerRow:layer.width*4,
                 space:CGColorSpaceCreateDeviceRGB(),
                 bitmapInfo:info,provider:provider,
                 decode:nil,shouldInterpolate:false,
                 intent:.defaultIntent)
 }
}
