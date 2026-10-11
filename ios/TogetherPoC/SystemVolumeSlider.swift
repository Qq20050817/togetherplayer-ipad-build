import SwiftUI
import MediaPlayer

// MPVolumeView controls the active system output route without private APIs.
struct SystemVolumeSlider:UIViewRepresentable {
 func makeUIView(context:Context)->MPVolumeView {let view=MPVolumeView();view.showsRouteButton=false;return view}
 func updateUIView(_ view:MPVolumeView,context:Context) {}
}
