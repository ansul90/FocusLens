"""Generic Prefab renderer for agent-composed ReportSpec objects."""
from __future__ import annotations

from prefab_ui import PrefabApp
from prefab_ui.components import (
    Card,
    CardContent,
    CardHeader,
    CardTitle,
    Column,
    Container,
    Grid,
    Heading,
    Metric,
    Muted,
    Progress,
    Row,
    Separator,
    Small,
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
    Text,
)

from report_spec import (
    BarChartSection,
    KPISection,
    ReportSpec,
    TableSection,
    TextSection,
)

TIER_VARIANT: dict[int, str] = {
    2:  "success",
    1:  "info",
    0:  "muted",
    -1: "warning",
    -2: "destructive",
}


def _render_text(section: TextSection) -> None:
    Text(section.content, cssClass="text-sm text-muted-foreground")


def _render_kpi(section: KPISection) -> None:
    with Card():
        with CardContent(cssClass="pt-6"):
            Metric(
                label=section.label,
                value=section.value,
                description=section.description,
                trend=section.trend,
                trendSentiment=section.trend_sentiment,
            )


def _render_bar_chart(section: BarChartSection) -> None:
    with Card():
        with CardHeader():
            CardTitle(section.title)
        with CardContent():
            if not section.data:
                Muted("No data.")
                return
            max_val = max((item.value for item in section.data), default=1) or 1
            with Column(gap=2):
                for item in section.data:
                    pct = (item.value / max_val * 100)
                    variant = TIER_VARIANT.get(item.tier, "muted") if item.tier is not None else "info"
                    with Column(gap=1):
                        with Row(gap=2, cssClass="items-center justify-between"):
                            Small(item.label, cssClass="font-medium")
                            Small(f"{item.value:g}", cssClass="tabular-nums")
                        Progress(value=pct, max=100, variant=variant, size="sm")


def _render_table(section: TableSection) -> None:
    with Card():
        with CardHeader():
            CardTitle(section.title)
        with CardContent():
            with Table():
                with TableHeader():
                    with TableRow():
                        for h in section.headers:
                            TableHead(h)
                with TableBody():
                    for row in section.rows:
                        with TableRow():
                            for cell in row:
                                TableCell(str(cell))


def build_report(spec: ReportSpec) -> PrefabApp:
    """Render a ReportSpec as a Prefab HTML page."""
    # Collect KPI sections to render in a grid row together
    kpi_sections = [s for s in spec.sections if isinstance(s, KPISection)]
    non_kpi = [s for s in spec.sections if not isinstance(s, KPISection)]

    with PrefabApp(title=spec.title) as app:
        with Container(cssClass="py-6 space-y-4"):
            Heading(spec.title, level=1, cssClass="text-2xl font-bold mb-4")

            if kpi_sections:
                cols = min(len(kpi_sections), 4)
                with Grid(columns=cols, gap=4, cssClass="mb-4"):
                    for section in kpi_sections:
                        _render_kpi(section)

            for section in non_kpi:
                if isinstance(section, TextSection):
                    _render_text(section)
                elif isinstance(section, BarChartSection):
                    _render_bar_chart(section)
                elif isinstance(section, TableSection):
                    _render_table(section)

    return app
