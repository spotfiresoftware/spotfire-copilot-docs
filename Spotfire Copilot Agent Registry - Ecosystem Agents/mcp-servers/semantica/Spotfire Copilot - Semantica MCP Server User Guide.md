# Semantica MCP Server — User Guide

semantica × industry-data-model × knowledge-graph

The Semantica MCP server exposes read-only tools for exploring **industry data models** stored
in a knowledge graph. Its primary surface is a set of **schema tools** that describe and
navigate a loaded data model — industries, domains, tables, columns, business-glossary terms,
and foreign-key relationships — so that agents and other MCP clients can answer data-model
questions without reading raw schemas. It backs the
[Semantica Oil & Gas Agent](../../agents/Spotfire%20Copilot%20-%20Semantica%20Oil%20%26%20Gas%20Agent%20User%20Guide.md).

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Orientation](#orientation)
  - [Search and Describe](#search-and-describe)
  - [Relationships](#relationships)
  - [Investigation](#investigation)
  - [Spotfire Context](#spotfire-context)
- [Additional Tool Categories](#additional-tool-categories)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server publishes the **industry schema tools** (names prefixed `schema_`) that let an
agent explore a loaded data model. The data model is loaded into a Neo4j knowledge graph; the
server reads it (and refreshes from it) at runtime.

Output conventions:

- All tools return JSON text.
- Tool failures return a structured payload with an `error` field describing the cause.
- Tools are **read-only** and strictly grounded: they return what the loaded model contains and
  never invent tables, columns, types, or relationships. Approximate matches are flagged as
  candidates rather than silently confirmed.
- Most tools accept an `industry` key (e.g. `oil_gas`, `manufacturing`) to scope results to one
  model; omit it to search across all loaded models where supported.

The schema tools are published **only when the server is connected to a Neo4j knowledge graph**
with a data model loaded. The server can also publish Semantica's general-purpose tool
categories — see [Additional Tool Categories](#additional-tool-categories).

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the
[Semantica MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Semantica%20MCP%20Server%20Deployment%20Guide.md).
The server reads a Neo4j knowledge graph that must have the industry data model loaded before
the schema tools return results. The server must be deployed and reachable before the Semantica
Oil & Gas Agent can be invoked.

## Connecting

| Setting          | Value                                                                           |
| ---------------- | ------------------------------------------------------------------------------- |
| Transport        | `streamable-http` (recommended)                                                 |
| URL              | Set via `SEMANTICA_OILGAS_MCP_SERVER_URL` (e.g. `https://mcp-semantica.example.com/mcp`) |
| Auth             | Configured on the server at deploy time (static bearer token or OAuth/JWKS)      |

## Tool Reference

### Orientation

#### `schema_list_industries`
- **Purpose:** List the industry data models loaded in the knowledge graph (e.g. `manufacturing`, `oil_gas`) with domain/table/attribute counts. Use first to see what the agent can answer about.
- **Inputs:** _none_.

#### `schema_list_domains`
- **Purpose:** List the business domains of an industry model (e.g. production, drilling, reservoir) with descriptions and table counts.
- **Inputs:** `industry` (str, optional — e.g. `oil_gas`; omit for all).

### Search and Describe

#### `schema_search`
- **Purpose:** Search the model for tables, attributes/columns, or domains by name, business-glossary term, or description (fuzzy substring). Use for "which table has X?" / "find columns about Y".
- **Inputs:** `query` (str, required), `industry` (str, optional), `kind` (str, optional — `table` | `attribute` | `domain`), `limit` (int, default `20`).

#### `schema_describe_table`
- **Purpose:** Describe a table — its domain, description, primary key, columns (name/type/glossary), and its outgoing and incoming foreign-key relationships. Accepts a table name or `<domain>.<table>`.
- **Inputs:** `table` (str, required), `industry` (str, optional), `attribute_limit` (int, default `200`).

### Relationships

#### `schema_get_related_tables`
- **Purpose:** From a known table, discover tables connected through declared foreign-key relationships (up to `max_hops`). Returns each related table with join columns, direction, hop count, and path.
- **Inputs:** `industry` (str, required), `table_name` (str, required), `max_hops` (int, 1–3, default `1`), `limit` (int, default `25`, max `100`).

#### `schema_find_relationship_paths`
- **Purpose:** Explain how two tables connect: the shortest modeled foreign-key paths between a source and target table, each as an ordered sequence of tables with join columns and direction. Returns a clear no-path result when none exists (never invents a link).
- **Inputs:** `industry` (str, required), `source` (str, required), `target` (str, required), `max_hops` (int, 1–5, default `3`), `limit` (int, default `10`, max `25`).

### Investigation

#### `schema_get_investigation_context`
- **Purpose:** Given a business question (and optional Spotfire table/column names), return a structured, schema-grounded context: matched concepts and tables, modeled relationships among them, adjacent domains, unresolved Spotfire-name mappings, and suggested follow-up searches. Flags uncertain mappings as candidates.
- **Inputs:** `industry` (str, required), `business_question` (str, required), `analysis_name` (str, optional), `data_tables` (list[str], optional), `columns` (list[str], optional), `selected_metric` (str, optional), `selected_entities` (list[str], optional), `limit` (int, default `15`, max `50`).

#### `schema_suggest_dimensions`
- **Purpose:** Recommend model-supported dimensions to explore next for an investigation type. Each suggestion has a status (`supported` | `candidate` | `not_found`), the backing table/attributes, and the modeled path from a starting concept. Never claims a dimension the loaded model does not support.
- **Inputs:** `industry` (str, required), `investigation_type` (str, required — for Oil & Gas: `production_decline`, `well_comparison`, `maintenance_investigation`, `well_traceability`), `starting_concepts` (list[str], optional), `available_tables` (list[str], optional), `available_columns` (list[str], optional), `limit` (int, default `12`, max `40`).

### Spotfire Context

#### `schema_resolve_spotfire_context`
- **Purpose:** Deterministically map Spotfire dashboard metadata (table and column names) to the loaded model. Returns exact/normalized matches plus unconfirmed candidates and unresolved fields; approximate matches are flagged, never silently confirmed.
- **Inputs:** `industry` (str, required), `data_tables` (list[str], optional), `columns` (list[str], optional), `selected_metric` (str, optional), `selected_entity` (str, optional).

## Additional Tool Categories

Beyond the industry schema tools, the Semantica server can publish Semantica's general-purpose
tool categories for building and working with context knowledge graphs:
`extraction`, `decisions`, `graph`, `reasoning`, `export`, and `retrieval`. These are controlled
by the `SEMANTICA_ENABLED_TOOL_CATEGORIES` setting (see the Deployment Guide). The Semantica
Oil & Gas Agent uses the `schema_*` tools above; the additional categories are for advanced
knowledge-graph use cases and are not required by that agent.

## Example Payloads

### List loaded industry models

```json
{ "name": "schema_list_industries", "arguments": {} }
```

### Find the table that holds a concept

```json
{
  "name": "schema_search",
  "arguments": { "industry": "oil_gas", "query": "daily production volume", "kind": "table", "limit": 10 }
}
```

### Describe a table

```json
{
  "name": "schema_describe_table",
  "arguments": { "industry": "oil_gas", "table": "downtime_event" }
}
```

### Find how two tables connect

```json
{
  "name": "schema_find_relationship_paths",
  "arguments": { "industry": "oil_gas", "source": "land.lease", "target": "production.daily_production", "max_hops": 4 }
}
```

### Investigate a business question

```json
{
  "name": "schema_get_investigation_context",
  "arguments": { "industry": "oil_gas", "business_question": "Why is production declining on this well?" }
}
```

### Suggest dimensions for an investigation

```json
{
  "name": "schema_suggest_dimensions",
  "arguments": { "industry": "oil_gas", "investigation_type": "well_comparison" }
}
```

## Related Documentation

- [Semantica MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Semantica%20MCP%20Server%20Deployment%20Guide.md) — deploy this server and load the data model.
- [Semantica Oil & Gas Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Semantica%20Oil%20%26%20Gas%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
