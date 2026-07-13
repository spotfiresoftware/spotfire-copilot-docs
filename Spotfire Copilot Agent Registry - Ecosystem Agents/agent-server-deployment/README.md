# Agent Server Deployment

The ecosystem agents are **not** deployed one by one. They are hosted by a single **LangGraph DeepAgents server** — an agent harness in the LangChain ecosystem that hosts one or more A2A agents and executes stateful, multi-step workflows on the LangGraph runtime. A single server deployment can host **all** agents or any **subset** you choose to enable.

Two deployment variants are published. Choose the one that matches your licensing and runtime model:

- **[Spotfire Copilot — LangGraph DeepAgents Server (OSS) Deployment Guide](Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md)** — a custom DeepAgents server built directly on open-source (MIT-licensed) LangGraph libraries. Supports Docker Compose (image pull) and Kubernetes (Helm from OCI). Best when you want a self-contained server without the LangGraph Platform stack.
- **[Spotfire Copilot — LangGraph DeepAgents Server (Licensed) Deployment Guide](Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md)** — the licensed DeepAgents runtime packaged for the LangGraph Platform (`langgraph build` flow), deployed to Kubernetes with Helm. Adds platform runtime semantics and optional LangSmith tracing.

Both variants expose the same set of A2A agents and connect to the same [MCP servers](../mcp-servers/README.md) for tools and data access.

## See also

- [Artifact Sources and Access](../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy shared by these guides.
- [MCP Servers](../mcp-servers/README.md) — deploy the MCP backends each agent requires before enabling it.
