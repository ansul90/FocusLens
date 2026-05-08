# Demo script

A demo script that lands every assignment requirement visibly. Total runtime ~6 minutes once Ollama is warm.

The server now exposes **8 tools** (4 data + 1 internet + 1 local-CRUD + 2 UI) and the dashboard is served by a real **FastAPI/uvicorn process at `http://127.0.0.1:8765`**, not a `file://` URL. Verdict buttons in the dashboard PATCH the database live, which is the strongest CRUD moment.

## Pre-demo prep (off-camera, 1 min)

```bash
cd focuslens-mcp

# 1. Reset insights so the demo starts from a clean state
sqlite3 "$HOME/Library/Application Support/FocusLens/focuslens.db" \
  "DELETE FROM app_insights;"

# 2. Warm up gemma4 so the first iteration isn't a 30-60s cold load
ollama run gemma4:26b-a4b-it-q4_K_M "ready" >/dev/null 2>&1 &

# 3. Confirm DB and the (now-empty) app_insights table exist
sqlite3 "$HOME/Library/Application Support/FocusLens/focuslens.db" \
  "SELECT COUNT(*) FROM app_insights;"

# 4. Free port 8765 if a previous run left uvicorn lingering
lsof -ti:8765 | xargs -r kill -9
```

Open two terminal panes side by side — left for commands, right watching the DB live:

```bash
# right pane — polls app_insights every 2s
watch -n2 'sqlite3 "$HOME/Library/Application Support/FocusLens/focuslens.db" \
  "SELECT app_name, verdict FROM app_insights ORDER BY updated_at DESC"'
```

## On-camera demo (~6 min)

### Step 1 — Show the architecture (30s)

Open `README.md` in the repo. Point at the ASCII diagram. One sentence each:

> *"FocusLens is the Swift app that records my activity. focuslens-mcp is a Python MCP server I wrote with eight tools — three of them externally observable (internet, local-file CRUD, UI) plus four read-only data tools and a custom report builder. host.py is one Ollama-driven MCP client that drives them; the FocusLens app itself is a second MCP client embedded in the menu bar — same server, two surfaces."*

### Step 2 — Show the 8 tools in code (45s)

```bash
grep -n "@mcp.tool" server.py
```

Output will show **8** `@mcp.tool` decorations. Map them to the assignment buckets:

> *"`web_lookup_app` is the internet tool — DuckDuckGo plus page fetch.  
> `insights_store` is the local-file CRUD — operates on the `app_insights` table in `focuslens.db`.  
> `render_report` and `show_dashboard` are both UI tools — render_report builds a one-shot chart/table page from sections the LLM composes; show_dashboard launches the full interactive dashboard.  
> The remaining four — list_top_apps, get_productivity_score, get_category_breakdown, get_hourly_breakdown — are read-only data tools the agent uses to gather facts before it acts."*

### Step 3 — Show STDIO transport, no SSE (15s)

```bash
grep -n "mcp.run" server.py
```

> *"`mcp.run()` with no args means STDIO — the host spawns the server as a subprocess and pipes JSON-RPC over stdin/stdout. No port for the MCP protocol itself. The dashboard's HTTP server on port 8765 is a separate channel — that's the rendered UI surface, not the MCP transport."*

### Step 4 — Run the demo prompt (~2 min)

Right pane: the `watch` command from prep step (currently shows 0 rows — will fill as the agent runs).

Left pane:

```bash
uv run python host.py -v
```

Narrate as the trace prints:

- **Iteration 1** → *"Agent calls `list_top_apps` first. That's reading FocusLens's SQLite DB."*
- **Iteration 2** → *"Calls `insights_store(list)` to see what's already saved — table is empty, returns no rows."*
- **Iterations 3-8** → *"For each top app, the agent does web_lookup → upsert. Watch the right pane — `app_insights` is being created and grown live."*
- **Last iteration** → *"`show_dashboard` returns an `http://127.0.0.1:8765/?days=7` URL. Host auto-opens browser."*

When the browser opens, the **Prefab dashboard** renders. Show: cards with each app, the verdict badge, the summary the agent wrote, and the source URLs.

### Step 5 — Demonstrate live UI → DB → Swift-app loop (45s) ⭐

**This is the strongest CRUD moment — a UI-driven write that lands in the same DB the Swift app reads.**

In the dashboard, click a verdict button — e.g. flip Chrome from *neutral* to *distracting*.

> *"That click PATCHed `/api/insight/Google%20Chrome` on the dashboard's FastAPI server. Two writes happened atomically: app_insights was upserted, AND a matching row was added to `category_rules` — which is one of FocusLens's own tables. The Swift app picks up that rule on its next refresh — same single source of truth."*

Prove both writes from the left pane:

```bash
sqlite3 "$HOME/Library/Application Support/FocusLens/focuslens.db" \
  "SELECT app_name, verdict, updated_at FROM app_insights WHERE app_name LIKE '%Chrome%';
   SELECT match_value, category_id FROM category_rules ORDER BY id DESC LIMIT 1;"
```

The right pane's `watch` already shows `updated_at` shifting while `created_at` stays — that proves a real upsert (not an insert).

### Step 6 — Custom report (render_report tool, ~1 min)

Same MCP server, different UI tool — the agent composes a fresh visualization on the fly.

```bash
uv run python host.py "Show me a chart comparing my productivity scores for each of the last 3 days, with KPIs above the chart." -v
```

Narrate:

- *"Agent calls `get_productivity_score` three times — once per day."*
- *"Then calls `render_report` with a list of sections it composed: three KPI cards plus a bar_chart. The host opens `http://127.0.0.1:8765/report/{id}`."*

> *"This is the part I'm most happy with — the LLM is choosing the visualization shape. Same server, same uvicorn, but render_report is a generic Prefab-based composer driven entirely by the agent's structured output."*

### Step 7 — Same server, second client (in-app) (30s)

Open the FocusLens menu bar app → Dashboard window → **Ask FocusLens** tab.

Type:

> *"What were my most distracting apps this week?"*

Then ask:

> *"Show me a chart of my productivity scores for the last 3 days."*

Narrate the two questions differently:

> *"The first question hits four native Swift tools — current_time, get_activity, query_sessions, and classify_app — backed by direct GRDB reads into the same focuslens.db. No MCP round-trip, no Python process, sub-second response.*
>
> *The second question triggers render_report, which IS an MCP call. FocusLens spawns server.py as a subprocess — same server.py from this directory — pipes the tool call over stdin/stdout, and the agent gets back a localhost URL it can open. That's the second MCP client: host.py is the CLI client, MCPClient.swift is the in-app client. Same server, two surfaces, render_report shared between both."*

## Talking points to hit during the demo

| Requirement | Sentence to drop |
|---|---|
| Internet tool | *"DuckDuckGo HTML endpoint, no API key, then BeautifulSoup pulls title and meta description."* |
| Local file CRUD | *"All four operations — list, get, upsert, delete — on the `app_insights` table in `focuslens.db`. Plus the dashboard's PATCH endpoint also writes `category_rules`. One DB, one source of truth."* |
| Prefab UI (×2) | *"`show_dashboard` returns the persistent dashboard at localhost:8765. `render_report` returns ephemeral, agent-composed report pages at the same origin. Both are Prefab-rendered server-side."* |
| MCP / STDIO | *"Standard MCP over STDIO — could swap Claude Desktop in tomorrow without changing a line of server code."* |
| Two MCP clients | *"`host.py` is the CLI client — uses all 8 MCP tools. `MCPClient.swift` is the in-app client — registers only `render_report` from MCP; data queries use 4 native Swift tools instead. Same server.py, two different consumers."* |
| FocusLens integration | *"Server is read-only on activity_sessions and categories. Writes are scoped to app_insights and category_rules. The Swift app and the agent never step on each other."* |

## Suggested 30-second demo prompt for the slide / readme

> *"Look at my top apps from FocusLens. For any without a saved verdict, search the web to figure out what the app does and whether it's productive. Save a verdict for each. Then show me the dashboard."*

This single sentence forces all three externally-observable tools (internet, local CRUD, UI) and the Prefab dashboard in the cleanest sequence — drop it as a screenshot in your writeup.

For the render_report moment, this prompt works:

> *"Compare my productivity scores for each of the last 3 days. Show me a chart with KPIs."*

## If the demo flakes mid-recording

Failure modes to plan for:

| If… | Do this |
|---|---|
| Agent hangs on iteration 1 | gemma4 cold-loaded — kill, re-run; warmup should have avoided this |
| Agent never calls `show_dashboard` | bump prompt to *"…and you MUST call show_dashboard at the end."* |
| DDG rate-limits | re-run after 60s; or temporarily set `max_results=1` in `web_lookup_app` |
| Dashboard renders blank | check that `focuslens.db` has recent sessions; the Swift app must have run today |
| Port 8765 already bound | `lsof -ti:8765 \| xargs kill -9` and re-run — the prep step covers this |
| Verdict button click does nothing | check the FastAPI server logs; the host process must still be alive (the uvicorn thread dies with it) |
| `render_report` returns 404 in browser | report TTL is 1 hour — re-run the prompt to regenerate |
| Ask FocusLens tab data queries return nothing | data tools are native Swift — check that `focuslens.db` has recent sessions and Ollama is running |
| Ask FocusLens `render_report` fails | this IS an MCP call — check that `uv` is on PATH (`AppConstants.MCP.uvPath`); the Swift client spawns `uv run python server.py` |
