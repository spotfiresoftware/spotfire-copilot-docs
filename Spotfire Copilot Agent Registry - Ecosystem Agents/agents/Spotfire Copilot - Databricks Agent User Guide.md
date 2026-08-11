# Databricks Agent — User Guide

data × databricks × unity-catalog × sql

The Databricks Agent is a specialist AI agent that explores Unity Catalog metadata, traces table lineage, and runs SQL against Databricks, helping analysts and data engineers discover data and generate accurate queries without leaving the chat.

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
  - [Stage 2: Catalog and Schema Discovery](#stage-2-catalog-and-schema-discovery)
  - [Stage 3: Table Structure](#stage-3-table-structure)
  - [Stage 4: Data Lineage and Code Discovery](#stage-4-data-lineage-and-code-discovery)
  - [Stage 5: Query Construction and Execution](#stage-5-query-construction-and-execution)
  - [Stage 6: Multi-step Workflows](#stage-6-multi-step-workflows)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Databricks Agent is a conversational analyst available inside the Spotfire Copilot Panel. It is connected to a Databricks workspace through a dedicated MCP server and is designed to answer questions in natural language — no Unity Catalog navigation, SQL boilerplate, or workspace tabs required.

The agent uses a set of specialized tools to discover catalogs, schemas, and tables, inspect table columns and partitioning, trace upstream and downstream data lineage (including the notebooks and jobs that produce or consume tables), and execute SQL queries against a configured SQL warehouse. It returns Markdown-formatted results that are easy to read in chat.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the Databricks workspace through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`databricks` MCP server** — the agent's tools call this MCP server at runtime. See the [Databricks MCP server user guide](../mcp-servers/databricks/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20User%20Guide.md) and [deployment guide](../mcp-servers/databricks/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Deployment%20Guide.md).

If either component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail to answer with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Databricks Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live Databricks workspace.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Reference        | Examples                                                       |
| ---------------- | -------------------------------------------------------------- |
| Catalog          | `prod`, `dev`, `samples`, `system`                             |
| Schema           | `sales`, `bi_conformed`, `accuweather`                         |
| Table            | Fully qualified `catalog.schema.table`, e.g. `prod.sales.orders` |
| Column           | Plain column names if they belong to a known table             |
| SQL              | A specific SQL statement you want executed                     |
| Lineage scope    | "upstream", "downstream", "notebooks that write to this table" |

If a required reference is missing (for example, a table name without a catalog), the agent will ask a short clarifying question rather than guess.

### What Data Is Available

The agent reads from a Databricks workspace through the Databricks MCP server. Typical content includes:

- **Unity Catalog metadata** — catalogs, schemas, and tables with their descriptions and ownership.
- **Table structure** — columns, data types, comments, and partitioning information.
- **Data lineage** — upstream and downstream tables, plus notebooks and jobs that read from or write to a table.
- **Notebook references** — workspace paths to notebooks involved in lineage (so you can open them directly).
- **Query results** — rows returned by SQL statements executed against the configured SQL warehouse.

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, or external CSVs. Read/query permissions are determined by the identity and warehouse configured on the MCP server.

## What the Agent Can Do

The Databricks Agent groups its tools into the following capability areas:

| Capability             | What It Does                                                                                       | Example Request                                                            |
| ---------------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Catalog Discovery      | List all accessible Unity Catalogs                                                                  | "What catalogs are available?"                                             |
| Catalog & Schema Detail| Describe a catalog's schemas, or a schema's tables (optionally with columns)                        | "Describe the `samples` catalog" / "Describe the `accuweather` schema"     |
| Table Structure        | Show columns, types, comments, and partitioning for a specific table                                | "Get the structure of `prod.sales.orders`"                                 |
| Data Lineage           | Trace upstream/downstream tables plus notebooks and jobs that read or write a table                 | "Show lineage and processing notebooks for `prod.sales.orders`"            |
| SQL Execution          | Run a SQL query against the configured Databricks SQL warehouse                                     | "Run `SELECT city, MAX(temperature) FROM ... GROUP BY city`"               |
| Query Construction     | Combine discovery and lineage results to draft an accurate SQL query for review or execution        | "Give me the SQL to get the city with the highest temperature"             |

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step and no session-wide data cache to manage — every question is answered by calling the appropriate tools against the live Databricks workspace.

### Stage 1: Orientation

**When to use:** You are new to the workspace and want to see what is available before drilling in.

**Example prompts:**
- "What can you do?"
- "List the available catalogs."
- "What types of data are in the `samples` catalog?"

**What you get back:** A capability summary or a Markdown list of catalogs and their descriptions.

### Stage 2: Catalog and Schema Discovery

**When to use:** You know roughly what you want but not the exact table.

**Example prompts:**
- "Describe the `prod` catalog."
- "What schemas are in `samples`?"
- "Describe the `accuweather` schema."
- "Describe the `sales` schema and include column details."

**What you get back:** A summary of the catalog's schemas (or the schema's tables). Add "include columns" to get column-level detail useful for query building.

### Stage 3: Table Structure

**When to use:** You have a specific table in mind and want its columns and types.

**Example prompts:**
- "Get the table structure for `samples.accuweather.forecast_hourly_metric`."
- "What columns does `prod.sales.orders` have?"
- "Show data types and partitioning for `prod.sales.orders`."

**What you get back:** A Markdown table listing columns with types, comments, and partitioning information.

### Stage 4: Data Lineage and Code Discovery

**When to use:** You want to understand where a table's data comes from, where it goes, or which notebooks process it.

**Example prompts:**
- "Show the data lineage for `prod.sales.orders`."
- "What notebooks write to `prod.sales.orders`?"
- "Trace upstream and downstream tables for `samples.accuweather.forecast_hourly_metric`."
- "Provide the structure and data lineage for `forecast_hourly_metric`."

**What you get back:** Upstream and downstream tables, plus the notebooks and jobs that read from or write to the table, with workspace paths you can open to inspect the transformation logic.

### Stage 5: Query Construction and Execution

**When to use:** You want to ask a data question and have the agent draft and/or run the SQL.

**Example prompts:**
- "Can you get the city with the highest temperatures?"
- "Can you provide the SQL to get that information?"
- "Run a query that returns the top 10 customers by order total in 2024."
- "Execute: `SELECT customer_id, SUM(order_total) FROM prod.sales.orders WHERE order_date > '2024-01-01' GROUP BY customer_id ORDER BY 2 DESC LIMIT 10`."

**What you get back:** Either the SQL statement (when you ask for SQL only) or a Markdown result table (when you ask to run it). The agent will typically discover the relevant table and columns first so the SQL is grounded in real metadata.

### Stage 6: Multi-step Workflows

**When to use:** Your question combines discovery, lineage, and querying.

**Example prompts:**
- "Find the table that stores hourly forecasts in `samples`, describe it, and show the city with the highest average temperature for July."
- "Trace lineage for `prod.sales.orders` and write a SQL that joins it with its primary upstream table."
- "Describe the `accuweather` schema, pick the forecast table, and return the top 5 hottest cities."

**What you get back:** A consolidated answer where the agent has chained tools internally (list/describe → lineage → SQL) and reports the final result with brief notes about intermediate steps.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering catalog discovery,
         catalog/schema detail, table structure, lineage, SQL
         execution, and multi-step workflows.]

You:    List available catalogs.

Agent:  Found 5 catalogs:
        - samples       Sample datasets shipped with Databricks
        - prod          Main production catalog
        - dev           Development catalog
        - system        System and audit data
        - main          Default catalog
        ...

You:    Describe the samples catalog.

Agent:  samples contains 4 schemas:
        - accuweather   Weather forecast data
        - tpch          TPC-H benchmark tables
        - nyctaxi       NYC taxi trips
        - retail        Retail sample data

You:    Get the structure for samples.accuweather.forecast_hourly_metric.

Agent:  [Returns a Markdown table with columns, types, and comments.]

You:    Provide the structure and data lineage for forecast_hourly_metric.

Agent:  [Returns columns + upstream tables + downstream tables +
         notebooks that read/write the table with workspace paths.]

You:    Can you get the city with the highest temperatures?

Agent:  Suggested SQL:
        SELECT city, MAX(temperature) AS max_temp
        FROM samples.accuweather.forecast_hourly_metric
        GROUP BY city
        ORDER BY max_temp DESC
        LIMIT 1;

        Result:
        city    max_temp
        Phoenix 47.8

You:    Thanks.
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Natural-language data discovery      | Browse catalogs, schemas, and tables in plain English without opening the Databricks UI.                                     |
| Metadata-grounded SQL                | The agent inspects Unity Catalog descriptions and column details before drafting queries, reducing guesswork.                |
| Comprehensive lineage                | Trace upstream/downstream tables plus the notebooks and jobs involved in producing or consuming a table.                     |
| Code discovery                       | Lineage results include workspace paths to notebooks so you can inspect the actual transformation logic.                     |
| One-step execution                   | Ask for SQL and the result in the same message; the agent runs the statement against the configured SQL warehouse.            |
| Markdown output                      | All descriptions and result tables are returned as Markdown, optimized for chat reading and copy-paste.                       |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.                |

## Tips for Best Results

- **Use fully qualified table names.** `catalog.schema.table` avoids ambiguity (e.g. `prod.sales.orders`).
- **Start broad, then narrow.** List catalogs → describe a catalog → describe a schema → describe a table.
- **Ask for columns when drafting SQL.** Add "include columns" or "with column detail" to your schema description requests so the agent can write accurate SQL.
- **Request lineage when debugging data.** Lineage reveals the notebooks and upstream tables that explain unexpected values.
- **Be explicit about SQL vs. results.** Say "give me the SQL" if you only want the statement, or "run this and show the result" if you want execution.
- **Keep queries scoped.** Add `LIMIT` and `WHERE` clauses for exploratory work to avoid long-running queries.
- **Open notebooks directly.** When the agent shows a notebook path in lineage, you can open it in your Databricks workspace to review the code.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                | Definition                                                                                                                  |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Unity Catalog (UC)  | Databricks' centralized governance layer for cataloging, securing, and discovering data assets.                             |
| Catalog             | The top-level container in Unity Catalog (e.g. `prod`, `dev`, `samples`).                                                   |
| Schema              | A namespace inside a catalog that groups related tables (e.g. `sales`, `accuweather`).                                      |
| Table               | A managed or external table within a schema; the unit you query with SQL.                                                   |
| Column              | A single field within a table, with a name, data type, and optional description.                                            |
| Lineage             | The chain of upstream and downstream relationships between tables, plus the notebooks and jobs that read or write them.     |
| Notebook            | A Databricks document containing code (Python, SQL, Scala) that often implements transformation logic.                      |
| Job                 | A scheduled or triggered execution unit that runs notebooks or other tasks in Databricks.                                   |
| SQL Warehouse       | The compute endpoint that executes SQL queries; the agent uses it for `execute_sql_query`.                                  |
| MCP Server          | The Model Context Protocol server (`databricks`) that exposes the Databricks tools the agent calls at runtime.              |
