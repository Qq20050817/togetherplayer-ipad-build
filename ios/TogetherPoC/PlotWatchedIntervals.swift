import Foundation

// A rewind can place the next played interval below an earlier recorded one.
// Only merge overlapping intervals; never form a reversed ClosedRange or fill
// an unwatched jump. Historical ranges remain bounded and AI still uses cutoff.
enum PlotWatchedIntervals {
 static func record(_ ranges:inout [ClosedRange<Double>],from start:Double,to end:Double) {
  guard start.isFinite,end.isFinite,start>=0,end>start,end-start<=2.5 else {return}
  if let previous=ranges.last,start<=previous.upperBound+0.2,end>=previous.lowerBound-0.2 {
   ranges[ranges.count-1]=min(previous.lowerBound,start)...max(previous.upperBound,end)
  } else {
   ranges.append(start...end)
   if ranges.count>500 {ranges.removeFirst(ranges.count-500)}
  }
 }
}
