import Foundation

struct BaiduMediaReference: Equatable {
 let nonce: String
 let fingerprint: String
 let size: Int64
 var value: String {"baidu://\(nonce)/\(fingerprint)/\(size)"}
 init?(value: String) {
  guard value.range(of:"^baidu://[a-f0-9]{32}/[a-f0-9]{32}/[1-9][0-9]{0,15}$",options:.regularExpression) != nil else {return nil}
  let parts=value.dropFirst(8).split(separator:"/")
  guard parts.count==3,let n=Int64(parts[2]),n<=9007199254740991 else {return nil}
  nonce=String(parts[0]);fingerprint=String(parts[1]);size=n
 }
 static func create(fingerprint: String,size: Int64) -> Self? {
  Self(value:"baidu://\(UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased())/\(fingerprint.lowercased())/\(size)")
 }
 func matches(fingerprint: String,size: Int64) -> Bool {self.fingerprint==fingerprint.lowercased() && self.size==size}
}
