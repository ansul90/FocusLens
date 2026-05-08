"""Interactive Prefab dashboard for FocusLens.

Layout:
  - Header bar: title (left) + date-range nav (right)
  - KPI row: Score card + Active Time card + Productive/Neutral/Distracting breakdown card
  - Middle row: Category Breakdown card (left) | Hourly Activity card (right)
  - Bottom: Top Apps grid with verdict buttons
"""
from __future__ import annotations

from datetime import date, timedelta
from urllib.parse import quote

from prefab_ui import PrefabApp
from prefab_ui.actions import Fetch, OpenLink
from prefab_ui.components import (
    Badge,
    Card,
    CardContent,
    CardDescription,
    CardFooter,
    CardHeader,
    CardTitle,
    Column,
    Container,
    Grid,
    GridItem,
    Heading,
    Metric,
    Muted,
    Progress,
    Row,
    Separator,
    Small,
    Text,
    Button,
)

import db
import insights as insights_mod

TIER_VARIANT: dict[int, str] = {
    2:  "success",
    1:  "info",
    0:  "muted",
    -1: "warning",
    -2: "destructive",
}

TIER_LABEL: dict[int, str] = {
    2:  "Very productive",
    1:  "Productive",
    0:  "Neutral",
    -1: "Distracting",
    -2: "Very distracting",
}

VERDICT_VARIANT: dict[str, str] = {
    "productive":   "success",
    "neutral":      "secondary",
    "distracting":  "destructive",
}


def _score_sentiment(score: int) -> tuple[str, str]:
    if score >= 85:
        return "Highly productive", "positive"
    if score >= 70:
        return "Productive", "positive"
    if score >= 50:
        return "Average", "neutral"
    if score >= 30:
        return "Below average", "negative"
    return "Needs focus", "negative"


def _fmt_duration(seconds: int) -> str:
    h, rem = divmod(int(seconds), 3600)
    m = rem // 60
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m"
    return f"{seconds}s"


def _header(title: str, start: date, end: date, base_url: str) -> None:
    today = date.today()
    presets = [
        ("Today", today,                     today),
        ("7d",    today - timedelta(days=6), today),
        ("30d",   today - timedelta(days=29), today),
    ]
    with Row(gap=0, cssClass="items-center justify-between mb-4"):
        Heading(title, level=1, cssClass="text-2xl font-bold")
        with Row(gap=2):
            for label, ps, pe in presets:
                is_active = (start == ps and end == pe)
                Button(
                    label,
                    variant="default" if is_active else "outline",
                    size="sm",
                    on_click=OpenLink(f"{base_url}/?start={ps.isoformat()}&end={pe.isoformat()}"),
                )


def _kpi_row(score_data: dict) -> None:
    label, sentiment = _score_sentiment(score_data["score"])
    total = score_data["total_active_seconds"]
    by_tier = score_data["by_tier"]

    productive_secs    = sum(s for t, s in by_tier.items() if t > 0)
    neutral_secs       = by_tier.get(0, 0)
    distracting_secs   = sum(s for t, s in by_tier.items() if t < 0)

    with Grid(columns=3, gap=4, cssClass="mb-4"):
        # Score card
        with Card():
            with CardHeader():
                CardTitle("Productivity Score")
            with CardContent():
                Metric(
                    label="",
                    value=f"{score_data['score']}",
                    description=label,
                    trend="up" if sentiment == "positive" else ("down" if sentiment == "negative" else "neutral"),
                    trendSentiment=sentiment,
                )
                Progress(
                    value=score_data["score"],
                    max=100,
                    variant=TIER_VARIANT.get(2 if score_data["score"] >= 70 else (1 if score_data["score"] >= 50 else -1)),
                    size="sm",
                    cssClass="mt-2",
                )

        # Active time card
        with Card():
            with CardHeader():
                CardTitle("Active Time")
            with CardContent():
                Metric(
                    label="",
                    value=_fmt_duration(total),
                    description=f"{round(total / 60)} minutes tracked",
                )

        # Tier breakdown card
        with Card():
            with CardHeader():
                CardTitle("Time Breakdown")
            with CardContent():
                with Column(gap=2):
                    for secs, variant, tier_label in [
                        (productive_secs,  "success",     "Productive"),
                        (neutral_secs,     "muted",       "Neutral"),
                        (distracting_secs, "destructive", "Distracting"),
                    ]:
                        pct = (secs / total * 100) if total > 0 else 0
                        with Row(gap=2, cssClass="items-center"):
                            Small(tier_label, cssClass="w-24 shrink-0")
                            Progress(value=pct, max=100, variant=variant, size="sm")
                            Small(f"{pct:.0f}%", cssClass="w-8 text-right tabular-nums")


def _category_card(cats: list[dict]) -> None:
    with Card(cssClass="h-full"):
        with CardHeader():
            CardTitle("Categories")
        with CardContent():
            if not cats:
                Muted("No data for this period.")
                return
            total = sum(c["total_seconds"] for c in cats)
            with Column(gap=3):
                for cat in cats:
                    pct = (cat["total_seconds"] / total * 100) if total > 0 else 0
                    tier = cat.get("is_productive", 0)
                    with Column(gap=1):
                        with Row(gap=2, cssClass="items-center justify-between"):
                            Small(cat["category_name"], cssClass="font-medium")
                            Small(f"{_fmt_duration(cat['total_seconds'])}  {pct:.0f}%", cssClass="tabular-nums")
                        Progress(
                            value=pct,
                            max=100,
                            variant=TIER_VARIANT.get(tier, "muted"),
                            size="sm",
                        )


def _hourly_card(hours: list[dict]) -> None:
    with Card(cssClass="h-full"):
        with CardHeader():
            CardTitle("Hourly Activity")
        with CardContent():
            if not hours:
                Muted("No data for this period.")
                return
            max_secs = max(h["total_seconds"] for h in hours)
            with Column(gap=2):
                for h in hours:
                    pct = (h["total_seconds"] / max_secs * 100) if max_secs > 0 else 0
                    tier = h["dominant_tier"]
                    with Row(gap=2, cssClass="items-center"):
                        Small(h["label"], cssClass="w-12 shrink-0 text-right tabular-nums")
                        Progress(
                            value=pct,
                            max=100,
                            variant=TIER_VARIANT.get(tier, "muted"),
                            size="sm",
                        )
                        Small(_fmt_duration(h["total_seconds"]), cssClass="w-14 tabular-nums")


def _verdict_buttons(app_name: str, current: str | None, base_url: str, start: date, end: date) -> None:
    encoded = quote(app_name, safe="")
    patch_url  = f"{base_url}/api/insight/{encoded}"
    reload_url = f"{base_url}/?start={start.isoformat()}&end={end.isoformat()}"
    for verdict in ("productive", "neutral", "distracting"):
        Button(
            verdict.title(),
            variant=VERDICT_VARIANT[verdict] if current == verdict else "outline",
            size="sm",
            on_click=Fetch.patch(patch_url, body={"verdict": verdict}, on_success=OpenLink(reload_url)),
        )


def _top_apps_section(apps: list[dict], insight_map: dict, base_url: str, start: date, end: date) -> None:
    with Card():
        with CardHeader():
            CardTitle("Top Apps")
            CardDescription("Correct the agent's classification with the verdict buttons.")
        with CardContent():
            with Grid(minColumnWidth="280px", gap=4):
                for row in apps:
                    insight = insight_map.get(row["app_name"].casefold())
                    current_verdict = insight["verdict"] if insight else None
                    with Card():
                        with CardHeader():
                            with Row(gap=2, cssClass="items-center"):
                                Text(row["app_name"], cssClass="font-semibold")
                                if current_verdict:
                                    Badge(current_verdict.title(), variant=VERDICT_VARIANT[current_verdict])
                                else:
                                    Badge("Unclassified", variant="outline")
                            CardDescription(
                                f"{_fmt_duration(row['total_seconds'])} · "
                                f"{row['session_count']} sessions · "
                                f"{row.get('category_name') or 'Uncategorized'}"
                            )
                        if insight:
                            with CardContent():
                                Small(insight["summary"])
                        with CardFooter():
                            with Row(gap=2):
                                _verdict_buttons(row["app_name"], current_verdict, base_url, start, end)


def build_app(
    start: date | None = None,
    end: date | None = None,
    days: int = 7,
    base_url: str = "http://127.0.0.1:8765",
) -> PrefabApp:
    today = date.today()
    end   = end   or today
    start = start or (end - timedelta(days=days - 1))

    apps        = db.top_apps_for_range(start, end, limit=10)
    cats        = db.category_summary(start, end)
    score_data  = db.productivity_score(start, end)
    hours       = db.hourly_breakdown(start, end)
    insight_map = {i["app_name"].casefold(): i for i in insights_mod.list_all()}

    span_days = (end - start).days + 1
    title = (
        f"FocusLens · {start.strftime('%b %d, %Y')}"
        if start == end
        else f"FocusLens · {start.strftime('%b %d')} – {end.strftime('%b %d, %Y')} ({span_days}d)"
    )

    with PrefabApp(title=title) as app:
        with Container(cssClass="py-6 space-y-4"):
            _header(title, start, end, base_url)
            _kpi_row(score_data)
            with Grid(columns=2, gap=4, cssClass="mb-4"):
                _category_card(cats)
                _hourly_card(hours)
            _top_apps_section(apps, insight_map, base_url, start, end)
    return app
