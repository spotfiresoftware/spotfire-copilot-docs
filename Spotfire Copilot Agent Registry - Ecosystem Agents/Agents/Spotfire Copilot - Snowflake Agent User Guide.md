# Snowflake Agent — User Guide

data × snowflake × cortex-analyst × cortex-search × natural-language-q&a × semantic-view

The Snowflake Agent is a conversational wrapper around the **Snowflake** MCP server. It lets you ask natural-language questions about your Snowflake account inside the Spotfire Copilot Panel and surfaces grounded answers — the SQL Cortex Analyst ran, the result rows, ranked support-ticket search hits, or a `Send_Email` confirmation — without ever leaving the chat.

## Table of Contents

- [Introduction](#introduction)
- [What Is Snowflake Cortex](#what-is-snowflake-cortex)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Orientation](#stage-1-orientation)
  - [Stage 2: Ask a Financial / Risk / Customer Question (Cortex Analyst)](#stage-2-ask-a-financial--risk--customer-question-cortex-analyst)
  - [Stage 3: Search the Support-Ticket Corpus (Cortex Search)](#stage-3-search-the-support-ticket-corpus-cortex-search)
  - [Stage 4: Explore Schema / Metadata (Read-Only SQL)](#stage-4-explore-schema--metadata-read-only-sql)
  - [Stage 5: Send an Email](#stage-5-send-an-email)
  - [Stage 6: Interpret Results](#stage-6-interpret-results)
  - [Stage 7: Iteratively Refine an Ambiguous Question](#stage-7-iteratively-refine-an-ambiguous-question)
- [Typical End-to-End Session](#typical-end-to-end-session)

---

## Introduction

The Snowflake Agent is a conversational data analyst available inside the Spotfire Copilot Panel. It does not generate SQL itself for analytical questions, navigate the Snowflake account by guessing, or fabricate result rows. Every answer the agent returns comes from **Snowflake** through the `snowflake` MCP server's four tools:

- **Cortex Analyst** over a curated finance & risk semantic view, for structured / quantitative questions.
- **Cortex Search** over an unstructured support-ticket corpus, for "what are users complaining about" / "find tickets mentioning X" questions.
- **Read-only SQL** (`SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN`) for schema and metadata exploration not covered by the semantic view.
- **`Send_Email`** stored procedure for outbound mail, executed only when you explicitly ask.

The agent's job is to route each question to the right tool, run it with the minimum necessary input, and present the grounded answer cleanly. Because all underlying functionality is provided by Snowflake, the capabilities, accuracy, governance model, and limitations described here are the ones documented by Snowflake. The agent inherits them — it does not extend or replace them.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions you type into the Spotfire Copilot Panel, and all answers come from Snowflake through the MCP server's tools.

## What Is Snowflake Cortex

Snowflake Cortex is Snowflake's family of native AI features. Two of them back this agent:

| Surface             | What It Is                                                                                                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cortex Analyst**  | Snowflake's natural-language data Q&A surface backed by a **semantic view**. Translates a question into SQL against a curated set of tables and returns a grounded answer plus the SQL it ran. Synchronous, read-only. |
| **Cortex Search**   | Keyword + vector search over an indexed corpus of unstructured text (here: support tickets). Returns ranked passages with relevance scores.                          |

Key concepts the agent surfaces to you:

| Term                | Meaning                                                                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Semantic view**   | A curated layer that maps business concepts (customer, transaction, risk score, campaign response) onto the underlying Snowflake tables/columns. Cortex Analyst reasons against it; you do not query the view directly with SQL. |
| **Search service**  | A Cortex Search index built over a column of unstructured text. The agent queries it with natural-language phrases and gets ranked passages back.                     |
| **Warehouse / role / database.schema.table** | Snowflake's execution context. The MCP server is already configured with a warehouse and role; the agent does not switch them.                                  |
| **Verified email**  | The email address Snowflake has confirmed for the calling user. `Send_Email` defaults the recipient to this address when none is supplied.                            |
| **Read-only**       | The agent never issues writes. SQL is restricted to `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN`, and `Send_Email` is the only side-effecting tool — only fired on explicit request. |

For background on Cortex Analyst and Cortex Search, see the upstream documentation:
- [Cortex Analyst overview](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- [Semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Cortex Search overview](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
- [Snowflake email notifications (`Send_Email`)](https://docs.snowflake.com/en/user-guide/email-stored-procedures)

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../Agent%20Server%20Deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../Agent%20Server%20Deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`snowflake` MCP server** — the agent's only tools (`Finance_and_Risk_Assessment_Semantic_View`, `Support_Tickets_Cortex_Search`, `SQL_Execution_Tool`, `Send_Email`) call this MCP server at runtime. The MCP server is configured with the Snowflake account, warehouse, role, semantic view, search service, and email integration it is allowed to address.

In addition, on the Snowflake side you need:

- A **semantic view** (default `DASH_MCP_DB.DATA.FINANCIAL_SERVICES_ANALYTICS`) curated by an analyst, registering the tables, dimensions, metrics, synonyms, and example queries that Cortex Analyst will reason over.
- A **Cortex Search service** (default `DASH_MCP_DB.DATA.SUPPORT_TICKETS`) built over the support-ticket corpus.
- The MCP server's identity must have `USAGE` on the warehouse, `USAGE` on the database/schema, `SELECT` on the underlying tables, `USAGE` on the semantic view and search service, and `USAGE` on the `Send_Email` stored procedure.
- A notification integration that backs `Send_Email`, plus a verified email address for the caller when relying on the recipient default.

If any component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Snowflake Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries Snowflake live.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Reference         | Examples                                                                  |
| ----------------- | ------------------------------------------------------------------------- |
| Metric / measure  | "revenue", "transaction amount", "risk score", "response rate", "decline rate" |
| Time window       | "last quarter", "yesterday", "the last 30 days", "Q1 2026", "this year"    |
| Dimension / split | "by region", "per customer segment", "by campaign", "by month"             |
| Filter            | "high-risk customers only", "where status = 'declined'", "EMEA only"      |
| Comparison        | "vs. the previous quarter", "year over year", "highest", "top 10"          |
| Ticket topic      | "failed wire transfers", "mobile app login", "international transfer fees" |
| Schema target     | A fully qualified `database.schema.table` for SQL inspection               |
| Email intent      | "email me…", "send to alice@example.com with subject …"                    |

If a reference is missing or ambiguous (for example, "recent transactions" without a time window), the agent will either ask a short clarifying question or send a best-effort question to the right tool and call out the assumption it made.

### What Data Is Available

The data you can ask about is determined entirely by what the MCP server is configured against:

- **Structured finance & risk data** lives behind the **semantic view** (default `DASH_MCP_DB.DATA.FINANCIAL_SERVICES_ANALYTICS`): customers, transactions, marketing campaigns, support interactions, risk assessments. Cortex Analyst chooses the tables/columns and writes the SQL — you do not need to know the schema.
- **Unstructured support-ticket text** lives behind the **Cortex Search service** (default `DASH_MCP_DB.DATA.SUPPORT_TICKETS`). Queries are natural-language phrases and matches are ranked by relevance.
- **Schema and metadata** for anything visible to the configured role is reachable via the read-only SQL tool (`SHOW`, `DESCRIBE`, bounded `SELECT`).
- **Email delivery** is provided by Snowflake's `Send_Email` stored procedure, using whatever notification integration the account has configured.

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, external CSVs, PDFs, or other unstructured documents through the Copilot Panel. Read permissions are governed by Snowflake's role/grant model per the identity used by the MCP server.

## What the Agent Can Do

The agent exposes exactly what the Snowflake MCP server exposes. There are no additional capabilities.

| Capability                       | What It Does (via Snowflake)                                                                                                                                       | Example Request                                                                |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Natural-language data Q&A        | Send a question to Cortex Analyst over the finance & risk semantic view. Cortex picks the relevant tables/columns, generates SQL, runs it, and returns the answer. | "Top 10 customers by total transaction value over the last 12 months."          |
| SQL grounding                    | Show the SQL Cortex Analyst ran so you can review, audit, or copy it.                                                                                              | "Show me the SQL Cortex Analyst used."                                          |
| Result tables                    | Return small result sets verbatim as a Markdown table; summarize larger sets with row counts.                                                                      | "Total transaction amount by quarter for the past 2 years."                     |
| Support-ticket semantic search   | Query the Cortex Search service over the support-ticket corpus and return the top hits with relevance scores.                                                      | "Find tickets mentioning failed wire transfers."                                |
| Read-only schema / metadata SQL  | Run `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN` for objects not covered by the semantic view.                                                                       | "Describe `FACT_TRANSACTIONS`." / "Row counts per table in `DASH_MCP_DB.DATA`." |
| Send an email                    | Call the `Send_Email` stored procedure. Markdown bodies are converted to HTML; recipient defaults to the caller's verified email; subject defaults to "Snowflake CoWork". | "Email the top-10 churn-risk list to alice@example.com with subject 'Q2 churn watchlist'." |
| Clarification / refinement       | Ask a single clarifying question when the input is ambiguous, or send a best-effort rephrasing and call out the assumption.                                        | "Rephrase 'recent declines' as a concrete time window before asking Cortex."    |

What the agent **does not** do (because the MCP server does not expose it, or because the agent is intentionally restricted):

- Author or modify a semantic view, a Cortex Search service, or their underlying tables.
- Pick which semantic view, search service, warehouse, or role to use — those are decided by the MCP server configuration.
- Write, update, or delete data. SQL is strictly read-only and the following are refused even on explicit request: `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `CREATE`, `REPLACE`, `DROP`, `ALTER`, `TRUNCATE`, `GRANT`, `REVOKE`, `CALL`, `COPY`, `PUT`, `GET`, `USE`, `SET`, multi-statement scripts.
- Send email proactively. `Send_Email` only fires when you explicitly ask.
- Fabricate SQL. The only SQL surfaced is SQL Cortex Analyst returned in its `sql` field, or SQL the agent composed for `SQL_Execution_Tool` and actually executed.
- Answer questions about PDFs, Word docs, or other unstructured content outside the configured Cortex Search service.
- Generate visualizations directly inside chat. Result tables are rendered as Markdown.

## How the Workflow Operates

The agent guides you through a question-and-answer flow. There is no upload step and no session-wide cache to manage. Every question is answered by calling Snowflake live; the right tool is picked by the **shape** of the question.

### Stage 1: Orientation

**When to use:** You want to know what the agent does before drilling in.

**Example prompts:**
- "What can you do?"
- "help"

**What you get back:** A short capability summary listing the kinds of questions each tool answers, with starter prompts for Cortex Analyst, Cortex Search, read-only SQL, and `Send_Email`.

### Stage 2: Ask a Financial / Risk / Customer Question (Cortex Analyst)

**When to use:** Your question is structured or quantitative — "how many", "top N", "trend over time", "broken down by", "rate of". These map to the finance & risk semantic view.

**Example prompts:**
- "Top 10 customers by total transaction value over the last 12 months."
- "Total transaction amount by quarter for the past 2 years."
- "How many high-risk customers do we have, broken down by region?"
- "Average risk score by customer segment."
- "Which marketing campaigns had the highest response rate this year?"
- "Decline rate trend by month over the past 6 months."
- "Customers with more than 5 support tickets in the last 90 days."

**What you get back:** A grounded answer in plain language, the SQL Cortex Analyst ran (in a fenced ```sql block), and a small result table when applicable. If Cortex Analyst returned a clarification block instead of an answer, the agent surfaces it verbatim and asks you to refine.

### Stage 3: Search the Support-Ticket Corpus (Cortex Search)

**When to use:** Your question is about unstructured ticket text — themes, complaints, similar tickets, mentions of a topic.

**Example prompts:**
- "Find tickets mentioning failed wire transfers."
- "Top complaints about the mobile app in the last 30 days."
- "Show tickets similar to 'login fails after password reset'."
- "Any tickets about international transfer fees?"

**What you get back:** The top 3–5 hits with relevance scores and enough of each passage that you can judge relevance.

### Stage 4: Explore Schema / Metadata (Read-Only SQL)

**When to use:** You need account, database, schema, or table metadata that the semantic view does not model — table lists, column definitions, row counts, the data range present in a fact table.

**Example prompts:**
- "What tables live in `DASH_MCP_DB.DATA`?"
- "Describe `FACT_TRANSACTIONS`."
- "Min and max `transaction_date` in `FACT_TRANSACTIONS`."
- "Row counts per table in `DASH_MCP_DB.DATA`."
- "Show the columns on `FINANCIAL_SERVICES_ANALYTICS`."

**What you get back:** The SQL the agent ran (always read-only) and the result table. Writes are refused with a short explanation pointing you at Snowsight or a privileged workflow.

### Stage 5: Send an Email

**When to use:** You explicitly want to email a result. The agent will never volunteer this.

**Example prompts:**
- "Email me a summary of the previous answer."
- "Send the top-10 churn-risk list to alice@example.com with subject 'Q2 churn watchlist'."
- "Email the support-ticket trends report to bob@example.com."

**What you get back:** A one-line confirmation: who it went to, what the subject was, and the procedure's return / status. If you omit the recipient, the procedure uses your verified Snowflake email; if you omit the subject, it defaults to "Snowflake CoWork". Markdown bodies are converted to HTML before sending.

### Stage 6: Interpret Results

**When to use:** You want help understanding what a tool returned.

**Example prompts:**
- "Explain the SQL Cortex Analyst just ran."
- "Summarize that result in one sentence."
- "What assumptions did Cortex make about the time window?"

**What you get back:** A plain-English explanation grounded in the previous tool response, without inventing details the tool did not provide.

### Stage 7: Iteratively Refine an Ambiguous Question

**When to use:** The first attempt didn't land — Cortex Analyst returned a clarification, a search returned nothing relevant, or a query came back empty.

**Example prompts:**
- "Rephrase 'recent declines' as the last 30 days and ask Cortex again."
- "First show me which quarters have data in `FACT_TRANSACTIONS`, then re-run the question against a populated window."
- "Search for 'wire transfer failure' instead of 'failed transfer'."

**What you get back:** A reformulated question or query, with the agent calling out the assumption it made.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  I can answer questions about your Snowflake account using the
         Snowflake MCP server: Cortex Analyst over a finance and risk
         semantic view, Cortex Search over an unstructured support-ticket
         corpus, read-only SQL for schema and metadata, and a Send_Email
         stored procedure when you explicitly ask for one.
         [...starter prompts...]

You:    Top 10 customers by total transaction value over the last 12 months.

Agent:  Top 10 customers by total transaction value, last 12 months:

         ```sql
         SELECT customer_name, SUM(transaction_amount) AS total_value
         FROM DASH_MCP_DB.DATA.FINANCIAL_SERVICES_ANALYTICS
         WHERE transaction_date BETWEEN '2025-06-08' AND '2026-06-08'
         GROUP BY customer_name
         ORDER BY total_value DESC
         LIMIT 10;
         ```

         | customer_name | total_value |
         | ------------- | ----------- |
         | Acme Corp.    | 1,284,500   |
         | ...           | ...         |

You:    Anything in the support tickets about Acme Corp. recently?

Agent:  Top hits from the support-ticket corpus:

         1. (score 0.87) "Acme Corp. — wire transfer to vendor failed
            twice this week..."
         2. (score 0.82) "Acme — mobile app login fails after password
            reset..."
         3. ...

You:    Min and max transaction_date in FACT_TRANSACTIONS.

Agent:  ```sql
         SELECT MIN(transaction_date) AS min_date,
                MAX(transaction_date) AS max_date
         FROM DASH_MCP_DB.DATA.FACT_TRANSACTIONS;
         ```

         | min_date   | max_date   |
         | ---------- | ---------- |
         | 2023-01-01 | 2025-12-31 |

You:    Email a summary of the top-10 customers to alice@example.com
         with subject "Q2 customer watchlist".

Agent:  Sent: recipient alice@example.com, subject "Q2 customer
         watchlist". Procedure returned: ok (message id …).
```

## Key Benefits

| Benefit                              | Description                                                                                                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Natural-language data Q&A            | Ask business questions in plain English; Cortex Analyst generates the SQL, runs it, and returns a grounded result.                                            |
| Curated, governed semantic view      | Answers are scoped to a semantic view an analyst has curated with dimensions, metrics, synonyms, and example queries.                                          |
| Semantic search over tickets         | Cortex Search lets you ask "what are users complaining about" instead of writing keyword SQL against a free-text column.                                       |
| Snowflake governance                 | Object-level grants and role-based access are enforced by Snowflake automatically — users only see data the MCP server's role is authorized to access.        |
| Read-only by design                  | SQL is restricted to `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN`; writes are refused even on explicit request.                                                  |
| Gated email                          | `Send_Email` only fires when you explicitly ask, with safe defaults (caller's verified email, "Snowflake CoWork" subject) and Markdown → HTML translation.    |
| Grounded SQL surfaced in chat        | The SQL Cortex Analyst ran is shown in the response, so you can review, copy, or paste it elsewhere.                                                          |
| Single conversational surface        | One agent covers structured analytics, unstructured search, schema inspection, and outbound email — you don't have to remember which tool to ask first.        |
| Works independently of visualizations | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.                                                |

## Tips for Best Results

- **Be specific about the time window.** "Last 30 days" or "Q1 2026" beats "recent" — Cortex Analyst will pick a reasonable default if you don't, but it may not be the one you wanted.
- **If a quarter / year query comes back empty, ask what data exists first.** Run `Min and max transaction_date in FACT_TRANSACTIONS` (or the relevant fact table) and then re-run the question against a populated window. The agent will not invent rows to fill the gap.
- **Use Cortex Analyst over raw SQL whenever possible.** The semantic view knows the business definitions (revenue, risk score, decline rate, response rate) and writes better SQL than ad-hoc prompts. Drop to `SQL_Execution_Tool` for schema / metadata only.
- **Mention the metric, not the column.** Cortex Analyst maps "revenue", "transaction value", "risk score" to the right columns via the semantic view's synonyms. Use the language your business users use.
- **Trust the SQL block.** The SQL the agent shows is the SQL that actually ran — copy it into a worksheet or notebook for further work. Read-only by definition.
- **Search with the user's phrasing.** Cortex Search is a semantic index, but exact-phrase variants ("wire transfer failure" vs. "failed transfer") can still surface different ranked passages.
- **Empty results often mean permissions.** If Cortex Analyst or a SQL query returns nothing, check that the MCP server's role has `SELECT` on the underlying tables and `USAGE` on the semantic view / search service.
- **Don't expect the agent to send email unprompted.** Summaries, follow-ups, and "did you mean…" prompts will never become emails. Ask for one explicitly when you want it.
- **`Send_Email` defaults are deliberate.** Omitting the recipient routes the message to your verified email (useful for "email me a summary"); omitting the subject uses "Snowflake CoWork". The agent will tell you which defaults it used.
- **Pick the right agent.** Use the **Snowflake Agent** for Snowflake-resident finance/risk analytics, support-ticket semantic search, and Snowflake schema/metadata. Use the **Databricks Genie Agent** for curated NL Q&A inside a Genie Space, or the **Databricks Agent** for Unity Catalog exploration, lineage, and ad-hoc Databricks SQL.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Limitations

These limits come from Snowflake itself, from the MCP server's configuration, and from the agent's intentional safety rules.

- **Scope is fixed by the semantic view and search service.** The agent cannot reason over tables that are not registered to the configured semantic view, or over corpora outside the configured Cortex Search service. To extend the scope, an analyst must update the view or stand up a new search service.
- **One semantic view / one search service per deployment.** The MCP server points at a single semantic view and a single search service. Switching domains requires reconfiguring the MCP server.
- **Read-only.** SQL writes and session-state changes are refused. The agent will suggest Snowsight or a privileged workflow instead.
- **Cortex Analyst clarifications must be answered.** When Cortex Analyst returns a `suggestions` / clarification block instead of an answer, the agent surfaces it verbatim — it will not invent a "best guess" answer.
- **No fabricated rows or SQL.** If a tool returned no rows, the agent says so. It will not synthesize values to make a result look complete.
- **No unstructured documents outside the configured search service.** PDFs, Word docs, and other free-text files are out of scope unless they are part of the indexed corpus.
- **Email is one-shot and gated.** `Send_Email` is the only side-effecting tool, only fires on explicit request, and is constrained by Snowflake's notification integration (recipient allow-lists, attachment rules, rate limits).
- **Latency varies.** Cortex Analyst is synchronous but complex questions over large semantic views can take several seconds; Cortex Search latency depends on the index size; SQL latency depends on the warehouse.
- **Concurrency and warehouse scaling are external.** Performance depends on the size and state of the warehouse the MCP server is configured against.

## Glossary

| Term                         | Definition                                                                                                                                                          |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Snowflake Cortex             | Snowflake's family of native AI features. This agent uses Cortex Analyst and Cortex Search.                                                                          |
| Cortex Analyst               | Snowflake's natural-language data Q&A surface backed by a semantic view. Generates SQL, runs it on the configured warehouse, returns a grounded answer.              |
| Cortex Search                | Keyword + vector search over an indexed corpus of unstructured text. Returns ranked passages with relevance scores.                                                  |
| Semantic view                | A curated layer that maps business concepts (customer, transaction, risk score, campaign response) onto the underlying tables/columns. Cortex Analyst reasons against it. |
| Search service               | A Cortex Search index built over a column of unstructured text (here: support tickets).                                                                              |
| Warehouse                    | The compute endpoint Snowflake uses to run SQL. Configured per MCP server.                                                                                           |
| Role                         | Snowflake's unit of authorization. Object-level grants are evaluated against the MCP server's role.                                                                  |
| Verified email               | The email address Snowflake has confirmed for the calling user. `Send_Email` defaults the recipient to this address when none is supplied.                            |
| `Send_Email`                 | Stored procedure that emails a recipient via Snowflake's notification integration. Side-effecting; only fired on explicit request.                                   |
| Read-only SQL                | `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN` only. All other DDL/DML and session-state changes are refused.                                                            |
| MCP Server                   | The Model Context Protocol server (`snowflake`) that exposes the `Finance_and_Risk_Assessment_Semantic_View`, `Support_Tickets_Cortex_Search`, `SQL_Execution_Tool`, and `Send_Email` tools the agent calls at runtime. |
