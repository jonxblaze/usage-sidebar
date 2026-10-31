import Foundation

enum ClaudeProvider {
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let keychainService = "Claude Code-credentials"
    static let keychainServiceAlt = "Claude Code"

    static func fetch() async -> ProviderStatus {
        do {
            let tokens = await loadAccessTokens()
            guard !tokens.isEmpty else {
                return .missingAuth(hint: BuiltInProvider.claude.missingHint)
            }
            var lastStatus = 0
            var sawAuthFailure = false
            for token in tokens {
                let response = try await HTTP.request(
                    url: usageURL,
                    headers: [
                        "Authorization": "Bearer \(token)",
                        "Accept": "application/json",
                        "Content-Type": "application/json",
                        "anthropic-beta": "oauth-2025-04-20",
                        "User-Agent": "claude-code/2.1.260",
                    ]
                )
                lastStatus = response.status
                if response.status == 401 || response.status == 403 {
                    sawAuthFailure = true
                    continue
                }
                guard (200..<300).contains(response.status), let json = JSONMap(response.json) else {
                    return .error("Claude usage request failed (\(response.status)).")
                }
                return parse(json)
            }
            if sawAuthFailure {
                return .missingAuth(hint: "Claude sign-in expired. Open Claude Code so it can refresh, then this sidebar will update.")
            }
            return .error("Claude usage request failed (\(lastStatus)).")
        } catch HTTP.HTTPError.rateLimited(let delay) {
            return .rateLimited(until: Date().addingTimeInterval(delay))
        } catch HTTP.HTTPError.transport {
            return .error("Could not reach api.anthropic.com.")
        } catch {
            return .error("Claude usage unavailable.")
        }
    }

    static func parse(_ json: JSONMap) -> ProviderStatus {
        let session = window(json.map("five_hour", "fiveHour"), title: "Current session")
        let weekly = window(json.map("seven_day", "sevenDay"), title: "All models")
        var rows: [UsageRow] = []
        if let session { rows.append(session) }
        if let weekly { rows.append(weekly) }
        guard !rows.isEmpty else {
            return .error("Claude usage payload had no session or weekly window.")
        }
        return .ok(UsageSnapshot(
            ringPercent: session?.percentUsed,
            ringUnlimited: false,
            rows: rows,
            detail: nil
        ))
    }

    private static func window(_ map: JSONMap?, title: String) -> UsageRow? {
        guard let map else { return nil }
        guard let raw = map.double("utilization") else { return nil }
        let resets = DateParse.date(from: map.any("resets_at", "resetsAt"))
        return UsageRow(
            title: title,
            resetsAt: resets,
            percentUsed: UsageMath.clampedPercent(raw),
            unlimited: false
        )
    }

    /// Claude Code refreshes into Keychain (`Claude Code-credentials`). The
    /// `~/.claude/.credentials.json` copy is often weeks stale and must not
    /// win just because the file exists. Does not refresh OAuth itself —
    /// refreshing would rotate Claude Code's token.
    ///
    /// `Secrets.keychainPassword` reads through `/usr/bin/security`, which
    /// this item already trusts. No login-password sheet on the poll.
    private static func loadAccessTokens() async -> [String] {
        var candidates: [Candidate] = []
        var seen = Set<String>()
        func add(_ data: Data?) {
            guard let data, let parsed = parsedOAuth(from: data) else { return }
            guard seen.insert(parsed.token).inserted else { return }
            candidates.append(parsed)
        }
        let silent = await Task.detached(priority: .utility) {
            (
                Secrets.keychainPassword(service: keychainService),
                Secrets.keychainPassword(service: keychainServiceAlt),
                Secrets.readFile(Secrets.home.appendingPathComponent(".claude/.credentials.json"))
            )
        }.value
        add(silent.0)
        add(silent.1)
        add(silent.2)
        let now = Date()
        return candidates
            .sorted { a, b in
                let aValid = a.expiresAt.map { $0 > now } ?? true
                let bValid = b.expiresAt.map { $0 > now } ?? true
                if aValid != bValid { return aValid && !bValid }
                return (a.expiresAt ?? .distantPast) > (b.expiresAt ?? .distantPast)
            }
            .map(\.token)
    }

    private struct Candidate {
        var token: String
        var expiresAt: Date?
    }

    private static func parsedOAuth(from data: Data) -> Candidate? {
        let text = String(data: data, encoding: .utf8) ?? ""
        let jsonData = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) else { return nil }
        let root = JSONMap(obj)
        let oauth = root?.map("claudeAiOauth", "claude_ai_oauth") ?? root
        guard let access = oauth?.string("accessToken", "access_token") else { return nil }
        return Candidate(
            token: access,
            expiresAt: DateParse.date(from: oauth?.any("expiresAt", "expires_at"))
        )
    }
}
