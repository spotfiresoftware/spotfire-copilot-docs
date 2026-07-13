# Spotfire Library MCP Server — User Guide

spotfire × library × metadata

The `spotfire-lib` MCP server (internal name `sflib`) exposes a curated set of tools for browsing a Spotfire Server's library — listing registered data connectors, discovering Spotfire Analysis files (DXPs) with filters, and retrieving detailed metadata for a specific DXP.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Connector Discovery](#connector-discovery)
  - [DXP Discovery](#dxp-discovery)
  - [DXP Metadata](#dxp-metadata)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Spotfire Library Metadata Agent](../../agents/Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md). It wraps the Spotfire Server's library REST endpoints behind a small set of focused tools:

- Connector discovery (all connectors registered on the Spotfire Server, with type and properties).
- DXP discovery with server-side filtering by creator, title fragment, and library path prefix, with a configurable result limit.
- DXP metadata retrieval (tables, columns, pages, bookmarks, embedded data flags, permissions, and versions) by item ID.

All tools return a **JSON string** representing the Spotfire Server response. Clients typically parse this back into structured data before presenting it. Errors from the Spotfire Server are returned as part of the JSON payload (e.g. an `error` field) rather than thrown as exceptions.

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
- **Purpose:** Retrieve all data connectors registered on the Spotfire Server. Connectors enable Spotfire to load data from external systems (Snowflake, Oracle, TDV, ODBC, Information Links, etc.).
- **Inputs:** _none_.
- **Output:** A JSON string with an `items` array. Each connector entry typically includes:
  - **Basic info** — `id`, `title`, `path`, `type`, `description`.
  - **User metadata** — `createdBy`, `modifiedBy`, `permissions`.
  - **Properties** — connector-specific keys such as `Spotfire.ConnectionSourceDatabase`, `Spotfire.Connector`.
  - **Versioning** — `versionId`, `itemVersions`.
- **When to use:** Answering "what connectors are available?" or "can I connect to system X?" questions.

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
- **Purpose:** Retrieve detailed metadata for a single DXP, including tables, columns, pages, bookmarks, permissions, and version history.
- **Inputs:** `dxp_id` (str, required) — The Spotfire library item ID of the DXP.
- **Output:** A JSON string with basic info, user metadata, properties (table/column/page counts, embedded-data flag, bookmark count), and versioning.
- **When to use:** "Show details for `SalesAnalysis.dxp`", "how many tables/columns/pages in DXP X?", "who can access this DXP?", "version history for this DXP".

## Example Payloads

### List all connectors

```json
{
  "name": "get_data_connections_tool",
  "arguments": {}
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
