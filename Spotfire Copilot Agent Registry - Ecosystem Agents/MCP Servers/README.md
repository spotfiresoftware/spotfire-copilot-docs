# MCP Servers

Guides for the Model Context Protocol (MCP) servers published by Cloud Software Group. Each MCP server exposes a backend system (OSDU, Databricks, Data Virtualization, Spotfire Library/License, Tavily, and others) as MCP tools over `streamable-http`, so that ecosystem agents — and any MCP-capable client — can call them.

Each server has its own subfolder containing two guides:

- a **User Guide** — the tools it exposes and how to consume them from an agent or MCP client, and
- a **Deployment Guide** — how to stand the server up (Docker Compose and Kubernetes/Helm).

Deploy the MCP servers an agent needs first, then point the agent at them with the corresponding `*_MCP_SERVER_URL` settings in the [Agent Server Deployment](../Agent%20Server%20Deployment/README.md) guides.

The **Used by** column shows which agent each server backs. For the full pairing with A2A agent ids and env prefixes, see the [section capability matrix](../README.md#capability-matrix).

## Available servers

| MCP server | Guides | Used by (agent) | Env prefix |
|---|---|---|---|
| OSDU | [User Guide](OSDU/Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20User%20Guide.md) · [Deployment Guide](OSDU/Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20Deployment%20Guide.md) | [OSDU Agent](../Agents/Spotfire%20Copilot%20-%20OSDU%20Agent%20User%20Guide.md) | `OSDU` |
| Databricks | [User Guide](Databricks/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20User%20Guide.md) · [Deployment Guide](Databricks/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Deployment%20Guide.md) | [Databricks Agent](../Agents/Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md) | `DATABRICKS` |
| Data Virtualization (DV) | [User Guide](Data%20Virtualization%20%28DV%29/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20User%20Guide.md) · [Deployment Guide](Data%20Virtualization%20%28DV%29/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20Deployment%20Guide.md) | [Data Virtualization (DV) Agent](../Agents/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20Agent%20User%20Guide.md) | `DV` |
| Energy DDR Neo4j | [User Guide](Energy%20DDR%20Neo4j/Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20User%20Guide.md) · [Deployment Guide](Energy%20DDR%20Neo4j/Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20Deployment%20Guide.md) | [Daily Drilling Reports (DDR) Agent](../Agents/Spotfire%20Copilot%20-%20Daily%20Drilling%20Reports%20%28DDR%29%20Agent%20User%20Guide.md) | `DDR` |
| Spotfire Library | [User Guide](Spotfire%20Library/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20User%20Guide.md) · [Deployment Guide](Spotfire%20Library/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md) | [Spotfire Library Metadata Agent](../Agents/Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md) | `SFLIB` |
| Spotfire License | [User Guide](Spotfire%20License/Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20User%20Guide.md) · [Deployment Guide](Spotfire%20License/Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20Deployment%20Guide.md) | [Spotfire License Management Agent](../Agents/Spotfire%20Copilot%20-%20Spotfire%20License%20Management%20Agent%20User%20Guide.md) | `SFLIC` |
| Tavily | [User Guide](Tavily/Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20User%20Guide.md) · [Deployment Guide](Tavily/Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20Deployment%20Guide.md) | [Tavily Web Search Agent](../Agents/Spotfire%20Copilot%20-%20Tavily%20Web%20Search%20Agent%20User%20Guide.md) | `TAVILY` |

> The `databricks-genie` (`GENIE`), `snowflake` (`SNOWFLAKE`), and `milvus` (`MILVUS`) agents use **External** MCP servers — consumed by the agent but not documented in this section. Deploy them from their own product documentation.

## Common notes

- Each guide covers Docker Compose and Kubernetes (Helm) deployment paths.
- Use OCI registry credentials that can pull image artifacts — see [Artifact Sources and Access](../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md).
- These guides standardize on the `streamable-http` MCP transport.

## Glossary

| Term | Definition |
|---|---|
| Base URL | Root URL for an external service API, without additional endpoint paths. |
| Bind Address | Network interface address where the server listens (for example `0.0.0.0`). |
| Server Listening Port | TCP port exposed by the MCP server process. |
| Transport | MCP protocol transport mode. These guides standardize on `streamable-http`. |
| OCI Image Reference | Full container image reference including registry, repository, and tag. |
| OAuth Client ID | Public identifier for an OAuth client integration. |
| OAuth Client Secret | Secret credential paired with an OAuth client ID. |
| Service Username / Password | Credentials used by the MCP server to authenticate to an external backend service. |
| API Key | Key-based credential used to authorize API calls to an external service. |
| Query Timeout | Maximum time allowed for an outbound backend query before timing out. |
| Readiness Mode | Policy controlling how strictly readiness checks depend on external systems. |
| Required = Yes | Must be set for the deployment to function. |
| Required = No | Optional. If omitted, default behavior is used. |
| Required = Conditional | Required only when a specific related setting or mode is enabled. |
| MCP Auth Enabled | Enables inbound authentication on MCP endpoints. |
| Static Bearer Tokens | Comma-separated tokens accepted directly by the MCP server. |
| Issuer URL | OAuth issuer identifier URL exposed in auth metadata. |
| Resource Server URL | Public URL representing the protected MCP resource server. |
| Required Scopes | Scope values that inbound access tokens must include. |
| JWKS URL | URL used to fetch public keys for JWT signature validation. |
| Audience (`aud`) | Optional JWT claim value used to restrict token audience. |
