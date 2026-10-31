import AppKit
import SwiftUI

/// A real window, not a popover: a transient popover closes the moment you
/// switch apps to copy an API key, and would take the half-filled form with it.
@MainActor
final class ProvidersWindow {
    static let shared = ProvidersWindow()
    private var window: NSWindow?

    func show(store: UsageStore) {
        let window = self.window ?? makeWindow(store: store)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(store: UsageStore) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Providers"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProvidersView(store: store))
        window.center()
        return window
    }
}

@MainActor
final class AddProviderForm: ObservableObject {
    @Published var name = ""
    @Published var color = ProviderColor.purple
    @Published var usageURL = ""
    @Published var apiKey = ""
    @Published var percentPath = ""
    @Published var resetPath = ""
    @Published var testing = false
    @Published var testSummary: String?
    @Published var testReply: String?
    @Published var saveError: String?

    /// nil until every required field is usable.
    var provider: CustomProvider? {
        let name = trimmed(self.name)
        let percentPath = trimmed(self.percentPath)
        let resetPath = trimmed(self.resetPath)
        guard !name.isEmpty, !percentPath.isEmpty, !key.isEmpty, keyIsHeaderSafe,
              CustomProvider.isValidUsageURL(usageURL) else { return nil }
        return CustomProvider(
            name: name,
            color: color,
            usageURL: trimmed(usageURL),
            percentPath: percentPath,
            resetPath: resetPath.isEmpty ? nil : resetPath
        )
    }

    var key: String { trimmed(apiKey) }

    /// The key goes in a header, so printable ASCII with no spaces only.
    private var keyIsHeaderSafe: Bool {
        key.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }

    func test() async {
        guard let provider else { return }
        testing = true
        testSummary = nil
        testReply = nil
        let probe = await CustomProviderClient.probe(provider, apiKey: key)
        testing = false
        testSummary = summary(probe.status)
        testReply = probe.reply
    }

    func clearTest() {
        testSummary = nil
        testReply = nil
    }

    func clear() {
        name = ""
        usageURL = ""
        apiKey = ""
        percentPath = ""
        resetPath = ""
        saveError = nil
        clearTest()
    }

    private func summary(_ status: ProviderStatus) -> String {
        switch status {
        case .ok: return "Works: \(status.ringCaption) used."
        case .missingAuth(let hint): return hint
        case .error(let message): return message
        case .rateLimited: return "Rate limited. Try again in a minute."
        case .loading: return ""
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ProvidersView: View {
    @ObservedObject var store: UsageStore
    @StateObject private var form = AddProviderForm()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                currentList
                if !store.removedBuiltIns.isEmpty {
                    builtInList
                }
                Divider()
                addForm
            }
            .padding(20)
        }
        .frame(width: 440, height: 620)
        .preferredColorScheme(.dark)
    }

    private var currentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("In your sidebar")
            if store.providers.isEmpty {
                Text("Nothing yet. Add a provider below.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(store.providers) { entry in
                HStack(spacing: 10) {
                    badge(entry)
                    Text(entry.displayName)
                        .font(.system(size: 13))
                    Spacer()
                    Button("Remove") { store.remove(entry) }
                }
            }
        }
    }

    private var builtInList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Built-in")
            ForEach(store.removedBuiltIns) { provider in
                HStack(spacing: 10) {
                    badge(.builtIn(provider))
                    Text(provider.displayName)
                        .font(.system(size: 13))
                    Spacer()
                    Button("Add") { store.add(.builtIn(provider)) }
                        .disabled(!store.canAddProvider)
                }
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Add a custom provider")
            Text("Needs a URL that returns your usage as JSON. The API key is sent as a Bearer token to this URL only, and is stored in your Keychain.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Name", text: $form.name)
            HStack(spacing: 8) {
                ForEach(ProviderColor.allCases) { color in
                    Button {
                        form.color = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle().stroke(Color.white, lineWidth: form.color == color ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Usage URL (https://…)", text: $form.usageURL)
            SecureField("API key", text: $form.apiKey)
            TextField("Field with percent used, 0 to 100 (data.percent_used)", text: $form.percentPath)
            TextField("Field with reset date (optional)", text: $form.resetPath)

            HStack {
                Button(form.testing ? "Testing…" : "Test") {
                    Task { await form.test() }
                }
                .disabled(form.provider == nil || form.testing)
                Button("Add Provider") {
                    Task { await save() }
                }
                    .disabled(form.provider == nil || !store.canAddProvider)
                Spacer()
            }

            if !store.canAddProvider {
                note("The sidebar is full at \(UsageStore.maxProviders) providers.")
            }
            if let error = form.saveError {
                note(error)
            }
            if let summary = form.testSummary {
                note(summary)
            }
            if let reply = form.testReply {
                Text(reply)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12))
        .onChange(of: [form.usageURL, form.apiKey, form.percentPath, form.resetPath]) {
            form.clearTest()
        }
    }

    private func save() async {
        guard let provider = form.provider else { return }
        if await store.addCustom(provider, apiKey: form.key) {
            form.clear()
        } else {
            form.saveError = "Could not save the API key to the Keychain."
        }
    }

    private func badge(_ entry: ProviderEntry) -> some View {
        ZStack {
            Circle().fill(entry.brand.opacity(0.25))
            ProviderMark(entry: entry)
                .scaleEffect(0.8)
        }
        .frame(width: 26, height: 26)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
    }
}
