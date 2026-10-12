import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

// Direct UIKit touch tracking avoids competition with SwiftUI's outer tap
// recognizers. The surface is restricted to the movie, away from tool buttons.
@MainActor final class FullscreenTouchView: UIView {
 var onStart:((CGPoint)->Void)?
 var onMove:((CGPoint)->Void)?
 var onEnd:(()->Void)?
 var onCancel:(()->Void)?
 override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
  guard event?.allTouches?.count == 1,let touch=touches.first else {onCancel?();return}
  onStart?(touch.location(in:self))
 }
 override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
  guard event?.allTouches?.count == 1,let touch=touches.first else {onCancel?();return}
  onMove?(touch.location(in:self))
 }
 override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {onEnd?()}
 override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) {onCancel?()}
}

struct FullscreenGestureSurface:UIViewRepresentable {
 var hold:(Bool)->Void
 var tap:()->Void
 var feedback:(String)->Void
 var interacting:(Bool)->Void
 func makeCoordinator()->Coordinator {Coordinator(self)}
 func makeUIView(context:Context)->FullscreenTouchView {
  let view=FullscreenTouchView()
  view.backgroundColor = .clear
  view.isUserInteractionEnabled=true
  view.isMultipleTouchEnabled=true
  view.accessibilityIdentifier="fullscreen-gesture-surface"
  view.isAccessibilityElement=true
  view.accessibilityLabel="全屏播放手势"
  view.accessibilityValue="亮度 \(Int((UIScreen.main.brightness*100).rounded()))%"
  let coordinator=context.coordinator
  coordinator.surface=view
  view.onStart={[weak coordinator] point in coordinator?.start(point)}
  view.onMove={[weak coordinator] point in coordinator?.move(point)}
  view.onEnd={[weak coordinator] in coordinator?.end()}
  view.onCancel={[weak coordinator] in coordinator?.finish()}
  let volume=MPVolumeView(frame:CGRect(x:0,y:0,width:1,height:1))
  volume.alpha=0.01
  volume.showsRouteButton=false
  volume.isUserInteractionEnabled=false
  view.addSubview(volume)
  coordinator.volumeView=volume
  return view
 }
 func updateUIView(_ view:FullscreenTouchView,context:Context) {context.coordinator.parent=self}
 static func dismantleUIView(_ view:FullscreenTouchView,coordinator:Coordinator) {
  coordinator.finish()
  UIScreen.main.brightness=coordinator.originalBrightness
 }
 @MainActor final class Coordinator:NSObject {
  var parent:FullscreenGestureSurface
  weak var surface:FullscreenTouchView?
  var volumeView:MPVolumeView?
  let originalBrightness=UIScreen.main.brightness
  var origin:CGPoint = .zero
  var initial:CGFloat=0
  var left=false
  var tracking=false
  var sliding=false
  var holding=false
  var ignored=false
  var longPress:DispatchWorkItem?
  init(_ parent:FullscreenGestureSurface) {self.parent=parent}
  func start(_ point:CGPoint) {
   finish()
   guard let view=surface else {return}
   tracking=true
   origin=point
   left=point.x<view.bounds.midX
   initial=left ? UIScreen.main.brightness : CGFloat(AVAudioSession.sharedInstance().outputVolume)
   let task=DispatchWorkItem {[weak self] in
    guard let self=self,self.tracking && !self.sliding && !self.ignored else {return}
    self.holding=true
    self.parent.interacting(true)
    self.parent.hold(true)
    self.parent.feedback("长按 · 2× 倍速")
   }
   longPress=task
   DispatchQueue.main.asyncAfter(deadline:.now()+0.35,execute:task)
  }
  func move(_ point:CGPoint) {
   guard tracking,let view=surface else {return}
   let dx=point.x-origin.x,dy=point.y-origin.y
   if !sliding && !ignored {
    guard abs(dx)>12 || abs(dy)>12 else {return}
    longPress?.cancel()
    longPress=nil
    if holding {holding=false;parent.hold(false)}
    if abs(dy)<=abs(dx) {ignored=true;parent.interacting(false);parent.feedback("");return}
    sliding=true
    parent.interacting(true)
   }
   guard sliding else {return}
   let value=min(1,max(0,initial-dy/max(1,view.bounds.height)))
   if left {
    UIScreen.main.brightness=value
    view.accessibilityValue="亮度 \(Int((value*100).rounded()))%"
   } else if let slider=volumeView?.subviews.compactMap({$0 as? UISlider}).first {
    slider.setValue(Float(value),animated:false)
    slider.sendActions(for:.valueChanged)
    view.accessibilityValue="音量 \(Int((slider.value*100).rounded()))%"
   }
   parent.feedback("\(left ? "亮度" : "音量") \(Int(value*100))%")
  }
  func end() {
   let tapped=tracking && !sliding && !holding && !ignored
   finish()
   if tapped {parent.tap()}
  }
  func finish() {
   longPress?.cancel()
   longPress=nil
   if holding {holding=false;parent.hold(false)}
   tracking=false
   sliding=false
   ignored=false
   parent.interacting(false)
   parent.feedback("")
  }
 }
}

struct FullscreenDeviceStatus:View {
 @State private var battery=UIDevice.current.batteryLevel
 var body:some View {
  TimelineView(.periodic(from:.now,by:30)) {context in
   HStack(spacing:8){Text(context.date,style:.time);Image(systemName:"battery.100");Text(battery>=0 ? "\(Int((battery*100).rounded()))%" : "—")}
    .accessibilityIdentifier("fullscreen-device-status").font(.caption.monospacedDigit()).padding(.horizontal,8).padding(.vertical,4).background(.black.opacity(0.4)).clipShape(Capsule())
  }.onAppear {UIDevice.current.isBatteryMonitoringEnabled=true;battery=UIDevice.current.batteryLevel}
   .onReceive(NotificationCenter.default.publisher(for:UIDevice.batteryLevelDidChangeNotification)){_ in battery=UIDevice.current.batteryLevel}
 }
}
