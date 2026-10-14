package dev.together.poc

// Keep the long movie question in a scrollable BODY. Android AlertDialog's
// title is a single line on some vendor ROMs, truncating the actual question.
object PlotPollPresentation {
 fun title(kind:String,minutes:Long,seconds:Long):String = "🎭 $kind · $minutes:${seconds.toString().padStart(2,'0')}"
 fun questionBody(waiting:Boolean,question:String):String =
  (if(waiting)"先选一个答案，双方提交后继续播放。后续剧情预测将在真正看过后再核对。\n\n" else "") +
   question.trim().ifEmpty{"题目正在同步，请稍后重新打开。"}
}
