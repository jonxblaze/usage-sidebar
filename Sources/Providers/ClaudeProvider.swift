import Foundation

enum ClaudeProvider {
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let keychainService = "Claude Code-credentials"
    static let keychainServiceAlt = "Claude Code"

    static func fetch() async -> ProviderStatus {
        do {
            guard let token = await Task.detached(priority: .utility, operation: { loadAccessToken() }).value else {
                return .missingAuth(hint: ProviderID.claude.missingHint)
            }
            let response = try await HTTP.request(
                url: usageURL,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "anthropic-beta": "oauth-2025-04-20",
                    "User-Agent": "claude-code/2.1.0",
                ]
            )
            if response.status == 401 || response.status == 403 {
                return .missingAuth(hint: "Claude sign-in expired. Open Claude Code so it can refresh, then this sidebar will update.")
            }
            guard (200..<300).contains(response.status), let json = JSONMap(response.json) else {
                return .error("Claude usage request failed (\(response.status)).")
            }
            return parse(json)
        } catch HTTP.HTTPError.rateLimited(let delay) {
            return .rateLimited(until: Date().addingTimeInterval(delay))
        } catch HTTP.HTTPError.transport {
            return .error("Could not reach api.anthropic.com.")
        } catch {
            return .error("Claude usage unavailable.")
        }
    }

    private static func parse(_ json: JSONMap) -> ProviderStatus {
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
            percentUsed: UsageMath.percent(fromRaw: raw),
            unlimited: false
        )
    }

    /// Keychain first (macOS Claude Code), then ~/.claude/.credentials.json.
    /// Does not refresh OAuth itself — refreshing would rotate Claude Code's token.
    private static func loadAccessToken() -> String? {
        let blobs: [Data] = {
            var out: [Data] = []
            if let d = Secrets.keychainPassword(service: keychainService) { out.append(d) }
            if let d = Secrets.keychainPassword(service: keychainServiceAlt) { out.append(d) }
            let file = Secrets.home.appendingPathComponent(".claude/.credentials.json")
            if let d = Secrets.readFile(file) { out.append(d) }
            return out
        }()
        for data in blobs {
            if let token = token(from: data) { return token }
        }
        return nil
    }

    private static func token(from data: Data) -> String? {
        let raw = data
        let text = String(data: raw, encoding: .utf8) ?? ""
        let jsonData = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) else { return nil }
        let root = JSONMap(obj)
        let oauth = root?.map("claudeAiOauth", "claude_ai_oauth") ?? root
        guard let access = oauth?.string("accessToken", "access_token") else { return nil }
        return access
    }
}
