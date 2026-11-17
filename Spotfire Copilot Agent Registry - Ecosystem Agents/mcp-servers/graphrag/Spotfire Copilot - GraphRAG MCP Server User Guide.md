# GraphRAG MCP Server — User Guide

spotfire-knowledge × retrieval × knowledge-graph

The `graphrag` MCP server exposes read-only tools for Retrieval-Augmented Generation over the
unified Spotfire knowledge corpus. It combines **vector retrieval** (product docs, release
notes, and Dr. Spotfire video transcripts in Milvus/Zilliz) with a **Neo4j knowledge graph**
(feature lifecycle, cross-document relationships, and structured Daily Drilling Report
analytics), so that agents and other MCP clients can answer documentation and drilling
questions without writing queries.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [Documentation Retrieval](#documentation-retrieval)
  - [Knowledge Graph](#knowledge-graph)
  - [Feature Lifecycle](#feature-lifecycle)
  - [Drilling Reports (DDR)](#drilling-reports-ddr)
  - [Advanced / Fallback](#advanced--fallback)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [GraphRAG Agent](../../agents/Spotfire%20Copilot%20-%20GraphRAG%20Agent%20User%20Guide.md).
It exposes **44 tools** across four families: documentation retrieval, knowledge-graph
exploration, feature-lifecycle/version queries, and Daily Drilling Report (DDR) analytics.

Output conventions:

- All tools return JSON text.
- Tool failures return a structured payload with an `error` field describing the cause.
- Passage results use a normalized schema (`chunk_id`, `document_id`, `title`, `text`,
  `source_uri`, `page_start`, `page_end`, `section_path`, `document_type`, `product_version`,
  `score`, `chunk_ordinal`, `version_id`, `is_active`, `timestamp_seconds`; optional fields
  are omitted when absent) and carry a `citation`: paged documents get a page range; video
  transcripts get a **deep-link** at the chunk's start time (`…&t=NNNs`, labelled `@ hh:mm:ss`).
- The **Knowledge Graph**, **Feature Lifecycle**, and **Drilling Reports** families require a
  Neo4j connection (`NEO4J_URI`). When the graph is not configured, those tools return
  `{ "error": "not_configured" }`; documentation retrieval still works from the vector store.

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the
[GraphRAG MCP Server Deployment Guide](Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20Deployment%20Guide.md).
The server reads a Milvus/Zilliz collection and a Neo4j graph that must be **populated first** —
see the [GraphRAG Corpus Loading Guide](Spotfire%20Copilot%20-%20GraphRAG%20Corpus%20Loading%20Guide.md).
The server must be deployed and reachable before the GraphRAG Agent can be invoked.

## Connecting

| Setting          | Value                                                                        |
| ---------------- | ---------------------------------------------------------------------------- |
| Transport        | `streamable-http` (recommended)                                              |
| URL              | Set via `GRAPHRAG_MCP_SERVER_URL` (e.g. `https://mcp-graphrag.example.com/mcp`) |
| Auth             | Configured on the server at deploy time (static bearer token or OAuth/JWKS)  |

## Tool Reference

### Documentation Retrieval

Vector search over the loaded corpus (product docs, release notes, transcripts). Uses hybrid
dense + BM25 retrieval when the collection has a sparse field, else dense.

#### `search_documentation`
- **Purpose:** Natural-language search over all configured documentation.
- **Inputs:** `query` (str, required), `limit` (int, default `8`), `document_type` (str, optional), `product_version` (str, optional), `tags` (object, optional), `document_id` (str, optional), `active_only` (bool, default `false`), `retrieval_mode` (str, `auto` | `dense` | `bm25` | `hybrid`, default `auto`).
- **Output:** Ranked passages with provenance and citations.

#### `get_document_details`
- **Purpose:** Metadata for one document.
- **Inputs:** `document_id` (str, required).
- **Output:** `{ document_id, title, source_uri, document_type, product_version, chunk_count }`.

#### `get_document_passages`
- **Purpose:** Passages from one document; ranked by `query` if given, else in chunk order.
- **Inputs:** `document_id` (str, required), `query` (str, optional), `page_start` (int, optional), `page_end` (int, optional), `section_path` (str, optional), `limit` (int, default `8`), `offset` (int, default `0`).

#### `find_related_documents`
- **Purpose:** Content-similarity recommendations, excluding the source document.
- **Inputs:** `document_id` (str, required), `limit` (int, default `5`).

#### `list_filter_values`
- **Purpose:** Distinct `document_type` / `product_version` values for discovering valid filters.
- **Inputs:** _none_.

#### `get_corpus_overview`
- **Purpose:** Collections, chunk/document counts, available types/versions, active retrieval modes.
- **Inputs:** _none_.

#### `get_adjacent_passages`
- **Purpose:** Chunks surrounding a hit, for context-window expansion.
- **Inputs:** `chunk_id` (str, optional) **or** `document_id` (str) + `chunk_ordinal` (int); `before` (int, default `2`), `after` (int, default `2`).

### Knowledge Graph

Combined semantic + graph retrieval and graph exploration. Requires `NEO4J_URI`.

#### `search_knowledge`
- **Purpose:** One call — hybrid retrieval **plus** graph expansion of the retrieved documents.
- **Inputs:** `query` (str, required), `limit` (int, default `8`), `document_type` (str, optional), `product_version` (str, optional), `tags` (object, optional), `graph_limit` (int, default `50`).
- **Output:** `{ passages (with citations), graph (expansion edges) }`. Falls back to passages only when the graph is disabled.

#### `get_graph_overview`
- **Purpose:** Node labels and relationship types present in the graph.
- **Inputs:** _none_.

#### `search_graph_entities`
- **Purpose:** Find graph entities by a text term (matches name / title / ticket / wellbore / rig / report number / id).
- **Inputs:** `term` (str, required), `labels` (list[str], optional), `include_chunks` (bool, default `false`), `limit` (int, default `20`).

#### `get_entity_relationships`
- **Purpose:** Explore the relationships around one entity identified by a property match.
- **Inputs:** `key` (str, required), `value` (str, required), `labels` (list[str], optional), `limit` (int, default `50`).

#### `get_graph_context`
- **Purpose:** Graph neighbourhood around a document or chunk (expand a semantic hit).
- **Inputs:** `anchor` (str — a `document_id` or `chunk_id`, required), `depth` (int, 1–3, default `1`), `limit` (int, default `50`).

### Feature Lifecycle

Version-graph queries over release-notes documents. Requires `NEO4J_URI`.

#### `feature_lifecycle`
- **Purpose:** Trace a feature's lifecycle across versions (introduced / deprecated / removed / changed) with provenance.
- **Inputs:** `ticket` (str, e.g. `"TS-84423"`, optional) **or** `keyword` (str, e.g. `"Apache Drill"`, optional); `limit` (int, default `25`).

#### `list_changes_between_versions`
- **Purpose:** Complete, structured set of feature changes across versions.
- **Inputs:** `from_version` (str, optional), `to_version` (str, optional, inclusive), `kinds` (list[str] — any of `introduced`, `deprecated`, `removed`, `changed`, optional), `limit` (int, default `1000`).

### Drilling Reports (DDR)

Schema-tolerant structured analytics over Daily Drilling Reports across **oil** (Volve; depth
on the report, ISO dates) and **thermal** (FORGE; depth in survey/casing tables, `MM/DD/YYYY`
dates) wells. Computed from the graph (never model knowledge). Requires `NEO4J_URI`.

**Discovery and counts** — `ddr_list_wellbores`, `ddr_list_rig_names`, `ddr_list_reports`,
`ddr_list_reports_by_wellbore` (`wellbore`), `ddr_list_reports_by_rig` (`rig`),
`ddr_list_reports_by_date_range` (`start`/`end` as `YYYY-MM-DD`), `ddr_num_reports`,
`ddr_num_reports_by_wellbore` (`wellbore`), `ddr_num_reports_by_rig` (`rig`).

**Depth** — `ddr_well_depth_summary` (`wellbore`; returns `max_depth_m` for oil and thermal,
`total_drilled_m` for oil, and a `max_depth_source` label), `ddr_total_depth_grouped`
(per-wellbore rollup for all wells).

**Field analytics** — `ddr_list_available_fields` (optional `well_type`), `ddr_field_stats`
(`field_key`, optional `wellbore`), `ddr_field_stats_by_wellbore` (`field_key`),
`ddr_field_stats_by_rig` (`field_key`), `ddr_field_values` (`field_key`, optional `wellbore`).

**Per-report deep dives** (all take `report_id`) — `ddr_get_report`, `ddr_get_report_fields`,
`ddr_get_report_operations`, `ddr_operations_summary`, `ddr_summary_activities`,
`ddr_planned_activities`, `ddr_get_survey_stations`, `ddr_get_casing_strings`,
`ddr_get_drilling_fluid_rows`, `ddr_drilling_fluid_stats`, `ddr_get_pore_pressure_rows`,
`ddr_pore_pressure_stats`, `ddr_report_full_context`.

> The narrative tools `ddr_summary_activities` and `ddr_planned_activities` return rows only
> for oil reports; thermal reports have no narrative-activity section.

### Advanced / Fallback

#### `ddr_cypher`
- **Purpose:** Run a custom **read-only** Cypher query against the Neo4j graph. Use only when no specialized tool fits.
- **Inputs:** `query` (str, required), `limit` (int, default `200`).
- **Caution:** Write/DDL/procedure clauses (`CREATE`/`MERGE`/`DELETE`/`SET`/`REMOVE`/`DROP`/`FOREACH`/`LOAD CSV`, `db.`/`apoc.`/`dbms.`) are rejected. Discover schema first via `get_graph_overview` and `ddr_list_available_fields`.

## Example Payloads

### Search the documentation

```json
{
  "name": "search_documentation",
  "arguments": { "query": "What does the geospatial library do?", "limit": 8 }
}
```

### Combined semantic + graph answer

```json
{
  "name": "search_knowledge",
  "arguments": { "query": "Apache Drill connector", "limit": 8, "graph_limit": 50 }
}
```

### Changes between two Spotfire versions

```json
{
  "name": "list_changes_between_versions",
  "arguments": { "from_version": "14.5.0", "to_version": "15.0.0", "kinds": ["introduced", "deprecated", "removed"] }
}
```

### Depth for a wellbore (oil or thermal)

```json
{
  "name": "ddr_well_depth_summary",
  "arguments": { "wellbore": "FORGE 16A [78]-32" }
}
```

### Full context for one report

```json
{
  "name": "ddr_report_full_context",
  "arguments": { "report_id": "<report id>" }
}
```

## Related Documentation

- [GraphRAG MCP Server Deployment Guide](Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [GraphRAG Corpus Loading Guide](Spotfire%20Copilot%20-%20GraphRAG%20Corpus%20Loading%20Guide.md) — load the vector store and knowledge graph the server reads.
- [GraphRAG Agent User Guide](../../agents/Spotfire%20Copilot%20-%20GraphRAG%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
