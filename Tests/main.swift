import Foundation

// Run with: bash scripts/test.sh
var failures = 0

func check(_ name: String, _ passed: Bool) {
    print(passed ? "PASS" : "FAIL", name)
    if !passed { failures += 1 }
}

func bucket(_ id: String, _ remaining: Double) -> [String: Any] {
    ["bucketId": id, "remainingFraction": remaining]
}

func group(_ name: String, _ buckets: [[String: Any]]) -> [String: Any] {
    ["displayName": name, "buckets": buckets]
}

func snapshot(_ groups: [[String: Any]]) -> UsageSnapshot? {
    guard let json = JSONMap(["groups": groups]),
          case .ok(let snap)? = AntigravityProvider.parseSummary(json) else { return nil }
    return snap
}

// Shape of a live RetrieveUserQuotaSummary reply from 2026-10-31.
let live = snapshot([
    group("Gemini Models", [bucket("gemini-weekly", 0.75), bucket("gemini-5h", 0.99)]),
    group("Claude and GPT models", [bucket("3p-weekly", 1), bucket("3p-5h", 1)]),
    group("Gemini 4 Argon", [bucket("gemini-argon-wtu-weekly", 0)]),
])
check("ring is plan weekly, not the exhausted model", live?.ringPercent == 25)
check("exhausted model keeps its row", live?.rows.last?.percentUsed == 100)
check("exhausted model is named", live?.rows.last?.title == "Gemini 4 Argon Weekly")
check("plan rows have short names", live?.rows.first?.title == "Weekly" && live?.rows[1].title == "Current session")
check("other groups keep their prefix", live?.rows[2].title == "Claude and GPT models Weekly")

let noPlanWeekly = snapshot([
    group("Claude and GPT models", [bucket("3p-weekly", 0.5), bucket("3p-5h", 0.2)]),
])
check("without plan weekly, ring is the highest bucket", noPlanWeekly?.ringPercent == 80)

exit(failures == 0 ? 0 : 1)
