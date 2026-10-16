import SwiftUI

@MainActor struct ImportedMovieLibrarySheet:View {
 @ObservedObject var model:TestClient
 @Environment(\.dismiss) private var dismiss
 @State private var files=[LocalMovieCopyStore.Entry]()
 @State private var selected=Set<String>()
 @State private var status=""
 @State private var busy=false
 @State private var confirming=false
 @State private var scan:Task<[LocalMovieCopyStore.Entry],Error>?
 private var protected:Set<String> {Set([model.cleanupSourceURL?.standardizedFileURL.resolvingSymlinksInPath().path].compactMap{$0})}
 private var chosen:[LocalMovieCopyStore.Entry] {files.filter{selected.contains($0.id) && !protected.contains($0.id)}}
 private var bytes:Int64 {files.reduce(0){$0+$1.stamp.size}}
 var body:some View {
  NavigationStack {
   List {
    Section {
     Label("\(files.count) 份 · "+ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file),systemImage:"internaldrive").accessibilityIdentifier("import-library-count")
     Text("这里只管理 App 内的导入副本，不删除原文件。再次兼容导入相同内容会复用已有副本。").font(.caption).foregroundStyle(.secondary)
     Button {findDuplicates()} label:{Label("查找重复副本",systemImage:"doc.on.doc")}.disabled(busy || files.count<2).accessibilityIdentifier("import-library-find-duplicates")
     if busy {ProgressView();if scan != nil {Button("取消检查"){scan?.cancel()}}}
     if !status.isEmpty {Text(status).font(.subheadline).accessibilityIdentifier("import-library-status")}
    }
    if files.isEmpty && !busy {Section {Text("还没有导入副本").foregroundStyle(.secondary)}}
    Section("导入副本") {
     ForEach(files) {file in
      VStack(alignment:.leading,spacing:8) {
       Toggle(isOn:Binding(get:{selected.contains(file.id)},set:{if $0 {selected.insert(file.id)}else{selected.remove(file.id)}})) {
        VStack(alignment:.leading,spacing:4) {
         Text(file.url.lastPathComponent).lineLimit(3)
         Text(ByteCountFormatter.string(fromByteCount:file.stamp.size,countStyle:.file)).font(.caption).foregroundStyle(.secondary)
        }
       }.disabled(busy || protected.contains(file.id)).accessibilityIdentifier("import-library-select-"+file.url.lastPathComponent)
       if protected.contains(file.id) {Label("正在使用 · 已保护",systemImage:"lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("import-library-protected")}
       else {Button("使用此副本"){model.beginLocalFileSelection();model.useLocalFile(file.url);dismiss()}.disabled(busy).accessibilityIdentifier("import-library-use-"+file.url.lastPathComponent)}
      }.padding(.vertical,4)
     }
    }
    if !chosen.isEmpty {
     Section {
      Button(role:.destructive){confirming=true} label:{Text("删除所选 \(chosen.count) 份副本").frame(maxWidth:.infinity)}.disabled(busy).accessibilityIdentifier("import-library-delete")
     }
    }
   }.navigationTitle("管理导入副本").navigationBarTitleDisplayMode(.inline)
    .toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}.disabled(busy)}}
    .task {await reload()}
    .confirmationDialog("删除所选导入副本？",isPresented:$confirming,titleVisibility:.visible) {
     Button("确认删除副本",role:.destructive){deleteSelected()}
     Button("取消",role:.cancel){}
    } message:{Text("仅删除这台设备上的 App 副本；原文件保留。正在使用的影片不会删除。")}
    .interactiveDismissDisabled(busy)
  }
 }
 private func reload()async {
  do {files=try await Task.detached(priority:.utility){try LocalMovieCopyStore.entries()}.value;selected.formIntersection(Set(files.map(\.id)))}
  catch{status=error.localizedDescription}
 }
 private func findDuplicates() {
  busy=true;status="正在检查重复副本，大影片可能需要一些时间…";selected=[]
  let keep=protected
  let worker=Task.detached(priority:.utility) {try LocalMovieCopyStore.duplicateExtras(protected:keep){message in Task{@MainActor in if scan != nil && busy {status=message}}}}
  scan=worker
  Task {
   do {
    let extras=try await worker.value
    selected=Set(extras.map(\.id)).subtracting(protected)
    status=extras.isEmpty ? "没有发现内容完全相同的副本。" : "已选中 \(selected.count) 份多余副本，核对后可删除。每部影片至少保留一份。"
   }catch is CancellationError {status="已取消检查，未删除任何文件。"}
   catch {status=error.localizedDescription}
   scan=nil;busy=false
  }
 }
 private func deleteSelected() {
  let pending=chosen,keep=protected
  busy=true;status="正在删除所选副本…"
  Task {
   let result=await Task.detached(priority:.utility) {()->(Int,[String]) in
    var count=0,failures=[String]()
    for file in pending {
     do {try LocalMovieCopyStore.remove(file,protected:keep);count+=1}
     catch{failures.append(file.url.lastPathComponent+"："+error.localizedDescription)}
    }
    return(count,failures)
   }.value
   selected=[];await reload();busy=false
   status="已删除 \(result.0) 份副本。原文件保留。"+(result.1.isEmpty ? "" : "\n"+result.1.joined(separator:"\n"))
  }
 }
}
