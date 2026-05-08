"""CRUD over the app_insights table in focuslens.db.

Single source of truth alongside FocusLens's own tables. The Swift app ignores
this table (GRDB only processes migrations it knows about); we create it on
first use via db._connect_rw().
"""
from __future__ import annotations

import json
from datetime import datetime

from db import _connect_rw


def _row_to_dict(row) -> dict:
    d = dict(row)
    d["sources"] = json.loads(d.get("sources") or "[]")
    return d


def _now() -> str:
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def list_all() -> list[dict]:
    with _connect_rw() as conn:
        rows = conn.execute(
            "SELECT * FROM app_insights ORDER BY app_name COLLATE NOCASE"
        ).fetchall()
        return [_row_to_dict(r) for r in rows]


def get(app_name: str) -> dict | None:
    with _connect_rw() as conn:
        row = conn.execute(
            "SELECT * FROM app_insights WHERE app_name = ? COLLATE NOCASE",
            (app_name,),
        ).fetchone()
        return _row_to_dict(row) if row else None


def upsert(app_name: str, verdict: str, summary: str, sources: list[str] | None = None) -> dict:
    if verdict not in {"productive", "neutral", "distracting"}:
        raise ValueError(f"verdict must be productive|neutral|distracting, got {verdict!r}")
    sources_json = json.dumps(sources or [])
    now = _now()
    with _connect_rw() as conn:
        existing = conn.execute(
            "SELECT created_at FROM app_insights WHERE app_name = ? COLLATE NOCASE",
            (app_name,),
        ).fetchone()
        if existing:
            conn.execute(
                """UPDATE app_insights
                   SET verdict=?, summary=?, sources=?, updated_at=?
                   WHERE app_name=? COLLATE NOCASE""",
                (verdict, summary, sources_json, now, app_name),
            )
            created_at = existing["created_at"]
        else:
            conn.execute(
                """INSERT INTO app_insights
                   (app_name, verdict, summary, sources, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (app_name, verdict, summary, sources_json, now, now),
            )
            created_at = now
    return {
        "app_name": app_name,
        "verdict": verdict,
        "summary": summary,
        "sources": sources or [],
        "created_at": created_at,
        "updated_at": now,
    }


def delete(app_name: str) -> bool:
    with _connect_rw() as conn:
        cursor = conn.execute(
            "DELETE FROM app_insights WHERE app_name = ? COLLATE NOCASE",
            (app_name,),
        )
        return cursor.rowcount > 0
