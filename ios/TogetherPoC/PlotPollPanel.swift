import SwiftUI
import UniformTypeIdentifiers

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
 @ObservedObject var materials:FilmMaterialExportSession
 @ObservedObject var bank:FilmQuestionBankRuntime
 @Environment(\.dismiss) private var dismiss
 var onClose:(()->Void)?
 @State private var selected=""
 @State private var custom=""
 @State private var editQuestion=""
 @State private var editOptions:[String]=[]
 @State private var authOpen=false
 @State private var advancedOpen=false
 @State private var aiOnlySubtitlePickerOpen=false
 @State private var bankPickerOpen=false
 @State private var materialsPreviewOpen=false
 @State private var restartBankRound=false
 init(model:TestClient,onClose:(()->Void)?=nil) {
  self.model=model;intelligence=model.plotIntelligence;auth=model.plotIntelligence.auth
  materials=model.filmMaterials;bank=model.questionBankRuntime
  self.onClose=onClose
 }
 var body:some View {
  NavigationStack {
   ScrollView {
    LazyVStack(alignment:.leading,spacing:12) {
     if model.plotPoll != nil {questionCard}
     overview
     if model.isRoomHost || (!model.isConnected && model.adapter.player.currentItem != nil) {
      offlineMaterialsAndQuestionBank
      if bank.active==nil {generationCard}
      if bank.active==nil && intelligence.result != nil && intelligence.previewUsable {previewCard}
      if bank.active==nil {interactionCard;advancedCard}
     }
     Text("点击提取时才扫描素材；由你手动分享给 ChatGPT。导入题库后，观影时不再请求 AI。").font(.caption2).foregroundStyle(.secondary)
    }.padding(14).frame(maxWidth:560).frame(maxWidth:.infinity)
   }.accessibilityIdentifier("plot-settings-scroll").background(Color(red:0.025,green:0.035,blue:0.055))
    .navigationTitle("剧情推理室").navigationBarTitleDisplayMode(.inline)
    .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("完成") {if let onClose {onClose()} else {dismiss()}}.accessibilityIdentifier("plot-settings-close")}}
    .sheet(isPresented:$materialsPreviewOpen) {FilmMaterialsPreview(session:materials)}
    .confirmationDialog("开始新一轮题库？已发布记录会重置，原题库保留。",isPresented:$restartBankRound,titleVisibility:.visible) {Button("开始新一轮",role:.destructive){bank.startNewRound()}}
    .sheet(isPresented:$authOpen) {PlotAuthorizationView(intelligence:intelligence,auth:auth)}
    .fileImporter(isPresented:$bankPickerOpen,allowedContentTypes:[.json]) { result in
     if case .success(let url)=result {
      Task {await bank.importFile(url,filmKey:model.bankMovieKey,source:model.bankMovieURL,durationMs:model.adapter.duration)}
     }
    }
    .sheet(isPresented:$aiOnlySubtitlePickerOpen) {
     SubtitleDocumentPicker(onPick:{url in
      aiOnlySubtitlePickerOpen=false
      Task {await model.importFullFilmSubtitleForAI(url)}
     },onCancel:{aiOnlySubtitlePickerOpen=false})
    }
    .onAppear {
     if let value=intelligence.result {editQuestion=value.text;editOptions=value.choices}
     #if DEBUG
     if ProcessInfo.processInfo.environment["TOGETHER_PLOT_AUTOPAUSE_IN_SETTINGS_UI_TEST"]=="1" {
      DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
       model.plotPoll=["id":"qa-question-over-settings","question":"警方找到的钥匙为什么与证词矛盾？","options":["证人隐瞒来源","有人交换钥匙","还需核实时间"],"positionMs":42000.0,"blocking":true,"waitingForAnswers":true,"revealed":false,"submitted":[String](),"answers":[String:String]()]
      }
     }
     #endif
    }
    .onChange(of:intelligence.result) {value in if let value {editQuestion=value.text;editOptions=value.choices}}
    .onChange(of:model.plotPoll?["id"] as? String) {_ in selected="";custom=""}
    .onDisappear {if intelligence.shouldCancelOnPanelDismissal {intelligence.cancel()}}
  }.preferredColorScheme(.dark).accessibilityIdentifier("plot-settings-panel")
 }
 private var overview:some View {
  HStack(alignment:.top,spacing:12) {
   Image(systemName:"sparkles").font(.title2).foregroundStyle(.white).frame(width:42,height:42).background(Color.indigo).clipShape(RoundedRectangle(cornerRadius:12))
   VStack(alignment:.leading,spacing:5) {
    Text(bank.active == nil ? intelligence.selectedModel : "离线电影题库").font(.headline)
    if bank.active == nil && !auth.modelName.isEmpty && (intelligence.selectedModel.contains("ChatGPT") || !auth.requestPhase.isEmpty || !auth.lastFailure.isEmpty) {Text("本次选用："+auth.modelName).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plot-cloud-model-name")}
    Text(bank.active != nil ? bank.status : (intelligence.working && !auth.requestPhase.isEmpty ? auth.requestPhase : intelligence.reason))
     .font(.caption).foregroundStyle(bank.active == nil && (intelligence.reason.contains("失败") || intelligence.reason.contains("超时")) ? Color.orange : Color.secondary).lineLimit(5).accessibilityIdentifier("plot-ai-reason")
   }.frame(maxWidth:.infinity,alignment:.leading)
  }.padding(4)
 }
 private var generationCard:some View {
  PlotPanelCard(title:"旧版实时 AI（仅手动）",icon:"wand.and.stars") {
   WholeFilmStatusCard(host:intelligence.wholeFilm,retry:{model.prepareCompleteFilmForAI(force:true)},importSubtitle:{aiOnlySubtitlePickerOpen=true},importStatus:model.aiOnlySubtitleImportStatus)
   Picker("AI 出题模式",selection:$intelligence.mode) {ForEach(PlotMode.allCases) {mode in Text(mode.title).tag(mode)}}.pickerStyle(.menu).accessibilityIdentifier("plot-ai-mode")
   Button {intelligence.generate()} label:{
    HStack {if intelligence.working {ProgressView().tint(.white)} else {Image(systemName:"sparkles")};Text(intelligence.working ? "正在分析…" : "生成问题");Spacer()}.frame(maxWidth:.infinity,minHeight:30)
   }.buttonStyle(.borderedProminent).disabled(intelligence.working || auth.loadingModels || model.adapter.player.currentItem == nil).accessibilityIdentifier("plot-ai-generate")
   HStack {
    if intelligence.working {Button("取消分析") {intelligence.cancel()}}
    else {Button("深度推理一次") {intelligence.generate(manualDeep:true)}.disabled(model.adapter.player.currentItem == nil || !auth.connected || auth.loadingModels)}
    Spacer()
    Button(auth.connected ? "连接与隐私" : "连接 ChatGPT") {authOpen=true}.accessibilityIdentifier("plot-chatgpt-settings")
   }.font(.caption).buttonStyle(.bordered)
   Toggle("允许智能调用 ChatGPT",isOn:$intelligence.automaticAllowed).font(.subheadline)
   Text("App 自动请求总计 \(intelligence.automaticRequests)/\(intelligence.limit) · 全部尝试 \(intelligence.requests)").font(.caption).foregroundStyle(.secondary)
   Text("全片分析 \(intelligence.analysisRequests)/\(intelligence.analysisLimit) · 出题 \(intelligence.questionRequests) · 审核 \(intelligence.auditRequests)").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-request-breakdown")
   if intelligence.legacyRequests>0 {Text("旧版未分类请求 \(intelligence.legacyRequests) 次（保留计数，未清零）").font(.caption2).foregroundStyle(.secondary)}
   if !auth.lastFailure.isEmpty {Text(auth.lastFailure).font(.caption).foregroundStyle(.orange);Button("检查连接（不消耗推理额度）") {authOpen=true}.font(.caption)}
   if !model.isConnected {Label("当前离线，可预览，连接房间后再发布",systemImage:"wifi.slash").font(.caption).foregroundStyle(.orange)}
  }
 }
 private var offlineMaterialsAndQuestionBank:some View {
  PlotPanelCard(title:"制作 AI 电影题库",icon:"square.and.arrow.up.on.square") {
   Text("你主动导出字幕与关键画面，交给 ChatGPT 聊天生成题库；播放时不再调用 AI。").font(.caption).foregroundStyle(.secondary)
   Button {
    model.beginFilmMaterialsExport()
   } label:{
    Label(materials.working ? "正在提取完整字幕和关键画面…" : "一键导出电影 AI 素材",systemImage:"film.stack")
   }.buttonStyle(.borderedProminent).disabled(materials.working || model.bankMovieURL == nil)
    .accessibilityIdentifier("plot-export-film-materials")
   Text(model.playbackTitle.isEmpty ? "未选择电影" : model.playbackTitle).font(.caption).lineLimit(2)
   if materials.working {ProgressView(value:materials.progress).accessibilityIdentifier("plot-film-export-progress");Button("取消提取",role:.cancel){materials.cancel()}.accessibilityIdentifier("plot-cancel-film-materials")}
   Button("补充完整外置字幕（仅制作素材）") {aiOnlySubtitlePickerOpen=true}
    .buttonStyle(.bordered).disabled(materials.working || model.bankMovieURL == nil).accessibilityIdentifier("plot-import-material-subtitle")
   if !model.aiOnlySubtitleImportStatus.isEmpty {Text(model.aiOnlySubtitleImportStatus).font(.caption2).foregroundStyle(.secondary)}
   Text(materials.status).font(.caption).foregroundStyle(.secondary)
    .accessibilityIdentifier("plot-film-export-status")
   if let zip=materials.file {
    Button("预览字幕与分镜") {materialsPreviewOpen=true}.buttonStyle(.bordered).accessibilityIdentifier("plot-preview-film-materials")
    ShareLink(item:zip) {Label("分享素材包给 ChatGPT",systemImage:"square.and.arrow.up")}
     .buttonStyle(.bordered).accessibilityIdentifier("plot-share-film-materials")
    ShareLink(items:materials.individualFiles) {Label("分享全部素材文件（不压缩）",systemImage:"square.stack")}.buttonStyle(.bordered).accessibilityIdentifier("plot-share-material-files")
    Menu("单独分享字幕 / 分镜 / Schema") {
     ForEach(materials.individualFiles,id:\.self) {url in ShareLink(item:url){Text(url.lastPathComponent)}}
    }.buttonStyle(.bordered).accessibilityIdentifier("plot-share-one-material")
    Text("已保存至“文件 → 我的 iPad → TogetherPlayer → AI素材”")
     .font(.caption2).foregroundStyle(.secondary)
   }
   Divider()
   Button {
    bankPickerOpen=true
   } label:{
    Label("导入 ChatGPT 制作的 JSON 题库",systemImage:"square.and.arrow.down")
   }.buttonStyle(.borderedProminent).disabled(model.bankMovieURL == nil || bank.importing)
    .accessibilityIdentifier("plot-import-question-bank")
   Text(bank.status).font(.caption).foregroundStyle(.secondary)
    .accessibilityIdentifier("plot-question-bank-status")
   if let active=bank.active {
    Text("题库：\(active.title) · 共 \(active.questions.count) 道题 · 本轮已发布 \(bank.publishedCount) 道 · 已答完 \(bank.completedCount) 道")
     .font(.caption).foregroundStyle(.secondary)
    Text("原片指纹已核对；题目随播放触发，正确答案仅在揭晓后发送。").font(.caption2).foregroundStyle(.secondary)
    Button("开始新一轮题库") {restartBankRound=true}.disabled(bank.importing).accessibilityIdentifier("plot-restart-bank-round")
   }
   if !bank.revealedAnswer.isEmpty {
    Text("剧情已揭晓").font(.headline)
    Text(bank.revealedAnswer).font(.callout).accessibilityIdentifier("plot-question-bank-reveal")
   }
  }
 }
 private var interactionCard:some View {
  PlotPanelCard(title:"观影互动",icon:"person.2") {
   Toggle("重要剧情自动提问",isOn:$intelligence.eventDrivenEnabled).disabled(model.isConnected && !model.supportsBlockingPolls).accessibilityIdentifier("plot-event-driven")
   Toggle("答题后继续播放",isOn:$intelligence.pauseForQuestions).disabled(!model.supportsBlockingPolls).accessibilityIdentifier("plot-blocking-mode")
   Text(model.supportsBlockingPolls ? "设置自动保存。单人答完继续，双人需双方答完；原本暂停则保持暂停。" : "当前房间未支持同步答题暂停。").font(.caption).foregroundStyle(.secondary)
   Text(intelligence.autoTriggerStatus).font(.caption).foregroundStyle(.secondary).lineLimit(3).accessibilityIdentifier("plot-auto-trigger-status")
   Text("本次观影：有效自动题 \(intelligence.automaticQuestionCount) · 提交房间 \(intelligence.automaticPublishCount)。请求次数包含失败，不等于已弹出的题数。").font(.caption2).foregroundStyle(.secondary)
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
   DisclosureGroup("高级设置",isExpanded:$advancedOpen) {
    if advancedOpen {PlotAdvancedSettings(model:model,intelligence:intelligence,auth:auth)}
   }
  }
 }
}
@MainActor private struct PlotAdvancedSettings:View {
 @ObservedObject var model:TestClient
 @ObservedObject var intelligence:PlotIntelligence
 @ObservedObject var auth:ChatGPTAuthProbe
 @ObservedObject var visuals:PlotVisualSampler
 @ObservedObject var subtitles:ExternalSubtitles
 @State private var localAvailability="正在检查系统模型"
 init(model:TestClient,intelligence:PlotIntelligence,auth:ChatGPTAuthProbe) {
  self.model=model;self.intelligence=intelligence;self.auth=auth
  visuals=model.visualSampler;subtitles=model.externalSubtitles
 }
 var body:some View {
    VStack(alignment:.leading,spacing:14) {
     Stepper("本片自动请求总上限：\(intelligence.limit) 次",value:$intelligence.limit,in:1...200)
     Stepper("全片分析子上限：\(intelligence.analysisLimit) 次",value:$intelligence.analysisLimit,in:1...32)
     Text("分析、出题和审核均计入自动总上限；分析另有子上限，并为自动出题预留4次，不会自行提高预算。互动出题至少间隔3分钟；整片分析合并批次、复用缓存，失败不自动重试。手动深度推理单独计数。").font(.caption).foregroundStyle(.secondary)
     Text("苹果本地 AI：\(localAvailability) · 已采集 \(intelligence.collectedSubtitleCount) 条字幕线索").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plot-model-diagnostics")
     Toggle("本机画面分析（试验）",isOn:$visuals.enabled).accessibilityIdentifier("plot-visual-experiment")
     Text("仅分析已播放画面，保存粗略场景标签，不上传图像。").font(.caption).foregroundStyle(.secondary)
     Text("画面识别：\(visuals.status)").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-visual-status")
     Toggle("PGS 字幕 OCR 供 AI 使用",isOn:$subtitles.convertPGSForAI).accessibilityIdentifier("plot-pgs-ai-only-srt")
     Toggle("原版 PGS 位图显示（试验）",isOn:$subtitles.originalPGSBitmapEnabled).disabled(model.adapter.player.rate>0).accessibilityIdentifier("plot-original-pgs-bitmap-experimental")
     Text("位图显示默认关闭；仅在影片暂停时切换，可能增加解码负担。OCR 不会修改影片或切换观看字幕。").font(.caption).foregroundStyle(.secondary)
     if !subtitles.nativeIndexStatus.isEmpty {Text("内置字幕：\(subtitles.nativeIndexStatus)").font(.caption2).accessibilityIdentifier("plot-native-subtitle-index")}
     Text("已看线索：\(intelligence.collectedSubtitleCount)条；全片分析进度见上方").font(.caption2).accessibilityIdentifier("plot-full-film-preanalysis")
     Text(auth.verificationStatus).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-routing-diagnostics")
     Text("TogetherPlayer \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") · 构建 \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "")").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-client-version")
    }.padding(.top,14)
   .onAppear {localAvailability=PlotLocalAI.availabilityDetail}
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
     Text("全片分析 \(intelligence.analysisRequests)/\(intelligence.analysisLimit) · 出题 \(intelligence.questionRequests) · 审核 \(intelligence.auditRequests)").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("plot-request-breakdown")
   if intelligence.legacyRequests>0 {Text("旧版未分类请求 \(intelligence.legacyRequests) 次（保留计数，未清零）").font(.caption2).foregroundStyle(.secondary)}
   if !auth.lastFailure.isEmpty {Text(auth.lastFailure).font(.caption).foregroundStyle(.orange)}
     Button("Continue with ChatGPT") {auth.connect()}.buttonStyle(.borderedProminent).disabled(auth.working || auth.loadingModels || intelligence.working)
     if auth.connected {
      Picker("推理模型",selection:$auth.preferredModelID) {
       Text("自动选择（按账号可用列表）").tag("")
       ForEach(auth.availableModels,id:\.id) {model in Text(model.name).tag(model.id)}
       if !auth.preferredModelID.isEmpty && !auth.availableModels.contains(where:{$0.id==auth.preferredModelID}) {Text("已保存的选择（请刷新列表）").tag(auth.preferredModelID)}
      }.pickerStyle(.menu).disabled(intelligence.working || auth.loadingModels || auth.working).accessibilityIdentifier("plot-model-selector")
      Button(auth.loadingModels ? "正在获取模型…" : "获取可用模型") {auth.refreshModels()}.disabled(auth.loadingModels || auth.working || intelligence.working).accessibilityIdentifier("plot-model-refresh")
      Text("只列出当前账号支持的订阅模型。获取列表不发起推理；指定模型不可用时会提示，不会擅自替换。").font(.caption).foregroundStyle(.secondary)
     }
     Text(auth.verificationStatus).font(.caption2).foregroundStyle(.secondary)
    }
    PlotPanelCard(title:"隐私与用量",icon:"hand.raised") {
     Toggle("同意发送必要的剧情摘要",isOn:$intelligence.consent)
     Toggle("允许 ChatGPT 提前分析全片字幕与剧情",isOn:$intelligence.wholeFilmCloudConsent)
     Text("可能包含未播放的对白、反转和结局，仅供后台策划；全片分析、出题和剧透审核分别显示，仍共同受自动请求总上限保护，不额外使用付费 API。不开启时仅在本机理解全片。").font(.caption).foregroundStyle(.secondary)
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
       Button("执行一次调用诊断") {auth.testRepeatedCall()}.disabled(!auth.connected || auth.working || auth.loadingModels || intelligence.working || !intelligence.consent || !intelligence.creditsDisabled)
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

@MainActor private struct WholeFilmStatusCard:View {
 @ObservedObject var host:WholeFilmHost
 let retry:()->Void
 let importSubtitle:()->Void
 let importStatus:String
 var body:some View {
  VStack(alignment:.leading,spacing:8) {
   Label("全片理解",systemImage:"film.stack").font(.subheadline.weight(.semibold))
   if !host.analysisBackend.isEmpty {Text(host.analysisBackend).font(.caption2).accessibilityIdentifier("plot-whole-film-backend")}
   if host.estimatedCloudRequests>0 {Text("本次续分析预计最多 \(host.estimatedCloudRequests) 次云端请求 · 完成 \(host.completed)/\(host.total) 段").font(.caption2).accessibilityIdentifier("plot-analysis-estimate")}
   Text(host.subtitleSource).font(.caption2).foregroundStyle(.secondary)
   Text(host.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plot-whole-film-status")
   if host.busy || host.readingActive {ProgressView(value:Double(host.completed),total:Double(max(1,host.total)));Button("暂停后台分析"){host.cancel()}}
   else {Button("继续分析（复用已完成片段）",action:retry).font(.caption)}
   Button("导入完整字幕供 AI 分析（不改变播放字幕）",action:importSubtitle)
    .font(.caption).accessibilityIdentifier("plot-import-ai-only-full-subtitle")
   if !importStatus.isEmpty {
    Text(importStatus).font(.caption2).foregroundStyle(.secondary)
     .accessibilityIdentifier("plot-import-ai-only-full-subtitle-status")
   }
  }.frame(maxWidth:.infinity,alignment:.leading)
 }
}
