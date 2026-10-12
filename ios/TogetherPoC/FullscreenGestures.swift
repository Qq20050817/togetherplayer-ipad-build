import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

// Installed only over the full-screen movie, never over transport/tool buttons.
struct FullscreenGestureSurface:UIViewRepresentable {
 var hold:(Bool)->Void
 var tap:()->Void
 var feedback:(String)->Void
 var interacting:(Bool)->Void
 func makeCoordinator()->Coordinator {Coordinator(self)}
 func makeUIView(context:Context)->UIView {
  let view=UIView();view.backgroundColor = .clear
  view.accessibilityIdentifier="fullscreen-gesture-surface";view.isAccessibilityElement=true;view.accessibilityLabel="全屏播放手势";view.accessibilityValue="亮度 \(Int((UIScreen.main.brightness*100).rounded()))%"
  let c=context.coordinator;c.surface=view
  let volume=MPVolumeView(frame:CGRect(x:0,y:0,width:1,height:1));volume.alpha=0.01;volume.showsRouteButton=false;volume.isUserInteractionEnabled=false
  view.addSubview(volume);c.volumeView=volume
  let pan=UIPanGestureRecognizer(target:c,action:#selector(Coordinator.pan(_:)));pan.maximumNumberOfTouches=1
  let press=UILongPressGestureRecognizer(target:c,action:#selector(Coordinator.press(_:)));press.minimumPressDuration=0.35;press.allowableMovement=12
  let tap=UITapGestureRecognizer(target:c,action:#selector(Coordinator.tap(_:)));tap.require(toFail:press);tap.require(toFail:pan)
  view.addGestureRecognizer(pan);view.addGestureRecognizer(press);view.addGestureRecognizer(tap)
  return view
 }
 func updateUIView(_ view:UIView,context:Context) {context.coordinator.parent=self}
 static func dismantleUIView(_ view:UIView,coordinator:Coordinator) {coordinator.finish();UIScreen.main.brightness=coordinator.originalBrightness}
 @MainActor final class Coordinator:NSObject {
  var parent:FullscreenGestureSurface
  weak var surface:UIView?
  var volumeView:MPVolumeView?
  let originalBrightness=UIScreen.main.brightness
  var initial:CGFloat=0;var left=false;var holding=false
  init(_ parent:FullscreenGestureSurface){self.parent=parent}
  @objc func tap(_ recognizer:UITapGestureRecognizer){parent.tap()}
  @objc func press(_ r:UILongPressGestureRecognizer){
   if r.state == .began {holding=true;parent.interacting(true);parent.hold(true);parent.feedback("长按 · 2× 倍速")}
   else if r.state == .ended || r.state == .cancelled || r.state == .failed {finish()}
  }
  func finish(){if holding {holding=false;parent.hold(false)};parent.interacting(false);parent.feedback("")}
  @objc func pan(_ r:UIPanGestureRecognizer){
   guard let view=surface else {return}
   if r.state == .began {
    let translation=r.translation(in:view)
    guard abs(translation.y)>abs(translation.x) else {r.isEnabled=false;r.isEnabled=true;return}
    finish();parent.interacting(true)
    left=(r.location(in:view).x-translation.x)<view.bounds.width/2
    initial=left ? UIScreen.main.brightness : CGFloat(AVAudioSession.sharedInstance().outputVolume)
   }
   if r.state == .began || r.state == .changed {
    let value=min(1,max(0,initial-r.translation(in:view).y/max(1,view.bounds.height)))
    if left {UIScreen.main.brightness=value;view.accessibilityValue="亮度 \(Int((UIScreen.main.brightness*100).rounded()))%"}
    else if let slider=volumeView?.subviews.compactMap({$0 as? UISlider}).first {slider.setValue(Float(value),animated:false);slider.sendActions(for:.valueChanged);view.accessibilityValue="音量 \(Int((slider.value*100).rounded()))%"}
    parent.feedback("\(left ? "亮度" : "音量") \(Int(value*100))%")
   } else if r.state == .ended || r.state == .cancelled || r.state == .failed {parent.interacting(false);parent.feedback("")}
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
