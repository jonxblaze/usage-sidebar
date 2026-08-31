import AppKit
import SwiftUI

struct SidebarRoot: View {
    @ObservedObject var store: UsageStore
    @State private var settingsOpen = false
    @State private var hovered = false

    var body: some View {
        Group {
            if store.expanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.expanded)
    }

    private var expandedBody: some View {
        VStack(spacing: 13) {
            // Providers vertical list
            ForEach(ProviderID.allCases) { id in
                RingCell(id: id, status: store.status(for: id))
            }

            // Settings gear button
            Button {
                settingsOpen.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.12))
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                    Image(systemName: "gearshape")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $settingsOpen, arrowEdge: .leading) {
                SettingsPopover(store: store)
            }
            .help("Settings")

            // Collapse handle
            Button {
                withAnimation { store.expanded = false }
            } label: {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 18, height: 3.5)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)
            .help("Collapse sidebar")
        }
        .padding(.top, 22)
        .padding(.bottom, 16)
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .frame(width: 52)
        .background {
            SidebarBackground()
        }
        .shadow(color: .black.opacity(0.50), radius: 12, x: -3, y: 2)
    }

    private var collapsedBody: some View {
        Button {
            withAnimation { store.expanded = true }
        } label: {
            ZStack {
                CollapsedScoopShape()
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.05))
                    .overlay {
                        CollapsedScoopShape()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }

                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .offset(x: -2)
            }
            .frame(width: 18, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 6, x: -2, y: 1)
        .help("Expand usage sidebar")
    }
}

// MARK: - Ring Cell (Vertical Layout: Ring on Top, Percentage Below)

struct RingCell: View {
    let id: ProviderID
    let status: ProviderStatus
    @State private var open = false
    @State private var hover = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Dark circular inner plate
                    Circle()
                        .fill(Color(white: 0.12))

                    // Progress track and active arc
                    RingTrack(progress: status.ringProgress, color: id.brand)

                    // Provider logo mark
                    ProviderMark(id: id)
                        .frame(width: 17, height: 17)
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                // Percentage caption directly below
                Text(status.ringCaption)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .scaleEffect(hover ? 1.06 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popover(isPresented: $open, arrowEdge: .leading) {
            UsagePopover(id: id, status: status)
        }
        .help(id.displayName)
    }
}

// MARK: - Progress Ring Track

struct RingTrack: View {
    var progress: Double?
    var color: Color

    var body: some View {
        ZStack {
            // Inactive subtle track
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 2.8)

            // Active progress arc
            Circle()
                .trim(from: 0, to: progress ?? 0)
                .stroke(
                    color.opacity(progress == nil ? 0.25 : 1),
                    style: StrokeStyle(lineWidth: 2.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: progress)
        }
    }
}

// MARK: - Organic Right-Edge Concave Scoop Shapes

/// Shape that hugs the right edge of the screen with smooth concave corner fillets at top and bottom.
struct EdgeScoopShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let scoopR: CGFloat = min(28, h * 0.15)

        var p = Path()

        // Start at top right flush with screen edge
        p.move(to: CGPoint(x: w, y: 0))

        // Top concave curve: swoops from (w, 0) inward to (0, scoopR)
        p.addCurve(
            to: CGPoint(x: 0, y: scoopR),
            control1: CGPoint(x: w, y: scoopR * 0.55),
            control2: CGPoint(x: 0, y: scoopR * 0.45)
        )

        // Left straight vertical edge
        p.addLine(to: CGPoint(x: 0, y: h - scoopR))

        // Bottom concave curve: swoops from (0, h - scoopR) outward to (w, h)
        p.addCurve(
            to: CGPoint(x: w, y: h),
            control1: CGPoint(x: 0, y: h - scoopR * 0.45),
            control2: CGPoint(x: w, y: h - scoopR * 0.55)
        )

        // Right straight vertical edge along screen
        p.addLine(to: CGPoint(x: w, y: 0))

        p.closeSubpath()
        return p
    }
}

/// Compact scoop for collapsed state.
struct CollapsedScoopShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r: CGFloat = min(10, w * 0.5)

        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        p.addCurve(
            to: CGPoint(x: 0, y: r * 1.5),
            control1: CGPoint(x: w, y: r * 0.7),
            control2: CGPoint(x: 0, y: r * 0.8)
        )
        p.addLine(to: CGPoint(x: 0, y: h - r * 1.5))
        p.addCurve(
            to: CGPoint(x: w, y: h),
            control1: CGPoint(x: 0, y: h - r * 0.8),
            control2: CGPoint(x: w, y: h - r * 0.7)
        )
        p.addLine(to: CGPoint(x: w, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Solid obsidian dark background matching the mockup.
struct SidebarBackground: View {
    var body: some View {
        EdgeScoopShape()
            .fill(Color(red: 0.05, green: 0.05, blue: 0.05))
            .overlay {
                EdgeScoopShape()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

// MARK: - Provider Marks

struct ProviderMark: View {
    let id: ProviderID

    var body: some View {
        switch id {
        case .claude:
            ClaudeOfficialMark()
                .foregroundStyle(.white)
        case .grok:
            GrokOfficialMark()
                .foregroundStyle(.white)
        case .antigravity:
            AntigravityCrystalMark()
        case .copilot:
            CopilotOfficialMark()
                .foregroundStyle(.white)
        }
    }
}

/// Official Anthropic Claude Logo (12-Arm Sunburst Asterisk).
struct ClaudeOfficialMark: View {
    private static let d = "m4.709 15.955 4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 0 1-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z"

    var body: some View {
        SVGPathShape(pathString: Self.d, viewBox: CGRect(x: 0, y: 0, width: 24, height: 24))
    }
}

/// Official xAI Grok / Grok Build Logo.
struct GrokOfficialMark: View {
    private static let d = "M9.27 15.29l7.978-5.897c.391-.29.95-.177 1.137.272.98 2.369.542 5.215-1.41 7.169-1.951 1.954-4.667 2.382-7.149 1.406l-2.711 1.257c3.889 2.661 8.611 2.003 11.562-.953 2.341-2.344 3.066-5.539 2.388-8.42l.006.007c-.983-4.232.242-5.924 2.75-9.383.06-.082.12-.164.179-.248l-3.301 3.305v-.01L9.267 15.292M7.623 16.723c-2.792-2.67-2.31-6.801.071-9.184 1.761-1.763 4.647-2.483 7.166-1.425l2.705-1.25a7.808 7.808 0 00-1.829-1A8.975 8.975 0 005.984 5.83c-2.533 2.536-3.33 6.436-1.962 9.764 1.022 2.487-.653 4.246-2.34 6.022-.599.63-1.199 1.259-1.682 1.925l7.62-6.815"

    var body: some View {
        SVGPathShape(pathString: Self.d, viewBox: CGRect(x: 0, y: 0, width: 24, height: 24))
    }
}

/// Official GitHub Copilot Logo (Octicon Robot Visor Head with Eyes).
struct CopilotOfficialMark: View {
    private static let headD = "M23.922 16.992c-.861 1.495-5.859 5.023-11.922 5.023-6.063 0-11.061-3.528-11.922-5.023A.641.641 0 0 1 0 16.736v-2.869a.841.841 0 0 1 .053-.22c.372-.935 1.347-2.292 2.605-2.656.167-.429.414-1.055.644-1.517a10.195 10.195 0 0 1-.052-1.086c0-1.331.282-2.499 1.132-3.368.397-.406.89-.717 1.474-.952 1.399-1.136 3.392-2.093 6.122-2.093 2.731 0 4.767.957 6.166 2.093.584.235 1.077.546 1.474.952.85.869 1.132 2.037 1.132 3.368 0 .368-.014.733-.052 1.086.23.462.477 1.088.644 1.517 1.258.364 2.233 1.721 2.605 2.656a.832.832 0 0 1 .053.22v2.869a.641.641 0 0 1-.078.256ZM12.172 11h-.344a4.323 4.323 0 0 1-.355.508C10.703 12.455 9.555 13 7.965 13c-1.725 0-2.989-.359-3.782-1.259a2.005 2.005 0 0 1-.085-.104L4 11.741v6.585c1.435.779 4.514 2.179 8 2.179 3.486 0 6.565-1.4 8-2.179v-6.585l-.098-.104s-.033.045-.085.104c-.793.9-2.057 1.259-3.782 1.259-1.59 0-2.738-.545-3.508-1.492a4.323 4.323 0 0 1-.355-.508h-.016.016Zm.641-2.935c.136 1.057.403 1.913.878 2.497.442.544 1.134.938 2.344.938 1.573 0 2.292-.337 2.657-.751.384-.435.558-1.15.558-2.361 0-1.14-.243-1.847-.705-2.319-.477-.488-1.319-.862-2.824-1.025-1.487-.161-2.192.138-2.533.529-.269.307-.437.808-.438 1.578v.021c0 .265.021.562.063.893Zm-1.626 0c.042-.331.063-.628.063-.894v-.02c-.001-.77-.169-1.271-.438-1.578-.341-.391-1.046-.69-2.533-.529-1.505.163-2.347.537-2.824 1.025-.462.472-.705 1.179-.705 2.319 0 1.211.175 1.926.558 2.361.365.414 1.084.751 2.657.751 1.21 0 1.902-.394 2.344-.938.475-.584.742-1.44.878-2.497Z"
    private static let eyesD = "M14.5 14.25a1 1 0 0 1 1 1v2a1 1 0 0 1-2 0v-2a1 1 0 0 1 1-1Zm-5 0a1 1 0 0 1 1 1v2a1 1 0 0 1-2 0v-2a1 1 0 0 1 1-1Z"

    var body: some View {
        ZStack {
            SVGPathShape(pathString: Self.headD, viewBox: CGRect(x: 0, y: 0, width: 24, height: 24))
            SVGPathShape(pathString: Self.eyesD, viewBox: CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }
}


/// Antigravity / Gemini faceted crystal snowflake starburst mark.
struct AntigravityCrystalMark: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2
            let r = min(w, h) * 0.50

            // 4 main cardinal diamond points
            var star = Path()
            let wCore = r * 0.22

            // Top
            star.move(to: CGPoint(x: cx, y: cy - r))
            star.addLine(to: CGPoint(x: cx + wCore, y: cy - wCore))
            // Right
            star.addLine(to: CGPoint(x: cx + r, y: cy))
            star.addLine(to: CGPoint(x: cx + wCore, y: cy + wCore))
            // Bottom
            star.addLine(to: CGPoint(x: cx, y: cy + r))
            star.addLine(to: CGPoint(x: cx - wCore, y: cy + wCore))
            // Left
            star.addLine(to: CGPoint(x: cx - r, y: cy))
            star.addLine(to: CGPoint(x: cx - wCore, y: cy - wCore))
            star.closeSubpath()

            ctx.fill(star, with: .color(.white))

            // 4 diagonal faceted rays
            let diagR = r * 0.68
            let dOffset = diagR * 0.7071
            let dInner = wCore * 0.7071

            var diagonals = Path()
            // Top Right
            diagonals.move(to: CGPoint(x: cx + dInner, y: cy - dInner))
            diagonals.addLine(to: CGPoint(x: cx + dOffset, y: cy - dOffset))
            // Bottom Right
            diagonals.move(to: CGPoint(x: cx + dInner, y: cy + dInner))
            diagonals.addLine(to: CGPoint(x: cx + dOffset, y: cy + dOffset))
            // Bottom Left
            diagonals.move(to: CGPoint(x: cx - dInner, y: cy + dInner))
            diagonals.addLine(to: CGPoint(x: cx - dOffset, y: cy + dOffset))
            // Top Left
            diagonals.move(to: CGPoint(x: cx - dInner, y: cy - dInner))
            diagonals.addLine(to: CGPoint(x: cx - dOffset, y: cy - dOffset))

            ctx.stroke(
                diagonals,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
            )
        }
    }
}

// MARK: - SVG Path Parser & Shape Engine

struct SVGPathShape: Shape {
    let pathString: String
    let viewBox: CGRect

    func path(in rect: CGRect) -> Path {
        let base = SVGPathEngine.parse(pathString)
        let scaleX = rect.width / viewBox.width
        let scaleY = rect.height / viewBox.height
        let scale = min(scaleX, scaleY)
        let dx = rect.midX - (viewBox.width * scale) / 2
        let dy = rect.midY - (viewBox.height * scale) / 2

        let transform = CGAffineTransform(translationX: dx, y: dy)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -viewBox.minX, y: -viewBox.minY)

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
                guard let _ = nextNumber(), let _ = nextNumber(),
                      let _ = nextNumber(), let _ = nextNumber(), let _ = nextNumber(),
                      let ex = nextNumber(), let ey = nextNumber() else { break }
                let end = isRel ? CGPoint(x: currentPoint.x + ex, y: currentPoint.y + ey) : CGPoint(x: ex, y: ey)
                path.addLine(to: end)
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
    let id: ProviderID
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
                Circle().fill(id.brand.opacity(0.25))
                ProviderMark(id: id)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)

            Text(id.usageTitle)
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
        case .missingAuth(let hint):
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
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(BarTone.color(forPercent: pct))
                            .frame(width: max(6, geo.size.width * min(max(pct / 100.0, 0), 1)))
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
                id: .claude,
                status: UsageStore.samplePreview.claude
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
        store.claude = .ok(UsageSnapshot(
            ringPercent: 73,
            ringUnlimited: false,
            rows: [
                UsageRow(title: "Current session", resetsAt: sessionEnd, percentUsed: 73, unlimited: false),
                UsageRow(title: "All models", resetsAt: weekEnd, percentUsed: 7, unlimited: false),
            ],
            detail: nil
        ))
        store.grok = .ok(UsageSnapshot(
            ringPercent: 21,
            ringUnlimited: false,
            rows: [UsageRow(title: "Weekly", resetsAt: weekEnd, percentUsed: 21, unlimited: false)],
            detail: nil
        ))
        store.antigravity = .ok(UsageSnapshot(
            ringPercent: 52,
            ringUnlimited: false,
            rows: [
                UsageRow(title: "Current session", resetsAt: sessionEnd, percentUsed: 52, unlimited: false),
                UsageRow(title: "Weekly", resetsAt: weekEnd, percentUsed: 18, unlimited: false),
            ],
            detail: nil
        ))
        store.copilot = .ok(UsageSnapshot(
            ringPercent: 40,
            ringUnlimited: false,
            rows: [
                UsageRow(title: "Premium", resetsAt: weekEnd, percentUsed: 40, unlimited: false),
                UsageRow(title: "Chat", resetsAt: nil, percentUsed: nil, unlimited: true),
            ],
            detail: nil
        ))
        return store
    }
}
#endif
