import SwiftUI
import UIKit

// Native tracking has distinct end/cancel events. Accessibility value changes
// commit immediately without fabricating a permanently active drag session.
@MainActor struct PlaybackSeekSlider:UIViewRepresentable {
 var value:Double
 var duration:Double
 var enabled:Bool
 var preview:(Double)->Void
 var commit:(Double)->Void
 var cancel:()->Void
 func makeCoordinator()->Coordinator {Coordinator(self)}
 func makeUIView(context:Context)->UISlider {
  let slider=UISlider()
  slider.minimumValue=0;slider.maximumValue=Float(max(1,duration))
  slider.accessibilityLabel="影片进度";slider.accessibilityIdentifier="movie-progress"
  slider.addTarget(context.coordinator,action:#selector(Coordinator.begin(_:)),for:.touchDown)
  slider.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)
  slider.addTarget(context.coordinator,action:#selector(Coordinator.end(_:)),for:[.touchUpInside,.touchUpOutside])
  slider.addTarget(context.coordinator,action:#selector(Coordinator.abort(_:)),for:.touchCancel)
  return slider
 }
 func updateUIView(_ slider:UISlider,context:Context){
  context.coordinator.parent=self
  slider.isEnabled=enabled
  let upper=Float(max(1,duration.isFinite ? duration : 1))
  if slider.maximumValue != upper {slider.maximumValue=upper}
  if !slider.isTracking && !context.coordinator.tracking {
   let current=Float(min(Double(upper),max(0,value.isFinite ? value : 0)))
   if slider.value != current {slider.setValue(current,animated:false)}
  }
 }
 @MainActor final class Coordinator:NSObject {
  var parent:PlaybackSeekSlider
  private(set) var tracking=false
  init(_ parent:PlaybackSeekSlider){self.parent=parent}
  @objc func begin(_ slider:UISlider){tracking=true;parent.preview(Double(slider.value))}
  @objc func changed(_ slider:UISlider){
   if tracking || slider.isTracking {tracking=true;parent.preview(Double(slider.value))}
   else {parent.commit(Double(slider.value))}
  }
  @objc func end(_ slider:UISlider){
   guard tracking else{return}
   tracking=false;parent.commit(Double(slider.value))
  }
  @objc func abort(_ slider:UISlider){tracking=false;parent.cancel()}
 }
}
