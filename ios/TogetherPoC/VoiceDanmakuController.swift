import AVFoundation
import Speech
import Combine

private final class VoiceAudioSink {
 private let lock=NSLock()
 private var request:SFSpeechAudioBufferRecognitionRequest?
 func set(_ value:SFSpeechAudioBufferRecognitionRequest?) {lock.lock();request=value;lock.unlock()}
 func append(_ buffer:AVAudioPCMBuffer) {lock.lock();defer {lock.unlock()};request?.append(buffer)}
}

@MainActor final class VoiceDanmakuController:ObservableObject {
 enum State:String {case disabled,preparing,ready,recording,finishing,review}
 @Published private(set) var state=State.disabled
 @Published private(set) var status="语音弹幕未开启"
 @Published var preview=""
 @Published var maxSeconds=60.0
 @Published var maxCharacters=300
 @Published var threshold=0.003
 #if DEBUG
 private var gestureFixture=false
 func installGestureFixture() {gestureFixture=true;state = .ready;status="按住说话，松开预览"}
 #endif
 private var gate=VoiceSendGate()
 private var draft=VoiceRecognitionDraft()
 private var lastPreviewUpdate=0.0
 var roomKey:(()->String)?
 var duck:((Bool)->Void)?
 let capture=VoiceCapture()
 private let recognitionCallbacks:OperationQueue = {let q=OperationQueue();q.name="TogetherPlayer.LocalSpeechCallbacks";q.qualityOfService = .userInitiated;q.maxConcurrentOperationCount=1;return q}()
 private var recognizer:SFSpeechRecognizer?
 private var request:SFSpeechAudioBufferRecognitionRequest?
 private var task:SFSpeechRecognitionTask?
 private let sink=VoiceAudioSink()
 private var generation=0
 private var recognitionGeneration=0
 private var finalText:String?
 private var deadline:Task<Void,Never>?
 private var finalDeadline:Task<Void,Never>?
 var sendText:((String)->Bool)?
 init() {
  capture.onBuffer={ [sink] buffer in sink.append(buffer) }
  capture.onFailure={ [weak self] message in self?.cancel(message:message) }
 }
 func enable() {
  guard state == .disabled else {return}
  generation += 1;let current=generation;state = .preparing;status="检查本地中文识别与麦克风权限…"
  SFSpeechRecognizer.requestAuthorization { [weak self] permission in
   Task { @MainActor in
    guard let self=self,self.generation==current else {return}
    guard permission == .authorized else {self.state = .disabled;self.status="未获语音识别权限，请在系统设置中允许";return}
    guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:"zh-CN")),recognizer.supportsOnDeviceRecognition else {self.state = .disabled;self.status="此设备尚不支持本地中文识别，语音弹幕未开启";return}
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
     Task { @MainActor in
      guard let self=self,self.generation==current else {return}
      guard granted else {self.state = .disabled;self.status="未获麦克风权限，请在系统设置中允许";return}
      guard self.capture.prepareSession() else {self.state = .disabled;self.status=self.capture.status;return}
      recognizer.queue=self.recognitionCallbacks
      self.recognizer=recognizer;self.state = .ready;self.status="按住说话，松开预览；上滑取消，默认最长 60 秒，需确认后发送"
     }
    }
   }
  }
 }
 func begin() {
  guard state == .ready else {return}
  #if DEBUG
  if gestureFixture {
   gate.begin(room:roomKey?() ?? "");state = .recording;status="录音中 · 手势测试替身（不启用麦克风）";duck?(true);return
  }
  #endif
  guard let recognizer=recognizer else {return}
  guard recognizer.isAvailable && recognizer.supportsOnDeviceRecognition else {status="本地中文识别暂不可用；电影继续播放";return}
  generation += 1;let current=generation;preview="";finalText=nil;draft=VoiceRecognitionDraft();lastPreviewUpdate=0;gate.begin(room:roomKey?() ?? "");gate.limit=maxCharacters
  state = .recording;status="录音中 · 松开后预览，确认才发送"
  startRecognition(current)
  capture.threshold=threshold;duck?(true)
  capture.requestStart()
  guard capture.active else {cancel(message:capture.status);return}
  let seconds=max(15,min(120,maxSeconds))
  deadline=Task { [weak self] in
   try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))
   guard !Task.isCancelled,let self=self,self.generation==current else {return}
   self.release();self.status="已到录音上限，等待本地识别结果；不会自动发送"
  }
 }
 func release(cancelled:Bool=false) {
  guard state == .recording else {return}
  if cancelled {cancel(message:"已取消，未发送");return}
  #if DEBUG
  if gestureFixture {gate.finish();gate.review("语音手势测试结果");preview=gate.text;state = .review;status="请检查或修改文字，点击确认发送才会发给对方";duck?(false);return}
  #endif
  deadline?.cancel();deadline=nil;state = .finishing;gate.finish();status="正在完成本地识别…"
  sink.set(nil);capture.stop(restoreSession:false);duck?(false);request?.endAudio()
  let current=generation
  // A short finalization window keeps the last spoken syllables and corrections.
  // Preserve partials rather than waiting three seconds when text is already present.
  preview=draft.text
  let wait:UInt64=draft.text.isEmpty ? 3_000_000_000 : 700_000_000
  finalDeadline=Task { [weak self] in
   try? await Task.sleep(nanoseconds:wait)
   guard !Task.isCancelled,let self=self,self.generation==current else {return}
   if self.draft.text.isEmpty {self.cancel(message:"未收到识别文字；请靠近 iPad 麦克风，确认收音电平后重试")} else {self.finalText=self.draft.text;self.complete(current);self.status="识别未完整结束，请检查或修改文字后确认；尚未发送"}
  }
 }
 private func startRecognition(_ current:Int) {
  guard let recognizer=recognizer else {return}
  recognitionGeneration += 1;let segment=recognitionGeneration
  let request=SFSpeechAudioBufferRecognitionRequest()
  request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true;request.taskHint = .dictation
  self.request=request;sink.set(request)
  task=recognizer.recognitionTask(with:request) { [weak self] result,error in
   Task { @MainActor in
    guard let self=self,self.generation==current,self.recognitionGeneration==segment else {return}
    if let result=result {
     let value=result.bestTranscription.formattedString
     self.draft.accept(value,final:result.isFinal)
     let now=ProcessInfo.processInfo.systemUptime
     if result.isFinal || self.state == .finishing || now-self.lastPreviewUpdate>=0.2 {self.preview=self.draft.text;self.lastPreviewUpdate=now}
     if result.isFinal {
      if self.state == .finishing {self.finalText=self.draft.text;self.complete(current)}
      else if self.state == .recording {self.startRecognition(current)}
     }
    } else if let error=error {
     if !self.draft.text.isEmpty {
      if self.state == .recording {self.release();self.finalText=self.draft.text;self.complete(current)}
      else if self.state == .finishing {self.finalText=self.draft.text;self.complete(current)}
      self.status="识别已中断，已有文字已保留；请修改后确认，尚未发送"
     } else {let detail=error as NSError;self.cancel(message:"本地识别未返回文字（\(detail.domain):\(detail.code)），可重试；电影继续播放")}
    }
   }
  }
 }
 private func complete(_ current:Int) {
  guard current==generation,state == .finishing else {return}
  let text=(finalText ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
  let compact=text.replacingOccurrences(of:" ",with:"")
  guard !text.isEmpty,!compact.contains("取消弹幕") else {cancel(message:text.isEmpty ? "未识别到文字，未发送" : "已取消，未发送");return}
  finalDeadline?.cancel();finalDeadline=nil;generation += 1
  sink.set(nil);task?.cancel();task=nil;request=nil
  gate.review(text);preview=gate.text;state = .review;status="请检查或修改文字，点击确认发送才会发给对方"
 }
 func confirm() {
  guard state == .review else {return}
  gate.text=preview;gate.limit=maxCharacters
  let sender=sendText
  if gate.confirm(room:roomKey?() ?? "",send:{sender?($0) ?? false}) {state = .ready;preview="";status="已确认发送，按住可继续说话"}
  else {status="未发送：请检查房间连接、文字是否为空或超过 \(maxCharacters) 字"}
 }
 func cancel(message:String="已取消，未发送") {
  generation += 1;deadline?.cancel();deadline=nil;finalDeadline?.cancel();finalDeadline=nil
  sink.set(nil);capture.stop(restoreSession:false);duck?(false);request?.endAudio();task?.cancel();task=nil;request=nil;finalText=nil;gate.cancel();preview="";draft=VoiceRecognitionDraft()
  if state != .disabled {state = recognizer == nil ? .disabled : .ready};status=message
 }
 func disable() {cancel(message:"语音弹幕已关闭，麦克风已释放");capture.stop();state = .disabled;recognizer=nil;preview=""}
}
