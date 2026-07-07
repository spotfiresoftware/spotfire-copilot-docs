# MCP Servers

Deployment guides for the Model Context Protocol (MCP) servers published by Cloud Software Group. Each MCP server exposes a backend system (OSDU, Databricks, Data Virtualization, Spotfire Library/License, Tavily, and others) as MCP tools over `streamable-http`, so that ecosystem agents — and any MCP-capable client — can call them.

Deploy the MCP servers an agent needs first, then point the agent at them with the corresponding `*_MCP_SERVER_URL` settings in the [LangGraph DeepAgents Server](../LangGraph%20DeepAgents%20Servers/README.md) guides.

## Available guides

- [OSDU MCP Server](Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20Deployment%20Guide.md)
- [Databricks MCP Server](Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Deployment%20Guide.md)
- [Data Virtualization (DV) MCP Server](Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20Deployment%20Guide.md)
- [Energy DDR Neo4j MCP Server](Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20Deployment%20Guide.md)
- [Spotfire Library MCP Server](Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20Deployment%20Guide.md)
- [Spotfire License MCP Server](Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20Deployment%20Guide.md)
- [Tavily MCP Server](Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20Deployment%20Guide.md)

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
