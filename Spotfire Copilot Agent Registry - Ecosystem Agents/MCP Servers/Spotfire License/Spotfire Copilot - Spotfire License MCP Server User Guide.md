# Spotfire License MCP Server — User Guide

spotfire × licenses × administration

The `spotfire-lic` MCP server (internal name `sflic`) exposes a curated set of tools for inspecting and managing Spotfire licenses and license functions on a Spotfire Server — listing the license catalog, looking up entitlements for users and groups, assigning licenses (with specific functions) to groups, and revoking them.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [License Catalog](#license-catalog)
  - [User Entitlements](#user-entitlements)
  - [Group Entitlements](#group-entitlements)
  - [License Assignment](#license-assignment)
  - [License Revocation](#license-revocation)
  - [User & Group Discovery](#user--group-discovery)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Spotfire License Management Agent](../../Agents/Spotfire%20Copilot%20-%20Spotfire%20License%20Management%20Agent%20User%20Guide.md). It wraps the Spotfire Server's license-administration REST endpoints behind a small set of focused tools:

- License catalog and per-license function listing.
- User entitlement lookups (licenses and functions enabled for a user).
- Group entitlement lookups (licenses and functions assigned to a group), with optional inheritance.
- License assignment to a group with a specified set of functions.
- License revocation from a group.
- User and group discovery on the Spotfire Server.

All tools return a **JSON string** representing the Spotfire Server response. Errors are returned as part of the JSON payload (e.g. an `error` field) rather than thrown as exceptions.

> **Caution.** `set_license_for_group_tool` and `remove_license_from_group_tool` **mutate state** on the Spotfire Server. Clients should confirm intent before invoking them.

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the [Spotfire License MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20Deployment%20Guide.md). The server must be deployed and reachable before the Spotfire License Management Agent can be invoked.

## Connecting

| Setting          | Value                                                                          |
| ---------------- | ------------------------------------------------------------------------------ |
| Transport        | `streamable-http` (recommended)                                                |
| URL              | Set via `SFLIC_MCP_SERVER_URL` (e.g. `https://mcp-spotfire-lic.example.com/mcp`) |
| Auth             | The server authenticates to the Spotfire Server using a configured client ID and secret; optional MCP-side auth via JWKS or token allowlist for clients. |

Backend configuration (`SF_URL`, `SF_CLIENT_ID`, `SF_CLIENT_SECRET`) is set on the server at deploy time — see the deployment guide.

## Tool Reference

### License Catalog

#### `list_all_licenses_and_functions_tool`
- **Purpose:** List every license defined on the Spotfire Server, including the full set of functions each license contains.
- **Inputs:** _none_.
- **When to use:** Top-level "what licenses exist?" questions, or as the first call before drilling into a specific license.

#### `list_license_functions_tool`
- **Purpose:** List the functions that belong to a single license.
- **Inputs:** `license_name` (str, required) — e.g. `Spotfire Analyst`.
- **When to use:** "What functions are in `Spotfire Analyst`?", or before assigning a license so the caller can choose a function subset.

### User Entitlements

#### `list_user_licenses_tool`
- **Purpose:** Return every license and every enabled license function for a specific user (typically resolved through the user's group memberships).
- **Inputs:** `user_id` (str, required) — the Spotfire user identifier (UUID).
- **When to use:** "What licenses does user X have?", "What can user X do?"

#### `list_user_license_functions_tool`
- **Purpose:** Return the functions of a single license that are enabled for a specific user.
- **Inputs:** `license_name` (str, required), `user_id` (str, required).
- **When to use:** Fine-grained checks like "Does user X have `DataOnDemand` under `Spotfire Analyst`?"

### Group Entitlements

#### `list_group_licenses_tool`
- **Purpose:** Return every license and every enabled license function assigned to a specific group, with the option to include licenses inherited from parent groups.
- **Inputs:** `group_id` (str, required), `include_inherited` (bool, optional, default `false`).
- **When to use:** "What licenses does the Analysts group have?"; set `include_inherited=true` for the full effective entitlement.

#### `list_group_license_functions_tool`
- **Purpose:** Return the functions of a single license that are enabled for a specific group, with optional inheritance.
- **Inputs:** `license_name` (str, required), `group_id` (str, required), `include_inherited` (bool, optional, default `false`).
- **When to use:** "Which `Spotfire Analyst` functions are enabled for the Analysts group?"

### License Assignment

#### `set_license_for_group_tool`
- **Purpose:** Assign (or update) a license for a group with a specified list of functions. **Mutates state** on the Spotfire Server.
- **Inputs:** `license_name` (str, required), `group_id` (str, required), `functions` (list of str, required) — the function names to enable for the group under this license. To enable all, pass the full function list (see `list_license_functions_tool`).
- **Best practices:**
  - Read `list_license_functions_tool` first to know the valid function names.
  - Confirm the group via `get_all_groups_tool` (or a direct group ID) before calling.

### License Revocation

#### `remove_license_from_group_tool`
- **Purpose:** Remove a license from a group. **Mutates state** on the Spotfire Server.
- **Inputs:** `license_name` (str, required), `group_id` (str, required).
- **When to use:** Revoking a license from a group entirely. To narrow the function set instead, prefer `set_license_for_group_tool` with a reduced function list.

### User & Group Discovery

#### `get_all_groups_tool`
- **Purpose:** List every group defined on the Spotfire Server.
- **Inputs:** _none_.
- **When to use:** Resolving a group name to a `group_id` before any entitlement query or change.

#### `get_all_users_tool`
- **Purpose:** List every user defined on the Spotfire Server.
- **Inputs:** _none_.
- **When to use:** Resolving a user name to a `user_id` before an entitlement query.

## Example Payloads

### List the full license catalog

```json
{
  "name": "list_all_licenses_and_functions_tool",
  "arguments": {}
}
```

### Show a group's effective entitlements (with inheritance)

```json
{
  "name": "list_group_licenses_tool",
  "arguments": {
    "group_id": "9f8e7d6c-5b4a-3210-fedc-ba9876543210",
    "include_inherited": true
  }
}
```

### Assign a license to a group with selected functions

```json
{
  "name": "set_license_for_group_tool",
  "arguments": {
    "license_name": "Spotfire Analyst",
    "group_id": "9f8e7d6c-5b4a-3210-fedc-ba9876543210",
    "functions": ["OpenAnalysisInClient", "DataOnDemand", "ScheduledUpdates"]
  }
}
```

### Remove a license from a group

```json
{
  "name": "remove_license_from_group_tool",
  "arguments": {
    "license_name": "Spotfire Business Author",
    "group_id": "9f8e7d6c-5b4a-3210-fedc-ba9876543210"
  }
}
```

## Related Documentation

- [Spotfire License MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [Spotfire License Management Agent User Guide](../../Agents/Spotfire%20Copilot%20-%20Spotfire%20License%20Management%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
