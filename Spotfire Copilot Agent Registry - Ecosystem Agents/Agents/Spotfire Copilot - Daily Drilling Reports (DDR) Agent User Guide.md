# Daily Drilling Reports (DDR) Agent — User Guide

energy × daily-drilling-reports × neo4j

The DDR Agent is a specialist AI agent that answers questions about Daily Drilling Reports stored in a Neo4j knowledge graph, helping drilling engineers, operations supervisors, and asset teams explore reports, monitor depth and rig performance, and dive into individual reports without writing queries.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Orientation](#stage-1-orientation)
  - [Stage 2: Report Discovery](#stage-2-report-discovery)
  - [Stage 3: Counts and Depth KPIs](#stage-3-counts-and-depth-kpis)
  - [Stage 4: Field Analytics](#stage-4-field-analytics)
  - [Stage 5: Report Deep Dives](#stage-5-report-deep-dives)
  - [Stage 6: Advanced / Custom Cypher](#stage-6-advanced--custom-cypher)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The DDR Agent is a conversational analyst available inside the Spotfire Copilot Panel. It is connected to a Neo4j knowledge graph of Daily Drilling Reports through a dedicated MCP server and is designed to answer questions in natural language — no Cypher, no SQL, and no manual report hunting required.

The agent uses a set of specialized tools to retrieve, aggregate, and summarize report data on demand. You can list reports, count them, compute depth statistics by wellbore or rig, compare extracted field values across the fleet, or open up a single report and ask for a full breakdown of its operations, activities, drilling fluids, and pore pressures.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the DDR knowledge graph through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`energy-ddr-neo4j` MCP server** — the agent's tools call this MCP server at runtime. See [Energy DDR Neo4j MCP server deployment guide](../MCP%20Servers/Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20Deployment%20Guide.md).

If either component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail to answer with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **DDR Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live DDR knowledge graph.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Filter             | Examples                                        |
| ------------------ | ----------------------------------------------- |
| Wellbore           | `15/9-F-5`, `34/10-A-1H`                        |
| Rig name           | `TREASURE PROSPECT`, `DEEPSEA ATLANTIC`         |
| Date range         | `between 2016-01-01 and 2016-03-31`, `last quarter` |
| Report ID          | The drilling report identifier from the graph  |
| Field key          | e.g. `depthAtLastCasingMmd`, `mudWeight`        |

If a required filter is missing for a precise answer, the agent will ask a short clarifying question rather than guess.

### What Data Is Available

The agent reads from a Neo4j knowledge graph populated by the DDR loader. Typical content includes:

- **Drilling reports** with `report_id`, `report_date`, `wellbore`, `rig_name`, and `distance_drilled`.
- **Operations** performed during each report (activity codes, durations, categories).
- **Summary and planned activities** as recorded by the rig crew.
- **Extracted fields** — numeric KPIs lifted from report sections (e.g. depth at last casing, mud weight).
- **Drilling fluid** rows and statistics (density, viscosity, funnel viscosity).
- **Pore pressure** rows and statistics.
- **Reference lists** of all known wellbores and rigs.

The agent does **not** ingest Spotfire columns, well production rates, well headers, formation tops, or seismic data. If your question requires data outside the DDR graph, the agent will say so.

## What the Agent Can Do

The DDR Agent groups its tools into the following capability areas:

| Capability             | What It Does                                                                                  | Example Request                                                  |
| ---------------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Report Discovery       | List reports by wellbore, rig, or date range; list all wellbores and rigs                      | "List reports for wellbore 15/9-F-5 in Q1 2016"                  |
| Counts & KPIs          | Count reports and compute max/avg/total depth at the field, wellbore, or rig level             | "How many reports do we have for rig TREASURE PROSPECT?"         |
| Field Analytics        | Discover extracted field keys and compute stats, comparisons, and raw values                   | "Compare mudWeight by rig"                                       |
| Report Deep Dives      | Fetch full details, operations, activities, fluids, and pressures for a specific report        | "Give me everything about report `abc-123`"                      |
| Advanced / Cypher      | Run a custom Cypher query for shapes no specialized tool can produce                           | "Run a Cypher query that joins reports and operations where ..." |

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step and no session-wide data cache to manage — every question is answered by calling the appropriate tools against the live graph.

### Stage 1: Orientation

**When to use:** You are new to the dataset and want to know what is available before asking detailed questions.

**Example prompts:**
- "What can you do?"
- "How many reports are in the database?"
- "List all wellbores."
- "List all rigs."
- "What extracted fields are available?"

**What you get back:** A short capability summary or a clean list of wellbores, rigs, or field keys you can use as filters in follow-up questions.

### Stage 2: Report Discovery

**When to use:** You want to find the reports that match a wellbore, rig, date range, or any combination of those filters.

**Example prompts:**
- "List the latest 50 reports."
- "Show reports for wellbore 15/9-F-5."
- "List reports for rig TREASURE PROSPECT between 2016-01-01 and 2016-03-31."
- "Find reports for wellbore 15/9-F-5 drilled by rig TREASURE PROSPECT in 2016."

**What you get back:** A clean table including, where available:

| Column            | Meaning                                       |
| ----------------- | --------------------------------------------- |
| `report_id`       | Unique identifier of the drilling report      |
| `report_date`     | Date the report was filed                     |
| `wellbore`        | Wellbore the report belongs to                |
| `rig_name`        | Rig that produced the report                  |
| `distance_drilled`| Distance drilled during the report period     |

The agent returns real rows only — no `...` placeholders. If the result set is too large, it returns a clean subset and explains, outside the table, how to narrow the filters.

### Stage 3: Counts and Depth KPIs

**When to use:** You want a single-number answer or a small statistical summary at the field, wellbore, or rig level.

**Example prompts:**
- "How many reports are available for wellbore 15/9-F-5?"
- "What is the max distance drilled overall?"
- "What is the max distance drilled for rig TREASURE PROSPECT?"
- "What is the average depth for wellbore 15/9-F-5?"
- "Give me full depth stats for wellbore 15/9-F-5 between 2016-01-01 and 2016-06-30."

**What you get back:** Concise KPI values such as `count`, `min`, `max`, `avg`, `total`, with the units and the filter context echoed back so the answer is traceable.

### Stage 4: Field Analytics

**When to use:** You want to study a specific extracted field (a KPI lifted from report text) across the fleet, or compare it by wellbore or rig.

**Example prompts:**
- "What extracted field keys are available?"
- "Compute stats for field `depthAtLastCasingMmd`."
- "Compute field stats for `mudWeight` filtered by wellbore 15/9-F-5."
- "Compare `mudWeight` by rig."
- "Show raw values of `mudWeight` for wellbore 15/9-F-5."

**What you get back:** Either an aggregated table (`value_count`, `avg`, `min`, `max`, `total`, units, field key) grouped by your dimension, or a list of raw values when you explicitly ask for them.

### Stage 5: Report Deep Dives

**When to use:** You have a specific `report_id` from an earlier list and want to understand what happened on that report.

**Example prompts:**
- "Get report details for report `abc-123`."
- "What operations were performed in report `abc-123`?"
- "Summarize the operations for report `abc-123`."
- "Show summary and planned activities for report `abc-123`."
- "Get drilling fluid stats for report `abc-123`."
- "Get pore pressure rows for report `abc-123`."
- "Give me everything about report `abc-123` in one call."

**What you get back:** A summary of the key findings — not a JSON dump — covering the requested aspects. For "everything" requests, the agent uses a single full-context tool and then condenses the response into readable sections.

### Stage 6: Advanced / Custom Cypher

**When to use:** Your question requires a shape, join, or filter that no specialized tool can produce.

**Example prompt:**
- "Run a Cypher query that returns the top 10 wellbores by total distance drilled in 2016."

**What you get back:** Before constructing Cypher, the agent first discovers the relevant labels, relationships, and properties (it never guesses). It then returns the query result as a table along with a short explanation. Use this as a fallback — the specialized tools are faster and safer for common questions.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering discovery, KPIs,
         field analytics, report deep dives, and custom Cypher.]

You:    How many reports do we have, and for which wellbores?

Agent:  Total reports: 1,284
        Distinct wellbores: 42
        Top wellbores by report count:
        15/9-F-5    218
        34/10-A-1H  176
        ...

You:    List reports for wellbore 15/9-F-5 between 2016-01-01 and
        2016-03-31.

Agent:  [Returns a table with report_id, report_date, rig_name,
         distance_drilled for the 18 matching reports.]

You:    What is the average depth and max distance drilled for that
        wellbore in the same period?

Agent:  Wellbore: 15/9-F-5
        Date range: 2016-01-01 .. 2016-03-31
        avg_depth: 2,418 m
        max_distance_drilled: 312 m
        report_count: 18

You:    Give me everything about report 15-9-F-5-2016-02-14.

Agent:  [Summarizes operations, activities, drilling fluid stats,
         and pore pressure stats for that report.]

You:    Compare mudWeight by rig.

Agent:  [Returns a table grouped by rig_name with value_count, avg,
         min, max, units.]

You:    Thanks.
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| No query language required           | Ask questions in plain English; the agent picks the right tool for you.                                                      |
| Specialized tools first              | Common questions are answered by purpose-built tools that already return canonical columns and units.                        |
| Honest, real-row tables              | The agent never inserts `...` or placeholder rows. Truncation, if any, is explained outside the table.                       |
| Cypher as a safety net               | When a question needs a custom shape, the agent does schema discovery first and then writes Cypher against real properties.  |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.               |
| Filterable at every level            | Wellbore, rig, date range, report ID, and extracted field key filters can be combined freely.                                |
| Deep dives in one call               | A single request can return the full context for a report, with the agent condensing it into readable sections.              |

## Tips for Best Results

- **Be specific with filters.** Mention the wellbore, rig, and date range when they matter — the agent applies them directly.
- **Use exact wellbore and rig names.** If you're unsure, ask "List all wellbores" or "List all rigs" first.
- **Quote report IDs.** Put the report ID in backticks or quotes to avoid ambiguity (e.g. `report abc-123`).
- **Discover fields before stats.** If you don't remember the exact field key, ask "What extracted fields are available?" before requesting stats.
- **Prefer specialized requests over Cypher.** "Average depth for wellbore X" is faster and safer than a custom Cypher query for the same thing.
- **Ask follow-up questions.** Use earlier results to drill in: list reports, then pick one, then ask for its full context.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                       | Definition                                                                                                                  |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| DDR                        | Daily Drilling Report — the daily record filed by the rig describing operations, depths, fluids, and pressures.             |
| Wellbore                   | A specific hole drilled into the subsurface, identified by an industry-standard name (e.g. `15/9-F-5`).                     |
| Rig                        | The drilling unit (land rig or offshore rig) that produced the report (e.g. `TREASURE PROSPECT`).                           |
| Report ID                  | The unique identifier of an individual DDR record in the knowledge graph.                                                   |
| Distance Drilled           | The length of new hole drilled during the period covered by a single report.                                                |
| Extracted Field            | A numeric KPI lifted from report text into the graph (e.g. `depthAtLastCasingMmd`, `mudWeight`).                            |
| Operations                 | The detailed activity records associated with a report (codes, durations, categories).                                      |
| Summary / Planned Activity | Narrative entries describing what was done and what is planned next, per report.                                            |
| Drilling Fluid             | Mud properties recorded during the report (density, viscosity, funnel viscosity, etc.).                                     |
| Pore Pressure              | Subsurface pressure measurements or estimates captured in the report.                                                       |
| Cypher                     | The graph query language used by Neo4j. The agent uses it only as a fallback when no specialized tool fits.                 |
| MCP Server                 | The Model Context Protocol server (`energy-ddr-neo4j`) that exposes the DDR tools the agent calls at runtime.               |
