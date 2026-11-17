# Semantica Oil & Gas Agent — User Guide

oil-and-gas × data-model × knowledge-graph

The Semantica Oil & Gas Agent is a specialist AI agent that explains and navigates the Oil &
Gas **industry data model** — wells, production, reservoirs, drilling, facilities, equipment,
HSE, and land. It answers business questions by mapping them to the model's concepts, tables,
columns, business-glossary terms, and foreign-key relationships, so analysts can orient, find
the right data, and plan an investigation without reading raw schemas.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
  - [What the Agent Does Not Do](#what-the-agent-does-not-do)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Investigate a Business Question](#stage-1-investigate-a-business-question)
  - [Stage 2: Suggest Investigation Dimensions](#stage-2-suggest-investigation-dimensions)
  - [Stage 3: Work From Your Spotfire Analysis](#stage-3-work-from-your-spotfire-analysis)
  - [Stage 4: Find Tables, Columns, and Terms](#stage-4-find-tables-columns-and-terms)
  - [Stage 5: Describe a Table](#stage-5-describe-a-table)
  - [Stage 6: Trace Relationships](#stage-6-trace-relationships)
  - [Stage 7: Orient and Graph Insights](#stage-7-orient-and-graph-insights)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Semantica Oil & Gas Agent is a conversational data-model assistant available inside the
Spotfire Copilot Panel. It is connected to the Oil & Gas industry data model — loaded as a
knowledge graph — through a dedicated MCP server (Semantica), and answers questions in natural
language about **what data exists, what it means, and how it connects**.

The agent is designed for business users. You can ask an operational question ("why is
production declining on this well — what should I look at?") and the agent maps it to the
model: the relevant concepts, how they relate via foreign keys, and which dimensions are worth
investigating next. It is **read-only** and strictly grounded — every answer about a table,
column, or relationship comes from the loaded model, never from general knowledge, and it never
invents schema.

The agent is scoped exclusively to **Oil & Gas**. It does not answer about other industry
models, and it does not read your live production data — it works from the data model so you can
pair its guidance with the actual data in Spotfire.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot
Panel, the following must already be deployed and reachable:

- **LangGraph DeepAgents server** — the agent ships as part of the LangGraph DeepAgents
  server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md)
  or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **Semantica MCP server** — the agent's tools call this MCP server at runtime, with the
  **Oil & Gas data model loaded** into its knowledge graph. See the
  [Semantica MCP Server User Guide](../mcp-servers/semantica/Spotfire%20Copilot%20-%20Semantica%20MCP%20Server%20User%20Guide.md)
  and [deployment guide](../mcp-servers/semantica/Spotfire%20Copilot%20-%20Semantica%20MCP%20Server%20Deployment%20Guide.md).

If the agent server or MCP server is missing or unreachable, the agent will not appear in the
Copilot Panel, or it will fail with a tool-related error. If the Oil & Gas model is not loaded
into the graph, the schema tools return nothing and the agent reports it.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Semantica Oil & Gas Agent** (or the equivalent label configured in your
   environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live Oil & Gas data model.

### What You Provide

The agent only needs **natural-language questions**. It is most useful when you provide:

| Signal                 | Examples                                                              |
| ---------------------- | --------------------------------------------------------------------- |
| A business question    | "Production is declining on a well — what should I investigate?"       |
| An investigation type  | production decline, well comparison, maintenance, well traceability    |
| A topic or term        | "downtime", "decline curve", "H2S", "lease obligations"                |
| A table or column      | `daily_production`, `downtime_event`, `equipment`, `lease`             |
| Your Spotfire context  | The tables/columns/metric currently in your analysis (to map them)     |

### What Data Is Available

The agent reads the **Oil & Gas industry data model** (the Databricks lakehouse `oil_gas`
model), loaded as a knowledge graph. It spans **19 business domains**, including:

- **Exploration** — basins, blocks, prospects, plays, discoveries, fields, formations.
- **Drilling** — drilling wells, daily drilling reports, bit runs, casing, mud programs, AFEs.
- **Reservoir** — decline curves, pressure history, material balance, production forecasts.
- **Production** — daily production, downtime events, artificial lift / ESP, flaring, facilities.
- **Assets** — equipment, facilities, inspections, failures, corrosion, integrity programs.
- **HSE** — incidents, emissions (GHG, H2S), environmental monitoring.
- **Land**, **Workforce**, **Logistics**, **Finance/Revenue**, **Commercial**, and more.

For each table the model carries a domain, description, primary key, columns (name, type,
business-glossary term), and typed foreign-key relationships to other tables.

### What the Agent Does Not Do

- It does **not** read live production numbers or Spotfire row data. It describes the **model**
  (structure, meaning, relationships) and suggests where to look — pair that with your data.
- It does **not** prove causation. The model shows how concepts *can* relate; it does not prove
  that one explains an observed change. The agent labels findings accordingly.
- It covers **only** the Oil & Gas model. For other industries or for document-based questions,
  use the matching agent.

## What the Agent Can Do

| Capability                      | What It Does                                                                                         | Example Request                                                     |
| ------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Investigate a business question | Map a question to matched model concepts, their relationships, adjacent domains, and follow-ups      | "What should I investigate for a decline in well production?"       |
| Suggest investigation dimensions| Recommend model-supported dimensions for a named investigation type, with support status             | "Which dimensions should I compare across these wells?"             |
| Map Spotfire context            | Map your analysis's tables/columns/metric to the model (exact / normalized / candidate)              | "Map the wells and metrics in my current analysis to the model"     |
| Search tables, columns & terms  | Find tables/columns/domains by name, glossary term, or description                                   | "Which table holds daily production volumes?"                       |
| Describe a table                | Show a table's domain, description, primary key, columns, and foreign-key relationships               | "Describe the `downtime_event` table"                               |
| Trace relationships             | Explain how tables connect: related tables, shortest join paths, lineage across domains               | "How does a well connect to its reservoir and production tables?"   |
| Orient & graph insights         | List domains/tables; summarize the loaded model's structure                                           | "What domains does the oil & gas model cover?"                      |

## How the Workflow Operates

The agent routes each question to the matching skill and answers by calling schema tools against
the live Oil & Gas model. Every schema tool call is scoped to `industry = oil_gas`.

### Stage 1: Investigate a Business Question

**When to use:** You have an operational question and want the model-grounded map of what to
look at.

**Example prompts:**
- "Production is declining on a well — what should I investigate?"
- "How do reservoir pressure and well production relate?"
- "What's connected to drilling cost / AFE spend?"

**What you get back:** A structured, schema-grounded context — matched concepts and tables,
modeled relationships among them, adjacent domains, any unresolved Spotfire-name mappings, and
suggested follow-up searches. Findings are labeled as **model findings**, **Spotfire mappings**,
**suggestions**, or **limitations**, and uncertain mappings are flagged as candidates.

### Stage 2: Suggest Investigation Dimensions

**When to use:** You know the kind of investigation and want the model-supported dimensions to
explore next.

**Supported investigation types:** `production_decline`, `well_comparison`,
`maintenance_investigation`, `well_traceability`.

**Example prompts:**
- "Which dimensions should I compare across these wells?"
- "What should I look at for an equipment-failure / maintenance investigation?"

**What you get back:** A list of suggested dimensions, each with a status
(`supported` / `candidate` / `not_found`), the backing table/attributes, and the modeled path
from a starting concept. The agent never claims a dimension the loaded model does not support.

### Stage 3: Work From Your Spotfire Analysis

**When to use:** You want to connect what's on screen to the model.

**Example prompts:**
- "Map the wells and metrics in my current analysis to the model."
- "My dashboard shows production by field — what related dimensions could I add?"

**What you get back:** A deterministic mapping of your tables/columns/metric to model concepts,
marked **exact**, **normalized**, or **candidate**, with any unresolved fields listed — never
silently confirmed.

### Stage 4: Find Tables, Columns, and Terms

**When to use:** You want to locate where something lives in the model.

**Example prompts:**
- "Which table holds daily production volumes?"
- "Where is well decline-curve data?"
- "Search the model for H2S or GHG emissions."

**What you get back:** Ranked matches (tables, columns, or domains) by name, business-glossary
term, or description, quoting the exact model names.

### Stage 5: Describe a Table

**When to use:** You want the full detail of one table.

**Example prompts:**
- "Describe the `daily_production` table."
- "What columns does `downtime_event` have?"
- "Show the primary key and glossary terms for `decline_curve`."

**What you get back:** The table's domain, description, primary key, a compact column list
(name · type · glossary), and its outgoing/incoming foreign-key relationships.

### Stage 6: Trace Relationships

**When to use:** You want to understand how tables connect (joins / lineage).

**Example prompts:**
- "How does a well connect to its reservoir and production tables?"
- "What references the `facility` table?"
- "How is a `lease` connected to a well?"

**What you get back:** Related tables with join columns and direction, or the shortest modeled
foreign-key path(s) between two tables — and a clear no-path result when none exists.

### Stage 7: Orient and Graph Insights

**When to use:** You are new to the model and want the lay of the land.

**Example prompts:**
- "What domains does the oil & gas model cover?"
- "List the tables in the drilling domain."
- "Give me a summary of the loaded model."

**What you get back:** The business domains with descriptions and table counts, the tables in a
domain, or a structural overview of the loaded model.

## Typical End-to-End Session

```
You:    Production is declining on a well — what should I investigate?

Agent:  [Returns matched model concepts (daily_production, downtime_event,
         decline_curve, artificial_lift), the modeled relationships among
         them, adjacent domains (reservoir, asset), and suggested next
         searches — each labeled as a model finding or suggestion.]

You:    Which dimensions should I compare across these wells?

Agent:  [Returns supported dimensions for well_comparison, each with a
         status, backing table/attributes, and the modeled path.]

You:    Describe the downtime_event table.

Agent:  Domain: production
        Description: ...
        Primary key: ...
        Columns: ... (name · type · glossary)
        Relationships: downtime_event → facility, downtime_event → equipment ...

You:    How is a lease connected to a well?

Agent:  [Returns the shortest modeled foreign-key path(s) from land.lease
         to the well table(s), or a clear no-path result.]

You:    Thanks.
```

## Key Benefits

| Benefit                           | Description                                                                                                             |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Business-question first           | Ask in plain language; the agent maps your question to the model's concepts, relationships, and dimensions.             |
| Strictly grounded                 | Every table/column/relationship comes from the loaded model — never invented. Uncertain mappings are flagged.           |
| Spotfire-aware                    | Maps your dashboard's tables, columns, and metric to the model (exact / normalized / candidate).                        |
| Join & lineage ready              | Explains how tables connect via foreign keys, including shortest join paths across domains.                             |
| Honest about scope                | Describes the model, not live data, and never claims causation from connectivity alone.                                 |
| Oil & Gas focused                 | Scoped to the `oil_gas` model's 19 domains — no cross-industry drift.                                                    |

## Tips for Best Results

- **Lead with the business question.** The investigation and dimension tools are built for
  operational questions — start there, then drill into specific tables.
- **Mention your Spotfire context.** Naming the tables/columns/metric on screen lets the agent
  map them to the model.
- **Use exact model names when you have them.** Quoting a table like `downtime_event` gives the
  most precise description; otherwise search first.
- **Name the investigation type** (production decline, well comparison, maintenance, well
  traceability) to get the best dimension suggestions.
- **Treat suggestions as a map, not a verdict.** The model shows what *can* relate — confirm
  with your actual data in Spotfire.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                   | Definition                                                                                                           |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Industry data model    | A loaded data model for an industry (here, the Databricks lakehouse `oil_gas` model).                               |
| Domain                 | A business area within the model (e.g. production, drilling, reservoir, HSE).                                        |
| Table                  | An entity in a domain, with a primary key, description, and columns (e.g. `daily_production`).                       |
| Column / Attribute     | A field on a table, with a SQL type, an optional business-glossary term, and a description.                          |
| Business-glossary term | The standardized business meaning attached to a column (e.g. OEE, downtime).                                         |
| Foreign key            | A typed relationship from one table to another (`REFERENCES`).                                                       |
| Join path              | The ordered sequence of tables/foreign keys that connect two tables.                                                |
| Investigation type     | A named analysis pattern the agent can suggest dimensions for (e.g. `production_decline`, `well_comparison`).        |
| Spotfire mapping        | A dashboard field mapped to a model concept, marked `exact`, `normalized`, or `candidate`.                          |
| MCP Server             | The Model Context Protocol server (Semantica) that exposes the data-model schema tools the agent calls at runtime.   |
