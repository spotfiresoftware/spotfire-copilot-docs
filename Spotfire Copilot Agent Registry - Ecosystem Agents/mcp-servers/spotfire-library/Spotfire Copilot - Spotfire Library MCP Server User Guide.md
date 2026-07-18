# Spotfire Library MCP Server — User Guide

spotfire × library × metadata

The `spotfire-lib` MCP server (internal name `sflib`) exposes a curated set of tools for browsing a Spotfire Server's library — listing registered data connectors (with filters), retrieving detailed metadata for a specific connector, discovering Spotfire Analysis files (DXPs) with filters, and retrieving detailed metadata for a specific DXP.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Connector Discovery](#connector-discovery)
  - [Connector Metadata](#connector-metadata)
  - [DXP Discovery](#dxp-discovery)
  - [DXP Metadata](#dxp-metadata)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Spotfire Library Metadata Agent](../../agents/Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md). It wraps the Spotfire Server's library REST endpoints behind a small set of focused tools:

- Connector discovery with server-side filtering by creator, title fragment, and library path prefix, with a configurable result limit.
- Connector metadata retrieval (connector type, connection properties, and permissions) by item ID.
- DXP discovery with server-side filtering by creator, title fragment, and library path prefix, with a configurable result limit.
- DXP metadata retrieval (path, item properties, and permissions) by item ID.

All tools return a **JSON string** representing the Spotfire Server response. Clients typically parse this back into structured data before presenting it. Failures are returned as short plain-text status messages (for example `"No dxps found"`, `"No data connections found"`, or `"Failed to get access token"`) rather than thrown as exceptions. When a discovery result would be too large to return reliably, the list tools instead return a JSON object whose `status` is `"too_many_results"`, with guidance to refine the query.

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the [Spotfire Library MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md). The server must be deployed and reachable before the Spotfire Library Metadata Agent can be invoked.

## Connecting

| Setting          | Value                                                                          |
| ---------------- | ------------------------------------------------------------------------------ |
| Transport        | `streamable-http` (recommended)                                                |
| URL              | Set via `SFLIB_MCP_SERVER_URL` (e.g. `https://mcp-spotfire-lib.example.com/mcp`) |
| Auth             | The server authenticates to the Spotfire Server using a configured client ID and secret; optional MCP-side auth via JWKS or token allowlist for clients. |

Backend configuration (`SF_URL`, `SF_CLIENT_ID`, `SF_CLIENT_SECRET`) is set on the server at deploy time. The server also exposes `/healthz` and `/readyz`; `/readyz` validates connectivity to the Spotfire Server with a configurable timeout (`READYZ_TIMEOUT`, default `5.0` seconds).

## Tool Reference

### Connector Discovery

#### `get_data_connections_tool`
- **Purpose:** Retrieve the data connectors registered on the Spotfire Server with optional server-side filtering and limiting. Connectors enable Spotfire to load data from external systems (Snowflake, Oracle, TDV, ODBC, Information Links, etc.).
- **Inputs:**
  - `created_by` (str, optional) — Filter by creator display name (contains match).
  - `title_contains` (str, optional) — Filter by title text (contains match).
  - `path_prefix` (str, optional) — Filter by library path prefix (e.g. `/public/Connections`).
  - `limit` (int, optional, default `100`) — Maximum number of connector entries to return.
- **Output:** A JSON string with `count`, `returned`, the applied `filters`, and an `items` array. Each connector entry is trimmed to `id`, `title`, `path`, `type`, `createdBy`, and `modified`. If the result set is too large to return reliably, the tool instead returns a `status: "too_many_results"` object with guidance to refine the query.
- **When to use:** Answering "what connectors are available?" or "can I connect to system X?" questions.

### Connector Metadata

#### `get_dataconnection_metadata_tool`
- **Purpose:** Retrieve detailed library metadata for a single data connection item.
- **Inputs:** `dataconnection_id` (str, required) — The Spotfire library item ID of the data connection.
- **Output:** A JSON string with basic info (`id`, `title`, `path`, `type`, `description`), user metadata (`createdBy`, `modifiedBy`, `permissions`), and connector-specific `properties` (key/value pairs such as `Spotfire.ConnectionSourceDatabase` or `Spotfire.Connector`, when the Spotfire Server records them). The large preview-thumbnail property (`Spotfire.Preview.Thumb`) is stripped out to keep the payload small.
- **When to use:** "Show details for the `SalesDB` data connection", "what source database / connector type does X use?", "who can access this connection?".

### DXP Discovery

#### `get_dxps_tool`
- **Purpose:** Retrieve Spotfire Analysis files (DXPs) from the library with optional server-side filtering and limiting.
- **Inputs:**
  - `created_by` (str, optional) — Filter by creator display name (contains match).
  - `title_contains` (str, optional) — Filter by title text (contains match).
  - `path_prefix` (str, optional) — Filter by library path prefix (e.g. `/public/Energy`).
  - `limit` (int, optional, default `100`) — Maximum number of DXP entries to return.
- **Output:** A JSON string with an `items` array. Each DXP entry typically includes basic info (`id`, `title`, `path`) and user metadata (`createdBy`, `modified`).
- **Best practices:**
  - Provide as many filters as the user mentioned to keep payloads small.
  - For exploratory queries, use a small `limit` (e.g. 20–25) first and widen if needed.

### DXP Metadata

#### `get_dxp_metadata_tool`
- **Purpose:** Retrieve detailed library metadata for a single DXP item.
- **Inputs:** `dxp_id` (str, required) — The Spotfire library item ID of the DXP.
- **Output:** A JSON string with the item's basic info (`id`, `title`, `path`, `type`, `description`), user metadata (`createdBy`, `modifiedBy`, `permissions`), and its `properties` — the key/value pairs the Spotfire Server attaches to the item. The large preview-thumbnail property (`Spotfire.Preview.Thumb`) is stripped out to keep the payload small.
- **When to use:** "Show library details for `SalesAnalysis.dxp`", "who created / who can access this DXP?", "what properties are set on this DXP?".
- **Note:** This returns the DXP's *library* metadata; it does not open the analysis file, so it does not compute per-analysis internals such as table, column, page, or bookmark counts unless the Spotfire Server has recorded them as item properties.

## Example Payloads

### List all connectors

```json
{
  "name": "get_data_connections_tool",
  "arguments": {}
}
```

### Get full metadata for a specific data connection

```json
{
  "name": "get_dataconnection_metadata_tool",
  "arguments": {
    "dataconnection_id": "0f9e8d7c-6b5a-4321-fedc-ba9876543210"
  }
}
```

### List DXPs under a library subtree, filtered by title

```json
{
  "name": "get_dxps_tool",
  "arguments": {
    "path_prefix": "/public/Energy",
    "title_contains": "Well",
    "limit": 50
  }
}
```

### Get full metadata for a specific DXP

```json
{
  "name": "get_dxp_metadata_tool",
  "arguments": {
    "dxp_id": "1a2b3c4d-5e6f-7890-abcd-ef1234567890"
  }
}
```

## Related Documentation

- [Spotfire Library MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [Spotfire Library Metadata Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
