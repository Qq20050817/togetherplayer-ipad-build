import Foundation
@main struct BaiduReferenceRegression {
 static func main() {
  let one=BaiduMediaReference.create(fingerprint:String(repeating:"A",count:32),size:6800248966)!
  let two=BaiduMediaReference.create(fingerprint:String(repeating:"a",count:32),size:6800248966)!
  precondition(one.value != two.value && BaiduMediaReference(value:one.value)==one)
  precondition(one.matches(fingerprint:String(repeating:"a",count:32),size:6800248966))
  precondition(!one.matches(fingerprint:String(repeating:"b",count:32),size:6800248966))
  precondition(!one.matches(fingerprint:one.fingerprint,size:5))
  precondition(BaiduMediaReference(value:one.value+"?access_token=secret")==nil)
  precondition(BaiduMediaReference.create(fingerprint:one.fingerprint,size:9007199254740992)==nil)
  print("PASS: Baidu identity matching, session invalidation, credential rejection and size bounds")
 }
}
