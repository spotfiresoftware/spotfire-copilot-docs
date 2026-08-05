# Spotfire Library Metadata Agent — User Guide

spotfire × library × metadata

The Spotfire Library Metadata Agent is a specialist AI agent that browses a Spotfire Server's library to answer questions about library items of any kind — Spotfire Analysis files (DXPs), data connections, information links, data functions, columns, folders, and more — including their metadata, properties, and permissions.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [Supported Item Types](#supported-item-types)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Orientation](#stage-1-orientation)
  - [Stage 2: Discovery (list & search)](#stage-2-discovery-list--search)
  - [Stage 3: Item Details](#stage-3-item-details)
  - [Stage 4: Connectivity Q&A](#stage-4-connectivity-qa)
  - [Stage 5: Multi-step Workflows](#stage-5-multi-step-workflows)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Spotfire Library Metadata Agent is a conversational assistant available inside the Spotfire Copilot Panel. It is connected to a Spotfire Server's Library Service through a dedicated MCP server and is designed to answer questions in natural language — no Library Administration console, REST API calls, or item ID lookups required.

The agent uses two generic library tools: one to list/search items of a chosen kind (with filters by creator, title, and path), and one to retrieve the full library metadata of a single item by its id. It maps your natural-language request to the right item kind, so you can ask about DXPs, data connections, information links, data functions, columns, folders, and more.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the Spotfire Server library through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`spotfire-lib` MCP server** — the agent's tools call this MCP server at runtime. See the [Spotfire Library MCP server user guide](../mcp-servers/spotfire-library/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20User%20Guide.md) and [deployment guide](../mcp-servers/spotfire-library/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md).

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
| Item kind          | "DXPs", "data connections", "information links", "data functions" |
| Library path       | `/public/Energy`, `/Users/jdoe/Reports`                        |
| Author             | "created by Evie", "made by John Doe"                          |
| Title fragment     | "sales", "drilling", "marketing report"                        |
| System (connectivity) | TDV, Snowflake, Oracle, ODBC                                |
| Item identifier    | a name like `SalesAnalysis.dxp`, or a specific item ID for exact metadata |

If the item kind is ambiguous, or a required reference is missing (for example, an explicit item when asking for its properties), the agent will ask a short clarifying question rather than guess.

### What Data Is Available

The agent reads from a Spotfire Server library through the `spotfire-lib` MCP server. Typical content includes:

- **Library items of any kind** — DXPs, data connections, information links, data functions, data sources, visualization mods, columns, folders, and more (see [Supported Item Types](#supported-item-types)) — each with `id`, `title`, `path`, `type`, creator, and modified date.
- **Item metadata** — for a specific item: its library `properties` (key/value pairs — e.g. a data connection's source database and connector type), authorship, permissions, and type. This is the item metadata the Spotfire Server stores; for a DXP it is not the analysis internals.

The agent does **not** open or render DXPs, ingest spreadsheet uploads, or read marked rows from a visualization. Read access is determined by the credentials configured on the MCP server (a Spotfire Server client ID and secret).

## What the Agent Can Do

The Spotfire Library Metadata Agent groups its tools into the following capability areas:

| Capability                  | What It Does                                                                                       | Example Request                                              |
| --------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| Discovery (list & search)   | List or search library items of a chosen kind, with filters by author, title, and path              | "What information links are available under `/public`?"      |
| Item Details                | Return the full library metadata for a specific item — type, properties, authorship, permissions    | "Show details for `SalesDB` / `SalesAnalysis.dxp`."          |
| Item Children               | List the direct children of an item — e.g. the columns of a data source, or the contents of a folder | "What columns does the `SalesData` data source have?"        |
| Connectivity Q&A            | Answer whether a particular system can be reached through the registered data connections            | "Can I connect to Snowflake from this server?"               |
| Library Navigation          | Combine filters to drill into a subtree of the library for any item kind                             | "List the marketing DXPs modified this year."                |
| Inventory Summaries         | Combine multiple tool calls to summarize library content                                              | "How many data functions are under `/public/Analytics`?"     |

## Supported Item Types

You can ask the agent to discover or inspect any of these kinds — it maps your wording to the right kind automatically:

DXPs (analysis files), data connections (connectors), information links, data functions, data sources, connection data sources, visualization mods, action mods, SBDF data files, shapes, filters, joins, procedures, DXP scripts, color schemes, folders, columns, and automation service jobs.

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step — every question is answered by calling the appropriate tools against the live Spotfire Server library.

### Stage 1: Orientation

**When to use:** You want to know what is available before drilling in.

**Example prompts:**
- "What can you do?"
- "What connectors are available in this Spotfire server?"
- "List the DXPs in the library."

**What you get back:** A capability summary or a list of items of the requested kind.

### Stage 2: Discovery (list & search)

**When to use:** You want to find items of a given kind by author, title, or library path.

**Example prompts:**
- "What DXPs has Evie created under `/public/Energy`?"
- "Which data connections have `Sales` in the title?"
- "What information links live under `/public`?"
- "List up to 25 data functions by John Doe."

**What you get back:** A list of items scoped to your filters, each with `id`, `title`, `path`, `type`, author, and modified date. The agent applies server-side filtering to keep responses focused.

### Stage 3: Item Details

**When to use:** You want the full library metadata for one specific item.

**Example prompts:**
- "Show details for `SalesAnalysis.dxp`."
- "What source database does the `MarketingWarehouse` connection use?"
- "What properties are set on `<item>`?"
- "Who created / who can access `<item>`?"

**What you get back:** A consolidated library-metadata record covering the item's basic info, type, authorship, permissions, and stored properties. If you gave only a name, the agent first lists that kind to resolve the item's id. You can also list the item's **children** (e.g. the columns of a data source, or the contents of a folder) using the same id.

### Stage 4: Connectivity Q&A

**When to use:** You want to know whether an external system can be reached through this Spotfire Server.

**Example prompts:**
- "Can I connect to Snowflake?"
- "Can I connect to TDV from here?"
- "What systems can I integrate with?"

**What you get back:** The agent checks the registered data connections and answers whether a specific system is present, quoting the matching connection (or listing the closest alternatives).

### Stage 5: Multi-step Workflows

**When to use:** Your question combines discovery and item details.

**Example prompts:**
- "Find DXPs by Evie under `/public/Energy` and show the properties and permissions for the most recent one."
- "List the most recent data functions and show the details for the top one."
- "What connectors are available, and who created the Snowflake connection?"

**What you get back:** A consolidated answer where the agent has chained tools internally (list → filter → metadata lookup) and reports a summary with brief notes about intermediate steps.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering discovery of any
         item kind, item-metadata lookups, connectivity Q&A, and
         multi-step library workflows.]

You:    What information links are available under /public?

Agent:  Found 3 information links under /public:
        1. id=il-01 | title=SalesByRegion   | path=/public/IL/SalesByRegion   | createdBy=Evie
        2. id=il-02 | title=InventoryLevels | path=/public/IL/InventoryLevels | createdBy=John Doe
        3. id=il-03 | title=CustomerChurn   | path=/public/IL/CustomerChurn   | createdBy=Evie

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
        - Type: spotfire.dxp
        - Created by: Evie
        - Last modified: 2026-04-12
        - Permissions: Read/Write (Energy group), Read (public)
        - Properties: the item properties recorded by the
          Spotfire Server (e.g. DisplayName, ContentSize)

You:    Thanks.
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Natural-language library browsing    | Discover any library item kind and its metadata in plain English without opening the Library Administration tools.           |
| Any item type                        | One agent covers DXPs, data connections, information links, data functions, columns, folders, and more.                      |
| Server-side filtering                | Discovery queries support filters by creator, title, and path, keeping responses focused even for large libraries.           |
| Rich library metadata                | One call returns an item's basic info, type, authorship, permissions, and stored properties — for any kind.                  |
| Connectivity Q&A                     | Quickly answer "can I reach system X?" questions by checking the registered data connections.                                |
| Combines discovery and detail        | Multi-step questions are handled by chaining tools internally and presenting a single answer.                                 |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.               |

## Tips for Best Results

- **Name the item kind.** Say "information links", "data functions", "data connections", or "DXPs" so the agent picks the right kind; if it's ambiguous it will ask.
- **Filter early.** Mentioning a path prefix (`/public/Energy`) or author ("created by Evie") narrows the result set on the server side.
- **Use title fragments.** Saying "DXPs with `sales` in the title" leverages server-side title contains-matching for fast, focused results.
- **Cap your list.** For exploratory queries, asking for "the top 20" or "up to 25" keeps responses easy to scan.
- **Reference an item explicitly.** When you want metadata, name the item (`SalesAnalysis.dxp`) or paste its ID for an exact lookup.
- **Ask connectivity questions plainly.** "Can I connect to Snowflake?" is enough — the agent will check the data connections and answer.
- **Stack questions.** It is fine to ask "List DXPs by Evie under `/public/Energy` and show the properties of the most recent one" — the agent will chain the tool calls.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                         | Definition                                                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Spotfire Server              | The server that hosts the Spotfire library, user accounts, connectors, and web/automation services.                       |
| Library                      | A hierarchical store on the Spotfire Server containing DXP files, data connections, information links, data functions, and many other item kinds. |
| Library item / Item type     | Any object stored in the library. Its `type` (e.g. `spotfire.dxp`, `spotfire.dataconnection`, `spotfire.query`) determines its kind. |
| DXP                          | A Spotfire Analysis file (`*.dxp`) containing visualizations, data tables, pages, bookmarks, and configuration.           |
| Connector                    | A registered connection to an external system (Snowflake, Oracle, TDV, ODBC, etc.) that DXPs can use as a data source.    |
| Information Link             | A legacy Spotfire mechanism for defining reusable, parameterized SQL queries against a data source.                       |
| Library Path                 | The slash-separated location of an item in the library, e.g. `/public/Energy/WellPerformance.dxp`.                        |
| Item Version                 | A snapshot of a library item; the Spotfire Server retains a version history for each item.                                |
| MCP Server                   | The Model Context Protocol server (`spotfire-lib`) that exposes the library tools the agent calls at runtime.             |
