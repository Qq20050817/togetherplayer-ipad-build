import SwiftUI

/// A deliberately opt-in, small-footprint discussion panel. It never pauses
/// synchronized playback and never sends subtitles/film data to the server.
@MainActor struct PlotPollPanel: View {
 @ObservedObject var model:TestClient
 @Environment(\.dismiss) private var dismiss
 @State private var preview:PlotQuestion?
 @State private var generating=false
 @State private var selected=""
 @State private var custom=""
 @StateObject private var authProbe=ChatGPTAuthProbe()
 var body:some View {
  NavigationStack {
   ScrollView {
    VStack(alignment:.leading,spacing:18) {
     if let poll=model.plotPoll,let id=poll["id"] as? String {
      let title=poll["question"] as? String ?? ""
      let options=poll["options"] as? [String] ?? []
      let revealed=poll["revealed"] as? Bool ?? false
      VStack(alignment:.leading,spacing:12) {
       Label("正在投票 · \(Int(((poll["positionMs"] as? Double ?? 0)/1000)/60)) 分钟",systemImage:"theatermasks.fill").font(.headline)
       Text(title).font(.title3.bold())
       if !model.plotPollSubmitted {
        ForEach(options,id:\.self) {option in
         Button {selected=option;custom=""} label:{
          HStack {Image(systemName:selected==option ? "largecircle.fill.circle" : "circle");Text(option);Spacer()}
           .padding(10).background(Color.white.opacity(selected==option ? 0.18:0.06)).clipShape(RoundedRectangle(cornerRadius:9))
         }.buttonStyle(.plain)
        }
        TextField("✏️ 自己填写答案（始终可用）",text:$custom,axis:.vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
        Button("提交我的回答") {
         model.answerPlotPoll(custom.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? selected : custom)
         selected="";custom=""
        }.disabled(custom.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && selected.isEmpty)
         .buttonStyle(.borderedProminent)
       } else {Label("你已经回答，答案已锁定",systemImage:"checkmark.seal.fill")}
       if revealed {
        Text("双方均已回答 · 观点对照").font(.headline)
        ForEach(model.plotPollAnswers.keys.sorted(),id:\.self){userID in
         let name=model.members.first(where:{$0.userId==userID})?.name ?? (userID==model.plotMyUserID ? "我":"好友")
         Text("\(name)：\(model.plotPollAnswers[userID] ?? "")").padding(8)
          .frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:8))
        }
       } else {Text("双方都提交以后才公开答案，避免互相影响。").font(.caption).foregroundStyle(.secondary)}
      }
      .id(id)
     } else {Text("还没有剧情问题。房主可以根据已播放的字幕出一道题；没有字幕也能使用免费问题模板。")
      .foregroundStyle(.secondary)}
     if model.isRoomHost {
      Divider()
      Button {
       generating=true
       Task {
        preview=await PlotPromptMaker.create(excerpt:model.externalSubtitles.observedPlotExcerpt())
        generating=false
       }
      } label:{Label(generating ? "正在本地生成…" : "根据当前剧情出一道题",systemImage:"sparkles")}
       .disabled(generating || !model.isConnected)
       .buttonStyle(.borderedProminent)
      if let draft=preview {
       Text(draft.source).font(.caption).foregroundStyle(.secondary)
       Text(draft.text).font(.headline)
       ForEach(draft.choices,id:\.self){choice in Text("○ \(choice)").font(.subheadline)}
       Button("发布问题给两个人") {model.publishPlotPoll(draft);preview=nil}.disabled(!model.isConnected)
      }
     }
     DisclosureGroup("🧪 ChatGPT 首次授权及连续调用试验") {
      VStack(alignment:.leading,spacing:12) {
       Text("首次登录将打开官方 ChatGPT 授权页面。只保留本机授权，不把密码、令牌、电影、字幕传给房间服务端。")
        .font(.caption).foregroundStyle(.secondary)
       Text(authProbe.status).font(.callout).accessibilityIdentifier("chatgpt-auth-status")
       Button("Continue with ChatGPT") {authProbe.connect()}
        .disabled(authProbe.working)
        .buttonStyle(.borderedProminent).accessibilityIdentifier("chatgpt-auth-start")
       Button("在播放器内测试调用（可重复点击）") {authProbe.testRepeatedCall()}
        .disabled(!authProbe.connected || authProbe.working)
        .accessibilityIdentifier("chatgpt-auth-test")
       if !authProbe.testText.isEmpty {Text(authProbe.testText).font(.callout)}
       if authProbe.connected {
        Button("清除本机授权",role:.destructive){authProbe.disconnect()}
       }
       Text("授权测试版：若回调无法回到 iPad，请勿多次提交授权；返回应用查看诊断。此入口不会改变默认苹果本地 AI 出题方式。")
        .font(.caption2).foregroundStyle(.secondary)
      }.padding(10)
     }
     Text("隐私：只把问题、选项和回答发送到房间；字幕留在 iPad。设备端 AI 不可用会自动使用免费模板。")
      .font(.caption2).foregroundStyle(.secondary)
    }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
   }
   .navigationTitle("🎭 剧情推理室")
   .toolbar {ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
  }.preferredColorScheme(.dark)
 }
}
