# FocusLens — Personal Mac Activity Tracker with AI Insights

A personal RescueTime alternative built as a native macOS menu bar app, powered by Google Gemini Flash 2.0 for intelligent insights.

## Why This Project

- RescueTime charges $7-18/month for features that are straightforward to build
- Their paid analytics/insights layer maps directly to what Gemini Flash can do for pennies/month
- Local-first: all data stays on your machine (RescueTime sends everything to their servers)
- Passive tracking generates rich data — Gemini's value comes from analyzing data *after* it's collected, not before

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| UI | SwiftUI `MenuBarExtra` (`.window` style) | Native Mac, no dock icon (`LSUIElement = YES`), richer than `NSMenu` |
| Storage | SQLite via GRDB.swift | Local-first, crash-safe WAL mode, migrations, thread-safe `DatabasePool` |
| Activity capture | `NSWorkspace` notifications + Accessibility API (`AXUIElement`) | Event-driven (not polled), gets window titles |
| AI | Gemini Flash 2.0 REST API | Post-hoc analysis only, API key stored in `UserDefaults` (personal use; Keychain was over-engineered for this threat model) |
| Target | macOS 15+ (Sequoia) | `MenuBarExtra` `.window` style + `SMAppService` + `@Observable` |
| Concurrency | Swift structured concurrency (async/await, actors) | Safe, modern, avoids data races |
| Distribution | Direct build, no App Store | Personal use; Accessibility permissions complicate App Store review |

## Locked Technical Choices

These are decided. Any change requires explicit renegotiation.

| Choice | Decision |
|---|---|
| Project location | `eagv3/week2/FocusLens/` (Xcode project lives next to this plan file) |
| Xcode project shape | Single target (app only); tests in a second target `FocusLensTests` |
| Deployment target | macOS 15 (Sequoia) |
| Host architecture | Apple Silicon only (developer machine) |
| Signing | Free Apple personal team via Xcode auto-manage; `SMAppService.register()` called idempotently on every launch |
| App Sandbox | **Disabled** (Accessibility API is incompatible with the sandbox) |
| Hardened Runtime | On (required by macOS 15 for Accessibility prompts to behave correctly) |
| Testing framework | Swift Testing (macro-based, `@Test` / `#expect`) |
| Dependency manager | Swift Package Manager (GRDB added as SPM dependency) |
| GRDB version | Latest stable 7.x |
| Gemini key source | Google AI Studio API key, stored in `UserDefaults` under key `"ai.gemini.apiKey"` (Keychain was original plan; switched to UserDefaults — acceptable for single-user personal tool) |
| Menu-bar UI pattern | `MenuBarExtra(..., isInserted:)` with `.window` style; root SwiftUI view is `MenuBarView` |
| Menu-bar icon | SF Symbol `eye` (placeholder; may revisit post-Phase 2) |
| Menu-bar refresh strategy | **Cached aggregates** — see below |
| Permission prompts | Accessibility: granted by user on their machine; app degrades gracefully if revoked |

### Menu-bar refresh strategy (locked)

No always-on timer. The menu bar content updates via exactly two triggers:

1. **On session end** (app switch / idle transition / pause) — the tracker publishes an event; an `@Observable` `TodayAggregate` store recomputes "top N apps today" and "productivity total" via a single cached query.
2. **Only while the menu is open** — `onAppear` on `MenuBarView` starts a 1Hz tick to recompute the visible "current session duration" label as `Date.now - session.startedAt`. `onDisappear` stops it.

Closed-menu CPU cost from UI refresh: **zero.** This replaces the earlier `Timer.publish(every: 60)` approach.

## Where Gemini Flash 2.0 Fits

AI is the **reporting/insights layer**, not the tracking layer. It reads your data and tells you things you wouldn't notice yourself.

### Strong Use Cases (post-session / post-day)
1. **Smart categorization** — reads window titles contextually ("YouTube — JS Conference Talk" = Learning, not Distraction)
2. **Natural language reports** — ask your data questions in plain English
3. **Proactive daily insights** — end-of-day digest surfacing patterns
4. **Weekly narrative summary** — compares trends across weeks
5. **Distraction pattern analysis** — when/why you get distracted, correlations
6. **Goal tracking with understanding** — "2h deep coding daily" — Gemini understands what counts

### Rejected Use Case
- **Session start planning** — adds friction at the moment you just want to start working. AI value comes *after* data is generated, not before.

## macOS APIs Needed

| API | Purpose | Permission Required |
|---|---|---|
| `AXUIElement` / Accessibility API | Read window titles of frontmost app | Accessibility (System Settings) |
| `NSWorkspace.shared.frontmostApplication` | Get active app (fallback, no window titles) | None |
| `NSWorkspace.didActivateApplicationNotification` | Event-driven app switch detection | None |
| `CGEventSource.secondsSinceLastEventType` | Idle time detection (seconds since last input) | None |
| `NSStatusBar` / `NSStatusItem` | Menu bar icon and menu | None |
| `SMAppService` (macOS 13+) | Launch at login | None |
| `UserNotifications` | Daily digest notifications, goal alerts | Notification permission |

**Avoided**: `CGWindowListCopyWindowInfo` (requires Screen Recording permission — worse UX than Accessibility).

## Data Model

### `activity_sessions` (Phase 1)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| app_bundle_id | TEXT NOT NULL | e.g., "com.apple.Safari" |
| app_name | TEXT NOT NULL | e.g., "Safari" |
| window_title | TEXT | Nullable if AX permission denied |
| started_at | TEXT NOT NULL | ISO 8601 |
| ended_at | TEXT | NULL while active |
| duration_seconds | REAL | Computed on end |
| is_idle | INTEGER DEFAULT 0 | 1 = idle period |

### `never_track_apps` (Phase 1, UI lands Phase 2)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| app_bundle_id | TEXT UNIQUE NOT NULL | Bundle ID to exclude from tracking entirely |
| added_at | TEXT NOT NULL | ISO 8601 |

### `categories` (Phase 2)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| name | TEXT NOT NULL | e.g., "Coding", "Communication" |
| color_hex | TEXT | For UI display |
| is_productive | INTEGER | -2 (very distracting) to +2 (very productive) |

### `category_rules` (Phase 2)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| category_id | INTEGER FK | References categories |
| match_type | TEXT | "app_bundle", "window_title_contains", "window_title_regex" |
| match_value | TEXT | Pattern to match |
| priority | INTEGER | Higher priority wins |

### `ai_categorizations` (Phase 3)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| activity_session_id | INTEGER FK | References activity_sessions |
| category_id | INTEGER FK | References categories |
| sub_category | TEXT | e.g., project name |
| confidence | REAL | 0.0 to 1.0 |
| reasoning | TEXT | Why Gemini chose this |

### `daily_summaries` (Phase 3)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| date | TEXT NOT NULL | YYYY-MM-DD |
| summary_markdown | TEXT | Gemini-generated narrative |
| raw_stats_json | TEXT | Cached aggregated stats |
| generated_at | TEXT | Timestamp |

### `goals` (Phase 4)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| description | TEXT | Human-readable goal |
| category_id | INTEGER FK | What category to track |
| target_minutes | INTEGER | Daily target |
| goal_type | TEXT | "minimum" or "maximum" |
| is_active | INTEGER | On/off |

### `focus_sessions` (Phase 5)
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| started_at | TEXT NOT NULL | When focus session began |
| ended_at | TEXT | When it ended |
| planned_minutes | INTEGER | Intended duration |
| blocked_apps_json | TEXT | JSON array of bundle IDs |
| label | TEXT | Optional user label |

## Cross-Cutting Concerns (locked before Phase 1)

See "Locked Technical Choices" above for project-shape decisions. These are the behavioral / engineering-hygiene rules:

| Concern | Decision |
|---|---|
| Logging | `os.Logger`, subsystem `com.focuslens.app`. Window titles logged at `.debug` only, never `.info` (PII) |
| Never-track list | Schema lands in Phase 1 (`never_track_apps`) even though UI ships in Phase 2 — prevents backfilling PII |
| DB migrations | GRDB `DatabaseMigrator` at `DatabaseManager` init; each phase adds a numbered migration, never edits past ones |
| Concurrency | `DatabasePool` (concurrent reads during writes) — not `DatabaseQueue`; `ActivityTracker` is an `actor` |
| PII in prompts | Never send full window titles to Gemini: truncate to ≤ 120 chars and strip obvious PII patterns (emails, 16-digit numbers); responses constrained by JSON schema |
| Menu-bar refresh | No always-on timer; cached aggregate invalidated on session end; 1Hz duration tick only while menu is open |

## Implementation Phases

### Phase 1: Silent Tracker (MVP)

**Goal**: Menu bar app that silently records every app/window switch and shows today's usage.

**What's in**:
- Activity tracking via `NSWorkspace.didActivateApplicationNotification` + `AXUIElement` for window titles
- Idle detection — poll every 30s, mark idle after 10 min of no input
- Accessibility permission handling with graceful degradation (app-name-only if denied)
- Menu bar UI via `MenuBarExtra` (`.window` style) — SF Symbol `eye` icon, current app row, today's top 10 apps ranked by time
- Pause/resume toggle (SwiftUI `Toggle` inside `MenuBarView`)
- Launch at login via `SMAppService` (idempotent `register()` on every launch)
- Discard sessions < 2 seconds (accidental Cmd+Tab pass-throughs)
- `never_track_apps` table + filter in tracker (UI comes Phase 2)

**What's out**: categories, charts, AI, goals, blocking, settings window.

**Key implementation details**:
- `ActivityTracker` as a Swift `actor` for thread safety
- Database at `~/Library/Application Support/FocusLens/focuslens.db`
- `TodayAggregate` — an `@Observable` cache of "top N apps today" + running totals, recomputed only when a session closes (not on a timer)
- "Current session duration" label is computed at render time as `Date.now - session.startedAt`; a 1Hz tick driven by `MenuBarView.onAppear`/`.onDisappear` keeps it visibly live *only while the menu is open*
- On app switch: close previous session (set `ended_at`, compute `duration_seconds`), open new session, emit event that invalidates `TodayAggregate`
- Handle edge case: notification fires but app is the same (space switches) — no session boundary
- Sleep/wake: observe `NSWorkspace.willSleepNotification` / `didWakeNotification` to close and reopen sessions cleanly
- Crash recovery: on launch, find any session with NULL `ended_at` and finalize with `min(now, startedAt + maxReasonableSession)`

**Success criteria**:
- [ ] Tracks app switches with window titles
- [ ] Idle periods detected and recorded separately
- [ ] Today's usage visible in menu bar dropdown
- [ ] Pause/resume works
- [ ] Launch at login works
- [ ] < 1% CPU, < 50MB RAM (measured via Instruments)
- [ ] Survives sleep/wake: open session closed cleanly, new session after wake
- [ ] Survives app crash mid-session: WAL recovers, open session gets reasonable `ended_at` on relaunch
- [ ] Quit during active session finalizes the session (no zombie rows)
- [ ] Apps in `never_track_apps` produce zero rows regardless of activation
- [ ] Unit tests for `ActivityTracker` state transitions and `IdleDetector` thresholds

**Effort**: 1-2 weekends

---

### Phase 2: Manual Categories + Dashboard

**Goal**: Transform raw data into meaningful categories with visual charts.

**What's in**:
- Category system with productivity ratings (-2 to +2)
- Rule-based categorization (app bundle match, window title contains/regex)
- Dashboard window with: donut chart by category, timeline bar, productivity score (0-100), app rankings
- Settings window (idle threshold, minimum session duration, category management, never-track list UI)
- Batch recategorization when rules change
- Default categories: Coding, Communication, Browsing, Design, Learning, Entertainment, Utilities

**Success criteria**:
- [ ] Categories with rules can be created, edited, deleted
- [ ] Changing a rule recategorizes 30 days of historical data in < 3 seconds
- [ ] Dashboard shows daily breakdown with charts (donut + timeline + rankings)
- [ ] Productivity score computed and displayed (0–100)
- [ ] Never-track list manageable from Settings
- [ ] Unit tests for rule matching precedence (priority, regex, bundle-id exact match)

**Effort**: 1-2 weekends | Depends on: Phase 1

---

### Phase 3: Gemini AI Integration

**Goal**: Smart categorization, natural language queries, and automated digests.

**Prerequisite**: ~1 week of data from Phases 1-2.

**What's in**:
- `GeminiClient` — thin REST wrapper, API key in `UserDefaults`, rate limiting (10 req/min), cost tracking
- Smart categorization — batch uncategorized (app, window_title) pairs to Gemini, constrained to existing categories via response schema. Accept/reject → suggestions become rules (learning loop)
- Natural language queries — pre-aggregate data in SQLite, send summary to Gemini (NEVER let Gemini generate SQL)
- Daily digest — auto at 6 PM, macOS notification, compares to 7-day average
- Weekly narrative — Friday summary with trend comparison

**Key design principle**: AI is purely additive. App tracks and categorizes via rules without network. AI features gracefully degrade to "offline" state.

**Estimated cost**: < $0.01/month (Flash pricing + small payloads)

**Success criteria**:
- [ ] AI categorization accuracy > 80% on held-out sample of 50 manually-labeled sessions
- [ ] Accept/reject feedback loop persists new rules that match going forward
- [ ] NL queries return grounded answers (all numbers traceable to SQLite aggregate)
- [ ] Daily/weekly digests auto-generated on schedule and store in `daily_summaries`
- [ ] App fully functional when offline: boots with no API key in UserDefaults, AI tabs show "Not configured"; no crashes, no retries
- [ ] Window titles are truncated to ≤ 120 chars and stripped of obvious PII patterns (emails, 16-digit numbers) before being sent to Gemini
- [ ] Rate limiter refuses silently (no exception) when budget exceeded

**Effort**: 2-3 weekends | Depends on: Phase 2 + data

---

### Phase 4: Goals, Alerts, and Proactive Nudges

**What's in**:
- Goal setting: "At least 2h Coding daily", "At most 30m Social Media daily"
- Real-time alerts: warn at 80%/100% of maximums, nudge at 4 PM if minimums behind
- Distraction pattern analysis (Gemini): context-switch correlations, distraction spirals, time-of-day patterns
- Proactive suggestions: gentle notification before historically distracted periods

**Success criteria**:
- [ ] Goals can be created, edited, deactivated, deleted
- [ ] Threshold alerts fire exactly once per crossing per day (no spam on bouncing totals near threshold)
- [ ] Minimum-behind nudge fires at configured time only if not met, respects `is_active`
- [ ] Distraction analysis produces ≥ 3 patterns given ≥ 14 days of data
- [ ] Respects macOS Do Not Disturb / Focus modes (checked via `UNUserNotificationCenter`)
- [ ] Goal progress visible on dashboard with progress rings

**Effort**: 1-2 weekends | Depends on: Phase 3

---

### Phase 5: Focus Sessions + App Blocking

**What's in**:
- Focus timer (25/50/90 min) from menu bar, icon changes during session
- Soft app blocking: `NSRunningApplication.activate` back to previous app + overlay message
- Focus analytics: completion rate, on-task percentage

**Success criteria**:
- [ ] Focus timer starts, pauses, resumes, completes; menu-bar icon reflects state
- [ ] Blocked-app activation bounces back to previous allowed app within 500ms
- [ ] No infinite bounce loop if both "from" and "to" apps are on the block list (fallback to Finder)
- [ ] Session logged with on-task % even if interrupted mid-session
- [ ] Completion rate + on-task % visible in a Focus Sessions view
- [ ] Notification on session completion; Do Not Disturb respected

**Effort**: 1-2 weekends | Depends on: Phase 2 (Phase 4 optional)

---

### Phase 6: Search + Data Management

**What's in**:
- Full-text search via SQLite FTS5 across window titles, app names, summaries
- CSV/JSON export
- Data retention: auto-delete raw sessions older than N months, keep summaries
- Daily highlights: optional one-line journal entry, feeds into AI narratives

**Success criteria**:
- [ ] FTS5 search returns results in < 100ms on 90 days of sessions
- [ ] CSV and JSON exports round-trip: export → re-import yields identical row counts and aggregates
- [ ] Retention job runs idempotently on a schedule, deletes per policy, preserves `daily_summaries`
- [ ] Daily highlights feed into the next weekly narrative (verified by inspecting prompt payload)
- [ ] Retention thresholds configurable from Settings

**Effort**: 1 weekend | Depends on: Phase 2

---

## Project Structure

Xcode project root: `eagv3/week2/FocusLens/FocusLens.xcodeproj`. Source lives in `eagv3/week2/FocusLens/FocusLens/` alongside `FocusLens-Plan.md` in `eagv3/week2/`.

```
eagv3/week2/
├── FocusLens-Plan.md                   # this file
└── FocusLens/                          # Xcode project root
    ├── FocusLens.xcodeproj
    ├── FocusLens/                      # app target source
    │   ├── App/
    │   │   ├── FocusLensApp.swift          # @main, MenuBarExtra(.window)
    │   │   ├── LoginItemManager.swift      # SMAppService wrapper
    │   │   └── AppConstants.swift          # Configurable thresholds
    │   ├── Models/
    │   │   ├── ActivitySession.swift
    │   │   ├── Category.swift              # Phase 2
    │   │   ├── CategoryRule.swift          # Phase 2
    │   │   ├── Goal.swift                  # Phase 4
    │   │   └── FocusSession.swift          # Phase 5
    │   ├── Storage/
    │   │   ├── DatabaseManager.swift       # GRDB pool, migrations
    │   │   ├── ActivitySessionStore.swift
    │   │   ├── NeverTrackStore.swift       # Phase 1 schema, Phase 2 UI
    │   │   ├── CategoryStore.swift         # Phase 2
    │   │   └── Migrations/
    │   │       ├── Migration001_Sessions.swift
    │   │       ├── Migration002_Categories.swift
    │   │       └── Migration003_AI.swift
    │   ├── Tracking/
    │   │   ├── ActivityTracker.swift       # Core engine (actor)
    │   │   ├── IdleDetector.swift
    │   │   ├── PermissionManager.swift
    │   │   ├── CategorizationEngine.swift  # Phase 2
    │   │   ├── GoalMonitor.swift           # Phase 4
    │   │   └── AppBlocker.swift            # Phase 5
    │   ├── AI/
    │   │   ├── GeminiClient.swift          # Phase 3
    │   │   ├── AICategorizer.swift         # Phase 3
    │   │   ├── DailyDigestGenerator.swift  # Phase 3
    │   │   ├── WeeklyNarrativeGenerator.swift # Phase 3
    │   │   └── DistractionAnalyzer.swift   # Phase 4
    │   ├── UI/
    │   │   ├── MenuBarView.swift           # SwiftUI root inside MenuBarExtra(.window)
    │   │   ├── TodayAggregate.swift        # @Observable cache invalidated on session end
    │   │   ├── DashboardView.swift         # Phase 2
    │   │   ├── DashboardCharts.swift       # Phase 2
    │   │   ├── TimelineView.swift          # Phase 2
    │   │   ├── SettingsView.swift          # Phase 2
    │   │   ├── CategorySettingsView.swift  # Phase 2
    │   │   ├── QueryView.swift             # Phase 3
    │   │   ├── GoalsView.swift             # Phase 4
    │   │   ├── FocusSessionView.swift      # Phase 5
    │   │   └── SearchView.swift            # Phase 6
    │   └── Utilities/
    │       ├── DateFormatters.swift
    │       ├── DurationFormatter.swift
    │       └── DateUtils.swift             # DB date formatting helpers
    └── FocusLensTests/                 # Swift Testing target
        ├── ActivityTrackerTests.swift
        ├── IdleDetectorTests.swift
        └── DurationFormatterTests.swift
```

## Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| User never grants Accessibility permission | HIGH | Degrade to app-only tracking; persistent gentle reminder |
| Some apps don't expose window titles via AX (Electron, games) | MEDIUM | Catch per-query, fall back to app name, log failures |
| Sensitive window titles (passwords, banking) | MEDIUM | `never_track_apps` list; all data local; titles truncated + PII-scrubbed before any Gemini call |
| Gemini API changes or deprecated | LOW | Abstract behind `AIProvider` protocol; swappable to Claude/local LLM |
| Gemini prompt injection via adversarial window titles | LOW | Constrain Gemini responses to a JSON schema; reject freeform category names |
| SQLite corruption from crash during write | LOW | GRDB uses WAL mode (crash-safe); daily `.bak` backup |
| Menu-bar refresh causing DB reads every minute | LOW | Cache "today top 10" in an `@Observable` store, invalidate only on session end |
| Battery drain | LOW | Event-driven tracking + 30s idle poll is negligible; profile with Instruments |

## Critical Path

```
Phase 1 (Silent Tracker) → Phase 2 (Categories + Dashboard) → Phase 3 (Gemini AI)
                                        ↓
                              Phase 4 (Goals)     — needs Phase 3
                              Phase 5 (Focus)     — needs Phase 2 only
                              Phase 6 (Search)    — needs Phase 2 only
```

Total estimated effort: 7-12 weekends over 2-3 months of casual development.

## Phase Gating Rule

**No phase begins until every checkbox in the prior phase's "Success criteria" is ticked and verified.** A short checklist markdown (`phase-N-verification.md`) will be produced at the end of each phase for sign-off.
