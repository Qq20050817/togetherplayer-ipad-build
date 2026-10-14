import SwiftUI

/// Only panel content animates. Reserving its width is a single layout change,
/// so the AVPlayer surface is not resized on every spring-animation frame.
@MainActor struct PlotSideRail<Settings:View,Question:View>:View {
 let width:CGFloat
 let settingsOpen:Bool
 let questionOpen:Bool
 let settings:Settings
 let question:Question
 init(width:CGFloat,settingsOpen:Bool,questionOpen:Bool,@ViewBuilder settings:()->Settings,@ViewBuilder question:()->Question) {
  self.width=width;self.settingsOpen=settingsOpen;self.questionOpen=questionOpen
  self.settings=settings();self.question=question()
 }
 var body:some View {
  ZStack {
   if settingsOpen {settings.transition(.opacity)}
   else if questionOpen {question.transition(.opacity)}
  }.animation(.easeOut(duration:0.16),value:settingsOpen)
   .animation(.easeOut(duration:0.16),value:questionOpen)
   .frame(width:settingsOpen || questionOpen ? width : 0)
   .clipped()
 }
}
