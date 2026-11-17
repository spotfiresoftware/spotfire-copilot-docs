# GraphRAG Corpus Loading Guide

How to load the Spotfire knowledge corpus into the vector store and knowledge graph that the
[GraphRAG MCP server](Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20User%20Guide.md) reads.

## Table of Contents

- [1. Overview](#1-overview)
- [2. What Gets Loaded](#2-what-gets-loaded)
- [3. Prerequisites](#3-prerequisites)
- [4. Data Layout](#4-data-layout)
- [5. Loading the Corpus](#5-loading-the-corpus)
  - [5.1 Fetch Video Transcripts (optional)](#51-fetch-video-transcripts-optional)
  - [5.2 Stage the Data](#52-stage-the-data)
  - [5.3 Dry-Run (validate parsing)](#53-dry-run-validate-parsing)
  - [5.4 Ingest (write to the stores)](#54-ingest-write-to-the-stores)
- [6. Verifying What Landed](#6-verifying-what-landed)
- [7. Incremental Updates](#7-incremental-updates)
- [8. Troubleshooting](#8-troubleshooting)
- [9. Related Documentation](#9-related-documentation)

---

## 1. Overview

The GraphRAG MCP server is **stateless**: it answers questions by reading two backing stores
that you populate ahead of time with a data loader (the `rag-loader` service):

- a **vector store** (Milvus/Zilliz collection, default `copilot_docs`) holding embedded text
  chunks for semantic + keyword retrieval, and
- a **Neo4j knowledge graph** holding document/feature/entity relationships, the release-notes
  feature-lifecycle graph, and the structured Daily Drilling Report (DDR) records.

One loader writes **both** stores from the same source content, so retrieval and graph answers
stay consistent. The embedding model used to load the vector store **must match** the model the
MCP server is configured with (see the
[Deployment Guide](Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20Deployment%20Guide.md)).

## 2. What Gets Loaded

The loader handles several document types into the single shared collection and graph:

| Document type     | Source                                             | Notes                                                        |
| ----------------- | -------------------------------------------------- | ------------------------------------------------------------ |
| `prose_doc`       | Product documentation / manuals (PDF, etc.)        | Page-aware chunking; citations carry page ranges.            |
| `release_notes`   | Per-version release notes                          | Also builds the feature-lifecycle graph (introduced/changed/deprecated/removed). |
| `transcript`      | Dr. Spotfire video transcripts                     | Carries per-chunk `timestamp_seconds` for deep-link citations. |
| `drilling_report` | Daily Drilling Reports (oil + thermal)             | Structured graph records (wells, rigs, operations, surveys, casing, fluids). |

Each chunk is tagged with `namespace`, `document_type`, `source_format`, and `product_version`
so the MCP server can filter in-index.

## 3. Prerequisites

- A reachable **Neo4j** instance (the graph the MCP server also reads).
- A reachable **Milvus/Zilliz** instance and a collection name (the loader creates the
  collection with the correct schema on first write if it does not exist).
- An **embedding API key** for the embedding provider/model you will use (e.g. OpenAI
  `text-embedding-3-small`, dimension `1536`). Record the exact model — the MCP server must be
  configured with the same one.
- The **rag-loader** tooling: either the deployed loader API/service, or the local
  `rag-loader` CLI (Python 3.12, installed with the `youtube` extra if you will fetch
  transcripts).

## 4. Data Layout

Source files are organized by `namespace` and `doc_type`:

```
data/
  <namespace>/
    prose_doc/      inbox/*.pdf
    release_notes/  inbox/*.pdf
    transcript/     cache/*.md   cache/sources.json   sources.txt
    drilling_report/ inbox/*.(pdf|json)
```

Most document types read from an `inbox/`. **Transcripts** live in `cache/` — the `.md` files
produced by the fetch step — alongside `cache/sources.json`, which maps each transcript file to
its canonical video URL, title, and tags.

## 5. Loading the Corpus

### 5.1 Fetch Video Transcripts (optional)

Transcripts are fetched **locally** (the deployed loader never calls the video provider). The
full URL list lives in `transcript/sources.txt`; fetched transcripts land in `cache/` as
`<title>-<id>.md`:

```bash
rag-loader fetch-transcripts --namespace <namespace> --data-root ./data --sleep 3
```

The fetcher is **resumable** (skips videos already in `cache/`) and stamps each transcript
paragraph with a `[hh:mm:ss]` marker. The transcript adapter turns that marker into the chunk's
`timestamp_seconds` field, which the MCP server uses for deep-linked video citations. If the
provider rate-limits the run, wait and re-run — nothing is lost or duplicated.

### 5.2 Stage the Data

Place source files under `data/<namespace>/<doc_type>/` as shown above. When loading against a
deployed loader service, upload the slice to the service's storage (for example, stream the
`<namespace>/<doc_type>` folder into the loader pod's data volume). Re-uploading identical files
is safe and idempotent.

### 5.3 Dry-Run (validate parsing)

A dry-run walks the data and reports what **would** be written to Neo4j and Milvus, without
writing anything:

```bash
# CLI
rag-loader dry-run --namespace <namespace> --doc-type transcript --data-root ./data

# or via the loader API
curl -s -X POST localhost:8080/v1/ingest \
  -H 'content-type: application/json' \
  -d '{"namespace":"<namespace>","doc_type":"transcript","execute":false}'
```

Start with `transcript` (fast); `prose_doc` / `release_notes` use document extraction and large
PDFs take longer.

### 5.4 Ingest (write to the stores)

Run one document type at a time. Ingest **writes to Neo4j and the Milvus collection** and is
**idempotent** — already-loaded, unchanged documents are skipped:

```bash
curl -s -X POST localhost:8080/v1/ingest \
  -H 'content-type: application/json' \
  -d '{"namespace":"<namespace>","doc_type":"transcript","execute":true}'
```

Repeat for `prose_doc`, `release_notes`, and `drilling_report`. The response reports
`parsed` (new), `skipped` (already loaded), and `failed` counts.

## 6. Verifying What Landed

Check counts in both stores after loading. In Milvus, count chunks per document type:

```python
from pymilvus import MilvusClient
c = MilvusClient(uri="<MILVUS_URI>", token="<MILVUS_TOKEN>")
for dt in ("transcript", "prose_doc", "release_notes", "drilling_report"):
    n = c.query("copilot_docs", filter=f'document_type == "{dt}"',
                output_fields=["count(*)"])[0]
    print(dt, n)
```

In Neo4j, count `Chunk` nodes (the property is `document_type`, not `doc_type`) and the DDR
`Summary report` nodes. The MCP server's `get_corpus_overview` tool also reports collection and
document counts once the server is running.

## 7. Incremental Updates

The loader is resumable and idempotent, so adding content is a matter of re-running the loop
for the new files:

1. Fetch or stage the new source files (e.g. more transcripts).
2. Upload the slice to the loader storage (identical files overwrite harmlessly; already-loaded
   documents stay as-is).
3. Run `ingest` with `execute: true` for that `doc_type`. Only the new or changed documents are
   parsed; the rest are skipped.

No full reload is required, and the GraphRAG MCP server picks up new content automatically
because it reads the same live stores.

## 8. Troubleshooting

1. **Ingest reports `failed` for every document:**
   - Usually an invalid embedding API key or an unreachable store. Validate the embedding key
     and the Neo4j / Milvus connectivity, then re-run (idempotent).
2. **Large PDF is killed during ingest (out of memory):**
   - Very large documents are processed in page windows; ensure the loader has adequate memory,
     and load `prose_doc` / `release_notes` one document type at a time.
3. **Video citations later show no timestamp:**
   - Confirm transcripts were fetched with timestamps (the default) and that the collection has
     an explicit `timestamp_seconds` field. Re-fetch and re-ingest the affected transcripts if
     needed.
4. **Retrieval quality is poor / empty after loading:**
   - Confirm the MCP server is configured with the **same** embedding provider, model, and
     dimension used here. A mismatch makes stored and query vectors incomparable.

## 9. Related Documentation

- [GraphRAG MCP Server User Guide](Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20User%20Guide.md) — the tools that read these stores.
- [GraphRAG MCP Server Deployment Guide](Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20Deployment%20Guide.md) — point the server at the loaded stores (embedding model must match).
- [GraphRAG Agent User Guide](../../agents/Spotfire%20Copilot%20-%20GraphRAG%20Agent%20User%20Guide.md) — the agent backed by this corpus.
