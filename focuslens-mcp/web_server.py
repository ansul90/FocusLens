"""FastAPI server that backs the interactive Prefab dashboard.

Starts lazily as a daemon thread on first call to ensure_running().
"""
import threading
import time
import logging
import uuid
from datetime import date, timedelta

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

import insights
import prefab_app as _prefab
import prefab_report as _report
from report_spec import ReportSpec

log = logging.getLogger("focuslens-web")

PORT = 8765
BASE_URL = f"http://127.0.0.1:{PORT}"

_REPORT_TTL = 3600        # seconds before a stored report expires
_REPORT_MAX = 100         # max reports kept in memory at once
_reports: dict[str, tuple[ReportSpec, float]] = {}  # id → (spec, stored_at)


def store_report(spec: ReportSpec) -> str:
    """Store a ReportSpec in memory and return its short ID."""
    _evict_reports()
    report_id = uuid.uuid4().hex[:8]
    _reports[report_id] = (spec, time.time())
    log.info("stored report %s: %s", report_id, spec.title)
    return report_id


def _evict_reports() -> None:
    now = time.time()
    expired = [k for k, (_, ts) in _reports.items() if now - ts > _REPORT_TTL]
    for k in expired:
        del _reports[k]
    # Hard cap: drop oldest if still over limit
    while len(_reports) >= _REPORT_MAX:
        oldest = min(_reports, key=lambda k: _reports[k][1])
        del _reports[oldest]

_server: uvicorn.Server | None = None
_thread: threading.Thread | None = None

api = FastAPI(title="focuslens-mcp dashboard")

api.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@api.get("/", response_class=HTMLResponse)
def dashboard(
    start: date | None = None,
    end: date | None = None,
    days: int = 7,
) -> str:
    today = date.today()
    resolved_end = end or today
    resolved_start = start or (resolved_end - timedelta(days=days - 1))
    app = _prefab.build_app(start=resolved_start, end=resolved_end, base_url=BASE_URL)
    return app.html()


@api.get("/report/{report_id}", response_class=HTMLResponse)
def render_report(report_id: str) -> str:
    entry = _reports.get(report_id)
    if not entry:
        raise HTTPException(status_code=404, detail=f"Report '{report_id}' not found or expired.")
    spec, _ = entry
    return _report.build_report(spec).html()


def ensure_running() -> str:
    """Start the uvicorn server in a daemon thread if not already running."""
    global _server, _thread
    if _thread and _thread.is_alive():
        return BASE_URL
    config = uvicorn.Config(
        api,
        host="127.0.0.1",
        port=PORT,
        log_level="error",
        access_log=False,
    )
    _server = uvicorn.Server(config)
    _thread = threading.Thread(target=_server.run, daemon=True, name="prefab-dashboard")
    _thread.start()
    # Wait for uvicorn to bind the port (max 5s)
    for _ in range(50):
        if _server.started:
            break
        time.sleep(0.1)
    log.info("dashboard server started at %s", BASE_URL)
    return BASE_URL
