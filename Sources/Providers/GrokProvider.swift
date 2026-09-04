import Foundation

enum GrokProvider {
    static let billingURL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
    static let billingURLAlt = "https://cli-chat-proxy.grok.com/billing?format=credits"

    static func fetch() async -> ProviderStatus {
        do {
            guard let token = await Task.detached(priority: .utility, operation: { loadToken() }).value else {
                return .missingAuth(hint: ProviderID.grok.missingHint)
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

    private static func parse(_ json: JSONMap) -> ProviderStatus {
        let config = json.map("config") ?? json
        let grokBuild = productPercent(config, named: "GrokBuild")
        let unified = config.double("creditUsagePercent", "credit_usage_percent")
        let percent = grokBuild ?? unified
        let period = config.map("currentPeriod", "current_period")
        let end = DateParse.date(from: period?.any("end"))
            ?? DateParse.date(from: config.any("billingPeriodEnd", "billing_period_end"))
        let periodType = period?.string("type", "periodType") ?? ""
        let title: String = {
            if grokBuild != nil { return "Grok Build" }
            if periodType.uppercased().contains("WEEK") { return "Weekly" }
            if periodType.uppercased().contains("MONTH") { return "Monthly" }
            return "Weekly"
        }()
        let row = UsageRow(
            title: title,
            resetsAt: end,
            percentUsed: percent.map { UsageMath.percent(fromRaw: $0) },
            unlimited: false
        )
        if percent == nil && end == nil {
            return .error("Grok billing response had no creditUsagePercent or period end.")
        }
        return .ok(UsageSnapshot(
            ringPercent: row.percentUsed,
            ringUnlimited: false,
            rows: [row],
            detail: nil
        ))
    }

    private static func productPercent(_ config: JSONMap, named name: String) -> Double? {
        guard let products = config.array("productUsage", "product_usage") else { return nil }
        for item in products {
            guard let map = JSONMap(item) else { continue }
            let product = map.string("product") ?? ""
            guard product.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else {
                continue
            }
            if let value = map.double("usagePercent", "usage_percent") {
                return value
            }
        }
        return nil
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
