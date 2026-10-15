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
 var body:some View {
  NavigationStack {
   List {
    Section {
     Label(source.lastPathComponent,systemImage:"film").font(.headline)
     Text("选择影片所在文件夹，检查清单后删除。只清理这台设备；不会删除好友的文件。").font(.subheadline).foregroundStyle(.secondary)
     if WatchedFileCleanup.isAppOwned(source) {Text("当前为 App 内文件，只清理这里的副本。").font(.caption).foregroundStyle(.secondary)}
     Button {if WatchedFileCleanup.isAppOwned(source){inspect(source.deletingLastPathComponent())}else{choosing=true}} label:{Label(WatchedFileCleanup.isAppOwned(source) ? "检查 App 内文件" : "选择影片所在文件夹",systemImage:"folder")}.disabled(loading || deleting || finished).accessibilityIdentifier("cleanup-choose-folder")
    }
    if loading {ProgressView("正在检查本地文件…")}
    if let plan {
     Section("待清理文件") {
      ForEach(plan.files) {file in
       Toggle(isOn:Binding(get:{selected.contains(file.id)},set:{if $0 {selected.insert(file.id)} else{selected.remove(file.id)}})) {
        VStack(alignment:.leading,spacing:4) {
         Label(file.name,systemImage:file.isMovie ? "film" : "captions.bubble").lineLimit(3)
         Text(ByteCountFormatter.string(fromByteCount:file.stamp.size,countStyle:.file)).font(.caption).foregroundStyle(.secondary)
        }
       }.disabled(deleting || finished).accessibilityIdentifier("cleanup-file-"+file.name)
      }
      Text("已选\(selected.count)个文件 · \(ByteCountFormatter.string(fromByteCount:plan.files.filter{selected.contains($0.id)}.reduce(0){$0+$1.stamp.size},countStyle:.file))").font(.subheadline)
     }
     if !finished {
      Section {
       Button(role:.destructive) {confirm=true} label:{Label(deleting ? "正在清理…" : "删除所选文件",systemImage:"trash").frame(maxWidth:.infinity)}.disabled(selected.isEmpty || deleting || loading).accessibilityIdentifier("cleanup-delete")
       Text("删除前会停止本机影片。此操作会实际删除文件，不能在 App 内撤销；文件变化或无删除权限时会保留并说明原因。").font(.caption).foregroundStyle(.secondary)
      }
     }
    }
    if !status.isEmpty {Section {Text(status).accessibilityIdentifier("cleanup-result")}}
   }.navigationTitle("看完清理").navigationBarTitleDisplayMode(.inline)
    .toolbar {ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}.disabled(deleting)}}
    .sheet(isPresented:$choosing) {CleanupFolderPicker(onPick:{choosing=false;inspect($0)},onCancel:{choosing=false})}
    .alert("确认删除所选本地文件？",isPresented:$confirm) {
     Button("删除",role:.destructive){remove()}
     Button("取消",role:.cancel){}
    } message:{Text("将删除清单中勾选的\(selected.count)个文件，并停止本机播放。云端和好友文件不受影响。")}
    .interactiveDismissDisabled(deleting)
    .onDisappear {if let folderScope {folderScope.stopAccessingSecurityScopedResource()}}
  }
 }
 private func inspect(_ folder:URL) {
  guard !loading,!deleting else{return}
  if let folderScope {folderScope.stopAccessingSecurityScopedResource()}
  folderScope=folder.startAccessingSecurityScopedResource() ? folder : nil
  loading=true;plan=nil;selected=[];status=""
  Task {
   do {
    let result=try await Task.detached(priority:.utility){try WatchedFileCleanup.plan(source:source,folder:folder,importedSubtitle:importedSubtitle)}.value
    plan=result;selected=Set(result.files.map(\.id))
   } catch {status=error.localizedDescription}
   loading=false
  }
 }
 private func remove() {
  guard let plan,!deleting,!selected.isEmpty else{return}
  let files=plan.files.filter{selected.contains($0.id)}
  guard detach(source) else{status="影片或房间已变化，未删除任何文件。请重新打开清理。";return}
  deleting=true
  Task {
   let result=await Task.detached(priority:.utility){WatchedFileCleanup.remove(files,in:plan.folder)}.value
   var message="已删除\(result.deleted.count)个文件。"
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
