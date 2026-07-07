# Spotfire Copilot™ Agent Registry — Ecosystem Agents

**Ecosystem agents** are pre-built, framework-based A2A (Agent-to-Agent) agent servers — together with the Model Context Protocol (MCP) servers that back them — that you can deploy to give Spotfire Copilot ready-made, domain-targeted capabilities. They complement the [Agent Registry — Domain Agents](../Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md) container and the [Agent Registry Toolkit](../Spotfire%20Copilot%20Agent%20Registry%20Toolkit/Spotfire%20Copilot%20-%20Agent%20Registry%20Toolkit%20User%20Guide.md) you use to build your own.

Where the toolkit is about *building* custom agents, the ecosystem guides here are about *deploying* the agent servers and MCP servers that Cloud Software Group publishes as container images and Helm charts.

## How it fits together

There are two layers, deployed independently and wired together with URLs and tokens:

1. **Agent servers** — a DeepAgents server (built on LangChain and LangGraph) hosts one or more A2A agents (for example `osdu_agent`, `databricks_agent`, `snowflake_agent`) on a single endpoint. You register each agent with the Spotfire Copilot orchestrator so clients can invoke it. Two deployment variants are available: **OSS** (open-source LangGraph libraries) and **Licensed** (LangGraph Platform runtime).
2. **MCP servers** — each agent reaches its underlying system (OSDU, Databricks, Data Virtualization, Spotfire Library/License, Tavily, and others) through an MCP server that exposes tools over `streamable-http`. You deploy the MCP servers an agent needs, then point the agent at them with `*_MCP_SERVER_URL` settings.

These ecosystem agents depend on a deployed orchestrator. If you have not installed it yet, start with the [Installation Guide — Backend Setup](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md).

## Agent servers (LangGraph DeepAgents)

See [LangGraph DeepAgents Servers](LangGraph%20DeepAgents%20Servers/README.md) for the section index, or go directly to a variant:

- **[LangGraph DeepAgents Server — OSS Deployment Guide](LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md)** — deploy the custom DeepAgents server built on open-source LangGraph libraries, via Docker Compose or Helm.
- **[LangGraph DeepAgents Server — Licensed Deployment Guide](LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md)** — deploy the licensed DeepAgents runtime on the LangGraph Platform, via Helm.

## MCP servers

See [MCP Servers](MCP%20Servers/README.md) for the section index and glossary. Individual guides:

- [OSDU MCP Server](MCP%20Servers/Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20Deployment%20Guide.md)
- [Databricks MCP Server](MCP%20Servers/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Deployment%20Guide.md)
- [Data Virtualization (DV) MCP Server](MCP%20Servers/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20Deployment%20Guide.md)
- [Energy DDR Neo4j MCP Server](MCP%20Servers/Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20Deployment%20Guide.md)
- [Spotfire Library MCP Server](MCP%20Servers/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md)
- [Spotfire License MCP Server](MCP%20Servers/Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20Deployment%20Guide.md)
- [Tavily MCP Server](MCP%20Servers/Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20Deployment%20Guide.md)

## Shared reference

- **[Artifact Sources and Access](Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md)** — OCI registry login, artifact pull validation, and version selection policy shared by all guides in this section.

## Suggested order

1. Deploy the [MCP servers](MCP%20Servers/README.md) your agents need.
2. Deploy an agent server ([OSS](LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or [Licensed](LangGraph%20DeepAgents%20Servers/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md)) and point each agent at its MCP server URLs.
3. Register each agent endpoint with the orchestrator (see the agent server guide's *Registering A2A Agents with an Orchestrator* section).
