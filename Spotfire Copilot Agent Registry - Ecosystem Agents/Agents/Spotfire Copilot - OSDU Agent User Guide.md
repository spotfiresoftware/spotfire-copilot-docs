# OSDU Agent — User Guide

energy × osdu × subsurface-data

The OSDU Agent is a specialist AI agent that answers questions about wells, wellbores, datasets, schemas, and lineage held in an OSDU data platform, helping geoscientists, data managers, and asset teams explore subsurface records without writing API calls.

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
  - [Stage 2: Well Discovery](#stage-2-well-discovery)
  - [Stage 3: Well Detail and Relationships](#stage-3-well-detail-and-relationships)
  - [Stage 4: Dataset Discovery](#stage-4-dataset-discovery)
  - [Stage 5: Schema Intelligence](#stage-5-schema-intelligence)
  - [Stage 6: Record Inspection and History](#stage-6-record-inspection-and-history)
  - [Stage 7: Lineage and Relationships](#stage-7-lineage-and-relationships)
  - [Stage 8: Multi-step Workflows](#stage-8-multi-step-workflows)
  - [Stage 9: Broad Search](#stage-9-broad-search)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The OSDU Agent is a conversational analyst available inside the Spotfire Copilot Panel. It is connected to an OSDU instance through a dedicated MCP server and is designed to answer questions in natural language — no record IDs, kinds, or search APIs needed up front.

The agent uses a set of specialized tools to discover wells and wellbores, retrieve full storage records and versions, run semantic search across the platform, inspect schemas, and trace lineage and relationships across records. It can chain tools automatically for compound questions (for example, "find a well, list its wellbores, then show their datasets").

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the OSDU platform through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`osdu` MCP server** — the agent's tools call this MCP server at runtime. See the [OSDU MCP server user guide](../mcp-servers/osdu/Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20User%20Guide.md) and [deployment guide](../mcp-servers/osdu/Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20Deployment%20Guide.md).

If either component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail to answer with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **OSDU Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live OSDU platform.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Filter / Reference | Examples                                                                 |
| ------------------ | ------------------------------------------------------------------------ |
| Well name fragment | `AMR`, `block 14`, `test`                                                |
| Operator           | `Aramco`, `Shell`, `Acme Energy`                                         |
| Region / field     | `North Sea`, `Gulf of Mexico`, `Permian`, `Block 23`                     |
| Record ID          | `osdu:master-data--Well:1042`, `osdu:work-product-component--Wellbore:9001` |
| Kind               | `osdu:wks:master-data--Well:1.0.0`, `osdu:wks:dataset--SeismicAcquisition:1.0.0` |
| Dataset ID         | The dataset identifier from OSDU                                         |
| Version            | A specific record version number                                         |

If a required filter or identifier is missing for a precise answer, the agent will ask a short clarifying question rather than guess.

### What Data Is Available

The agent reads from an OSDU platform through the OSDU MCP server. Typical content includes:

- **Wells** — master-data records identified by `osdu:master-data--Well:<id>`, with name, operator, region, and field attributes.
- **Wellbores** — work-product-component records linked to a parent well.
- **Datasets** — seismic, well log, production, trajectory, pressure, and other dataset records, optionally tied to wells, wellbores, or regions.
- **Schemas** — kind definitions including required fields, reference fields, and constraints.
- **Storage records** — full record payloads and version history.
- **Relationships and lineage** — graph of related records (parents, children, references) for wells, wellbores, and datasets.
- **Access and governance** — legal tags and entitlement groups configured in the partition.

The agent does **not** ingest spreadsheet uploads, marked rows from a visualization, or external CSVs. If your question requires data outside the OSDU platform, the agent will say so.

## What the Agent Can Do

The OSDU Agent groups its tools into the following capability areas:

| Capability                  | What It Does                                                                                       | Example Request                                                       |
| --------------------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Access & Governance         | List legal tags and entitlement groups configured in the partition                                  | "What legal tags are active in this partition?"                       |
| Well Discovery              | Find wells by name, operator, region, or field                                                      | "Find wells operated by Aramco in the North Sea"                      |
| Well Detail & Relationships | Summarize a well, list its wellbores, find its linked datasets                                      | "Summarize well `osdu:master-data--Well:1042` and list its wellbores" |
| Dataset Discovery           | Find datasets by region or via semantic search                                                      | "Find seismic datasets in the Gulf of Mexico"                         |
| Schema Intelligence         | Retrieve and explain the schema of any OSDU kind                                                    | "Explain the required fields in the Wellbore schema"                  |
| Record Inspection & History | Fetch a full storage record, list its versions, explain it in context                               | "Get version 3 of record `<id>`"                                      |
| Lineage & Relationships     | Trace lineage graphs and related records to N hops                                                  | "Show the lineage graph for dataset `<id>` with depth 2"              |
| Multi-step Workflows        | Chain tools automatically across discovery, detail, and lineage steps                               | "Find an AMR well, summarize it, and list its datasets"               |
| Broad Search                | Run free-text or kind-scoped search across the partition                                            | "Search OSDU broadly for anything related to CO2 storage"             |

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step and no session-wide data cache to manage — every question is answered by calling the appropriate tools against the live OSDU platform.

### Stage 1: Orientation

**When to use:** You are new to the partition and want to know what is available before drilling into specific records.

**Example prompts:**
- "What can you do?"
- "What legal tags are active in this partition?"
- "Show entitlement groups for this partition."
- "What types of records exist here?"

**What you get back:** A short capability summary, or governance lists you can use as filters when discussing access in later questions.

### Stage 2: Well Discovery

**When to use:** You want to find wells that match a name, operator, region, or field.

**Example prompts:**
- "Find wells with name containing AMR."
- "Find wells operated by Aramco."
- "List wells in the North Sea region."
- "Show wells in field block 23 operated by Shell."

**What you get back:** A clean list of matching wells with `id`, `kind`, `title`, and any operator/region/field attributes that were resolved. Pick an `id` from the result to drive the next step.

### Stage 3: Well Detail and Relationships

**When to use:** You have a well `id` and want a summary, its wellbores, or its associated datasets.

**Example prompts:**
- "Give me a summary of well `osdu:master-data--Well:1042`."
- "What wellbores are drilled from well `<id>`?"
- "What datasets are linked to well `<id>`?"
- "Does this well have any trajectory datasets?"

**What you get back:** A concise summary or a list with `id`, `kind`, `title`, and parent linkage where applicable. Use these IDs as inputs for record inspection or lineage queries.

### Stage 4: Dataset Discovery

**When to use:** You want to find datasets by region or by semantic intent.

**Example prompts:**
- "Find datasets in the Gulf of Mexico."
- "Search for seismic survey datasets semantically."
- "Find all datasets related to pressure testing."
- "What production-data datasets exist in this system?"

**What you get back:** A list of dataset records (`id`, `kind`, `title`) ranked by relevance for semantic queries, or filtered by attribute for region queries.

### Stage 5: Schema Intelligence

**When to use:** You want to understand the structure of an OSDU kind before creating or interpreting records.

**Example prompts:**
- "What is the schema for `osdu:wks:master-data--Well:1.0.0`?"
- "Explain the required fields in the Wellbore schema."
- "What reference fields does the `dataset--SeismicAcquisition` kind have?"
- "What fields are mandatory when creating a Well record?"

**What you get back:** A description of the kind's required fields, reference fields, and constraints — explained in plain language in addition to the raw schema where useful.

### Stage 6: Record Inspection and History

**When to use:** You have a specific record `id` and want its content, version history, or an in-context explanation.

**Example prompts:**
- "Get the record for id `osdu:master-data--Well:1042`."
- "Show me version 3 of record `<id>`."
- "What versions exist for record `<id>`?"
- "Explain this record and its relationships: `<id>`."

**What you get back:** The full storage record (or requested version), the version list, or a narrative explanation that places the record in context with its references and parents.

### Stage 7: Lineage and Relationships

**When to use:** You want to trace how records connect — upstream sources, downstream products, and related references.

**Example prompts:**
- "Show the lineage graph for dataset `<id>` with depth 2."
- "What records are related to `<id>`?"
- "Trace related records 2 hops out from `<id>`."
- "Explain this dataset including its lineage: `<id>`."

**What you get back:** A graph-shaped result with nodes and edges (capped for readability), plus a short narrative summary of what the graph shows.

### Stage 8: Multi-step Workflows

**When to use:** Your question combines several stages — discovery, detail, and lineage — in one ask.

**Example prompts:**
- "Find a well named AMR-03, summarize it, and list its datasets."
- "Who operates wells in the North Sea, and what datasets are associated with one of those wells?"
- "Find wells operated by Aramco, pick one, and explain its wellbores."
- "Search for pressure data semantically, then explain the lineage of the first result."

**What you get back:** A consolidated answer where the agent has chained tools internally and reports the final result with brief notes about the intermediate steps it took.

### Stage 9: Broad Search

**When to use:** You don't have a specific kind, ID, or operator in mind and want to scan the partition.

**Example prompts:**
- "Search for all Well records in the system."
- "How many records of kind `*:*:master-data--Well:*` exist?"
- "Search OSDU broadly for anything related to CO2 storage."
- "Find records matching `block 14` in any kind."

**What you get back:** A list of matching records or counts grouped by kind. Use this as a starting point for more focused queries in earlier stages.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering access & governance,
         well discovery, well detail, datasets, schemas, record
         inspection, lineage, multi-step, and broad search.]

You:    Find wells with name containing AMR, limit 5.

Agent:  Found 4 wells:
        osdu:master-data--Well:1042  AMR-03   Aramco  North Sea
        osdu:master-data--Well:2048  AMR-07   Aramco  North Sea
        ...

You:    Summarize osdu:master-data--Well:1042 and list its wellbores.

Agent:  Well AMR-03 (operator Aramco, region North Sea, field Block 23).
        Wellbores (3):
        osdu:work-product-component--Wellbore:9001  AMR-03-ST1
        osdu:work-product-component--Wellbore:9002  AMR-03-ST2
        osdu:work-product-component--Wellbore:9003  AMR-03-ST3

You:    What datasets are linked to that well?

Agent:  [Lists datasets grouped by kind: seismic, well log, trajectory,
         pressure, ...]

You:    Show the lineage for the first seismic dataset with depth 2.

Agent:  [Returns a graph summary with nodes/edges and a narrative
         description of upstream acquisition and downstream products.]

You:    Explain the Wellbore schema.

Agent:  [Describes required fields, reference fields, and constraints
         for osdu:wks:work-product-component--Wellbore:1.0.0.]

You:    Thanks.
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| No record IDs required to start      | Begin with a name fragment, operator, or region; pick IDs from the agent's results to drill in.                              |
| Specialized tools first              | Common questions are answered by purpose-built tools that already join wells, wellbores, datasets, and lineage.              |
| Semantic search built in             | Ask for concepts ("offshore wells in Gulf", "pressure testing") even when you don't know the exact kind or name.             |
| Schema explanations on demand        | Get plain-language summaries of OSDU kinds without consulting external docs.                                                 |
| Lineage and relationships            | Trace graphs of related records and dataset lineage to controlled depths, with capped node counts for readability.           |
| Multi-step chained workflows         | Combine discovery, detail, and lineage in a single question; the agent orchestrates tool calls for you.                      |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.               |

## Tips for Best Results

- **Start broad, then narrow.** Use a name fragment or operator first, then drill into a specific `id` returned by the agent.
- **Quote record IDs and kinds.** Wrap OSDU IDs and kinds in backticks (e.g. `osdu:master-data--Well:1042`) to keep them intact.
- **Specify at least one filter for well searches.** Well discovery typically needs at least one of: name, operator, region, or field.
- **Cap lineage depth.** Ask for `depth 1` or `depth 2` first; deeper traversals can be large and slower.
- **Use semantic search for concepts.** When you don't know the exact kind or name, phrase the request semantically ("anything related to CO2 storage").
- **Ask for schema before creating or interpreting records.** Knowing the required and reference fields speeds up downstream work.
- **Combine in one ask.** The agent chains tools for compound requests (find → summarize → list datasets), so you don't have to.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                    | Definition                                                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| OSDU                    | Open Subsurface Data Universe — an open-standard data platform for upstream energy data.                                    |
| Record                  | A single OSDU object identified by an `id` and described by a `kind`.                                                       |
| Kind                    | The schema identifier for a record (e.g. `osdu:wks:master-data--Well:1.0.0`).                                               |
| Well                    | A master-data record describing a physical well surface location, operator, and metadata.                                   |
| Wellbore                | A work-product-component record describing a bore drilled from a parent well.                                               |
| Dataset                 | A record describing acquired or derived data (seismic, well log, trajectory, pressure, etc.).                               |
| Storage Record          | The full payload of a record as stored by the OSDU Storage service, including data, references, and ACLs.                   |
| Version                 | A historical revision of a record; OSDU retains version history per record.                                                 |
| Schema                  | The definition of a kind — required fields, reference fields, types, and constraints.                                       |
| Lineage                 | The graph of upstream and downstream relationships connecting datasets and other records.                                   |
| Semantic Search         | A relevance-ranked search that returns records matching the meaning of a phrase rather than exact text matches.             |
| Legal Tag               | A governance label that controls how a record may be used and shared.                                                       |
| Entitlement Group       | A group identity used to grant or restrict access to records.                                                               |
| MCP Server              | The Model Context Protocol server (`osdu`) that exposes the OSDU tools the agent calls at runtime.                          |
