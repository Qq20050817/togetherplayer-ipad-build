import SwiftUI
import UniformTypeIdentifiers

struct WatchedCleanupSheet:View {
 let source:URL
 let importedSubtitle:URL?
 let detach:(URL)->Bool
 let report:(String)->Void
 @Environment(\.dismiss) private var dismiss
 @State private var choosing=false
 @State private var loading=false
 @State private var deleting=false
 @State private var confirm=false
 @State private var plan:CleanupPlan?
 @State private var selected:Set<String>=[]
 @State private var folderScope:URL?
 @State private var status=""
 @State private var finished=false
 @State private var originalAndCopy=false
 @State private var inspectionTask:Task<CleanupPlan,Error>?
 var body:some View {
  NavigationStack {
   List {
    Section {
     Label(source.lastPathComponent,systemImage:"film").font(.headline)
     if !finished {
     Text("选择影片所在文件夹，检查清单后删除。只清理这台设备；不会删除好友的文件。").font(.subheadline).foregroundStyle(.secondary)
     if WatchedFileCleanup.isAppOwned(source) {Text("当前播放的是 App 内文件。仅清理副本不会删除“我的 iPad”里的原文件；可选择原文件夹核对后一起清理。").font(.caption).foregroundStyle(.secondary)}
     Button {originalAndCopy=false;if WatchedFileCleanup.isAppOwned(source){inspect(source.deletingLastPathComponent())}else{choosing=true}} label:{Label(WatchedFileCleanup.isAppOwned(source) ? "仅检查 App 内文件（保留原文件）" : "选择影片所在文件夹",systemImage:"folder")}.disabled(loading || deleting || finished).accessibilityIdentifier("cleanup-choose-folder")
     if WatchedFileCleanup.isAppOwned(source) {
      Button {originalAndCopy=true;choosing=true} label:{Label("选择原文件夹，清理原件与副本",systemImage:"folder.badge.minus")}.disabled(loading || deleting || finished).accessibilityIdentifier("cleanup-choose-original")
     }
     }
    }
    if loading {ProgressView(originalAndCopy ? "正在逐字节核对原文件与副本，大影片需要一些时间…" : "正在检查本地文件…");Button("取消核对"){inspectionTask?.cancel()}}
    if let plan,!finished {
     Section("待清理文件") {
      Text("原文件夹："+plan.folder.lastPathComponent).font(.caption).foregroundStyle(.secondary)
      ForEach(plan.allFiles) {file in
       Toggle(isOn:Binding(get:{selected.contains(file.id)},set:{if $0 {selected.insert(file.id)} else{selected.remove(file.id)}})) {
        VStack(alignment:.leading,spacing:4) {
         Label(file.name,systemImage:file.isMovie ? "film" : "captions.bubble").lineLimit(3)
         Text((plan.appCopyFiles.contains{$0.id==file.id} ? "App 导入副本 · " : WatchedFileCleanup.isAppOwned(file.url) ? "App 内文件 · " : "所选文件夹原文件 · ")+ByteCountFormatter.string(fromByteCount:file.stamp.size,countStyle:.file)).font(.caption).foregroundStyle(.secondary)
        }
       }.disabled(deleting || finished).accessibilityIdentifier("cleanup-file-"+file.name)
      }
      Text("已选\(selected.count)个文件 · \(ByteCountFormatter.string(fromByteCount:plan.allFiles.filter{selected.contains($0.id)}.reduce(0){$0+$1.stamp.size},countStyle:.file))").font(.subheadline)
     }

    }
    if !status.isEmpty {Section {Text(status).accessibilityIdentifier("cleanup-result")}}
   }.safeAreaInset(edge:.bottom) {
    if plan != nil && !finished {
     VStack(spacing:8) {
      Button(role:.destructive) {confirm=true} label:{Label(deleting ? "正在清理…" : "删除所选文件",systemImage:"trash").frame(maxWidth:.infinity,minHeight:36)}.buttonStyle(.borderedProminent).tint(.red).disabled(selected.isEmpty || deleting || loading).accessibilityIdentifier("cleanup-delete")
      Text("确认后实际删除勾选文件并停止本机播放，不能在 App 内撤销。").font(.caption).foregroundStyle(.secondary)
     }.padding(12).background(.regularMaterial)
    }
   }.navigationTitle("看完清理").navigationBarTitleDisplayMode(.inline)
    .toolbar {ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}.disabled(deleting || loading)}}
    .sheet(isPresented:$choosing) {CleanupFolderPicker(onPick:{choosing=false;inspect($0)},onCancel:{choosing=false})}
    .alert("确认删除所选本地文件？",isPresented:$confirm) {
     Button("删除",role:.destructive){remove()}
     Button("取消",role:.cancel){}
    } message:{Text("将删除清单中勾选的\(selected.count)个文件，并停止本机播放。云端和好友文件不受影响。")}
    .interactiveDismissDisabled(deleting || loading)
    .onDisappear {inspectionTask?.cancel();if let folderScope {folderScope.stopAccessingSecurityScopedResource()}}
  }
 }
 private func inspect(_ folder:URL) {
  guard !loading,!deleting else{return}
  if let folderScope {folderScope.stopAccessingSecurityScopedResource()}
  folderScope=folder.startAccessingSecurityScopedResource() ? folder : nil
  loading=true;plan=nil;selected=[];status=""
  let matchOriginal=originalAndCopy
  let job=Task.detached(priority:.utility){try matchOriginal ? WatchedFileCleanup.planOriginalAndCopy(source:source,folder:folder,importedSubtitle:importedSubtitle) : WatchedFileCleanup.plan(source:source,folder:folder,importedSubtitle:importedSubtitle)}
  inspectionTask=job
  Task {
   do {
    let result=try await job.value
    try Task.checkCancellation()
    plan=result;selected=Set(result.allFiles.map(\.id))
   } catch is CancellationError {status="已取消核对，没有删除文件。"}
   catch {status=error.localizedDescription}
   inspectionTask=nil;loading=false
  }
 }
 private func remove() {
  guard let plan,!deleting,!selected.isEmpty else{return}
  let files=plan.allFiles.filter{selected.contains($0.id)}
  guard detach(source) else{status="影片或房间已变化，未删除任何文件。请重新打开清理。";return}
  deleting=true
  Task {
   let result=await Task.detached(priority:.utility){WatchedFileCleanup.remove(files,from:plan)}.value
   var message="已删除\(result.deleted.count)个文件（已核验不存在）。"
   if WatchedFileCleanup.isAppOwned(source) && plan.appCopyFiles.isEmpty {message+="\n本次仅清理 App 内文件；导入前的原文件未删除。"}
   if !result.deleted.isEmpty {message+="\n"+result.deleted.joined(separator:"\n")}
   message+="\n清理范围："+plan.folder.lastPathComponent
   if !result.failed.isEmpty {message+="\n以下文件未删除：\n"+result.failed.joined(separator:"\n")}
   status=message;report(message);deleting=false;finished=true
  }
 }
}
private struct CleanupFolderPicker:UIViewControllerRepresentable {
 let onPick:(URL)->Void
 let onCancel:()->Void
 func makeCoordinator()->Coordinator {Coordinator(onPick:onPick,onCancel:onCancel)}
 func makeUIViewController(context:Context)->UIDocumentPickerViewController {
  let c=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false)
  c.delegate=context.coordinator;c.allowsMultipleSelection=false
  return c
 }
 func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context){}
 final class Coordinator:NSObject,UIDocumentPickerDelegate {
  let onPick:(URL)->Void;let onCancel:()->Void
  init(onPick:@escaping(URL)->Void,onCancel:@escaping()->Void){self.onPick=onPick;self.onCancel=onCancel}
  func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){if let url=urls.first{onPick(url)}else{onCancel()}}
  func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){onCancel()}
 }
}
