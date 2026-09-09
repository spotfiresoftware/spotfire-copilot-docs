<!--
  <copyright file="DATABRICKS_SPOTFIRE_AGENT_USER_GUIDE.md" company="Cloud Software Group, Inc.">
    Copyright (c) 2006 - 2026 Cloud Software Group, Inc.
  All rights reserved.
  This software is the confidential and proprietary information
  of Cloud Software Group, Inc. ("Confidential Information"). You shall not
  disclose such Confidential Information and may not use it in any way,
  absent an express written license agreement between you and
  Cloud Software Group, Inc. that authorizes such use.
  </copyright>
-->

# Databricks Spotfire Agent — User Guide

## Table of Contents

- [Introduction](#introduction)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What Data Does It Need?](#what-data-does-it-need)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Capability 1: Connection Discovery (Automatic)](#capability-1-connection-discovery-automatic)
  - [Capability 2: Browsing Catalogs, Schemas & Tables](#capability-2-browsing-catalogs-schemas--tables)
  - [Capability 3: Previewing a Table Before You Commit](#capability-3-previewing-a-table-before-you-commit)
  - [Capability 4: Bringing Data Into Spotfire (Landing)](#capability-4-bringing-data-into-spotfire-landing)
  - [Capability 5: Filtering at the Source or Locally](#capability-5-filtering-at-the-source-or-locally)
  - [Capability 6: Marking & Visualization](#capability-6-marking--visualization)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The **Databricks Spotfire Agent** is a specialist AI agent available within Spotfire Copilot that helps analysts and Spotfire developers **explore Databricks data and bring it into their analysis** — without leaving Spotfire, and without writing a single line of SQL themselves. Rather than switching to the Databricks workspace, hunting through Unity Catalog, and hand-building connection queries, the agent works directly through an **existing Spotfire data connection** to Databricks: it discovers what's reachable, previews tables on request, and lands the data you want as live, refreshable Spotfire tables.

The agent acts as a data-connection expert: it understands the Databricks catalog → schema → table hierarchy, authors connector-native SQL in the correct dialect, and knows how to push a query down to the source so the result comes back as a new Spotfire table you can immediately visualize, filter, and mark. It is a **connection-only** agent — it uses Spotfire's native data-connection tooling and does **not** require a Databricks MCP server or any external service.

---

## Getting Started

### Invoking the Agent

1. Open your Spotfire analysis. It must contain **at least one configured Databricks data connection** (see [What Data Does It Need?](#what-data-does-it-need) below).
2. Open Spotfire Copilot.
3. Press the **/** key to bring up the agent selector.
4. Choose **Databricks Spotfire Agent** from the list.

The agent greets you with a short overview of what it can do:

> Hi! I'm the **Databricks Spotfire Agent**. Working through your Spotfire data connection, I can:
> - **Show what's reachable** — the Databricks catalogs, schemas, and tables your connection can see.
> - **Preview a table before you commit** — pull a small sample so you can inspect its columns and values first.
> - **Bring a table into Spotfire** — land it as a new live, refreshable table, then filter, visualize, or mark it.

Just describe what you're looking for in plain language — the agent writes the SQL. For example:

- *"What tables can I bring in from Databricks?"*
- *"Bring master_production_data into Spotfire"*
- *"Pull sales for 2026 into Spotfire and chart it"*

**Tip:** You never need to author or paste SQL. Describe the table or the result you want in plain English and the agent composes the connector-native query for you.

### What Data Does It Need?

The agent works entirely through a **Spotfire data connection** that is already configured in your analysis. At minimum it needs:

- **One working Databricks (or compatible) data connection** in the `.dxp`. The agent reuses an existing connection-backed table as a **carrier** — the entry point it pushes queries through.

Optional but helpful:

- The connection's tables should be enumerable via the connector's metadata API so the agent can list catalogs, schemas, and tables. This works on most Databricks connections; when it doesn't, the agent degrades gracefully and lets you **name** the table you want directly.

You do **not** need to pre-model views, configure column mappings, or build custom queries in advance — the agent discovers the connection automatically and authors everything for you.

---

## How the Workflow Operates

Unlike a multi-stage wizard, this agent runs a single, flexible **conversational tool loop** — every request (discover, preview, land, filter, visualize, mark) is handled in one continuous conversation. You can move between capabilities freely and in any order. The sections below describe each capability the agent offers.

### Capability 1: Connection Discovery (Automatic)

**What happens:** The moment you invoke the agent, it inspects your Spotfire analysis **once** to find a usable Databricks connection and build a compact map of everything that connection can reach:

- Finds a connection-backed table to use as the **carrier**
- Enumerates the reachable tables as fully-qualified `catalog.schema.table` names
- Caches this map so it can answer catalog/schema/table questions instantly for the rest of the session — without re-querying on every turn

**What you see:** Nothing intrusive — discovery runs behind the scenes so your first real question is answered immediately.

**Why it matters:** This one-time discovery is a deliberate speed optimization. Because the reachable-table list is cached, follow-up questions like *"what schemas are in sf_demos?"* are answered by parsing the map rather than making slow round-trips to the source every time.

---

### Capability 2: Browsing Catalogs, Schemas & Tables

**What happens:** When you ask what's available, the agent reads the connection's reachable objects and answers at whatever level you ask — catalog, schema, or table — by parsing the fully-qualified names.

**What you see:** Direct answers such as:

- *"What catalogs are available?"* → the distinct top-level catalogs (e.g., `main`, `samples`, `sf_demos`)
- *"What schemas are in sf_demos?"* → the schemas within that catalog
- *"What tables are in sf_demos.ai_demo_01?"* → the tables under that schema

For large lists, the agent shows a representative sample and states the total count.

**Honest fallback:** If the connection's metadata service returns nothing (some connectors can't enumerate tables), the agent tells you plainly and invites you to **name** the table you want — it can still land a named table directly.

---

### Capability 3: Previewing a Table Before You Commit

**What happens:** Before you bring in a full table, you can ask the agent to **preview** it. The agent runs a read-only query against the live source and returns the rows or column metadata **inline in the chat** — nothing is added to your document.

**What you see:**

- *"Show me a sample of master_production_data"* → a small Markdown table of sample rows
- *"What columns does volve_production have?"* → the column names and data types

This lets you inspect a table's shape and values **before** deciding to land the full live table.

**Note:** A preview never creates a Spotfire table — it's purely informational. Only the landing step (next) adds data to your analysis.

---

### Capability 4: Bringing Data Into Spotfire (Landing)

**What happens:** This is the core action. When you ask to bring in a table, the agent:

1. Picks a **carrier** connection to push the query through
2. Authors a connector-native `SELECT` in the correct **Databricks/Spark SQL dialect**
3. Calls the landing operation to model the query as a new custom-query view and materialize it as a **new, live, external, refreshable Spotfire table**
4. **Automatically creates a Table plot** bound to the new table so you can see the data immediately

Landing is **additive and safe** — it only appends a new view; it never alters or removes the connection's existing tables. The agent does this directly without asking for permission, because bringing in a table is exactly what you asked for.

**What you see:**

> *"Modelled a custom query on [carrier] and loaded it as external table **master_production_data** (12,480 rows). I've added a Table visualization for it."*

The new table appears in your Spotfire document, connected live to Databricks and refreshable.

**Source-side filtering while landing:** You can narrow the data as it's brought in — e.g., *"Bring in production where FIELD = IOLA"* — and the agent pushes that filter **down to Databricks** so only matching rows are landed.

---

### Capability 5: Filtering at the Source or Locally

**What happens:** After a table is landed, you can refine it further. The agent chooses the most efficient path:

- **Source push-down** — if the column is an adjustable on-demand parameter, the agent re-parameterizes the query and refreshes, so the filter is applied **at Databricks**
- **Local Spotfire filter** — if the column isn't source-parameterizable, the agent applies a filter **locally in Spotfire** and tells you plainly that it did so

**What you see:**

- *"Filter this to 2026 only"*
- *"Show only rows where operator = Continental"*
- *"Narrow it to wells deeper than 18,000 ft"*

The agent always tells you **which** kind of filter it applied, so you know whether the source or just the local view was narrowed.

---

### Capability 6: Marking & Visualization

**What happens:** Once data is in Spotfire, the agent can mark rows and build additional visualizations on the landed table.

**What you see:**

- *"Mark the rows where cumulative oil > 100,000"* → highlights matching rows in your visualizations
- *"Create a scatter plot of depth vs. cumulative oil"* → builds a new plot bound to the landed table
- *"Chart it by field"* → creates a bar chart grouped by your chosen column

Every visualization is bound to the exact table that was landed, so what you see always reflects the real data.

---

## Typical End-to-End Session

Here's what a complete session looks like in practice:

```
You:    /Databricks Spotfire Agent

Agent:  [Discovers the connection behind the scenes]
        "Hi! I'm the Databricks Spotfire Agent. I can show what's reachable,
         preview a table, or bring a table into Spotfire as a live table."

You:    "What tables can I bring in?"

Agent:  "Your Databricks connection can reach 312 tables across catalogs
         main, samples, and sf_demos. In sf_demos.ai_demo_01 you'll find
         master_production_data, volve_production, and 20 others..."

You:    "Show me a sample of master_production_data"

Agent:  [Runs a read-only preview against the source]
        "Here are the first 25 rows (of ~12,000). Columns: FIELD, WELL,
         DATE, OIL_BBL, WATER_BBL, GAS_MCF..."
        [Inline Markdown table]

You:    "Bring it into Spotfire and chart oil by field"

Agent:  [Lands the table via connector push-down]
        "Loaded external table master_production_data (12,480 rows) and
         added a Table plot."
        [Creates a bar chart of OIL_BBL by FIELD]
        "Here's cumulative oil grouped by field."

You:    "Filter it to FIELD = IOLA"

Agent:  [Pushes the filter down to Databricks and refreshes]
        "Filtered master_production_data to FIELD = IOLA at the source
         (1,240 rows)."

You:    "done"

Agent:  "Great — your live Databricks table is in Spotfire and ready to
         explore further."
```

**Total time: ~1 minute** to go from "what's in Databricks?" to a live, charted, filtered Spotfire table.

---

## Key Benefits

| Benefit | Description |
| --- | --- |
| **No SQL required** | The agent authors all connector-native SQL in the correct Databricks/Spark dialect — you just describe what you want |
| **No MCP server needed** | Works entirely through your existing Spotfire data connection — no external Databricks service to configure |
| **Live, refreshable tables** | Landed tables stay connected to Databricks — they're external and refreshable, not static snapshots |
| **Preview before you commit** | Inspect rows and columns inline in chat without adding anything to your document |
| **Source-side push-down** | Filters can be pushed down to Databricks so you only land the rows you need |
| **Grounded, honest answers** | The agent only reports what a tool actually returned — it never fabricates table names, row counts, or successes |
| **Automatic visualization** | Every landed table gets a Table plot immediately, and you can request more charts on top |

---

## Tips for Best Results

- **Ask what's reachable first** — Start with *"what can I bring in?"* to see the catalogs, schemas, and tables your connection exposes.
- **Preview before landing** — Use *"show me a sample of X"* to confirm a table is the right one before you bring in the full live table.
- **Name the table if discovery is empty** — If the agent says it can't enumerate the connection, just tell it the exact table name and it can still land it directly.
- **Filter at the source when you can** — Ask for the filter *while* bringing the table in (e.g., *"bring in sales where year = 2026"*) so only the rows you want are landed.
- **Ask follow-up questions** — After landing, ask things like *"how many rows?"*, *"chart oil by field"*, or *"filter to just 2026"* — the agent remembers what it already brought in.
- **Use plain, exact values** — When filtering on a text column, give the value exactly as it appears in the data (matching case and spacing) so the source query matches rows correctly.

---

## Glossary

| Term | Definition |
| --- | --- |
| **Data Connection** | A Spotfire-configured link to an external source (here, Databricks). The agent works exclusively through this connection. |
| **Carrier** | An existing connection-backed table the agent reuses as the entry point to push queries through to the source. |
| **Catalog / Schema / Table** | Databricks' three-level hierarchy for organizing data. The agent derives all three by parsing fully-qualified `catalog.schema.table` names. |
| **Landing** | Bringing a query result into Spotfire as a new, live, external, refreshable data table (via connector push-down). |
| **Live / Refreshable Table** | A landed table that stays connected to Databricks and can be refreshed — as opposed to a static, one-time snapshot. |
| **Push-down** | Sending a query or filter *down* to Databricks so the work happens at the source and only the needed rows are returned. |
| **Preview** | A read-only query whose rows or column metadata are shown inline in chat, adding nothing to your document. |
| **On-demand Parameter** | A source-side query parameter on a landed table that the agent can re-set to push a new filter down to Databricks. |
| **Local Filter** | A filter applied within Spotfire (not at the source) — used when a column isn't source-parameterizable. |
| **MCP Server** | An external "Model Context Protocol" service some agents use. This agent is **connection-only** and needs none. |