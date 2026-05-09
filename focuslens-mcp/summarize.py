"""Narrative day summary using a local Ollama model.

Pulls structured stats from db.py and asks Ollama to produce a 2-3 paragraph
plain-English summary. Returns stats + narrative; degrades gracefully if
Ollama is unreachable.
"""
from __future__ import annotations

import logging
import os
from datetime import date

import ollama

import db

log = logging.getLogger("focuslens-mcp.summarize")

_DEFAULT_MODEL = os.environ.get(
    "FOCUSLENS_SUMMARY_MODEL",
    os.environ.get("FOCUSLENS_MODEL", "gemma3:4b"),
)

_PROMPT_TEMPLATE = """You are summarizing a person's computer activity for {date_label}.

Here is their data:
- Productivity score: {score}/100
- Total active time: {hours}h {minutes}m
- Top apps: {top_apps}
- Category breakdown: {categories}

Write a 2-3 paragraph plain-English summary of their day. Be direct and specific.
Mention what they spent most time on, how productive the day was, and one observation
about their patterns. Do not use markdown. Do not start with "Here is a summary."
"""


def _fmt_seconds(s: int) -> tuple[int, int]:
    return s // 3600, (s % 3600) // 60


def _date_label(d: date) -> str:
    today = date.today()
    if d == today:
        return "today"
    delta = (today - d).days
    if delta == 1:
        return "yesterday"
    return d.strftime("%B %-d")


def build(d: date) -> dict:
    """Return stats + narrative for a single day. narrative is None if Ollama is unavailable."""
    apps = db.top_apps_for_range(d, d, limit=5)
    score_data = db.productivity_score(d, d)
    cats = db.category_summary(d, d)

    hours, minutes = _fmt_seconds(score_data["total_active_seconds"])

    top_apps_str = ", ".join(
        f"{r['app_name']} ({r['total_seconds'] // 60}m)"
        for r in apps[:5]
    ) or "none"

    cats_str = ", ".join(
        f"{r['category_name']} ({r['total_seconds'] // 60}m)"
        for r in cats[:6]
    ) or "none"

    stats = {
        "productivity_score": score_data["score"],
        "total_active_seconds": score_data["total_active_seconds"],
        "top_apps": [{"app_name": r["app_name"], "total_seconds": r["total_seconds"]} for r in apps],
        "categories": [{"name": r["category_name"], "total_seconds": r["total_seconds"], "tier": r["is_productive"]} for r in cats],
    }

    prompt = _PROMPT_TEMPLATE.format(
        date_label=_date_label(d),
        score=score_data["score"],
        hours=hours,
        minutes=minutes,
        top_apps=top_apps_str,
        categories=cats_str,
    )

    narrative: str | None = None
    error: str | None = None
    try:
        resp = ollama.chat(
            model=_DEFAULT_MODEL,
            messages=[{"role": "user", "content": prompt}],
        )
        narrative = (resp["message"]["content"] or "").strip()
    except Exception as exc:
        log.warning("ollama unavailable for summarize_day: %s", exc)
        error = "ollama_unavailable"

    result: dict = {"date": d.isoformat(), "stats": stats, "narrative": narrative}
    if error:
        result["error"] = error
    return result
