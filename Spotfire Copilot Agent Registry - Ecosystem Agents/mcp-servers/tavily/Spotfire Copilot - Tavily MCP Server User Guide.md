# Tavily MCP Server — User Guide

web × search × news

The `tavily` MCP server exposes a curated set of tools for performing AI-powered web searches via the [Tavily](https://tavily.com) API — running general web searches with AI-extracted content, getting direct answers backed by sources, and querying recent news within a configurable time window.

## Table of Contents

- [Overview](#overview)
- [Deployment and Prerequisites](#deployment-and-prerequisites)
- [Connecting](#connecting)
- [Tool Reference](#tool-reference)
  - [General Web Search](#general-web-search)
  - [Direct Answer Search](#direct-answer-search)
  - [News Search](#news-search)
- [Example Payloads](#example-payloads)
- [Related Documentation](#related-documentation)

---

## Overview

This MCP server is the backend for the [Tavily Web Search Agent](../../agents/Spotfire%20Copilot%20-%20Tavily%20Web%20Search%20Agent%20User%20Guide.md). It wraps Tavily's search API behind a small set of focused tools:

- General web search with AI-extracted content.
- Answer-style search that returns a generated answer with supporting sources.
- News search with a configurable look-back window.
- Domain inclusion and exclusion on every search type.
- Configurable search depth (`basic` or `advanced`) on web and answer searches.

The server returns formatted text strings ready for an LLM (or human) to consume. Where applicable, the string includes a leading `Answer:` block (for answer search) and per-result `Title`, `URL`, `Content`, and `Published` fields. Domain filters accept a list of domain strings (e.g. `["nature.com", "nasa.gov"]`); a single string or comma-separated string is also accepted.

## Deployment and Prerequisites

This user guide describes how to *consume* the server's tools. To *deploy* it, follow the [Tavily MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20Deployment%20Guide.md). The server must be deployed and reachable before the Tavily Web Search Agent can be invoked.

## Connecting

| Setting          | Value                                                                    |
| ---------------- | ------------------------------------------------------------------------ |
| Transport        | `streamable-http` (recommended)                                          |
| URL              | Set via `TAVILY_MCP_SERVER_URL` (e.g. `https://mcp-tavily.example.com/mcp`) |
| Auth             | The server authenticates to Tavily using a configured API key (`TAVILY_API_KEY`); optional MCP-side auth via JWKS or token allowlist for clients. |

### Readiness modes

The server exposes `/healthz` plus a multi-mode `/readyz`, controlled by `TAVILY_READINESS_MODE`:

- `config_only` (default) — readiness only checks that `TAVILY_API_KEY` is present. Avoids consuming Tavily quota on Kubernetes probes.
- `strict_external` — readiness performs a live Tavily request and fails when Tavily is unreachable or quota-exceeded.
- `external_degraded_ok` — readiness performs a live Tavily request, but still returns ready (with `degraded_ready`) on transient or quota issues.

## Tool Reference

### General Web Search

#### `tavily_web_search`
- **Purpose:** Run a comprehensive web search with AI-extracted relevant content. Ideal for research, fact-finding, and gathering detailed information.
- **Inputs:**
  - `query` (str, required) — the search query.
  - `max_results` (int, optional, default `5`, max ~`20`) — number of results to return.
  - `search_depth` (str, optional, default `basic`) — `basic` (fast, cheaper) or `advanced` (more thorough).
  - `include_domains` (list[str] or str, optional) — restrict results to these domains.
  - `exclude_domains` (list[str] or str, optional) — exclude these domains from results.
- **Output:** A formatted string with `Detailed Results:` followed by `Title`, `URL`, and AI-extracted `Content` per result.
- **When to use:** Multi-source overviews, background research, and document discovery.

### Direct Answer Search

#### `tavily_answer_search`
- **Purpose:** Run a search and return a generated answer plus the supporting source list. Ideal for concrete questions where citations matter.
- **Inputs:**
  - `query` (str, required).
  - `max_results` (int, optional, default `5`, max ~`20`).
  - `search_depth` (str, optional, default `advanced`) — `basic` or `advanced`.
  - `include_domains` (list[str] or str, optional).
  - `exclude_domains` (list[str] or str, optional).
- **Output:** A formatted string with a leading `Answer:` block, followed by a `Sources:` list and then `Detailed Results:` per result.
- **When to use:** "What is X?", "How does Y work?", "Give me a concrete answer with citations."

### News Search

#### `tavily_news_search`
- **Purpose:** Search recent news articles with publication dates. Ideal for current-events questions and short-term tracking.
- **Inputs:**
  - `query` (str, required).
  - `max_results` (int, optional, default `5`, max ~`20`).
  - `days` (int, optional, default `3`, range `1`–`365`) — number of days back to search.
  - `include_domains` (list[str] or str, optional).
  - `exclude_domains` (list[str] or str, optional).
- **Output:** A formatted string with `Detailed Results:` per article, including a `Published` date alongside `Title`, `URL`, and `Content`.
- **When to use:** "Latest news on X", "Top headlines this week", "Recent announcements about Y".

## Example Payloads

### General web search with domain include/exclude

```json
{
  "name": "tavily_web_search",
  "arguments": {
    "input": {
      "query": "Anthropic Model Context Protocol overview",
      "max_results": 8,
      "search_depth": "advanced",
      "include_domains": ["anthropic.com", "modelcontextprotocol.io"],
      "exclude_domains": ["reddit.com"]
    }
  }
}
```

### Direct answer search with citations, excluding Wikipedia

```json
{
  "name": "tavily_answer_search",
  "arguments": {
    "input": {
      "query": "What is the average lifespan of redwood trees?",
      "max_results": 6,
      "search_depth": "advanced",
      "exclude_domains": ["wikipedia.org"]
    }
  }
}
```

### News search over the last 5 days

```json
{
  "name": "tavily_news_search",
  "arguments": {
    "input": {
      "query": "AI",
      "max_results": 10,
      "days": 5
    }
  }
}
```

## Related Documentation

- [Tavily MCP Server Deployment Guide](Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20Deployment%20Guide.md) — deploy this server.
- [Tavily Web Search Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Tavily%20Web%20Search%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
- [MCP Servers index](../README.md)
