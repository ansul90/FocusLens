# focuslens-mcp

A Python project that augments [FocusLens](../FocusLens) with eight MCP tools
driven by a local Ollama agent. The agent reads your activity data from FocusLens's
SQLite DB, generates plain-English day summaries, saves verdicts to the same DB,
and renders an interactive Prefab dashboard in your browser.

```
┌──────────────────────────────────────┐
│  FocusLens.app (Swift)               │
│    writes activity_sessions,         │
│    categories, category_rules        │
│    ~/Library/Application Support/    │
│    FocusLens/focuslens.db            │
└─────────────┬──────────────┬─────────┘
              │ read-only    │ reads app_insights
              ↓              │ (Ask FocusLens in-app)
┌─────────────────────────────────────────┐
│  focuslens-mcp (this dir)               │
│                                         │
│  host.py  ── Ollama agent loop (CLI)    │
│     │                                   │
│     │ stdio (JSON-RPC / MCP)            │
│     ↓                                   │
│  server.py  ── FastMCP STDIO server     │
│     ├─ list_top_apps           (data)   │
│     ├─ get_productivity_score  (data)   │
│     ├─ get_category_breakdown  (data)   │
│     ├─ get_hourly_breakdown    (data)   │
│     ├─ summarize_day           (Ollama) │
│     ├─ insights_store          (CRUD)   │
│     ├─ render_report           (UI)     │
│     └─ show_dashboard          (UI)     │
│          │                              │
│          ↓ (via web_server.py)          │
│     FastAPI/uvicorn @ localhost:8765    │
│       GET  /           → dashboard     │
│       GET  /report/:id → custom report │
│       PATCH /api/insight/:app → upsert │
│                                         │
│  MCPClient.swift also spawns server.py  │
│  for the in-app Ask FocusLens feature  │
└─────────────────────────────────────────┘
```

## Setup

```bash
# from the focuslens-mcp/ directory
uv sync

# requires Ollama running with the model FocusLens already uses
ollama pull gemma4:26b-a4b-it-q4_K_M     # ~17 GB, only if not already pulled
```

You also need FocusLens to have run at least once (so `focuslens.db` exists).

## Running

```bash
# default demo prompt (summarizes last 3 days, shows dashboard)
uv run python host.py

# custom prompt
uv run python host.py "Summarize yesterday for me."

# custom report prompt
uv run python host.py "Compare my productivity scores for the last 3 days and show a chart."

# verbose (traces every tool call)
uv run python host.py -v

# different model
FOCUSLENS_MODEL=llama3.1:8b uv run python host.py
```

When the agent calls `show_dashboard`, the host opens `http://127.0.0.1:8765` in
your default browser. The dashboard is **interactive** — clicking a verdict button
on any app card PATCHes the database immediately and reloads the page.

When the agent calls `render_report`, the host opens an ephemeral page at
`http://127.0.0.1:8765/report/{id}` (expires after 1 hour).

## The MCP tools

### Data tools (read-only)

| Tool | What it does |
|---|---|
| `list_top_apps(days, limit)` | Top apps by time from `focuslens.db`. Returns app name, bundle ID, total seconds, session count, and current category. |
| `get_productivity_score(start, end)` | Weighted 0–100 score + seconds broken down by tier (−2 very distracting → +2 very productive). |
| `get_category_breakdown(start, end)` | Seconds per category for a date range. |
| `get_hourly_breakdown(start, end)` | Activity per hour with dominant productivity tier. |

### Action tools

| Tool | What it does |
|---|---|
| `summarize_day(date)` | Generates a 2-3 paragraph plain-English narrative of a single day via local Ollama. Returns stats + narrative; degrades gracefully if Ollama is unreachable. |
| `insights_store(operation, ...)` | CRUD on the `app_insights` table inside `focuslens.db`. Operations: `list`, `get`, `upsert`, `delete`. |

### UI tools

| Tool | What it does |
|---|---|
| `render_report(title, sections)` | Compose a custom visual page from agent-structured sections (KPI, bar_chart, table, text). Returns a URL to an ephemeral page at `localhost:8765/report/{id}`. |
| `show_dashboard(days)` | Launch the interactive dashboard at `http://127.0.0.1:8765`. Verdict buttons on each card write both `app_insights` and `category_rules` in `focuslens.db`. |

## Why this design

- **Single source of truth.** Insights live in an `app_insights` table inside `focuslens.db` alongside `activity_sessions` and `categories`. The Swift app ignores tables it doesn't know about; GRDB only runs the migrations it registered.
- **Activity queries are read-only.** Only `app_insights` and `category_rules` are written by the Python layer — no risk of corrupting Swift-owned session rows.
- **STDIO transport for MCP.** `host.py` spawns `server.py` as a subprocess and pipes JSON-RPC over stdin/stdout. No port for the MCP protocol itself. The HTTP server on port 8765 is a separate channel that backs the rendered UI surfaces only.
- **Two MCP clients, one server.** `host.py` (CLI) and `FocusLens/AI/MCP/MCPClient.swift` (in-app Ask FocusLens) both spawn `server.py` independently. Keeping the server stateless means both clients get a consistent view without coordination.
- **Prefab dashboard is a separate surface from FocusLens's native dashboard.** This isn't a replacement — it's an enrichment view that complements the Swift UI, adds interactive verdicting, and supports custom agent-generated reports.
- **Same Ollama model FocusLens uses.** No extra weights to download; both surfaces share one resident model.

## Files

```
focuslens-mcp/
├── pyproject.toml      # uv-managed deps
├── server.py           # FastMCP STDIO server — 8 tools (4 data, summarize_day, insights_store, render_report, show_dashboard)
├── host.py             # Ollama agent loop + MCP client + browser opener (CLI)
├── web_server.py       # FastAPI/uvicorn dashboard server on localhost:8765
├── prefab_app.py       # interactive dashboard layout (show_dashboard)
├── prefab_report.py    # custom report layout (render_report)
├── report_spec.py      # Pydantic schema for render_report sections
├── db.py               # read-only SQLite helpers (sessions, scores, hourly)
├── insights.py         # CRUD helpers for app_insights table in focuslens.db
└── summarize.py        # Ollama-backed narrative generator for summarize_day
```
