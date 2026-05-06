# FocusLens

A native macOS menu bar app that silently tracks your app and browser activity, categorises it by productivity tier, uses Gemini AI to intelligently classify browser sessions, and answers natural-language questions about your activity via a local LLM agent (Ollama).

---

## Features

### Activity Tracking
- Monitors app switches and window titles via the macOS Accessibility API
- Detects idle time (default: 5 minutes) and excludes it from tracked time
- Discards sessions shorter than 60 seconds (configurable in `AppConstants.swift`)
- Persists sessions locally in SQLite — no data leaves your machine
- Recovers gracefully after sleep/wake and crashes (WAL mode + open-session recovery on relaunch)
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
- **Hourly timeline** — colour-coded by productivity tier (Swift Charts)
- **Ask FocusLens** — natural-language chat powered by a local Ollama agent

### Rule-Based Categorisation
- Matches sessions by app bundle ID, window title substring, or regex
- 9 built-in categories seeded at first launch (Development, Dev Tools, AI Tools, Notes & PKM, Communication, Office, Browser, Media, Utilities)
- Each category carries a productivity tier from −2 (very distracting) to +2 (very productive)
- Batch recategorisation of uncategorised sessions runs automatically on app launch and after each session ends

### Ask FocusLens — Local AI Agent
Ask natural-language questions about your activity data. A local **gemma4** model (via Ollama) acts as the reasoning engine, calling SQL-backed tools to answer your questions — all on-device, nothing sent to the cloud.

**Example queries:**
- "How much time did I spend coding today?"
- "What were my top 3 apps this week?"
- "Compare today's productivity to yesterday"
- "What was I doing at 3pm yesterday?"
- "How much time on Slack vs GitHub today?"

**How it works (same pattern as the Python demo):**
1. User types a question
2. LLM decides which tool to call
3. Tool queries the local SQLite database
4. LLM integrates the result — either calls another tool or gives a final answer
5. Up to 6 iterations; forgiving JSON parser handles sloppy local-model output

**Available tools:**

| Tool | Description |
|------|-------------|
| `current_time` | Current date/time and named ranges (today, yesterday) |
| `list_categories` | All productivity categories with their tiers |
| `query_sessions` | Individual sessions for a date, with optional filters |
| `aggregate_time` | Time totals grouped by category, app, or hour |
| `top_apps` | Top N apps by time for a date |
| `productivity_score` | 0–100 score with tier breakdown |
| `compare_periods` | Side-by-side comparison of two dates or date ranges |

#### Setup (required for Ask FocusLens)
1. Install [Ollama](https://ollama.com) (requires version ≥ 0.20.0 for gemma4)
2. Pull the model: `ollama pull gemma4`
3. Ollama runs automatically in the background — no manual `ollama serve` needed after installation
4. Open FocusLens Settings → AI → Local AI (Ollama) and click **Test Ollama** to verify

> **Privacy:** The agent runs entirely on your machine. No activity data is sent to any server.

### AI-Powered Browser Classification (Gemini)
Browsers capture the page title for every session. FocusLens sends these titles to Gemini and reclassifies sessions that were generically tagged as "Browser" into specific categories (Development, News, Entertainment, etc.).

- Model: `gemini-2.5-flash`
- Batches up to 25 sessions per request
- **Reclassify Now** button in Settings for on-demand re-processing of all pending browser sessions
- Prompt injection defence: page titles are treated as data only; responses validated against an allow-list

#### When Gemini is called

| Trigger | Behaviour |
|---|---|
| **Reclassify Now button** | On-demand from the AI settings tab — classifies all sessions still tagged "Browser" |

> Automatic classification on session-end and app-launch is implemented but currently disabled (commented out in `FocusLensApp.swift`). New browser sessions accumulate in the "Browser" category until manual reclassification.

### Settings
- **General** — displays current idle threshold and minimum session length (compile-time constants)
- **Categories** — create, edit, delete categories and assign match rules
- **Never Track** — manage the list of apps excluded from tracking entirely
- **AI** — configure Local AI (Ollama) and Cloud AI (Gemini) backends

---

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16 or later
- Accessibility permission (prompted on first launch)
- [Ollama](https://ollama.com) ≥ 0.20.0 with `gemma4` model (optional — only required for Ask FocusLens)
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

79 tests across 12 suites covering the tracker, idle detector, categorisation engine, Gemini client, prompt builder, category mapper, browser classifier, Ollama client, response parser, and agent runner.

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
│       ├── Migration003_SeedRules.swift
│       └── Migration004_FixAITools.swift
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
│   ├── OllamaClient.swift          # REST actor for Ollama /api/generate
│   ├── OllamaSettings.swift        # UserDefaults-backed Ollama config
│   └── Agent/
│       ├── AgentRunner.swift       # Agent loop: prompt → LLM → tool → repeat
│       ├── AgentTool.swift         # Protocol + ToolRegistry
│       ├── ResponseParser.swift    # Forgiving JSON parser for local models
│       ├── SystemPrompt.swift      # Dynamic system prompt builder
│       └── Tools/
│           └── AgentTools.swift    # 7 SQL-backed tools
├── UI/
│   ├── MenuBarView.swift
│   ├── TodayAggregate.swift        # @Observable state, async DB refresh
│   ├── DashboardView.swift         # Tab bar: Stats | Ask FocusLens
│   ├── DashboardCharts.swift       # Gauge, tier bar, category rows, hourly chart
│   ├── SettingsView.swift
│   ├── CategorySettingsView.swift
│   ├── AISettingsView.swift        # Ollama + Gemini configuration
│   ├── AskFocusLensView.swift      # Chat UI with trace inspector
│   └── AskViewModel.swift          # @Observable state for the agent chat
└── Utilities/
    ├── DateFormatters.swift
    └── DurationFormatter.swift

FocusLensTests/                     # Swift Testing suite
├── ActivityTrackerTests.swift
├── IdleDetectorTests.swift
├── DurationFormatterTests.swift
├── CategorizationEngineTests.swift
├── GeminiPromptTests.swift
├── BrowserCategoryMapperTests.swift
├── GeminiClientTests.swift
├── BrowserClassifierTests.swift
├── OllamaClientTests.swift
├── ResponseParserTests.swift
└── AgentRunnerTests.swift
```

**Database**: `~/Library/Application Support/FocusLens/focuslens.db`

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5, SwiftUI |
| Minimum OS | macOS 15 |
| Database | SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift) 7.x |
| Charts | Swift Charts |
| State management | `@Observable` (Observation framework) |
| Concurrency | Swift actors, `async`/`await`, `Task.detached` |
| Local AI | Ollama REST API (gemma4, no SDK) |
| Cloud AI | Google Gemini API (REST, no SDK) |
| Tests | Swift Testing (`@Test`, `#expect`) |
| System APIs | NSWorkspace, AXUIElement, CGEventSource, SMAppService |

---

## Privacy

All data is stored locally in `~/Library/Application Support/FocusLens/`. 

- **Ask FocusLens** runs entirely via Ollama on your machine — no data leaves your machine.
- **Gemini browser classification** sends only browser window titles to Google's Gemini API, and only when you have configured a Gemini API key and click Reclassify Now.

App Sandbox is disabled (required for Accessibility API access). Hardened Runtime is enabled.

---

## Features

### Activity Tracking
- Monitors app switches and window titles via the macOS Accessibility API
- Detects idle time (default: 5 minutes) and excludes it from tracked time
- Discards sessions shorter than 60 seconds (configurable in `AppConstants.swift`)
- Persists sessions locally in SQLite — no data leaves your machine
- Recovers gracefully after sleep/wake and crashes (WAL mode + open-session recovery on relaunch)
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
- **Hourly timeline** — colour-coded by productivity tier (Swift Charts)

### Rule-Based Categorisation
- Matches sessions by app bundle ID, window title substring, or regex
- 9 built-in categories seeded at first launch (Development, Dev Tools, AI Tools, Notes & PKM, Communication, Office, Browser, Media, Utilities)
- Each category carries a productivity tier from −2 (very distracting) to +2 (very productive)
- Batch recategorisation of uncategorised sessions runs automatically on app launch and after each session ends

### AI-Powered Browser Classification (Gemini)
Browsers capture the page title for every session. FocusLens sends these titles to Gemini and reclassifies sessions that were generically tagged as "Browser" into specific categories (Development, News, Entertainment, etc.).

- Model: `gemini-2.5-flash`
- Batches up to 25 sessions per request
- **Reclassify Now** button in Settings for on-demand re-processing of all pending browser sessions
- Prompt injection defence: page titles are treated as data only; responses validated against an allow-list

#### When Gemini is called

| Trigger | Behaviour |
|---|---|
| **Reclassify Now button** | On-demand from the AI settings tab — classifies all sessions still tagged "Browser" |

> Automatic classification on session-end and app-launch is implemented but currently disabled (commented out in `FocusLensApp.swift`). New browser sessions accumulate in the "Browser" category until manual reclassification.

### Settings
- **General** — displays current idle threshold and minimum session length (compile-time constants)
- **Categories** — create, edit, delete categories and assign match rules
- **Never Track** — manage the list of apps excluded from tracking entirely
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
│       ├── Migration003_SeedRules.swift
│       └── Migration004_FixAITools.swift
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
├── UI/
│   ├── MenuBarView.swift
│   ├── TodayAggregate.swift        # @Observable state, async DB refresh
│   ├── DashboardView.swift
│   ├── DashboardCharts.swift       # Gauge, tier bar, category rows, hourly chart
│   ├── SettingsView.swift
│   ├── CategorySettingsView.swift
│   └── AISettingsView.swift
└── Utilities/
    ├── DateFormatters.swift
    └── DurationFormatter.swift

FocusLensTests/                     # Swift Testing suite
├── ActivityTrackerTests.swift
├── IdleDetectorTests.swift
├── DurationFormatterTests.swift
├── CategorizationEngineTests.swift
├── GeminiPromptTests.swift
├── BrowserCategoryMapperTests.swift
├── GeminiClientTests.swift
└── BrowserClassifierTests.swift
```

**Database**: `~/Library/Application Support/FocusLens/focuslens.db`

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5, SwiftUI |
| Minimum OS | macOS 15 |
| Database | SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift) 7.x |
| Charts | Swift Charts |
| State management | `@Observable` (Observation framework) |
| Concurrency | Swift actors, `async`/`await`, `Task.detached` |
| AI | Google Gemini API (REST, no SDK) |
| Tests | Swift Testing (`@Test`, `#expect`) |
| System APIs | NSWorkspace, AXUIElement, CGEventSource, SMAppService |

---

## Privacy

All data is stored locally in `~/Library/Application Support/FocusLens/`. Nothing is sent to any server unless you configure a Gemini API key, in which case only browser window titles are sent to Google's Gemini API for classification.

App Sandbox is disabled (required for Accessibility API access). Hardened Runtime is enabled.
