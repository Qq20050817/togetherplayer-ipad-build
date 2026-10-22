import Foundation

enum VideoRotation {
 static func normalized(_ turns:Int)->Int {((turns % 4)+4)%4}
 static func next(_ turns:Int)->Int {(normalized(turns)+1)%4}
 static func degrees(_ turns:Int)->Int {normalized(turns)*90}
 static func presentation(_ size:CGSize,turns:Int)->CGSize {
  let valid=size.width>0 && size.height>0 ? size : CGSize(width:16,height:9)
  return normalized(turns)%2==0 ? valid : CGSize(width:valid.height,height:valid.width)
 }
 static func renderingSize(picture:CGSize,turns:Int)->CGSize {
  normalized(turns)%2==0 ? picture : CGSize(width:picture.height,height:picture.width)
 }
}
