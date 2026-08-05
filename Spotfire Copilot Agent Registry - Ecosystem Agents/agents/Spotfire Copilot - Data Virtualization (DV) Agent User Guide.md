# Data Virtualization (DV) Agent — User Guide

data × data-virtualization × odata

The Data Virtualization Agent is a specialist AI agent that discovers data sources, tables, and columns exposed by a Data Virtualization layer and executes OData v4 queries against them, helping analysts and business users answer data questions in plain language.

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
  - [Stage 2: Table Discovery](#stage-2-table-discovery)
  - [Stage 3: Column Discovery](#stage-3-column-discovery)
  - [Stage 4: Column Metadata](#stage-4-column-metadata)
  - [Stage 5: Query Construction and Execution](#stage-5-query-construction-and-execution)
  - [Stage 6: Multi-step Workflows](#stage-6-multi-step-workflows)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Data Virtualization Agent is a conversational analyst available inside the Spotfire Copilot Panel. It is connected to a Data Virtualization (DV) server through a dedicated MCP server and is designed to answer questions in natural language — no DV console, OData syntax, or table-name guessing required.

The agent uses a set of specialized tools to list the available data sources, browse their tables and columns, inspect column metadata, and execute OData v4 queries that return real data. It can chain tools automatically for compound questions (for example, "find the orders table, identify the discount column, and return the customer with the highest discount").

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the Data Virtualization layer through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`dv` MCP server** — the agent's tools call this MCP server at runtime. See the [DV MCP server user guide](../mcp-servers/data-virtualization-dv/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20User%20Guide.md) and [deployment guide](../mcp-servers/data-virtualization-dv/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20Deployment%20Guide.md).

If either component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail to answer with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Data Virtualization Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live Data Virtualization server.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Reference        | Examples                                                  |
| ---------------- | --------------------------------------------------------- |
| Data source      | `cds_tutorial`, `sales_db`, `inventory_db`                |
| Table            | `Order`, `Customer`, `Product`                            |
| Column           | `UnitPrice`, `discount`, `freight`                        |
| OData v4 query   | `/cds_tutorial/Order?$filter=UnitPrice gt 20&$top=10`     |
| Filter intent    | "highest discount", "top 10 by freight", "open orders"    |

If a required reference is missing (for example, a table name without a data source), the agent will ask a short clarifying question rather than guess.

### What Data Is Available

The agent reads from a Data Virtualization layer through the DV MCP server. Typical content includes:

- **Data sources** — federated databases and services configured in the DV layer.
- **Tables** — logical tables exposed by each data source.
- **Columns** — column names and their metadata (data type, length, etc.).
- **Query results** — rows returned by OData v4 queries executed against the DV server.

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, or external CSVs. Read access is determined by the credentials configured on the MCP server.

## What the Agent Can Do

The DV Agent groups its tools into the following capability areas:

| Capability                | What It Does                                                                                        | Example Request                                              |
| ------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| Data Source Discovery     | List all available data sources and get summary info for one                                         | "What data sources are available?"                           |
| Table Discovery           | List all tables, or tables for a specific data source                                                | "What tables are available for `cds_tutorial`?"              |
| Column Discovery          | List columns across all sources, by data source, by table, or by data source + table                 | "What columns can provide order details?"                    |
| Column Metadata           | Show data type, length, and other metadata for a specific column                                     | "What is the data type of `discount` in `Order`?"            |
| OData v4 Query Execution  | Run a full OData v4 query against the DV server and return the data                                  | "Run `/cds_tutorial/Order?$top=5&$select=OrderID,Customer`"  |
| Query Construction        | Combine discovery results to draft an accurate OData v4 query for review or execution                | "Get the customer with the highest discount on an order"     |

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step and no session-wide data cache to manage — every question is answered by calling the appropriate tools against the live DV server.

### Stage 1: Orientation

**When to use:** You want to know what is exposed by the DV layer before drilling in.

**Example prompts:**
- "What can you do?"
- "List all data sources."
- "Tell me about the `cds_tutorial` data source."

**What you get back:** A capability summary or a list of data sources (and an info block when you ask about a specific one).

### Stage 2: Table Discovery

**When to use:** You know the data source and want to find the right table.

**Example prompts:**
- "What tables are available?"
- "What tables are in `cds_tutorial`?"
- "List the order-related tables."

**What you get back:** A comma-separated list of tables, scoped to the data source if you provided one.

### Stage 3: Column Discovery

**When to use:** You want to know which columns exist and where, to drive a query.

**Example prompts:**
- "List all columns for the `Order` table."
- "Show me the columns of `cds_tutorial.Order`."
- "What columns can provide order details?"
- "What columns are in the `cds_tutorial` data source?"

**What you get back:** A list of fully-qualified or table-scoped column names, depending on the level of filter you used.

### Stage 4: Column Metadata

**When to use:** You need data type or length information for a specific column before filtering or aggregating.

**Example prompts:**
- "What is the metadata for `cds_tutorial.Order.discount`?"
- "What data type is `freight` in `cds_tutorial.Order`?"
- "Show me the column length for `cds_tutorial.Customer.name`."

**What you get back:** A description such as `Column Name: ..., Data Type: ..., Column Length: ...`.

### Stage 5: Query Construction and Execution

**When to use:** You want to ask a data question and have the agent draft and/or run an OData v4 query.

**Example prompts:**
- "What is the company name with the highest discount for an order?"
- "What is the highest freight charge for my orders?"
- "Get the top 10 orders sorted by `UnitPrice` descending."
- "Run `/cds_tutorial/Order?$filter=UnitPrice gt 20&$select=ProductName,UnitPrice&$top=20`."

**What you get back:** Either the OData v4 query (when you ask for the query only) or the rows returned by the DV server (when you ask to run it). The agent will typically discover the relevant table and columns first so the query is grounded in real metadata.

### Stage 6: Multi-step Workflows

**When to use:** Your question combines discovery and execution.

**Example prompts:**
- "Find the orders table in `cds_tutorial`, identify the discount column, and return the customer with the highest discount."
- "List the tables in `cds_tutorial`, pick the orders table, and return the top 5 highest freight charges."
- "What columns are in the `Order` table, and what is the average `UnitPrice`?"

**What you get back:** A consolidated answer where the agent has chained tools internally (list/describe → metadata → OData query) and reports the final result with brief notes about intermediate steps.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering data source
         discovery, table discovery, column discovery and metadata,
         OData v4 query execution, and multi-step workflows.]

You:    What data sources are available?

Agent:  cds_tutorial, sales_db, inventory_db, hr_db

You:    What tables are available for cds_tutorial?

Agent:  Order, OrderDetails, Customer, Product, ViewOrder

You:    What columns can provide order details?

Agent:  cds_tutorial.Order.OrderID, cds_tutorial.Order.CustomerID,
        cds_tutorial.Order.UnitPrice, cds_tutorial.Order.discount,
        cds_tutorial.Order.freight, cds_tutorial.Order.status,
        cds_tutorial.OrderDetails.ProductID,
        cds_tutorial.OrderDetails.Quantity, ...

You:    What is the company name with the highest discount for an order?

Agent:  Suggested OData v4 query:
        /cds_tutorial/ViewOrder?$orderby=discount desc&$top=1
                              &$select=CompanyName,discount

        Result:
        CompanyName       discount
        Acme Imports      0.42

You:    What is the highest freight charge for my orders?

Agent:  Suggested OData v4 query:
        /cds_tutorial/ViewOrder?$apply=aggregate(freight with max
                                       as highest_freight)

        Result:
        highest_freight
        1284.50

You:    Thanks.
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Natural-language data discovery      | Browse data sources, tables, and columns in plain English without opening the DV console.                                    |
| Metadata-grounded queries            | The agent inspects DV metadata before drafting OData queries, reducing guesswork and wrong column names.                     |
| OData v4 expressivity                | Supports the full OData v4 query surface (`$filter`, `$select`, `$orderby`, `$top`, `$expand`, `$apply`, ...).               |
| One-step execution                   | Ask for a query and the result in the same message; the agent runs it against the DV server.                                 |
| Flexible scoping                     | Column discovery can be scoped globally, by data source, by table, or by data source + table.                                |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.               |

## Tips for Best Results

- **Mention the data source.** Saying "in `cds_tutorial`" or "from `sales_db`" avoids ambiguity when multiple sources expose similarly-named tables.
- **Start broad, then narrow.** List data sources → list tables → list columns → ask the question. The agent will do this automatically if you give it a compound question, but explicit steps help when you're exploring.
- **Ask for metadata when filtering.** Knowing a column's data type avoids type mismatches in `$filter` expressions.
- **Be explicit about query vs. results.** Say "give me the OData query" if you only want the URL, or "run it and show the result" if you want execution.
- **Keep queries scoped.** Use `$top`, `$select`, and `$filter` for exploratory work to keep responses fast.
- **Use `$apply` for aggregations.** OData v4 `$apply=aggregate(...)` is the right tool for max/min/sum/avg questions.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                         | Definition                                                                                                              |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Data Virtualization (DV)     | A layer that exposes data from multiple underlying sources through a single virtual catalog and query interface.        |
| Data Source                  | A federated database or service registered in the DV layer (e.g. `cds_tutorial`, `sales_db`).                           |
| Table                        | A logical table exposed by a data source through the DV layer.                                                          |
| Column                       | A field in a logical table, identified as `datasource.table.column`.                                                    |
| OData v4                     | An open protocol for querying and manipulating data via HTTP. Supports `$filter`, `$select`, `$orderby`, `$top`, etc.   |
| `$filter` / `$select`        | OData v4 query options to restrict rows / pick specific columns.                                                        |
| `$orderby` / `$top`          | OData v4 query options to sort and limit results.                                                                       |
| `$apply` / `aggregate`       | OData v4 query option for aggregations such as max/min/sum/avg.                                                         |
| MCP Server                   | The Model Context Protocol server (`dv`) that exposes the Data Virtualization tools the agent calls at runtime.         |
