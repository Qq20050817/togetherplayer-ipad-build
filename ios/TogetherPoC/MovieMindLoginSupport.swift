import Foundation

protocol MovieMindSessionStorage: Sendable {
  func read() -> String
  func write(_ token: String) throws
}

struct MovieMindStoredSession: Codable {
  let origin: String
  let userId: String
  let token: String

  static func decode(_ value: String, origin: String, userId: String?) -> String {
    if let data = value.data(using: .utf8),
      let session = try? JSONDecoder().decode(Self.self, from: data)
    {
      return session.origin == origin && session.userId == userId ? session.token : ""
    }
    // Legacy opaque receipts remain usable only at their existing stored scope.
    guard userId != nil,
      value.range(of: "^[A-Za-z0-9_-]{16,512}$", options: .regularExpression) != nil
    else { return "" }
    return value
  }
}

enum MovieMindLoginFailure: Error {
  case emptyCredentials
  case inProgress
  case invalidAddress
  case pendingService
  case pendingAccount
  case unreadableOutbox
  case invalidReceipt
  case sessionStorage(Int32)

  static func canonicalOrigin(_ input: String) throws -> String {
    let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var parts = URLComponents(string: input), let scheme = parts.scheme?.lowercased(),
      let host = parts.host?.lowercased(), !host.isEmpty,
      host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
      parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/",
      scheme == "https" || scheme == "http" && ["127.0.0.1", "localhost"].contains(host)
    else { throw Self.invalidAddress }
    parts.scheme = scheme
    parts.host = host
    parts.path = ""
    if scheme == "https" && parts.port == 443 || scheme == "http" && parts.port == 80 {
      parts.port = nil
    }
    guard let result = parts.url?.absoluteString else { throw Self.invalidAddress }
    return result
  }

  static func message(for error: Error) -> String {
    if let error = error as? Self {
      switch error {
      case .emptyCredentials: return "请填写用户名和密码，再登录"
      case .inProgress: return "正在登录，请稍候"
      case .invalidAddress: return "服务地址格式不正确，请填写独立服务的 HTTPS 根地址"
      case .pendingService: return "本机有待同步草稿，请先登录原服务完成同步；草稿已保留"
      case .pendingAccount: return "本机草稿属于另一个账号，请先登录原账号完成同步；草稿已保留"
      case .unreadableOutbox: return "本机待同步文件暂时无法读取，原文件已保留；播放不受影响"
      case .invalidReceipt: return "服务登录回执不完整，尚未保存新账号；请稍后重试"
      case .sessionStorage(let code):
        if code == -34018 {
          return "服务器已验证账号，但当前安装签名缺少钥匙串权限（Keychain -34018）；请核对签名安装，草稿已保留"
        }
        return "服务器已验证账号，但系统未能保存登录凭证（Keychain \(code)）；原会话和草稿已保留"
      }
    }
    let error = error as NSError
    if error.domain == "MovieMindHTTP" {
      switch error.code {
      case 401, 403: return "服务拒绝登录（HTTP \(error.code)），请先在网页用同一账号核对；草稿已保留"
      case 429: return "登录尝试过于频繁（HTTP 429），请稍后再试"
      case 300...399: return "服务地址发生跳转（HTTP \(error.code)），请核对 HTTPS 根地址"
      default: return "MovieMind 登录服务暂不可用（HTTP \(error.code)），请稍后再试"
      }
    }
    if error.domain == NSURLErrorDomain {
      switch error.code {
      case URLError.timedOut.rawValue: return "登录连接超时（网络 -1001），请稍后重试；播放不受影响"
      case URLError.cannotFindHost.rawValue, URLError.dnsLookupFailed.rawValue:
        return "暂时无法解析服务地址（网络 \(error.code)），请核对网址"
      case URLError.notConnectedToInternet.rawValue, URLError.networkConnectionLost.rawValue:
        return "网络连接暂不可用（网络 \(error.code)），请连接后重试"
      case URLError.secureConnectionFailed.rawValue, URLError.serverCertificateUntrusted.rawValue,
        URLError.serverCertificateHasBadDate.rawValue,
        URLError.serverCertificateHasUnknownRoot.rawValue:
        return "HTTPS 安全连接失败（网络 \(error.code)），请核对服务地址和系统时间"
      default: return "MovieMind 连接失败（网络 \(error.code)），请稍后重试；草稿已保留"
      }
    }
    return "MovieMind 登录未完成，请稍后重试；原会话和草稿已保留"
  }
}
