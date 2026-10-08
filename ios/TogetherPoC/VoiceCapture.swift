import AVFoundation
import Combine

/// Microphone samples are measured in memory and handed only to local recognition.
/// No recording is written to disk or sent through the room socket.
@MainActor final class VoiceCapture: ObservableObject {
 @Published private(set) var active=false
 @Published private(set) var requesting=false
 @Published private(set) var level:Double=0
 @Published private(set) var audible=false
 @Published private(set) var status="麦克风未开启"
 private let engine=AVAudioEngine()
 private var generation=0
 private var tapped=false
 private var recordingOutputIDs=Set<String>()
 private var snapshot:SessionSnapshot?
 private let injectedSession:VoiceRecordingSession?
 private lazy var liveSession=VoiceRecordingSession(isCurrent:{let s=AVAudioSession.sharedInstance();return s.category == .playAndRecord && s.mode == .default},activate:{[weak self] in try self?.configureSession()},release:{[weak self] in try self?.restoreSession()})
 private var recordingSession:VoiceRecordingSession {injectedSession ?? liveSession}
 private var observers:[NSObjectProtocol]=[]
 var onBuffer:((AVAudioPCMBuffer)->Void)?
 var onFailure:((String)->Void)?
 var threshold=0.003
 private struct SessionSnapshot {
  let category:AVAudioSession.Category
  let mode:AVAudioSession.Mode
  let options:AVAudioSession.CategoryOptions
  let input:AVAudioSessionPortDescription?
  let outputIDs:Set<String>
  let multichannel:Bool
 }
 init(session:VoiceRecordingSession?=nil) {
  injectedSession=session
  let center=NotificationCenter.default
  observers.append(center.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] _ in
   Task { @MainActor in self?.checkRoute() }
  })
  observers.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] notification in
   guard let value=notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,value==AVAudioSession.InterruptionType.began.rawValue else {return}
   Task { @MainActor in self?.fail("音频被系统中断，麦克风已关闭") }
  })
  observers.append(center.addObserver(forName:AVAudioSession.mediaServicesWereResetNotification,object:nil,queue:.main) { [weak self] _ in
   Task { @MainActor in self?.fail("音频服务重置，麦克风已关闭") }
  })
 }
 deinit {for observer in observers {NotificationCenter.default.removeObserver(observer)}}
 func toggle() {if active || requesting {stop()} else {requestStart()}}
 func requestStart() {
  guard !active && !requesting else {return}
  generation += 1;let current=generation
  let session=AVAudioSession.sharedInstance()
  switch session.recordPermission {
  case .denied:status="未获麦克风权限，请在系统设置中允许";return
  case .granted:start();return
  case .undetermined:
   requesting=true;status="等待麦克风授权"
   session.requestRecordPermission { [weak self] granted in
    Task { @MainActor in
     guard let self=self,self.generation==current else {return}
     self.requesting=false
     if granted {self.start()} else {self.status="麦克风权限被拒绝，电影播放不受语音模块控制"}
    }
   }
  @unknown default:status="当前系统无法确认麦克风权限"
  }
 }
 func prepareSession()->Bool {
  do {try recordingSession.prepare();recordingOutputIDs=Set(AVAudioSession.sharedInstance().currentRoute.outputs.map(\.uid));status="音频会话已准备；按住时才启用麦克风";return true}
  catch {stop(message:"麦克风准备失败：\(error.localizedDescription)");return false}
 }
 private func configureSession() throws {
  let session=AVAudioSession.sharedInstance()
  let old=SessionSnapshot(category:session.category,mode:session.mode,options:session.categoryOptions,input:session.preferredInput,outputIDs:Set(session.currentRoute.outputs.map(\.uid)),multichannel:session.supportsMultichannelContent)
  if snapshot == nil {snapshot=old}
  try session.setCategory(.playAndRecord,mode:.default,options:[.allowBluetoothA2DP,.defaultToSpeaker])
  guard let builtIn=session.availableInputs?.first(where:{$0.portType == .builtInMic}) else {throw CaptureError.noDeviceMic}
  try session.setPreferredInput(builtIn)
  try session.setActive(true)
  guard Set(session.currentRoute.outputs.map(\.uid))==old.outputIDs,
   !session.currentRoute.outputs.contains(where:{$0.portType == .bluetoothHFP || $0.portType == .builtInReceiver}) else {throw CaptureError.routeChanged}
  let format=engine.inputNode.outputFormat(forBus:0)
  guard format.sampleRate>0 && format.channelCount>0 else {throw CaptureError.invalidFormat}
  engine.prepare()
 }
 private func restoreSession() throws {
  guard let previous=snapshot else {return};snapshot=nil
  let session=AVAudioSession.sharedInstance()
  try session.setCategory(previous.category,mode:previous.mode,options:previous.options)
  try session.setPreferredInput(previous.input)
  try session.setSupportsMultichannelContent(previous.multichannel)
  try session.setActive(true)
 }
 private func start() {
  guard prepareSession() else {onFailure?(status);return}
  do {
   let input=engine.inputNode;let format=input.outputFormat(forBus:0)
   guard format.sampleRate>0 && format.channelCount>0 else {throw CaptureError.invalidFormat}
   let current=generation
   let bufferHandler=onBuffer
   var noiseGate=VoiceNoiseGate(threshold:max(0.001,min(0.1,threshold)))
   var lastUpdate=0.0
   input.installTap(onBus:0,bufferSize:2048,format:format) { [weak self] buffer,_ in
    // The callback is installed once per hold and consumes the buffer in place.
    let now=ProcessInfo.processInfo.systemUptime
    guard let channels=buffer.floatChannelData,buffer.frameLength>0 else {return}
    let values=channels[0]
    var sum:Double=0
    for i in 0..<Int(buffer.frameLength) {sum += Double(values[i]*values[i])}
    let rms=sqrt(sum/Double(buffer.frameLength))
    // An amplitude threshold cannot separate movie dialogue from the user.
    // Never erase quiet consonants or short words before recognition.
    let audible=noiseGate.accepts(rms:rms,now:now)
    bufferHandler?(buffer)
    guard now-lastUpdate>=0.25 else {return};lastUpdate=now
    Task { @MainActor in guard let self=self,self.generation==current,self.active else {return};self.level=min(1,rms*10);self.audible=audible }
   }
   tapped=true;engine.prepare();try engine.start();active=true
   status="麦克风使用中 · 内置麦克风；请核对电影声音、字幕和同步"
  } catch {
   stop(message:error.localizedDescription);onFailure?(status)
  }
 }
 private func fail(_ message:String) {guard active || requesting else {return};stop(message:message);onFailure?(message)}
 private func checkRoute() {
  guard active else {return}
  let session=AVAudioSession.sharedInstance()
  if Set(session.currentRoute.outputs.map(\.uid)) != recordingOutputIDs || session.category != .playAndRecord || !engine.isRunning {
   stop(message:"音频输出发生变化，麦克风已关闭，请重新验证当前设备")
   onFailure?(status)
  }
 }
 func stop(message:String="麦克风已关闭",restoreSession:Bool=true) {
  generation += 1;requesting=false;active=false;level=0;audible=false
  engine.stop();if tapped {engine.inputNode.removeTap(onBus:0);tapped=false}
  if restoreSession {
   do {try recordingSession.restore()}
   catch {status="麦克风已停止；恢复音频会话失败，请关闭并重新打开影片";return}
  }
  status=message
 }
 private enum CaptureError:LocalizedError {
  case noDeviceMic,routeChanged,invalidFormat
  var errorDescription:String? {
   switch self {
   case .noDeviceMic:return "没有可用的内置麦克风，保持电影播放"
   case .routeChanged:return "当前耳机／输出无法保持原音频路由，已关闭麦克风并恢复播放会话"
   case .invalidFormat:return "麦克风音频格式不可用，已恢复播放会话"
   }
  }
 }
}
