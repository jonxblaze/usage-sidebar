import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var claude: ProviderStatus = .loading
    @Published var grok: ProviderStatus = .loading
    @Published var antigravity: ProviderStatus = .loading
    @Published var copilot: ProviderStatus = .loading
    @Published var expanded = false
    @Published var startsAtLogin: Bool
    @Published var loginMessage: String?

    private let previewMode: Bool
    private var tasks: [Task<Void, Never>] = []

    init(preview: Bool = false) {
        previewMode = preview
        startsAtLogin = LoginItem.isEnabled
    }

    func status(for id: ProviderID) -> ProviderStatus {
        switch id {
        case .claude: return claude
        case .grok: return grok
        case .antigravity: return antigravity
        case .copilot: return copilot
        }
    }

    func start() {
        guard !previewMode else { return }
        LoginItem.enableOnFirstLaunch()
        startsAtLogin = LoginItem.isEnabled
        for id in ProviderID.allCases {
            tasks.append(Task { [weak self] in
                await self?.poll(id)
            })
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func setStartsAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            startsAtLogin = LoginItem.isEnabled
            loginMessage = nil
        } catch {
            loginMessage = "Could not change login item. Move Usage Sidebar.app into /Applications and try again."
            startsAtLogin = LoginItem.isEnabled
        }
    }

    private func poll(_ id: ProviderID) async {
        var interval: TimeInterval = 60
        while !Task.isCancelled {
            let result = await fetch(id)
            apply(id, result)
            switch result {
            case .rateLimited(let until):
                let wait = max(until.timeIntervalSinceNow, 30)
                await sleep(wait)
            case .error, .missingAuth:
                interval = min(max(interval, 60) * 1.5, 300)
                await sleep(interval)
            default:
                interval = 60
                await sleep(60)
            }
        }
    }

    private func fetch(_ id: ProviderID) async -> ProviderStatus {
        switch id {
        case .claude: return await ClaudeProvider.fetch()
        case .grok: return await GrokProvider.fetch()
        case .antigravity: return await AntigravityProvider.fetch()
        case .copilot: return await CopilotProvider.fetch()
        }
    }

    private func apply(_ id: ProviderID, _ status: ProviderStatus) {
        switch id {
        case .claude: claude = status
        case .grok: grok = status
        case .antigravity: antigravity = status
        case .copilot: copilot = status
        }
    }

    private func sleep(_ seconds: TimeInterval) async {
        let ns = UInt64(max(seconds, 1) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
    }
}
