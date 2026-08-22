# Snowflake Agent — User Guide

data × snowflake × cortex-analyst × well-surveys × natural-language-q&a × semantic-view

The Snowflake Agent is a conversational wrapper around the **Snowflake** MCP server. It lets you ask natural-language questions about oil & gas well directional surveys in your Snowflake account inside the Spotfire Copilot Panel and surfaces grounded answers — the SQL Cortex Analyst ran and the result rows — without ever leaving the chat.

## Table of Contents

- [Introduction](#introduction)
- [What Is Snowflake Cortex](#what-is-snowflake-cortex)
- [Prerequisites](#prerequisites)
- [Provisioning the External Snowflake MCP Server](#provisioning-the-external-snowflake-mcp-server)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Orientation](#stage-1-orientation)
  - [Stage 2: Ask a Well-Survey Question (Cortex Analyst)](#stage-2-ask-a-well-survey-question-cortex-analyst)
  - [Stage 3: Explore Schema / Metadata (Read-Only SQL)](#stage-3-explore-schema--metadata-read-only-sql)
  - [Stage 4: Interpret Results](#stage-4-interpret-results)
  - [Stage 5: Iteratively Refine an Ambiguous Question](#stage-5-iteratively-refine-an-ambiguous-question)
- [Typical End-to-End Session](#typical-end-to-end-session)

---

## Introduction

The Snowflake Agent is a conversational data analyst available inside the Spotfire Copilot Panel. It does not generate SQL itself for analytical questions, navigate the Snowflake account by guessing, or fabricate result rows. Every answer the agent returns comes from **Snowflake** through the `snowflake` MCP server's two tools:

- **Cortex Analyst** over a curated directional-survey semantic view (`VOLVE_SURVEYS`), for structured / quantitative questions about oil & gas wellbore surveys.
- **Read-only SQL** (`SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN`) for schema and metadata exploration not covered by the semantic view.

The agent's job is to route each question to the right tool, run it with the minimum necessary input, and present the grounded answer cleanly. Because all underlying functionality is provided by Snowflake, the capabilities, accuracy, governance model, and limitations described here are the ones documented by Snowflake. The agent inherits them — it does not extend or replace them.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions you type into the Spotfire Copilot Panel, and all answers come from Snowflake through the MCP server's tools.

## What Is Snowflake Cortex

Snowflake Cortex is Snowflake's family of native AI features. One of them backs this agent:

| Surface             | What It Is                                                                                                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cortex Analyst**  | Snowflake's natural-language data Q&A surface backed by a **semantic view**. Translates a question into SQL against a curated set of tables and returns a grounded answer plus the SQL it ran. Synchronous, read-only. |

Key concepts the agent surfaces to you:

| Term                | Meaning                                                                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Semantic view**   | A curated layer that maps survey concepts (well identifier, measured depth, inclination, azimuth, dogleg severity) onto the underlying Snowflake tables/columns. Cortex Analyst reasons against it; you do not query the view directly with SQL. |
| **Directional survey** | A set of measurement points describing a wellbore's geometric path through the subsurface — measured depth, inclination, azimuth, true vertical depth, and coordinates. The Volve dataset covers wells from the Volve field. |
| **Warehouse / role / database.schema.table** | Snowflake's execution context. The MCP server is already configured with a warehouse and role; the agent does not switch them.                                  |
| **Read-only**       | The agent never issues writes. SQL is restricted to `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN`; there are no side-effecting tools. |

For background on Cortex Analyst and semantic views, see the upstream documentation:
- [Cortex Analyst overview](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- [Semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/overview)

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph DeepAgents server** — the agent ships as part of the LangGraph DeepAgents server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`snowflake` MCP server** — the agent's only tools (`VOLVE_SURVEYS`, `SQL_Execution_Tool`) call this MCP server at runtime. The MCP server is configured with the Snowflake account, warehouse, role, and semantic view it is allowed to address.

In addition, on the Snowflake side you need:

- A **semantic view** (default `DASH_MCP_DB.DATA.VOLVE_SURVEYS`, over the base table `VOLVE_COMBINED_DIRECTIONAL_SURVEYS`) curated by an analyst, registering the tables, dimensions, metrics, synonyms, and example queries that Cortex Analyst will reason over.
- The MCP server's identity must have `USAGE` on the warehouse, `USAGE` on the database/schema, `SELECT` on the underlying tables, and `USAGE` on the semantic view.

If any component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail with a tool-related error.

## Provisioning the External Snowflake MCP Server

Unlike the MCP servers that Spotfire publishes (OSDU, Databricks, Data Virtualization, and others), the `snowflake` MCP server is **external** — a [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp) that you provision **inside your own Snowflake account**. There is no container or Helm chart to deploy from this documentation set; you create the server object in Snowflake and point the agent at its URL. Snowflake's own documentation is the source of truth for the full procedure, RBAC model, OAuth setup, network policies, and limitations — this section covers only what is specific to this agent.

### What this agent expects

The Snowflake Agent loads exactly **two tools** from the MCP server; provision the server so it exposes both, named as follows:

| Tool name (as the agent sees it) | Snowflake tool type    | Backs                                                                 |
| -------------------------------- | ---------------------- | --------------------------------------------------------------------- |
| `VOLVE_SURVEYS`                  | `CORTEX_ANALYST_MESSAGE` | The directional-survey semantic view (default `DASH_MCP_DB.DATA.VOLVE_SURVEYS`). |
| `SQL_Execution_Tool`             | `SYSTEM_EXECUTE_SQL`     | Read-only SQL (`SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN`) on the configured database. |

### Create the MCP server

Run this in your Snowflake account (adjust the database, schema, semantic view, and warehouse to your environment). See Snowflake's [Create an MCP Server object](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp#create-an-mcp-server-object) for the full reference.

```yaml
CREATE OR REPLACE MCP SERVER copilot_mcp_server
  FROM SPECIFICATION $$
    tools:
      - name: "VOLVE_SURVEYS"
        title: "Volve Directional Surveys"
        type: "CORTEX_ANALYST_MESSAGE"
        identifier: "DASH_MCP_DB.DATA.VOLVE_SURVEYS"
        description: "Cortex Analyst over the Volve well directional-survey semantic view."
      - name: "SQL_Execution_Tool"
        title: "SQL Execution Tool"
        type: "SYSTEM_EXECUTE_SQL"
        description: "Executes read-only SQL against the connected Snowflake database."
        config:
          read_only: true
          warehouse: "<your_warehouse>"
  $$;
```

### Grant access

The role the MCP server runs under needs, at minimum: `USAGE` on the MCP server, `SELECT` on the semantic view (required to invoke the Cortex Analyst tool), `SELECT` on the underlying tables, and `USAGE` on the warehouse and the database/schema. See Snowflake's [Access control](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp#access-control) table for the exact privilege list.

### Get the server URL

The MCP server URL follows this format:

```
https://<account_url>/api/v2/databases/<database>/schemas/<schema>/mcp-servers/<name>
```

For the example above that is `https://<account_url>/api/v2/databases/DASH_MCP_DB/schemas/DATA/mcp-servers/copilot_mcp_server`. Some clients require **hyphens instead of underscores** in the account portion of the host — see Snowflake's [MCP server security recommendations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp#mcp-server-security-recommendations).

### Point the agent at it

Set these on the LangGraph DeepAgents server (see the deployment guides for where env values are supplied). Snowflake recommends **OAuth over hardcoded tokens**; use a Programmatic Access Token (PAT) with a least-privileged role only where a static bearer token is required.

| Setting                          | Value                                                                 |
| -------------------------------- | --------------------------------------------------------------------- |
| `SNOWFLAKE_MCP_SERVER_URL`       | The MCP server URL above.                                             |
| `SNOWFLAKE_MCP_SERVER_TRANSPORT` | `streamable-http`.                                                    |
| `SNOWFLAKE_MCP_BEARER_TOKEN`     | OAuth access token or PAT for the MCP server's role (keep it in a secret store, not in committed files). |

Once the server is reachable and the token is valid, the agent will discover `VOLVE_SURVEYS` and `SQL_Execution_Tool` at startup and appear in the Copilot Panel.

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
| Metric / measure  | "inclination", "azimuth", "measured depth (MD)", "true vertical depth (TVD)", "dogleg severity" |
| Dimension / split | "per well", "by well identifier", "by data source"                        |
| Filter            | "well F-11 only", "surveys below 2000 m MD"                               |
| Comparison        | "deepest well", "highest inclination", "top 10 survey points"             |
| Schema target     | A fully qualified `database.schema.table` for SQL inspection               |

If a reference is missing or ambiguous (for example, "the deepest survey" without a metric), the agent will either ask a short clarifying question or send a best-effort question to the right tool and call out the assumption it made.

### What Data Is Available

The data you can ask about is determined entirely by what the MCP server is configured against:

- **Structured directional-survey data** lives behind the **semantic view** (default `DASH_MCP_DB.DATA.VOLVE_SURVEYS`, base table `VOLVE_COMBINED_DIRECTIONAL_SURVEYS`): per-well survey points with measured depth, inclination, azimuth, TVD/TVDSS, dogleg severity, displacement, and coordinates. Cortex Analyst chooses the tables/columns and writes the SQL — you do not need to know the schema.
- **Schema and metadata** for anything visible to the configured role is reachable via the read-only SQL tool (`SHOW`, `DESCRIBE`, bounded `SELECT`).

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, external CSVs, PDFs, or other unstructured documents through the Copilot Panel. Read permissions are governed by Snowflake's role/grant model per the identity used by the MCP server.

## What the Agent Can Do

The agent exposes exactly what the Snowflake MCP server exposes. There are no additional capabilities.

| Capability                       | What It Does (via Snowflake)                                                                                                                                       | Example Request                                                                |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Natural-language data Q&A        | Send a question to Cortex Analyst over the Volve directional-survey semantic view. Cortex picks the relevant tables/columns, generates SQL, runs it, and returns the answer. | "Average inclination per well." / "Which well reaches the deepest TVD?"        |
| SQL grounding                    | Show the SQL Cortex Analyst ran so you can review, audit, or copy it.                                                                                              | "Show me the SQL Cortex Analyst used."                                          |
| Result tables                    | Return small result sets verbatim as a Markdown table; summarize larger sets with row counts.                                                                      | "Max measured depth (MD_M_RKB) by well."                                        |
| Read-only schema / metadata SQL  | Run `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN` for objects not covered by the semantic view.                                                                       | "Describe `VOLVE_COMBINED_DIRECTIONAL_SURVEYS`." / "Row counts per table in `DASH_MCP_DB.DATA`." |
| Clarification / refinement       | Ask a single clarifying question when the input is ambiguous, or send a best-effort rephrasing and call out the assumption.                                        | "Do you mean measured depth or true vertical depth?"                            |

What the agent **does not** do (because the MCP server does not expose it, or because the agent is intentionally restricted):

- Author or modify a semantic view or its underlying tables.
- Pick which semantic view, warehouse, or role to use — those are decided by the MCP server configuration.
- Write, update, or delete data. SQL is strictly read-only and the following are refused even on explicit request: `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `CREATE`, `REPLACE`, `DROP`, `ALTER`, `TRUNCATE`, `GRANT`, `REVOKE`, `CALL`, `COPY`, `PUT`, `GET`, `USE`, `SET`, multi-statement scripts.
- Fabricate SQL. The only SQL surfaced is SQL Cortex Analyst returned in its `sql` field, or SQL the agent composed for `SQL_Execution_Tool` and actually executed.
- Answer questions about PDFs, Word docs, or other unstructured content — the agent has no search tool.
- Generate visualizations directly inside chat. Result tables are rendered as Markdown.

## How the Workflow Operates

The agent guides you through a question-and-answer flow. There is no upload step and no session-wide cache to manage. Every question is answered by calling Snowflake live; the right tool is picked by the **shape** of the question.

### Stage 1: Orientation

**When to use:** You want to know what the agent does before drilling in.

**Example prompts:**
- "What can you do?"
- "help"

**What you get back:** A short capability summary listing the kinds of questions each tool answers, with starter prompts for Cortex Analyst and read-only SQL.

### Stage 2: Ask a Well-Survey Question (Cortex Analyst)

**When to use:** Your question is structured or quantitative — "how many", "top N", "average by", "deepest / highest". These map to the Volve directional-survey semantic view.

**Example prompts:**
- "How many survey points does each well have?"
- "Average inclination (INC_DEG) per well."
- "Which well reaches the deepest true vertical depth (TVD_M_RKB)?"
- "Max measured depth (MD_M_RKB) by well."
- "Average dogleg severity and azimuth by data source."
- "Which well has the highest average dogleg severity?"

**What you get back:** A grounded answer in plain language, the SQL Cortex Analyst ran (in a fenced ```sql block), and a small result table when applicable. If Cortex Analyst returned a clarification block instead of an answer, the agent surfaces it verbatim and asks you to refine.

### Stage 3: Explore Schema / Metadata (Read-Only SQL)

**When to use:** You need account, database, schema, or table metadata that the semantic view does not model — table lists, column definitions, row counts, the value range present in a column.

**Example prompts:**
- "What tables live in `DASH_MCP_DB.DATA`?"
- "Describe `VOLVE_COMBINED_DIRECTIONAL_SURVEYS`."
- "Min and max `TVD_M_RKB` in `VOLVE_COMBINED_DIRECTIONAL_SURVEYS`."
- "Row counts per table in `DASH_MCP_DB.DATA`."
- "Show the columns on `VOLVE_SURVEYS`."

**What you get back:** The SQL the agent ran (always read-only) and the result table. Writes are refused with a short explanation pointing you at Snowsight or a privileged workflow.

### Stage 4: Interpret Results

**When to use:** You want help understanding what a tool returned.

**Example prompts:**
- "Explain the SQL Cortex Analyst just ran."
- "Summarize that result in one sentence."
- "Which columns did Cortex use for depth?"

**What you get back:** A plain-English explanation grounded in the previous tool response, without inventing details the tool did not provide.

### Stage 5: Iteratively Refine an Ambiguous Question

**When to use:** The first attempt didn't land — Cortex Analyst returned a clarification, or a query came back empty.

**Example prompts:**
- "Ask for true vertical depth instead of measured depth."
- "First show me the distinct data sources, then compare dogleg severity between them."
- "Filter to just well F-11 and re-run."

**What you get back:** A reformulated question or query, with the agent calling out the assumption it made.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  I can answer questions about Volve-field oil & gas well
         directional surveys in Snowflake: Cortex Analyst over the
         VOLVE_SURVEYS semantic view (depth, inclination, azimuth,
         dogleg severity, coordinates) and read-only SQL for schema
         and metadata.
         [...starter prompts...]

You:    How many distinct well identifiers are in the survey data?

Agent:  There are 21 distinct well identifiers in the VOLVE survey data.

         ```sql
         SELECT COUNT(DISTINCT "Well Identifier") AS distinct_well_count
         FROM DASH_MCP_DB.DATA.VOLVE_COMBINED_DIRECTIONAL_SURVEYS;
         ```

You:    Which well reaches the deepest true vertical depth?

Agent:  ```sql
         SELECT "Well Identifier" AS well, MAX(TVD_M_RKB) AS max_tvd
         FROM DASH_MCP_DB.DATA.VOLVE_COMBINED_DIRECTIONAL_SURVEYS
         GROUP BY 1
         ORDER BY max_tvd DESC
         LIMIT 5;
         ```

         | well        | max_tvd |
         | ----------- | ------- |
         | 15/9-F-11 A | 3402.0  |
         | ...         | ...     |

You:    Min and max TVD_M_RKB in VOLVE_COMBINED_DIRECTIONAL_SURVEYS.

Agent:  ```sql
         SELECT MIN(TVD_M_RKB) AS min_tvd,
                MAX(TVD_M_RKB) AS max_tvd
         FROM DASH_MCP_DB.DATA.VOLVE_COMBINED_DIRECTIONAL_SURVEYS;
         ```

         | min_tvd | max_tvd |
         | ------- | ------- |
         | 0.0     | 3402.0  |
```

## Key Benefits

| Benefit                              | Description                                                                                                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Natural-language data Q&A            | Ask survey questions in plain English; Cortex Analyst generates the SQL, runs it, and returns a grounded result.                                              |
| Curated, governed semantic view      | Answers are scoped to a semantic view an analyst has curated with dimensions, metrics, synonyms, and example queries.                                          |
| Snowflake governance                 | Object-level grants and role-based access are enforced by Snowflake automatically — users only see data the MCP server's role is authorized to access.        |
| Read-only by design                  | SQL is restricted to `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN`; writes are refused even on explicit request.                                                  |
| Grounded SQL surfaced in chat        | The SQL Cortex Analyst ran is shown in the response, so you can review, copy, or paste it elsewhere.                                                          |
| Single conversational surface        | One agent covers structured survey analytics and schema inspection — you don't have to remember which tool to ask first.                                       |
| Works independently of visualizations | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.                                                |

## Tips for Best Results

- **This data is depth-indexed, not time-series.** There is no transaction/event date — ask about wellbore geometry (depth, inclination, azimuth, coordinates) rather than time windows.
- **Use Cortex Analyst over raw SQL whenever possible.** The semantic view knows the survey definitions (measured depth, true vertical depth, dogleg severity, inclination) and writes better SQL than ad-hoc prompts. Drop to `SQL_Execution_Tool` for schema / metadata only.
- **Mention the metric, not the column.** Cortex Analyst maps "measured depth", "true vertical depth", "dogleg" to the right columns via the semantic view's synonyms — you don't need to know that MD is `MD_M_RKB`.
- **Trust the SQL block.** The SQL the agent shows is the SQL that actually ran — copy it into a worksheet or notebook for further work. Read-only by definition.
- **Group by well or data source.** Most survey questions are naturally per-well ("average inclination per well") or per source ("dogleg severity by data source").
- **Empty results often mean permissions.** If Cortex Analyst or a SQL query returns nothing, check that the MCP server's role has `SELECT` on the underlying tables and `USAGE` on the semantic view.
- **Pick the right agent.** Use the **Snowflake Agent** for Snowflake-resident Volve well-survey analytics and Snowflake schema/metadata. Use the **Databricks Genie Agent** for curated NL Q&A inside a Genie Space, or the **Databricks Agent** for Unity Catalog exploration, lineage, and ad-hoc Databricks SQL.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Limitations

These limits come from Snowflake itself, from the MCP server's configuration, and from the agent's intentional safety rules.

- **Scope is fixed by the semantic view.** The agent cannot reason over tables that are not registered to the configured semantic view. To extend the scope, an analyst must update the view.
- **One semantic view per deployment.** The MCP server points at a single semantic view. Switching domains requires reconfiguring the MCP server.
- **Read-only.** SQL writes and session-state changes are refused. The agent will suggest Snowsight or a privileged workflow instead.
- **Cortex Analyst clarifications must be answered.** When Cortex Analyst returns a `suggestions` / clarification block instead of an answer, the agent surfaces it verbatim — it will not invent a "best guess" answer.
- **No fabricated rows or SQL.** If a tool returned no rows, the agent says so. It will not synthesize values to make a result look complete.
- **No unstructured search.** The agent has no Cortex Search tool; PDFs, Word docs, and other free-text files are out of scope.
- **No email.** The agent has no outbound-mail tool.
- **Latency varies.** Cortex Analyst is synchronous but complex questions over large semantic views can take several seconds; SQL latency depends on the warehouse.
- **Concurrency and warehouse scaling are external.** Performance depends on the size and state of the warehouse the MCP server is configured against.

## Glossary

| Term                         | Definition                                                                                                                                                          |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Snowflake Cortex             | Snowflake's family of native AI features. This agent uses Cortex Analyst.                                                                                            |
| Cortex Analyst               | Snowflake's natural-language data Q&A surface backed by a semantic view. Generates SQL, runs it on the configured warehouse, returns a grounded answer.              |
| Semantic view                | A curated layer that maps survey concepts (well identifier, measured depth, inclination, azimuth, dogleg severity) onto the underlying tables/columns. Cortex Analyst reasons against it. |
| Directional survey           | A set of measurement points describing a wellbore's geometric path through the subsurface — depth, inclination, azimuth, TVD, and coordinates.                        |
| Warehouse                    | The compute endpoint Snowflake uses to run SQL. Configured per MCP server.                                                                                           |
| Role                         | Snowflake's unit of authorization. Object-level grants are evaluated against the MCP server's role.                                                                  |
| Read-only SQL                | `SELECT` / `SHOW` / `DESCRIBE` / `EXPLAIN` only. All other DDL/DML and session-state changes are refused.                                                            |
| MCP Server                   | The Model Context Protocol server (`snowflake`) that exposes the `VOLVE_SURVEYS` and `SQL_Execution_Tool` tools the agent calls at runtime. |
