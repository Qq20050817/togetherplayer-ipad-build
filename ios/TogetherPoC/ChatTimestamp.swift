import Foundation

/// Chat message timestamps are Unix milliseconds supplied by the room server.
/// Never use the local receive time: history and reconnects must keep the same time.
enum ChatTimestamp {
 static func label(milliseconds:Double,now:Date=Date(),calendar:Calendar=Calendar.current)->String {
  guard milliseconds.isFinite,milliseconds>0,milliseconds<253402300799000 else {return ""}
  let date=Date(timeIntervalSince1970:milliseconds/1000)
  let formatter=DateFormatter()
  formatter.locale=Locale(identifier:"zh_CN")
  formatter.calendar=calendar
  formatter.timeZone=calendar.timeZone
  if calendar.isDate(date,inSameDayAs:now) {
   formatter.dateFormat="HH:mm"
   return formatter.string(from:date)
  }
  let yesterday=calendar.date(byAdding:.day,value:-1,to:now)
  if let yesterday=yesterday,calendar.isDate(date,inSameDayAs:yesterday) {
   formatter.dateFormat="HH:mm"
   return "昨天 "+formatter.string(from:date)
  }
  formatter.dateFormat=calendar.component(.year,from:date)==calendar.component(.year,from:now) ?
   "M月d日 HH:mm" : "yyyy年M月d日 HH:mm"
  return formatter.string(from:date)
 }
}
