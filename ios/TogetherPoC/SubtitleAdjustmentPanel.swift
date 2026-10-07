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
    }
    Section("字体与间距") {
     Menu {ForEach(SubtitleFontFamily.allCases) {family in Button(family.label) {subtitles.fontFamily=family}}} label:{Text("字体：\(subtitles.fontFamily.label)").frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}.accessibilityIdentifier("subtitle-font-family")
     Menu {ForEach(SubtitleFontWeight.allCases) {weight in Button(weight.label) {subtitles.fontWeight=weight}}} label:{Text("粗细：\(subtitles.fontWeight.label)").frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}.accessibilityIdentifier("subtitle-font-weight")
     Text(String(format:"字间距 %+.2f",subtitles.letterSpacing))
     Slider(value:$subtitles.letterSpacing,in:-2...6,step:0.25).accessibilityLabel("字幕字间距")
     Text(String(format:"行间距 %+.1f",subtitles.lineSpacing))
     Slider(value:$subtitles.lineSpacing,in:-8...20,step:0.5).accessibilityLabel("字幕行间距")
     Text("字幕预览 Aa 中文\n第二行 Subtitle preview").font(SubtitleTypography.font(subtitles)).tracking(SubtitleAppearance.letterSpacing(subtitles.letterSpacing)).lineSpacing(CGFloat(SubtitleAppearance.lineSpacing(subtitles.lineSpacing))).foregroundColor(.white).shadow(color:.black,radius:2,x:0,y:1).accessibilityIdentifier("subtitle-style-preview")
     Text("字距向右增大，向左收紧；行距向右增大、向左收紧。背景透明。")
    }
    Section {
     Button("恢复默认") {subtitles.resetAdjustments()}.accessibilityIdentifier("reset-subtitle-adjustments")
     Text("字体、粗细、字距、行距、字号和位置会保存。时间偏移用于当前影片，切换影片或导入新的外挂字幕后重置。内置文字字幕与外挂字幕使用同一组设置。")
    }
   }.navigationTitle("字幕调整").toolbar {Button("完成") {dismiss()}.accessibilityIdentifier("close-subtitle-adjustments")}
  }.preferredColorScheme(.dark)
 }
}
