# Spotfire Library Metadata Agent — User Guide

spotfire × library × metadata

The Spotfire Library Metadata Agent is a specialist AI agent that browses a Spotfire Server's library to answer questions about available data connectors and Spotfire Analysis files (DXPs), including their metadata, properties, and versions.

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
  - [Stage 2: Connector Discovery](#stage-2-connector-discovery)
  - [Stage 3: DXP Discovery](#stage-3-dxp-discovery)
  - [Stage 4: DXP Metadata](#stage-4-dxp-metadata)
  - [Stage 5: Multi-step Workflows](#stage-5-multi-step-workflows)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Spotfire Library Metadata Agent is a conversational assistant available inside the Spotfire Copilot Panel. It is connected to a Spotfire Server's Library Service through a dedicated MCP server and is designed to answer questions in natural language — no Library Administration console, REST API calls, or item ID lookups required.

The agent uses a set of specialized tools to list the data connectors registered on the Spotfire Server, browse the DXP files available in the library (with filters by creator, title, and path), and retrieve detailed metadata for a specific DXP, including its data tables, columns, pages, bookmarks, and versions.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the Spotfire Server library through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../Agent%20Server%20Deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../Agent%20Server%20Deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`spotfire-lib` MCP server** — the agent's tools call this MCP server at runtime. See the [Spotfire Library MCP server user guide](../MCP%20Servers/Spotfire%20Library/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20User%20Guide.md) and [deployment guide](../MCP%20Servers/Spotfire%20Library/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md).

If either component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail to answer with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Spotfire Library Metadata Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live Spotfire Server library.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Reference          | Examples                                                       |
| ------------------ | -------------------------------------------------------------- |
| Library path       | `/public/Energy`, `/Users/jdoe/Reports`                        |
| Author             | "created by Evie", "made by John Doe"                          |
| Title fragment     | "sales", "drilling", "marketing report"                        |
| Connector type     | TDV, Snowflake, Information Links, Oracle, ODBC                |
| DXP identifier     | `SalesAnalysis.dxp`, or a specific item ID for deep metadata   |

If a required reference is missing (for example, an explicit DXP when asking for its tables and columns), the agent will ask a short clarifying question rather than guess.

### What Data Is Available

The agent reads from a Spotfire Server library through the `spotfire-lib` MCP server. Typical content includes:

- **Data connectors** — every connector registered on the server, with type, description, properties, and permissions.
- **DXP files** — Spotfire Analysis files in the library, with title, path, creator, and modified date.
- **DXP metadata** — for a specific DXP: tables and columns counts, pages, bookmarks, embedded data flags, version history, and permissions.

The agent does **not** open or render DXPs, ingest spreadsheet uploads, or read marked rows from a visualization. Read access is determined by the credentials configured on the MCP server (a Spotfire Server client ID and secret).

## What the Agent Can Do

The Spotfire Library Metadata Agent groups its tools into the following capability areas:

| Capability                  | What It Does                                                                                       | Example Request                                              |
| --------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| Connector Discovery         | List every data connector registered on the Spotfire Server and inspect its type and properties     | "What connectors are available?"                             |
| Connectivity Q&A            | Answer questions about whether a particular system can be reached through existing connectors        | "Can I connect to Snowflake from this server?"               |
| DXP Discovery               | List DXPs in the library with filters by author, title, and path                                     | "What DXPs has Evie created under `/public/Energy`?"         |
| DXP Metadata                | Return detailed metadata for a specific DXP — tables, columns, pages, bookmarks, versions            | "Show details for `SalesAnalysis.dxp`."                      |
| Library Navigation          | Combine filters to drill into a subtree of the library                                               | "List the marketing reports modified this year."             |
| Inventory Summaries         | Combine multiple tool calls to summarize library content                                              | "How many DXPs are under `/public/Sales`?"                   |

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step — every question is answered by calling the appropriate tools against the live Spotfire Server library.

### Stage 1: Orientation

**When to use:** You want to know what is available on the Spotfire Server before drilling in.

**Example prompts:**
- "What can you do?"
- "What connectors are available in this Spotfire server?"
- "List the DXPs in the library."

**What you get back:** A capability summary or a JSON-derived list of connectors / DXPs.

### Stage 2: Connector Discovery

**When to use:** You want to know which external systems can be reached through this Spotfire Server.

**Example prompts:**
- "What connectors are available?"
- "Can I connect to TDV from here?"
- "Can I connect to Snowflake?"
- "What data sources can I access through Information Links?"

**What you get back:** The list of connectors with their types and properties, and a direct answer about whether a specific connector type is present.

### Stage 3: DXP Discovery

**When to use:** You want to find Spotfire Analysis files by author, title, or library path.

**Example prompts:**
- "What DXPs are available?"
- "What DXPs has Evie created?"
- "Which DXPs have `Sales` in the title?"
- "What DXPs are under `/public/Energy`?"
- "List up to 25 DXPs by John Doe under `/public/Reports`."

**What you get back:** A list of DXPs scoped to your filters, each with its title, path, author, and modified date. The agent applies server-side filtering to keep responses focused.

### Stage 4: DXP Metadata

**When to use:** You want full details for a specific DXP.

**Example prompts:**
- "Show details for `SalesAnalysis.dxp`."
- "How many tables and columns are in `MarketingReport.dxp`?"
- "What pages and bookmarks are in DXP `<id>`?"
- "Who can access `QuarterlyReview.dxp`?"

**What you get back:** A consolidated metadata record covering tables/column counts, pages, bookmarks, embedded data flags, permissions, properties, and version history.

### Stage 5: Multi-step Workflows

**When to use:** Your question combines discovery and metadata.

**Example prompts:**
- "Find DXPs by Evie under `/public/Energy` and tell me how many tables each one has."
- "List the most recent sales DXPs and show me the page count for the top one."
- "What connectors are available, and which DXPs use the Snowflake connector?"

**What you get back:** A consolidated answer where the agent has chained tools internally (list → filter → metadata lookup) and reports a summary with brief notes about intermediate steps.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering connector
         discovery, DXP discovery with filters, DXP metadata
         lookups, and multi-step library workflows.]

You:    What connectors are available in this Spotfire server?

Agent:  The server has the following connectors:
        - Snowflake (Spotfire.Connector)
        - Oracle (Spotfire.Connector)
        - TDV / Data Virtualization (Spotfire.Connector)
        - Information Links (legacy)
        - ODBC

You:    Can I connect to Snowflake?

Agent:  Yes — a Snowflake connector is registered on this server.

You:    What DXPs has Evie created under /public/Energy?

Agent:  Found 3 DXPs created by Evie under /public/Energy:
        - WellPerformance.dxp        modified 2026-04-12
        - RigUtilization.dxp         modified 2026-03-28
        - ProductionForecast.dxp     modified 2026-02-09

You:    Show details for WellPerformance.dxp.

Agent:  WellPerformance.dxp
        - Path: /public/Energy/WellPerformance.dxp
        - Created by: Evie
        - Tables: 4, Columns: 87, Pages: 6
        - Bookmarks: 3
        - Embedded data: yes
        - Latest version: 12 (modified 2026-04-12)

You:    Thanks.
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Natural-language library browsing    | Discover connectors, DXPs, and their metadata in plain English without opening the Library Administration tools.             |
| Server-side filtering                | DXP queries support filters by creator, title, and path, keeping responses focused even for large libraries.                  |
| Rich DXP metadata                    | One call returns tables, columns, pages, bookmarks, embedded data flags, permissions, and version history.                    |
| Connectivity Q&A                     | Quickly answer "can I reach system X?" questions by checking the registered connectors.                                       |
| Combines discovery and detail        | Multi-step questions are handled by chaining tools internally and presenting a single answer.                                 |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.               |

## Tips for Best Results

- **Filter early.** Mentioning a path prefix (`/public/Energy`) or author ("created by Evie") narrows the result set on the server side.
- **Use title fragments.** Saying "DXPs with `sales` in the title" leverages server-side title contains-matching for fast, focused results.
- **Cap your list.** For exploratory queries, asking for "the top 20" or "up to 25" keeps responses easy to scan.
- **Reference a DXP explicitly.** When you want metadata, name the DXP (`SalesAnalysis.dxp`) or paste its ID for an exact lookup.
- **Ask connectivity questions plainly.** "Can I connect to Snowflake?" is enough — the agent will check the connector list and answer.
- **Stack questions.** It is fine to ask "List DXPs by Evie under `/public/Energy` and tell me how many tables the most recent one has" — the agent will chain the tool calls.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                         | Definition                                                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Spotfire Server              | The server that hosts the Spotfire library, user accounts, connectors, and web/automation services.                       |
| Library                      | A hierarchical store on the Spotfire Server containing DXP files, data connections, information links, and other items.   |
| DXP                          | A Spotfire Analysis file (`*.dxp`) containing visualizations, data tables, pages, bookmarks, and configuration.           |
| Connector                    | A registered connection to an external system (Snowflake, Oracle, TDV, ODBC, etc.) that DXPs can use as a data source.    |
| Information Link             | A legacy Spotfire mechanism for defining reusable, parameterized SQL queries against a data source.                       |
| Library Path                 | The slash-separated location of an item in the library, e.g. `/public/Energy/WellPerformance.dxp`.                        |
| Item Version                 | A snapshot of a library item; the Spotfire Server retains a version history for each item.                                |
| MCP Server                   | The Model Context Protocol server (`spotfire-lib`) that exposes the library tools the agent calls at runtime.             |
