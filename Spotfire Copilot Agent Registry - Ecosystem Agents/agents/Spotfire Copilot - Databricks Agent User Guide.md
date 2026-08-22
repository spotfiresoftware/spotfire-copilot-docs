# Databricks Agent — User Guide

a reusable blueprint for domain-specific Databricks agents

The Databricks Agent is a **template** for building a domain expert on top of Databricks. It connects to four Databricks capabilities — a **Genie space** (data), **Unity Catalog functions** (domain computations), **AI Search** indexes (documents), and **SQL** (discovery) — and answers questions in natural language from the Spotfire Copilot Panel. To create an agent for a *new* domain, you don't change the agent: you point it at a **Genie space, functions, and indexes built for that domain.**

## Table of Contents

- [Introduction](#introduction)
- [A Blueprint for Any Domain](#a-blueprint-for-any-domain)
- [Build Your Domain Resources (Guided Path)](#build-your-domain-resources-guided-path)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Orientation](#stage-1-orientation)
  - [Stage 2: Ask Data Questions (Genie)](#stage-2-ask-data-questions-genie)
  - [Stage 3: Domain Analysis (UC Functions)](#stage-3-domain-analysis-uc-functions)
  - [Stage 4: Documents & Guidance (AI Search)](#stage-4-documents--guidance-ai-search)
  - [Stage 5: Discovery & SQL](#stage-5-discovery--sql)
  - [Stage 6: Multi-step Workflows](#stage-6-multi-step-workflows)
- [Worked Example: A Petroleum Agent](#worked-example-a-petroleum-agent)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Databricks Agent is a conversational assistant available inside the Spotfire Copilot Panel. It works against a Databricks workspace through **Databricks‑managed MCP servers** and answers questions in natural language — no Unity Catalog navigation, SQL boilerplate, or workspace tabs required.

The agent aggregates tools from up to four Databricks capabilities, each a different MCP server:

- **Genie (scoped space)** — the **primary way to retrieve data**. Ask a natural‑language question and Genie writes and runs the SQL over the data in its space.
- **Unity Catalog Functions** — call registered UC functions that encode your domain's computations, diagnostics, or analysis.
- **AI Search (Vector Search)** — retrieve grounded passages from indexed documents (best practices, standards, procedures).
- **SQL (DBSQL)** — catalog/schema/table **discovery** (SHOW/DESCRIBE) and a **fallback** for complex queries or when Genie can't answer.

Any capability that is not configured is simply unavailable; the agent works with whatever is connected and says so if something the user needs is missing. It returns Markdown‑formatted results that are easy to read in chat.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it acts only on the questions you type into the Spotfire Copilot Panel, and all answers come from the Databricks workspace through its tools.

## A Blueprint for Any Domain

The agent's **behavior is domain‑agnostic** — its routing, tool‑use rules, and response style are general. What makes it a *petroleum* agent, a *retail* agent, or a *manufacturing* agent is the **Databricks resources you point it at**. To stand up an agent for a new domain, provide three things in your Databricks workspace and configure the agent's four capability URLs to reference them:

| Building block | What you create in Databricks | What it gives the agent | Capability URL |
| --- | --- | --- | --- |
| **1. Genie space** | A Genie space over your domain's tables (the datasets you want answered in natural language). | Natural‑language **data retrieval** — the agent's primary data path. | `…/api/2.0/mcp/genie/{space_id}` |
| **2. Unity Catalog functions** | UC functions that perform your domain's computations/analysis (diagnostics, scoring, classification, validation, …). | **Domain expertise on tap** — callable analysis tools. | `…/api/2.0/mcp/functions/{catalog}/{schema}` |
| **3. Vector Search indexes** | Vector Search indexes over your domain's documents (guidance, standards, manuals). | **Grounded document answers** (RAG). | `…/api/2.0/mcp/ai-search/{catalog}/{schema}` |
| **4. SQL** | Nothing domain‑specific — it's generic discovery + fallback. | Catalog discovery and a SQL fallback. | `…/api/2.0/mcp/sql` |

**How adaptation works in practice:**

1. **Build the resources** for your domain (a Genie space, some UC functions, one or more Vector Search indexes).
2. **Point the agent at them** by setting the four URLs in the agent server's configuration (see the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md#databricks-agent)). Only the ones you set are active.
3. **Supply a behavior pack.** Pointing the agent at your resources lets it *fetch* your data; the **behavior pack** is what makes it *speak your domain* — a small folder holding the agent's identity (`pack.yaml`), system prompt, domain knowledge (key terms, formulas, thresholds), help text, and skills. The server ships a built‑in **default** pack, so the agent boots without one — but that default is generic, so a domain pack is **expected for a real domain agent** (it also sets the agent's name/description in the picker). Mount your pack folder and point the agent at it (no code change); the [MCP Server Blueprint](databricks-mcp-server-blueprint/mcp_server_blueprint.ipynb) notebook generates a starter pack you can customize. See *Behavior pack (per‑domain)* in the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md#databricks-agent), and the [Databricks Agent Behavior Pack Authoring Guide](databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20Agent%20Behavior%20Pack%20Authoring%20Guide.md) for the exact folder structure and skill format.

That's the whole recipe. The same agent becomes a specialist for whatever domain your resources and behavior pack describe — a blueprint you can replicate per domain.

**Prefer a guided, automated path?** Rather than building the resources by hand, run the **MCP Server Blueprint** notebook — it provisions all four MCP servers *and* generates a starter behavior pack for you. See [Build Your Domain Resources (Guided Path)](#build-your-domain-resources-guided-path).

## Build Your Domain Resources (Guided Path)

The blueprint above lists *what* to build. The **MCP Server Blueprint** notebook builds it *for you* — a self‑contained Databricks notebook (runs on serverless compute, no cluster setup) that provisions all four Databricks‑managed MCP servers **and** generates a starter behavior pack. It turns the manual “build the resources” step into a guided, roughly 1–2‑hour workflow.

**What the notebook produces**

- The four **capability endpoint URLs** (Genie space, UC functions, AI Search, DBSQL) — printed at the end, ready to paste into the agent server configuration.
- A **service principal** granted the access each capability needs.
- A **starter behavior pack** — the folder you hand to deployment (`pack.yaml`, `system_prompt.md`, `AGENTS.md`, `help.md`, and the four capability skills), pre‑filled for your domain.

**What you do (high level)**

1. **Configure** — set your catalog, schema, domain tables, and domain name.
2. **Verify prerequisites** — the notebook confirms the catalog, schema, and tables are reachable.
3. **Create UC functions** — your domain computations (diagnosis, scoring, forecasting), with SQL templates and Databricks Assistant prompts.
4. **Create a Genie space** — natural‑language access over your tables.
5. **Generate & index reference documents** — build an AI Search index for grounded document answers.
6. **Grant permissions** — SQL grants plus Genie `CAN_RUN` for the service principal.
7. **Generate the behavior pack** — the notebook writes the pack files for your domain.
8. **Test connectivity & collect URLs** — validates all four servers and prints your endpoints.

For the full step‑by‑step — including the Databricks Assistant shortcuts and troubleshooting — see the [**MCP Server Blueprint** guide](databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Blueprint%20Guide.md) and its [notebook](databricks-mcp-server-blueprint/mcp_server_blueprint.ipynb).

**Customize the generated pack.** The notebook produces a *starter* pack; refine it so the agent speaks your domain fluently — real thresholds and formulas in `AGENTS.md`, accurate table schemas in the Genie skill, and every function listed in the UC‑functions skill. For the exact folder structure, the `SKILL.md` format (YAML frontmatter, the rule that a skill's folder name must match its `name`, and space‑separated `allowed-tools`), and authoring tips, follow the [Databricks Agent Behavior Pack Authoring Guide](databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20Agent%20Behavior%20Pack%20Authoring%20Guide.md).

**Hand off to deployment.** The notebook writes the pack into a Databricks UC Volume, so first **export it** from the volume (the [MCP Server Blueprint guide](databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Blueprint%20Guide.md#2-export-the-pack-from-databricks) shows the CLI/UI/API options). Then give the deployment team the exported pack folder plus the endpoint URLs and service‑principal credentials. They mount the pack (`DATABRICKS_AGENT_PACK_DIR`) and set the four `*_MCP_SERVER_URL` values and the OAuth variables. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md#databricks-agent).

> Building by hand instead? The same three building blocks in [A Blueprint for Any Domain](#a-blueprint-for-any-domain) still apply — the notebook simply automates them and gives you a pack to start from.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **Databricks resources for your domain** — a Genie space, UC functions, and/or Vector Search indexes (see [A Blueprint for Any Domain](#a-blueprint-for-any-domain)), each exposed as a Databricks‑managed MCP endpoint and configured on the agent server. No separate self‑hosted MCP server is required.
- **A Databricks service principal (OAuth M2M)** — the agent authenticates with a service principal using OAuth (tokens minted and refreshed automatically). The principal must have permission to use the Genie space, functions, indexes, and warehouse you expect to access.

Configuration is covered in the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md#databricks-agent). If a capability is not configured or the principal lacks permission, that capability's tools are unavailable and the agent will say so.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select the **Databricks Agent** (or the domain‑specific label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always works against the live Databricks workspace.

### What You Provide

The agent only needs **natural‑language questions**. To get focused answers, mention any of the following when they apply:

| Reference        | Examples                                                              |
| ---------------- | -------------------------------------------------------------------- |
| Data question    | "Total sales by region last quarter", "Which items are low on stock?" |
| Computation      | "Score this customer's churn risk", "Diagnose this reading"          |
| Knowledge topic  | "What does our standard say about X?"                                |
| Discovery        | "What tables/functions are available?"                              |
| SQL              | A specific SQL statement you want executed                           |

If a required detail is missing (for example, a vague time window), the agent asks a short clarifying question or resolves it explicitly before acting.

### What Data Is Available

What the agent can reach depends on which capabilities are configured and what the service principal is allowed to use:

- **Genie space** — natural‑language answers over the tables in the configured Genie space, including the SQL Genie ran.
- **Unity Catalog functions** — the functions registered under the configured `{catalog}.{schema}`, exposed as callable tools.
- **Vector Search indexes** — the configured indexes, queried for the most relevant chunks (grounded retrieval).
- **SQL results** — rows returned by SQL executed against Unity Catalog via the DBSQL server.

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, or external CSVs. Access is governed by the service‑principal identity and the resources it is permitted to use.

## What the Agent Can Do

The agent groups its tools into four capability areas and routes each question to the right one:

| Capability | What It Does | Route it handles |
| --- | --- | --- |
| **Genie (data)** | Answer natural‑language data questions over the Genie space; Genie writes and runs the SQL. **Primary data path.** | "What / how many / trends / comparisons / totals over the data" |
| **UC Functions (computation)** | Call registered functions that compute domain analysis/diagnostics/scoring. | "Diagnose / analyze / score / classify / validate …" |
| **AI Search (documents)** | Retrieve and ground answers in indexed documents. | "What does the guidance/standard/manual say about …?" |
| **SQL (discovery)** | Catalog/schema/table discovery and a fallback for complex SQL. | "What tables/columns/functions exist?" and Genie fallback |

For a question that needs a computation on data the user didn't provide, the agent **chains** them: retrieve the values with Genie, then call the function (see [Multi‑step Workflows](#stage-6-multi-step-workflows)).

## How the Workflow Operates

Every question is answered by calling the appropriate tools against the live workspace — there is no upload step or session cache to manage.

### Stage 1: Orientation

**When to use:** You want to see what the agent can do.

**Example prompts:** "What can you do?" / "help"

**What you get back:** A capability summary with starter prompts.

### Stage 2: Ask Data Questions (Genie)

**When to use:** Any question that needs data — values, trends, comparisons, totals, "which …".

**Example prompts:**
- "What were total sales by region last quarter?"
- "Which records changed the most this month?"

**What you get back:** Genie's grounded answer and result table (and the SQL it ran when provided). Genie is the primary retrieval path.

### Stage 3: Domain Analysis (UC Functions)

**When to use:** You want a domain computation/diagnosis a registered function performs.

**Example prompts:**
- "Score / diagnose / classify / validate this: …" (with explicit values), or
- "Diagnose the worst‑performing item in category X" (the agent fetches the data with Genie first, then runs the function).

**What you get back:** The function's result, relayed faithfully, with a brief interpretation.

### Stage 4: Documents & Guidance (AI Search)

**When to use:** A question best answered from indexed documents (best practices, standards, procedures).

**Example prompts:** "What does our standard say about …?" / "Best practices for …"

**What you get back:** An answer grounded in the retrieved passages, noting the index used.

### Stage 5: Discovery & SQL

**When to use:** You want to see what exists, or you have exact SQL to run.

**Example prompts:**
- "What tables are in `catalog.schema`?" / "Describe `catalog.schema.table`."
- "Run this read‑only query: `SELECT …`."

**What you get back:** The discovery result or query output as a Markdown table. Read‑only by default; the agent confirms before any data‑modifying statement.

### Stage 6: Multi-step Workflows

**When to use:** The question spans more than one capability.

**Example prompts:**
- "Find the worst item by <metric>, then diagnose it." → Genie retrieves the data → a UC function analyzes it → ranked answer.
- "Is our value above the documented threshold?" → Genie gets the value → AI Search finds the threshold → compare.

**What you get back:** A consolidated answer where the agent chained capabilities internally and reports the result with brief notes on the intermediate steps.

## Worked Example: A Petroleum Agent

The same blueprint, configured for oil & gas, becomes a petroleum‑engineering assistant for the Volve field:

- **Genie space:** "Oil & Gas Production Analytics" over `master_production_data` (daily oil/gas/water volumes, pressures) and `volve_combined_directional_surveys` (trajectory stations).
- **UC functions:** `diagnose_well_production`, `analyze_wellbore_trajectory`, plus text helpers (`classify_topic`, `summarize_text`, `extract_entities`, `validate_data`).
- **AI Search index:** `petroleum_knowledge_index` (technical guidance for petroleum exploration).

Example conversation:

```
You:    Find the sickest well in the OSPREY field based on the latest production data.

Agent:  [Genie retrieves OSPREY's latest production values, then runs
         diagnose_well_production on them.]
        Health status: WARNING. Water cut ≈ 31%, GOR ≈ 63 scf/stb …

You:    What does the guidance say about pressure testing?

Agent:  [AI Search over the petroleum knowledge index, grounded in the documents.]

You:    What tables are available?

Agent:  [SQL SHOW TABLES … returns the schema's tables.]
```

Swap the Genie space, functions, and index for a different domain, and the same agent answers that domain's questions.

## Key Benefits

| Benefit | Description |
| --- | --- |
| Domain‑agnostic blueprint | One agent design; adapt to any domain by pointing it at a Genie space, functions, and indexes. |
| Natural‑language data | Genie writes and runs the SQL — users don't need SQL for everyday questions. |
| Domain expertise on tap | Registered UC functions turn domain logic into callable analysis tools. |
| Grounded documents | AI Search answers are grounded in indexed documents, reducing hallucination. |
| Automatic routing & chaining | The agent picks the right capability and chains them (retrieve → compute) when needed. |
| Read‑only by default | SQL defaults to read‑only; data‑modifying statements require confirmation. |
| Secure, auto‑refreshing auth | Connects via a Databricks service principal (OAuth M2M); tokens minted and refreshed automatically. |

## Tips for Best Results

- **Pick the right capability by intent.** Data question → Genie; a computation/diagnosis → a UC function; document/standard question → AI Search; "what exists?" → SQL.
- **Make questions concrete.** Resolve vague windows ("recent") into explicit ranges so answers match your intent.
- **Let the agent chain.** For "analyze the worst X", just ask — it fetches the data with Genie and runs the function for you; you don't need to paste values.
- **Ground knowledge questions.** For "what does our standard say about Y", the agent uses AI Search and cites the passages — ask it to name the index for provenance.
- **Default to read‑only SQL.** Only ask for a write when you truly intend to change data, and confirm the change.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term | Definition |
| --- | --- |
| Blueprint | The domain‑agnostic agent design; specialized per domain by the Databricks resources it points at. |
| Behavior pack | A folder holding the agent's domain‑specific inputs (system prompt, domain knowledge, help text, skills, and a `pack.yaml` manifest). The server ships a default pack; mount your own to adapt the agent to a domain without code changes. |
| MCP Server Blueprint | A Databricks notebook that provisions the four Databricks‑managed MCP servers for a domain and generates a starter behavior pack — the guided alternative to building the resources by hand. |
| Behavior Pack Authoring Guide | The reference for the behavior pack's folder structure and `SKILL.md` format ([Databricks Agent Behavior Pack Authoring Guide](databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20Agent%20Behavior%20Pack%20Authoring%20Guide.md)), used to customize the pack the blueprint generates. |
| Databricks‑managed MCP server | A Model Context Protocol endpoint hosted by Databricks exposing a workspace capability (genie / functions / vector‑search / sql) as tools. |
| Genie space | A scoped Databricks Genie experience over a chosen set of tables; the agent's primary natural‑language data‑retrieval path. |
| Unity Catalog (UC) | Databricks' centralized governance layer for cataloging, securing, and discovering data and AI assets. |
| UC Function | A function registered in Unity Catalog, exposed by the Functions MCP server as a callable analysis tool. |
| Vector Search / AI Search | Databricks' vector index/retrieval service; the agent queries indexes to ground answers in relevant documents (RAG). |
| RAG | Retrieval‑Augmented Generation — grounding an answer in retrieved passages rather than the model's own knowledge. |
| DBSQL | The Databricks SQL execution capability; used for discovery (SHOW/DESCRIBE) and as a fallback. |
| Service principal (M2M OAuth) | A non‑human Databricks identity used with OAuth client credentials to authenticate the agent to the managed servers. |
