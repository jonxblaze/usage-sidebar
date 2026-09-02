import Foundation

enum CopilotProvider {
    static let userURL = "https://api.github.com/copilot_internal/user"

    static func fetch() async -> ProviderStatus {
        do {
            guard let token = await Task.detached(priority: .utility, operation: { loadToken() }).value else {
                return .missingAuth(hint: ProviderID.copilot.missingHint)
            }
            let response = try await HTTP.request(
                url: userURL,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/json",
                    "User-Agent": "GitHubCopilotChat/0.26.7",
                    "Editor-Version": "vscode/1.96.0",
                    "Editor-Plugin-Version": "copilot-chat/0.26.7",
                ]
            )
            if response.status == 401 || response.status == 403 {
                return .missingAuth(hint: "GitHub token is missing Copilot access. Run gh auth login.")
            }
            guard (200..<300).contains(response.status), let json = JSONMap(response.json) else {
                return .error("Copilot quota request failed (\(response.status)).")
            }
            return parse(json)
        } catch HTTP.HTTPError.rateLimited(let delay) {
            return .rateLimited(until: Date().addingTimeInterval(delay))
        } catch HTTP.HTTPError.transport {
            return .error("Could not reach api.github.com.")
        } catch {
            return .error("Copilot usage unavailable.")
        }
    }

    private static func parse(_ json: JSONMap) -> ProviderStatus {
        let reset = DateParse.date(from: json.any("quota_reset_date_utc", "quotaResetDateUtc", "quota_reset_date", "quotaResetDate"))
        let snapshots = JSONMap(json.any("quota_snapshots", "quotaSnapshots"))
        let order = ["premium_interactions", "chat", "completions"]
        var rows: [UsageRow] = []
        var ringPercent: Double?
        var ringUnlimited = false

        if let snapshots {
            for key in order {
                guard let snap = snapshots.map(key) else { continue }
                let title: String = {
                    switch key {
                    case "premium_interactions": return "Premium"
                    case "chat": return "Chat"
                    case "completions": return "Completions"
                    default: return key
                    }
                }()
                let unlimited = snap.bool("unlimited") ?? false
                var used: Double? = nil
                if !unlimited {
                    if let remaining = snap.double("percent_remaining", "percentRemaining") {
                        used = UsageMath.usedFromRemainingPercent(remaining)
                    } else if let remaining = snap.double("remaining", "quota_remaining", "quotaRemaining"),
                              let entitlement = snap.double("entitlement"), entitlement > 0 {
                        used = (1.0 - remaining / entitlement) * 100.0
                    }
                }
                rows.append(UsageRow(
                    title: title,
                    resetsAt: unlimited ? nil : reset,
                    percentUsed: unlimited ? nil : used,
                    unlimited: unlimited
                ))
            }
        }

        if let limited = rows.first(where: { !$0.unlimited }) {
            ringPercent = limited.percentUsed
            ringUnlimited = false
        } else if rows.contains(where: { $0.unlimited }) {
            ringUnlimited = true
            ringPercent = nil
        }

        guard !rows.isEmpty else {
            return .error("Copilot response had no quota_snapshots.")
        }
        return .ok(UsageSnapshot(
            ringPercent: ringPercent,
            ringUnlimited: ringUnlimited,
            rows: rows,
            detail: nil
        ))
    }

    /// `gh auth token`, then ~/.config/gh/hosts.yml, then Keychain gh:github.com.
    private static func loadToken() -> String? {
        if let fromFile = hostsYMLToken() { return fromFile }
        let extra = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            Secrets.home.appendingPathComponent(".local/bin").path,
        ]
        if let out = try? ProcessRun.capture(
            executable: "/usr/bin/env",
            arguments: ["gh", "auth", "token"],
            timeout: 5,
            extraPath: extra
        ) {
            let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !t.contains(" ") { return t }
        }
        if let data = Secrets.keychainPassword(service: "gh:github.com") {
            let t = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let t, !t.isEmpty { return t }
        }
        return nil
    }

    private static func hostsYMLToken() -> String? {
        let configDir = ProcessInfo.processInfo.environment["GH_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? Secrets.home.appendingPathComponent(".config/gh")
        for name in ["hosts.yml", "hosts.yaml"] {
            let url = configDir.appendingPathComponent(name)
            guard let data = Secrets.readFile(url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            if let token = yamlToken(from: text) { return token }
        }
        return nil
    }

    private static func yamlToken(from text: String) -> String? {
        var inGithub = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("github.com:") { inGithub = true; continue }
            if inGithub, !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.contains(":") && !line.hasPrefix("github.com") {
                inGithub = false
            }
            guard inGithub else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("oauth_token:") {
                var value = trimmed.dropFirst("oauth_token:".count)
                    .trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                if value.isEmpty || value == "null" || value == "~" || value == "keychain" { return nil }
                return value
            }
        }
        return nil
    }
}
