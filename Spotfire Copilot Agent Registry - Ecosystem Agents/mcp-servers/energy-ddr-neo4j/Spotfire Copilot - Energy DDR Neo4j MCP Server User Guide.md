# Energy DDR Neo4j MCP Server — User Guide

energy × daily-drilling-reports × neo4j

The `energy-ddr-neo4j` MCP server exposes a curated set of tools for querying Daily Drilling Reports (DDR) stored in a Neo4j knowledge graph, so that agents and other MCP clients can answer drilling questions without writing Cypher.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Report Discovery](#report-discovery)
  - [Counts and Depth KPIs](#counts-and-depth-kpis)
  - [Field Analytics](#field-analytics)
  - [Report Deep Dives](#report-deep-dives)
  - [Advanced / Fallback](#advanced--fallback)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Daily Drilling Reports (DDR) Agent](../../agents/Spotfire%20Copilot%20-%20Daily%20Drilling%20Reports%20%28DDR%29%20Agent%20User%20Guide.md). It provides specialized tools for report discovery, depth and rig KPIs, extracted-field analytics, and per-report deep dives, plus a fallback Cypher tool.

Output conventions:

- All tools return JSON text.
- Tool failures return a structured payload with an `error` field describing the cause.
- Date filters use ISO `YYYY-MM-DD` strings; empty strings mean "no filter".

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the [Energy DDR Neo4j MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20Deployment%20Guide.md). The server must be deployed and reachable before the DDR Agent can be invoked.

## Connecting

| Setting          | Value                                                                              |
| ---------------- | ---------------------------------------------------------------------------------- |
| Transport        | `streamable-http` (recommended)                                                    |
| URL              | Set via `DDR_MCP_SERVER_URL` (e.g. `https://mcp-energy-ddr-neo4j.example.com/mcp`)  |
| Auth             | Configured on the server at deploy time                                            |

## Tool Reference

### Report Discovery

#### `list_drilling_reports_tool`
- **Purpose:** List drilling reports across the graph.
- **Inputs:** `limit` (int, optional, default `200`).
- **Output:** Rows with `report_id`, `report_date`, `wellbore`, `rig_name`, `distance_drilled`.

#### `list_drilling_reports_by_wellbore_tool`
- **Purpose:** List reports for a specific wellbore.
- **Inputs:** `wellbore` (str, required), `limit` (int, default `200`).

#### `list_drilling_reports_by_rig_name_tool`
- **Purpose:** List reports produced by a specific rig.
- **Inputs:** `rigname` (str, required), `limit` (int, default `200`).

#### `list_reports_by_date_range_tool`
- **Purpose:** List reports filed within an inclusive date range.
- **Inputs:** `start_date` (str, `YYYY-MM-DD`, required), `end_date` (str, `YYYY-MM-DD`, required), `limit` (int, default `200`).

#### `list_reports_with_filters_tool`
- **Purpose:** List reports using any combination of wellbore, rig, and date filters.
- **Inputs:** `wellbore` (str, optional), `rig_name` (str, optional), `start_date` (str, optional), `end_date` (str, optional), `limit` (int, default `200`).

#### `list_wellbores_tool`
- **Purpose:** List wellbores with their report counts and first/last report dates.
- **Inputs:** `limit` (int, default `200`).
- **Output:** Rows with `wellbore`, `report_count`, `first_report_date`, `last_report_date`.

#### `list_rig_names_tool`
- **Purpose:** List rig names with their report counts and first/last report dates.
- **Inputs:** `limit` (int, default `200`).
- **Output:** Rows with `rig_name`, `report_count`, `first_report_date`, `last_report_date`.

### Counts and Depth KPIs

#### `num_reports_tool`
- **Purpose:** Count all reports in the graph.
- **Inputs:** _none_. **Output:** `{ count }`.

#### `num_reports_by_wellbore_tool`
- **Purpose:** Count reports for a given wellbore.
- **Inputs:** `wellbore` (str, required). **Output:** `{ wellbore, count }`.

#### `num_reports_by_rig_name_tool`
- **Purpose:** Count reports for a given rig.
- **Inputs:** `rigname` (str, required). **Output:** `{ rig_name, count }`.

#### `max_distance_drilled_tool`
- **Purpose:** Maximum distance drilled across all reports.
- **Inputs:** _none_. **Output:** `{ max_distance_drilled }`.

#### `max_distance_drilled_by_wellbore_tool`
- **Purpose:** Maximum distance drilled for one wellbore.
- **Inputs:** `wellbore` (str, required).

#### `max_distance_drilled_by_rig_name_tool`
- **Purpose:** Maximum distance drilled for one rig.
- **Inputs:** `rigname` (str, required).

#### `average_depth_by_wellbore_tool`
- **Purpose:** Average distance drilled per report for a wellbore.
- **Inputs:** `wellbore` (str, required), `start_date` (str, optional), `end_date` (str, optional).

#### `total_depth_by_wellbore_tool`
- **Purpose:** Total distance drilled for a wellbore.
- **Inputs:** `wellbore` (str, required), `start_date` (str, optional), `end_date` (str, optional).

#### `total_depth_grouped_by_wellbore_tool`
- **Purpose:** One row per wellbore with summed distance drilled. Use this for "table of well vs total drilled" questions.
- **Inputs:** `start_date` (str, optional), `end_date` (str, optional), `limit` (int, default `500`).
- **Output:** Rows with `wellbore`, `total_distance_drilled`.

#### `depth_stats_by_wellbore_tool`
- **Purpose:** Depth statistics for a wellbore.
- **Inputs:** `wellbore` (str, required), `start_date` (str, optional), `end_date` (str, optional).
- **Output:** `{ count, avg, total, min, max }`.

### Field Analytics

#### `list_available_fields_tool`
- **Purpose:** List the extracted field keys present in the graph so clients can pick canonical keys before requesting stats.
- **Inputs:** `limit` (int, default `200`).
- **Output:** List of field keys.

#### `field_stats_tool`
- **Purpose:** Aggregate numeric stats for a field across multiple reports.
- **Inputs:** `field_key` (str, required), `wellbore` (str, optional), `rig_name` (str, optional), `start_date` (str, optional), `end_date` (str, optional).
- **Output:** `{ field_key, value_count, avg, min, max, total, units }`.

#### `field_stats_by_wellbore_tool`
- **Purpose:** Per-wellbore aggregate stats for a numeric field.
- **Inputs:** `field_key` (str, required), `rig_name` (str, optional), `start_date` (str, optional), `end_date` (str, optional), `limit` (int, default `200`).

#### `field_stats_by_rig_name_tool`
- **Purpose:** Per-rig aggregate stats for a numeric field.
- **Inputs:** `field_key` (str, required), `wellbore` (str, optional), `start_date` (str, optional), `end_date` (str, optional), `limit` (int, default `200`).

#### `field_values_tool`
- **Purpose:** Per-report raw values for a field. Supports both text and numeric fields.
- **Inputs:** `field_key` (str, required), `wellbore` (str, optional), `rig_name` (str, optional), `start_date` (str, optional), `end_date` (str, optional), `limit` (int, default `500`).
- **Output:** Rows with `report_id`, `report_date`, `value` (and `wellbore` / `rig_name` for context).

### Report Deep Dives

#### `get_drilling_report_by_id_tool`
- **Purpose:** Retrieve the top-level record for a single drilling report.
- **Inputs:** `report_id` (str, required).

#### `get_drilling_report_operations_tool`
- **Purpose:** Retrieve the operations rows for one report (codes, durations, categories).
- **Inputs:** `report_id` (str, required).

#### `operations_summary_tool`
- **Purpose:** Aggregated operations summary (operation count, total/average duration, categories) for one report.
- **Inputs:** `report_id` (str, required).

#### `get_report_fields_tool`
- **Purpose:** All extracted key/value fields for one report.
- **Inputs:** `report_id` (str, required).

#### `get_summary_activities_tool`
- **Purpose:** Rows of the "Summary of Activities (24 hours)" narrative section for one report.
- **Inputs:** `report_id` (str, required). **Output:** Rows with `sequence` (int) and `text` (str).

#### `get_planned_activities_tool`
- **Purpose:** Rows of the "Summary of Planned Activities (24 hours)" section for one report.
- **Inputs:** `report_id` (str, required). **Output:** Rows with `sequence` (int) and `text` (str).

#### `get_drilling_fluid_rows_tool`
- **Purpose:** Drilling fluid name/value rows for one report.
- **Inputs:** `report_id` (str, required).

#### `drilling_fluid_stats_tool`
- **Purpose:** Aggregate drilling fluid stats (counts and numeric min/avg/max) for one report.
- **Inputs:** `report_id` (str, required).

#### `get_pore_pressure_rows_tool`
- **Purpose:** Pore pressure table rows for one report.
- **Inputs:** `report_id` (str, required).

#### `pore_pressure_stats_tool`
- **Purpose:** Aggregate pore pressure stats (depth and mud weight min/avg/max) for one report.
- **Inputs:** `report_id` (str, required).

#### `get_report_full_context_tool`
- **Purpose:** Full report context in one call — summary report, operations, fields, activities, drilling fluid, and pore pressure.
- **Inputs:** `report_id` (str, required).

### Advanced / Fallback

#### `cypher_query_tool`
- **Purpose:** Execute a custom Cypher query against the Neo4j graph. Use only when no specialized tool can produce the required shape.
- **Inputs:** `query` (str, required).
- **Caution:** Clients should perform schema discovery (e.g. `list_available_fields_tool`, sample reports via `list_drilling_reports_tool`, `get_report_fields_tool`) before crafting Cypher.

## Example Payloads

### List reports filtered by wellbore, rig, and date range

```json
{
  "name": "list_reports_with_filters_tool",
  "arguments": {
    "wellbore": "15/9-F-5",
    "rig_name": "TREASURE PROSPECT",
    "start_date": "2016-01-01",
    "end_date": "2016-03-31",
    "limit": 200
  }
}
```

### Depth statistics for a wellbore in a date range

```json
{
  "name": "depth_stats_by_wellbore_tool",
  "arguments": {
    "wellbore": "15/9-F-5",
    "start_date": "2016-01-01",
    "end_date": "2016-06-30"
  }
}
```

### Full context for one report

```json
{
  "name": "get_report_full_context_tool",
  "arguments": { "report_id": "15_9_F_15_D_2016_07_18_Summary Report" }
}
```

## Related Documentation

- [Energy DDR Neo4j MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [Daily Drilling Reports (DDR) Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Daily%20Drilling%20Reports%20%28DDR%29%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
