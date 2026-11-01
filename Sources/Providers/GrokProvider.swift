import Foundation

enum GrokProvider {
    static let billingURL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
    static let billingURLAlt = "https://cli-chat-proxy.grok.com/billing?format=credits"

    static func fetch() async -> ProviderStatus {
        do {
            guard let token = await Task.detached(priority: .utility, operation: { loadToken() }).value else {
                return .notSignedIn(hint: BuiltInProvider.grok.missingHint)
            }
            var lastStatus = 0
            for url in [billingURL, billingURLAlt] {
                let response = try await HTTP.request(
                    url: url,
                    headers: [
                        "Authorization": "Bearer \(token)",
                        "Accept": "application/json",
                        "X-XAI-Token-Auth": "xai-grok-cli",
                        "x-grok-client-surface": "grok-build",
                        "x-grok-client-version": "1.0.0",
                    ]
                )
                lastStatus = response.status
                if response.status == 401 || response.status == 403 {
                    return .missingAuth(hint: "Grok Build sign-in expired. Run grok login.")
                }
                if (200..<300).contains(response.status), let json = JSONMap(response.json) {
                    return parse(json)
                }
                if response.status == 404 { continue }
                return .error("Grok billing request failed (\(response.status)).")
            }
            return .error("Grok billing request failed (\(lastStatus)).")
        } catch HTTP.HTTPError.rateLimited(let delay) {
            return .rateLimited(until: Date().addingTimeInterval(delay))
        } catch HTTP.HTTPError.transport {
            return .error("Could not reach cli-chat-proxy.grok.com.")
        } catch {
            return .error("Grok usage unavailable.")
        }
    }

    static func parse(_ json: JSONMap) -> ProviderStatus {
        let config = json.map("config") ?? json
        // Grok `/usage` is unified SuperGrok weekly credits, not the
        // GrokBuild-only product slice (those can differ by several points).
        let unified = config.double("creditUsagePercent", "credit_usage_percent")
        let period = config.map("currentPeriod", "current_period")
        let end = DateParse.date(from: period?.any("end"))
            ?? DateParse.date(from: config.any("billingPeriodEnd", "billing_period_end"))
        let periodType = period?.string("type", "periodType") ?? ""
        let isMonthly = periodType.uppercased().contains("MONTH")

        var rows: [UsageRow] = []
        if let unified {
            rows.append(UsageRow(
                title: isMonthly ? "Monthly" : "Weekly",
                resetsAt: end,
                percentUsed: UsageMath.clampedPercent(unified),
                unlimited: false
            ))
        }
        var build: Double?
        if let products = config.array("productUsage", "product_usage") {
            for item in products {
                guard let map = JSONMap(item),
                      let name = map.string("product"),
                      let raw = map.double("usagePercent", "usage_percent") else { continue }
                let percentUsed = UsageMath.clampedPercent(raw)
                if name.lowercased() == "grokbuild" { build = percentUsed }
                rows.append(UsageRow(
                    title: productTitle(name),
                    resetsAt: end,
                    percentUsed: percentUsed,
                    unlimited: false
                ))
            }
        }

        let ring = rows.first?.percentUsed
        if ring == nil && end == nil {
            return .error("Grok billing response had no creditUsagePercent or period end.")
        }
        // Grok has no session limit, so the inner ring is the Grok Build slice
        // of the weekly credits on the outer ring.
        let weekly = isMonthly ? nil : unified.map(UsageMath.clampedPercent)
        return .ok(UsageSnapshot(
            ringPercent: weekly == nil ? ring : build,
            ringUnlimited: false,
            rows: rows,
            detail: nil,
            weeklyPercent: weekly
        ))
    }

    private static func productTitle(_ name: String) -> String {
        switch name.lowercased() {
        case "grokbuild": return "Grok Build"
        case "grokchat": return "Grok Chat"
        case "groktasks": return "Grok Tasks"
        default: return name
        }
    }

    private static func loadToken() -> String? {
        let url = Secrets.home.appendingPathComponent(".grok/auth.json")
        guard let data = Secrets.readFile(url) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return token(from: obj)
    }

    private static func token(from obj: [String: Any]) -> String? {
        if let entry = obj["https://accounts.x.ai/sign-in"] as? [String: Any] {
            if let key = nonempty(entry["key"]) { return key }
            if let t = nonempty(entry["access_token"]) { return t }
        }
        for (k, v) in obj {
            guard k.contains("::"), let entry = v as? [String: Any] else { continue }
            if let key = nonempty(entry["key"]) { return key }
            if let t = nonempty(entry["access_token"]) { return t }
        }
        for value in obj.values {
            guard let entry = value as? [String: Any] else { continue }
            if let key = nonempty(entry["key"]), key.count > 10 { return key }
        }
        if let t = nonempty(obj["access_token"]) { return t }
        if let t = nonempty(obj["key"]) { return t }
        return nil
    }

    private static func nonempty(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
