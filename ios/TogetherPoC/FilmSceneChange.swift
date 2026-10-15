import Foundation
import CoreGraphics

enum FilmSceneChange {
 // Tiny luminance histograms bound memory/CPU. They detect gross visual
 // changes between samples, not characters, actions or every cut in a film.
 static func signature(_ image:CGImage)->[Double]? {
  let w=32,h=18
  var bytes=[UInt8](repeating:0,count:w*h*4)
  let drawn=bytes.withUnsafeMutableBytes{raw->Bool in
   guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
   context.draw(image,in:CGRect(x:0,y:0,width:w,height:h));return true
  }
  guard drawn else{return nil}
  var histogram=[Double](repeating:0,count:16)
  for i in stride(from:0,to:bytes.count,by:4) {
   let l=(Int(bytes[i])*54+Int(bytes[i+1])*183+Int(bytes[i+2])*19)/256
   histogram[min(15,l/16)]+=1/Double(w*h)
  }
  return histogram
 }
 static func distance(_ a:[Double]?,_ b:[Double]?)->Double? {
  guard let a,let b,a.count==16,b.count==16 else{return nil}
  return min(1,max(0,zip(a,b).reduce(0){$0+abs($1.0-$1.1)}/2))
 }
}
