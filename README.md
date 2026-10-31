# Usage Sidebar

**Usage Sidebar** is an always-on-top, right-edge macOS utility pill that monitors **your live quota and credit usage** across top AI coding tools: **Claude Code**, **Grok Build**, **Google Antigravity**, and **GitHub Copilot**.

It never invents numbers: missing or expired credentials show **—**, and SwiftUI previews are labeled **Sample**.

This is an `LSUIElement` accessory app (no Dock icon). Hover any badge to open a detailed flyout popover with quota breakdown and reset timers, or click it to keep the popover open. Click the bottom handle to collapse the sidebar into a slim edge tab, or click the settings gear to toggle launch at login and quit.

> **Unofficial Utility**: Reuses tokens and credentials already stored locally by those tools and queries the same usage endpoints they use internally. Credentials and secrets are never printed or transmitted to third parties.

---

## ✨ Features & Design

- **Organic Right-Edge Scoop (`EdgeScoopShape`)**: Obsidian dark dock (`#0D0D0D`) with smooth concave Bézier fillets that seamlessly hug the right edge of your display.
- **Vertical Badge Widget System**:
  - 38×38pt circular badges with high-contrast active progress ring tracks.
  - High-legibility monospaced percentage readouts (`13pt .monospacedDigit()`) placed directly below each badge.
  - Interactive hover scaling and spring animations.
- **Hover Slide-In & Focusout Slide-Out**: Moving your mouse over the collapsed edge tab automatically slides the full dock into view; leaving the dock automatically stows it back into the edge tab after a 350ms grace period.
- **Pin / Always-Open Mode**: Click the pin icon in the bottom toolbar (or toggle in Settings) to keep the sidebar pinned open permanently.
- **Official Brand Vector Marks (`SVGPathEngine`)**:
  - 🟠 **Anthropic Claude**: Official 12-arm sunburst / asterisk vector mark (`#FA5A2A`).
  - 🟢 **xAI Grok Build**: Official dynamic sliced ring logo with flared top-right blade wing and tapered fin (`#10B981`).
  - 🟡 **Google Antigravity**: Multi-faceted crystal snowflake starburst mark (`#D5F01F`).
  - 🔵 **GitHub Copilot**: Official GitHub Primer Octicons astronaut robot head with visor & eye cutouts (`#3B82F6`).
  - Built with a pure Swift zero-dependency SVG path parsing engine (`SVGPathEngine`).
- **Collapsible Edge Tab**: Click the collapse handle to stow the sidebar into a minimal 18pt edge tab (`CollapsedScoopShape`), or hover to expand.
- **Integrated Settings Popover**: Dedicated gear button for "Start at Login" configuration (`SMAppService`), Auto-Hide preferences, and quick app termination.
- **Detailed Quota Popovers**:
  - Live progress bars with color-coded utilization thresholds (<50% Green, 50-80% Orange, >80% Red).
  - Humanized reset countdowns (e.g. *"Resets in 45 min"*, *"Resets Mon 10:00 AM"*).
  - Multi-tier bucket breakdowns (session limits, weekly caps, premium interactions).
  - Active popover protection keeps the dock open while reading details.
- **Multi-Monitor Awareness**: Automatically repositions and anchors flush to the active screen on display configuration changes.
- **Native App Icon**: High-resolution macOS application icon bundle (`AppIcon.icns`).

---

## 📋 Requirements

- **macOS 14.0 (Sonoma)** or later
- **Apple Silicon (arm64)** or **Intel (x86_64)** Mac
- **Xcode Command Line Tools** (`xcode-select --install`) for `swiftc` compilation

---

## 🛠️ Build & Installation

Build the native `.app` bundle without needing a full Xcode IDE project:

```bash
cd usage-sidebar
bash scripts/build-app.sh
open dist/UsageSidebar.app
```

The build script compiles all Swift sources in `Sources/` into a single standalone binary and packages `dist/UsageSidebar.app` (`LSUIElement=true`, `LSMinimumSystemVersion=14.0`).

### Gatekeeper / Quarantine
If macOS Gatekeeper blocks opening an unsigned local build:

```bash
xattr -d com.apple.quarantine dist/UsageSidebar.app
```

> **Tip**: Copying `UsageSidebar.app` to `/Applications` makes login items (`SMAppService`) more reliable across reboots.

### Version and wiki

`bash scripts/install-hooks.sh` once per clone. The pre-commit hook then bumps `CFBundleShortVersionString` (patch) and `CFBundleVersion`, and moves `CHANGELOG.md`'s `[Unreleased]` notes under that version. The post-commit hook updates the wiki page `entities/usage-sidebar`. Put `[skip version]` in a `git commit -m` message, or set `USAGE_SIDEBAR_SKIP_VERSION=1`, to commit without a bump. Amends and merges do not bump.

---

## 🔑 Persistent Non-Interactive Authentication

Usage Sidebar reads tokens other tools already stored. Claude Code's **live** OAuth is Keychain item `Claude Code-credentials` (the `~/.claude/.credentials.json` copy is often weeks stale).

Those items trust `/usr/bin/security` (`apple-tool:`), not this app. The sidebar reads them through that tool, so macOS does not ask for your login password on launch or on the 60s poll. A direct Keychain read from the app raises that sheet, and Always Allow is wiped the next time Claude or Antigravity rewrites the item.

| Provider | Primary | Fallback |
|---|---|---|
| **Claude Code** | Keychain `Claude Code-credentials` (unexpired) | `~/.claude/.credentials.json` |
| **Grok Build** | `~/.grok/auth.json` | — |
| **Google Antigravity** | `~/.gemini/antigravity-cli/oauth_creds.json`, `~/.gemini/oauth_creds.json`, or local Language Server | `gemini` (account `antigravity`) |
| **GitHub Copilot** | `~/.config/gh/hosts.yml` or `gh auth token` | `gh:github.com` |

---

## 📡 Where Credentials Come From

1. **Anthropic Claude**:
   - Reads Keychain `Claude Code-credentials` first (live token), then `~/.claude/.credentials.json` if it is still valid.
   - `GET https://api.anthropic.com/api/oauth/usage` with header `anthropic-beta: oauth-2025-04-20`.
   - Ring tracks the 5-hour rolling session percentage. Popover details current session + weekly all-models utilization.
   - *Note: Does not refresh OAuth tokens to prevent rotating Claude Code's active session.*
2. **xAI Grok Build**:
   - Reads from `~/.grok/auth.json` (`https://accounts.x.ai/sign-in`.key, `{issuer}::{client_id}`.key, or `access_token`).
   - `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with `x-grok-client-surface: grok-build` and `X-XAI-Token-Auth: xai-grok-cli`.
   - Ring tracks `config.creditUsagePercent`. Popover shows weekly quota and billing period reset date.
3. **Google Antigravity**:
   - Reads from `~/.gemini/antigravity-cli/oauth_creds.json`, `~/.gemini/oauth_creds.json`, `~/.agy`, or `~/Library/Application Support/Antigravity`.
   - Primary: `POST https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`.
   - Fallback: Connects via local loopback language server (`RetrieveUserQuotaSummary` / `GetUserStatus` on `127.0.0.1` via TLS with `LocalTrustDelegate`).
   - Ring displays the scarcest quota bucket percentage (e.g. Gemini 5-hour or weekly model cap).
4. **GitHub Copilot**:
   - Reads from `~/.config/gh/hosts.yml` or `gh auth token`.
   - `GET https://api.github.com/copilot_internal/user` → `quota_snapshots`.
   - Ring displays the limited bucket (`premium_interactions` or `chat`). Unlimited buckets display **∞** / **Unlimited**.

Each provider polls independently every ~60 seconds and implements exponential backoff on HTTP 429 rate limit responses (honoring `Retry-After` headers).

---

## 🗂️ Project Structure

```
usage-sidebar/
├── CHANGELOG.md              # Version release notes and history
├── README.md                 # Project documentation and guide
├── Sources/
│   ├── App/
│   │   ├── LoginItem.swift       # SMAppService registration for auto-start
│   │   ├── UsageSidebarApp.swift # App lifecycle, NSPanel floating window & edge snapping
│   │   └── UsageStore.swift      # Multi-provider state management & concurrency loops
│   ├── Models/
│   │   └── Models.swift          # Data models, color palettes, math & date parsers
│   ├── Providers/
│   │   ├── AntigravityProvider.swift # Cloud Code PA API & local language server polling
│   │   ├── ClaudeProvider.swift      # Anthropic OAuth usage API polling
│   │   ├── CopilotProvider.swift     # GitHub internal Copilot quota API polling
│   │   └── GrokProvider.swift        # xAI CLI billing proxy API polling
│   ├── Support/
│   │   ├── JSONMap.swift         # Dynamic JSON tree traversal and safe casting
│   │   └── Secrets.swift         # Keychain query, process execution, token regex redaction
│   ├── Views/
│   │   └── Views.swift           # SwiftUI UI, EdgeScoopShape, SVGPathEngine, and popovers
│   └── Info.plist                # LSUIElement, macOS 14 bundle configuration
├── dist/                         # Compiled macOS application output (UsageSidebar.app)
└── scripts/
    └── build-app.sh              # Standalone swiftc build & code signing script
```

---

## 📄 License

MIT License. Designed for personal productivity.
