# Agent Registry for Spotfire®

The **Agent Registry for Spotfire®** is a centralized hub of AI agents that extend **Spotfire Copilot™** with industry-specific capabilities and ecosystem connectivity. Agents are served via the A2A protocol and registered directly with the Spotfire Copilot orchestrator.

The registry is delivered as two containers:

| Container | What it hosts |
|-----------|---------------|
| **Domain Agents Container** | Industry-vertical agents (including Well Recompletions) **and** the Agent Registry Toolkit for building and serving your own agents |
| **Platform Integrations Container** | The full suite of ecosystem integration agents (Databricks, Snowflake, OSDU, and more) |

Deploy either or both, depending on which agents you need.

## Table of Contents

- [Agent Registry Containers](#agent-registry-containers)
  - [Domain Agents Container](#domain-agents-container)
  - [Platform Integrations Container](#platform-integrations-container)
- [Agent Registry Toolkit](#agent-registry-toolkit)
- [MCP Enabled Agents](#mcp-enabled-agents)

---

## Agent Registry Containers

### Domain Agents Container

The Domain Agents Container does two things in one deployment:

1. **Ready-to-use industry agents**: ships with curated vertical agents, most notably the **Well Recompletions Agent**, a key agent for Oil & Gas customers analysing recompletion candidates directly from Spotfire
2. **Agent development with the Agent Registry Toolkit**: includes the **Agent Registry Toolkit**, which abstracts all Spotfire tool calls and provides high-level workflow templates, so teams can build and serve their own domain-specific agents in the same container without writing low-level agent infrastructure

This is the container to deploy if you need the Well Recompletions Agent, want to build custom agents, or both.

- [Setup and Deployment Guide: Domain Agents Container](Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md)

**Agents hosted in this container:**

*Energy:*
- [Agent for Well Recompletions](Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Agents/Spotfire%20Copilot%20-%20Well%20Recompletions%20Agent%20User%20Guide.md)

### Platform Integrations Container

The Platform Integrations Container comes pre-packaged with the full set of ecosystem integration agents and is designed for platform operators who want a production-ready rollout with minimal configuration. It supports Docker Compose for local and dev environments, and Kubernetes via Helm for production deployments.

Two deployment paths are available depending on your licensing model:

- [LangGraph DeepAgents Server — Licensed Deployment Guide](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md)
- [LangGraph DeepAgents Server — OSS Deployment Guide](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md)

**Agents hosted in this container:**

*Ecosystem Agents:*
- [Agent for OSDU™](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20OSDU%20Agent%20User%20Guide.md)
- [Agent for Spotfire® Data Virtualization](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20Agent%20User%20Guide.md)
- [Agent for Databricks](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md)
- [Agent for Databricks Genie](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Databricks%20Genie%20Agent%20User%20Guide.md)
- [Agent for Snowflake Cortex](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Snowflake%20Agent%20User%20Guide.md)
- [Agent for Spotfire® Server (Library)](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md)
- [Agent for Spotfire® Server (License Management)](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Spotfire%20License%20Management%20Agent%20User%20Guide.md)
- [Agent for Tavily](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Tavily%20Web%20Search%20Agent%20User%20Guide.md)

**Continuous Expansion:** The list of available agents will continue to grow as we expand vertical coverage and ecosystem integrations.

## Agent Registry Toolkit

The Agent Registry Toolkit provides everything needed to build agents that work natively with Spotfire Copilot: pre-built Spotfire tool abstractions, high-level workflow templates, and a guided developer experience via VS Code and GitHub Copilot.

**What the toolkit provides:**

- **Spotfire tool abstractions**: ready-made operations for filtering, marking rows, running SQL, and configuring visualisations, so you never write raw Spotfire API calls
- **High-level workflow templates**: structured patterns for multi-turn agent conversations, intent routing, and stage decomposition
- **Guided design and scaffolding**: a form-driven workflow in VS Code Copilot Chat for designing agents, generating stage stubs, and authoring prompts from a confirmed technical design
- **Built-in dry-run harness**: validates agent structure and exercises the full workflow loop without requiring a live Spotfire connection
- **MCP developer tools**: schema discovery, design review, and dry-run accessible directly from VS Code

The toolkit is the recommended path for any team building domain-specific agents on top of Spotfire Copilot.

- [Agent Registry Toolkit: Guide and Reference](Spotfire%20Copilot%20Agent%20Registry%20Toolkit/Spotfire%20Copilot%20-%20Agent%20Registry%20Toolkit%20User%20Guide.md)

## MCP Enabled Agents

In addition to the A2A container-based deployment, selected agents are also available via the **Model Context Protocol (MCP)**. This allows the same agent capabilities to be connected to any MCP-compatible client without going through the A2A container.

The following agents are currently available via MCP:

- [Agent for Daily Drilling Reports](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agents/Spotfire%20Copilot%20-%20Daily%20Drilling%20Reports%20%28DDR%29%20Agent%20User%20Guide.md)
- [All Ecosystem Agents (OSDU™, SDV, Databricks, Tavily and Spotfire® Server)](https://community.spotfire.com/articles/spotfire/mcp-enabled-agents-user-guide/)

Additional agents are being progressively exposed via MCP.

For deploying the MCP servers that back these agents, see the [MCP server deployment guides](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/mcp-servers/README.md).
