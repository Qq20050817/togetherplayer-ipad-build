import Foundation
import CryptoKit

enum BaiduFileIdentity {
 static func size(_ value: Any?) -> Int64? {
  let n: Int64?
  if let text=value as? String {n=Int64(text.trimmingCharacters(in:.whitespacesAndNewlines))}
  else if let number=value as? NSNumber {n=number.int64Value;guard number.doubleValue==Double(number.int64Value) else {return nil}}
  else {n=nil}
  guard let n=n,n>0,n<=9007199254740991 else {return nil};return n
 }
 static func provider(_ value: Any?) -> String? {
  guard let text=(value as? String)?.trimmingCharacters(in:.whitespacesAndNewlines),!text.isEmpty,text != String(repeating:"0",count:32) else {return nil}
  if text.range(of:"^[a-fA-F0-9]{32}$",options:.regularExpression) != nil {return text.lowercased()}
  // Provider fingerprints can be opaque identifiers, not literal hexadecimal MD5.
  guard text.range(of:"^[A-Za-z0-9_-]{32,128}$",options:.regularExpression) != nil else {return nil}
  return digest(Data(("baidu-provider-md5-v1:"+text).utf8))
 }
 static func merge(info: [String:Any],file: BaiduFile) -> BaiduFile {
  BaiduFile(id:file.id,name:file.name,path:file.path,size:size(info["size"]) ?? size(file.size) ?? 0,fingerprint:provider(info["md5"]) ?? provider(file.fingerprint) ?? "",isDirectory:false)
 }
 static func offsets(size: Int64) -> [Int64] {Array(Set([0,max(0,size/2-32768),max(0,size-65536)])).sorted()}
 static func sample(size: Int64,samples: [(Int64,Data)]) -> String {
  var bytes=Data("together-baidu-sample-v1\n\(size)\n".utf8)
  for (offset,data) in samples.sorted(by:{$0.0<$1.0}) {bytes.append(Data("\n\(offset):\(data.count)\n".utf8));bytes.append(data)}
  return digest(bytes)
 }
 static func localFile(_ url: URL) throws -> (size: Int64,fingerprint: String) {
  guard url.isFileURL else {throw CocoaError(.fileReadUnsupportedScheme)}
  let values=try url.resourceValues(forKeys:[.fileSizeKey])
  guard let raw=values.fileSize,raw>0 else {throw CocoaError(.fileReadCorruptFile)}
  let size=Int64(raw)
  guard size<=9007199254740991 else {throw CocoaError(.fileReadTooLarge)}
  let handle=try FileHandle(forReadingFrom:url)
  defer {try? handle.close()}
  var samples:[(Int64,Data)]=[]
  for offset in offsets(size:size) {
   let count=Int(min(65536,size-offset))
   try handle.seek(toOffset:UInt64(offset))
   let data=try handle.read(upToCount:count) ?? Data()
   guard data.count==count else {throw CocoaError(.fileReadCorruptFile)}
   samples.append((offset,data))
  }
  return (size,sample(size:size,samples:samples))
 }
 private static func digest(_ data: Data) -> String {SHA256.hash(data:data).prefix(16).map {String(format:"%02x",$0)}.joined()}
}
