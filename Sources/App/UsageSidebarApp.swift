import AppKit
import Combine
import SwiftUI

@main
struct UsageSidebarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var panel: NSPanel?
    private var host: NSHostingView<SidebarRoot>?
    private var expandedSink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
        installPanel()
        reposition()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )

        expandedSink = store.$expanded
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.animateResize()
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    private func installPanel() {
        let root = SidebarRoot(store: store)
        let view = NSHostingView(rootView: root)
        view.sizingOptions = [.intrinsicContentSize]
        var size = view.fittingSize
        if size.width < 8 || size.height < 20 {
            size = NSSize(width: 18, height: 54)
        }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = view
        panel.orderFrontRegardless()
        self.host = view
        self.panel = panel
    }

    // MARK: - Layout

    private func animateResize() {
        guard let panel, let host else { return }
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let origin = computeOrigin(panelSize: size)
        let target = NSRect(origin: origin, size: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }
        panel.invalidateShadow()
    }

    @objc func reposition() {
        guard let panel else { return }
        let size = panel.frame.size
        let origin = computeOrigin(panelSize: size)
        panel.setFrameOrigin(origin)
        panel.invalidateShadow()
    }

    private func computeOrigin(panelSize size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return .zero }
        let visible = screen.visibleFrame
        let x = screen.frame.maxX - size.width
        let y = visible.minY + (visible.height - size.height) / 2
        return NSPoint(x: x, y: y)
    }
}
