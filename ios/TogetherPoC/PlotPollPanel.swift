import SwiftUI

@MainActor struct PlotPanelCard<Content:View>:View {
 let title:String
 let icon:String
 let content:Content
 init(title:String,icon:String,@ViewBuilder content:()->Content) {self.title=title;self.icon=icon;self.content=content()}
 var body:some View {
  VStack(alignment:.leading,spacing:14) {
   Label(title,systemImage:icon).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
   content
  }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
   .background(Color(red:0.075,green:0.095,blue:0.14)).clipShape(RoundedRectangle(cornerRadius:16))
   .overlay(RoundedRectangle(cornerRadius:16).stroke(.white.opacity(0.07)))
 }
}
@MainActor struct PlotPollPanel:View {
 @ObservedObject var model:TestClient
 @ObservedObject var intelligence:PlotIntelligence
 @ObservedObject var auth:ChatGPTAuthProbe
 @ObservedObject var visuals:PlotVisualSampler
 @ObservedObject var subtitles:ExternalSubtitles
 @Environment(\.dismiss) private var dismiss
 var onClose:(()->Void)?
 @State private var selected=""
 @State private var custom=""
 @State private var editQuestion=""
 @State private var editOptions:[String]=[]
 @State private var authOpen=false
 init(model:TestClient,onClose:(()->Void)?=nil) {
  self.model=model;intelligence=model.plotIntelligence;auth=model.plotIntelligence.auth
  visuals=model.visualSampler;subtitles=model.externalSubtitles;self.onClose=onClose
 }
 var body:some View {
  NavigationStack {
   ScrollView {
    VStack(alignment:.leading,spacing:12) {
     if model.plotPoll != nil {questionCard}
     overview
     if model.isRoomHost || (!model.isConnected && model.adapter.player.currentItem != nil) {
      generationCard
      if intelligence.result != nil && intelligence.previewUsable {previewCard}
      interactionCard
      advancedCard
     }
     Text("只使用已观看内容；向云端发送摘要需先取得你的同意。").font(.caption2).foregroundStyle(.secondary)
    }.padding(14).frame(maxWidth:560).frame(maxWidth:.infinity)
   }.accessibilityIdentifier("plot-settings-scroll").background(Color(red:0.025,green:0.035,blue:0.055))
    .navigationTitle("剧情推理室").navigationBarTitleDisplayMode(.inline)
    .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("完成") {if let onClose {onClose()} else {dismiss()}}.accessibilityIdentifier("plot-settings-close")}}
    .sheet(isPresented:$authOpen) {PlotAuthorizationView(intelligence:intelligence,auth:auth)}
    .onAppear {if let value=intelligence.result {editQuestion=value.text;editOptions=value.choices}}
    .onChange(of:intelligence.result) {value in if let value {editQuestion=value.text;editOptions=value.choices}}
    .onChange(of:model.plotPoll?["id"] as? String) {_ in selected="";custom=""}
    .onDisappear {intelligence.cancel()}
  }.preferredColorScheme(.dark).accessibilityIdentifier("plot-settings-panel")
 }
 private var overview:some View {
  HStack(alignment:.top,spacing:12) {
   Image(systemName:"sparkles").font(.title2).foregroundStyle(.white).frame(width:42,height:42).background(Color.indigo).clipShape(RoundedRectangle(cornerRadius:12))
   VStack(alignment:.leading,spacing:5) {
    Text(intelligence.selectedModel).font(.headline)
    if !auth.modelName.isEmpty && (intelligence.selectedModel.contains("ChatGPT") || !auth.requestPhase.isEmpty || !auth.lastFailure.isEmpty) {Text("本次选用："+auth.modelName).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plot-cloud-model-name")}
    Text(intelligence.working && !auth.requestPhase.isEmpty ? auth.requestPhase : intelligence.reason)
     .font(.caption).foregroundStyle(intelligence.reason.contains("失败") || intelligence.reason.contains("超时") ? Color.orange : Color.secondary).lineLimit(5).accessibilityIdentifier("plot-ai-reason")
   }.frame(maxWidth:.infinity,alignment:.leading)
  }.padding(4)
 }
 private var generationCard:some View {
  PlotPanelCard(title:"根据已观看剧情出题",icon:"wand.and.stars") {
   Picker("AI 出题模式",selection:$intelligence.mode) {ForEach(PlotMode.allCases) {mode in Text(mode.title).tag(mode)}}.pickerStyle(.menu).accessibilityIdentifier("plot-ai-mode")
   Button {intelligence.generate()} label:{
    HStack {if intelligence.working {ProgressView().tint(.white)} else {Image(systemName:"sparkles")};Text(intelligence.working ? "正在分析…" : "生成问题");Spacer()}.frame(maxWidth:.infinity,minHeight:30)
   }.buttonStyle(.borderedProminent).disabled(intelligence.working || model.adapter.player.currentItem == nil).accessibilityIdentifier("plot-ai-generate")
   HStack {
    if intelligence.working {Button("取消分析") {intelligence.cancel()}}
    else {Button("深度推理一次") {intelligence.generate(manualDeep:true)}.disabled(model.adapter.player.currentItem == nil || !auth.connected)}
    Spacer()
    Button(auth.connected ? "连接与隐私" : "连接 ChatGPT") {authOpen=true}.accessibilityIdentifier("plot-chatgpt-settings")
   }.font(.caption).buttonStyle(.bordered)
   Toggle("允许智能调用 ChatGPT",isOn:$intelligence.automaticAllowed).font(.subheadline)
   Text("本片自动请求 \(intelligence.automaticRequests)/\(intelligence.limit) · 总尝试 \(intelligence.requests)").font(.caption).foregroundStyle(.secondary)
   if !auth.lastFailure.isEmpty {Text(auth.lastFailure).font(.caption).foregroundStyle(.orange);Button("检查连接（不消耗推理额度）") {authOpen=true}.font(.caption)}
   if !model.isConnected {Label("当前离线，可预览，连接房间后再发布",systemImage:"wifi.slash").font(.caption).foregroundStyle(.orange)}
  }
 }
 private var interactionCard:some View {
  PlotPanelCard(title:"观影互动",icon:"person.2") {
   Toggle("重要剧情自动提问",isOn:$intelligence.eventDrivenEnabled).disabled(model.isConnected && !model.supportsBlockingPolls).accessibilityIdentifier("plot-event-driven")
   Toggle("答题后继续播放",isOn:$intelligence.pauseForQuestions).disabled(!model.supportsBlockingPolls).accessibilityIdentifier("plot-blocking-mode")
   Text(model.supportsBlockingPolls ? "设置自动保存。单人答完继续，双人需双方答完；原本暂停则保持暂停。" : "当前房间未支持同步答题暂停。").font(.caption).foregroundStyle(.secondary)
   Text(intelligence.autoTriggerStatus).font(.caption).foregroundStyle(.secondary).lineLimit(3).accessibilityIdentifier("plot-auto-trigger-status")
   if model.plotPollWaiting {Button("取消本题并保持暂停",role:.destructive) {model.cancelPlotPoll()}.font(.caption)}
  }
 }
 private var previewCard:some View {
  PlotPanelCard(title:"题目预览",icon:"text.bubble") {
   if let draft=intelligence.result {
    Text(draft.source).font(.caption).foregroundStyle(.secondary)
    TextField("问题预览（可以编辑）",text:$editQuestion,axis:.vertical).lineLimit(2...5).textFieldStyle(.roundedBorder).accessibilityIdentifier("plot-question-preview")
    ForEach(editOptions.indices,id:\.self) {index in TextField("候选选项 \(index+1)",text:$editOptions[index]).textFieldStyle(.roundedBorder)}
    Button("发布问题并回答") {
     guard intelligence.previewUsable else {return}
     model.publishPlotPoll(PlotQuestion(text:editQuestion.trimmingCharacters(in:.whitespacesAndNewlines),choices:editOptions.map{$0.trimmingCharacters(in:.whitespacesAndNewlines)},source:draft.source,evidenceIDs:draft.evidenceIDs,kind:draft.kind,blocking:intelligence.pauseForQuestions))
    }.buttonStyle(.borderedProminent).frame(maxWidth:.infinity)
     .disabled(!model.isConnected || !(5...200).contains(editQuestion.trimmingCharacters(in:.whitespacesAndNewlines).count) || editOptions.contains(where:{$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || $0.count>80}) || Set(editOptions.map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}).count != editOptions.count).accessibilityIdentifier("plot-publish")
    Button("重新生成") {intelligence.generate(regenerate:true)}.disabled(intelligence.working).font(.caption)
   }
  }
 }
 private var questionCard:some View {
  PlotPanelCard(title:"当前问题",icon:"theatermasks") {
   if let poll=model.plotPoll {
    Text(poll["question"] as? String ?? "").font(.headline)
    if model.plotPollWaiting {Text(poll["solo"] as? Bool == true ? "回答后继续播放" : "双方回答后继续播放").font(.caption).foregroundStyle(.secondary)}
    if !model.plotPollSubmitted {
     ForEach(poll["options"] as? [String] ?? [],id:\.self) {option in
      Button {selected=option;custom=""} label:{HStack(alignment:.top) {Image(systemName:selected==option ? "checkmark.circle.fill" : "circle");Text(option).fixedSize(horizontal:false,vertical:true);Spacer()}.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.blue.opacity(selected==option ? 0.22 : 0.08)).clipShape(RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)
     }
     TextField("写下你的推理",text:$custom,axis:.vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
     Button("提交我的回答") {model.answerPlotPoll(custom.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? selected : custom);selected="";custom=""}.buttonStyle(.borderedProminent).disabled(custom.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && selected.isEmpty)
    } else if poll["revealed"] as? Bool == true {
     ForEach(model.plotPollAnswers.keys.sorted(),id:\.self) {user in
      let name=model.members.first(where:{$0.userId==user})?.name ?? (user==model.plotMyUserID ? "我":"好友")
      Text("\(name)：\(model.plotPollAnswers[user] ?? "")").font(.callout).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:10))
     }
    } else {Label("已提交，等待好友",systemImage:"checkmark.circle").font(.callout).foregroundStyle(.secondary)}
   }
  }
 }
 private var advancedCard:some View {
  PlotPanelCard(title:"设置与状态",icon:"slider.horizontal.3") {
   DisclosureGroup("高级设置") {
    VStack(alignment:.leading,spacing:14) {
     Stepper("自动请求上限：\(intelligence.limit) 次",value:$intelligence.limit,in:1...50)
     Text("同片段优先复用，自动请求至少间隔3分钟；失败计数，不自动重试。手动深度推理单独计数。").font(.caption).foregroundStyle(.secondary)
     Text("苹果本地 AI：\(PlotLocalAI.availabilityDetail) · 已采集 \(intelligence.collectedSubtitleCount) 条字幕线索").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plot-model-diagnostics")
     Toggle("本机画面分析（试验）",isOn:$visuals.enabled).accessibilityIdentifier("plot-visual-experiment")
     Text("仅分析已播放画面，保存粗略场景标签，不上传图像。").font(.caption).foregroundStyle(.secondary)
     Text("画面识别：\(visuals.status)").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-visual-status")
     Toggle("PGS 字幕 OCR 供 AI 使用",isOn:$subtitles.convertPGSForAI).accessibilityIdentifier("plot-pgs-ai-only-srt")
     Toggle("原版 PGS 位图显示（试验）",isOn:$subtitles.originalPGSBitmapEnabled).disabled(model.adapter.player.rate>0).accessibilityIdentifier("plot-original-pgs-bitmap-experimental")
     Text("位图显示默认关闭；仅在影片暂停时切换，可能增加解码负担。OCR 不会修改影片或切换观看字幕。").font(.caption).foregroundStyle(.secondary)
     if !subtitles.nativeIndexStatus.isEmpty {Text("内置字幕：\(subtitles.nativeIndexStatus)").font(.caption2).accessibilityIdentifier("plot-native-subtitle-index")}
     Text("预分析：\(intelligence.fullFilmPreparationStatus)").font(.caption2).accessibilityIdentifier("plot-full-film-preanalysis")
     Text(auth.verificationStatus).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-routing-diagnostics")
     Text("TogetherPlayer \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") · 构建 \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "")").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-client-version")
    }.padding(.top,14)
   }
  }
 }
}
@MainActor struct PlotAuthorizationView:View {
 @ObservedObject var intelligence:PlotIntelligence
 @ObservedObject var auth:ChatGPTAuthProbe
 @Environment(\.dismiss) private var dismiss
 var body:some View {
  NavigationStack {
   ScrollView {VStack(alignment:.leading,spacing:12) {
    PlotPanelCard(title:"ChatGPT 连接",icon:"link") {
     Label(auth.connected ? "本机授权已保存" : "尚未连接",systemImage:auth.connected ? "checkmark.circle" : "person.crop.circle").font(.headline)
     Text(auth.status).font(.caption).foregroundStyle(.secondary)
     if !auth.modelName.isEmpty {Text("最近选用的订阅模型："+auth.modelName).font(.caption).foregroundStyle(.secondary)}
     if !auth.lastFailure.isEmpty {Text(auth.lastFailure).font(.caption).foregroundStyle(.orange)}
     Button("Continue with ChatGPT") {auth.connect()}.buttonStyle(.borderedProminent).disabled(auth.working)
     Text(auth.verificationStatus).font(.caption2).foregroundStyle(.secondary)
    }
    PlotPanelCard(title:"隐私与用量",icon:"hand.raised") {
     Toggle("同意发送必要的已观看剧情摘要",isOn:$intelligence.consent)
     Toggle("我已关闭本应用的 Credits 使用",isOn:$intelligence.creditsDisabled)
     Text("仅发送必要文字摘要，影片和令牌不上传房间服务器；不自动使用另行付费的 API。Credits 开关需要在官方设置中关闭，此处是你的确认。").font(.caption).foregroundStyle(.secondary)
     Link("打开官方用量设置",destination:URL(string:"https://chatgpt.com/settings/usage")!).font(.caption)
    }
    PlotPanelCard(title:"连接检查",icon:"network") {
     Text("不发送授权信息或剧情内容，不发起推理请求。网络可达不代表授权或额度已通过验证。").font(.caption).foregroundStyle(.secondary)
     Button(auth.checkingConnection ? "正在检查…" : "检查 OpenAI 连接") {auth.checkConnection()}.buttonStyle(.bordered).disabled(auth.checkingConnection || auth.working || intelligence.working).accessibilityIdentifier("plot-connectivity-check")
     ForEach(auth.connectionResults,id:\.host) {result in Label(result.message,systemImage:result.reachable ? "checkmark.circle" : "exclamationmark.triangle").font(.caption).foregroundStyle(result.reachable ? Color.green : Color.orange)}
     DisclosureGroup("调用诊断") {
      VStack(alignment:.leading,spacing:12) {
       Text("下面会使用本机授权执行一次真实调用，消耗一次请求；连接检查本身不消耗推理额度。").font(.caption)
       Button("执行一次调用诊断") {auth.testRepeatedCall()}.disabled(!auth.connected || auth.working || intelligence.working || !intelligence.consent || !intelligence.creditsDisabled)
       Text("诊断请求 \(auth.diagnosticRequests)/6").font(.caption)
       if !auth.testText.isEmpty {Text(auth.testText).font(.caption)}
      }.padding(.top,12)
     }
     Button("清除本机授权",role:.destructive) {auth.disconnect();intelligence.automaticAllowed=false}.font(.caption)
    }
   }.padding(14).frame(maxWidth:560).frame(maxWidth:.infinity)}
    .background(Color(red:0.025,green:0.035,blue:0.055)).navigationTitle("ChatGPT 连接与隐私").navigationBarTitleDisplayMode(.inline).toolbar {Button("完成") {dismiss()}.accessibilityIdentifier("plot-auth-close")}
  }.preferredColorScheme(.dark)
   .sheet(isPresented:Binding(get:{auth.authorizationURL != nil},set:{if !$0 {auth.cancelAuthorization()}})) {
    if let url=auth.authorizationURL {PlotSignInBrowser(url:url,cancelled:{auth.cancelAuthorization()})}
   }
 }
}
