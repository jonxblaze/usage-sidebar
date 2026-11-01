import AppKit
import SwiftUI

struct SidebarRoot: View {
    @ObservedObject var store: UsageStore
    // Stored State, not @State. @State is a SwiftUIMacros macro, and Command
    // Line Tools do not ship that plugin. This is the same storage the
    // property wrapper used to synthesize.
    private var settingsOpen: Bool {
        get { _settingsOpen.wrappedValue }
        nonmutating set { _settingsOpen.wrappedValue = newValue }
    }
    private var _settingsOpen = State(wrappedValue: false)
    private var activePopoverID: String? {
        get { _activePopoverID.wrappedValue }
        nonmutating set { _activePopoverID.wrappedValue = newValue }
    }
    private var _activePopoverID = State<String?>(wrappedValue: nil)
    private var pinnedPopoverID: String? {
        get { _pinnedPopoverID.wrappedValue }
        nonmutating set { _pinnedPopoverID.wrappedValue = newValue }
    }
    private var _pinnedPopoverID = State<String?>(wrappedValue: nil)
    private var gearHovered: Bool {
        get { _gearHovered.wrappedValue }
        nonmutating set { _gearHovered.wrappedValue = newValue }
    }
    private var _gearHovered = State(wrappedValue: false)
    private var pinHovered: Bool {
        get { _pinHovered.wrappedValue }
        nonmutating set { _pinHovered.wrappedValue = newValue }
    }
    private var _pinHovered = State(wrappedValue: false)
    private var collapseHovered: Bool {
        get { _collapseHovered.wrappedValue }
        nonmutating set { _collapseHovered.wrappedValue = newValue }
    }
    private var _collapseHovered = State(wrappedValue: false)
    private var tabHovered: Bool {
        get { _tabHovered.wrappedValue }
        nonmutating set { _tabHovered.wrappedValue = newValue }
    }
    private var _tabHovered = State(wrappedValue: false)
    private var isMouseInsideSidebar: Bool {
        get { _isMouseInsideSidebar.wrappedValue }
        nonmutating set { _isMouseInsideSidebar.wrappedValue = newValue }
    }
    private var _isMouseInsideSidebar = State(wrappedValue: false)
    private var exitTimerTask: Task<Void, Never>? {
        get { _exitTimerTask.wrappedValue }
        nonmutating set { _exitTimerTask.wrappedValue = newValue }
    }
    private var _exitTimerTask = State<Task<Void, Never>?>(wrappedValue: nil)

    private var hasActivePopover: Bool {
        settingsOpen || activePopoverID != nil
    }

    var body: some View {
        Group {
            if store.expanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.expanded)
        .onChange(of: store.visibleProviders) { _, providers in
            // A removed ring takes its popover with it. A stale ID here would
            // read as an open popover and block auto-hide.
            if let active = activePopoverID, !providers.contains(where: { $0.id == active }) {
                activePopoverID = nil
                pinnedPopoverID = nil
            }
        }
    }

    private var expandedBody: some View {
        VStack(spacing: 11) {
            // Providers vertical list
            ForEach(store.visibleProviders) { entry in
                RingCell(
                    entry: entry,
                    status: store.status(for: entry),
                    activePopoverID: _activePopoverID.projectedValue,
                    pinnedPopoverID: _pinnedPopoverID.projectedValue
                )
            }

            if store.visibleProviders.isEmpty && !store.isSearching {
                Text("None found")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(width: 38)
            }

            // Divider line
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 24, height: 1)
                .padding(.vertical, 1)

            // Settings & Pin toolbar. Side by side, these are wider than the rings.
            VStack(spacing: 6) {
                // Pin button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                        store.autoHide.toggle()
                        if !store.autoHide {
                            store.expanded = true
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(white: pinHovered || !store.autoHide ? 0.18 : 0.12))
                        Circle()
                            .stroke(
                                !store.autoHide
                                    ? Color(red: 0.25, green: 0.62, blue: 1.0).opacity(0.60)
                                    : Color.white.opacity(pinHovered ? 0.20 : 0.10),
                                lineWidth: 0.75
                            )
                        Image(systemName: !store.autoHide ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(
                                !store.autoHide
                                    ? Color(red: 0.25, green: 0.62, blue: 1.0)
                                    : Color.white.opacity(pinHovered ? 0.95 : 0.65)
                            )
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { pinHovered = $0 }
                .help(!store.autoHide ? "Sidebar is pinned open" : "Pin sidebar (prevent auto-hide)")

                // Settings gear button
                Button {
                    settingsOpen.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(white: gearHovered || settingsOpen ? 0.18 : 0.12))
                        Circle()
                            .stroke(Color.white.opacity(gearHovered || settingsOpen ? 0.20 : 0.10), lineWidth: 0.75)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(gearHovered || settingsOpen ? 0.95 : 0.75))
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { gearHovered = $0 }
                .popover(isPresented: _settingsOpen.projectedValue, arrowEdge: .leading) {
                    SettingsPopover(store: store)
                }
                .help("Settings")
            }

            // Hide / Collapse handle
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    store.expanded = false
                }
            } label: {
                Capsule()
                    .fill(Color.white.opacity(collapseHovered ? 0.50 : 0.22))
                    .frame(width: 18, height: 3.5)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { collapseHovered = $0 }
            .help("Hide sidebar (collapse to tab)")
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(width: 52)
        .background {
            SidebarBackground()
        }
        .onHover { hovering in
            isMouseInsideSidebar = hovering
            if hovering {
                exitTimerTask?.cancel()
                exitTimerTask = nil
            } else {
                handleMouseExit()
            }
        }
    }

    private var collapsedBody: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.expanded = true
            }
        } label: {
            ZStack {
                EdgeScoopShape(cornerRadius: 10)
                    .fill(EdgeScoopShape.fill)
                    .overlay {
                        EdgeScoopShape(cornerRadius: 10, isOutline: true)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(tabHovered ? 0.35 : 0.16),
                                        Color.white.opacity(tabHovered ? 0.16 : 0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomLeading
                                ),
                                lineWidth: 1
                            )
                    }

                Image(systemName: "chevron.left")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(tabHovered ? 1.0 : 0.75))
                    .offset(x: tabHovered ? -2 : -0.5)
                    .animation(.easeInOut(duration: 0.18), value: tabHovered)
            }
            .frame(width: 18, height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            tabHovered = hovering
            if hovering && store.autoHide && !store.expanded {
                exitTimerTask?.cancel()
                exitTimerTask = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.expanded = true
                }
            }
        }
        .help("Show Usage Sidebar")
    }

    private func handleMouseExit() {
        guard store.autoHide else { return }
        exitTimerTask?.cancel()
        exitTimerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            if !isMouseInsideSidebar && !hasActivePopover {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.expanded = false
                }
            }
        }
    }
}

// MARK: - Ring Cell (Vertical Layout: Ring on Top, Percentage Below)

struct RingCell: View {
    let entry: ProviderEntry
    let status: ProviderStatus
    @Binding var activePopoverID: String?
    /// The cell a click is holding open. Hover-opened popovers close on exit.
    @Binding var pinnedPopoverID: String?
    private var id: String { entry.id }
    private var hover: Bool {
        get { _hover.wrappedValue }
        nonmutating set { _hover.wrappedValue = newValue }
    }
    private var _hover = State(wrappedValue: false)
    private var hoverTask: Task<Void, Never>? {
        get { _hoverTask.wrappedValue }
        nonmutating set { _hoverTask.wrappedValue = newValue }
    }
    private var _hoverTask = State<Task<Void, Never>?>(wrappedValue: nil)

    private var isOpen: Binding<Bool> {
        Binding(
            get: { activePopoverID == id },
            set: { isPresented in
                if isPresented {
                    activePopoverID = id
                } else if activePopoverID == id {
                    activePopoverID = nil
                    pinnedPopoverID = nil
                }
            }
        )
    }

    /// Delay both ways so passing over a ring does not flash its popover.
    private func handleHover(_ hovering: Bool) {
        hover = hovering
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            if hovering {
                if pinnedPopoverID != id { pinnedPopoverID = nil }
                activePopoverID = id
            } else if activePopoverID == id, pinnedPopoverID != id {
                activePopoverID = nil
            }
        }
    }

    var body: some View {
        Button {
            hoverTask?.cancel()
            if pinnedPopoverID == id {
                pinnedPopoverID = nil
                activePopoverID = nil
            } else {
                pinnedPopoverID = id
                activePopoverID = id
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    // Dark circular inner plate
                    Circle()
                        .fill(Color(white: 0.12))
                        .padding(5.5)

                    // Session usage
                    RingTrack(
                        progress: status.ringProgress,
                        fill: entry.brand,
                        inset: 5,
                        lineWidth: 2.8,
                        lineCap: .round
                    )

                    // Weekly usage. A round cap would show the gradient's red
                    // end behind 12 o'clock.
                    if let weekly = status.weeklyProgress {
                        RingTrack(
                            progress: weekly,
                            fill: BarTone.ring,
                            inset: 1.1,
                            lineWidth: 2.2,
                            lineCap: .butt
                        )
                    }

                    // Provider logo mark
                    ProviderMark(entry: entry)
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                // Percentage caption directly below
                Text(status.ringCaption)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .scaleEffect(hover ? 1.06 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { handleHover($0) }
        .popover(isPresented: isOpen, arrowEdge: .leading) {
            UsagePopover(entry: entry, status: status)
        }
    }
}

// MARK: - Progress Ring Track

struct RingTrack<Fill: ShapeStyle>: View {
    var progress: Double?
    var fill: Fill
    var inset: CGFloat
    var lineWidth: CGFloat
    var lineCap: CGLineCap

    var body: some View {
        ZStack {
            // Inactive subtle track
            Circle()
                .inset(by: inset)
                .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)

            // Active progress arc
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: progress ?? 0)
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: progress)
        }
    }
}

// MARK: - Right-Edge Dock Shapes

/// Shape that runs off the right edge of the display, with rounded corners on the left.
struct EdgeScoopShape: Shape {
    static let fill = Color(red: 0.06, green: 0.06, blue: 0.07).opacity(0.96)

    var cornerRadius: CGFloat = 18
    /// Leaves the right side open and sits inside the frame, for a 1pt stroke.
    var isOutline = false

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = isOutline ? 0.5 : 0
        let top = inset
        let left = inset
        let bottom = rect.height - inset
        let r = min(cornerRadius, min(rect.width, rect.height / 2))

        var p = Path()
        p.move(to: CGPoint(x: rect.width, y: top))
        p.addLine(to: CGPoint(x: left + r, y: top))
        p.addArc(
            center: CGPoint(x: left + r, y: top + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(180),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        p.addArc(
            center: CGPoint(x: left + r, y: bottom - r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: rect.width, y: bottom))
        if !isOutline { p.closeSubpath() }
        return p
    }
}

/// Solid obsidian dark background with subtle border gradient.
struct SidebarBackground: View {
    var body: some View {
        EdgeScoopShape(cornerRadius: 18)
            .fill(EdgeScoopShape.fill)
            .overlay {
                EdgeScoopShape(cornerRadius: 18, isOutline: true)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomLeading
                        ),
                        lineWidth: 1
                    )
            }
    }
}

// MARK: - Provider Marks

struct ProviderMark: View {
    let entry: ProviderEntry

    var body: some View {
        switch entry {
        case .builtIn(.claude):
            ClaudeOfficialMark()
                .foregroundStyle(.white)
        case .builtIn(.grok):
            GrokOfficialMark()
                .foregroundStyle(.white)
        case .builtIn(.antigravity):
            AntigravityCrystalMark()
                .foregroundStyle(.white)
        case .builtIn(.copilot):
            CopilotOfficialMark()
                .foregroundStyle(.white)
        case .custom(let provider):
            Text(provider.initial)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// Official Anthropic Claude Logo (12-Arm Sunburst Asterisk).
struct ClaudeOfficialMark: View {
    private static let d = "m4.709 15.955 4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 0 1-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z"

    var body: some View {
        SVGPathShape(pathString: Self.d)
            .frame(width: 15, height: 15)
    }
}

/// Official Grok mark from grok.com/images/favicon.svg (the two filled
/// glyph paths; squircle chrome omitted so it sits in the circular badge).
struct GrokOfficialMark: View {
    private static let d = """
        M210.484 312.759L343.465 210.383C349.984 205.364 359.302 207.322 362.408 215.117C378.758 256.231 371.454 305.64 338.925 339.563C306.397 373.487 261.137 380.927 219.768 363.983L174.577 385.803C239.394 432.008 318.104 420.581 367.289 369.251C406.303 328.564 418.386 273.104 407.088 223.091L407.19 223.198C390.807 149.726 411.218 120.359 453.03 60.3072C454.02 58.8833 455.01 57.4595 456 56L400.978 113.382V113.204L210.45 312.794Z \
        M183.042 337.641C136.519 291.294 144.54 219.567 184.236 178.203C213.59 147.59 261.683 135.096 303.666 153.464L348.755 131.75C340.632 125.627 330.221 119.042 318.275 114.414C264.277 91.2407 199.63 102.774 155.735 148.516C113.513 192.549 100.236 260.254 123.036 318.027C140.069 361.206 112.148 391.748 84.0229 422.575C74.0561 433.503 64.0553 444.431 56 456L183.007 337.677Z
        """

    var body: some View {
        SVGPathShape(pathString: Self.d)
            .frame(width: 16, height: 16)
    }
}

/// Official GitHub Copilot Logo (Octicon Robot Visor Head with Eyes).
struct CopilotOfficialMark: View {
    private static let headD = "M23.922 16.992c-.861 1.495-5.859 5.023-11.922 5.023-6.063 0-11.061-3.528-11.922-5.023A.641.641 0 0 1 0 16.736v-2.869a.841.841 0 0 1 .053-.22c.372-.935 1.347-2.292 2.605-2.656.167-.429.414-1.055.644-1.517a10.195 10.195 0 0 1-.052-1.086c0-1.331.282-2.499 1.132-3.368.397-.406.89-.717 1.474-.952 1.399-1.136 3.392-2.093 6.122-2.093 2.731 0 4.767.957 6.166 2.093.584.235 1.077.546 1.474.952.85.869 1.132 2.037 1.132 3.368 0 .368-.014.733-.052 1.086.23.462.477 1.088.644 1.517 1.258.364 2.233 1.721 2.605 2.656a.832.832 0 0 1 .053.22v2.869a.641.641 0 0 1-.078.256ZM12.172 11h-.344a4.323 4.323 0 0 1-.355.508C10.703 12.455 9.555 13 7.965 13c-1.725 0-2.989-.359-3.782-1.259a2.005 2.005 0 0 1-.085-.104L4 11.741v6.585c1.435.779 4.514 2.179 8 2.179 3.486 0 6.565-1.4 8-2.179v-6.585l-.098-.104s-.033.045-.085.104c-.793.9-2.057 1.259-3.782 1.259-1.59 0-2.738-.545-3.508-1.492a4.323 4.323 0 0 1-.355-.508h-.016.016Zm.641-2.935c.136 1.057.403 1.913.878 2.497.442.544 1.134.938 2.344.938 1.573 0 2.292-.337 2.657-.751.384-.435.558-1.15.558-2.361 0-1.14-.243-1.847-.705-2.319-.477-.488-1.319-.862-2.824-1.025-1.487-.161-2.192.138-2.533.529-.269.307-.437.808-.438 1.578v.021c0 .265.021.562.063.893Zm-1.626 0c.042-.331.063-.628.063-.894v-.02c-.001-.77-.169-1.271-.438-1.578-.341-.391-1.046-.69-2.533-.529-1.505.163-2.347.537-2.824 1.025-.462.472-.705 1.179-.705 2.319 0 1.211.175 1.926.558 2.361.365.414 1.084.751 2.657.751 1.21 0 1.902-.394 2.344-.938.475-.584.742-1.44.878-2.497Z"
    private static let eyesD = "M14.5 14.25a1 1 0 0 1 1 1v2a1 1 0 0 1-2 0v-2a1 1 0 0 1 1-1Zm-5 0a1 1 0 0 1 1 1v2a1 1 0 0 1-2 0v-2a1 1 0 0 1 1-1Z"
    private static let d = headD + " " + eyesD

    var body: some View {
        SVGPathShape(pathString: Self.d)
            .frame(width: 16, height: 16)
    }
}

/// Official Antigravity / Gemini 4-Point Sparkle Mark.
struct AntigravityCrystalMark: View {
    private static let d = "M12 1.5 C12 7.298 7.298 12 1.5 12 C7.298 12 12 16.702 12 22.5 C12 16.702 16.702 12 22.5 12 C16.702 12 12 7.298 12 1.5 Z"

    var body: some View {
        SVGPathShape(pathString: Self.d)
            .frame(width: 16, height: 16)
    }
}

// MARK: - SVG Path Parser & Shape Engine

struct SVGPathShape: Shape {
    let pathString: String
    var viewBox: CGRect? = nil

    func path(in rect: CGRect) -> Path {
        let base = SVGPathEngine.parse(pathString)
        let bounds = viewBox ?? base.cgPath.boundingBox
        guard bounds.width > 0, bounds.height > 0 else { return base }

        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let scaledW = bounds.width * scale
        let scaledH = bounds.height * scale
        let dx = rect.midX - (scaledW / 2) - (bounds.minX * scale)
        let dy = rect.midY - (scaledH / 2) - (bounds.minY * scale)

        let transform = CGAffineTransform(translationX: dx, y: dy)
            .scaledBy(x: scale, y: scale)

        return base.applying(transform)
    }
}

enum SVGPathEngine {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var currentPoint: CGPoint = .zero
        var subpathStart: CGPoint = .zero
        var lastControlPoint: CGPoint? = nil

        let tokens = tokenize(d)
        var i = 0

        func nextNumber() -> CGFloat? {
            guard i < tokens.count else { return nil }
            let t = tokens[i]
            if let n = Double(t) {
                i += 1
                return CGFloat(n)
            }
            return nil
        }

        var currentCmd: Character = "M"

        while i < tokens.count {
            let token = tokens[i]
            if let first = token.first, token.count == 1, first.isLetter {
                currentCmd = first
                i += 1
            }

            switch currentCmd {
            case "M":
                guard let x = nextNumber(), let y = nextNumber() else { break }
                currentPoint = CGPoint(x: x, y: y)
                subpathStart = currentPoint
                path.move(to: currentPoint)
                lastControlPoint = nil
                currentCmd = "L"
            case "m":
                guard let dx = nextNumber(), let dy = nextNumber() else { break }
                currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                subpathStart = currentPoint
                path.move(to: currentPoint)
                lastControlPoint = nil
                currentCmd = "l"
            case "L":
                guard let x = nextNumber(), let y = nextNumber() else { break }
                currentPoint = CGPoint(x: x, y: y)
                path.addLine(to: currentPoint)
                lastControlPoint = nil
            case "l":
                guard let dx = nextNumber(), let dy = nextNumber() else { break }
                currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                path.addLine(to: currentPoint)
                lastControlPoint = nil
            case "H":
                guard let x = nextNumber() else { break }
                currentPoint = CGPoint(x: x, y: currentPoint.y)
                path.addLine(to: currentPoint)
                lastControlPoint = nil
            case "h":
                guard let dx = nextNumber() else { break }
                currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y)
                path.addLine(to: currentPoint)
                lastControlPoint = nil
            case "V":
                guard let y = nextNumber() else { break }
                currentPoint = CGPoint(x: currentPoint.x, y: y)
                path.addLine(to: currentPoint)
                lastControlPoint = nil
            case "v":
                guard let dy = nextNumber() else { break }
                currentPoint = CGPoint(x: currentPoint.x, y: currentPoint.y + dy)
                path.addLine(to: currentPoint)
                lastControlPoint = nil
            case "C":
                guard let x1 = nextNumber(), let y1 = nextNumber(),
                      let x2 = nextNumber(), let y2 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { break }
                let cp1 = CGPoint(x: x1, y: y1)
                let cp2 = CGPoint(x: x2, y: y2)
                let end = CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: cp1, control2: cp2)
                lastControlPoint = cp2
                currentPoint = end
            case "c":
                guard let dx1 = nextNumber(), let dy1 = nextNumber(),
                      let dx2 = nextNumber(), let dy2 = nextNumber(),
                      let dx = nextNumber(), let dy = nextNumber() else { break }
                let cp1 = CGPoint(x: currentPoint.x + dx1, y: currentPoint.y + dy1)
                let cp2 = CGPoint(x: currentPoint.x + dx2, y: currentPoint.y + dy2)
                let end = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                path.addCurve(to: end, control1: cp1, control2: cp2)
                lastControlPoint = cp2
                currentPoint = end
            case "S":
                guard let x2 = nextNumber(), let y2 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { break }
                let cp1: CGPoint
                if let last = lastControlPoint {
                    cp1 = CGPoint(x: 2 * currentPoint.x - last.x, y: 2 * currentPoint.y - last.y)
                } else {
                    cp1 = currentPoint
                }
                let cp2 = CGPoint(x: x2, y: y2)
                let end = CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: cp1, control2: cp2)
                lastControlPoint = cp2
                currentPoint = end
            case "s":
                guard let dx2 = nextNumber(), let dy2 = nextNumber(),
                      let dx = nextNumber(), let dy = nextNumber() else { break }
                let cp1: CGPoint
                if let last = lastControlPoint {
                    cp1 = CGPoint(x: 2 * currentPoint.x - last.x, y: 2 * currentPoint.y - last.y)
                } else {
                    cp1 = currentPoint
                }
                let cp2 = CGPoint(x: currentPoint.x + dx2, y: currentPoint.y + dy2)
                let end = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                path.addCurve(to: end, control1: cp1, control2: cp2)
                lastControlPoint = cp2
                currentPoint = end
            case "Q":
                guard let x1 = nextNumber(), let y1 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { break }
                let cp = CGPoint(x: x1, y: y1)
                let end = CGPoint(x: x, y: y)
                path.addQuadCurve(to: end, control: cp)
                lastControlPoint = cp
                currentPoint = end
            case "q":
                guard let dx1 = nextNumber(), let dy1 = nextNumber(),
                      let dx = nextNumber(), let dy = nextNumber() else { break }
                let cp = CGPoint(x: currentPoint.x + dx1, y: currentPoint.y + dy1)
                let end = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                path.addQuadCurve(to: end, control: cp)
                lastControlPoint = cp
                currentPoint = end
            case "A", "a":
                let isRel = (currentCmd == "a")
                guard let rx = nextNumber(), let ry = nextNumber(),
                      let xRotation = nextNumber(), let largeArcFlag = nextNumber(), let sweepFlag = nextNumber(),
                      let ex = nextNumber(), let ey = nextNumber() else { break }
                let end = isRel ? CGPoint(x: currentPoint.x + ex, y: currentPoint.y + ey) : CGPoint(x: ex, y: ey)
                if rx == 0 || ry == 0 || currentPoint == end {
                    path.addLine(to: end)
                } else {
                    let segments = arcSegments(
                        from: currentPoint, to: end, rx: rx, ry: ry,
                        xRotationDeg: xRotation, largeArc: largeArcFlag != 0, sweep: sweepFlag != 0
                    )
                    for seg in segments {
                        path.addCurve(to: seg.end, control1: seg.control1, control2: seg.control2)
                    }
                }
                currentPoint = end
                lastControlPoint = nil
            case "Z", "z":
                path.closeSubpath()
                currentPoint = subpathStart
                lastControlPoint = nil
            default:
                i += 1
            }
        }
        return path
    }

    /// Converts an SVG elliptical arc (endpoint parameterization) into cubic bezier
    /// segments, per the standard SVG 1.1 Appendix F.6 conversion.
    private static func arcSegments(
        from start: CGPoint,
        to end: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        xRotationDeg: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) -> [(control1: CGPoint, control2: CGPoint, end: CGPoint)] {
        var rx = abs(rx)
        var ry = abs(ry)
        let phi = xRotationDeg * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // Step 1: compute (x1', y1') — start point in the rotated ellipse frame.
        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Step 2: correct out-of-range radii.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        // Step 3: compute the ellipse center (cx', cy') then (cx, cy).
        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let co = den == 0 ? 0 : sign * sqrt(max(0, num / den))
        let cxp = co * (rx * y1p / ry)
        let cyp = co * (-ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        // Step 4: compute the start angle and sweep angle.
        func angleBetween(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = angleBetween(1, 0, ux, uy)
        var deltaTheta = angleBetween(ux, uy, vx, vy)
        if !sweep, deltaTheta > 0 {
            deltaTheta -= 2 * .pi
        } else if sweep, deltaTheta < 0 {
            deltaTheta += 2 * .pi
        }

        // Step 5: split into <= 90° segments and approximate each with a cubic bezier.
        let segCount = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let segAngle = deltaTheta / CGFloat(segCount)
        let alpha = 4.0 / 3.0 * tan(segAngle / 4)

        func transform(_ p: CGPoint) -> CGPoint {
            let x = rx * p.x
            let y = ry * p.y
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }

        var segments: [(control1: CGPoint, control2: CGPoint, end: CGPoint)] = []
        var angle1 = theta1
        for _ in 0..<segCount {
            let angle2 = angle1 + segAngle
            let p1 = CGPoint(x: cos(angle1), y: sin(angle1))
            let p2 = CGPoint(x: cos(angle2), y: sin(angle2))
            let q1 = CGPoint(x: p1.x - alpha * sin(angle1), y: p1.y + alpha * cos(angle1))
            let q2 = CGPoint(x: p2.x + alpha * sin(angle2), y: p2.y - alpha * cos(angle2))
            segments.append((transform(q1), transform(q2), transform(p2)))
            angle1 = angle2
        }
        return segments
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var cur = ""
        var prevCh: Character? = nil

        for ch in d {
            if ch.isLetter {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
                tokens.append(String(ch))
            } else if ch.isWhitespace || ch == "," {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
            } else if ch == "-" {
                if !cur.isEmpty && prevCh != "e" && prevCh != "E" {
                    tokens.append(cur)
                    cur = "-"
                } else {
                    cur.append(ch)
                }
            } else if ch == "." && cur.contains(".") {
                tokens.append(cur)
                cur = "."
            } else {
                cur.append(ch)
            }
            prevCh = ch
        }
        if !cur.isEmpty { tokens.append(cur) }
        return tokens
    }
}

// MARK: - Popovers

struct UsagePopover: View {
    let entry: ProviderEntry
    let status: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(16)
        .frame(width: 290, alignment: .leading)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(entry.brand.opacity(0.25))
                ProviderMark(entry: entry)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)

            Text(entry.usageTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .loading:
            Text("Waiting for a live reading…")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
        case .missingAuth(let hint), .notSignedIn(let hint):
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        case .error(let message):
            Text(Secrets.redact(message))
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        case .rateLimited(let until):
            Text("Rate limited. \(ResetFormat.phrase(until: until).replacingOccurrences(of: "Resets", with: "Retry"))")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.78))
        case .ok(let snap):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(snap.rows.enumerated()), id: \.offset) { _, row in
                    UsageRowView(row: row)
                }
                if let detail = snap.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
    }
}

struct SettingsPopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Toggle("Auto-Hide Sidebar", isOn: Binding(
                get: { store.autoHide },
                set: { store.autoHide = $0 }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))

            Text("Slides in on tab hover and slides out when mouse leaves.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    store.expanded = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12))
                    Text("Hide to Tab Now")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Tab")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                ProvidersWindow.shared.show(store: store)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 12))
                    Text("Manage Providers…")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().overlay(Color.white.opacity(0.12))

            Toggle("Start at Login", isOn: Binding(
                get: { store.startsAtLogin },
                set: { store.setStartsAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))

            if let msg = store.loginMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Color.white.opacity(0.12))

            Button("Quit Usage Sidebar") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.75))
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }
}

struct UsageRowView: View {
    let row: UsageRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if let date = row.resetsAt {
                    Text(ResetFormat.phrase(until: date))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            if row.unlimited {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 0.30, green: 0.82, blue: 0.45))
                            .frame(maxWidth: .infinity)
                    }
                Text("Unlimited")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            } else if let pct = row.percentUsed {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // The whole scale stays visible, dimmed past the used part.
                        Capsule().fill(BarTone.gradient).opacity(0.40)
                        Capsule()
                            .fill(BarTone.gradient)
                            .mask(alignment: .leading) {
                                Capsule().frame(width: max(6, geo.size.width * UsageMath.fraction(pct)))
                            }
                    }
                }
                .frame(height: 6)
                Text("\(Int(pct.rounded()))% Used")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            } else {
                Capsule().fill(Color.white.opacity(0.10)).frame(height: 6)
                Text("—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }
}

#if DEBUG
struct Sample: PreviewProvider {
    static var previews: some View {
        Group {
            SidebarRoot(store: UsageStore.samplePreview)
                .padding()
                .previewDisplayName("Sample")
            UsagePopover(
                entry: .builtIn(.claude),
                status: UsageStore.samplePreview.status(for: .builtIn(.claude))
            )
            .previewDisplayName("Sample")
        }
        .preferredColorScheme(.dark)
    }
}

extension UsageStore {
    static var samplePreview: UsageStore {
        let store = UsageStore(preview: true)
        let sessionEnd = Date().addingTimeInterval(51 * 60)
        let weekEnd = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(86_400 * 3)
        store.apply("claude", .ok(UsageSnapshot(
            ringPercent: 73,
            ringUnlimited: false,
            rows: [
                UsageRow(title: "Current session", resetsAt: sessionEnd, percentUsed: 73, unlimited: false),
                UsageRow(title: "All models", resetsAt: weekEnd, percentUsed: 7, unlimited: false),
            ],
            detail: nil,
            weeklyPercent: 7
        )))
        store.apply("grok", .ok(UsageSnapshot(
            ringPercent: 9,
            ringUnlimited: false,
            rows: [
                UsageRow(title: "Weekly", resetsAt: weekEnd, percentUsed: 21, unlimited: false),
                UsageRow(title: "Grok Build", resetsAt: weekEnd, percentUsed: 9, unlimited: false),
            ],
            detail: nil,
            weeklyPercent: 21
        )))
        store.apply("antigravity", .ok(UsageSnapshot(
            ringPercent: 52,
            ringUnlimited: false,
            rows: [
                UsageRow(title: "Current session", resetsAt: sessionEnd, percentUsed: 52, unlimited: false),
                UsageRow(title: "Weekly", resetsAt: weekEnd, percentUsed: 18, unlimited: false),
            ],
            detail: nil,
            weeklyPercent: 18
        )))
        store.apply("copilot", .ok(UsageSnapshot(
            ringPercent: 40,
            ringUnlimited: false,
            rows: [
                UsageRow(title: "Premium", resetsAt: weekEnd, percentUsed: 40, unlimited: false),
                UsageRow(title: "Chat", resetsAt: nil, percentUsed: nil, unlimited: true),
            ],
            detail: nil
        )))
        return store
    }
}
#endif
