import SwiftUI

@MainActor struct ChatGPTAuthDiagnosticView:View {
 @StateObject private var probe=ChatGPTAuthProbe()
 var body:some View {
  NavigationStack {
   ScrollView {
    VStack(alignment:.leading,spacing:18) {
     Label("TogetherPlayer · ChatGPT 授权试验",systemImage:"checkmark.shield.fill")
      .font(.title2.bold())
     Text("首次允许打开 OpenAI 官方授权页面。此后在本 App 内重复调用模型，不应该再次跳出。")
      .foregroundStyle(.secondary)
     Text(probe.status)
      .padding(14).frame(maxWidth:.infinity,alignment:.leading)
      .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:12))
      .accessibilityIdentifier("siwc-probe-status")
     Button("Continue with ChatGPT") {probe.connect()}
      .disabled(probe.working).buttonStyle(.borderedProminent)
      .accessibilityIdentifier("siwc-probe-connect")
     Button("不切换 App · 测试连续出题") {probe.testRepeatedCall()}
      .disabled(!probe.connected || probe.working)
      .buttonStyle(.bordered)
      .accessibilityIdentifier("siwc-probe-inference")
     if !probe.testText.isEmpty {
      Text("ChatGPT 返回：").font(.headline)
      Text(probe.testText).textSelection(.enabled)
     }
     if probe.connected {
      Button("仅清除 iPad 保存的授权",role:.destructive){probe.disconnect()}
     }
     Divider()
     Text("验证步骤：首次点连接并同意授权；回到 App 后点两次“测试连续出题”，再退出、重开 App 重试。只有两次调用均成功，才算实现了无反复切换。")
      .font(.callout)
     Text("这是独立试验版。不开启后台权限，不读取 Apple Intelligence 或 ChatGPT App 会话，也不把授权码、密钥或字幕上传到 TogetherPlayer 房间服务器。苹果系统可能在浏览器打开时暂停本地回调；失败状态会直接显示在此处。")
      .font(.caption).foregroundStyle(.secondary)
    }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
   }.navigationTitle("ChatGPT 授权测试")
  }.preferredColorScheme(.dark)
 }
}
