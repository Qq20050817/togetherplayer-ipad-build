import SwiftUI

@MainActor struct VoiceDanmakuPanel:View {
 @ObservedObject var voice:VoiceDanmakuController
 let connected:Bool
 var busyChanged:(Bool)->Void = {_ in}
 @State private var held=false
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
      .accessibilityLabel("按住说话，松开预览，上滑取消").accessibilityIdentifier("hold-voice-danmaku")
      .gesture(DragGesture(minimumDistance:0).onChanged {value in
       guard connected,voice.state == .ready || voice.state == .recording else {return}
       if !held {held=true;voice.begin()}
       cancelling=value.translation.height < -60
      }.onEnded {_ in voice.release(cancelled:cancelling);held=false;cancelling=false})
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
  }.onChange(of:connected) {if !$0 {voice.cancel(message:"连接中断，当前录音已取消；重连后可再次按住")};held=false}
   .onChange(of:voice.state) {if voice.state != .recording {held=false;cancelling=false};updateBusy()}
   .onChange(of:settings) {_ in updateBusy()}
   .onDisappear {if held {voice.cancel()};held=false;busyChanged(false)}
   .sheet(isPresented:$settings) {
    NavigationStack {
     Form {
      Picker("录音上限",selection:$voice.maxSeconds) {ForEach([30.0,60.0,120.0],id:\.self) {Text("\(Int($0)) 秒").tag($0)}}
      Picker("文字上限",selection:$voice.maxCharacters) {ForEach([120,300,500],id:\.self) {Text("\($0) 字").tag($0)}}
      Text("收音阈值 \(voice.threshold, specifier:"%.3f")")
      Slider(value:$voice.threshold,in:0.001...0.1).accessibilityLabel("收音阈值")
      Text("阈值越大，越容易过滤小声，也可能漏掉你轻声说的话。外放对白突然变响仍可能混入，请核对文字再确认。推荐使用耳机。")
     }.navigationTitle("语音弹幕设置").toolbar {Button("完成") {settings=false}}
    }.preferredColorScheme(.dark)
   }
 }
 private func updateBusy() {busyChanged(settings || voice.state == .preparing || voice.state == .recording || voice.state == .finishing || voice.state == .review)}
}

@MainActor private struct VoiceInputLevel:View {
 @ObservedObject var capture:VoiceCapture
 var body:some View {ProgressView(value:capture.level).accessibilityLabel("麦克风输入电平")}
}
