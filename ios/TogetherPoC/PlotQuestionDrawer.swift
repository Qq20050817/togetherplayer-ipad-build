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
 @State private var expanded:Set<Int>=[]
 private let dark=Color(red:0.055,green:0.07,blue:0.10)
 private let tile=Color(red:0.10,green:0.14,blue:0.20)
 private func lines(_ text:String)->[String] {text.components(separatedBy:"\n").filter{!$0.isEmpty}}
 private func number(_ text:String,after prefix:String)->Int {
  guard let part=text.components(separatedBy:prefix).dropFirst().first else{return 0}
  return Int(part.prefix(while:{$0.isNumber})) ?? 0
 }
 private func trim(_ value:String,_ prefix:String)->String {value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value}
 private func typeName(_ title:String)->String {
  if title.contains("🎮") {return "🎮 互动关卡"}
  if title.contains("为什么") || title.contains("动机") {return "🎭 人物动机"}
  if title.contains("时间") || title.contains("先后") {return "⏱ 时间线"}
  return "🧩 剧情推理"
 }
 @ViewBuilder private func summary(_ header:String)->some View {
  let info=lines(header)
  let total=number(header,after:"本轮发题 ")
  let done=number(header,after:"完成 ")
  VStack(alignment:.leading,spacing:12) {
   Label("本轮成绩",systemImage:"trophy.fill").font(.title3.bold()).foregroundStyle(.yellow)
   Text(info.first ?? "电影观影结算").font(.callout.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
   HStack {
    Label("共 \(total) 题",systemImage:"square.stack")
    Spacer()
    Label("完成 \(done) 题",systemImage:"checkmark.circle.fill").foregroundStyle(.green)
   }.font(.subheadline)
   ProgressView(value:Double(done),total:Double(max(total,1))).tint(.green)
   ForEach(info.filter{$0.hasPrefix("成绩：")},id:\.self) {score in
    Text(score).font(.subheadline.weight(.medium)).padding(10)
     .frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:8))
   }
  }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
   .background(tile).clipShape(RoundedRectangle(cornerRadius:14))
   .accessibilityIdentifier("recap-summary-card")
 }
 @ViewBuilder private func question(_ part:String,number index:Int)->some View {
  let info=lines("第"+part)
  let heading=info.first ?? "第\(index)题"
  let right=info.first(where:{$0.hasPrefix("正确答案：")})
  let evidence=info.filter{$0.hasPrefix("关键证据：")}
  let explanation=info.first(where:{$0.hasPrefix("剧情解析：")}).map{trim($0,"剧情解析：")} ?? ""
  let submitted=info.filter{!$0.hasPrefix("第") && !$0.hasPrefix("正确答案：") && !$0.hasPrefix("关键证据：") && !$0.hasPrefix("剧情解析：") && !$0.hasPrefix("开放讨论题") && !$0.hasPrefix("本轮") && !$0.hasPrefix("所有答案")}
  let wrong=submitted.contains(where:{$0.contains(" ✗")})
  let good=submitted.contains(where:{$0.contains(" ✓")})
  VStack(alignment:.leading,spacing:0) {
   Button {
    if expanded.contains(index){expanded.remove(index)}else{expanded.insert(index)}
   } label:{
    HStack(alignment:.top,spacing:10) {
     VStack(alignment:.leading,spacing:7) {
      Text(typeName(heading)).font(.caption.bold()).foregroundStyle(.cyan)
      Text(heading).font(.callout.weight(.semibold)).fixedSize(horizontal:false,vertical:true).foregroundStyle(.white)
      if wrong {Label("存在答错",systemImage:"xmark.circle.fill").foregroundStyle(.orange)}
      else if good {Label("已答对",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}
      else {Label("查看答案",systemImage:"questionmark.circle").foregroundStyle(.secondary)}
     }.font(.caption)
     Spacer(minLength:4)
     Image(systemName:expanded.contains(index) ? "chevron.up.circle.fill":"chevron.down.circle")
      .font(.title3).foregroundStyle(.cyan)
    }.padding(13).frame(maxWidth:.infinity,alignment:.leading)
   }.buttonStyle(.plain)
   if expanded.contains(index) {
    Divider().overlay(.white.opacity(0.08))
    VStack(alignment:.leading,spacing:12) {
     if let right {
      Label(trim(right,"正确答案："),systemImage:"checkmark.seal.fill")
       .foregroundStyle(.green).font(.callout.weight(.semibold))
     } else {Label("开放讨论题 · 不计分",systemImage:"bubble.left.and.bubble.right").foregroundStyle(.cyan)}
     ForEach(submitted,id:\.self) {vote in Text(vote).font(.subheadline).foregroundStyle(.white.opacity(0.82))}
     if !explanation.isEmpty {
      let sentences=explanation.split(separator:"。",omittingEmptySubsequences:true).map{String($0)}
      VStack(alignment:.leading,spacing:5) {
       Label("一句话结论",systemImage:"lightbulb.fill").foregroundStyle(.yellow).font(.caption.bold())
       Text((sentences.first ?? explanation)+"。").font(.subheadline)
      }.frame(maxWidth:.infinity,alignment:.leading)
      if sentences.count>1 {
       Label("剧情意义",systemImage:"arrow.triangle.branch").foregroundStyle(.cyan).font(.caption.bold())
       Text(sentences.dropFirst().joined(separator:"。")+"。").font(.subheadline).foregroundStyle(.white.opacity(0.85))
      }
     }
     if !evidence.isEmpty {
      Label("关键证据",systemImage:"doc.text.magnifyingglass").font(.caption.bold()).foregroundStyle(.cyan)
      ForEach(evidence.prefix(3),id:\.self) {item in
       HStack(alignment:.top,spacing:8) {
        Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)
        Text(trim(item,"关键证据：")).font(.subheadline).fixedSize(horizontal:false,vertical:true)
       }
      }
     }
    }.padding(13).frame(maxWidth:.infinity,alignment:.leading).background(Color.black.opacity(0.12))
   }
  }.background(tile).clipShape(RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).stroke(wrong ? Color.orange.opacity(0.45) : .white.opacity(0.06)))
   .accessibilityIdentifier("recap-question-card-\(index)")
 }
 @ViewBuilder private func movieReview(_ source:String)->some View {
  let items=lines(source)
  let beats=items.filter{$0.hasPrefix("剧情节点：")}
  let people=items.filter{$0.hasPrefix("人物关系：")}
  let theme=items.first(where:{$0.hasPrefix("主题解读：")}).map{trim($0,"主题解读：")}
  let topic=items.first(where:{$0.hasPrefix("观后讨论：")}).map{trim($0,"观后讨论：")}
  VStack(alignment:.leading,spacing:13) {
   Label("🎞 全片复盘",systemImage:"film.stack").font(.title3.bold())
   Text("从剧情脉络到人物动机，1～2 分钟回顾整部电影。").font(.caption).foregroundStyle(.secondary)
   if !beats.isEmpty {
    Label("关键剧情时间线",systemImage:"point.3.connected.trianglepath.dotted").font(.subheadline.bold()).foregroundStyle(.cyan)
    ForEach(beats,id:\.self) {beat in
     let segments=trim(beat,"剧情节点：").components(separatedBy:"｜")
     HStack(alignment:.top,spacing:10) {
      Image(systemName:"circle.inset.filled").foregroundStyle(.cyan)
      VStack(alignment:.leading,spacing:4) {
       Text(segments.count>1 ? segments[1] : "剧情节点").font(.callout.bold())
       Text(segments.last ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.8))
      }
     }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:9))
    }
   }
   if !people.isEmpty {
    Label("人物关系与动机",systemImage:"person.2.fill").font(.subheadline.bold()).foregroundStyle(.cyan)
    ForEach(people,id:\.self) {person in
     let segments=trim(person,"人物关系：").components(separatedBy:"｜")
     VStack(alignment:.leading,spacing:3) {
      Text(segments.first ?? "").font(.callout.bold())
      Text(segments.dropFirst().joined(separator:"｜")).font(.subheadline).foregroundStyle(.white.opacity(0.8))
     }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:9))
    }
   }
   if let theme {
    Label("电影想表达什么",systemImage:"brain.head.profile").font(.subheadline.bold()).foregroundStyle(.yellow)
    Text(theme).font(.subheadline).fixedSize(horizontal:false,vertical:true)
   }
   if let topic {
    Label("留给两个人的问题",systemImage:"bubble.left.and.bubble.right.fill").font(.subheadline.bold()).foregroundStyle(.cyan)
    Text(topic).font(.callout.weight(.medium)).fixedSize(horizontal:false,vertical:true)
   }
  }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
   .background(tile).clipShape(RoundedRectangle(cornerRadius:14))
   .accessibilityIdentifier("recap-film-review-card")
 }
 var body:some View {
  let chunks=report.components(separatedBy:"\n🎞 全片复盘\n")
  let quiz=chunks[0].components(separatedBy:"\n第")
  VStack(alignment:.leading,spacing:14) {
   HStack {
    Label("观影结算",systemImage:"checkmark.seal.fill").font(.headline)
    Spacer()
    Button(action:onClose){Image(systemName:"xmark")}.accessibilityLabel("收起观影结算")
     .accessibilityIdentifier(fullscreen ? "fullscreen-close-film-recap":"close-film-recap")
   }
   ScrollView {
    LazyVStack(alignment:.leading,spacing:12) {
     summary(quiz[0])
     ForEach(quiz.indices.dropFirst(),id:\.self) {index in question(quiz[index],number:index)}
     if chunks.count>1 {movieReview(chunks[1])}
     else {
      Label("这份旧题库暂无全片复盘，新生成的题库可附带时间线与主题解读。",systemImage:"film")
       .font(.caption).foregroundStyle(.secondary).padding(10)
     }
    }
   }.accessibilityIdentifier("film-recap-scroll")
   Text("全部答案仅在片尾公开，回看可在剧情推理室重新查看。").font(.caption).foregroundStyle(.secondary)
  }.padding(18).background(dark).clipShape(RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.08)))
   .preferredColorScheme(.dark).accessibilityElement(children:.contain)
   .accessibilityIdentifier(fullscreen ? "fullscreen-film-recap-drawer":"film-recap-drawer")
 }
}
