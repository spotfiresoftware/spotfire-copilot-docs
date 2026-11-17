# GraphRAG Agent — User Guide

spotfire-knowledge × retrieval × knowledge-graph

The GraphRAG Agent is a specialist AI agent that answers questions about the Spotfire
knowledge corpus — product documentation, release notes, Dr. Spotfire video transcripts, and
structured drilling reports — using retrieval-augmented generation grounded in a vector store
and a Neo4j knowledge graph. Every answer is backed by citations to its source passage, page,
or video timestamp.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Answer a Documentation Question](#stage-1-answer-a-documentation-question)
  - [Stage 2: Investigate a Topic in Depth](#stage-2-investigate-a-topic-in-depth)
  - [Stage 3: Troubleshoot a Spotfire Problem](#stage-3-troubleshoot-a-spotfire-problem)
  - [Stage 4: Compare Product Versions](#stage-4-compare-product-versions)
  - [Stage 5: Discover Related Documentation](#stage-5-discover-related-documentation)
  - [Stage 6: Explore the Knowledge Graph](#stage-6-explore-the-knowledge-graph)
  - [Stage 7: Answer Drilling-Data Questions](#stage-7-answer-drilling-data-questions)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The GraphRAG Agent is a conversational research assistant available inside the Spotfire
Copilot Panel. It is connected to the unified Spotfire knowledge corpus through a dedicated
MCP server and answers questions in natural language — no search syntax, no manual document
hunting.

The agent combines two retrieval styles. **Vector search** finds the most relevant passages
across product guides, release notes, and video transcripts (hybrid dense + keyword
retrieval). A **Neo4j knowledge graph** adds structure on top: it tracks how Spotfire
features change across versions, how documents and entities relate to one another, and the
structured contents of Daily Drilling Reports (DDRs). The agent picks the right mix for each
question and always reports where its answer came from.

The agent works independently of the surrounding analysis or dashboard. It does not receive
marked rows, table data, or column metadata — it acts only on the questions you type into the
Spotfire Copilot Panel, and every answer is grounded in the corpus through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot
Panel, the following must already be deployed and reachable in your environment:

- **LangGraph DeepAgents server** — the agent ships as part of the LangGraph DeepAgents
  server. See the [OSS deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md)
  or the [licensed deployment guide](../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`graphrag` MCP server** — the agent's tools call this MCP server at runtime. See the
  [GraphRAG MCP Server User Guide](../mcp-servers/graphrag/Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20User%20Guide.md)
  and [deployment guide](../mcp-servers/graphrag/Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20Deployment%20Guide.md).
- **A loaded corpus** — the MCP server reads a Milvus/Zilliz collection and a Neo4j graph that
  must be populated first. See the
  [GraphRAG Corpus Loading Guide](../mcp-servers/graphrag/Spotfire%20Copilot%20-%20GraphRAG%20Corpus%20Loading%20Guide.md).

If the agent server or the MCP server is missing or unreachable, the agent will not appear in
the Copilot Panel, or it will fail to answer with a tool-related error. If the corpus is empty
for a given document type, the agent will say it found nothing rather than inventing an answer.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **GraphRAG Agent** (or the equivalent label configured in your environment) from the
   agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live knowledge corpus.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, include any of
the following when they apply:

| Signal              | Examples                                                           |
| ------------------- | ------------------------------------------------------------------ |
| Topic / feature     | "the geospatial library", "Action Mods", "Apache Drill connector"  |
| Document type       | "in the release notes", "from the Dr. Spotfire videos"             |
| Product version     | "in 15.0.0", "between 14.5.0 and 15.0.0"                            |
| Error message       | Paste the exact error text to troubleshoot                         |
| Well / rig / report | For drilling-data questions (e.g. `15/9-19 A`, a report id)        |

If a question is ambiguous, the agent asks a short clarifying question rather than guessing.

### What Data Is Available

The agent reads from a unified corpus loaded by the data loader into a vector store (Milvus/
Zilliz) and a Neo4j knowledge graph. Typical content includes:

- **Product documentation** — Spotfire product guides and manuals.
- **Release notes** — per-version notes, plus a feature-lifecycle graph tracking when features
  were **introduced, changed, deprecated, or removed**.
- **Dr. Spotfire video transcripts** — timestamped transcripts of Dr. Spotfire sessions, so
  citations can deep-link to the exact moment in a video.
- **Customer / domain documents** — any additional documentation loaded for your deployment.
- **Daily Drilling Reports (DDRs)** — structured oil and thermal drilling reports (wells,
  rigs, depth, operations, surveys, casing, drilling fluid, pore pressure).

The agent does **not** read Spotfire columns, marked rows, or live analysis data. If your
question needs data outside the loaded corpus, the agent will say so.

## What the Agent Can Do

The GraphRAG Agent groups its capabilities into the following areas:

| Capability                    | What It Does                                                                                        | Example Request                                                            |
| ----------------------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Documentation Q&A             | Answer a direct question from the docs, release notes, or videos, with citations                    | "What does the geospatial library for Spotfire do?"                        |
| In-depth investigation        | Synthesize an answer across several documents for a broad or open-ended topic                        | "What are the Spotfire support essentials and best practices?"             |
| Troubleshooting               | Diagnose an error or problem and suggest remediation from the documentation                          | "I get a connection error opening a data connection — how do I fix it?"    |
| Version comparison            | List what was introduced, changed, deprecated, or removed between versions                           | "List every feature changed between Spotfire 14.5.0 and 15.0.0"           |
| Discover related docs         | Find related manuals, tutorials, release notes, or videos for a topic                                | "What Dr. Spotfire videos do you have about geospatial?"                   |
| Knowledge-graph exploration   | Combine semantic search with graph expansion to answer relationship / connected-entity questions     | "What is related to the Apache Drill connector?"                          |
| Drilling-data analytics       | Answer structured questions about drilling reports — wells, rigs, depth, operations, and more        | "What's the total depth drilled for well 15/9-19 A?"                       |

## How the Workflow Operates

The agent routes each question to the matching skill and answers by calling the appropriate
tools against the live corpus. There is no upload step and no session-wide cache to manage.

### Stage 1: Answer a Documentation Question

**When to use:** You have a direct question and want a grounded answer with citations.

**Example prompts:**
- "What's new with Spotfire Copilot 2.3?"
- "What are Action Mods in Spotfire and how are they used?"
- "How do I push compute to load billions of rows fast?"

**What you get back:** A concise answer assembled from the most relevant passages, each claim
cited to its source document (with page range) or video (with a `hh:mm:ss` timestamp
deep-link).

### Stage 2: Investigate a Topic in Depth

**When to use:** The question is broad, open-ended, or needs several sources synthesized.

**Example prompts:**
- "What are the Spotfire support essentials / best practices?"
- "Give me an overview of geospatial analytics in Spotfire."

**What you get back:** A structured synthesis drawing on multiple documents, with citations
per section and an honest note where the corpus is thin.

### Stage 3: Troubleshoot a Spotfire Problem

**When to use:** You hit an error or unexpected behavior and want a documented fix.

**Example prompts:**
- "I get `<paste error>` when opening a data connection."
- "My visualization renders slowly on a large data table — what should I check?"

**What you get back:** A likely cause and remediation steps drawn from the documentation,
cited, with a clear statement when no documented fix is found.

### Stage 4: Compare Product Versions

**When to use:** You want the complete, structured set of feature changes across versions —
not a few keyword hits.

**Example prompts:**
- "What changed for visualizations in 15.0?"
- "List every feature introduced, deprecated, or removed between Spotfire 14.5.0 and 15.0.0."
- "Show all features that were deprecated across all Spotfire versions."

**What you get back:** A structured list of features and their lifecycle events
(introduced / changed / deprecated / removed), sourced from the release-notes feature-lifecycle
graph, each traceable to the release-notes passage it was parsed from.

### Stage 5: Discover Related Documentation

**When to use:** You want to find the documents, tutorials, or videos about a topic — corpus
orientation rather than a single answer.

**Example prompts:**
- "What Dr. Spotfire videos do you have about geospatial?"
- "List the videos on data virtualization."
- "Which docs mention Databricks or Snowflake?"

**What you get back:** A list of related documents and videos with titles and links, grouped
by type where useful.

### Stage 6: Explore the Knowledge Graph

**When to use:** Your question is about relationships or connected context — how things relate,
not just what a document says.

**Example prompts:**
- "What is related to the Apache Drill connector?"
- "Show me the entities connected to this document."
- "Give me an overview of the knowledge graph."

**What you get back:** A combined answer: supporting passages (with citations) plus the graph
edges that connect the retrieved documents, features, and entities.

### Stage 7: Answer Drilling-Data Questions

**When to use:** You want structured facts about drilling reports — wells, rigs, depth, field
statistics, operations, surveys, casing, drilling fluid, or pore pressure.

**Example prompts:**
- "List the drilling reports for well 15/9-19 A."
- "What's the total depth drilled for well 15/9-19 A?"
- "How deep did the FORGE 16A well go?"
- "What were the summary activities on report `<report id>`?"

**What you get back:** Computed, structured answers (counts, sums, min/avg/max) with their
provenance (wellbore, report id, field key), honoring the differences between oil and thermal
wells. This capability covers the same drilling-report analytics as the dedicated DDR agent.

## Typical End-to-End Session

```
You:    What does the geospatial library for Spotfire do?

Agent:  [Summarizes the geospatial library from the documentation and
         Dr. Spotfire videos, with a citation deep-linking to the video
         at 00:04:59 and a product-guide page reference.]

You:    What Dr. Spotfire videos do you have about geospatial?

Agent:  [Lists the matching videos with titles and links.]

You:    List every feature introduced or deprecated between Spotfire
        14.5.0 and 15.0.0.

Agent:  [Returns a structured list of features with their lifecycle
         events, each traceable to the release notes.]

You:    What's the total depth drilled for well 15/9-19 A?

Agent:  Well 15/9-19 A: ~1,954 m drilled across 40 daily reports;
        ~4,643 m measured depth. (Oil well — distance-drilled tracked
        per report.)

You:    What is related to the Apache Drill connector?

Agent:  [Returns supporting passages plus the connected features and
         documents from the knowledge graph.]

You:    Thanks.
```

## Key Benefits

| Benefit                           | Description                                                                                                                          |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Grounded, cited answers           | Every claim is backed by a source passage, page range, or video timestamp — no ungrounded generation.                               |
| Video deep-links                  | Transcript citations link to the exact moment in a Dr. Spotfire video (`…&t=NNNs`), so you can jump straight to the relevant part.   |
| Hybrid retrieval                  | Combines dense semantic search with keyword (BM25) matching for both conceptual and exact-term questions.                            |
| Version-aware                     | A feature-lifecycle graph answers "what changed between versions" completely and structurally, not with a few keyword hits.         |
| Graph + vector in one agent       | Relationship and connected-context questions are answered by combining semantic retrieval with knowledge-graph expansion.           |
| Drilling-report analytics         | Structured DDR questions (wells, rigs, depth, operations) are answered from the graph, across oil and thermal wells.                 |
| Works independently               | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.                       |

## Tips for Best Results

- **Name the topic or feature.** Mention the specific feature, connector, or product area —
  the agent retrieves the most relevant passages for it.
- **Say the document type when it matters.** "in the release notes" or "from the Dr. Spotfire
  videos" focuses retrieval on that source.
- **Give versions for comparisons.** For "what changed" questions, name the versions or an
  inclusive range (e.g. `14.5.0` to `15.0.0`).
- **Paste exact error text to troubleshoot.** The exact message retrieves the best-matching
  remediation guidance.
- **Use exact well / report identifiers for drilling questions.** If unsure, ask "List the
  wells" or "List the drilling reports for `<well>`" first.
- **Follow the citations.** Open the cited page or video timestamp to verify and read more.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                   | Definition                                                                                                                       |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| GraphRAG               | Retrieval-Augmented Generation that combines vector search with a knowledge graph for grounded, relationship-aware answers.       |
| Corpus                 | The unified set of loaded content: product docs, release notes, Dr. Spotfire transcripts, customer docs, and drilling reports.    |
| Vector search          | Finding the most relevant passages by semantic similarity (optionally combined with keyword/BM25 matching).                       |
| Knowledge graph        | A Neo4j graph of features, documents, entities, and drilling-report records and the relationships between them.                   |
| Citation               | The source reference attached to an answer — document title and page range, or video title and `hh:mm:ss` timestamp.             |
| Feature lifecycle      | The record of when a Spotfire feature was introduced, changed, deprecated, or removed, parsed from release notes.                 |
| Transcript             | A timestamped text transcript of a Dr. Spotfire video, enabling deep-linked citations.                                           |
| DDR                    | Daily Drilling Report — a structured daily record of drilling operations (oil and thermal wells).                                |
| MCP Server             | The Model Context Protocol server (`graphrag`) that exposes the retrieval and graph tools the agent calls at runtime.             |
