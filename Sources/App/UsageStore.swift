import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    /// Each ring is about 66pt tall, so more than this runs off a laptop screen.
    static let maxProviders = 10
    private static let providersKey = "providers"

    @Published private(set) var providers: [ProviderEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(providers) {
                UserDefaults.standard.set(data, forKey: Self.providersKey)
            }
        }
    }
    @Published private var statuses: [String: ProviderStatus] = [:]
    @Published var expanded: Bool
    @Published var autoHide: Bool {
        didSet {
            UserDefaults.standard.set(autoHide, forKey: "autoHide")
        }
    }
    @Published var startsAtLogin: Bool
    @Published var loginMessage: String?

    private let previewMode: Bool
    private var tasks: [String: Task<Void, Never>] = [:]

    init(preview: Bool = false) {
        previewMode = preview
        providers = Self.savedProviders()
        startsAtLogin = LoginItem.isEnabled
        let isAutoHide = UserDefaults.standard.object(forKey: "autoHide") != nil
            ? UserDefaults.standard.bool(forKey: "autoHide")
            : true
        autoHide = isAutoHide
        expanded = !isAutoHide
    }

    private static func savedProviders() -> [ProviderEntry] {
        guard let data = UserDefaults.standard.data(forKey: providersKey),
              let saved = try? JSONDecoder().decode([ProviderEntry].self, from: data) else {
            return ProviderEntry.defaults
        }
        return saved
    }

    func status(for entry: ProviderEntry) -> ProviderStatus {
        statuses[entry.id] ?? .loading
    }

    var canAddProvider: Bool { providers.count < Self.maxProviders }

    var removedBuiltIns: [BuiltInProvider] {
        BuiltInProvider.allCases.filter { !providers.contains(.builtIn($0)) }
    }

    func add(_ entry: ProviderEntry) {
        guard canAddProvider, !providers.contains(entry) else { return }
        providers.append(entry)
        startPolling(entry)
    }

    /// Returns false, and adds nothing, if the Keychain refused the key.
    func addCustom(_ provider: CustomProvider, apiKey: String) async -> Bool {
        guard canAddProvider else { return false }
        let saved = await Task.detached(priority: .userInitiated) {
            Secrets.saveAPIKey(apiKey, id: provider.id)
        }.value
        guard saved else { return false }
        add(.custom(provider))
        return true
    }

    func remove(_ entry: ProviderEntry) {
        tasks.removeValue(forKey: entry.id)?.cancel()
        statuses[entry.id] = nil
        providers.removeAll { $0.id == entry.id }
        if case .custom(let provider) = entry {
            Task.detached(priority: .utility) {
                Secrets.deleteAPIKey(id: provider.id)
            }
        }
    }

    func start() {
        guard !previewMode else { return }
        LoginItem.enableOnFirstLaunch()
        startsAtLogin = LoginItem.isEnabled
        providers.forEach(startPolling)
    }

    func stop() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func startPolling(_ entry: ProviderEntry) {
        guard !previewMode else { return }
        tasks[entry.id] = Task { [weak self] in
            await self?.poll(entry)
        }
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

    private func poll(_ entry: ProviderEntry) async {
        var interval: TimeInterval = 60
        while !Task.isCancelled {
            let result = await fetch(entry)
            guard !Task.isCancelled else { return }
            apply(entry.id, result)
            switch result {
            case .rateLimited(let until):
                let wait = max(until.timeIntervalSinceNow, 30)
                await sleep(wait)
            case .missingAuth:
                // Credentials can appear the moment Claude/Grok refresh a token.
                // Do not stretch this out to 5 minutes.
                interval = 60
                await sleep(60)
            case .error:
                interval = min(max(interval, 60) * 1.5, 300)
                await sleep(interval)
            default:
                interval = 60
                await sleep(60)
            }
        }
    }

    private func fetch(_ entry: ProviderEntry) async -> ProviderStatus {
        switch entry {
        case .builtIn(.claude): return await ClaudeProvider.fetch()
        case .builtIn(.grok): return await GrokProvider.fetch()
        case .builtIn(.antigravity): return await AntigravityProvider.fetch()
        case .builtIn(.copilot): return await CopilotProvider.fetch()
        case .custom(let provider): return await CustomProviderClient.fetch(provider)
        }
    }

    func apply(_ id: String, _ status: ProviderStatus) {
        statuses[id] = status
    }

    private func sleep(_ seconds: TimeInterval) async {
        // A server picks `seconds` on the rate-limit path. Out of range traps here.
        let bounded = seconds.isFinite ? min(max(seconds, 1), 3600) : 3600
        let ns = UInt64(bounded * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
    }
}
