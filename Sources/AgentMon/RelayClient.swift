import CryptoKit
import Foundation
import Security

enum RelayClientError: LocalizedError {
  case invalidConfiguration(String)
  case authenticationFailed
  case incompatibleProtocol(Int)
  case invalidResponse
  case staleSnapshot
  case certificateMismatch

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message): message
    case .authenticationFailed: "The relay rejected its pairing token."
    case .incompatibleProtocol(let version):
      "The relay uses unsupported protocol version \(version)."
    case .invalidResponse: "The relay returned an invalid response."
    case .staleSnapshot: "The relay snapshot is stale."
    case .certificateMismatch: "The relay certificate does not match its saved fingerprint."
    }
  }
}

struct RelayConfiguration: Equatable, Sendable {
  let baseURL: URL
  let certificateFingerprint: String
  let token: String

  static func load() -> RelayConfiguration? {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: SettingsKeys.relayEnabled),
      let rawURL = defaults.string(forKey: SettingsKeys.relayURL),
      let url = URL(string: rawURL),
      let token = try? RelayKeychain.loadToken(),
      !token.isEmpty
    else {
      return nil
    }

    return RelayConfiguration(
      baseURL: url,
      certificateFingerprint: defaults.string(forKey: SettingsKeys.relayFingerprint) ?? "",
      token: token
    )
  }

  func validate() throws {
    guard baseURL.scheme?.lowercased() == "https" else {
      throw RelayClientError.invalidConfiguration("The relay URL must use HTTPS.")
    }
    guard baseURL.host != nil else {
      throw RelayClientError.invalidConfiguration("The relay URL needs a host name or address.")
    }
    guard !token.isEmpty else {
      throw RelayClientError.invalidConfiguration("Enter the relay pairing token.")
    }
    guard PinnedRelayDelegate.normalize(certificateFingerprint).count == 64 else {
      throw RelayClientError.invalidConfiguration(
        "Enter the relay certificate's SHA-256 fingerprint."
      )
    }
  }
}

struct RelayClient {
  func fetchSnapshot(configuration: RelayConfiguration) async throws -> RelaySnapshot {
    try configuration.validate()

    let delegate = PinnedRelayDelegate(
      fingerprint: configuration.certificateFingerprint
    )
    let session = URLSession(
      configuration: .ephemeral,
      delegate: delegate,
      delegateQueue: nil
    )
    defer { session.finishTasksAndInvalidate() }

    var request = URLRequest(
      url: configuration.baseURL.appendingPathComponent("v1/status")
    )
    request.timeoutInterval = 5
    request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      if let validationError = delegate.validationError {
        throw validationError
      }
      throw error
    }
    if let error = delegate.validationError {
      throw error
    }
    guard let http = response as? HTTPURLResponse else {
      throw RelayClientError.invalidResponse
    }
    if http.statusCode == 401 || http.statusCode == 403 {
      throw RelayClientError.authenticationFailed
    }
    guard 200..<300 ~= http.statusCode else {
      throw RelayClientError.invalidResponse
    }

    let snapshot = try RelaySnapshotDecoder.decode(data)
    guard snapshot.protocolVersion == RelayProtocol.version else {
      throw RelayClientError.incompatibleProtocol(snapshot.protocolVersion)
    }
    guard !snapshot.host.id.isEmpty,
      !snapshot.host.name.isEmpty,
      snapshot.sessions.count <= 50,
      snapshot.sessions.allSatisfy({
        !$0.id.isEmpty
          && !$0.project.isEmpty
          && !$0.task.isEmpty
          && $0.task.unicodeScalars.count <= 120
      })
    else {
      throw RelayClientError.invalidResponse
    }
    guard abs(snapshot.generatedAt.timeIntervalSinceNow) <= RelayProtocol.maximumSnapshotAge else {
      throw RelayClientError.staleSnapshot
    }
    return snapshot
  }
}

final class PinnedRelayDelegate: NSObject, URLSessionDelegate {
  private let fingerprint: String
  private(set) var validationError: RelayClientError?

  init(fingerprint: String) {
    self.fingerprint = Self.normalize(fingerprint)
  }

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let trust = challenge.protectionSpace.serverTrust,
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
      let certificate = chain.first
    else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }

    let data = SecCertificateCopyData(certificate) as Data
    let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard actual == fingerprint else {
      validationError = .certificateMismatch
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }

    completionHandler(.useCredential, URLCredential(trust: trust))
  }

  static func normalize(_ value: String) -> String {
    value
      .lowercased()
      .filter(\.isHexDigit)
  }
}

enum RelayKeychain {
  private static let service = "com.verykross.AgentMon.relay"
  private static let account = "primary"

  static func saveToken(_ token: String) throws {
    let base: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    SecItemDelete(base as CFDictionary)

    var item = base
    item[kSecValueData] = Data(token.utf8)
    item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw RelayClientError.invalidConfiguration(
        "Could not save the pairing token in Keychain (error \(status))."
      )
    }
  }

  static func loadToken() throws -> String {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return ""
    }
    guard status == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      throw RelayClientError.invalidConfiguration(
        "Could not read the pairing token from Keychain (error \(status))."
      )
    }
    return value
  }
}
