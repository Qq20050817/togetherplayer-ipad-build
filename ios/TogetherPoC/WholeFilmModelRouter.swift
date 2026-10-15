import Foundation

enum WholeFilmBackend:String {case local,chatgpt}
enum WholeFilmRoutingFailure:LocalizedError {
 case localUnavailable,localLanguage,cloudBlocked(String),fallback
 var errorDescription:String? {
  switch self {
  case .localUnavailable:return "苹果本地 AI 当前不可用；可切换到已授权的 ChatGPT。"
  case .localLanguage:return "苹果本地 AI 不支持当前语言或地区，尚未完成分析。可切换“仅 ChatGPT”；不会要求修改影片或字幕。"
  case .cloudBlocked(let message):return message
  case .fallback:return "当前选择免费备用题库，不运行全片 AI 分析。"
  }
 }
}

/// Explicit choices apply to analysis and spoiler audit, not just question
/// generation. A language failure in Smart mode can use an already-authorized
/// cloud backend, but never changes privacy consent or enables a paid API.
@MainActor final class WholeFilmModelRouter {
 typealias Inference=(String,String) async throws->String
 var localAvailable:()->Bool={PlotLocalAI.available}
 var cloudAllowed:()->Bool={false}
 var cloudBlockedReason:()->String={"ChatGPT 全片分析尚未就绪；请检查授权、全片隐私同意、智能调用及额度保护。"}
 var localInference:Inference={try await PlotLocalAI.respond(instructions:$0,input:$1)}
 var cloudInference:Inference={_,_ in throw WholeFilmRoutingFailure.cloudBlocked("ChatGPT 尚未连接。")}
 var onBackend:((WholeFilmBackend)->Void)?
 private(set) var localLanguageFailed=false
 var canUseLocal:Bool {localAvailable() && !localLanguageFailed}
 func available(mode:PlotMode)->Bool {
  switch mode {
  case .chatgpt:return cloudAllowed()
  case .local:return canUseLocal
  case .smart:return canUseLocal || cloudAllowed()
  case .fallback:return false
  }
 }
 func unavailableError(mode:PlotMode)->Error {
  if mode == .fallback {return WholeFilmRoutingFailure.fallback}
  if mode == .local {return localLanguageFailed ? WholeFilmRoutingFailure.localLanguage : WholeFilmRoutingFailure.localUnavailable}
  if mode == .chatgpt {return WholeFilmRoutingFailure.cloudBlocked(cloudBlockedReason())}
  return localLanguageFailed ? WholeFilmRoutingFailure.localLanguage : WholeFilmRoutingFailure.cloudBlocked(cloudBlockedReason())
 }
 static func isLocalLanguageError(_ error:Error)->Bool {
  let message=error.localizedDescription.lowercased()
  return message.contains("unsupported language") || message.contains("unsupportedlanguageorlocale") || message.contains("unsupported locale") ||
   (message.contains("不支持") && (message.contains("语言") || message.contains("地区")))
 }
 func respond(mode:PlotMode,instructions:String,input:String,cloudPermission:Bool?=nil,cloud:Inference?=nil) async throws->String {
  let permitted=cloudPermission ?? cloudAllowed()
  let remote=cloud ?? cloudInference
  switch mode {
  case .fallback:throw WholeFilmRoutingFailure.fallback
  case .chatgpt:
   guard permitted else{throw WholeFilmRoutingFailure.cloudBlocked(cloudBlockedReason())}
   onBackend?(.chatgpt);return try await remote(instructions,input)
  case .local,.smart:
   if canUseLocal {
    onBackend?(.local)
    do {return try await localInference(instructions,input)}
    catch {
     if error is CancellationError {throw error}
     guard Self.isLocalLanguageError(error) else{throw error}
     localLanguageFailed=true
     guard mode == .smart,permitted else{throw WholeFilmRoutingFailure.localLanguage}
     try Task.checkCancellation()
     onBackend?(.chatgpt);return try await remote(instructions,input)
    }
   }
   guard mode == .smart,permitted else{throw unavailableError(mode:mode)}
   onBackend?(.chatgpt);return try await remote(instructions,input)
  }
 }
}
