# Data Virtualization (DV) MCP Server — User Guide

data × data-virtualization × odata

The `dv` MCP server exposes a curated set of tools for discovering data sources, tables, and columns published by a Data Virtualization layer, plus a generic OData v4 query executor, so that agents and other MCP clients can answer data questions without writing direct database calls.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Data Source Discovery](#data-source-discovery)
  - [Table Discovery](#table-discovery)
  - [Column Discovery](#column-discovery)
  - [Column Metadata](#column-metadata)
  - [OData v4 Query Execution](#odata-v4-query-execution)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Data Virtualization (DV) Agent](../../agents/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20Agent%20User%20Guide.md). It wraps the DV server's catalog and OData v4 endpoints behind a small set of focused tools:

- Data source discovery and information.
- Table discovery, globally or scoped to a data source.
- Column discovery at four scopes (all, by data source, by table, by data source + table).
- Per-column metadata (data type, length, etc.).
- Arbitrary OData v4 query execution.

Output conventions:

- Discovery tools return **comma-separated strings** of identifiers (data sources, tables, fully-qualified columns).
- `get_column_metadata_tool` returns a descriptive string such as `Column Name: ..., Data Type: ..., Column Length: ...`.
- `odata4_query_executor_tool` returns the DV server response (typically JSON) as a string.

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the [Data Virtualization (DV) MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20Deployment%20Guide.md). The server must be deployed and reachable before the DV Agent can be invoked.

## Connecting

| Setting          | Value                                                                    |
| ---------------- | ------------------------------------------------------------------------ |
| Transport        | `streamable-http` (recommended)                                          |
| URL              | Set via `DV_MCP_SERVER_URL` (e.g. `https://mcp-dv.example.com/mcp`)       |
| Auth             | The server authenticates to the DV layer via configured credentials; clients do not pass DV credentials. |

Backend configuration (`DV_URL`, `DV_USERNAME`, `DV_PASSWORD`) is set on the server at deploy time — see the deployment guide.

## Tool Reference

### Data Source Discovery

#### `list_all_datasources_tool`
- **Purpose:** Return all data sources available in the DV layer.
- **Inputs:** _none_.
- **Output:** Comma-separated list of data source names.

#### `get_datasource_info_tool`
- **Purpose:** Return information about a specific data source.
- **Inputs:** `datasource` (str, required).
- **Output:** A descriptive string with the data source's properties.

### Table Discovery

#### `list_all_tables_tool`
- **Purpose:** Return every table exposed across all data sources.
- **Inputs:** _none_.
- **Output:** Comma-separated list of tables.

#### `list_tables_by_datasource_tool`
- **Purpose:** Return tables exposed by a specific data source.
- **Inputs:** `datasource` (str, required).
- **Output:** Comma-separated list of tables in that data source.

### Column Discovery

#### `list_all_columns_tool`
- **Purpose:** Return columns for all tables across all data sources (used by agents to build a mental model of the catalog).
- **Inputs:** `table` (str). The current implementation accepts a `table` argument; in practice agents typically call this without a meaningful filter to get the broad list.
- **Output:** Comma-separated list of `datasource.table.column` names.

#### `list_columns_by_datasource_tool`
- **Purpose:** Return columns for all tables within a single data source.
- **Inputs:** `datasource` (str, required).
- **Output:** Comma-separated list of `table.column` names.

#### `list_columns_by_table_tool`
- **Purpose:** Return columns for a specific table (across all data sources that expose a table with that name).
- **Inputs:** `table` (str, required).
- **Output:** Comma-separated list of `datasource.table.column` names.

#### `list_columns_by_datasource_and_table_tool`
- **Purpose:** Return columns for one specific table in one specific data source.
- **Inputs:** `datasource` (str, required), `table` (str, required).
- **Output:** Comma-separated list of column names.

### Column Metadata

#### `get_column_metadata_tool`
- **Purpose:** Return metadata for a single column (data type, length, and other properties).
- **Inputs:** `datasource` (str, required), `table` (str, required), `column` (str, required).
- **Output:** Descriptive string such as `Column Name: customer_id, Data Type: INT, Column Length: 10`.

### OData v4 Query Execution

#### `odata4_query_executor_tool`
- **Purpose:** Execute an OData v4 query against the DV server and return the response.
- **Inputs:** `query` (str, required) — the full OData v4 request including service endpoint and query parameters (`$filter`, `$select`, `$orderby`, `$top`, `$expand`, `$apply`, etc.).
- **Output:** The DV server response (typically JSON) as a string.
- **Best practices:**
  - Use `$top` and `$select` to keep responses small during exploration.
  - Prefer `$apply=aggregate(...)` for max/min/sum/avg questions.
  - Ensure the query follows OData v4 syntax — discover column names first via the column discovery tools.

## Example Payloads

### List available data sources

```json
{
  "name": "list_all_datasources_tool",
  "arguments": {}
}
```

### List columns for one table in one data source

```json
{
  "name": "list_columns_by_datasource_and_table_tool",
  "arguments": {
    "datasource": "cds_tutorial",
    "table": "Order"
  }
}
```

### Execute an OData v4 query

```json
{
  "name": "odata4_query_executor_tool",
  "arguments": {
    "query": "/cds_tutorial/Order?$filter=UnitPrice gt 20&$select=ProductName,UnitPrice&$top=10"
  }
}
```

### Execute an OData v4 aggregation

```json
{
  "name": "odata4_query_executor_tool",
  "arguments": {
    "query": "/cds_tutorial/ViewOrder?$apply=aggregate(discount with max as highest_discount)"
  }
}
```

## Related Documentation

- [Data Virtualization (DV) MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [Data Virtualization (DV) Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
