"""FastMCP STDIO server exposing tools for FocusLens enrichment and reporting.

Tools:
  - list_top_apps        → top apps by time for a date range
  - get_productivity_score → weighted 0-100 score + tier breakdown
  - get_category_breakdown → seconds per category
  - get_hourly_breakdown   → activity + dominant tier per hour
  - summarize_day        → Ollama-generated narrative summary of a single day
  - insights_store       → CRUD on app_insights table (local file)
  - render_report        → compose a custom Prefab report, returns URL (UI)
  - show_dashboard       → open the full interactive dashboard (UI)
"""
from __future__ import annotations

import logging
from datetime import date, timedelta
from typing import Literal

from fastmcp import FastMCP
from pydantic import ValidationError

import db
import insights
import summarize
import web_server
from report_spec import ReportSpec

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("focuslens-mcp")

mcp = FastMCP("focuslens-mcp")


@mcp.tool
def list_top_apps(days: int = 7, limit: int = 10) -> dict:
    """Return the user's top apps from FocusLens for the last N days.

    Use this first to know which apps the user actually spends time on,
    before deciding what to research.
    """
    today = date.today()
    start = today - timedelta(days=max(1, days) - 1)
    apps = db.top_apps_for_range(start, today, limit=limit)
    return {
        "range": {"start": start.isoformat(), "end": today.isoformat()},
        "apps": apps,
    }


@mcp.tool
def get_productivity_score(start: str, end: str) -> dict:
    """Return the weighted productivity score (0-100) for a date range.

    Args:
        start: Start date as YYYY-MM-DD (inclusive).
        end:   End date as YYYY-MM-DD (inclusive).

    Returns score, total_active_seconds, and seconds broken down by tier
    (-2 very distracting → +2 very productive).
    """
    return db.productivity_score(date.fromisoformat(start), date.fromisoformat(end))


@mcp.tool
def get_category_breakdown(start: str, end: str) -> dict:
    """Return time spent per category for a date range.

    Args:
        start: Start date as YYYY-MM-DD (inclusive).
        end:   End date as YYYY-MM-DD (inclusive).

    Returns a list of {category_name, is_productive (tier), total_seconds}.
    """
    cats = db.category_summary(date.fromisoformat(start), date.fromisoformat(end))
    return {"start": start, "end": end, "categories": cats}


@mcp.tool
def get_hourly_breakdown(start: str, end: str) -> dict:
    """Return activity per hour of day for a date range.

    Args:
        start: Start date as YYYY-MM-DD (inclusive).
        end:   End date as YYYY-MM-DD (inclusive).

    Returns a list of {hour (0-23), label, total_seconds, dominant_tier}.
    """
    hours = db.hourly_breakdown(date.fromisoformat(start), date.fromisoformat(end))
    return {"start": start, "end": end, "hours": hours}


@mcp.tool
def summarize_day(date: str) -> dict:
    """Generate a plain-English narrative summary of a single day's activity.

    Uses a local Ollama model to produce a 2-3 paragraph description of how
    the day was spent. Also returns the structured stats used to generate it.
    Degrades gracefully if Ollama is unavailable (stats still returned).

    Args:
        date: The day to summarize as YYYY-MM-DD.

    Returns {"date", "stats": {productivity_score, total_active_seconds,
    top_apps, categories}, "narrative": "...", "error": "ollama_unavailable" (if failed)}.
    """
    from datetime import date as date_type
    d = date_type.fromisoformat(date)
    return summarize.build(d)


@mcp.tool
def render_report(title: str, sections: list[dict]) -> dict:
    """Compose a custom visual report and return a URL to open in the browser.

    Use this when the user wants a chart, table, or visual summary — not just text.
    The report is ephemeral (expires after 1 hour).

    Args:
        title:    Report heading shown at the top of the page.
        sections: Ordered list of sections. Each section must have a "type" field:

          {"type": "text",      "content": "..."}
          {"type": "kpi",       "label": "...", "value": "...",
                                "description": "...",         # optional
                                "trend": "up"|"down"|"neutral",  # optional
                                "trend_sentiment": "positive"|"negative"|"neutral"}  # optional
          {"type": "bar_chart", "title": "...",
                                "data": [{"label": "...", "value": 42, "tier": 1}]}
                                # tier: -2 to +2 controls bar colour; omit for default
          {"type": "table",     "title": "...",
                                "headers": ["Col A", "Col B"],
                                "rows": [["r1c1", "r1c2"], ["r2c1", "r2c2"]]}

    Multiple KPI sections are automatically laid out in a grid row.
    Returns {"url": "...", "report_id": "..."} — open the URL in a browser.
    """
    try:
        spec = ReportSpec.model_validate({"title": title, "sections": sections})
    except ValidationError as exc:
        return {"error": "Invalid report spec", "details": str(exc)}

    web_server.ensure_running()
    report_id = web_server.store_report(spec)
    url = f"{web_server.BASE_URL}/report/{report_id}"
    log.info("report %s ready at %s", report_id, url)
    return {"url": url, "report_id": report_id, "message": f"Report ready. Open: {url}"}


@mcp.tool
def insights_store(
    operation: Literal["list", "get", "upsert", "delete"],
    app_name: str | None = None,
    verdict: Literal["productive", "neutral", "distracting"] | None = None,
    summary: str | None = None,
    sources: list[str] | None = None,
) -> dict:
    """CRUD on the app_insights table in focuslens.db.

    Operations:
      - list:    return all stored insights
      - get:     return one insight by app_name
      - upsert:  create or update an insight (requires app_name, verdict, summary)
      - delete:  remove an insight by app_name
    """
    if operation == "list":
        return {"insights": insights.list_all()}
    if not app_name:
        raise ValueError(f"app_name is required for operation={operation!r}")
    if operation == "get":
        entry = insights.get(app_name)
        return {"insight": entry}
    if operation == "upsert":
        if not verdict or not summary:
            raise ValueError("upsert requires verdict and summary")
        entry = insights.upsert(app_name, verdict, summary, sources or [])
        return {"insight": entry, "stored": True}
    if operation == "delete":
        removed = insights.delete(app_name)
        return {"removed": removed}
    raise ValueError(f"unknown operation: {operation!r}")


@mcp.tool
def show_dashboard(days: int = 7) -> dict:
    """Launch the interactive FocusLens Prefab dashboard in a web browser.

    Starts a local web server (localhost:8765) if not already running and
    returns its URL. The dashboard shows the top apps from the last N days
    with verdict badges. Each app card has Productive / Neutral / Distracting
    buttons — clicking one updates focuslens.db immediately and reloads the page.
    """
    url = web_server.ensure_running()
    full_url = f"{url}/?days={days}"
    log.info("dashboard available at %s", full_url)
    return {
        "url": full_url,
        "days": days,
        "message": f"Dashboard ready. Open: {full_url}",
    }


if __name__ == "__main__":
    mcp.run()
