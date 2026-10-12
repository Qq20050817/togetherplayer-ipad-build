import Foundation
import CryptoKit
import Security

// Verify the signed ID token before saving any credentials. Never trust claims
// obtained by base64-decoding without signature verification.
enum ChatGPTIdentityVerifier {
 enum Failure:Error {case invalidToken,invalidSignature,invalidClaims,missingKey}
 static func base64URL(_ value:String)->Data? {
  var s=value.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
  s+=String(repeating:"=",count:(4-s.count%4)%4)
  return Data(base64Encoded:s)
 }
 static func signedIdentity(_ jwt:String,clientID:String,nonce:String) async throws -> String {
  let pieces=jwt.split(separator:".").map(String.init)
  guard pieces.count==3,
   let headerData=base64URL(pieces[0]),
   let header=(try? JSONSerialization.jsonObject(with:headerData)) as? [String:Any],
   header["alg"] as? String == "RS256",let kid=header["kid"] as? String,
   let payloadData=base64URL(pieces[1]),
   let payload=(try? JSONSerialization.jsonObject(with:payloadData)) as? [String:Any],
   let signature=base64URL(pieces[2]) else {throw Failure.invalidToken}
  let jwksURL=URL(string:"https://auth.openai.com/.well-known/jwks.json")!
  var request=URLRequest(url:jwksURL);request.timeoutInterval=20
  let (keyData,response)=try await URLSession.shared.data(for:request)
  guard (response as? HTTPURLResponse)?.statusCode==200,
   let keys=(try? JSONSerialization.jsonObject(with:keyData)) as? [String:Any],
   let list=keys["keys"] as? [[String:Any]],
   let item=list.first(where:{$0["kid"] as? String==kid && $0["kty"] as? String=="RSA"}),
   let n=item["n"] as? String,let e=item["e"] as? String,
   let modulus=base64URL(n),let exponent=base64URL(e) else {throw Failure.missingKey}
  let publicKey=try createRSAPublicKey(modulus:modulus,exponent:exponent)
  let signedPart=Data((pieces[0]+"."+pieces[1]).utf8)
  var err:Unmanaged<CFError>?
  guard SecKeyVerifySignature(publicKey,.rsaSignatureMessagePKCS1v15SHA256,signedPart as CFData,signature as CFData,&err) else {
   throw Failure.invalidSignature
  }
  let now=Date().timeIntervalSince1970
  let audiences=(payload["aud"] as? [String]) ?? [(payload["aud"] as? String ?? "")]
  guard payload["iss"] as? String=="https://auth.openai.com",
   audiences.contains(clientID),payload["nonce"] as? String==nonce,
   let exp=(payload["exp"] as? NSNumber)?.doubleValue,exp>now-30,
   let issued=(payload["iat"] as? NSNumber)?.doubleValue,issued<=now+60,
   let sub=payload["sub"] as? String,!sub.isEmpty else {throw Failure.invalidClaims}
  return sub
 }
 private static func createRSAPublicKey(modulus:Data,exponent:Data) throws -> SecKey {
  func length(_ size:Int)->Data {
   if size<128 {return Data([UInt8(size)])}
   var n=size,bytes:[UInt8]=[]
   while n>0 {bytes.insert(UInt8(n&255),at:0);n>>=8}
   return Data([0x80|UInt8(bytes.count)]+bytes)
  }
  func integer(_ bytes:Data)->Data {
   var b=bytes
   while b.count>1 && b.first==0 {b.removeFirst()}
   if let first=b.first,first>=0x80 {b.insert(0,at:0)}
   return Data([0x02])+length(b.count)+b
  }
  let seq=integer(modulus)+integer(exponent)
  let der=Data([0x30])+length(seq.count)+seq
  var err:Unmanaged<CFError>?
  guard let key=SecKeyCreateWithData(der as CFData,[
   kSecAttrKeyType:kSecAttrKeyTypeRSA,
   kSecAttrKeyClass:kSecAttrKeyClassPublic,
   kSecAttrKeySizeInBits:modulus.count*8
  ] as CFDictionary,&err) else {throw Failure.invalidToken}
  return key
 }
}

struct ChatGPTLocalCredentials:Codable {
 var clientID:String
 var subject:String
 var idToken:String
 var accessToken:String
 var refreshToken:String
 var scopes:String
 var expiresAt:Double
}
enum ChatGPTLocalKeychain {
 private static let service="dev.together.poc.chatgpt-probe"
 static func read()->ChatGPTLocalCredentials? {
  let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,
   kSecAttrService as String:service,kSecAttrAccount as String:"default",
   kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
  var result:CFTypeRef?
  guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,
   let data=result as? Data else {return nil}
  return try? JSONDecoder().decode(ChatGPTLocalCredentials.self,from:data)
 }
 static func save(_ value:ChatGPTLocalCredentials)->Bool {
  guard let data=try? JSONEncoder().encode(value) else{return false}
  let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,
    kSecAttrService as String:service,kSecAttrAccount as String:"default"]
  let attributes:[String:Any]=[kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
  let updated=SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
  if updated==errSecSuccess {return true}
  guard updated==errSecItemNotFound else {return false}
  var q=query
  q[kSecValueData as String]=data
  q[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  return SecItemAdd(q as CFDictionary,nil)==errSecSuccess
 }
 static func delete(){
  SecItemDelete([kSecClass as String:kSecClassGenericPassword,
    kSecAttrService as String:service,kSecAttrAccount as String:"default"] as CFDictionary)
 }
}
