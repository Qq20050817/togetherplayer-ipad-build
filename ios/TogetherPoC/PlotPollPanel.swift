import SwiftUI

/// A deliberately opt-in, small-footprint discussion panel. It never pauses
/// synchronized playback and never sends subtitles/film data to the server.
@MainActor struct PlotPollPanel: View {
 @ObservedObject var model:TestClient
 @ObservedObject var intelligence:PlotIntelligence
 @Environment(\.dismiss) private var dismiss
 @State private var selected=""
 @State private var custom=""
 @State private var editQuestion=""
 @State private var editOptions:[String]=[]
 @State private var authOpen=false
 @State private var pauseForPoll=false
 init(model:TestClient) {self.model=model;self.intelligence=model.plotIntelligence}
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
       if model.plotPollWaiting {Label("请双方回答后继续播放",systemImage:"pause.circle.fill")}
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
     if model.isRoomHost || (!model.isConnected && model.adapter.player.currentItem != nil) {
      Divider()
      if !model.isConnected {Text("房间已断线：仍可在本机生成问题预览，重新连接后才能发布给好友。").font(.caption).foregroundStyle(.orange)}
      Toggle("答题后继续播放",isOn:$pauseForPoll).disabled(!model.supportsBlockingPolls).accessibilityIdentifier("plot-blocking-mode")
      Text(model.supportsBlockingPolls ? "开启后发布题目时暂停，双方答完才恢复；原本已暂停则保持暂停。" : "当前服务器尚未支持此模式；需先部署试验服务端。")
       .font(.caption).foregroundStyle(.secondary)
      if model.plotPollWaiting {Button("取消本题并保持暂停",role:.destructive) {model.cancelPlotPoll()}}
      Picker("AI 出题模式",selection:$intelligence.mode) {ForEach(PlotMode.allCases){mode in Text(mode.title).tag(mode)}}
       .pickerStyle(.menu).accessibilityIdentifier("plot-ai-mode")
      Text("当前：\(intelligence.selectedModel)").font(.subheadline)
      Text(intelligence.reason).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plot-ai-reason")
      Text("ChatGPT 自动请求 \(intelligence.automaticRequests)/\(intelligence.limit) · 总请求 \(intelligence.requests)").font(.caption)
      Toggle("允许智能调用 ChatGPT",isOn:$intelligence.automaticAllowed)
      Stepper("本片自动调用上限：\(intelligence.limit) 次",value:$intelligence.limit,in:1...50)
      Text("智能省额度已开启：同片段复用、至少间隔3分钟，失败也计数；不会自动重试。手动深度推理单独计数。")
       .font(.caption2).foregroundStyle(.secondary)
      Button("ChatGPT 授权与隐私设置") {authOpen=true}.buttonStyle(.bordered)
      Button {intelligence.generate()} label:{Label(intelligence.working ? "正在分析…" : "根据已观看剧情生成问题",systemImage:"sparkles")}
       .disabled(intelligence.working || model.adapter.player.currentItem == nil)
       .buttonStyle(.borderedProminent)
       .accessibilityIdentifier("plot-ai-generate")
      if intelligence.working {Button("取消分析") {intelligence.cancel()}.buttonStyle(.bordered)}
      Button("手动深度推理一次") {intelligence.generate(manualDeep:true)}.disabled(intelligence.working || model.adapter.player.currentItem == nil)
      if let draft=intelligence.result,intelligence.previewUsable {
       Text(draft.source).font(.caption).foregroundStyle(.secondary)
       TextField("问题预览（可以编辑）",text:$editQuestion,axis:.vertical).textFieldStyle(.roundedBorder).accessibilityIdentifier("plot-question-preview")
       ForEach(editOptions.indices,id:\.self) {index in TextField("候选选项 \(index+1)",text:$editOptions[index]).textFieldStyle(.roundedBorder)}
       Button("重新生成（同片段不会重复调用云端）") {intelligence.generate(regenerate:true)}.disabled(intelligence.working)
       Button("发布问题给两个人") {
        guard intelligence.previewUsable else {return}
        let edited=PlotQuestion(text:editQuestion.trimmingCharacters(in:.whitespacesAndNewlines),choices:editOptions.map{$0.trimmingCharacters(in:.whitespacesAndNewlines)},source:draft.source,evidenceIDs:draft.evidenceIDs,kind:draft.kind,blocking:pauseForPoll)
        model.publishPlotPoll(edited)
       }.disabled(!model.isConnected || !(5...200).contains(editQuestion.count) || editOptions.contains(where:{$0.isEmpty || $0.count>80}) || Set(editOptions).count != editOptions.count).accessibilityIdentifier("plot-publish")
      }
     }
     Text("隐私：房间仅接收问题、选项和回答。剧情记忆保存在本机；只有你同意云端分析且 ChatGPT 授权有效时，才向 OpenAI 发送本题所需的已观看摘要。设备端 AI 不可用会采用免费题库。")
      .font(.caption2).foregroundStyle(.secondary)
    }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
   }
   .navigationTitle("🎭 剧情推理室")
   .toolbar {ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
   .sheet(isPresented:$authOpen) {PlotAuthorizationView(intelligence:intelligence,auth:intelligence.auth)}
   .onChange(of:intelligence.result) {value in if let value {editQuestion=value.text;editOptions=value.choices}}
   .onDisappear {intelligence.cancel()}
  }.preferredColorScheme(.dark)
 }
}

@MainActor struct PlotAuthorizationView:View {
 @ObservedObject var intelligence:PlotIntelligence
 @ObservedObject var auth:ChatGPTAuthProbe
 @Environment(\.dismiss) private var dismiss
 var body:some View {
  NavigationStack {Form {
   Section("云端分析由你控制") {
    Text("仅发送当前已经观看的必要剧情摘要、相关线索和已揭晓的预测。不会发送影片、完整字幕、账号令牌到房间服务，也不会调用另行收费的 API。")
    Toggle("同意向 ChatGPT 发送必要剧情摘要",isOn:$intelligence.consent)
    Link("打开 ChatGPT 用量设置",destination:URL(string:"https://chatgpt.com/settings/usage")!)
    Text("请先在官方用量设置中禁止本应用使用 Credits。应用无法替你修改这一账号设置；该确认不代表服务器已验证设置。")
    Toggle("我已关闭本应用的 Credits 使用",isOn:$intelligence.creditsDisabled)
   }
   Section("ChatGPT 首次授权（只需一次）") {
    Text(auth.status);Text(auth.verificationStatus)
    Button("Continue with ChatGPT") {auth.connect()}.disabled(auth.working)
    Text("首次授权成功后即可出题；下次使用会自动复用或刷新授权，不必再做连续调用测试。下方真实调用检查仅用于故障诊断，每次会消耗一次订阅请求。")
    Button("可选：执行一次调用诊断") {auth.testRepeatedCall()}.disabled(!auth.connected || auth.working || !intelligence.consent || !intelligence.creditsDisabled)
    Text("可选诊断请求：\(auth.diagnosticRequests) 次（最多6次）")
    if !auth.testText.isEmpty {Text(auth.testText)}
    Button("清除本机授权",role:.destructive) {auth.disconnect();intelligence.automaticAllowed=false}
   }
  }.navigationTitle("ChatGPT 授权与隐私").toolbar {Button("完成"){dismiss()}}}
   .sheet(isPresented:Binding(get:{auth.authorizationURL != nil},set:{if !$0 {auth.cancelAuthorization()}})) {
    if let url=auth.authorizationURL {PlotSignInBrowser(url:url,cancelled:{auth.cancelAuthorization()})}
   }
 }
}
