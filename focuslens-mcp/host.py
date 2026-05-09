"""Ollama-driven MCP host CLI.

Spawns server.py via STDIO, discovers its tools, and runs an agent loop with
a local Ollama model. The agent decides tool calls; the host dispatches them
through the MCP client and feeds results back. When show_dashboard returns a
file:// URL, the host opens it in the default browser.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import sys
import webbrowser
from pathlib import Path
from typing import Any

import ollama
from fastmcp import Client

log = logging.getLogger("focuslens-host")

DEFAULT_MODEL = os.environ.get("FOCUSLENS_MODEL", "gemma4:26b-a4b-it-q4_K_M")
MAX_ITERATIONS = 24
SERVER_SCRIPT = Path(__file__).parent / "server.py"

SYSTEM_PROMPT = """You are an assistant attached to FocusLens, a macOS app
that tracks the user's app and browser activity.

## Available tools

Data tools (call these to fetch activity data):
  - list_top_apps(days, limit)          → top apps by time
  - get_productivity_score(start, end)  → 0-100 score + tier breakdown
  - get_category_breakdown(start, end)  → seconds per category
  - get_hourly_breakdown(start, end)    → activity per hour with dominant tier
  - summarize_day(date)                 → Ollama-generated narrative for a single day
  Dates are always YYYY-MM-DD strings.

Storage tools:
  - insights_store(operation, ...)      → CRUD on saved app verdicts

UI tools (always call at most once, at the end):
  - render_report(title, sections)      → compose a custom chart/table page, returns URL
  - show_dashboard(days)                → open the full interactive dashboard, returns URL

## When to use render_report vs show_dashboard

Use render_report when the user asks for a specific chart, custom analysis,
comparison, or visual summary. Pass the data you fetched as sections.

Use show_dashboard when the user wants an overview of all their activity,
or wants to correct app verdicts.

## render_report section types

  {"type": "kpi",       "label": "...", "value": "...", "description": "...",
                        "trend": "up"|"down"|"neutral",
                        "trend_sentiment": "positive"|"negative"|"neutral"}
  {"type": "bar_chart", "title": "...",
                        "data": [{"label": "App", "value": 3600, "tier": 2}]}
  {"type": "table",     "title": "...", "headers": [...], "rows": [[...]]}
  {"type": "text",      "content": "..."}

KPI sections are grouped into a grid row automatically.
tier on bar_chart data: -2=very distracting, -1=distracting, 0=neutral,
                         1=productive, 2=very productive (controls bar colour).

## Summarize workflow (when user asks for a day summary or journal)

1. Call summarize_day(date) for the target day. It returns stats + narrative.
2. Relay the narrative to the user. Optionally call render_report with the stats.
3. Stop calling tools.

## Custom analysis workflow (when user asks for charts/insights)

1. Call the relevant data tool(s) to fetch what you need.
2. Call render_report with the fetched data shaped into sections.
3. Reply briefly with one sentence. Stop calling tools.

Be concise. Verdict reasoning: tools that build/communicate/learn are
productive; entertainment/social-media browsing is distracting; chat and
email are usually neutral.
"""


def _mcp_tool_to_ollama(tool: Any) -> dict:
    """Convert an MCP Tool object into Ollama's expected tool format."""
    schema = tool.inputSchema or {"type": "object", "properties": {}}
    return {
        "type": "function",
        "function": {
            "name": tool.name,
            "description": tool.description or "",
            "parameters": schema,
        },
    }


def _tool_result_to_text(result: Any) -> str:
    """Coerce a CallToolResult into a JSON string the model can read."""
    if hasattr(result, "structured_content") and result.structured_content is not None:
        try:
            return json.dumps(result.structured_content, ensure_ascii=False)
        except (TypeError, ValueError):
            pass
    if hasattr(result, "content") and result.content:
        parts = []
        for c in result.content:
            text = getattr(c, "text", None)
            if text:
                parts.append(text)
        if parts:
            return "\n".join(parts)
    return str(result)


_dashboard_url: str | None = None


_URL_TOOLS = {"show_dashboard", "render_report"}


def _maybe_open_dashboard(tool_name: str, raw_result: str) -> None:
    global _dashboard_url
    if tool_name not in _URL_TOOLS:
        return
    try:
        data = json.loads(raw_result)
    except json.JSONDecodeError:
        return
    url = data.get("url") if isinstance(data, dict) else None
    if url:
        _dashboard_url = url
        log.info("opening %s: %s", tool_name, url)
        webbrowser.open(url)


async def run_agent(prompt: str, model: str, verbose: bool) -> None:
    async with Client(str(SERVER_SCRIPT)) as mcp:
        tools = await mcp.list_tools()
        ollama_tools = [_mcp_tool_to_ollama(t) for t in tools]
        if verbose:
            log.info("connected. %d tools: %s", len(tools), [t.name for t in tools])

        messages: list[dict] = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ]

        for iteration in range(1, MAX_ITERATIONS + 1):
            if verbose:
                log.info("iteration %d → %s", iteration, model)
            resp = ollama.chat(model=model, messages=messages, tools=ollama_tools)
            msg = resp["message"]
            messages.append(_normalize_message(msg))

            tool_calls = msg.get("tool_calls") or []
            if not tool_calls:
                content = (msg.get("content") or "").strip()
                if content:
                    print("\n" + content)
                break

            for call in tool_calls:
                fn = call["function"]
                name = fn["name"]
                args = fn.get("arguments") or {}
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except json.JSONDecodeError:
                        args = {}
                if verbose:
                    log.info("→ tool call: %s(%s)", name, _truncate(args))
                try:
                    result = await mcp.call_tool(name, args)
                    text = _tool_result_to_text(result)
                except Exception as exc:
                    text = json.dumps({"error": str(exc)})
                if verbose:
                    log.info("← %s", _truncate(text, 200))
                _maybe_open_dashboard(name, text)
                messages.append({"role": "tool", "content": text, "name": name})

        else:
            log.warning("hit max iterations (%d); stopping", MAX_ITERATIONS)

        if _dashboard_url:
            print(f"\nDashboard live at {_dashboard_url}")
            print("Press Ctrl+C to stop the server.")
            try:
                while True:
                    await asyncio.sleep(1)
            except (asyncio.CancelledError, KeyboardInterrupt):
                pass


def _normalize_message(msg: Any) -> dict:
    """Ollama may return Pydantic-ish objects; coerce to a plain dict."""
    if isinstance(msg, dict):
        out = dict(msg)
    else:
        out = {
            "role": getattr(msg, "role", "assistant"),
            "content": getattr(msg, "content", "") or "",
        }
        tcs = getattr(msg, "tool_calls", None)
        if tcs:
            out["tool_calls"] = [
                {
                    "function": {
                        "name": tc.function.name,
                        "arguments": dict(tc.function.arguments or {}),
                    }
                }
                for tc in tcs
            ]
    return out


def _truncate(value: Any, n: int = 120) -> str:
    s = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, default=str)
    return s if len(s) <= n else s[:n] + "…"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ollama-driven MCP host for FocusLens enrichment."
    )
    parser.add_argument(
        "prompt",
        nargs="?",
        default=(
            "Summarize my last 3 days one by one, then show me the dashboard."
        ),
        help="Natural-language instruction for the agent (default is the demo prompt).",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Ollama model name (default: {DEFAULT_MODEL}).",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Trace each step.")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    try:
        asyncio.run(run_agent(args.prompt, args.model, args.verbose))
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
