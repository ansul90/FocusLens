# FocusLens — Issue Tracker

Reviewed: **2026-05-07**  
Project state: **entering Phase 4** (cleanup complete; 14 issues resolved)

---

## Priority legend

| Priority | Meaning |
|---|---|
| **P0 — Critical** | Can crash, silently corrupt data, or lose tracking sessions. Fix before the next run. |
| **P1 — High** | Wrong behaviour visible to the user; significant data quality risk. Fix this sprint. |
| **P2 — Medium** | Incorrect under specific conditions or a latent crash path. Fix before Phase 4. |
| **P3 — Low** | Code smell, maintenance debt, or minor UX polish. Fix opportunistically. |

---

## Fixed in session (2026-05-06)

| # | File | What was fixed |
|---|---|---|
| [#5](#5-agentrunner-double-truncation-produces-invalid-json) | `AgentRunner.swift` | Removed bespoke second truncation that appended `]}` blindly, corrupting JSON for non-array tools |
| [#6](#6-cgEventType-force-unwrap-in-idledetector) | `IdleDetector.swift` | Replaced `CGEventType(rawValue: ~0)!` force-unwrap with graceful fallback |
| [#18](#18-toolregistry-startup-race) | `AgentTool.swift`, `FocusLensApp.swift` | Replaced fire-and-forget async `registerDefaultTools()` with synchronous pre-populated `ToolRegistry(tools:)` initializer |
| [#7](#7-force-cast-axuielement-in-permissionmanager) | `PermissionManager.swift` | Replaced `as! AXUIElement` with safe `as? AXUIElement` guard |
| [#25](#25-browserclassifier-filters-on-both-bundle-id-list-and-category-id) | `BrowserClassifier.swift` | Removed `BrowserBundleIds.all` filter; reclassification now relies solely on `category_id = browserCategoryId` |
| [#26](#26-browserbundleidsall-duplicates-the-browser-rules-seeded-in-migration003) | `BrowserBundleIds.swift` | Deleted `BrowserBundleIds.swift` and removed Xcode project references; `ClassificationResult` struct added for richer return value |
| [#3](#3-migration004-comment-is-misleading) | `Migration004_FixAITools.swift` | Rewrote comment to accurately describe the defensive repair scenario and when the guard fires |
| [#39](#39-activitysessionstoreclose-reads-then-writes-in-two-round-trips) | `ActivitySessionStore.swift` | Replaced fetch + UPDATE with single `julianday`-based UPDATE; eliminates silent nil-duration on missing row |
| [#38](#38-fk-cascade-on-deletecategory-may-not-fire) | `DatabaseManager.swift` | Added `PRAGMA foreign_keys = ON` via `config.prepareDatabase` so FK cascade is explicit and not dependent on GRDB internals |
| [#8](#8-idledetector-timer-not-added-to-common-run-loop-mode) | `IdleDetector.swift` | Replaced `scheduledTimer` with manual `Timer` added to `RunLoop.main` in `.common` mode; idle detection now fires during menu tracking |
| [#10](#10-idledetector-has-no-sendable-or-mainactor-annotation) | `IdleDetector.swift` | Marked `@MainActor`; timer and callbacks both run on main thread, isolation now declared |
| [#9](#9-activitytracker-accesses-nsworkspace-from-actor-isolated-tasks) | `ActivityTracker.swift` | NSWorkspace access moved outside actor hops — captured on `@MainActor` before Task or via `MainActor.run` in async methods |
| [#11](#11-databasemanager-is-unchecked-sendable-without-documentation) | `DatabaseManager.swift` | Added comment explaining why `@unchecked Sendable` is safe |
| [#12](#12-todayaggregaterefreshstats-captures-non-sendable-structs-in-taskdetached) | `ActivitySessionStore.swift`, `CategoryStore.swift` | Added `Sendable` conformance to both store types |

---

## Open issues

### P0 — Critical

#### #6 CGEventType force-unwrap in IdleDetector
**Status: Fixed**  
See fixed table above.

---

#### #7 Force-cast AXUIElement in PermissionManager
**Status: Fixed**  
See fixed table above.

---

### P1 — High

#### #5 AgentRunner double-truncation produces invalid JSON
**Status: Fixed**  
See fixed table above.

---

#### #18 ToolRegistry startup race
**Status: Fixed**  
See fixed table above.

---

#### #3 Migration004 comment is misleading
**Status: Fixed**
See fixed table above.

---

#### #14 Gemini API key stored in plaintext UserDefaults
**File:** `AI/GeminiSettings.swift`, `App/AppConstants.swift`

`FocusLens-Plan.md` (locked decision, line 40) states: *"Gemini key stored in macOS Keychain under service `com.focuslens.app`"*. Reality: the key is written to `UserDefaults.standard` under the key `"ai.gemini.apiKey"` in plaintext.

For personal single-user use this is acceptable. The plan doc has been acknowledged as needing an update to reflect the decision to use UserDefaults instead of Keychain.

**Fix (option A — easy):** Update `FocusLens-Plan.md` to replace the locked Keychain requirement with the actual UserDefaults choice.  
**Fix (option B — correct):** Implement Keychain storage using `SecItemAdd` / `SecItemCopyMatching` and migrate existing keys on first launch.

---

#### #25 BrowserClassifier filters on both bundle ID list and category ID
**Status: Fixed**  
See fixed table above.

---

#### #26 `BrowserBundleIds.all` duplicates the browser rules seeded in Migration003
**Status: Fixed**  
See fixed table above.

---

### P2 — Medium

#### #8 IdleDetector timer not added to `.common` run loop mode
**Status: Fixed**
See fixed table above.

---

#### #9 ActivityTracker accesses NSWorkspace from actor-isolated tasks
**Status: Fixed**
See fixed table above.

---

#### #10 `IdleDetector` has no `Sendable` or `@MainActor` annotation
**Status: Fixed**
See fixed table above.

---

#### #11 `DatabaseManager` is `@unchecked Sendable` without documentation
**Status: Fixed**
See fixed table above.

---

#### #12 `TodayAggregate.refreshStats` captures non-`Sendable` structs in `Task.detached`
**Status: Fixed**
See fixed table above.

---

#### #22 `OllamaClient.isAvailable` prefix-matches model names
**File:** `AI/OllamaClient.swift:67–70`

Configuring `gemma4:26b-a4b-it-q4_K_M` as the model name returns `true` if the user has *any* `gemma4:*` variant installed. A subsequent `generate` call will still request the fully-qualified name, which may fail with 404 if only a different quantisation is installed — but `isAvailable` said true.

**Fix:** Perform an exact-match first, fall back to prefix-match with a logger warning.

```swift
let exactMatch = tags.models.contains { $0.name.lowercased() == settings.modelName.lowercased() }
if exactMatch { return true }
// Prefix fallback — model is present but different quantisation
let configuredBase = settings.modelName.lowercased().components(separatedBy: ":").first ?? ""
let prefixMatch = tags.models.contains {
    ($0.name.lowercased().components(separatedBy: ":").first ?? "") == configuredBase
}
if prefixMatch { logger.warning("OllamaClient: exact model '\(settings.modelName)' not found; using closest match") }
return prefixMatch
```

---

#### #23 Two conflicting tool-result truncation limits
**File:** `AI/Agent/AgentTool.swift:62`, `App/AppConstants.swift:42`

`toolJSON` truncates at `AppConstants.Agent.toolResultMaxChars` (4000 chars). The second bespoke truncation in `AgentRunner` has been removed (fix #5), so this is now the single source of truth. However, 4000 chars can still overflow an 8192-token context window when several tool results accumulate across iterations.

**Fix:** Consider reducing `toolResultMaxChars` to 2000 and documenting the context-window budget assumption.

---

#### #27 `compactToolSummary` only captures the last tool call per turn
**File:** `UI/AskViewModel.swift:134`

The rolling conversation history appended by `compactToolSummary` only reflects the last tool call in a given agent turn. If the agent calls multiple tools before returning an answer, the earlier results are lost from the history, weakening follow-up question context.

**Fix:** Collect *all* `TraceStep.toolCall` steps from the trace and concatenate their summaries.

---

#### #13 `AgentLogger` writes to `~/Desktop` on every query with no opt-out
**File:** `AI/Agent/AgentRunner.swift:318–352`

The agent log is always written to `~/Desktop/focuslens-agent-log.txt` with no preference to disable it and no rotation. For a privacy-focused app that captures window titles, writing a full conversation log to the Desktop unconditionally is a meaningful privacy concern.

**Fix:** Move log path to `~/Library/Logs/FocusLens/`, gate on a debug flag in `AppConstants`, and truncate when > 1 MB.

---

#### #28 Paused state is not reflected in the menu-bar icon
**File:** `App/FocusLensApp.swift:19`

The menu-bar icon stays `"eye"` whether tracking is active or paused — user-visible wrong behaviour.

**Fix:** Bind `systemImage` to `aggregate.isPaused ? "eye.slash" : "eye"` in the `MenuBarExtra` label.

---

#### #31 Swallowed `try?` errors in tracking-critical paths
**Files:** `Tracking/ActivityTracker.swift:66,128,144,165,178,181`

`fetchOpenSessions`, `insert`, `delete`, and `close` all use `try?`, silently discarding errors. A disk-full or DB error causes sessions to be silently dropped with no log entry.

**Fix:** Replace `try?` with `try` inside a `do/catch` that logs at `.error` level via `os.Logger`.

---

#### #35 `Color(hex:)` silently falls back to gray for non-6-digit hex strings
**File:** `UI/DashboardCharts.swift:202–217`

The initializer returns `nil` (and callers substitute `.gray`) for any hex string that isn't exactly 6 hex digits. If a user enters `#fff` or an 8-character RGBA string in the category colour field, it silently renders as gray with no validation error.

**Fix:** Add validation in the Add Category sheet that checks the entered hex string matches the 6-digit pattern before enabling the Add button. Optionally extend `Color(hex:)` to handle 3-digit and 8-digit formats.

---

#### #38 FK cascade on `deleteCategory` may not fire
**Status: Fixed**
See fixed table above.

---

#### #39 `ActivitySessionStore.close` reads then writes in two round-trips
**Status: Fixed**
See fixed table above.

---

### P3 — Low

#### #15 README has duplicated content
**File:** `README.md`

The entire "Features → Privacy" section is duplicated starting at line 245. Looks like a botched merge. The second copy also references an older feature set (no Ollama/Ask FocusLens section).

**Fix:** Delete lines 245–423 of `README.md`.

---

#### #16 README test count is stale in two places
**File:** `README.md:138` and `README.md:337`

Line 138 says "79 tests across 12 suites". Line 337 (in the duplicate section) says "53 tests across 9 suites". Both numbers reflect different points in development history.

**Fix:** After deleting the duplicate section (#15), update the single remaining count to the actual number produced by `xcodebuild test`.

---

#### #17 Hardcoded bundle ID string in four files
**Files:** `Tracking/CategorizationEngine.swift:5`, `AI/BrowserClassifier.swift:19`, `UI/TodayAggregate.swift:18`, `UI/SettingsView.swift:51`, `UI/CategorySettingsView.swift:20`

These files use the literal `"com.focuslens.app"` instead of `AppConstants.bundleIdentifier`. If the bundle ID ever changes, these won't update automatically.

**Fix:** Replace all occurrences with `AppConstants.bundleIdentifier`.

---

#### #20 Inconsistent `date` argument names across agent tools
**File:** `AI/Agent/Tools/AgentTools.swift`

`query_sessions` and `top_apps` use `date:`, `aggregate_time` uses `date_range:`, `compare_periods` uses `period_a:` / `period_b:`. The LLM must learn three different argument names for what is conceptually the same thing, increasing the chance of mis-invocation.

**Fix:** Standardise on `date` for single-day tools and `date_range` for range tools. Update the system prompt examples accordingly.

---

#### #21 `ResponseParser.extractArgs` reserved-key list is incomplete
**File:** `AI/Agent/ResponseParser.swift:59`

The set `["tool_name", "answer", "name", "thought", "reasoning"]` may not cover all reasoning-key variants emitted by local models (e.g. `"thinking"`, `"chain_of_thought"`, `"scratchpad"`). Any unlisted key leaks into the args dict, causing tool invocations with spurious parameters.

**Fix:** Expand the reserved set to cover common chain-of-thought key names, or invert the logic: only accept keys that are in the tool's declared `argsDescription`.

---

#### #29 Migration003 silently destroys user-customised categories on upgrade
**File:** `Storage/Migrations/Migration003_SeedRules.swift:10–13`

```swift
try db.execute(sql: "DELETE FROM category_rules")
try db.execute(sql: "DELETE FROM categories")
```

Any categories or rules added by the user between Migration002 and Migration003 are deleted without warning. For personal use this was a one-time pain, but it is worth documenting.

**Fix:** Add a comment explaining this is a destructive one-time migration and that the app's first-run UX should warn users before running on an existing database (relevant if ever distributed).

---

#### #30 `Category.productivityScore` maps to `is_productive` column
**File:** `Models/Category.swift:14`

The Swift property is named `productivityScore` (an integer from −2 to +2), but the database column is named `is_productive`, which reads as a boolean. This is a naming mismatch that makes SQL queries confusing.

**Fix (non-breaking):** Add a database migration that renames the column to `productivity_score`. Update all raw SQL strings that reference `is_productive`.

---

#### #33 Migration002 seeds categories that Migration003 deletes
**File:** `Storage/Migrations/Migration002_Categories.swift`

Migration002 seeds 7 categories (Coding, Communication, etc.) that Migration003 unconditionally deletes and re-seeds with different names. Migration002's seeding work is completely wasted CPU and SQL on every fresh install.

**Fix:** Move category seeding entirely into Migration003 and have Migration002 create only the schema (tables + indexes).

---

#### #34 `AppConstants.appSupportDirectory` crashes if `FileManager` fails at module load
**File:** `App/AppConstants.swift:12`

The `appSupportDirectory` static computed property is evaluated at first access and calls `FileManager.default.urls(for:in:)`. If this returns an empty array (extremely unlikely, but theoretically possible in a sandboxed/test context), `[0]` will crash.

**Fix:**
```swift
static let appSupportDirectory: URL = {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        fatalError("Could not resolve Application Support directory — cannot launch FocusLens")
    }
    return base.appendingPathComponent("FocusLens", isDirectory: true)
}()
```

---

#### #36 `DurationFormatter.shortString(from:)` is a dead alias
**File:** `Utilities/DurationFormatter.swift:9`

`shortString(from:)` calls `format(seconds:)` identically to `string(from:)`. Nothing in the codebase calls `shortString`. It is either unused API or a stub for a future compact format that was never implemented.

**Fix:** Delete `shortString(from:)` or differentiate it (e.g. `"2h"` vs `"2h 15m"`).

---

#### #37 Two different model-name fuzzy-match implementations
**Files:** `AI/OllamaClient.swift:67`, `UI/AISettingsView.swift:176`

`OllamaClient.isAvailable` and `AISettingsView.runOllamaTest` each implement their own prefix-based model-name matching, with slightly different logic. If one is updated, the other is likely to be missed.

**Fix:** Extract model-name matching into a single helper on `OllamaSettings` or `OllamaClient`. Both call sites use the result.

---

#### #40 `DateFormatters` is dead code
**File:** `Utilities/DateFormatters.swift`

`DateFormatters.iso8601` (with `withFractionalSeconds`) is defined but not called anywhere in the app. All date formatting uses inline `DateFormatter` instances with `"yyyy-MM-dd HH:mm:ss.SSS"`.

**Fix:** Delete `DateFormatters.swift` or begin using it to replace the duplicated inline formatters.

---

#### #41 `AgentTools.swift` is 512 lines — all 7 tools in one file
**File:** `AI/Agent/Tools/AgentTools.swift`

All agent tools plus shared date helpers live in a single file. This makes it harder to find individual tools and will only grow as Phase 4+ adds more tools.

**Fix:** Split into one file per tool (e.g. `CurrentTimeTool.swift`, `TopAppsTool.swift`, etc.) with shared date helpers in `AgentToolHelpers.swift`.

---

#### #44 `CategorySettingsView` discards return value of `store.insert`
**File:** `UI/CategorySettingsView.swift:181,229`

`CategoryStore.insert(_:)` returns the inserted record with its assigned `id`, but the call sites discard it. After insertion, the view calls `loadCategories()` which re-fetches everything anyway, so there's no data loss — just a `@discardableResult`-less function returning a value that goes unused.

**Fix:** Mark `CategoryStore.insert(_:Category)` and `CategoryStore.insert(_:CategoryRule)` with `@discardableResult`, or capture and use the returned value instead of re-fetching.

---

#### #45 Debug log file not `.gitignore`d
**File:** `.cursor/debug-5e5237.log` (untracked, 159 KB)

The `.cursor/` debug log is untracked but not listed in `.gitignore`. Future `git add .` runs could accidentally commit it.

**Fix:** Add to `.gitignore`:
```
.cursor/
```

---

#### #46 No Accessibility usage description in `Info.plist`
**File:** `FocusLens/Info.plist`

macOS will display a generic permission prompt for Accessibility. Adding `NSAppleEventsUsageDescription` (for AX) with a user-facing explanation of why the app needs the permission produces a better first-run experience.

**Fix:** Add:
```xml
<key>NSAccessibilityUsageDescription</key>
<string>FocusLens reads the active window title to categorise your activity. No window contents are accessed.</string>
```

---

#### #47 Network client entitlement not declared
**File:** `FocusLens/FocusLens.entitlements`

The entitlements file is empty (`<dict/>`). Under Hardened Runtime, outbound network connections require `com.apple.security.network.client`. The app currently works because the App Sandbox is disabled, but if Sandbox is ever re-enabled (e.g. for App Store distribution), Gemini and Ollama HTTP calls will fail silently.

**Fix:** Add to `.entitlements` now as documentation even if the sandbox is off:
```xml
<key>com.apple.security.network.client</key>
<true/>
```

---

## Issue count by priority

| Priority | Open | Fixed this session |
|---|---|---|
| P0 | 0 | 2 (#6, #7) |
| P1 | 1 (#14) | 5 (#3, #5, #18, #25, #26) |
| P2 | 7 (#13, #22, #23, #27, #28, #31, #35) | 7 (#8, #9, #10, #11, #12, #38, #39) |
| P3 | 17 (#15–17, #20–21, #29–30, #33–34, #36–37, #40–41, #44–47) | 0 |
| **Total** | **25** | **14** |
