# Changelog

All notable changes to **Usage Sidebar** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed
- **Claude Code quota**: live OAuth now lives in Keychain (`Claude Code-credentials`). The sidebar was preferring a stale `~/.claude/.credentials.json` (often weeks old), getting HTTP 401, and showing **—**. It now prefers the unexpired Keychain token and skips 401/403 sources instead of giving up on the first one.
- **Missing-auth backoff**: a 401 no longer ramps the poll interval to 5 minutes, so a Grok/Claude token refresh is picked up on the next 60s cycle.

---

## [1.2.0] - 2026-09-01

### Added
- **Hover Slide-In & Focusout Slide-Out**:
  - Hovering over the collapsed edge tab automatically slides the full quota dock into view with a smooth spring animation.
  - Moving the cursor out of the sidebar area starts a 350ms debounced grace period and automatically stows the dock back into the edge tab.
  - Active popover protection: auto-collapse is suspended while reading detailed breakdowns in a provider popover or adjusting settings.
- **Pin / Always-Open Dock Mode**:
  - Added a dedicated Pin toggle button (`pin` / `pin.fill`) next to the settings gear at the bottom of the sidebar.
  - Added an "Auto-Hide Sidebar" toggle in the Settings popover. When pinned (`autoHide = false`), the dock remains expanded continuously. Setting is persisted in `UserDefaults`.
- **Application Icon & Asset Bundle**:
  - Added official brand application icon featuring vibrant stylized telemetry artwork.
  - Packaged multi-resolution `AppIcon.icns` (16×16 to 1024×1024@2x) and registered `CFBundleIconFile` in `Info.plist`.

### Changed
- **Persistent Non-Interactive Authentication**:
  - Completely eliminated modal macOS Keychain password prompts on app launch and polling loops.
  - Prioritized direct filesystem reads for existing local session/OAuth tokens (`~/.claude/.credentials.json`, `~/.gemini/antigravity-cli/oauth_creds.json`, `~/.config/gh/hosts.yml`, `~/.grok/auth.json`) before querying Keychain.
  - Configured `SecItemCopyMatching` with `LAContext.interactionNotAllowed = true` to guarantee silent, non-intrusive credential resolution.
- **Refined Dock Geometry & Brand Logos**:
  - Cleaned up right-edge dock pill curvature (18pt outer display corner radius, flat 0pt bezel anchor) with no edge artifacts.
  - Re-anchored and centered all 4 vector brand marks within their 38×38pt widget tiles.

---

## [1.1.0] - 2026-08-31

### Added
- **Official Brand Vector Logos**:
  - Anthropic Claude official 12-arm sunburst / asterisk logo (`ClaudeOfficialMark`).
  - xAI Grok / Grok Build official dynamic sliced ring logo with flared blade wing (`GrokOfficialMark`).
  - GitHub Copilot official GitHub Primer Octicons astronaut robot head with visor & eye cutouts (`CopilotOfficialMark`).
  - Google Antigravity multi-faceted crystal snowflake starburst mark (`AntigravityCrystalMark`).
- **Pure Swift SVG Path Engine**:
  - Zero-dependency vector parser and rendering engine (`SVGPathEngine`, `SVGPathShape`) supporting full SVG path commands (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `A`, `Z`) with aspect-ratio-preserving bounds scaling.
- **Organic Right-Edge Scoop Geometry**:
  - Custom `EdgeScoopShape` featuring continuous concave Bézier fillets tangent to the screen edge.
  - Collapsed tab scoop `CollapsedScoopShape` with smooth spring-animated expand/collapse transitions.
- **Collapsible Sidebar State**:
  - Collapse handle and compact tab to tuck the sidebar against the edge of the display with one click.
- **Dedicated Settings Popover**:
  - Bottom gear icon button opening a sleek settings popover with "Start at Login" toggle and "Quit Usage Sidebar" action.
- **Secure Local TLS & Robust Subprocess I/O**:
  - Added `LocalTrustDelegate` scoped strictly to `127.0.0.1` / `localhost` for secure communication with local IDE language servers.
  - Asynchronous background stream reading in `ProcessRun.capture` using `DispatchGroup` to prevent pipe deadlocks when scanning large process tables.

### Changed
- **Vertical Badge Widget Design**:
  - Redesigned from horizontal rows to compact vertical columns: 38×38pt circular badge with vibrant ring progress track on top, and centered monospaced percentage typography directly below.
- **Obsidian Dark Color Palette**:
  - Background updated to deep obsidian dark (`#0D0D0D`) with subtle white border highlights (`Color.white.opacity(0.08)`).
  - High-vibrancy brand accent colors for Claude (`#FA5A2A`), Grok Build (`#10B981`), Antigravity (`#D5F01F`), and GitHub Copilot (`#3B82F6`).
- **Window Positioning & Multi-Screen Support**:
  - Window positioning automatically recalculates on screen layout changes (`didChangeScreenParametersNotification` and `didChangeScreenNotification`).

### Fixed
- Fixed Antigravity quota retrieval failing when querying local language server instances over HTTPS.
- Fixed potential stdout buffer freeze when parsing system credentials via subprocess CLI commands.

---

## [1.0.0] - 2026-08-31

### Added
- Initial release of **Usage Sidebar** for macOS (14.0+).
- Unobtrusive floating `LSUIElement` utility pinned to the right edge of the screen.
- Real-time quota tracking for 4 AI developer tools:
  - **Anthropic Claude Code**: 5-hour session and weekly all-models utilization via OAuth API.
  - **xAI Grok Build**: Weekly credit usage and current billing period tracking via CLI proxy API.
  - **Google Antigravity**: Scarcest model quota and weekly quota tracking via Google Cloud APIs and local language server fallback.
  - **GitHub Copilot**: Premium interactions, chat quotas, and quota reset date tracking via internal Copilot APIs.
- Automatic credential discovery from macOS Keychain (`Claude Code-credentials`, `gh:github.com`, `gemini/antigravity`) and local file stores (`~/.claude/.credentials.json`, `~/.grok/auth.json`, `~/.config/gh/hosts.yml`).
- Independent ~60s polling loops with HTTP 429 exponential backoff per provider.
- Flyout popovers with reset timestamps, progress bars, and quota breakdowns.
- Native login item registration via `SMAppService.mainApp`.
