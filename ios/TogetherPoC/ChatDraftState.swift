import Foundation
import Combine

// Editing publishes only to input views, never to the room/player controller.
@MainActor final class ChatDraftState: ObservableObject {
 @Published var text=""
}
@MainActor final class ClientFeedback: ObservableObject {
 @Published var status="未连接"
 @Published var requestStatus=""
 @Published private(set) var playbackAction=""
 private var actionClear:Task<Void,Never>?
 func showPlaybackAction(_ value:String) {
  actionClear?.cancel();playbackAction=value
  actionClear=Task { @MainActor [weak self] in
   try? await Task.sleep(nanoseconds:5_000_000_000)
   guard !Task.isCancelled else {return};self?.playbackAction=""
  }
 }

}
