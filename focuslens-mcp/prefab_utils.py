"""Shared Prefab UI constants used across prefab_app and prefab_report."""

TIER_VARIANT: dict[int, str] = {
    2:  "success",
    1:  "info",
    0:  "muted",
    -1: "warning",
    -2: "destructive",
}

VERDICT_VARIANT: dict[str, str] = {
    "productive":   "success",
    "neutral":      "secondary",
    "distracting":  "destructive",
}
