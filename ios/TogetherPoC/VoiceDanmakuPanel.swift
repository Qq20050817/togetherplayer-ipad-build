import SwiftUI

@MainActor struct VoiceDanmakuPanel:View {
 @ObservedObject var voice:VoiceDanmakuController
 let connected:Bool
 var busyChanged:(Bool)->Void = {_ in}
 @State private var held=false
 @State private var gestureActive=false
 @State private var cancelling=false
 @State private var settings=false
 var body:some View {
  VStack(alignment:.leading,spacing:6) {
   HStack {
    if voice.state == .disabled || voice.state == .preparing {
     Button("启用语音弹幕") {voice.enable()}.disabled(!connected || voice.state == .preparing).accessibilityIdentifier("enable-voice-danmaku")
    } else {
     Text(held ? (cancelling ? "松开取消" : "正在录音 · 松开预览") : "按住说话")
      .padding(.horizontal,16).padding(.vertical,10).background(held ? Color.red : Color.blue).clipShape(Capsule())
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
       held=true;voice.begin()
      }.onEnded {_ in voice.release(cancelled:cancelling);gestureActive=false;held=false;cancelling=false})
     Button("关闭语音") {voice.disable();held=false}.accessibilityIdentifier("disable-voice-danmaku")
     Button("语音设置") {settings=true}.disabled(voice.state != .ready)
    }
   }
   Text(voice.status).font(.caption).foregroundColor(voice.state == .recording ? .red : .secondary).accessibilityIdentifier("voice-danmaku-status")
   if voice.state == .review {
    HStack(alignment:.top) {
     TextField("识别结果，可修改",text:$voice.preview,axis:.vertical).lineLimit(1...4).textFieldStyle(.roundedBorder).accessibilityIdentifier("voice-result")
     VStack {Button("确认发送") {voice.confirm()}.disabled(!connected).accessibilityIdentifier("confirm-voice-danmaku");Button("取消") {voice.cancel()}.accessibilityIdentifier("cancel-voice-danmaku")}
    }
   } else if !voice.preview.isEmpty {Text(voice.preview).font(.caption).lineLimit(2)}
   if voice.state == .recording {VoiceInputLevel(capture:voice.capture)}
  }.onAppear {updateBusy()}
   .onChange(of:connected) {if !$0 {voice.cancel(message:"连接中断，当前录音已取消；重连后可再次按住")};held=false}
   .onChange(of:voice.state) { _ in if voice.state != .recording {held=false;cancelling=false};updateBusy()}
   .onChange(of:settings) {_ in updateBusy()}
   .onDisappear {if held {voice.cancel()};gestureActive=false;held=false;busyChanged(false)}
   .sheet(isPresented:$settings) {
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
