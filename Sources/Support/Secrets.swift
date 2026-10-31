import Foundation
import Security

enum Secrets {
    /// Strip tokens from strings that might be logged or shown in errors.
    static func redact(_ text: String) -> String {
        var s = text
        let patterns = [
            "Bearer [A-Za-z0-9._\\-+=/]+",
            "token [A-Za-z0-9._\\-+=/]+",
            "ya29\\.[A-Za-z0-9._\\-]+",
            "sk-ant-[A-Za-z0-9._\\-]+",
            "gho_[A-Za-z0-9]+",
            "ghu_[A-Za-z0-9]+",
            "github_pat_[A-Za-z0-9_]+",
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p) {
                s = regex.stringByReplacingMatches(
                    in: s,
                    range: NSRange(s.startIndex..., in: s),
                    withTemplate: "[redacted]"
                )
            }
        }
        return s
    }

    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func readFile(_ url: URL) -> Data? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    /// Read a generic password another app stored.
    ///
    /// Do not call SecItemCopyMatching. These items trust `apple-tool:`
    /// (`/usr/bin/security`), not this ad-hoc binary. A direct copy shows the
    /// Mac login-password sheet, and neither `kSecUseAuthenticationUISkip` nor
    /// `LAContext.interactionNotAllowed` suppresses it (measured 2026-10-23
    /// against the `gemini` item). Token refreshes also rewrite the partition
    /// list, so Always Allow does not stick.
    ///
    /// If `security` blocks, it is waiting on that sheet. Kill it and do not
    /// retry: a 60s poll that kills the sheet is the password loop.
    static func keychainPassword(service: String, account: String? = nil) -> Data? {
        let key = service + "\u{0}" + (account ?? "")
        keychainGate.lock()
        let blocked = keychainBlocked.contains(key)
        keychainGate.unlock()
        if blocked { return nil }

        var args = ["find-generic-password", "-s", service]
        if let account, !account.isEmpty {
            args += ["-a", account]
        }
        args.append("-w")

        let data: Data
        do {
            data = try ProcessRun.captureData(
                executable: "/usr/bin/security",
                arguments: args,
                timeout: 2
            )
        } catch ProcessRun.RunError.timeout {
            keychainGate.lock()
            keychainBlocked.insert(key)
            keychainGate.unlock()
            return nil
        } catch {
            return nil
        }

        var bytes = [UInt8](data)
        if bytes.last == 0x0A { bytes.removeLast() }
        if bytes.last == 0x0D { bytes.removeLast() }
        guard !bytes.isEmpty else { return nil }
        return Data(bytes)
    }

    private static let apiKeyService = "com.jonb.UsageSidebar.api-key"

    private static func apiKeyQuery(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: id,
        ]
    }

    /// Keys for custom providers are items this app created, so unlike
    /// `keychainPassword` these go straight through SecItem. `security
    /// add-generic-password` would put the key on a process argument list.
    static func saveAPIKey(_ key: String, id: String) -> Bool {
        deleteAPIKey(id: id)
        var query = apiKeyQuery(id)
        query[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadAPIKey(id: String) -> String? {
        var query = apiKeyQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(id: String) {
        SecItemDelete(apiKeyQuery(id) as CFDictionary)
    }

    private static let keychainGate = NSLock()
    private static var keychainBlocked = Set<String>()
}

enum ProcessRun {
    enum RunError: Error { case timeout, failed, notFound }

    @discardableResult
    static func capture(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        extraPath: [String] = []
    ) throws -> String {
        let data = try captureData(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            extraPath: extraPath
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func captureData(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        extraPath: [String] = []
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        let extra = extraPath.joined(separator: ":")
        if !extra.isEmpty {
            env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        }
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        try process.run()

        var outData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            throw RunError.timeout
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RunError.failed }
        return outData
    }

    static func which(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(Secrets.home.path)/.local/bin/\(name)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}

final class LocalTrustDelegate: NSObject, URLSessionDelegate {
    static let shared = LocalTrustDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let host = challenge.protectionSpace.host.lowercased()
            if host == "127.0.0.1" || host == "localhost" {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

/// Keeps a custom provider's key from following a redirect to another host.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum HTTP {
    /// For URLs the user typed. `timeoutInterval` on a request is an idle
    /// timeout, so a slow drip needs this total deadline as well.
    private static let noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    static let maxUntrustedBody = 1_000_000

    private static let localSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config, delegate: LocalTrustDelegate.shared, delegateQueue: nil)
    }()

    struct Response {
        var status: Int
        var headers: [AnyHashable: Any]
        var body: Data
        var retryAfter: TimeInterval?

        var json: Any? {
            try? JSONSerialization.jsonObject(with: body)
        }
    }

    enum HTTPError: Error {
        case badURL
        case transport
        case status(Int)
        case rateLimited(TimeInterval)
        case empty
        case tooLarge
    }

    static func request(
        url: String,
        method: String = "GET",
        headers: [String: String],
        body: Data? = nil,
        timeout: TimeInterval = 15,
        followRedirects: Bool = true
    ) async throws -> Response {
        guard let parsed = URL(string: url) else { throw HTTPError.badURL }
        var req = URLRequest(url: parsed, timeoutInterval: timeout)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let host = parsed.host?.lowercased() ?? ""
        let session: URLSession
        if !followRedirects {
            session = noRedirectSession
        } else if host == "127.0.0.1" || host == "localhost" {
            session = localSession
        } else {
            session = URLSession.shared
        }
        let (data, urlResponse): (Data, URLResponse)
        do {
            if followRedirects {
                (data, urlResponse) = try await session.data(for: req)
            } else {
                (data, urlResponse) = try await cappedData(for: req, session: session)
            }
        } catch HTTPError.tooLarge {
            throw HTTPError.tooLarge
        } catch {
            throw HTTPError.transport
        }
        guard let http = urlResponse as? HTTPURLResponse else { throw HTTPError.transport }
        let retry = parseRetryAfter(http)
        if http.statusCode == 429 {
            throw HTTPError.rateLimited(retry ?? 60)
        }
        return Response(
            status: http.statusCode,
            headers: http.allHeaderFields,
            body: data,
            retryAfter: retry
        )
    }

    private static func cappedData(for req: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: req)
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxUntrustedBody { throw HTTPError.tooLarge }
        }
        return (data, response)
    }

    private static func parseRetryAfter(_ http: HTTPURLResponse) -> TimeInterval? {
        let value = http.value(forHTTPHeaderField: "Retry-After")
            ?? http.value(forHTTPHeaderField: "retry-after")
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite { return min(max(seconds, 1), 3600) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return max(date.timeIntervalSinceNow, 1)
        }
        return nil
    }
}
