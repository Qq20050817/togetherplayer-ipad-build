import SwiftUI

struct WatchMemoryView:View {
 @ObservedObject var memory:WatchMemory
 let currentTitle:String
 @Environment(\.dismiss) private var dismiss
 @State private var manualTitle=""
 @State private var editing:WatchRecord?
 var body:some View {
  NavigationStack {
   List {
    Section {
     Text("看完自动保存观影记录，删除影片与字幕后仍保留。档案保存在这台设备，更新 App 会保留；卸载或清除 App 数据会移除档案。").font(.caption).foregroundStyle(.secondary)
     if !memory.storageError.isEmpty {Text(memory.storageError).foregroundStyle(.red)}
     if !currentTitle.isEmpty {Button("标记当前《\(FilmTaste.clean(currentTitle))》已看"){memory.record(currentTitle)}}
     HStack {TextField("补记以前看过的电影（可带年份）",text:$manualTitle);Button("记录"){memory.record(manualTitle);manualTitle=""}.disabled(manualTitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
    }
    Section("为你推荐") {
     Text(memory.catalogStatus).font(.caption).foregroundStyle(.secondary)
     Button("更新在线片单"){Task {await memory.refreshCatalog()}}
     if memory.records.isEmpty {Text("看完或补记一部电影后开始推荐，评分能帮助区分喜欢和不喜欢。")}
     ForEach(memory.suggestions) {s in
      VStack(alignment:.leading,spacing:9) {
       Text("\(s.film.title) · \(String(s.film.year))").font(.headline)
       Text(s.film.tags.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
       Text("讲什么").font(.subheadline.bold());Text(s.film.synopsis)
       if let source=s.film.sourceURL,let url=URL(string:source) {Link("影片资料来自 Apple",destination:url).font(.caption)}
       Text("为什么推荐").font(.subheadline.bold());Text(s.reason)
       Text("与你的喜好关联").font(.subheadline.bold());Text(s.connection)
       HStack {Button("已看过"){memory.record(s.film.title)};Spacer();Button("暂不推荐"){memory.dismiss(s.id)}}
       .buttonStyle(.bordered).font(.caption)
      }.padding(.vertical,8)
     }
     Button("恢复暂不推荐的影片"){memory.restoreSuggestions()}
     Text("从内置与 Apple 在线片单中挑选。已看题材是弱参考；4 至 5 分增加关联推荐，1 至 2 分减少关联推荐。").font(.caption).foregroundStyle(.secondary)
    }
    Section("我的观影档案 · \(memory.records.count) 部") {
     ForEach(memory.records) {r in
      Button {editing=r} label:{
       VStack(alignment:.leading,spacing:5) {
        Text(r.title).font(.headline)
        Text(r.rating.map{"评分 \($0)/5"} ?? "已看过 · 尚未评分").font(.caption).foregroundStyle(.secondary)
        Text(r.tags.isEmpty ? "尚未识别题材，点此补充影片特点" : r.tags.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
        Text(r.completedAt,style:.date).font(.caption2).foregroundStyle(.secondary)
        if !r.note.isEmpty {Text(r.note).font(.caption)}
       }
      }.foregroundStyle(.primary)
     }
    }
   }.navigationTitle("观影档案与推荐").task {await memory.refreshCatalog()}
    .toolbar {ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}}}
    .sheet(item:$editing){record in WatchFeedbackView(memory:memory,record:record)}
  }
 }
}
private struct WatchFeedbackView:View {
 @ObservedObject var memory:WatchMemory
 let record:WatchRecord
 @Environment(\.dismiss) private var dismiss
 @State private var rating=0
 @State private var tags=Set<String>()
 @State private var note=""
 @State private var forgetting=false
 var body:some View {
  NavigationStack {
   Form {
    Section(record.title) {
     Picker("评价",selection:$rating) {Text("暂不评分").tag(0);Text("1 不喜欢").tag(1);Text("2 不太喜欢").tag(2);Text("3 一般").tag(3);Text("4 喜欢").tag(4);Text("5 很喜欢").tag(5)}
     TextField("喜欢或不喜欢的具体原因（备忘）",text:$note,axis:.vertical)
     Text("请选这部影片实际具有的特点，推荐会结合评分学习这些标签。文字原因作为备忘保存。").font(.caption).foregroundStyle(.secondary)
    }
    Section("影片特点") {ForEach(FilmTaste.tags,id:\.self){tag in Toggle(tag,isOn:Binding(get:{tags.contains(tag)},set:{if $0 {tags.insert(tag)} else {tags.remove(tag)}}))}}
    Section {Button("删除这条观影记忆",role:.destructive){forgetting=true}}
   }.navigationTitle("观影感受").toolbar {
    ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}}
    ToolbarItem(placement:.confirmationAction){Button("保存"){memory.feedback(record.id,rating:rating==0 ? nil : rating,tags:FilmTaste.tags.filter{tags.contains($0)},note:note);dismiss()}}
   }.onAppear{rating=record.rating ?? 0;tags=Set(record.tags);note=record.note}
    .confirmationDialog("仅删除观影记忆，片源不受影响",isPresented:$forgetting){Button("删除记忆",role:.destructive){memory.forget(record.id);dismiss()}}
  }
 }
}

struct WatchMemoryBanner:View {
 @ObservedObject var memory:WatchMemory
 @State private var open=false
 var body:some View {
  Group {
   if !memory.automaticTitle.isEmpty {
    HStack {
     Button {open=true} label:{Label("已记住这部电影 · 查看下一部推荐",systemImage:"sparkles")}
     Button {memory.automaticTitle=""} label:{Image(systemName:"xmark.circle.fill")}.accessibilityLabel("关闭推荐提示")
    }.padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:16)).padding(.bottom,65)
   }
  }.sheet(isPresented:$open){WatchMemoryView(memory:memory,currentTitle:memory.automaticTitle)}
 }
}
