# Databricks MCP Server — User Guide

data × databricks × unity-catalog × sql

The `databricks` MCP server exposes a curated set of tools for exploring Unity Catalog metadata, tracing table lineage (including notebooks and jobs), and executing SQL against a Databricks SQL warehouse, so that agents and other MCP clients can answer data questions without writing Databricks API calls.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Catalog & Schema Discovery](#catalog--schema-discovery)
  - [Table Detail & Lineage](#table-detail--lineage)
  - [SQL Execution](#sql-execution)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Databricks Agent](../../agents/Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md). It wraps the Databricks SDK behind a small set of Markdown-returning tools focused on:

- Catalog, schema, and table discovery.
- Column and partitioning detail for tables.
- Upstream/downstream lineage plus notebook and job references.
- SQL execution against a configured SQL warehouse.

All descriptive tools return Markdown so that responses are easy to read in chat and copy-paste into documentation. `execute_sql_query` returns Markdown tables for SELECT-style statements. Tool failures return a structured error message in the response payload.

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the [Databricks MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Deployment%20Guide.md). The server must be deployed and reachable before the Databricks Agent can be invoked.

## Connecting

| Setting          | Value                                                                        |
| ---------------- | ---------------------------------------------------------------------------- |
| Transport        | `streamable-http` (recommended)                                              |
| URL              | Set via `DATABRICKS_MCP_SERVER_URL` (e.g. `https://mcp-databricks.example.com/mcp`) |
| Auth             | The server authenticates to Databricks via the configured token / service principal; clients do not pass Databricks credentials. |
| Health endpoints | `GET /healthz`, `GET /readyz`                                                 |

Backend configuration (`DATABRICKS_HOST`, `DATABRICKS_TOKEN`, `DATABRICKS_SQL_WAREHOUSE_ID`) is set on the server at deploy time. The SQL warehouse ID is required for `execute_sql_query` and for lineage queries. The identity behind the token must have `USE CATALOG` / `USE SCHEMA` / `SELECT` on the objects the agent reads, and `CAN_USE` on the configured SQL warehouse.

## Tool Reference

### Catalog & Schema Discovery

#### `list_uc_catalogs`
- **Purpose:** List all Unity Catalogs the configured identity can access, with names, descriptions, and types.
- **Inputs:** _none_.
- **Output:** Markdown list of catalogs.
- **When to use:** Starting point when you don't know catalog names.

#### `describe_uc_catalog`
- **Purpose:** Summarize a specific catalog by listing its schemas with descriptions.
- **Inputs:** `catalog_name` (str, required) — e.g. `prod`, `dev`, `samples`.
- **Output:** Markdown summary of schemas in the catalog.

#### `describe_uc_schema`
- **Purpose:** Describe a schema's tables, optionally with column-level detail.
- **Inputs:** `catalog_name` (str, required), `schema_name` (str, required), `include_columns` (bool, optional, default `false`; set `true` to include columns for each table — useful when drafting SQL).
- **Output:** Markdown listing of tables (and columns when requested).

### Table Detail & Lineage

#### `describe_uc_table`
- **Purpose:** Describe a specific table with full column detail, types, comments, and partitioning. Optionally include comprehensive lineage.
- **Inputs:** `full_table_name` (str, required) — fully qualified three-part name, e.g. `prod.sales.orders`; `include_lineage` (bool, optional, default `false`). When `true`, the response also includes:
  - **Table lineage:** upstream tables (read by this table) and downstream tables (read from this table).
  - **Notebook & job lineage:** notebooks that read from or write to this table, including notebook name, workspace path, and associated Databricks job info (job name, ID, task details).
  - **Code discovery hints:** notebook paths so the calling agent can open the notebooks directly in the workspace and review actual transformation logic.
- **Output:** Markdown table description, optionally followed by lineage sections.

### SQL Execution

#### `execute_sql_query`
- **Purpose:** Execute a SQL statement against the configured Databricks SQL warehouse and return formatted results.
- **Inputs:** `sql` (str, required) — the complete SQL string to execute.
- **Output:** Markdown table of results for SELECT-style queries, or a status message for DDL/DML.
- **Timeout:** The underlying SDK call uses a `wait_timeout` of `50s`. Long-running queries may exceed this window.

## Example Payloads

### List available catalogs

```json
{
  "name": "list_uc_catalogs",
  "arguments": {}
}
```

### Describe a schema with column detail (good before drafting SQL)

```json
{
  "name": "describe_uc_schema",
  "arguments": {
    "catalog_name": "samples",
    "schema_name": "accuweather",
    "include_columns": true
  }
}
```

### Describe one table with lineage

```json
{
  "name": "describe_uc_table",
  "arguments": {
    "full_table_name": "samples.accuweather.forecast_hourly_metric",
    "include_lineage": true
  }
}
```

### Execute a SQL query

```json
{
  "name": "execute_sql_query",
  "arguments": {
    "sql": "SELECT city, MAX(temperature) AS max_temp FROM samples.accuweather.forecast_hourly_metric GROUP BY city ORDER BY max_temp DESC LIMIT 10"
  }
}
```

## Related Documentation

- [Databricks MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [Databricks Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
