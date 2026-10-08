import SwiftUI

@MainActor struct VoiceDanmakuPanel:View {
 @ObservedObject var voice:VoiceDanmakuController
 let connected:Bool
 var fullscreen=false
 var busyChanged:(Bool)->Void = {_ in}
 @State private var held=false
 @State private var gestureActive=false
 @State private var cancelling=false
 @State private var settings=false
 @State private var pendingBegin:Task<Void,Never>?
 var body:some View {
  VStack(alignment:.leading,spacing:6) {
   if fullscreen && showsDetails {details}
   toolbar
   if !fullscreen {details}
  }.font(fullscreen ? .caption : .body).buttonStyle(FullscreenToolStyle()).onAppear {updateBusy()}
   .onChange(of:connected) {if !$0 {voice.cancel(message:"连接中断，当前录音已取消；重连后可再次按住")};held=false}
   .onChange(of:voice.state) { _ in if voice.state != .recording {held=false;cancelling=false};if voice.state == .disabled {gestureActive=false};updateBusy()}
   .onChange(of:settings) {_ in updateBusy()}
   .onDisappear {pendingBegin?.cancel();pendingBegin=nil;if held {voice.cancel()};gestureActive=false;held=false;busyChanged(false)}
   .sheet(isPresented:$settings) {settingsPanel}
 }
 private var showsDetails:Bool {
  if voice.state == .disabled {return !voice.status.hasPrefix("语音弹幕未开启") && !voice.status.hasPrefix("语音弹幕已关闭")}
  if voice.state == .ready {return !["按住说话","已确认发送","已取消"].contains(where:{voice.status.hasPrefix($0)})}
  return true
 }
 private var toolbar:some View {
   HStack {
    if fullscreen {Spacer(minLength:0)}
    if voice.state == .disabled || voice.state == .preparing {
     Button {voice.enable()} label:{Label(fullscreen ? "语音" : "启用语音弹幕",systemImage:"mic.fill")}.disabled(!connected || voice.state == .preparing).accessibilityLabel("启用语音弹幕").accessibilityIdentifier("enable-voice-danmaku")
    } else {
     if fullscreen {options}
     Text(held ? (cancelling ? "松开取消" : (fullscreen ? "松开预览" : "正在录音 · 松开预览")) : "按住说话")
      .frame(width:fullscreen ? 96 : 160,height:36).background(held ? Color.red : Color.blue).clipShape(RoundedRectangle(cornerRadius:8))
      .accessibilityLabel("按住说话，松开预览，上滑取消")
      .accessibilityAction(named:Text("开始录音")) {if connected {voice.begin()}}
      .accessibilityAction(named:Text("结束录音并预览")) {voice.release()}
      .accessibilityAction(named:Text("取消录音")) {voice.cancel()}.accessibilityIdentifier("hold-voice-danmaku")
      .gesture(DragGesture(minimumDistance:0).onChanged {value in
       cancelling=value.translation.height < -60
       // One capture per finger-down. A recognition error or timeout may make
       // the controller ready again; finger movement must never restart it.
       guard !gestureActive else {return}
       gestureActive=true
       guard connected,voice.state == .ready else {return}
       held=true
       pendingBegin=Task { @MainActor in
        try? await Task.sleep(nanoseconds:16_000_000)
        guard !Task.isCancelled,gestureActive,held,connected,voice.state == .ready else {return}
        voice.begin();held=voice.state == .recording
       }
      }.onEnded {_ in pendingBegin?.cancel();pendingBegin=nil;voice.release(cancelled:cancelling);gestureActive=false;held=false;cancelling=false})
     if !fullscreen {options}
    }
   }
 }
 private var options:some View {
  Group {
   Button {voice.disable();held=false} label:{Text("关闭语音")}.accessibilityLabel("关闭语音").accessibilityIdentifier("disable-voice-danmaku")
   Button {settings=true} label:{Text("语音设置")}.accessibilityLabel("语音设置").disabled(voice.state != .ready)
  }
 }
 private var details:some View {
  VStack(alignment:.leading,spacing:6) {
   Text(voice.status).font(.caption).foregroundColor(voice.state == .recording ? .red : .secondary).accessibilityIdentifier("voice-danmaku-status")
   if voice.state == .review {
    HStack(alignment:.top) {
     TextField("识别结果，可修改",text:$voice.preview,axis:.vertical).lineLimit(1...4).textFieldStyle(.roundedBorder).accessibilityIdentifier("voice-result")
     VStack {Button("确认发送") {voice.confirm()}.disabled(!connected).accessibilityIdentifier("confirm-voice-danmaku");Button("取消") {voice.cancel()}.accessibilityIdentifier("cancel-voice-danmaku")}
    }
   } else if !voice.preview.isEmpty {Text(voice.preview).font(.caption).lineLimit(2)}
   if voice.state == .recording {VoiceInputLevel(capture:voice.capture)}
  }
 }
 private var settingsPanel:some View {
    NavigationStack {
     Form {
      Picker("录音上限",selection:$voice.maxSeconds) {ForEach([30.0,60.0,120.0],id:\.self) {Text("\(Int($0)) 秒").tag($0)}}
      Picker("文字上限",selection:$voice.maxCharacters) {ForEach([120,300,500],id:\.self) {Text("\($0) 字").tag($0)}}
      Text("收音提示阈值 \(voice.threshold, specifier:"%.3f")")
      Slider(value:$voice.threshold,in:0.001...0.1).accessibilityLabel("收音提示阈值")
      Text("阈值仅用于电平提示，不再切除小声讲话。外放时使用的是 iPad 内置麦克风，请靠近设备说话；电影对白仍可能混入，请检查文字后确认。耳机更可靠。")
      Button("完成") {settings=false}
     }.navigationTitle("语音弹幕设置")
    }.preferredColorScheme(.dark)
 }
 private func updateBusy() {busyChanged(settings || voice.state == .preparing || voice.state == .recording || voice.state == .finishing || voice.state == .review)}
}

@MainActor private struct VoiceInputLevel:View {
 @ObservedObject var capture:VoiceCapture
 var body:some View {
  VStack(alignment:.leading) {
   ProgressView(value:capture.level).accessibilityLabel("麦克风输入电平")
   Text(capture.audible ? "已收到声音；电影对白也可能被收录" : "声音较弱，请靠近 iPad 麦克风说话").font(.caption2).foregroundColor(capture.audible ? .secondary : .orange)
  }
 }
}
