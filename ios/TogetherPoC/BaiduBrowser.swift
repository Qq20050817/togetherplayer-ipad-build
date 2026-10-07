import SwiftUI
import AVKit
import AVFoundation

@MainActor final class BaiduBrowserModel: ObservableObject {
 @Published var tokenInput=""
 @Published var directory="/"
 @Published var files: [BaiduFile]=[]
 @Published var page=0
 @Published var busy=false
 @Published var status="尚未授权；仅进行百度官方个人体验测试"
 @Published var selectedName=""
 @Published var selectedFile: BaiduFile?
 @Published var rangeResult=""
 @Published var position=""
 @Published var hasAuthorization=false
 let player=AVPlayer()
 private var token=""
 private let mkvRemux=MKVRemux()
 private var previewGeneration=0
 private var source: URL?
 var selectedSource: URL? {source}
 private let adapter=BaiduSourceAdapter()
 private var generation=0
 private var timer: Timer?
 private var observation: NSKeyValueObservation?
 init() {
  try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
  try? AVAudioSession.sharedInstance().setSupportsMultichannelContent(true)
  try? AVAudioSession.sharedInstance().setActive(true)
  timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) {[weak self] _ in Task {@MainActor in self?.updatePosition()}}
 }
 func applyAuthorization() {
  var value=tokenInput.trimmingCharacters(in:.whitespacesAndNewlines)
  if let url=URL(string:value),url.scheme != nil {
   guard url.scheme=="https",url.host=="openapi.baidu.com" else {status="授权链接必须来自openapi.baidu.com";return}
   var parts=URLComponents();parts.query=url.fragment
   guard let extracted=parts.queryItems?.first(where:{$0.name=="access_token"})?.value else {status="链接中没有access_token，请确认已完成官方授权";return}
   value=extracted
  }
  guard !value.isEmpty,value.count<=4096,value.range(of:"^[A-Za-z0-9._~-]+$",options:.regularExpression) != nil else {status="授权信息格式无效；不要输入密码或Cookie";return}
  clear();token=value;tokenInput="";hasAuthorization=true;load(directory:"/",page:0)
 }
 func clear() {
  generation += 1;busy=false;token="";tokenInput="";hasAuthorization=false;source=nil
  stopPreview();files=[];selectedFile=nil;selectedName="";rangeResult="";position="";status="本机授权已清除；百度应用解绑需在百度授权管理中完成"
 }
 func load(directory next: String,page nextPage: Int) {
  guard !busy,hasAuthorization,next.hasPrefix("/"),nextPage>=0 else {return}
  busy=true;let g=generation;let auth=token
  Task {
   defer {if g==generation {busy=false}}
   do {
    let list=try await adapter.listFiles(token:auth,directory:next,page:nextPage)
    guard g==generation else {return}
    directory=next;page=nextPage;files=list;status="文件列表读取成功：本页\(list.count)项"
   } catch {if g==generation {status=(error as? BaiduProbeFailure)?.message ?? "读取失败，请检查百度授权和网络；没有记录授权链接"}}
  }
 }
 func select(_ file: BaiduFile) {
  if file.isDirectory {load(directory:file.path,page:0);return}
  guard !busy,hasAuthorization else {return};busy=true;let g=generation;let auth=token
  stopPreview();source=nil;selectedFile=nil;rangeResult="";selectedName=file.name
  Task {
   defer {if g==generation {busy=false}}
   do {
    let (url,matched)=try await adapter.requestPlayableSource(token:auth,file:file)
    guard g==generation else {return};source=url;selectedFile=matched;status="已取得本机文件源。先检查Range，再点播放验证。"

   } catch {if g==generation {status=(error as? BaiduProbeFailure)?.message ?? "取得文件源失败，请检查授权或接口权限"}}
  }
 }
 func testRange() {
  guard !busy,let url=source else {return};busy=true;let g=generation
  Task {
   defer {if g==generation {busy=false}}
   do {let text=try await RangeProbe.run(url);if g==generation {rangeResult=text}}
   catch {if g==generation {rangeResult=(error as? BaiduProbeFailure)?.message ?? "Range测试失败；没有下载整部影片"}}
  }
 }
 func play(forceRemux: Bool=false) {
  guard let url=source else {return}
  if !forceRemux,player.currentItem != nil {player.play();return}
  previewGeneration += 1;let g=previewGeneration;let name=selectedName
  let needsRemux=forceRemux || MKVRemux.needed(url:url,fileName:name)
  if forceRemux {player.pause();player.replaceCurrentItem(with:nil)}
  status="正在本机准备播放；兼容模式采用本机重新封装。"
  Task {
   guard g==previewGeneration else {return}
   do {
    let playbackURL: URL
    if needsRemux {playbackURL=try await mkvRemux.prepare(url,headers:["User-Agent":"pan.baidu.com"])} else {playbackURL=url}
    guard g==previewGeneration else {return}
    let asset=AVURLAsset(url:playbackURL,options:playbackURL==url ? [AVURLAssetHTTPUserAgentKey:"pan.baidu.com"] : [:])
    let item=AVPlayerItem(asset:asset);item.preferredForwardBufferDuration=12;player.replaceCurrentItem(with:item)
    if !needsRemux {
     Task {
      try? await Task.sleep(nanoseconds:20_000_000_000)
      guard g==previewGeneration,player.currentItem === item,item.status == .unknown else {return}
      status="原生加载超时，尝试本机兼容封装。";play(forceRemux:true)
     }
    }
    observation=item.observe(\.status,options:[.new]) {[weak self] observed,_ in Task {@MainActor in
     guard let self=self,self.player.currentItem === observed else {return}
     if observed.status == .failed {
      if !needsRemux {self.status="原生加载失败，尝试本机兼容封装。";self.play(forceRemux:true)}
      else {self.status="兼容播放仍失败（\((observed.error as NSError?)?.code ?? 0)），请检查取流或编码格式。"}
     }
    }}
    status="已交给系统播放器；HDR/杜比视界/Atmos输出需实际确认。"
    player.play()
   } catch {if g==previewGeneration {status="兼容准备失败，请检查网络、授权或音轨编码；未输出账户链接。"}}
  }
 }
 func stopPreview() {previewGeneration += 1;mkvRemux.stop();player.pause();player.replaceCurrentItem(with:nil)}
 func pause() {previewGeneration += 1;player.pause();if player.currentItem==nil {mkvRemux.stop()}}
 func seek() {guard source != nil else {return};player.seek(to:CMTime(seconds:120,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)}
 private func updatePosition() {
  guard let item=player.currentItem else {return}
  let n=player.currentTime().seconds;let d=item.duration.seconds
  position="位置 \(n.isFinite ? String(format:"%.1f",n) : "未知")s / \(d.isFinite ? String(format:"%.1f",d) : "未知")s；\(player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? "缓冲中" : player.timeControlStatus == .playing ? "播放中" : "暂停")"
 }
}

@MainActor struct BaiduBrowserView: View {
 @ObservedObject var model: BaiduBrowserModel
 let useSource: (URL,BaiduFile) -> Void
 var requiredTitle: String=""
 var variantContext: (String,String)?
 var useVariant: (URL,BaiduFile,String,String) -> Void = {_,_,_,_ in}
 let clearSource: () -> Void
 @State private var variantSelection: BaiduFile?
 @State private var variantURL: URL?
 @State private var confirmingVariant=false
 @State private var confirmedRoom: (String,String)?
 @Environment(\.scenePhase) private var phase
 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:12) {
    Text("百度网盘 · 房间选片").font(.title2)
    if !requiredTitle.isEmpty {Text("当前房间影片：\(requiredTitle)。可选择同一文件，或确认同一剪辑的另一画质。").foregroundColor(.orange)}
    Text("个人限时体验，非正式接入。官方授权页应用名mcp_server，请求网盘读写权限；本探针只调用读取接口，不上传、删除或创建分享。视频和授权信息不发给Muse或好友。").font(.caption)
    Link("查看百度官方个人体验说明",destination:URL(string:"https://github.com/baidu-netdisk/mcp#使用准备")!)
    Link("打开官方体验授权页面",destination:URL(string:"https://openapi.baidu.com/oauth/2.0/authorize?client_id=QHOuRXiepJBMjtk0esLhrPoNlQyYd0mF&redirect_uri=oob&response_type=token&scope=basic%2Cnetdisk")!)
    SecureField("官方返回的Token或完整回跳链接（仅本机内存）",text:$model.tokenInput).textInputAutocapitalization(.never).autocorrectionDisabled()
    HStack {Button("应用授权并读取文件") {model.applyAuthorization()}.disabled(model.busy);Button("清除本机授权",role:.destructive) {model.clear();clearSource()}}
    Text(model.status).foregroundColor(.orange)
    HStack {TextField("目录，例如/电影",text:$model.directory);Button("读取目录") {model.load(directory:model.directory,page:0)}}.disabled(model.busy || !model.hasAuthorization)
    HStack {Button("返回根目录") {model.load(directory:"/",page:0)};Button("上一页") {model.load(directory:model.directory,page:model.page-1)}.disabled(model.page==0);Text("第\(model.page+1)页");Button("下一页") {model.load(directory:model.directory,page:model.page+1)}.disabled(model.files.count<100)}.disabled(model.busy || !model.hasAuthorization)
    LazyVStack(alignment:.leading) {ForEach(model.files) {f in Button {model.select(f)} label:{HStack {Text(f.isDirectory ? "📁" : "🎞️");Text(f.name).multilineTextAlignment(.leading);Spacer();if !f.isDirectory {Text(ByteCountFormatter.string(fromByteCount:f.size,countStyle:.file)).font(.caption)}}}.disabled(model.busy)}}
    if !model.selectedName.isEmpty {
     Divider();Text(model.selectedName)
     Button("将此影片用于 Together 同步") {if let url=model.selectedSource,let file=model.selectedFile {model.pause();useSource(url,file)}}.disabled(model.selectedSource==nil || model.busy)
     if !requiredTitle.isEmpty {
      Button("使用同一影片的另一画质…") {
       variantSelection=model.selectedFile;variantURL=model.selectedSource;confirmedRoom=variantContext;confirmingVariant=true
      }.disabled(model.selectedSource==nil || model.busy).accessibilityIdentifier("use-quality-variant")
     }
     VideoPlayer(player:model.player).frame(height:260)
     HStack {Button("检查Range") {model.testRange()}.disabled(model.busy);Button("播放") {model.play()};Button("兼容重试") {model.play(forceRemux:true)};Button("暂停") {model.pause()};Button("跳到120秒") {model.seek()}}
     Text(model.rangeResult).font(.caption);Text(model.position).font(.system(.caption,design:.monospaced))
    }
    Text("MP4原生播放，MKV本机封装试用。精确匹配核对文件指纹和大小；另一画质需确认相同剪辑并核对时长，相差超过5秒暂停同步。画质仅影响本机，不替换好友文件，授权链接不会共享。百度App下载的低画质副本也可用“选择本地影片”直接读取，不再复制一份。TrueHD Atmos和ISO/BDMV未支持；退出App不保存Token。").font(.caption)
   }.padding()
  }.alert("使用同一影片的另一画质？",isPresented:$confirmingVariant) {
   Button("确认相同剪辑，使用此画质") {
    if let url=variantURL,let file=variantSelection,let context=confirmedRoom {model.pause();useVariant(url,file,context.0,context.1)}
    variantSelection=nil;variantURL=nil;confirmedRoom=nil
   }
   Button("取消",role:.cancel) {variantSelection=nil;variantURL=nil;confirmedRoom=nil}
  } message:{
   Text("房间：\(requiredTitle)\n本机：\(variantSelection?.name ?? "")\n确认是相同剪辑；名称和画质标记仅作提示。读取双方时长后才允许同步，差异超过5秒暂停；此选择只改变本机画质。")
  }.onAppear {UIApplication.shared.isIdleTimerDisabled=true}.onChange(of:phase) {p in if p == .background {model.stopPreview()} else if p != .active {model.pause()}}
 }
}
