# OSDU MCP Server — User Guide

energy × osdu × subsurface-data

The `osdu` MCP server exposes a curated set of tools for querying an OSDU data platform — discovering wells and wellbores, retrieving storage records and versions, running semantic search, inspecting schemas, and tracing record lineage — so that agents and other MCP clients can answer subsurface data questions without writing OSDU API calls.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Core OSDU Access](#core-osdu-access)
  - [Semantic & Domain Discovery](#semantic--domain-discovery)
  - [Well & Dataset Workflows](#well--dataset-workflows)
  - [Schema & Relationship Intelligence](#schema--relationship-intelligence)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [OSDU Agent](../../agents/Spotfire%20Copilot%20-%20OSDU%20Agent%20User%20Guide.md). It wraps the OSDU Search, Storage, Schema, and Entitlements APIs behind OAuth2 client-credentials authentication, and adds higher-level convenience tools for well/wellbore/dataset workflows, semantic search, schema explanations, and lineage traversal.

Output conventions for all tools:

- All tools return JSON text.
- Tool failures return a structured payload with `ok: false` and an `error` object including a code.
- Semantic/domain responses include `schema_version: 2026-04-22.semantic.v1`.

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the [OSDU MCP Server Deployment Guide](Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20Deployment%20Guide.md). The server must be deployed and reachable before the OSDU Agent can be invoked.

## Connecting

| Setting          | Value                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------- |
| Transport        | `streamable-http` (recommended)                                                       |
| URL              | Set via `OSDU_MCP_SERVER_URL` (e.g. `https://mcp-osdu.example.com/mcp`)                |
| Auth             | OAuth2 client credentials against the OSDU token URL                                   |
| Health endpoints | `GET /healthz`, `GET /readyz`, `GET /versionz`                                         |

Agents consuming this server typically set `OSDU_MCP_SERVER_URL` and, optionally, `OSDU_MCP_ALLOW_DEGRADED_STARTUP`. Backend credentials (`OSDU_BASE_URL`, `OSDU_TOKEN_URL`, `OSDU_CLIENT_ID`, `OSDU_CLIENT_SECRET`) are configured on the server at deploy time — see the deployment guide.

## Tool Reference

### Core OSDU Access

#### `osdu_list_legal_tags`
- **Purpose:** List legal tags configured in the OSDU partition.
- **Inputs:** `valid_only` (bool, optional, default `true`).
- **Output:** List of legal tag records.

#### `osdu_list_entitlement_groups`
- **Purpose:** List entitlement groups available in the partition.
- **Inputs:** _none_.
- **Output:** List of group identifiers and descriptions.

#### `osdu_search_records`
- **Purpose:** Search OSDU records by kind and free-text query.
- **Inputs:** `kind` (str, default `*:*:*:*`), `query` (str, default `*`), `limit` (int, default `10`).
- **Output:** Search hits with `id`, `kind`, and a subset of fields.

#### `osdu_get_storage_record`
- **Purpose:** Retrieve a full storage record.
- **Inputs:** `record_id` (str, required), `version` (int, optional).
- **Output:** The record payload, including `data`, references, and ACLs.

### Semantic & Domain Discovery

#### `osdu_semantic_search`
- **Purpose:** Run a semantic search across one or more entity scopes.
- **Inputs:** `query` (str, required), `entity` (one of `datasets`, `wells`, `all`; default `datasets`), `limit` (int, default `10`).
- **Output:** Ranked results with `id`, `kind`, `title`, and relevance metadata.

#### `osdu_find_datasets_by_region`
- **Purpose:** Find datasets associated with a named region.
- **Inputs:** `region` (str, required), `limit` (int, default `20`).
- **Output:** List of dataset records.

#### `osdu_list_wells_by_operator`
- **Purpose:** List wells operated by a specific company.
- **Inputs:** `operator` (str, required), `limit` (int, default `20`).
- **Output:** List of well records.

#### `osdu_find_wells`
- **Purpose:** Find wells by any combination of name, operator, region, and field. Requires at least one filter.
- **Inputs:** `name`, `operator`, `region`, `field` (all str, optional; at least one required), `limit` (int, default `20`).
- **Output:** List of well records matching the supplied filters.

### Well & Dataset Workflows

#### `osdu_get_well_summary`
- **Purpose:** Return a consolidated summary for a well, optionally including its wellbores.
- **Inputs:** `well_id` (str, required), `include_wellbores` (bool, default `true`).
- **Output:** Well record summary plus optional wellbore list.

#### `osdu_list_wellbores_for_well`
- **Purpose:** List wellbores drilled from a parent well.
- **Inputs:** `well_id` (str, required), `limit` (int, default `50`).
- **Output:** List of wellbore records with parent linkage.

#### `osdu_find_datasets_for_well`
- **Purpose:** Find datasets associated with a well, optionally filtered by dataset kind.
- **Inputs:** `well_id` (str, required), `dataset_kind` (str, optional), `include_wellbores` (bool, default `true`), `limit` (int, default `50`).
- **Output:** Dataset records grouped by linkage path.

#### `osdu_get_record_versions`
- **Purpose:** List historical versions of a record.
- **Inputs:** `record_id` (str, required).
- **Output:** Version list with timestamps.

### Schema & Relationship Intelligence

#### `osdu_get_kind_schema`
- **Purpose:** Retrieve the schema definition for a given kind.
- **Inputs:** `kind` (str, required).
- **Output:** Raw schema document.

#### `osdu_explain_schema`
- **Purpose:** Plain-language explanation of a kind's required and reference fields.
- **Inputs:** `kind` (str, required).
- **Output:** Narrative description plus structured field summary.

#### `osdu_find_related_records`
- **Purpose:** Traverse relationships outward from a record, returning a bounded graph.
- **Inputs:** `record_id` (str, required), `relation_type` (str, optional), `depth` (int, default `1`), `max_nodes` (int, default `40`).
- **Output:** Nodes and edges with relation labels.

#### `osdu_explain_record`
- **Purpose:** Narrate what a record represents in context, including its key references.
- **Inputs:** `record_id` (str, required).
- **Output:** Narrative summary plus structured highlights.

#### `osdu_get_dataset_lineage`
- **Purpose:** Trace upstream and downstream lineage for a dataset.
- **Inputs:** `dataset_id` (str, required), `depth` (int, default `2`), `max_nodes` (int, default `40`).
- **Output:** Lineage graph with nodes and edges.

#### `osdu_explain_dataset`
- **Purpose:** Narrate a dataset's content and lineage in plain language.
- **Inputs:** `dataset_id` (str, required).
- **Output:** Narrative summary plus structured highlights.

## Example Payloads

### List legal tags

```json
{
  "name": "osdu_list_legal_tags",
  "arguments": { "valid_only": true }
}
```

### Search well records

```json
{
  "name": "osdu_search_records",
  "arguments": {
    "kind": "*:*:master-data--Well:*",
    "query": "*",
    "limit": 3
  }
}
```

### Find wells by name fragment

```json
{
  "name": "osdu_find_wells",
  "arguments": { "name": "AMR", "limit": 5 }
}
```

### Get well summary with wellbores

```json
{
  "name": "osdu_get_well_summary",
  "arguments": {
    "well_id": "osdu:master-data--Well:1042",
    "include_wellbores": true
  }
}
```

### Trace dataset lineage

```json
{
  "name": "osdu_get_dataset_lineage",
  "arguments": {
    "dataset_id": "osdu:dataset--File.Generic:abcd-1234",
    "depth": 2,
    "max_nodes": 40
  }
}
```

## Related Documentation

- [OSDU MCP Server Deployment Guide](Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [OSDU Agent User Guide](../../agents/Spotfire%20Copilot%20-%20OSDU%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
