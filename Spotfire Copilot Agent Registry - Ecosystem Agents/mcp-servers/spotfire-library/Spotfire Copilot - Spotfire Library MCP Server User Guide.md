# Spotfire Library MCP Server — User Guide

spotfire × library × metadata

The `spotfire-lib` MCP server (internal name `sflib`) exposes a Spotfire Server's library through three generic tools: one to **list/search** any kind of library item (DXPs, data connections, information links, data functions, columns, and more) with filters, one to fetch the full **metadata** of a single item by its id, and one to list an item's **children** (e.g. a data source's columns, or a folder's contents).

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Listing Library Items](#listing-library-items)
  - [Item Metadata](#item-metadata)
  - [Item Children](#item-children)
  - [Supported Item Types](#supported-item-types)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Spotfire Library Metadata Agent](../../agents/Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md). It wraps the Spotfire Server's library REST endpoints behind a small set of focused tools:

- Listing/searching any supported library item type, with server-side filtering by creator, title fragment, and library path prefix, plus a configurable result limit.
- Retrieving the full metadata of a single library item (basic info, permissions, and stored properties) by its item id — for any item type.
- Listing the direct children of an item by its id (e.g. the columns of a data source or information link, or the items inside a folder).

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

### Listing Library Items

#### `list_library_items_tool`
- **Purpose:** List or search Spotfire library items of a given kind (browse / discovery). Choose the kind with `item_type`.
- **Inputs:**
  - `item_type` (str, required) — Which kind of item to list. One of the [supported item types](#supported-item-types) (e.g. `dxp`, `data_connection`, `information_link`).
  - `created_by` (str, optional) — Filter by creator display name (contains match).
  - `title_contains` (str, optional) — Filter by title text (contains match).
  - `path_prefix` (str, optional) — Filter by library path prefix (e.g. `/public/Energy`).
  - `limit` (int, optional, default `100`) — Maximum number of entries to return.
- **Output:** A JSON string with `count`, `returned`, the applied `filters`, and an `items` array. Each entry is trimmed to `id`, `title`, `path`, `type`, `createdBy`, and `modified`. If the result set is too large to return reliably, the tool instead returns a `status: "too_many_results"` object with guidance to refine the query.
- **When to use:** "What DXPs are available?", "list the data connections under /public/Energy", "what Information Links exist?".

### Item Metadata

#### `get_library_item_metadata_tool`
- **Purpose:** Retrieve the full library metadata for a single item by its id. Works for **any** item type (the single-item endpoint is type-agnostic).
- **Inputs:** `item_id` (str, required) — The Spotfire library item id.
- **Output:** A JSON string with basic info (`id`, `title`, `path`, `type`, `description`), user metadata (`createdBy`, `modifiedBy`, `permissions`), and the item's `properties` (the key/value pairs the Spotfire Server stores; the large preview-thumbnail property `Spotfire.Preview.Thumb` is stripped out).
- **Id resolution:** If you only have a name or title, first call `list_library_items_tool` with the matching `item_type` and `title_contains=<name>` to resolve the `id`, then call this tool.
- **Note:** This returns the item's *library* metadata; for a DXP it does not open the analysis file, so it does not compute per-analysis internals such as table/column/page/bookmark counts unless the Spotfire Server has recorded them as item properties.

### Item Children

#### `get_library_item_children_tool`
- **Purpose:** List the direct children of a library item by its id — for example the columns contained in a data source or information link, or the items inside a folder.
- **Inputs:**
  - `item_id` (str, required) — The Spotfire library item id whose children to list.
  - `created_by` (str, optional) — Filter children by creator display name (contains match).
  - `title_contains` (str, optional) — Filter children by title text (contains match).
  - `path_prefix` (str, optional) — Filter children by library path prefix.
  - `limit` (int, optional, default `100`) — Maximum number of child entries to return.
- **Output:** The same shape as `list_library_items_tool` — a JSON string with `count`, `returned`, the applied `filters`, and an `items` array (each child trimmed to `id`, `title`, `path`, `type`, `createdBy`, `modified`). If the child set is too large it returns a `status: "too_many_results"` object. Note that some children (e.g. columns) have no library `path`.
- **Id resolution:** If you only have a name, first call `list_library_items_tool` with the matching `item_type` to resolve the parent's `id`, then call this tool.
- **When to use:** "What columns does the `<name>` data source have?", "what's inside the `<name>` folder?".

### Supported Item Types

`item_type` accepts one of: `dxp`, `data_connection`, `visualization_mod`, `data_source`, `data_function`, `action_mod`, `sbdf`, `shape`, `filter`, `join`, `connection_data_source`, `procedure`, `dxp_script`, `color_scheme`, `information_link`, `folder`, `column`, `automation_service_job`.

## Example Payloads

### List DXPs under a library subtree, filtered by title

```json
{
  "name": "list_library_items_tool",
  "arguments": {
    "item_type": "dxp",
    "path_prefix": "/public/Energy",
    "title_contains": "Well",
    "limit": 50
  }
}
```

### List all data connections

```json
{
  "name": "list_library_items_tool",
  "arguments": {
    "item_type": "data_connection"
  }
}
```

### Get full metadata for a specific item (any type)

```json
{
  "name": "get_library_item_metadata_tool",
  "arguments": {
    "item_id": "1a2b3c4d-5e6f-7890-abcd-ef1234567890"
  }
}
```

### List the children of an item (e.g. a data source's columns)

```json
{
  "name": "get_library_item_children_tool",
  "arguments": {
    "item_id": "9d99f5a1-18fc-4a5e-8a79-db49fe512075"
  }
}
```

## Related Documentation

- [Spotfire Library MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [Spotfire Library Metadata Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
