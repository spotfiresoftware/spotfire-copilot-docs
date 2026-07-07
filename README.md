# Spotfire Copilot™ Documentation

Spotfire Copilot™ is a generative-AI assistant embedded directly in Spotfire® Analyst and Web Player. It pairs a containerised backend **orchestrator** with a client-side **panel** so analysts can ask questions in natural language, build visualizations, query their data, and draw on curated knowledge bases (RAG).

Beyond these built-in capabilities, Spotfire Copilot is significantly enhanced by **external A2A (Agent-to-Agent) agents**. Through the Agent Registry you can develop and deploy your own agents — whether **use-case-targeted** (tuned to a specific domain, dataset, or workflow) or **general-purpose** — that give Copilot entirely new skills, tools, and data access. External agents are the primary way to extend what Copilot can do for your users, turning it from an out-of-the-box assistant into a platform tailored to your organisation.

This repository is the canonical home for the Spotfire Copilot documentation. The guides below are grouped by the component they cover. 
## Documentation index

### Backend services

The server-side orchestrator and its companion services. Located in [Spotfire Copilot Backend Services/](Spotfire%20Copilot%20Backend%20Services).

- **[Installation Guide — Backend Setup](Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md)** — Deploy the orchestrator: generate credentials, choose an LLM provider, configure the knowledge base, and deploy with Docker across Azure, GCP, AWS, or Kubernetes, followed by verification and post-deployment setup. *Applies to: Orchestrator Service (versions 2.3.0–2.3.5).*
- **[Admin Console Guide](Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Admin%20Console%20Guide.md)** — Day-to-day operation of the admin console for customer administrators: managing users, OAuth2 clients, conversations, RAG indexes, and system health. *Applies to: Admin Console (versions 2.3.0–2.3.4).*
- **[Data Loaders Installation Guide](Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Data%20Loaders%20Installation%20Guide.md)** — Install and configure the data-loader services that ingest documents into the knowledge base: image selection, LLM and embedding providers, supported vector databases, and document preparation. *Applies to: Data Loader Services (versions 2.3.0–2.3.4).*

### Client extension

The Copilot panel that runs inside Spotfire clients. Located in [Spotfire Copilot Client Extension/](Spotfire%20Copilot%20Client%20Extension).

- **[Installation Guide — Frontend Setup](Spotfire%20Copilot%20Client%20Extension/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Frontend%20Setup.md)** — Deploy and configure the Copilot client panel: package deployment, Copilot preferences, licensing, enabling the panel in Spotfire Analyst and Web Player, and first usage. *Applies to: Spotfire Copilot version 2.3.x.*

### Agent Registry

External agents are one of the most powerful ways to extend Spotfire Copilot. The Agent Registry lets you **host and build custom A2A (Agent-to-Agent) agents** — from narrowly use-case-targeted agents to general-purpose ones — that plug into the orchestrator and dramatically broaden what Copilot can do for your users.

- **[Agent Registry Installation Guide](Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md)** — Deploy the Agent Registry container that hosts A2A agents and exposes them to the orchestrator, both for administrators deploying to cloud or on-premise and for developers running it locally. *Applies to: Agent Registry Container (version 1.1.0). Located in [Spotfire Copilot Agent Registry - Domain Agents/](Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents).*
- **[Agent Registry Toolkit User Guide](Spotfire%20Copilot%20Agent%20Registry%20Toolkit/Spotfire%20Copilot%20-%20Agent%20Registry%20Toolkit%20User%20Guide.md)** — Build custom agents locally with the Agent Registry Toolkit and MCP development server: toolkit surface, the VS Code workflow, a full MCP tool and skill reference, and an end-to-end walkthrough. *Applies to: Agent Registry 1.1.0. Located in [Spotfire Copilot Agent Registry Toolkit/](Spotfire%20Copilot%20Agent%20Registry%20Toolkit).*
- **[Ecosystem Agents](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/README.md)** — Deploy pre-built, framework-based agent servers and the MCP servers that back them. Covers the [LangGraph DeepAgents Server](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/LangGraph%20DeepAgents%20Servers/README.md) guides (**OSS** and **Licensed** variants) and [MCP server](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/MCP%20Servers/README.md) deployment guides for OSDU, Databricks, Data Virtualization, Spotfire Library/License, Tavily, and more. *Located in [Spotfire Copilot Agent Registry - Ecosystem Agents/](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents).*

## Where to start

For a fresh deployment, the guides are typically followed in this order:

1. **[Backend Setup](Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md)** — stand up the orchestrator (required first).
2. **[Admin Console](Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Admin%20Console%20Guide.md)** — create users and OAuth2 clients, then operate and administer the deployment.
3. **[Data Loaders](Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Data%20Loaders%20Installation%20Guide.md)** — populate the knowledge base for RAG.
4. **[Frontend Setup](Spotfire%20Copilot%20Client%20Extension/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Frontend%20Setup.md)** — enable the Copilot panel in Spotfire clients.

To unlock Copilot's full potential with custom agents (strongly recommended):

5. **[Agent Registry Installation Guide](Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md)** — host A2A agents.
6. **[Agent Registry Toolkit User Guide](Spotfire%20Copilot%20Agent%20Registry%20Toolkit/Spotfire%20Copilot%20-%20Agent%20Registry%20Toolkit%20User%20Guide.md)** — build your own agents.
7. **[Ecosystem Agents](Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/README.md)** — deploy pre-built agent servers (LangGraph DeepAgents, OSS or Licensed) and their MCP servers for ready-made domain capabilities.
