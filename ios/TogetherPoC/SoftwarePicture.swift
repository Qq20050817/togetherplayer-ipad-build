import AVFoundation
import SwiftUI

/// One decoder supplies the inline, fullscreen and subtitle-preview surfaces.
/// Restore the previous visible surface when the frontmost cover is dismissed.
@MainActor final class SoftwarePicture {
 let layer:AVSampleBufferDisplayLayer
 let size:CGSize
 private let hosts=NSPointerArray.weakObjects()
 init(layer:AVSampleBufferDisplayLayer,size:CGSize) {
  self.layer=layer
  self.size=size
  layer.videoGravity = .resizeAspect
 }
 func attach(_ host:SoftwarePictureHost) {
  remove(host)
  hosts.addPointer(Unmanaged.passUnretained(host).toOpaque())
  showTop()
 }
 func detach(_ host:SoftwarePictureHost) {
  remove(host)
  showTop()
 }
 private func remove(_ host:SoftwarePictureHost) {
  for i in (0..<hosts.count).reversed() {
   if hosts.pointer(at:i) == nil || hosts.pointer(at:i) == Unmanaged.passUnretained(host).toOpaque() {hosts.removePointer(at:i)}
  }
 }
 private func showTop() {
  guard let host=hosts.allObjects.last as? SoftwarePictureHost else {layer.removeFromSuperlayer();return}
  if layer.superlayer !== host.layer {host.layer.addSublayer(layer)}
  host.setNeedsLayout()
 }
}
@MainActor final class SoftwarePictureHost:UIView {
 var picture:SoftwarePicture? {
  didSet {
   guard oldValue !== picture else{return}
   oldValue?.detach(self)
   if window != nil {picture?.attach(self)}
  }
 }
 override func didMoveToWindow() {
  super.didMoveToWindow()
  if window != nil {picture?.attach(self)} else {picture?.detach(self)}
 }
 override func layoutSubviews() {
  super.layoutSubviews()
  guard let video=picture?.layer,video.superlayer === layer else{return}
  CATransaction.begin()
  CATransaction.setDisableActions(true)
  video.frame=bounds
  CATransaction.commit()
 }
}
struct SoftwarePictureView:UIViewRepresentable {
 let picture:SoftwarePicture
 func makeUIView(context:Context)->SoftwarePictureHost {SoftwarePictureHost()}
 func updateUIView(_ view:SoftwarePictureHost,context:Context) { view.picture=picture }
 static func dismantleUIView(_ view:SoftwarePictureHost,coordinator:()) {view.picture=nil}
}
