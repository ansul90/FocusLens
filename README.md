# FocusLens

A native macOS menu bar app that silently tracks your app and browser activity, categorises it by productivity tier, and uses Gemini AI to intelligently classify browser sessions beyond a generic "Browser" label.

---

## Features

### Activity Tracking
- Monitors app switches and window titles via the macOS Accessibility API
- Detects idle time (default: 5 minutes) and excludes it from tracked time
- Persists sessions locally in SQLite — no data leaves your machine
- Recovers gracefully after sleep/wake and crashes (WAL mode)
- Launches at login via `SMAppService`

### Menu Bar Popover
- Shows the currently active app and today's total tracked time
- Top 5 apps ranked by duration with an "Open Dashboard" link for full details
- Icon toolbar: Dashboard · Settings · Pause/Resume · Quit

### Dashboard
- **Date picker** — navigate any past day with `<` / `>` arrows or a compact date picker
- **Productivity score** — weighted average of session tiers mapped to 0–100
- **Category breakdown** — horizontal bar chart by category
- **Top apps** — ranked by time spent
- **Hourly timeline** — colour-coded by productivity tier

### Rule-Based Categorisation
- Matches sessions by app bundle ID, window title substring, or regex
- 9 built-in categories seeded at first launch (Development, Browser, AI Tools, Communication, Media, and more)
- Each category carries a productivity tier from −2 (very distracting) to +2 (very productive)

### AI-Powered Browser Classification (Gemini)
Browsers capture the page title for every session. FocusLens sends these titles to Gemini and reclassifies sessions that were generically tagged as "Browser" into specific categories (Development, News, Entertainment, etc.).

- Model: `gemini-2.5-flash`
- Batches up to 25 sessions per request
- Runs automatically on session end when an API key is configured
- **Reclassify Now** button in Settings for on-demand re-processing of all pending sessions
- Prompt injection defence: page titles are treated as data only

### Settings
- **General** — idle threshold, minimum session length
- **Categories** — create, edit, and assign rules to categories
- **AI** — enter Gemini API key, enable/disable classification, test connection, reclassify now

---

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16 or later
- Accessibility permission (prompted on first launch)
- Gemini API key (optional — only required for AI browser classification)

---

## Getting Started

```bash
git clone <repo-url>
cd FocusLens
open FocusLens.xcodeproj
```

Press **⌘R** in Xcode to build and run. The app appears in the menu bar (no Dock icon). On first launch, macOS will prompt for Accessibility permission — this is required for window title tracking.

### Command-line build

```bash
xcodebuild build \
  -project FocusLens.xcodeproj \
  -scheme FocusLens \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release
```

---

## Running Tests

```bash
xcodebuild test \
  -project FocusLens.xcodeproj \
  -scheme FocusLens \
  -destination 'platform=macOS,arch=arm64'
```

53 tests across 9 suites covering the tracker, idle detector, categorisation engine, Gemini client, prompt builder, category mapper, browser classifier, and duration formatter.

---

## Project Structure

```
FocusLens/
├── App/
│   ├── FocusLensApp.swift          # @main entry, MenuBarExtra, window declarations
│   ├── AppConstants.swift          # Thresholds, DB path, AI endpoint constants
│   └── LoginItemManager.swift      # SMAppService launch-at-login
├── Models/
│   ├── ActivitySession.swift
│   ├── Category.swift
│   └── CategoryRule.swift
├── Storage/
│   ├── DatabaseManager.swift       # GRDB pool + migration runner
│   ├── ActivitySessionStore.swift  # Session queries (parameterised by date)
│   ├── CategoryStore.swift
│   ├── NeverTrackStore.swift
│   └── Migrations/
│       ├── Migration001_Sessions.swift
│       ├── Migration002_Categories.swift
│       └── Migration003_SeedRules.swift
├── Tracking/
│   ├── ActivityTracker.swift       # Core Swift actor, session lifecycle
│   ├── IdleDetector.swift
│   ├── PermissionManager.swift
│   └── CategorizationEngine.swift
├── AI/
│   ├── GeminiClient.swift          # REST actor with typed request/response
│   ├── GeminiPrompt.swift          # Prompt builder, request/response types
│   ├── GeminiSettings.swift        # UserDefaults-backed API key + enabled flag
│   ├── BrowserClassifier.swift     # Orchestrates batch classification
│   ├── BrowserCategoryMapper.swift # Maps Gemini labels → DB category IDs
│   └── BrowserBundleIds.swift
└── UI/
    ├── MenuBarView.swift
    ├── DashboardView.swift
    ├── TodayAggregate.swift        # @Observable state, async DB refresh
    ├── SettingsView.swift
    ├── CategorySettingsView.swift
    ├── AISettingsView.swift
    └── (chart components)

FocusLensTests/                     # Swift Testing suite
```

**Database**: `~/Library/Application Support/FocusLens/focuslens.db`

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5, SwiftUI |
| Minimum OS | macOS 15 |
| Database | SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift) 7.x |
| State management | `@Observable` (Observation framework) |
| Concurrency | Swift actors, `async`/`await`, `Task.detached` |
| AI | Google Gemini API (REST, no SDK) |
| Tests | Swift Testing (`@Test`, `#expect`) |
| System APIs | NSWorkspace, AXUIElement, CGEventSource, SMAppService |

---

## Privacy

All data is stored locally in `~/Library/Application Support/FocusLens/`. Nothing is sent to any server unless you configure a Gemini API key, in which case only browser window titles are sent to Google's Gemini API for classification.

App Sandbox is disabled (required for Accessibility API access). Hardened Runtime is enabled.
