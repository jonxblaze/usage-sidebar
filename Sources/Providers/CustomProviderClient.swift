import Foundation

/// Reads usage from a URL the user configured. Fields come from the dotted
/// paths they gave. Anything missing is an error, never a made-up 0.
enum CustomProviderClient {
    struct Probe {
        var status: ProviderStatus
        /// The reply with the key removed, so a test can show which fields exist.
        var reply: String?
    }

    static func fetch(_ provider: CustomProvider) async -> ProviderStatus {
        let key = await Task.detached(priority: .utility) {
            Secrets.loadAPIKey(id: provider.id)
        }.value
        guard let key else {
            return .missingAuth(hint: "No API key saved. Remove \(provider.name) and add it again.")
        }
        return await probe(provider, apiKey: key, keepReply: false).status
    }

    static func probe(_ provider: CustomProvider, apiKey: String, keepReply: Bool = true) async -> Probe {
        // The saved list comes from UserDefaults, so the form's check is not enough.
        guard CustomProvider.isValidUsageURL(provider.usageURL) else {
            return Probe(status: .error("\(provider.name) needs an https usage URL."), reply: nil)
        }
        do {
            let response = try await HTTP.request(
                url: provider.usageURL,
                headers: ["Authorization": "Bearer \(apiKey)", "Accept": "application/json"],
                followRedirects: false
            )
            let reply = keepReply ? cleanReply(response.body, apiKey: apiKey) : nil
            if response.status == 401 || response.status == 403 {
                return Probe(status: .missingAuth(hint: "\(provider.name) rejected the API key."), reply: reply)
            }
            guard (200..<300).contains(response.status) else {
                return Probe(status: .error("\(provider.name) usage request failed (\(response.status))."), reply: reply)
            }
            return Probe(status: parse(response.json, provider: provider), reply: reply)
        } catch HTTP.HTTPError.rateLimited(let delay) {
            return Probe(status: .rateLimited(until: Date().addingTimeInterval(delay)), reply: nil)
        } catch HTTP.HTTPError.transport {
            return Probe(status: .error("Could not reach \(URL(string: provider.usageURL)?.host ?? provider.usageURL)."), reply: nil)
        } catch HTTP.HTTPError.tooLarge {
            return Probe(status: .error("\(provider.name) reply is over 1 MB."), reply: nil)
        } catch {
            return Probe(status: .error("\(provider.name) usage unavailable."), reply: nil)
        }
    }

    static func parse(_ json: Any?, provider: CustomProvider) -> ProviderStatus {
        // The string "nan" parses as a Double, and Int(.nan) traps in ringCaption.
        guard let raw = JSONMap.number(value(at: provider.percentPath, in: json)), raw.isFinite else {
            return .error("No number at \(provider.percentPath) in the \(provider.name) reply.")
        }
        let percent = UsageMath.clampedPercent(raw)
        let resets = provider.resetPath.flatMap { DateParse.date(from: value(at: $0, in: json)) }
        return .ok(UsageSnapshot(
            ringPercent: percent,
            ringUnlimited: false,
            rows: [UsageRow(title: "Usage", resetsAt: resets, percentUsed: percent, unlimited: false)],
            detail: nil
        ))
    }

    /// Walks `data.plans.0.used`. Number segments index into arrays.
    static func value(at path: String, in json: Any?) -> Any? {
        var current = json
        for part in path.split(separator: ".").map(String.init) {
            if let object = current as? [String: Any] {
                current = object[part]
            } else if let array = current as? [Any], let index = Int(part), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return path.isEmpty ? nil : current
    }

    private static func cleanReply(_ body: Data, apiKey: String) -> String? {
        guard let text = String(data: body, encoding: .utf8), !text.isEmpty else { return nil }
        let clean = Secrets.redact(text.replacingOccurrences(of: apiKey, with: "[redacted]"))
        return String(clean.prefix(2000))
    }
}
