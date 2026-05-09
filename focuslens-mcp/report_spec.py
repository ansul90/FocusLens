"""Pydantic models for agent-composable report sections."""
from typing import Annotated, Literal, Union

from pydantic import BaseModel, Field


class TextSection(BaseModel):
    type: Literal["text"]
    content: str


class KPISection(BaseModel):
    type: Literal["kpi"]
    label: str
    value: str
    description: str | None = None
    trend: Literal["up", "down", "neutral"] | None = None
    trend_sentiment: Literal["positive", "negative", "neutral"] | None = None


class BarItem(BaseModel):
    label: str
    value: float
    tier: int | None = None  # -2 to +2 maps to color; None → muted


class BarChartSection(BaseModel):
    type: Literal["bar_chart"]
    title: str
    data: list[BarItem]


class TableSection(BaseModel):
    type: Literal["table"]
    title: str
    headers: list[str]
    rows: list[list[str]]


ReportSection = Annotated[
    Union[TextSection, KPISection, BarChartSection, TableSection],
    Field(discriminator="type"),
]


class ReportSpec(BaseModel):
    title: str
    sections: list[ReportSection]
