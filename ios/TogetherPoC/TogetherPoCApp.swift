import SwiftUI
import AVKit
import UniformTypeIdentifiers

@main @MainActor struct TogetherPoCApp: App {
 @StateObject private var model=TestClient(automaticallyConnect:ProcessInfo.processInfo.environment["TOGETHER_UI_TEST"] != "1")
 @Environment(\.scenePhase) private var scenePhase
 var body: some Scene {
  WindowGroup {TestView(model:model,chat:model.chat)}
   .onChange(of:scenePhase) {phase in
    if phase == .background {model.handleBackground()}
    if phase == .active {model.handleForeground()}
   }
 }
}
@MainActor struct TestView: View {
 @ObservedObject var model: TestClient
 @ObservedObject var chat: ChatEngine
 var body: some View {
  TabView {
   WatchScreen(model:model,chat:chat).tabItem {Label("观影",systemImage:"play.rectangle")}.badge(chat.unread)
   RoomScreen(model:model).tabItem {Label("房间与片源",systemImage:"person.2")}
  }.preferredColorScheme(.dark).tint(.blue).onAppear {
   UIApplication.shared.isIdleTimerDisabled=true
   #if DEBUG
   if ProcessInfo.processInfo.environment["TOGETHER_SUBTITLE_SELECTION_TEST"]=="1" {try? LocalPickerUITestFixture.installSubtitle(into:model)}
   if ProcessInfo.processInfo.environment["TOGETHER_PICKER_SELECTION_TEST"]=="1" {try? LocalPickerUITestFixture.install(into:model)}
   if ProcessInfo.processInfo.environment["TOGETHER_ROOM_MEDIA_TEST"]=="1" {try? LocalPickerUITestFixture.installRoomMediaValidation(into:model)}
   if ProcessInfo.processInfo.environment["TOGETHER_LOCAL_QUALITY_TEST"]=="1" {try? LocalPickerUITestFixture.installQualitySelection(into:model)}
   #endif
  }
 }
}
@MainActor struct WatchScreen: View {
 @ObservedObject var model: TestClient
 @ObservedObject var chat: ChatEngine
 @State private var fullscreen=false
 @State private var settings=false
 @State private var sidebar=0
 var body: some View {
  GeometryReader {geometry in
   let wide=geometry.size.width>=900 && geometry.size.width>geometry.size.height
   let sideWidth=wide ? min(320,geometry.size.width*0.26) : 0
   let movieWidth=geometry.size.width-(wide ? sideWidth+48 : 32)
   VStack(spacing:12) {
    header
    ScrollView {
     if wide {
      HStack(alignment:.top,spacing:12) {
       VStack(spacing:12) {watchCard(height:min(movieWidth * CGFloat(9.0/16.0),max(300,geometry.size.height-360)));MediaLibraryPanel(model:model,library:model.library)}.frame(maxWidth:.infinity)
       VStack(spacing:12) {sidePanel(height:max(330,geometry.size.height-290));actions}.frame(width:sideWidth)
      }
     } else {
      VStack(spacing:12) {watchCard(height:movieWidth * CGFloat(9.0/16.0));sidePanel(height:300);MediaLibraryPanel(model:model,library:model.library);actions}
     }
    }
   }.padding(16)
  }.background(Color(red:0.025,green:0.03,blue:0.04)).preferredColorScheme(.dark)
   .onAppear {chat.visible=true;chat.markRead()}.onDisappear {chat.visible=false}
   .sheet(isPresented:$settings) {NavigationStack {RoomScreen(model:model).navigationTitle("房间与片源").toolbar {Button("完成") {settings=false}}}.preferredColorScheme(.dark)}
   .fullScreenCover(isPresented:$fullscreen) {FullscreenWatch(model:model,chat:chat)}
 }
 private var header: some View {
  ViewThatFits(in:.horizontal) {
   HStack(spacing:16) {brand;Spacer();ConnectionPill(model:model,playback:model.playback);Spacer();headerActions}
   VStack {HStack {brand;Spacer();headerActions};ConnectionPill(model:model,playback:model.playback)}
  }
 }
 private var brand: some View {Button {settings=true} label:{Label("一起看",systemImage:"person.2.fill").font(.title3.bold()).foregroundColor(.white)}.accessibilityLabel("打开房间与片源")}
 private var headerActions: some View {
  HStack(spacing:12) {
   ShareLink(item:"一起看电影\n房间：\(model.roomID)\n服务地址：\(model.server)") {Image(systemName:"link").frame(width:36,height:36)}.disabled(!model.isConnected)
   Button {settings=true} label:{Image(systemName:"gearshape").frame(width:36,height:36)}.accessibilityLabel("房间设置")
   Button {model.leaveRoom()} label:{Label("离开房间",systemImage:"rectangle.portrait.and.arrow.right").font(.caption.bold()).padding(10)}.background(Color(red:0.95,green:0.17,blue:0.34)).clipShape(RoundedRectangle(cornerRadius:12)).disabled(!model.isConnected)
  }.foregroundColor(.white)
 }
 private func watchCard(height: CGFloat) -> some View {
  VStack(alignment:.leading,spacing:12) {
   PlaybackCanvas(player:model.adapter.player,subtitles:model.externalSubtitles,chat:chat).frame(height:height)
    .overlay(alignment:.topLeading) {
     VStack(alignment:.leading,spacing:8) {
      Text(model.playbackTitle).font(.headline).lineLimit(1)
      HStack {ForEach(model.videoBadges,id:\.self) {Text($0).font(.caption2.bold()).padding(.horizontal,8).padding(.vertical,4).background(Color.black.opacity(0.5)).clipShape(Capsule())}}
     }.padding(16).shadow(color:.black,radius:4)
    }
    .overlay(alignment:.topTrailing) {
     HStack {Button {sidebar=0} label:{Image(systemName:"text.bubble")}.accessibilityLabel("显示聊天");Button {fullscreen=true} label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.accessibilityLabel("全屏观影")}.font(.title3).padding(16).shadow(color:.black,radius:4)
    }
   VStack(alignment:.leading,spacing:12) {
    PlaybackControls(model:model)
    HStack {TrackControls(model:model,subtitles:model.externalSubtitles);Spacer();Menu {ForEach(["😂","😱","😭","🤯","❤️","👀"],id:\.self) {emoji in Button(emoji) {model.react(emoji)}}} label:{Label("表情",systemImage:"face.smiling")}.disabled(!model.isConnected)}
    if !model.sourceNotice.isEmpty {HStack(alignment:.top) {Text(model.sourceNotice).font(.caption).foregroundColor(.orange);Spacer();Button(model.sourceResetLabel) {model.restoreRoomSource()}.font(.caption).buttonStyle(.bordered)}}
    if !model.roomNotice.isEmpty {Text(model.roomNotice).font(.caption).foregroundColor(.orange)}
    if !model.durationWarning.isEmpty {Text(model.durationWarning).font(.caption).foregroundColor(.orange)}
    RequestFeedback(feedback:model.feedback)
   }.padding(.horizontal,16).padding(.bottom,16)
  }.background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:20)).overlay {RoundedRectangle(cornerRadius:20).stroke(Color.white.opacity(0.07))}
 }
 private func sidePanel(height: CGFloat) -> some View {
  VStack(spacing:12) {
   Picker("侧栏",selection:$sidebar) {Text("聊天").tag(0);Text("成员 \(model.members.count)").tag(1);Text("列表").tag(2)}.pickerStyle(.segmented)
   if sidebar==0 {ChatPanel(model:model,chat:chat)}
   else if sidebar==1 {ScrollView {VStack(alignment:.leading,spacing:16) {ForEach(model.members) {member in
    HStack {Image(systemName:"person.crop.circle.fill").font(.title);VStack(alignment:.leading) {Text(member.name);Text(member.buffering ? "缓冲中" : member.online ? "在线" : "离线").font(.caption).foregroundColor(member.online ? .green : .secondary)};Spacer();Text(PlaybackMonitor.time(member.position/1000)).font(.caption.monospaced())}
   };if model.members.isEmpty {Text("加入房间后显示成员").foregroundStyle(.secondary)}}}}
   else {ScrollView {VStack(alignment:.leading,spacing:12) {ForEach(model.library.items) {item in Button {model.playLibraryItem(item)} label:{Label(item.title,systemImage:"film").lineLimit(2)}.disabled(!model.isRoomHost)};if model.library.items.isEmpty {Text("在下方添加影片到播放列表").font(.caption).foregroundStyle(.secondary)}}}}
  }.padding(14).frame(height:height).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:20)).overlay {RoundedRectangle(cornerRadius:20).stroke(Color.white.opacity(0.07))}
 }
 private var actions: some View {
  VStack(alignment:.leading,spacing:12) {
   Text("一起做什么").font(.headline)
   HStack {Button {sidebar=0} label:{Label("聊天交流",systemImage:"text.bubble.fill")};Menu {ForEach(["😂","😱","😭","🤯","❤️","👀"],id:\.self) {emoji in Button(emoji) {model.react(emoji)}}} label:{Label("发表情",systemImage:"face.smiling")}.disabled(!model.isConnected)}
   HStack {ShareLink(item:"一起看电影\n房间：\(model.roomID)\n服务地址：\(model.server)") {Label("分享房间",systemImage:"link")}.disabled(!model.isConnected);Button {settings=true} label:{Label("房间设置",systemImage:"gearshape")}}
  }.font(.caption).buttonStyle(.bordered).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:20))
 }
}
@MainActor struct ConnectionPill: View {
 @ObservedObject var model: TestClient
 @ObservedObject var playback: PlaybackMonitor
 var body: some View {
  HStack(spacing:8) {Circle().fill(model.isConnected ? (playback.buffering ? .orange : .green) : .gray).frame(width:9,height:9);Text(model.isConnected ? "\(playback.buffering ? "等待缓冲" : playback.playing ? "正在同步播放" : "已暂停") · \(model.members.count)人" : "未连接房间").font(.caption);Image(systemName:"waveform").foregroundColor(.blue)}.padding(.horizontal,14).padding(.vertical,10).background(Color.white.opacity(0.07)).clipShape(Capsule())
 }
}
@MainActor struct MediaLibraryPanel: View {
 @ObservedObject var model: TestClient
 @ObservedObject var library: MediaLibrary
 @State private var category=0
 @State private var adding=false
 private var filtered: [SavedMedia] {category==1 ? library.items.filter(\.favorite) : category==2 ? library.items.filter {$0.lastPlayed != nil}.sorted {($0.lastPlayed ?? .distantPast)>($1.lastPlayed ?? .distantPast)} : library.items}
 var body: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack {Picker("影片",selection:$category) {Text("播放列表").tag(0);Text("我的收藏").tag(1);Text("历史记录").tag(2)}.pickerStyle(.segmented).frame(maxWidth:380);Spacer()}
   ScrollView(.horizontal) {
    HStack(alignment:.top,spacing:12) {
     ForEach(filtered) {item in
      VStack(alignment:.leading,spacing:8) {
       Button {model.playLibraryItem(item)} label:{ZStack {RoundedRectangle(cornerRadius:12).fill(Color.blue.opacity(0.12));Image(systemName:model.engine.room?.mediaUrl==item.url ? "play.circle.fill" : "film").font(.largeTitle).foregroundColor(.blue)}.frame(width:150,height:80)}.disabled(!model.isRoomHost || !model.isConnected)
       Text(item.title).font(.caption).lineLimit(2).frame(width:150,alignment:.leading)
       HStack {Button {library.toggleFavorite(item)} label:{Image(systemName:item.favorite ? "heart.fill" : "heart")}.accessibilityLabel(item.favorite ? "取消收藏" : "收藏影片");Spacer();Button(role:.destructive) {library.remove(item)} label:{Image(systemName:"trash")}.accessibilityLabel("移除影片")}.font(.caption).frame(width:150)
      }
     }
     Button {adding=true} label:{VStack(spacing:10) {Image(systemName:"plus").font(.title);Text("添加影片").font(.caption)}.frame(width:120,height:115).overlay {RoundedRectangle(cornerRadius:12).stroke(Color.white.opacity(0.18),style:StrokeStyle(lineWidth:1,dash:[5]))}}
    }
   }
  }.padding(14).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:20)).sheet(isPresented:$adding) {AddMediaSheet(library:library)}
 }
}
@MainActor struct AddMediaSheet: View {
 @ObservedObject var library: MediaLibrary
 @Environment(\.dismiss) private var dismiss
 @State private var title=""
 @State private var source=""
 @State private var error=""
 var body: some View {
  NavigationStack {Form {TextField("影片名称",text:$title);TextField("已授权的HTTP / HLS影片链接",text:$source).textInputAutocapitalization(.never).autocorrectionDisabled();Text("播放列表只保存可分享的影片地址。百度账户授权链接不会保存到这里。").font(.caption);if !error.isEmpty {Text(error).foregroundColor(.orange)};Button("添加到播放列表") {if library.add(title:title,url:source) {dismiss()} else {error="请输入有效影片地址，不能含账户凭据"}}}.navigationTitle("添加影片").toolbar {Button("取消") {dismiss()}}}.preferredColorScheme(.dark)
 }
}

@MainActor struct PlaybackCanvas: View {
 let player: AVPlayer
 @ObservedObject var subtitles: ExternalSubtitles
 @ObservedObject var chat: ChatEngine
 var bottomInset: Double=0
 @State private var captionHeight:CGFloat=0
 var body: some View {
  GeometryReader {geometry in
   ZStack(alignment:.bottom) {
    Color.black
    StableVideo(player:player).equatable().allowsHitTesting(false)
    if !subtitles.text.isEmpty {
     Text(subtitles.text).font(Font.system(size:CGFloat(SubtitleAppearance.font(subtitles.fontSize)),weight:.semibold)).multilineTextAlignment(.center).foregroundColor(.white).shadow(color:.black,radius:2,x:0,y:1).padding(.horizontal,14).padding(.vertical,6).background(GeometryReader {proxy in Color.clear.preference(key:SubtitleHeightKey.self,value:proxy.size.height)}).padding(.horizontal,24).padding(.bottom,min(max(16,geometry.size.height*CGFloat(SubtitleAppearance.position(subtitles.bottomFraction)))+CGFloat(bottomInset),max(16,geometry.size.height-captionHeight-16))).allowsHitTesting(false)
    }
   }.onPreferenceChange(SubtitleHeightKey.self) {height in if abs(height-captionHeight)>0.5 {captionHeight=height}}.overlay(alignment:.trailing) {VStack {ForEach(chat.reactions) {reaction in Text(reaction.emoji).font(.largeTitle)}}.padding().allowsHitTesting(false)}
  }
 }
}
struct SubtitleHeightKey:PreferenceKey {
 static var defaultValue:CGFloat=0
 static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=max(value,nextValue())}
}
@MainActor struct PlaybackControls: View {
 @ObservedObject var model: TestClient
 @ObservedObject private var playback: PlaybackMonitor
 @State private var dragging=false
 @State private var target=0.0
 @State private var volume=1.0
 init(model: TestClient) {self.model=model;self.playback=model.playback}
 var body: some View {
  VStack(spacing:12) {
   HStack(spacing:10) {
    Text(PlaybackMonitor.time(dragging ? target : playback.position)).font(.caption.monospacedDigit()).frame(minWidth:45)
    Slider(value:Binding(get:{dragging ? target : playback.position},set:{target=$0}),in:0...max(1,playback.duration),onEditingChanged:{editing in if editing {target=playback.position};dragging=editing;if !editing {model.control("SEEK",position:max(0,target*1000-model.engine.timelineOffset))}}).disabled(playback.duration<=0).accessibilityLabel("影片进度")
    Text(PlaybackTime.remaining(duration:playback.duration,position:dragging ? target : playback.position)).font(.caption.monospacedDigit()).fixedSize(horizontal:true,vertical:false).accessibilityIdentifier("playback-remaining")
   }
   ViewThatFits(in:.horizontal) {
    HStack(spacing:18) {volumeControl.frame(width:140);Spacer();transport;Spacer()}
    VStack {transport;volumeControl.frame(maxWidth:180)}
   }
   if let request=model.pending {Button("批准对方：\(request["type"] as? String ?? "播放请求")") {model.approve()}.buttonStyle(.bordered)}
  }.onAppear {volume=Double(model.adapter.player.volume)}
 }
 private var transport: some View {
  HStack(spacing:22) {
   Button {model.neighboringMedia(-1)} label:{Image(systemName:"backward.end.fill")}.disabled(!model.canMoveMedia(-1)).accessibilityLabel("上一部影片")
   Button {model.control("SEEK",position:max(0,model.adapter.position-model.engine.timelineOffset-10000))} label:{Image(systemName:"gobackward.10")}.accessibilityLabel("后退10秒")
   Button {model.control(model.requestedPlaying ? "PAUSE" : "PLAY")} label:{Image(systemName:model.requestedPlaying ? "pause.fill" : "play.fill").foregroundColor(.black).frame(width:56,height:56).background(Color.white).clipShape(Circle())}.accessibilityLabel(model.requestedPlaying ? "暂停" : "播放")
   Button {model.control("SEEK",position:model.adapter.position-model.engine.timelineOffset+10000)} label:{Image(systemName:"goforward.10")}.accessibilityLabel("前进10秒")
   Button {model.neighboringMedia(1)} label:{Image(systemName:"forward.end.fill")}.disabled(!model.canMoveMedia(1)).accessibilityLabel("下一部影片")
  }.font(.title2).foregroundColor(.white)
 }
 private var volumeControl: some View {
  HStack {Button {volume=volume>0 ? 0 : 1;model.adapter.player.volume=Float(volume)} label:{Image(systemName:volume>0 ? "speaker.wave.2.fill" : "speaker.slash.fill")}.accessibilityLabel("切换静音");Slider(value:$volume,in:0...1).onChange(of:volume) {model.adapter.player.volume=Float($0)}.accessibilityLabel("播放音量")}
 }
}

@MainActor struct TrackControls: View {
 @ObservedObject var model: TestClient
 @ObservedObject var subtitles: ExternalSubtitles
 @State private var importing=false
 @State private var adjustingSubtitles=false
 var modalChanged: (Bool) -> Void = {_ in}
 var body: some View {
  VStack(alignment:.leading,spacing:8) {
   ViewThatFits(in:.horizontal) {
    HStack {audioMenu;subtitleMenu;importButton;adjustButton;Spacer()}
    VStack(alignment:.leading) {HStack {audioMenu;subtitleMenu};HStack {importButton;adjustButton}}
   }
   if subtitles.available {
    Text(subtitles.name).font(.caption).lineLimit(1).foregroundStyle(.secondary)
    Button("移除外挂字幕",role:.destructive) {subtitles.clear();model.chooseSubtitle(-1)}
   }
   if !subtitles.status.isEmpty {Text(subtitles.status).font(.caption).foregroundStyle(.secondary)}
  }.buttonStyle(.bordered)
   .onChange(of:importing || adjustingSubtitles) {modalChanged($0)}
   .sheet(isPresented:$importing) {
    SubtitleDocumentPicker(onPick:{url in importing=false;DispatchQueue.main.async {model.importSubtitle(url)}},onCancel:{importing=false;subtitles.cancelImport()})
   }
   .sheet(isPresented:$adjustingSubtitles) {SubtitleAdjustmentPanel(subtitles:subtitles)}
 }
 private var audioMenu: some View {
  Menu {
   Button {model.chooseAudio(-1)} label:{Label("自动选择",systemImage:model.selectedAudioIndex == -1 ? "checkmark" : "waveform")}
   if model.audioLabels.isEmpty {Text("未读取到可选音轨")}
   ForEach(model.audioLabels.indices,id:\.self) {index in Button {model.chooseAudio(index)} label:{Label(model.audioLabels[index],systemImage:model.selectedAudioIndex==index ? "checkmark" : "waveform")}}
  } label:{Label("音轨",systemImage:"waveform")}
 }
 private var subtitleMenu: some View {
  Menu {
   Button {model.chooseSubtitle(-1)} label:{Label("自动（内置）",systemImage:!subtitles.enabled && model.selectedSubtitleIndex == -1 ? "checkmark" : "captions.bubble")}
   Button {model.chooseSubtitle(-2)} label:{Label("关闭字幕",systemImage:!subtitles.enabled && model.selectedSubtitleIndex == -2 ? "checkmark" : "captions.bubble")}
   if model.subtitleLabels.isEmpty {Text("未读取到可选内置文字字幕；可导入外挂字幕")}
   ForEach(model.subtitleLabels.indices,id:\.self) {index in Button {model.chooseSubtitle(index)} label:{Label(model.subtitleLabels[index],systemImage:!subtitles.enabled && model.selectedSubtitleIndex==index ? "checkmark" : "captions.bubble")}}
   if subtitles.available {Button {model.enableExternalSubtitle()} label:{Label("外挂：\(subtitles.name)",systemImage:subtitles.enabled ? "checkmark" : "doc.text")}}
  } label:{Label("字幕",systemImage:"captions.bubble")}
 }
 private var adjustButton:some View {Button {adjustingSubtitles=true} label:{Label("字幕调整",systemImage:"slider.horizontal.3")}.accessibilityIdentifier("subtitle-adjustments")}
 private var importButton: some View {Button {subtitles.beginSelection();importing=true} label:{Label("导入字幕",systemImage:"doc.badge.plus")}.accessibilityIdentifier("import-subtitle")}
}
@MainActor final class FullscreenControlState: ObservableObject {
 @Published var visible=true
 private var timer: Timer?
 deinit {timer?.invalidate()}
 func cancel() {timer?.invalidate();timer=nil}
 func hide() {cancel();visible=false}
 func schedule(allowed: Bool) {
  cancel();guard allowed else {return}
  var timeout=3.0
  #if DEBUG
  if ProcessInfo.processInfo.environment["TOGETHER_UI_TEST"]=="1" {timeout=12}
  #endif
  let next=Timer(timeInterval:timeout,repeats:false) {[weak self] _ in Task {@MainActor in self?.visible=false}}
  timer=next;RunLoop.main.add(next,forMode:.common)
 }
}
@MainActor struct FullscreenWatch: View {
 @ObservedObject var model: TestClient
 @ObservedObject var chat: ChatEngine
 @Environment(\.dismiss) private var dismiss
 @StateObject private var controls=FullscreenControlState()
 @State private var selectingFile=false
 @State private var composing=false
 @State private var adjustingDanmaku=false
 var body: some View {
  VStack(spacing:0) {
   ZStack {
   PlaybackCanvas(player:model.adapter.player,subtitles:model.externalSubtitles,chat:chat,bottomInset:controls.visible && !composing ? 250 : 0)
    .accessibilityElement(children:.contain)
    .accessibilityIdentifier("fullscreen-movie")
    .contentShape(Rectangle()).onTapGesture {
     guard !composing else {return}
     if controls.visible {controls.cancel();withAnimation {controls.visible=false}}
     else {withAnimation {controls.visible=true};scheduleHide()}
    }
   DanmakuOverlay(chat:chat).padding(.top,controls.visible && !composing ? 60 : 12).allowsHitTesting(false)
   if controls.visible && !composing {VStack {
    HStack {Text(model.roomTitle).lineLimit(1);Spacer();Button("退出全屏") {dismiss()}}.padding(12).background(Color.black.opacity(0.65))
    Spacer()
    VStack {PlaybackControls(model:model);HStack {Button {composing=true} label:{Label("发弹幕",systemImage:"text.bubble.fill")}.buttonStyle(.bordered).disabled(!model.isConnected);Button("弹幕字号") {adjustingDanmaku=true}.buttonStyle(.bordered).popover(isPresented:$adjustingDanmaku) {DanmakuSettings().frame(width:280).padding(20)}};TrackControls(model:model,subtitles:model.externalSubtitles,modalChanged:{selectingFile=$0;if $0 {controls.cancel()} else {scheduleHide()}})}.padding(12).background(Color.black.opacity(0.8))
   }.simultaneousGesture(TapGesture().onEnded {scheduleHide()})}
   }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
   if composing {
    // Keep the movie in its own region above the composer and keyboard.
    // A modal sheet covers/dims the movie and expands while editing on iPad.
    VStack(spacing:8) {
     HStack {Text("发弹幕").font(.caption);Spacer();Button("收起") {composing=false}.accessibilityIdentifier("close-danmaku-input")}
     ChatEntry(model:model,draft:model.chatDraft,placeholder:"和对方说点什么…",onSent:{composing=false})
     RequestFeedback(feedback:model.feedback)
    }.padding(12).background(Color(white:0.08))
   }
  }.background(Color.black).preferredColorScheme(.dark)
   .onAppear {scheduleHide()}.onDisappear {controls.cancel()}
   .onChange(of:composing) {if $0 {controls.cancel()} else {scheduleHide()}}
   .onChange(of:adjustingDanmaku) {if $0 {controls.cancel()} else {scheduleHide()}}
 }
 private func scheduleHide() {controls.schedule(allowed:!selectingFile && !composing && !adjustingDanmaku)}
}

@MainActor struct DanmakuOverlay: View {
 @ObservedObject var chat: ChatEngine
 @AppStorage("danmakuFontSize") private var fontSize=24.0
 var body: some View {
  GeometryReader {geometry in
   ZStack(alignment:.topLeading) {
    DanmakuLayerView(items:chat.danmaku,fontSize:min(44,max(14,fontSize)))
   }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).clipped()
  }
 }
}
@MainActor struct DanmakuSettings: View {
 @AppStorage("danmakuFontSize") private var fontSize=24.0
 var body: some View {
  VStack(alignment:.leading,spacing:16) {
   Text("弹幕字号：\(Int(fontSize))").font(.headline)
   Slider(value:$fontSize,in:14...44,step:1).accessibilityLabel("弹幕文字大小")
   Text("一起看电影 👀").font(.system(size:fontSize,weight:.semibold))
   Button("恢复默认") {fontSize=24}
  }
 }
}

@MainActor struct DanmakuComposer: View {
 @ObservedObject var model: TestClient
 let onSent: () -> Void
 @Environment(\.dismiss) private var dismiss
 var body: some View {
  VStack(alignment:.leading,spacing:16) {
   HStack {Text("发弹幕").font(.headline);Spacer();Button("取消") {dismiss()}}
   ChatEntry(model:model,draft:model.chatDraft,placeholder:"和对方说点什么…",onSent:onSent)
   Text("发送后从画面顶部滑过，也会保留在聊天记录里。").font(.caption).foregroundStyle(.secondary)
   RequestFeedback(feedback:model.feedback)
  }.padding(20)
 }
}

@MainActor struct ChatPanel: View {
 @ObservedObject var model: TestClient
 @ObservedObject var chat: ChatEngine
 var body: some View {
  VStack(alignment:.leading) {
   Text("聊天").font(.headline)
   ScrollViewReader {proxy in
    ScrollView {LazyVStack(alignment:.leading,spacing:8) {
     ForEach(chat.messages) {message in
      HStack(alignment:.top,spacing:8) {
       if model.isMyMessage(message) {Spacer(minLength:24)}
       if !model.isMyMessage(message) {Image(systemName:"person.crop.circle.fill").font(.title2).foregroundColor(.blue)}
       VStack(alignment:model.isMyMessage(message) ? .trailing : .leading,spacing:4) {
        Text(message.name).font(.caption2).foregroundStyle(.secondary)
        Text(message.text).font(.callout).padding(10).background(model.isMyMessage(message) ? Color.blue : Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:12)).textSelection(.enabled)
       }
       if !model.isMyMessage(message) {Spacer(minLength:24)}
      }
     }
     Color.clear.frame(height:1).id("bottom")
    }}.frame(maxHeight:.infinity).onChange(of:chat.messages.last?.id) {_ in proxy.scrollTo("bottom",anchor:.bottom)}
   }
   if !chat.typingName.isEmpty {Text("\(chat.typingName) 正在输入…").font(.caption)}
   ChatEntry(model:model,draft:model.chatDraft,placeholder:"输入消息")
  }
 }
}
@MainActor struct ChatEntry: View {
 @ObservedObject var model: TestClient
 @ObservedObject var draft: ChatDraftState
 let placeholder: String
 var onSent: ()->Void = {}
 @FocusState private var focused: Bool
 var body: some View {
  HStack {
   TextField(placeholder,text:$draft.text).textFieldStyle(.roundedBorder).focused($focused).submitLabel(.send).accessibilityIdentifier(placeholder == "输入消息" ? "chat-input" : "danmaku-input").onSubmit {send()}.onChange(of:draft.text) {_ in model.sendTyping()}
   Button("发送") {send()}.buttonStyle(.borderedProminent).disabled(!model.isConnected || draft.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
  }.onAppear {if placeholder != "输入消息" {focused=true}}
 }
 private func send() {model.sendChat();if draft.text.isEmpty {onSent()}}
}
@MainActor struct RequestFeedback: View {
 @ObservedObject var feedback: ClientFeedback
 var body: some View {if !feedback.requestStatus.isEmpty {Text(feedback.requestStatus).font(.caption).foregroundColor(.orange)}}
}
@MainActor struct DiagnosticsFeedback: View {
 @ObservedObject var feedback: ClientFeedback
 var body: some View {
  RequestFeedback(feedback:feedback)
  Text(feedback.status).font(.system(.caption,design:.monospaced))
 }
}
@MainActor struct ConnectionFeedback: View {
 @ObservedObject var model: TestClient
 @ObservedObject var feedback: ClientFeedback
 var body: some View {Text(model.isConnected ? "已连接房间：\(model.roomID)" : feedback.status).font(.caption)}
}
@MainActor struct RoomMediaAction: View {
 @ObservedObject var model: TestClient
 @ObservedObject var feedback: ClientFeedback
 var body: some View {
  VStack(alignment:.leading,spacing:8) {
   Button(model.isSettingRoomMedia ? "正在设置房间影片…" : "设置房间影片") {model.setRoomMedia()}
    .buttonStyle(.borderless).disabled(!model.isRoomHost || model.isSettingRoomMedia).accessibilityIdentifier("set-room-media")
   if !feedback.requestStatus.isEmpty {Text(feedback.requestStatus).font(.caption).foregroundColor(.orange).accessibilityIdentifier("room-media-feedback")}
  }.frame(maxWidth:.infinity,alignment:.leading)
 }
}
@MainActor struct RoomScreen: View {
 @ObservedObject var model: TestClient
 @StateObject private var baidu=BaiduBrowserModel()
 private enum Picker: String, Identifiable {case baidu,local,localCopy;var id:String {rawValue}}
 @State private var picker: Picker?
 var body: some View {
  Form {
   Section("TogetherPlayer 0.4.8") {
    TextField("服务地址",text:$model.server).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    TextField("房间编号",text:$model.roomID).textInputAutocapitalization(.never).autocorrectionDisabled()
    HStack {Button("创建房间") {model.register(join:false)};Button("加入 / 重连") {model.register(join:true)}}.buttonStyle(.borderless)
    RequestFeedback(feedback:model.feedback)
    ConnectionFeedback(model:model,feedback:model.feedback)
    Toggle("等待对方缓冲或重连",isOn:Binding(get:{model.waitForPeer},set:{model.waitForPeer=$0;model.setWaiting($0)})).disabled(!model.isRoomHost)
    Button(model.isRoomHost ? "离开并关闭房间" : "离开房间",role:.destructive) {model.leaveRoom()}
   }
   Section("房间影片") {
    TextField("影片名称",text:$model.movieTitle)
    TextField("HTTP / HLS / WebDAV 文件链接",text:$model.mediaURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    RoomMediaAction(model:model,feedback:model.mediaFeedback)
    Button("苹果 HDR / Atmos 测试片") {model.useHighQualityTestSource();model.movieTitle="苹果 HDR / Atmos 测试片";if model.isRoomHost {model.setRoomMedia()}}.buttonStyle(.borderless).disabled(model.isSettingRoomMedia)
    Text("视频由设备直接读取。更换房间影片会暂停并让双方重新加载。").font(.caption)
   }
   Section("百度网盘 · 个人体验") {
    Button("授权并选择百度影片") {picker = .baidu}.disabled(!model.isConnected)
    Button("清除百度授权与本机片源",role:.destructive) {baidu.clear();model.clearBaiduSource()}
    Text("先加入房间。授权及直链只留在本机内存；好友不会得到你的网盘权限。MP4原生播放；MKV本机封装试用。目标为杜比视界P5和DD+ Atmos，TrueHD Atmos未支持。").font(.caption)
   }
   Section("仅本机使用另一版本") {
    if model.usingLocalFile {
     Text("本地影片：\(model.localFileName)").font(.caption)
    } else if model.usingBaiduSource {
     Text("百度本机片源已选择（授权链接隐藏）").font(.caption)
    } else {
     TextField("本机播放链接（可留空）",text:$model.localMediaURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    }
    Button("选择本地影片") {model.beginLocalFileSelection();picker = .local}.accessibilityIdentifier("choose-local-movie")
    Button("兼容导入本地影片（复制一份）") {model.beginLocalFileSelection();picker = .localCopy}.accessibilityIdentifier("import-local-movie-copy")
    RequestFeedback(feedback:model.feedback)
    Text("直接选择入口只读取原文件；兼容导入会复制一份。两者都不会上传影片。").font(.caption)
    Text("若直接点选文件没有返回，可用兼容导入。系统会复制一份到 App 临时目录，需要额外影片大小的空间；复制期间请等待，不要重复点选。不上传影片。").font(.caption)
    if model.isRoomHost {Button("仅替换本机为本地影片（好友继续在线）") {model.beginLocalFileSelection(publishRoom:false);picker = .local}}
    if model.usingLocalFile {
     Button("清除本地影片并恢复房间片源",role:.destructive) {model.clearLocalFileSource()}
    } else {
     Button("应用本机片源") {model.applyLocalSource()}
    }
    Text("本地文件直接读取，不额外复制。精确匹配会核对首/中/尾采样；百度下载的另一画质可在选片后确认相同剪辑，时长校验通过后同步。").font(.caption)
   }
   Section("身份与时间校准") {
    TextField("昵称",text:$model.nickname)
    TextField("本机时间偏移（秒，可负数）",text:$model.offsetSeconds).keyboardType(.numbersAndPunctuation)
    Text("本机正片比房间晚8秒开始时，填8。").font(.caption)
    Button("保存昵称与校准") {model.saveProfile()}
   }
   Section("画质诊断") {
    Button(model.atmosReferenceOverride ? "恢复官方自适应音轨" : "iPad Atmos测试片音轨") {model.toggleAtmosReference()}
    Text("音轨、字幕和外挂字幕导入已移至观影页画面下方。").font(.caption)
    Text(model.mediaInfo).font(.caption);Text(model.streamInfo).font(.caption)
   }
   Section("开源组件") {
    Text("包含PrismCore（LGPL-2.1+及商店例外）和MPVKit/FFmpeg。MKV在设备本机重新封装，不经过Muse。").font(.caption)
    Link("PrismCore源码与许可证",destination:URL(string:"https://github.com/Wenzlik/PrismCore")!)
    Link("MPVKit源码与许可证",destination:URL(string:"https://github.com/mpvkit/MPVKit")!)
   }
   Section("连接与测试") {
    DiagnosticsFeedback(feedback:model.feedback)
    Button("仅本机播放测试") {model.checkLocalVideo()}
    Button("本机兼容封装重试") {model.retryCompatibility()}
    Button("模拟断线3秒") {model.disconnectForTest()}
    Text("当前为前台观影；切后台会暂停本机，返回后恢复房间状态。").font(.caption)
   }
  }.buttonStyle(.borderless).sheet(item:$picker) {selection in
    switch selection {
    case .baidu:
     NavigationStack {BaiduBrowserView(model:baidu,useSource:{url,file in if model.useBaiduSource(url,file:file) {picker=nil}},requiredTitle:model.baiduRoomTitle,variantContext:model.engine.room.map {($0.roomId,$0.mediaUrl)},useVariant:{url,file,roomID,mediaURL in if model.useBaiduSource(url,file:file,confirmedRoomID:roomID,confirmedMediaURL:mediaURL) {picker=nil}},clearSource:{model.clearBaiduSource()}).toolbar {Button("返回Together") {baidu.pause();picker=nil}}}.onDisappear {baidu.stopPreview()}
    case .local,.localCopy:
     LocalMovieDocumentPicker(asCopy:selection == .localCopy,onPick:{url in
      picker=nil
      DispatchQueue.main.async {model.useLocalFile(url)}
     },onCancel:{picker=nil;model.cancelLocalFileSelection()})
    }
   }.alert("使用同一影片的另一画质？",isPresented:Binding(get:{model.localQualityCandidate != nil},set:{if !$0 {model.cancelLocalQuality()}}),presenting:model.localQualityCandidate) {candidate in
    Button("确认相同剪辑，使用此画质") {model.confirmLocalQuality(candidate)}
    Button("取消",role:.cancel) {model.cancelLocalQuality()}
   } message:{candidate in
    Text("房间：\(candidate.roomTitle)\n本机：\(candidate.url.lastPathComponent)\n\(MovieVariantPolicy.namesSuggestSameMovie(candidate.roomTitle,candidate.url.lastPathComponent) ? "去除画质标记后名称相近。" : "文件名称不同，请仔细核对。")名称相近不代表相同剪辑；确认后还会核对双方时长，差异超过5秒暂停同步。")
   }
 }
}
// Use one presentation route for this screen. In particular, the document
// browser must also work when RoomScreen itself is shown inside a settings sheet.
struct LocalMovieDocumentPicker: UIViewControllerRepresentable {
 var asCopy=false
 static var contentTypes:[UTType] {
  // .item includes folders; explicit file types do not depend on Infuse's UTI.
  // .data also keeps uncommon containers selectable.
  [.movie,.video,.mpeg4Movie,.data]
 }
 let onPick:(URL)->Void
 let onCancel:()->Void
 func makeCoordinator()->Coordinator {Coordinator(onPick:onPick,onCancel:onCancel)}
 func makeUIViewController(context:Context)->UIDocumentPickerViewController {
  let controller=UIDocumentPickerViewController(forOpeningContentTypes:Self.contentTypes,asCopy:asCopy)
  controller.allowsMultipleSelection=false;controller.delegate=context.coordinator
  controller.shouldShowFileExtensions=true
  if let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first {controller.directoryURL=documents}
  controller.view.accessibilityIdentifier="local-movie-document-picker"
  return controller
 }
 func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
 final class Coordinator:NSObject,UIDocumentPickerDelegate {
  let onPick:(URL)->Void;let onCancel:()->Void
  private var completed=false
  init(onPick:@escaping(URL)->Void,onCancel:@escaping()->Void){self.onPick=onPick;self.onCancel=onCancel}
  func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
   guard !completed else {return};completed=true
   if let url=urls.first {onPick(url)} else {onCancel()}
  }
  func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {guard !completed else {return};completed=true;onCancel()}
 }
}
struct StableVideo: View, Equatable {
 let player: AVPlayer
 static func == (lhs: StableVideo,rhs: StableVideo) -> Bool {lhs.player === rhs.player}
 var body: some View {VideoPlayer(player:player)}
}
