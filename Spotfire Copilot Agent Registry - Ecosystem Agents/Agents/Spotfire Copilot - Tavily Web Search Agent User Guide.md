# Tavily Web Search Agent — User Guide

web × search × news

The Tavily Web Search Agent is a specialist AI agent that performs AI-powered web searches, generates direct answers backed by sources, and surfaces recent news — letting users research topics in plain language without leaving the Spotfire Copilot Panel.

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
  - [Stage 2: General Web Search](#stage-2-general-web-search)
  - [Stage 3: Direct Answer Search](#stage-3-direct-answer-search)
  - [Stage 4: News Search](#stage-4-news-search)
  - [Stage 5: Domain-Scoped and Formatted Research](#stage-5-domain-scoped-and-formatted-research)
  - [Stage 6: Multi-step Research](#stage-6-multi-step-research)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Tavily Web Search Agent is a conversational research assistant available inside the Spotfire Copilot Panel. It is connected to Tavily's AI-powered search API through a dedicated MCP server and is designed to answer research questions in natural language — no separate browser tab, copy-pasting URLs, or manual citation formatting required.

The agent uses a set of specialized tools to run general web searches with AI-extracted content, run "answer" searches that produce a direct answer plus supporting sources, and run news searches that focus on recent articles within a configurable time window. Each tool supports domain inclusion and exclusion so results can be scoped to authoritative sources.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the public web via Tavily through the agent's tools.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`tavily` MCP server** — the agent's tools call this MCP server at runtime. See [Tavily MCP server deployment guide](../MCP%20Servers/Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20Deployment%20Guide.md).

If either component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail to answer with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Tavily Web Search Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live Tavily API.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Reference          | Examples                                                       |
| ------------------ | -------------------------------------------------------------- |
| Topic              | "Anthropic's MCP protocol", "redwood trees", "carbon capture"  |
| Output format      | "MLA format", "bullet list", "markdown with citations"         |
| Time window (news) | "in the last 5 days", "this week", "since April 1"             |
| Domain include     | "only from `nature.com` and `nasa.gov`"                        |
| Domain exclude     | "exclude Wikipedia", "no `reddit.com` results"                 |
| Depth              | "quick summary" → basic; "thorough review" → advanced          |
| Result count       | "top 10 results", "give me 3 sources"                          |

If a required reference is missing (for example, a topic), the agent will ask a short clarifying question rather than guess.

### What Data Is Available

The agent reads from the public web through Tavily's API and the `tavily` MCP server. Typical content includes:

- **Web pages** — articles, documentation, blog posts, and reference material with AI-extracted relevant content.
- **Direct answers** — a generated answer to a specific question, accompanied by the supporting source list.
- **News articles** — recent items with publication dates, within a configurable look-back window.

The agent does **not** read paywalled content beyond what Tavily can extract, ingest spreadsheet uploads, or read marked rows from a visualization. Quality of results depends on Tavily's index coverage and the API key/quota configured on the MCP server.

## What the Agent Can Do

The Tavily Web Search Agent groups its tools into the following capability areas:

| Capability                  | What It Does                                                                                       | Example Request                                              |
| --------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| General Web Search          | Run a comprehensive web search and return multiple results with AI-extracted relevant content       | "Tell me about Anthropic's newly released MCP protocol."     |
| Direct Answer Search        | Run a search and return a generated answer with the supporting source list                          | "What is the average lifespan of redwood trees?"             |
| News Search                 | Find recent news articles within a configurable look-back window (in days)                          | "Give me the top 10 AI-related news in the last 5 days."     |
| Domain-Scoped Research      | Restrict results to (or exclude) specific domains                                                    | "Tell me about redwood trees; exclude Wikipedia."            |
| Depth-Aware Search          | Choose between fast `basic` searches and thorough `advanced` searches                                | "Give me a thorough review of recent CRISPR breakthroughs."  |
| Formatted Output            | Return the answer in a specific format (MLA, markdown, bullets) with inline citations                | "Use MLA format in markdown with the URLs in the citations." |

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step — every question is answered by calling the appropriate tool against Tavily's API.

### Stage 1: Orientation

**When to use:** You want to know what the agent can do before drilling in.

**Example prompts:**
- "What can you do?"
- "What kinds of research are you good at?"

**What you get back:** A capability summary covering web search, answer search, and news search, plus the domain-filtering and depth options.

### Stage 2: General Web Search

**When to use:** You want a multi-source overview of a topic with AI-extracted highlights.

**Example prompts:**
- "Tell me about Anthropic's newly released MCP protocol."
- "Summarize recent advances in carbon capture, exclude `reddit.com`."
- "Find documentation pages for the OData v4 `$apply` query option, prefer `oasis-open.org` and `learn.microsoft.com`."

**What you get back:** A list of results with title, URL, AI-extracted content, and (where applicable) a publication date.

### Stage 3: Direct Answer Search

**When to use:** You want a concrete answer plus the sources that back it up.

**Example prompts:**
- "What is the average lifespan of redwood trees?"
- "How tall is the tallest known redwood, with sources?"
- "Give me a concrete answer backed by current web sources: what is the average lifespan of redwood trees?"

**What you get back:** A short generated answer, followed by the supporting sources (title + URL) and detailed extracted content for each.

### Stage 4: News Search

**When to use:** You want recent items, optionally constrained to a time window.

**Example prompts:**
- "Give me the top 10 AI-related news in the last 5 days."
- "Latest news about Spotfire releases from the last 14 days."
- "Show me news about CRISPR from the last 30 days, exclude `reddit.com`."

**What you get back:** A list of recent articles with publication dates, AI-extracted content, and source URLs.

### Stage 5: Domain-Scoped and Formatted Research

**When to use:** You want results from (or excluding) specific sites, or in a particular citation style.

**Example prompts:**
- "Tell me about redwood trees in MLA format in markdown syntax, include URLs in the citations, exclude Wikipedia."
- "Research the latest on LLM evaluation benchmarks, include only `arxiv.org` and `openai.com`."
- "Summarize Snowflake's latest Iceberg announcements; exclude press-release republishers."

**What you get back:** Results scoped to your domain filters, optionally formatted with inline citations.

### Stage 6: Multi-step Research

**When to use:** Your question combines breadth and depth, or general and news searches.

**Example prompts:**
- "First find the top 5 AI-related news items from the last 7 days, then give me an answer-style summary of what they collectively say."
- "Find authoritative pages on `nasa.gov` about Mars sample return, then summarize the timeline with citations."

**What you get back:** A consolidated answer where the agent has chained tools internally (news + general / answer) and reports a summary with citations and short notes about intermediate steps.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering general web
         search, direct answer search, news search, domain
         include/exclude filters, depth, and formatted output.]

You:    Tell me about Anthropic's newly released MCP protocol.

Agent:  Detailed Results:

        Title: Introducing the Model Context Protocol — Anthropic
        URL:   https://www.anthropic.com/news/...
        Content: ... AI-extracted summary ...

        Title: MCP specification overview — modelcontextprotocol.io
        URL:   https://modelcontextprotocol.io/...
        Content: ... AI-extracted summary ...

You:    What is the average lifespan of redwood trees? Use MLA in
        markdown, include the URLs in the citations, exclude Wikipedia.

Agent:  Answer: Coast redwoods (Sequoia sempervirens) commonly live
        1,200–1,800 years, with the oldest verified specimens over
        2,000 years old.

        Sources (MLA):
        - "Coast Redwood." *Save the Redwoods League*, ...,
          https://www.savetheredwoods.org/...
        - Smith, J. "Longevity of Sequoia sempervirens." *Forest
          Ecology and Management*, vol. 482, 2021, https://...

You:    Give me the top 10 AI-related news in the last 5 days.

Agent:  Detailed Results:
        1) Title: ...                        Published: 2026-05-11
           URL: https://...
           Content: ...
        2) Title: ...                        Published: 2026-05-10
           URL: https://...
        ...
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| AI-extracted content                  | Tavily summarizes each page so you can scan results quickly without opening every link.                                      |
| Direct answers with sources          | The answer-search tool returns a concrete answer plus the supporting source list, making citations easy.                     |
| News with publication dates          | News search returns articles with their publication date and a configurable look-back window.                                 |
| Domain filtering                     | Results can be restricted to (or exclude) specific domains, so you can favor authoritative sources and skip noisy ones.       |
| Depth control                        | Choose `basic` for speed and `advanced` for thoroughness, depending on the question.                                          |
| Format-aware answers                 | Ask for MLA, markdown, bullets, or other formats and the agent will present the result that way with citations.              |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.               |

## Tips for Best Results

- **Be specific.** "Recent CRISPR news from the last 7 days, exclude `reddit.com`" is much better than "CRISPR news".
- **Pick the right tool with your words.** Say "give me an answer" for direct-answer search, "find articles" for general search, "latest news" for news search.
- **Filter domains for trust.** Prefer authoritative sources with `include_domains` (e.g. `nasa.gov`, `nature.com`); exclude noisy ones with `exclude_domains` (e.g. `reddit.com`, `pinterest.com`).
- **Set a time window for news.** "In the last 14 days" or "from the last month" — Tavily news search supports a configurable look-back in days.
- **Ask for a format.** "MLA in markdown with citations" or "bullet list with URLs" gives you ready-to-paste output.
- **Use `basic` first, `advanced` when needed.** Basic searches are cheaper and fast; reach for advanced when the topic is dense or the answer must be thorough.
- **Cap results.** Asking for "the top 5" or "10 results" keeps responses focused and easy to scan (Tavily supports up to about 20 results per call).
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                         | Definition                                                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Tavily                       | An AI-powered web search API that returns ranked results with AI-extracted content, and optional generated answers.       |
| Web Search                   | A general search across the web; returns multiple results with AI-extracted content.                                      |
| Answer Search                | A search that returns a generated answer plus the supporting source list.                                                 |
| News Search                  | A search focused on recent news articles, with publication dates and a configurable look-back window in days.             |
| Search Depth                 | `basic` (fast, cheaper) or `advanced` (more thorough analysis).                                                           |
| Include / Exclude Domains    | Filters that restrict results to, or remove results from, specific websites.                                              |
| MCP Server                   | The Model Context Protocol server (`tavily`) that exposes the search tools the agent calls at runtime.                    |
