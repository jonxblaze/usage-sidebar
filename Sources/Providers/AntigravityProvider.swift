import Foundation

enum AntigravityProvider {
    static let quotaURLs = [
        "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
        "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
    ]

    static func fetch() async -> ProviderStatus {
        if let status = await fetchLocalLS() { return status }
        if let token = await Task.detached(priority: .utility, operation: { loadAccessToken() }).value {
            if let status = await fetchCloud(token: token) { return status }
        }
        if await Task.detached(priority: .utility, operation: { loadAccessToken() }).value == nil {
            return .missingAuth(hint: ProviderID.antigravity.missingHint)
        }
        return .error("Antigravity quota unavailable. Open Antigravity and try again.")
    }

    private static func fetchCloud(token: String) async -> ProviderStatus? {
        do {
            for url in quotaURLs {
                let response = try await HTTP.request(
                    url: url,
                    method: "POST",
                    headers: [
                        "Authorization": "Bearer \(token)",
                        "Content-Type": "application/json",
                        "User-Agent": "antigravity",
                    ],
                    body: Data("{}".utf8)
                )
                if response.status == 401 || response.status == 403 {
                    return nil
                }
                if (200..<300).contains(response.status), let json = JSONMap(response.json) {
                    if let parsed = parseSummary(json) { return parsed }
                    continue
                }
            }
            return nil
        } catch HTTP.HTTPError.rateLimited(let delay) {
            return .rateLimited(until: Date().addingTimeInterval(delay))
        } catch {
            return nil
        }
    }

    private static func parseSummary(_ json: JSONMap) -> ProviderStatus? {
        let root = json.map("response") ?? json
        guard let groups = root.array("groups") else { return nil }
        var rows: [UsageRow] = []
        for groupAny in groups {
            guard let group = JSONMap(groupAny) else { continue }
            let groupName = group.string("displayName", "display_name") ?? "Gemini"
            guard let buckets = group.array("buckets") else { continue }
            for bucketAny in buckets {
                guard let bucket = JSONMap(bucketAny) else { continue }
                let id = (bucket.string("bucketId", "bucket_id") ?? "").lowercased()
                let window = (bucket.string("window") ?? "").lowercased()
                let isWeekly = id.hasSuffix("weekly") || window == "weekly"
                let is5h = id.hasSuffix("5h") || window == "5h"
                guard isWeekly || is5h else { continue }
                guard let remaining = bucket.double("remainingFraction", "remaining_fraction"),
                      remaining >= 0, remaining <= 1 else { continue }
                let reset = DateParse.date(from: bucket.any("resetTime", "reset_time"))
                let prefix = groupName.localizedCaseInsensitiveContains("gemini") ? "" : "\(groupName) "
                let title = prefix + (isWeekly ? "Weekly" : "Current session")
                let row = UsageRow(
                    title: title,
                    resetsAt: reset,
                    percentUsed: UsageMath.usedFromRemainingFraction(remaining),
                    unlimited: false
                )
                rows.append(row)
            }
        }
        guard !rows.isEmpty else { return nil }
        let used = rows.compactMap(\.percentUsed)
        let scarcest = used.max()
        return .ok(UsageSnapshot(
            ringPercent: scarcest,
            ringUnlimited: false,
            rows: rows,
            detail: nil
        ))
    }

    // MARK: - Credentials

    private static func loadAccessToken() -> String? {
        for data in credentialBlobs() {
            if let token = TokenScan.googleAccessToken(in: data) { return token }
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let token = TokenScan.googleAccessToken(inJSON: obj) {
                return token
            }
        }
        return nil
    }

    private static func credentialBlobs() -> [Data] {
        var blobs: [Data] = []
        let user = NSUserName()
        if let d = Secrets.keychainPassword(service: "gemini", account: "antigravity") { blobs.append(d) }
        if let d = Secrets.keychainPassword(service: "gemini") { blobs.append(d) }
        if let d = Secrets.keychainPassword(service: "Antigravity Safe Storage", account: user) { blobs.append(d) }
        let files = [
            ".gemini/oauth_creds.json",
            ".gemini/google_accounts.json",
            ".gemini/antigravity-cli/oauth_creds.json",
            ".gemini/antigravity-cli/antigravity-oauth-token",
            ".gemini/antigravity-cli/google_credentials",
            ".gemini/antigravity/google_credentials",
            ".gemini/antigravity-ide/oauth_creds.json",
            ".agy/credentials.json",
            ".agy/auth.json",
            ".agy/antigravity-oauth-token",
        ].map { Secrets.home.appendingPathComponent($0) }
        for url in files {
            if let d = Secrets.readFile(url) { blobs.append(d) }
        }
        // "Antigravity IDE" is the current app name; "Antigravity" is the legacy name.
        for appDir in ["Antigravity IDE", "Antigravity"] {
            let support = Secrets.home
                .appendingPathComponent("Library/Application Support/\(appDir)")
            let vscdb = support.appendingPathComponent("User/globalStorage/state.vscdb")
            guard FileManager.default.fileExists(atPath: vscdb.path) else { continue }
            for key in ["antigravityUnifiedStateSync.oauthToken", "antigravityAuthStatus"] {
                if let d = sqliteValue(path: vscdb, key: key) {
                    blobs.append(d)
                }
            }
        }
        return blobs
    }

    private static func sqliteValue(path: URL, key: String) -> Data? {
        let sqlite = ProcessRun.which("sqlite3") ?? "/usr/bin/sqlite3"
        let uri = "file:\(path.path)?mode=ro"
        guard let stdout = try? ProcessRun.capture(
            executable: sqlite,
            arguments: ["-readonly", uri, "SELECT value FROM ItemTable WHERE key = '\(key)';"],
            timeout: 5
        ) else { return nil }
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let decoded = Data(base64Encoded: trimmed) { return decoded }
        return Data(trimmed.utf8)
    }

    // MARK: - Local language server fallback

    private static func fetchLocalLS() async -> ProviderStatus? {
        let endpoints = await Task.detached(priority: .utility, operation: { discoverLSBases() }).value
        for (base, cmdCsrf) in endpoints.prefix(8) {
            let csrf: String?
            if let c = cmdCsrf { csrf = c } else { csrf = await fetchCSRF(base: base) }
            if let quota = await postRPC(base: base, csrf: csrf, rpc: "exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"),
               let json = JSONMap(quota),
               let parsed = parseSummary(json) {
                return parsed
            }
            if let status = await postRPC(base: base, csrf: csrf, rpc: "exa.language_server_pb.LanguageServerService/GetUserStatus"),
               let parsed = parseUserStatus(status) {
                return parsed
            }
        }
        return nil
    }

    private static func parseUserStatus(_ json: Any) -> ProviderStatus? {
        guard let root = JSONMap(json) else { return nil }
        let user = root.map("userStatus") ?? root
        let cascade = user.map("cascadeModelConfigData")
        let models = cascade?.array("clientModelConfigs") ?? []
        var geminiRows: [UsageRow] = []
        for model in models {
            guard let map = JSONMap(model) else { continue }
            let label = map.string("label", "displayName") ?? ""
            guard label.localizedCaseInsensitiveContains("gemini") else { continue }
            guard let quota = map.map("quotaInfo", "quota_info") else { continue }
            guard let remaining = quota.double("remainingFraction", "remaining_fraction"),
                  remaining >= 0, remaining <= 1 else { continue }
            let reset = DateParse.date(from: quota.any("resetTime", "reset_time"))
            geminiRows.append(UsageRow(
                title: "Current session",
                resetsAt: reset,
                percentUsed: UsageMath.usedFromRemainingFraction(remaining),
                unlimited: false
            ))
        }
        guard let scarcest = geminiRows.max(by: { ($0.percentUsed ?? -1) < ($1.percentUsed ?? -1) }) else {
            return nil
        }
        return .ok(UsageSnapshot(
            ringPercent: scarcest.percentUsed,
            ringUnlimited: false,
            rows: [scarcest],
            detail: nil
        ))
    }

    private static func postRPC(base: String, csrf: String?, rpc: String) async -> Any? {
        var headers = [
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
        ]
        if let csrf, !csrf.isEmpty {
            headers["X-Codeium-Csrf-Token"] = csrf
            headers["x-codeium-csrf-token"] = csrf
        }
        do {
            let response = try await HTTP.request(
                url: "\(base)/\(rpc)",
                method: "POST",
                headers: headers,
                body: Data("{}".utf8),
                timeout: 3
            )
            guard (200..<300).contains(response.status) else { return nil }
            return response.json
        } catch {
            return nil
        }
    }

    private static func fetchCSRF(base: String) async -> String? {
        do {
            let response = try await HTTP.request(
                url: base,
                headers: ["Accept": "text/html"],
                timeout: 2
            )
            guard let html = String(data: response.body, encoding: .utf8) else { return nil }
            if let part = html.components(separatedBy: "csrfToken\":\"").dropFirst().first {
                return part.components(separatedBy: "\"").first
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func discoverLSBases() -> [(base: String, csrf: String?)] {
        var results: [(base: String, csrf: String?)] = []
        var seen: Set<String> = []
        if let override = ProcessInfo.processInfo.environment["ANTIGRAVITY_LS_ADDRESS"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var addr = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !addr.contains("://") { addr = "http://\(addr)" }
            let base = addr.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            results.append((base: base, csrf: nil))
            seen.insert(base)
        }
        guard let ps = try? ProcessRun.capture(
            executable: "/bin/ps",
            arguments: ["-axww", "-o", "pid=,command="],
            timeout: 3
        ) else { return results }

        // Collect candidate PIDs; prioritise actual language_server processes
        // so they aren't pushed out of the prefix cap by Electron helpers.
        var lsPids: [(pid: String, csrf: String?)] = []
        var otherPids: [(pid: String, csrf: String?)] = []
        for line in ps.split(separator: "\n") {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard let space = raw.firstIndex(of: " ") else { continue }
            let pid = String(raw[..<space])
            let cmd = String(raw[raw.index(after: space)...])
            let lower = cmd.lowercased()
            let isLS = lower.contains("language_server")
            let isAGY = lower.contains("antigravity")
                || lower.range(of: #"(^|[ /])agy([ ]|$)"#, options: .regularExpression) != nil
            guard isLS || isAGY else { continue }
            var csrf: String?
            if let r = cmd.range(of: "--csrf_token ") {
                let rest = cmd[r.upperBound...]
                let tok = rest.prefix(while: { !$0.isWhitespace })
                if !tok.isEmpty { csrf = String(tok) }
            }
            if isLS { lsPids.append((pid, csrf)) } else { otherPids.append((pid, csrf)) }
        }
        let ordered = lsPids + otherPids

        let lsof = FileManager.default.isExecutableFile(atPath: "/usr/sbin/lsof")
            ? "/usr/sbin/lsof" : "/usr/bin/lsof"
        for (pid, csrf) in ordered.prefix(6) {
            guard let out = try? ProcessRun.capture(
                executable: lsof,
                arguments: ["-nP", "-a", "-p", pid, "-iTCP", "-sTCP:LISTEN"],
                timeout: 2
            ) else { continue }
            for line in out.split(separator: "\n") {
                if let port = portFromLsof(String(line)) {
                    for proto in ["https", "http"] {
                        let base = "\(proto)://127.0.0.1:\(port)"
                        if !seen.contains(base) {
                            results.append((base: base, csrf: csrf))
                            seen.insert(base)
                        }
                    }
                }
            }
        }
        return results
    }

    private static func portFromLsof(_ line: String) -> Int? {
        // TCP 127.0.0.1:51234 (LISTEN)
        guard let range = line.range(of: #"\d+\.\d+\.\d+\.\d+:(\d+)"#, options: .regularExpression) else {
            if let r = line.range(of: #":(\d+)\s+\(LISTEN\)"#, options: .regularExpression) {
                let s = String(line[r]).filter(\.isNumber)
                return Int(s)
            }
            return nil
        }
        let match = String(line[range])
        guard let colon = match.lastIndex(of: ":") else { return nil }
        return Int(match[match.index(after: colon)...])
    }
}
