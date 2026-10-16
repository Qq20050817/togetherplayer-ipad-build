import SwiftUI

// A reserved rail beside the movie. Question presentation never covers or
// remounts the playback canvas, and AI configuration stays a separate flow.
@MainActor struct PlotQuestionDrawer:View {
 @ObservedObject var model:TestClient
 let onClose:()->Void
 let onSettings:()->Void
 var fullscreen=false
 @State private var selected=""
 @State private var custom=""
 var body:some View {
  VStack(alignment:.leading,spacing:14) {
   HStack {
    Label("剧情推理",systemImage:"sparkles").font(.headline)
    Spacer()
    Button(action:onClose){Image(systemName:"xmark")}.accessibilityLabel("收起剧情问题")
     .accessibilityIdentifier(fullscreen ? "fullscreen-close-plot-question" : "close-plot-question")
   }
   ScrollView {
    VStack(alignment:.leading,spacing:14) {
     if let poll=model.plotPoll {
      let question=poll["question"] as? String ?? ""
      let options=poll["options"] as? [String] ?? []
      Text(question).font(.title3.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
       .accessibilityIdentifier("plot-drawer-question")
      if model.plotPollWaiting {
       Label(poll["solo"] as? Bool == true ? "回答后继续" : "双方回答后继续",systemImage:"pause.circle").font(.caption).foregroundStyle(.secondary)
      }
      if !model.plotPollSubmitted {
       ForEach(options,id:\.self) {option in
        Button {selected=option;custom=""} label:{
         HStack(alignment:.top,spacing:10) {
          Image(systemName:selected==option ? "checkmark.circle.fill" : "circle")
          Text(option).fixedSize(horizontal:false,vertical:true);Spacer(minLength:0)
         }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
          .background(Color.blue.opacity(selected==option ? 0.24 : 0.08))
          .clipShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain)
       }
       TextField("也可以写下你的推理",text:$custom,axis:.vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
       Button("提交回答") {
        let typed=custom.trimmingCharacters(in:.whitespacesAndNewlines)
        model.answerPlotPoll(typed.isEmpty ? selected : typed)
       }.buttonStyle(.borderedProminent).frame(maxWidth:.infinity)
        .disabled(selected.isEmpty && custom.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("plot-drawer-submit")
      } else if poll["revealed"] as? Bool == true {
       ForEach(model.plotPollAnswers.keys.sorted(),id:\.self) {user in
        Text("\(user==model.plotMyUserID ? "我" : "好友")：\(model.plotPollAnswers[user] ?? "")")
         .font(.callout).padding(10).frame(maxWidth:.infinity,alignment:.leading)
         .background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:10))
       }
      } else {Label("已提交，等待好友",systemImage:"checkmark.circle.fill").font(.callout).foregroundStyle(.secondary)}
     }
    }
   }
   Button("出题与设置",action:onSettings).font(.caption).foregroundStyle(.secondary)
  }.padding(18).background(Color(red:0.055,green:0.07,blue:0.10))
   .clipShape(RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.08)))
   .preferredColorScheme(.dark).accessibilityElement(children:.contain)
   .accessibilityIdentifier(fullscreen ? "fullscreen-plot-question-drawer" : "plot-question-drawer")
   .onChange(of:model.plotPoll?["id"] as? String) {_ in selected="";custom=""}
 }
}

@MainActor struct FilmBankFinalDrawer:View {
 let report:String
 let onClose:()->Void
 var fullscreen=false
 var body:some View {
  VStack(alignment:.leading,spacing:14) {
   HStack {
    Label("观影结算",systemImage:"checkmark.seal.fill").font(.headline)
    Spacer()
    Button(action:onClose){Image(systemName:"xmark")}
     .accessibilityLabel("收起观影结算")
     .accessibilityIdentifier(fullscreen ? "fullscreen-close-film-recap" : "close-film-recap")
   }
   ScrollView {
    LazyVStack(alignment:.leading,spacing:12) {
     let sections=report.components(separatedBy:"\n第")
     ForEach(sections.indices,id:\.self) {index in
      Text(index==0 ? sections[index] : "第"+sections[index])
       .font(index==0 ? .headline : .callout)
       .foregroundStyle(.white)
       .frame(maxWidth:.infinity,alignment:.leading)
       .padding(12)
       .background(Color.white.opacity(0.05))
       .clipShape(RoundedRectangle(cornerRadius:10))
       .textSelection(.enabled)
     }
    }
   }.accessibilityIdentifier("film-recap-scroll")
   Text("所有答案与解析已保存，可在剧情推理室重新查看。")
    .font(.caption).foregroundStyle(.secondary)
  }.padding(18).background(Color(red:0.055,green:0.07,blue:0.10))
   .clipShape(RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.08)))
   .preferredColorScheme(.dark).accessibilityElement(children:.contain)
   .accessibilityIdentifier(fullscreen ? "fullscreen-film-recap-drawer" : "film-recap-drawer")
 }
}
