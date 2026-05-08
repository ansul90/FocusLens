"""SQLite access to focuslens.db.

Activity-session queries are read-only (Swift owns that schema).
The app_insights table is owned by this Python layer — created here on first
use, ignored by the Swift app's GRDB migrations.
"""
from __future__ import annotations

import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import date, datetime, time, timedelta
from typing import Iterator

DB_PATH = os.path.expanduser(
    "~/Library/Application Support/FocusLens/focuslens.db"
)

_CREATE_INSIGHTS = """
CREATE TABLE IF NOT EXISTS app_insights (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    app_name    TEXT    NOT NULL UNIQUE COLLATE NOCASE,
    verdict     TEXT    NOT NULL CHECK (verdict IN ('productive','neutral','distracting')),
    summary     TEXT    NOT NULL,
    sources     TEXT    NOT NULL DEFAULT '[]',
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
)
"""


def _check_db() -> None:
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(
            f"FocusLens database not found at {DB_PATH}. "
            "Run FocusLens.app at least once to create it."
        )


@contextmanager
def _connect_ro() -> Iterator[sqlite3.Connection]:
    _check_db()
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


@contextmanager
def _connect_rw() -> Iterator[sqlite3.Connection]:
    """Read-write connection — only used to manage app_insights."""
    _check_db()
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(_CREATE_INSIGHTS)
    conn.commit()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _day_bounds(d: date) -> tuple[str, str]:
    start = datetime.combine(d, time.min).isoformat()
    end = datetime.combine(d + timedelta(days=1), time.min).isoformat()
    return start, end


def top_apps_for_range(start: date, end_inclusive: date, limit: int = 10) -> list[dict]:
    """Top apps by total tracked seconds across a date range."""
    start_iso, _ = _day_bounds(start)
    _, end_iso = _day_bounds(end_inclusive)
    sql = """
        SELECT
            s.app_name,
            s.app_bundle_id,
            CAST(SUM(s.duration_seconds) AS INTEGER) AS total_seconds,
            COUNT(*) AS session_count,
            c.name AS category_name,
            COALESCE(c.is_productive, 0) AS is_productive
        FROM activity_sessions s
        LEFT JOIN categories c ON c.id = s.category_id
        WHERE s.started_at >= ?
          AND s.started_at < ?
          AND s.is_idle = 0
          AND s.duration_seconds IS NOT NULL
        GROUP BY s.app_bundle_id, s.app_name, c.name, c.is_productive
        ORDER BY total_seconds DESC
        LIMIT ?
    """
    with _connect_ro() as conn:
        return [dict(r) for r in conn.execute(sql, (start_iso, end_iso, limit)).fetchall()]


VERDICT_TIER = {"productive": 1, "neutral": 0, "distracting": -1}


def get_bundle_id(app_name: str) -> str | None:
    """Return the most recently seen bundle ID for an app name."""
    with _connect_ro() as conn:
        row = conn.execute(
            """SELECT app_bundle_id FROM activity_sessions
               WHERE app_name = ? COLLATE NOCASE
               ORDER BY started_at DESC LIMIT 1""",
            (app_name,),
        ).fetchone()
        return row["app_bundle_id"] if row else None


def write_category_rule(app_name: str, verdict: str) -> dict | None:
    """Insert or replace a high-priority category_rules row for app_name.

    Finds the best-fit existing category for the verdict's tier, then writes
    a bundle-ID rule so FocusLens picks it up on next recategorization.
    Returns the chosen category dict, or None if the app's bundle ID is unknown.
    """
    bundle_id = get_bundle_id(app_name)
    if not bundle_id:
        return None
    tier = VERDICT_TIER.get(verdict, 0)
    with _connect_rw() as conn:
        if tier > 0:
            row = conn.execute(
                "SELECT id, name FROM categories WHERE is_productive > 0 ORDER BY is_productive DESC LIMIT 1"
            ).fetchone()
        elif tier < 0:
            row = conn.execute(
                "SELECT id, name FROM categories WHERE is_productive < 0 ORDER BY is_productive ASC LIMIT 1"
            ).fetchone()
        else:
            row = conn.execute(
                "SELECT id, name FROM categories ORDER BY ABS(is_productive) ASC, id ASC LIMIT 1"
            ).fetchone()
        if not row:
            return None
        category_id, category_name = row["id"], row["name"]
        # Remove any prior rule for this bundle ID so we don't accumulate duplicates.
        conn.execute(
            "DELETE FROM category_rules WHERE match_type='app_bundle' AND match_value=?",
            (bundle_id,),
        )
        conn.execute(
            """INSERT INTO category_rules (category_id, match_type, match_value, priority)
               VALUES (?, 'app_bundle', ?, 100)""",
            (category_id, bundle_id),
        )
    return {"category_id": category_id, "category_name": category_name, "bundle_id": bundle_id}


def productivity_score(start: date, end_inclusive: date) -> dict:
    """Weighted productivity score (0-100) for a date range.

    Mirrors the SwiftUI dashboard formula:
        score = ((weighted_avg_tier + 2) / 4) * 100
    where tier ranges from -2 (very distracting) to +2 (very productive).
    Returns 50 when there is no tracked data.
    """
    start_iso, _ = _day_bounds(start)
    _, end_iso = _day_bounds(end_inclusive)
    sql = """
        SELECT COALESCE(c.is_productive, 0) AS tier,
               CAST(SUM(s.duration_seconds) AS INTEGER) AS total_seconds
        FROM activity_sessions s
        LEFT JOIN categories c ON c.id = s.category_id
        WHERE s.started_at >= ?
          AND s.started_at < ?
          AND s.is_idle = 0
          AND s.duration_seconds IS NOT NULL
        GROUP BY tier
    """
    with _connect_ro() as conn:
        rows = [dict(r) for r in conn.execute(sql, (start_iso, end_iso)).fetchall()]

    tier_seconds: dict[int, int] = {r["tier"]: r["total_seconds"] for r in rows}
    total = sum(tier_seconds.values())
    weighted_sum = sum(tier * secs for tier, secs in tier_seconds.items())
    score = (
        max(0, min(100, int(((weighted_sum / total) + 2.0) / 4.0 * 100)))
        if total > 0
        else 50
    )
    return {
        "score": score,
        "total_active_seconds": total,
        "by_tier": tier_seconds,
    }


def hourly_breakdown(start: date, end_inclusive: date) -> list[dict]:
    """Seconds per hour of day in a date range, with dominant productivity tier.

    Returns one entry per hour that has activity, sorted by hour (0-23).
    dominant_tier is the tier (-2 to +2) with the most time that hour.
    """
    start_iso, _ = _day_bounds(start)
    _, end_iso = _day_bounds(end_inclusive)
    sql = """
        SELECT CAST(strftime('%H', s.started_at, 'localtime') AS INTEGER) AS hour,
               COALESCE(c.is_productive, 0) AS tier,
               CAST(SUM(s.duration_seconds) AS INTEGER) AS total_seconds
        FROM activity_sessions s
        LEFT JOIN categories c ON c.id = s.category_id
        WHERE s.started_at >= ?
          AND s.started_at < ?
          AND s.is_idle = 0
          AND s.duration_seconds IS NOT NULL
        GROUP BY hour, tier
        ORDER BY hour, tier
    """
    with _connect_ro() as conn:
        rows = [dict(r) for r in conn.execute(sql, (start_iso, end_iso)).fetchall()]

    by_hour: dict[int, dict] = {}
    for r in rows:
        h, tier, secs = r["hour"], r["tier"], r["total_seconds"]
        if h not in by_hour:
            by_hour[h] = {"total_seconds": 0, "tier_seconds": {}}
        by_hour[h]["total_seconds"] += secs
        by_hour[h]["tier_seconds"][tier] = by_hour[h]["tier_seconds"].get(tier, 0) + secs

    return [
        {
            "hour": h,
            "label": f"{h:02d}:00",
            "total_seconds": d["total_seconds"],
            "dominant_tier": max(d["tier_seconds"], key=d["tier_seconds"].__getitem__),
        }
        for h, d in sorted(by_hour.items())
    ]


def category_summary(start: date, end_inclusive: date) -> list[dict]:
    """Total seconds per category in a date range."""
    start_iso, _ = _day_bounds(start)
    _, end_iso = _day_bounds(end_inclusive)
    sql = """
        SELECT
            COALESCE(c.name, 'Uncategorized') AS category_name,
            COALESCE(c.is_productive, 0) AS is_productive,
            CAST(SUM(s.duration_seconds) AS INTEGER) AS total_seconds
        FROM activity_sessions s
        LEFT JOIN categories c ON c.id = s.category_id
        WHERE s.started_at >= ?
          AND s.started_at < ?
          AND s.is_idle = 0
          AND s.duration_seconds IS NOT NULL
        GROUP BY c.name, c.is_productive
        ORDER BY total_seconds DESC
    """
    with _connect_ro() as conn:
        return [dict(r) for r in conn.execute(sql, (start_iso, end_iso)).fetchall()]
