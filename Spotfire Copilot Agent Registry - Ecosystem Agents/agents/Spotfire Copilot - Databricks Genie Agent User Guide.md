# Databricks Genie Agent — User Guide

data × databricks × genie × natural-language-q&a × unity-catalog

The Databricks Genie Agent is a thin, conversational wrapper around the **Databricks Genie** MCP server. It lets you ask natural-language questions about your enterprise data inside the Spotfire Copilot Panel and surfaces the grounded answer — including the SQL Genie ran, the result table, and a deep link back to the Genie conversation in Databricks — without ever leaving the chat.

## Table of Contents

- [Introduction](#introduction)
- [What Is Databricks Genie](#what-is-databricks-genie)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Orientation](#stage-1-orientation)
  - [Stage 2: Ask a Data Question](#stage-2-ask-a-data-question)
  - [Stage 3: Follow Up in the Same Conversation](#stage-3-follow-up-in-the-same-conversation)
  - [Stage 4: Interpret Results](#stage-4-interpret-results)
  - [Stage 5: Iteratively Refine an Ambiguous Question](#stage-5-iteratively-refine-an-ambiguous-question)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Limitations](#limitations)
- [Glossary](#glossary)

---

## Introduction

The Databricks Genie Agent is a conversational data analyst available inside the Spotfire Copilot Panel. It does not generate SQL itself, navigate Unity Catalog itself, or execute queries itself. Every answer the agent returns comes from **Databricks Genie** through the `databricks-genie` MCP server. The agent's job is to drive Genie correctly: submit your question, wait for Genie to finish its asynchronous reasoning, present Genie's answer cleanly, and continue the same Genie conversation across follow-up turns.

Because all the underlying functionality is provided by Databricks Genie, the capabilities, accuracy, governance model, and limitations described here are the ones documented by Databricks. The agent inherits them — it does not extend or replace them.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions you type into the Spotfire Copilot Panel, and all answers come from Databricks Genie through the MCP server's tools.

## What Is Databricks Genie

Databricks Genie is Databricks's natural-language data Q&A surface. The administrator (typically a data analyst or domain expert) curates one or more **Genie Spaces** with datasets registered in Unity Catalog, example SQL queries, SQL functions, JOIN relationships, and plain-text instructions. Business users then ask questions in natural language and get back a generated SQL query, a result table, and (optionally) a visualization.

Key Genie concepts the agent surfaces to you:

| Term              | Meaning                                                                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Genie Space**   | A curated scope of tables, metric views, example queries, and instructions that Genie is allowed to reason over. The administrator decides which Spaces exist and what they contain. |
| **Conversation**  | A multi-turn chat thread inside a Genie Space, identified by a `conversation_id`. Each follow-up turn reuses the same id so Genie keeps full context.   |
| **Deep link**     | A URL Genie returns that opens the same conversation in the Databricks UI. The agent always surfaces it when present.                                   |
| **Read-only**     | Genie does not insert, update, or delete data. Generated SQL is always read-only. Retries and concurrency are handled by the SQL warehouse.             |
| **Trusted asset** | A response is marked Trusted by Genie when it was produced from the exact text of an example query or SQL function curated by the Space author.         |

For full background on Genie, see the upstream documentation:
- [What is a Genie Space (Azure Databricks)](https://learn.microsoft.com/en-us/azure/databricks/genie/)
- [Use a Genie Space to explore business data](https://learn.microsoft.com/en-us/azure/databricks/genie/talk-to-genie)
- [Genie Spaces API](https://learn.microsoft.com/en-us/azure/databricks/genie/conversation-api)

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`databricks-genie` MCP server** — the agent's only tools (`genie_ask`, `genie_poll_response`) call this MCP server at runtime. The MCP server is configured with the Databricks workspace and the Genie Spaces it is allowed to address.

In addition, on the Databricks side you need:

- At least one **Genie Space** authored and shared with the identity used by the MCP server.
- That identity must have `SELECT` privileges on every Unity Catalog data object referenced by the Space (Genie enforces per-user Unity Catalog permissions on result rows).
- A pro or serverless **SQL warehouse** the Space is configured to use.

If any component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Databricks Genie Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries Databricks Genie live, which in turn reasons over the curated Genie Space.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Reference         | Examples                                                                  |
| ----------------- | ------------------------------------------------------------------------- |
| Metric / measure  | "revenue", "active users", "order volume", "average response time"        |
| Time window       | "last quarter", "yesterday", "the last 7 days", "Q1 2026"                  |
| Dimension / split | "by product line", "per region", "by customer segment"                     |
| Filter            | "EMEA only", "for premium customers", "where status = 'shipped'"          |
| Comparison        | "vs. the previous quarter", "year over year", "highest", "lowest"         |

If a reference is missing or ambiguous (for example, "recent sales" without a time window), the agent will either ask a short clarifying question or send a best-effort question to Genie and call out the assumption it made.

### What Data Is Available

The data you can ask about is determined entirely by the **Genie Space** the MCP server is configured against:

- A Genie Space is built on **Unity Catalog** objects: managed tables, external tables, foreign tables, views, metric views, and materialized views.
- Genie uses the metadata attached to those objects, plus the Space's **knowledge store** — author-curated table/column descriptions, synonyms, JOIN relationships, example SQL queries, SQL functions, and plain-text instructions.
- Genie works with **structured data only**. It cannot answer questions about PDFs, Word documents, or other unstructured content.
- File uploads (CSV / Excel) into a Genie Space are a Databricks public-preview feature; whether they're available depends on how the Space was configured by the administrator.

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, or external CSVs through the Copilot Panel. Read permissions are governed by Unity Catalog per the identity used by the MCP server (and in some configurations, per-user identity propagation).

## What the Agent Can Do

The agent exposes exactly what Databricks Genie exposes through the MCP server. There are no additional capabilities.

| Capability                   | What It Does (via Genie)                                                                                                                  | Example Request                                                       |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Natural-language data Q&A    | Send a question to Genie. Genie picks the relevant tables/columns, generates SQL, runs it on the configured SQL warehouse, returns a result. | "What were our top 10 customers by revenue last quarter?"             |
| SQL grounding                | Show the SQL Genie ran so you can review or copy it.                                                                                      | "Show me the SQL Genie used."                                          |
| Result tables                | Return small result sets verbatim as a Markdown table.                                                                                    | "How many active users did we have each day in the last 30 days?"     |
| Multi-turn conversation      | Continue the same Genie conversation so follow-ups carry full context (filters, time windows, prior result).                              | "Now break that down by product line."                                 |
| Deep link to Databricks      | Surface the Genie conversation URL so you can open it in the Databricks UI for visualizations or sharing.                                 | (Returned automatically with each answer.)                            |
| Clarification / refinement   | Ask a single clarifying question when the input is ambiguous, or send a best-effort rephrasing and call out the assumption.                | "Rephrase 'recent sales' as a concrete time window before asking."    |

What the agent **does not** do (because Genie does not expose it through this MCP surface):

- Author or modify a Genie Space, its instructions, example queries, SQL functions, or JOIN graph.
- Pick which Genie Space to use — that is decided by the MCP server configuration.
- Write, update, or delete data. Genie is read-only.
- Run SQL outside of a Genie Space. For ad-hoc Unity Catalog metadata exploration and freeform SQL execution, use the **Databricks Agent** instead.
- Answer questions about unstructured documents (PDFs, etc.).
- Generate visualizations directly inside chat. The Genie deep link opens the conversation in the Databricks UI where Genie's auto-generated visualizations are available.

## How the Workflow Operates

The agent guides you through a question-and-answer flow. There is no upload step and no session-wide cache to manage. Every question is answered by calling Genie live; Genie itself runs asynchronously, so the agent always polls until the response is complete before showing it to you.

### Stage 1: Orientation

**When to use:** You want to know what the agent does before drilling in.

**Example prompts:**
- "What can you do?"
- "help"

**What you get back:** A short capability summary listing the kinds of questions Genie answers, with starter prompts.

### Stage 2: Ask a Data Question

**When to use:** You have a concrete business question.

**Example prompts:**
- "What were total sales last month?"
- "Show me daily active users for the last 7 days."
- "Which products had the biggest revenue growth this year?"
- "Top 10 customers by revenue in Q1 2026."

**What you get back:** A grounded answer in plain language, the SQL Genie ran (in a fenced ```sql block), a small result table when applicable, and a deep link to the Genie conversation.

### Stage 3: Follow Up in the Same Conversation

**When to use:** You want to refine the previous answer without re-stating the full context.

**Example prompts:**
- "Now break that down by product line."
- "Same question but for the previous quarter."
- "Show me only the EMEA region."
- "Add a year-over-year comparison."

**What you get back:** A new answer from Genie that builds on the prior turn — same `conversation_id`, same Space, same deep link thread. Filters, time windows, and entities established earlier are preserved.

### Stage 4: Interpret Results

**When to use:** You want help understanding what Genie returned.

**Example prompts:**
- "Explain the SQL Genie just ran."
- "Summarize that result in one sentence."
- "What assumptions did Genie make about the time window?"

**What you get back:** A plain-English explanation grounded in Genie's previous response, without inventing details Genie did not provide.

### Stage 5: Iteratively Refine an Ambiguous Question

**When to use:** The first attempt didn't land — Genie asked a clarifying question, returned an empty result, or answered something slightly different from what you meant.

**Example prompts:**
- "Rephrase 'recent sales' as the last 30 days and ask Genie again."
- "I don't know which catalog — just ask Genie and tell me what it found."
- "Be more specific about which 'top customers' table to use."

**What you get back:** A reformulated question sent to Genie (in the same conversation when continuity matters), with the agent calling out the assumption it made.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  I can answer natural-language questions about your enterprise
         data using Databricks Genie. Genie searches across configured
         Genie Spaces and Unity Catalog, runs SQL on your behalf, and
         returns a grounded answer with a deep link back to the
         Databricks UI. Read-only.
         [...starter prompts...]

You:    What were our top 10 customers by revenue last quarter?

Agent:  Top 10 customers by revenue, Q1 2026:

         ```sql
         SELECT customer_name, SUM(order_total) AS revenue
         FROM prod.sales.orders
         WHERE order_date BETWEEN '2026-01-01' AND '2026-03-31'
         GROUP BY customer_name
         ORDER BY revenue DESC
         LIMIT 10;
         ```

         | customer_name | revenue   |
         | ------------- | --------- |
         | Acme Corp.    | 1,284,500 |
         | ...           | ...       |

         Open in Databricks: <deep link to the Genie conversation>

You:    Now break that down by product line.

Agent:  [Continues the same Genie conversation; returns the same top-10
         customers split by product line, with new SQL and a refreshed
         result table. Same deep link thread.]

You:    What assumptions did Genie make?

Agent:  Genie used `prod.sales.orders.order_date` for the quarter filter
         and treated `customer_name` as the customer identity. Revenue
         is the sum of `order_total` (no tax/refund adjustment was
         applied). [Grounded in Genie's previous SQL.]

You:    Same question but for Q4 2025.

Agent:  [Re-runs in the same Genie conversation with the new time
         window; returns updated SQL and a result table.]
```

## Key Benefits

| Benefit                              | Description                                                                                                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Natural-language data Q&A            | Ask business questions in plain English; Genie generates the SQL, runs it, and returns a grounded result.                                                     |
| Curated, governed knowledge          | Answers are scoped to a Genie Space the administrator has curated with descriptions, instructions, example SQL, and JOIN relationships.                       |
| Unity Catalog governance             | Row filters, column masks, and per-user `SELECT` privileges are enforced by Unity Catalog automatically — users only see data they are authorized to access. |
| Read-only by design                  | Generated SQL is always read-only. Genie cannot insert, update, or delete data.                                                                              |
| Multi-turn continuity                | Follow-ups stay in the same Genie conversation, so refinements like "now by region" or "same for last quarter" Just Work.                                    |
| Deep link back to Databricks         | Every answer includes a link to open the same conversation in the Databricks UI for visualizations, sharing, or audit.                                       |
| Grounded SQL surfaced in chat        | The SQL Genie ran is shown in the response, so you can review, copy, or paste it elsewhere.                                                                  |
| Works independently of visualizations | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.                                                |

## Tips for Best Results

- **Be specific about the time window.** "Last 30 days" or "Q1 2026" beats "recent" — Genie will pick a reasonable default if you don't, but it may not be the one you wanted.
- **Use the same conversation for follow-ups.** Phrases like "now…", "same but…", "and split by…" let Genie keep the prior context. Starting fresh each time discards entities, filters, and prior results.
- **Mention the metric, not the column.** Genie maps "revenue", "active users", "order volume" to the right columns based on the Space's knowledge store. Use the language your business users use.
- **Trust the SQL block.** When the agent shows the SQL Genie ran, you can copy it for use in a notebook or dashboard. Read-only by definition.
- **Open the deep link for visuals.** The Databricks UI auto-generates charts and lets you save/share the conversation. The agent does not render visuals inline.
- **If Genie is uncertain, it will ask.** Genie can ask follow-up questions when it can't generate an answer. Treat those as part of the workflow — answer them and let Genie continue.
- **Empty results often mean permissions.** If Genie returns nothing, check that the identity used by the MCP server (or your propagated identity) has `SELECT` on the underlying tables, and that any row filters / column masks aren't excluding everything.
- **Consider Inspect for high-stakes queries.** When the Genie Space is configured with **Inspect** (Databricks public preview), Genie reviews and improves its own generated SQL for complex filters, date logic, and joins. Ask the Space administrator whether Inspect is enabled.
- **Pick the right agent.** Use the **Databricks Genie Agent** for curated, NL-first business questions inside a Genie Space. Use the **Databricks Agent** for ad-hoc Unity Catalog exploration, lineage, and direct SQL execution outside a Space.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Limitations

These limits come from Databricks Genie itself. The agent inherits them.

- **Scope is fixed by the Genie Space.** The agent cannot reason over tables that are not registered to the Space. To extend the scope, the Space author must add the data and (ideally) curate metadata for it.
- **Structured data only.** Unstructured content (PDFs, Word docs, free-text files) is out of scope. For unstructured Q&A, Databricks offers **Chat in Genie**, which is a separate surface and not exposed by this agent.
- **Read-only.** Genie cannot mutate data. The agent will refuse and suggest the appropriate Databricks workflow.
- **Token / context limits.** Genie maintains conversation history, but very long conversations may have their oldest turns truncated. If continuity matters, summarize and re-anchor.
- **Language support is best in English.** Genie supports prompts in other languages (e.g. Portuguese, French), but the underlying agent framework wraps prompts in English and responses may sometimes appear in English.
- **Latency varies.** Genie is asynchronous; complex questions, large Spaces, or busy SQL warehouses can take several seconds (or longer) before the answer is ready. The agent polls until completion rather than reporting partial state.
- **Concurrency and warehouse scaling are external.** Performance depends on the size and type of SQL warehouse the Space is configured against.

## Glossary

| Term                         | Definition                                                                                                                                                          |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Databricks Genie             | The natural-language data Q&A surface in Databricks. Generates SQL, runs it on a SQL warehouse, returns a grounded answer.                                          |
| Genie Space                  | A curated scope of tables, metric views, example queries, SQL functions, JOIN relationships, and instructions that Genie is allowed to reason over.                  |
| Knowledge store              | The author-curated metadata layer inside a Genie Space (descriptions, synonyms, JOIN graph, example SQL, SQL functions, instructions).                              |
| Unity Catalog (UC)           | Databricks's centralized governance layer for cataloging, securing, and discovering data assets. Genie data access is governed by Unity Catalog.                    |
| SQL warehouse                | The compute endpoint Genie uses to run generated SQL. Configured per-Space by the author.                                                                           |
| Conversation                 | A multi-turn thread inside a Genie Space, identified by `conversation_id`. The agent reuses this id across follow-up turns to preserve context.                     |
| Deep link                    | A URL Genie returns that opens the conversation in the Databricks UI (with auto-generated visualizations and sharing).                                              |
| Trusted asset / Trusted response | A Genie response marked Trusted because it was produced from the exact text of an example query or SQL function the Space author curated.                       |
| Inspect (Public Preview)     | A Genie feature that reviews and improves Genie's own SQL for complex filters, joins, and date logic before returning the final answer.                              |
| Compound AI system           | The architecture Genie uses internally — multiple interacting components rather than a single LLM call. Operationally invisible to end users.                        |
| MCP Server                   | The Model Context Protocol server (`databricks-genie`) that exposes the `genie_ask` and `genie_poll_response` tools the agent calls at runtime.                     |
