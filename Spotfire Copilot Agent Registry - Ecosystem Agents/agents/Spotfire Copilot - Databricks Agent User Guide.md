# Databricks Agent — User Guide

data × databricks × functions × vector-search × genie × sql

The Databricks Agent is a specialist AI agent that connects to several **Databricks‑managed MCP servers** and helps you work with a Databricks workspace in natural language: it calls Unity Catalog **functions**, retrieves grounded passages from **Vector Search** indexes, answers data questions with **Genie**, and runs **SQL** — all from the Spotfire Copilot Panel.

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
  - [Stage 2: Ask Data Questions with Genie](#stage-2-ask-data-questions-with-genie)
  - [Stage 3: Grounded Retrieval with Vector Search](#stage-3-grounded-retrieval-with-vector-search)
  - [Stage 4: Run Unity Catalog Functions](#stage-4-run-unity-catalog-functions)
  - [Stage 5: Run SQL](#stage-5-run-sql)
  - [Stage 6: Multi-step Workflows](#stage-6-multi-step-workflows)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Databricks Agent is a conversational assistant available inside the Spotfire Copilot Panel. It connects to a Databricks workspace through the workspace's **Databricks‑managed MCP servers** and answers questions in natural language — no Unity Catalog navigation, SQL boilerplate, or workspace tabs required.

Rather than a single backend, the agent aggregates tools from up to four Databricks‑managed MCP servers, each covering a different capability:

- **Unity Catalog Functions** — call registered UC functions (domain analysis and text/LLM helpers) as tools.
- **Vector Search** — retrieve relevant passages from indexed documents/knowledge (Retrieval‑Augmented Generation).
- **Genie** — ask natural‑language data questions; Genie writes and runs the SQL for you.
- **DBSQL** — execute SQL directly against Unity Catalog (read‑only by default).

Any server that is not configured is simply unavailable; the agent works with whatever capabilities are connected. It returns Markdown‑formatted results that are easy to read in chat.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions you type into the Spotfire Copilot Panel, and all answers come from the Databricks workspace through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, the following must be in place:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **Databricks‑managed MCP servers** — the relevant managed MCP endpoints must be enabled in your Databricks workspace and configured on the agent server (one URL per capability: Functions, Vector Search, Genie, DBSQL). No separate self‑hosted MCP server is required.
- **A Databricks service principal (OAuth M2M)** — the agent authenticates to the managed servers with a service principal using OAuth (tokens are minted and refreshed automatically). The service principal must have permission to use the functions, indexes, Genie spaces, and warehouses you expect to access.

Configuration of these endpoints and credentials is covered in the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md#databricks-agent). If a capability's server is not configured or the service principal lacks permission, that capability's tools will be unavailable and the agent will say so.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Databricks Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always works against the live Databricks workspace.

### What You Provide

The agent only needs **natural‑language questions**. To get focused answers, mention any of the following when they apply:

| Reference        | Examples                                                              |
| ---------------- | -------------------------------------------------------------------- |
| Data question    | "Total production by field last month", "Top 10 customers by revenue"|
| Knowledge topic  | "What does the knowledge base say about managed pressure drilling?"  |
| Function + input | "Diagnose this well's production: …", "Summarize this text: …"       |
| SQL              | A specific SQL statement you want executed                           |
| Table            | Fully qualified `catalog.schema.table` for SQL, e.g. `prod.sales.orders` |

If a required detail is missing (for example, a vague time window), the agent will ask a short clarifying question or resolve it explicitly before acting.

### What Data Is Available

What the agent can reach depends on which Databricks‑managed servers are configured and what the service principal is allowed to use:

- **Unity Catalog functions** — the functions registered under the configured `{catalog}.{schema}`, exposed as callable tools.
- **Vector Search indexes** — the configured indexes, queried for the most relevant chunks (grounded retrieval).
- **Genie** — natural‑language answers grounded in the configured Genie Spaces and Unity Catalog, including the SQL Genie ran.
- **SQL results** — rows returned by SQL executed against Unity Catalog via the DBSQL server.

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, or external CSVs. Access is governed by the identity (service principal) and the resources it is permitted to use.

## What the Agent Can Do

The Databricks Agent groups its tools into four capability areas (each backed by a Databricks‑managed MCP server):

| Capability             | What It Does                                                                                   | Example Request                                                            |
| ---------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Unity Catalog Functions | Call registered UC functions as tools — domain analysis and text/LLM helpers                  | "Diagnose the production issue for this well: …"                            |
| Vector Search (RAG)    | Retrieve and ground answers in indexed documents/knowledge                                     | "What does the petroleum knowledge base say about managed pressure drilling?" |
| Genie                  | Answer natural‑language data questions; Genie writes and runs the SQL                          | "What was total production by field last month?"                           |
| SQL Execution          | Run SQL directly against Unity Catalog (read‑only by default)                                  | "Run a read‑only query to preview 10 rows of `prod.sales.orders`"          |

**Example Unity Catalog functions** (specific to the configured functions server; your workspace may differ):

| Function                     | What It Does                                                              |
| ---------------------------- | ------------------------------------------------------------------------ |
| `analyze_wellbore_trajectory`| Directional‑drilling analysis of a wellbore trajectory                   |
| `diagnose_well_production`   | Petroleum‑engineering diagnostics for a well from its production data    |
| `classify_topic`             | Classify text into one of the provided categories                        |
| `extract_entities`           | Extract named entities from unstructured text as JSON                    |
| `summarize_text`             | Summarize text (concise / detailed styles)                               |
| `validate_data`              | Validate a value against an expected format                              |

The exact function and index tools depend on what is registered in your Databricks workspace and change when the workspace's functions or indexes change.

## How the Workflow Operates

The agent guides you through a natural, question‑and‑answer flow. There is no upload step and no session‑wide data cache to manage — every question is answered by calling the appropriate tools against the live Databricks workspace.

### Stage 1: Orientation

**When to use:** You want to see what the agent can do before drilling in.

**Example prompts:**
- "What can you do?"
- "help"

**What you get back:** A capability summary with starter prompts for functions, Vector Search, Genie, and SQL.

### Stage 2: Ask Data Questions with Genie

**When to use:** You have an ad‑hoc data question and don't want to write SQL.

**Example prompts:**
- "What were our top 10 customers by revenue last quarter?"
- "How many active wells reported production yesterday?"
- (Follow‑up) "Now break that down by region."

**What you get back:** Genie's grounded answer, the SQL it ran, and a result table. Follow‑ups continue the same conversation.

### Stage 3: Grounded Retrieval with Vector Search

**When to use:** You have a conceptual or document‑grounded question best answered from indexed knowledge.

**Example prompts:**
- "What does our petroleum knowledge base say about managed pressure drilling?"
- "Find passages about well control in the ingested PDFs."

**What you get back:** An answer grounded in the retrieved passages, with a note about which index was used.

### Stage 4: Run Unity Catalog Functions

**When to use:** You want a specific computation or analysis that a registered UC function performs.

**Example prompts:**
- "Diagnose the production issue for this well: …"
- "Analyze this wellbore trajectory: …"
- "Summarize / classify / extract entities from this text."

**What you get back:** The result of the matching function, relayed faithfully, with a brief interpretation when it helps.

### Stage 5: Run SQL

**When to use:** You have SQL to run, or you want exact, hand‑written queries.

**Example prompts:**
- "Run a read‑only query to preview 10 rows of `prod.sales.orders`."
- "Execute: `SELECT customer_id, SUM(order_total) FROM prod.sales.orders GROUP BY customer_id ORDER BY 2 DESC LIMIT 10`."

**What you get back:** The executed SQL and a Markdown result table. The agent defaults to read‑only and will confirm before running any statement that modifies data.

### Stage 6: Multi-step Workflows

**When to use:** Your question spans more than one capability.

**Example prompts:**
- "Ask Genie for last month's production by field, then summarize the result with the summarize function."
- "Retrieve what the knowledge base says about a symptom, then run a read‑only query to check the related table."

**What you get back:** A consolidated answer where the agent chained capabilities internally (retrieval / Genie / function / SQL) and reports the final result with brief notes about intermediate steps.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary: UC functions, Vector Search (RAG),
         Genie data questions, and SQL execution, with starter prompts.]

You:    What does the petroleum knowledge base say about managed pressure drilling?

Agent:  [Queries the Vector Search knowledge index and answers, grounded in the
         retrieved passages, noting the index used.]

You:    Ask Genie: what was total production by field last month?

Agent:  [Submits the question to Genie, polls until complete, and returns the
         SQL Genie ran plus the result table.]

You:    Diagnose the production issue for well A-12 given this production data: ...

Agent:  [Calls the diagnose_well_production UC function and relays its result.]

You:    Run a read-only query to preview 10 rows of prod.sales.orders.

Agent:  Executed (read-only):
        SELECT * FROM prod.sales.orders LIMIT 10;

        Result:
        [Markdown table of 10 rows]

You:    Thanks.
```

## Key Benefits

| Benefit                              | Description                                                                                                          |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| One agent, four capabilities         | Functions, Vector Search (RAG), Genie, and SQL — all from one chat, routed automatically to the right server.       |
| Natural‑language data answers        | Ask questions in plain English; Genie writes and runs the SQL, or the agent runs the SQL you provide.              |
| Grounded retrieval                   | Vector Search answers are grounded in indexed documents/knowledge, reducing hallucination.                          |
| Domain functions on tap              | Registered Unity Catalog functions (e.g. well diagnostics, text helpers) are callable directly from chat.          |
| Read‑only by default                 | SQL execution defaults to read‑only; data‑modifying statements require explicit confirmation.                       |
| Secure, auto‑refreshing auth         | Connects via a Databricks service principal (OAuth M2M); tokens are minted and refreshed automatically.             |
| Markdown output                      | Descriptions and result tables are returned as Markdown, optimized for chat reading and copy‑paste.                 |

## Tips for Best Results

- **Pick the right capability by intent.** Ad‑hoc data question → Genie; document/concept question → Vector Search; a specific computation → a UC function; exact/precise query → SQL.
- **Make questions concrete.** Resolve vague time windows ("recent") into explicit ranges so Genie and SQL return what you expect.
- **Ground knowledge questions.** For "what does X say about Y", the agent uses Vector Search and cites the retrieved passages — ask it to name the index if you want provenance.
- **Default to read‑only SQL.** Say "read‑only" for exploration; only ask for a write when you truly intend to change data, and confirm the change.
- **Fully qualify table names** as `catalog.schema.table` in SQL.
- **Follow up in the same thread** for Genie so it reuses the conversation instead of starting over.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                | Definition                                                                                                                  |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Databricks‑managed MCP server | A Model Context Protocol endpoint hosted by Databricks that exposes a workspace capability (functions, vector‑search, genie, sql) as tools. |
| Unity Catalog (UC)  | Databricks' centralized governance layer for cataloging, securing, and discovering data and AI assets.                      |
| UC Function         | A function registered in Unity Catalog, exposed by the Functions MCP server as a callable tool.                             |
| Vector Search       | Databricks' vector index/retrieval service; the agent queries indexes to ground answers in relevant text (RAG).            |
| RAG                 | Retrieval‑Augmented Generation — grounding an answer in retrieved passages rather than the model's own knowledge.          |
| Genie               | Databricks' natural‑language data experience; it generates and runs SQL over configured Genie Spaces to answer questions.  |
| DBSQL               | The Databricks SQL execution capability; the agent runs SQL against Unity Catalog through the DBSQL MCP server.            |
| Service principal (M2M OAuth) | A non‑human Databricks identity used with OAuth client credentials to authenticate the agent to the managed servers. |
