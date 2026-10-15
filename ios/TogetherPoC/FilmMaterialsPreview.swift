import SwiftUI

@MainActor struct FilmMaterialsPreview:View {
 @ObservedObject var session:FilmMaterialExportSession
 @Environment(\.dismiss) private var dismiss
 var body:some View {
  NavigationStack {
   ScrollView {
    LazyVStack(alignment:.leading,spacing:18) {
     Text("素材包含全片剧情，仅供制作题库。分镜是离散静帧，不能证明缺失的连续动作。").font(.callout).foregroundStyle(.secondary)
     Text("完整字幕节选").font(.headline)
     Text(session.previewSubtitle).font(.caption.monospaced()).textSelection(.enabled)
     ForEach(session.individualFiles.filter{$0.pathExtension.lowercased()=="jpg"},id:\.self) {url in
      VStack(alignment:.leading) {
       Text(url.lastPathComponent).font(.caption)
       if let image=UIImage(contentsOfFile:url.path) {Image(uiImage:image).resizable().scaledToFit()}
       ShareLink(item:url){Label("分享这张分镜",systemImage:"square.and.arrow.up")}
      }
     }
    }.padding()
   }.navigationTitle("素材预览").toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
  }
 }
}
