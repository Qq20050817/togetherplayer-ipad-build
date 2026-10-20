import Foundation
import CoreGraphics
import Vision

// Evidence is separate from the strict question-bank Schema. Visual credits
// detection gives review candidates, never an automatic story-ending verdict.
enum FilmTailSamplingPlan {
 static let prioritySeconds = 720.0
 static let interval = 2.0
 static func start(duration:Double)->Double { max(0,duration-prioritySeconds) }
 static func dense(duration:Double,from override:Double?=nil)->[Double] {
  guard duration.isFinite,duration>0 else{return []}
  let begin=max(0,min(duration,override ?? start(duration:duration)))
  return stride(from:begin,to:duration,by:interval).map{$0}
 }
 static func boundary(at center:Double,duration:Double)->[Double] {
  guard duration>0 else{return []}
  return stride(from:max(0,center-5),through:min(duration-0.001,center+5),by:0.5).map{$0}
 }
 static func backward(from start:Double)->[Double] {
  let begin=max(0,start-60)
  return stride(from:begin,to:start,by:interval).map{$0}
 }
}

struct FilmFrameFailure:Codable {
 let startMs:Int
 let endMs:Int
 let requestedMs:Int
 let reason:String
 let returnedActualMs:Int?
}
struct FilmCreditCandidate:Codable {
 let atMs:Int
 let kind:String
 let confidence:Double
 let note:String
}
struct FilmEndingInspection:Codable {
 let formatVersion:Int
 let durationMs:Int
 let priorityStartMs:Int
 var inspectedRangesMs:[[Int]]
 var creditCandidates:[FilmCreditCandidate]
 var failedIntervals:[FilmFrameFailure]
 var unverifiedRangesMs:[[Int]]
 var storyEndMs:Int?
 let storyEndStatus:String
 let samplingPolicy:String
}

// Text on a mostly dark background is an intentionally conservative visual
// signal: opening cards, subtitles, and credits can look similar. OCR geometry
// by itself cannot establish the plot boundary or the absence of post-credits.
enum FilmCreditsDetector {
 static func isCreditsLike(_ image:CGImage)->Bool {
  guard let histogram=FilmSceneChange.signature(image) else{return false}
  let dark=histogram.prefix(4).reduce(0,+)
  guard dark>=0.52 else{return false}
  let request=VNDetectTextRectanglesRequest()
  request.reportCharacterBoxes=false
  do {
   try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
   let lines=request.results ?? []
   // Text geometry is used as a candidate signal only; no reliable end
   // timestamp is inferred from it.
   return lines.filter{$0.boundingBox.width>0.08 && $0.boundingBox.height>0.012}.count>=3
  } catch {return false}
 }
 static func candidates(_ signals:[(Int,Bool)])->[FilmCreditCandidate] {
  let ordered=signals.sorted{$0.0<$1.0}
  guard ordered.count>=3 else{return []}
  var result:[FilmCreditCandidate]=[]
  var run=0,nonCredits=0,inCredits=false,runStart=0,returnStart=0
  for (ms,credits) in ordered {
   if credits {
    if run==0 {runStart=ms}
    run+=1;nonCredits=0
    if !inCredits && run>=2 {
     result.append(FilmCreditCandidate(atMs:runStart,kind:"possibleCreditsStart",confidence:0.45,note:"连续深色文字画面；需检查边界、片尾彩蛋和完整剧情"))
     inCredits=true
    }
   } else {
    if nonCredits==0 {returnStart=ms}
    nonCredits+=1;run=0
    if inCredits && nonCredits>=2 {
     result.append(FilmCreditCandidate(atMs:returnStart,kind:"possiblePostCreditsScene",confidence:0.35,note:"演职员表后出现非名单画面；可能是彩蛋、标志或转场，需人工核实"))
     inCredits=false
    }
   }
  }
  return result
 }
}

// Shared time contract for FFmpeg and AVFoundation frames. Image similarity
// is deliberately excluded: a static shot has legitimately advancing PTS.
enum FilmFrameTimeGate {
 static func rejection(requestedMs:Int,actualMs:Int?,intervalMs:Int,previous:[(Int,Int)],durationMs:Int)->String? {
  guard let actualMs,actualMs>=0,actualMs<=durationMs else{return "没有可核实的解码帧时间戳"}
  if abs(actualMs-requestedMs)>max(50,intervalMs/2) {return "实际帧偏差超过采样间隔一半"}
  if previous.contains(where:{$0.1==actualMs && $0.0 != requestedMs}) {
   return "重复返回同一个帧时间戳"
  }
  if let preceding=previous.filter({$0.0<requestedMs}).max(by:{$0.0<$1.0}),preceding.1>actualMs {
   return "帧时间戳倒退"
  }
  return nil
 }
}
