import SwiftUI

@MainActor struct SubtitleAdjustmentPanel:View {
 @ObservedObject var subtitles:ExternalSubtitles
 @Environment(\.dismiss) private var dismiss
 var body:some View {
  NavigationStack {
   Form {
    Section("时间偏移") {
     Stepper(value:$subtitles.delay,in:-120...120,step:0.1) {Text(String(format:"字幕偏移 %+.1f 秒",subtitles.delay))}.accessibilityIdentifier("subtitle-delay")
     Text("正数让字幕晚出现，负数让字幕提前；只调整本机字幕，不改变影片同步。")
    }
    Section("垂直位置") {
     Text("距画面底部 \(Int(subtitles.bottomFraction*100))%")
     Slider(value:$subtitles.bottomFraction,in:0.02...0.85).accessibilityLabel("字幕垂直位置")
     Text("向右拖动，字幕向上移动。全屏显示播放按钮时会避开控制区域。")
    }
    Section("文字大小") {
     Text("字幕字号 \(Int(subtitles.fontSize))")
     Slider(value:$subtitles.fontSize,in:16...64,step:1).accessibilityLabel("字幕文字大小")
     Text("字幕预览 Aa 中文").font(.system(size:SubtitleAppearance.font(subtitles.fontSize))).accessibilityIdentifier("subtitle-style-preview")
    }
    Section {
     Button("恢复默认") {subtitles.resetAdjustments()}.accessibilityIdentifier("reset-subtitle-adjustments")
     Text("字号和位置会保存。时间偏移用于当前影片，切换影片或导入新的外挂字幕后重置。内置文字字幕与外挂字幕使用同一组设置。")
    }
   }.navigationTitle("字幕调整").toolbar {Button("完成") {dismiss()}.accessibilityIdentifier("close-subtitle-adjustments")}
  }.preferredColorScheme(.dark)
 }
}
