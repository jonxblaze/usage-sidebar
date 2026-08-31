import Foundation
import SwiftUI

enum ProviderID: String, CaseIterable, Identifiable {
    case claude
    case grok
    case antigravity
    case copilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .grok: return "Grok Build"
        case .antigravity: return "Antigravity"
        case .copilot: return "Copilot"
        }
    }

    var usageTitle: String { "\(displayName) Usage" }

    var brand: Color {
        switch self {
        case .claude: return Color(red: 0.98, green: 0.38, blue: 0.16)
        case .grok: return Color(red: 0.13, green: 0.88, blue: 0.54)
        case .antigravity: return Color(red: 0.84, green: 0.94, blue: 0.12)
        case .copilot: return Color(red: 0.25, green: 0.62, blue: 1.0)
        }
    }

    var missingHint: String {
        switch self {
        case .claude:
            return "Open Claude Code and sign in (claude /login). If macOS asks, click Always Allow for “Claude Code-credentials”."
        case .grok:
            return "Open Grok Build and run grok login so ~/.grok/auth.json exists."
        case .antigravity:
            return "Open the Antigravity app (or run agy) and sign in with Google."
        case .copilot:
            return "Run gh auth login, then this sidebar can read Copilot quota."
        }
    }
}

/// One horizontal row in a provider popover. Percent is omitted when unknown —
/// never filled in with a made-up 0.
struct UsageRow: Equatable {
    var title: String
    var resetsAt: Date?
    var percentUsed: Double?
    var unlimited: Bool
}

struct UsageSnapshot: Equatable {
    /// Ring value. `nil` means draw an empty ring and show "—".
    var ringPercent: Double?
    var ringUnlimited: Bool
    var rows: [UsageRow]
    var detail: String?
}

enum ProviderStatus: Equatable {
    case loading
    case missingAuth(hint: String)
    case ok(UsageSnapshot)
    case error(String)
    case rateLimited(until: Date)

    /// Value drawn under the ring. Never a fabricated live number.
    var ringCaption: String {
        switch self {
        case .ok(let snap) where snap.ringUnlimited:
            return "∞"
        case .ok(let snap):
            if let pct = snap.ringPercent {
                return "\(Int(pct.rounded()))%"
            }
            return "—"
        default:
            return "—"
        }
    }

    var ringProgress: Double? {
        switch self {
        case .ok(let snap) where snap.ringUnlimited:
            return 0
        case .ok(let snap):
            guard let pct = snap.ringPercent else { return nil }
            return min(max(pct / 100.0, 0), 1)
        default:
            return nil
        }
    }
}

enum UsageMath {
    /// Map a JSON utilization that may be either 0...1 or 0...100.
    static func percent(fromRaw raw: Double) -> Double {
        if raw < 0 { return 0 }
        if raw <= 1.0 { return raw * 100.0 }
        return min(raw, 999)
    }

    static func usedFromRemainingFraction(_ remaining: Double) -> Double {
        let r = min(max(remaining, 0), 1)
        return (1.0 - r) * 100.0
    }

    static func usedFromRemainingPercent(_ remaining: Double) -> Double {
        min(max(100.0 - remaining, 0), 100)
    }
}

enum ResetFormat {
    static func phrase(until date: Date, now: Date = Date()) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "Resetting…" }
        if remaining < 3600 {
            let minutes = max(Int((remaining / 60).rounded(.up)), 1)
            return "Resets in \(minutes) min"
        }
        if remaining < 86_400 {
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes == 0 { return "Resets in \(hours)h" }
            return "Resets in \(hours)h \(minutes)m"
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE h:mm a"
        return "Resets \(formatter.string(from: date))"
    }
}

enum DateParse {
    static func date(from value: Any?) -> Date? {
        if let n = value as? NSNumber {
            let v = n.doubleValue
            if v > 1_000_000_000_000 { return Date(timeIntervalSince1970: v / 1000) }
            if v > 1_000_000_000 { return Date(timeIntervalSince1970: v) }
            return nil
        }
        if let i = value as? Int {
            return date(from: NSNumber(value: i))
        }
        if let d = value as? Double {
            return date(from: NSNumber(value: d))
        }
        guard let s = value as? String, !s.isEmpty else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = isoFractional.date(from: trimmed) { return d }
        if let d = iso.date(from: trimmed) { return d }
        if let d = isoNoZ.date(from: trimmed) { return d }
        if let d = day.date(from: String(trimmed.prefix(10))) { return d }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoNoZ: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

enum BarTone {
    static func color(forPercent percent: Double) -> Color {
        if percent < 50 { return Color(red: 0.30, green: 0.82, blue: 0.45) }
        if percent < 80 { return Color(red: 0.95, green: 0.62, blue: 0.20) }
        return Color(red: 0.93, green: 0.32, blue: 0.28)
    }
}
