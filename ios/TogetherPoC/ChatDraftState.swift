import Foundation
import Combine

// Editing publishes only to input views, never to the room/player controller.
@MainActor final class ChatDraftState: ObservableObject {
 @Published var text=""
}
@MainActor final class ClientFeedback: ObservableObject {
 @Published var status="未连接"
 @Published var requestStatus=""
}
