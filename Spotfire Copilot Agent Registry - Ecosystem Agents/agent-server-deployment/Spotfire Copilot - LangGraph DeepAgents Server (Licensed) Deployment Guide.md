# DeepAgents Licensed Deployment Guide (LangGraph Platform Runtime)

## Table of Contents

- [1. Introduction](#1-introduction)
  - [1.1 Purpose of This Document](#11-purpose-of-this-document)
  - [1.2 Scope](#12-scope)
  - [1.3 What DeepAgents Is (LangChain and LangGraph Context)](#13-what-deepagents-is-langchain-and-langgraph-context)
  - [1.4 Deployment Mode in This Guide (Important)](#14-deployment-mode-in-this-guide-important)
- [2. Deployment Mode and OSS Differences](#2-deployment-mode-and-oss-differences)
  - [2.1 Licensed Runtime Mode](#21-licensed-runtime-mode)
  - [2.2 Key Differences from OSS Server Deployment](#22-key-differences-from-oss-server-deployment)
- [3. Artifact Sources and Access](#3-artifact-sources-and-access)
  - [3.1 Registry Locations](#31-registry-locations)
  - [3.2 Prerequisites](#32-prerequisites)
  - [3.3 OCI Credentials and Login](#33-oci-credentials-and-login)
  - [3.4 Version Selection Policy](#34-version-selection-policy)
- [4. Runtime Agent Exposure](#4-runtime-agent-exposure)
  - [4.1 Licensed Agent Set](#41-licensed-agent-set)
  - [4.2 Notes](#42-notes)
- [5. Kubernetes Installation with Helm from OCI](#5-kubernetes-installation-with-helm-from-oci)
  - [5.1 App-Only Chart (Production Pattern)](#51-app-only-chart-production-pattern)
  - [5.2 Full Stack Chart (App + Postgres + Redis)](#52-full-stack-chart-app--postgres--redis)
- [6. Configuration Reference](#6-configuration-reference)
  - [6.1 Minimal `values.yaml` (App-Only)](#61-minimal-valuesyaml-app-only)
  - [6.2 Environment Variables Reference (Licensed Source .env)](#62-environment-variables-reference-licensed-source-env)
  - [6.3 Key Terms (Quick Reference)](#63-key-terms-quick-reference)
- [7. Post-Deploy Validation](#7-post-deploy-validation)
  - [7.1 Kubernetes Checks](#71-kubernetes-checks)
- [8. Upgrade](#8-upgrade)
- [9. Uninstall](#9-uninstall)
- [10. Troubleshooting](#10-troubleshooting)
- [11. Related Documentation](#11-related-documentation)


## 1. Introduction

### 1.1 Purpose of This Document

This guide explains how to deploy the licensed DeepAgents server using OCI-published container images and Helm charts.

### 1.2 Scope

This guide covers:

1. Kubernetes deployment using the app-only Helm chart
2. Kubernetes deployment using the stack Helm chart (app + PostgreSQL + Redis)
3. Runtime configuration, validation, upgrade, and uninstall

Note: This is a licensed LangGraph Platform runtime deployment guide for
DeepAgents. OSS library-based server deployment is covered separately in the [OSS deployment guide](Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md).

### 1.3 What DeepAgents Is (LangChain and LangGraph Context)

Deep Agents is an agent harness in the LangChain ecosystem.

- LangChain provides the core building blocks for model/tool agent loops.
- Deep Agents adds a batteries-included harness for complex multi-step tasks,
  including planning, subagents, and context management.
- LangGraph provides open-source orchestration/runtime libraries.

In this guide, deployment targets the licensed LangGraph Platform runtime
packaging for DeepAgents.

### 1.4 Deployment Mode in This Guide (Important)

This guide deploys the licensed DeepAgents runtime (LangGraph Platform image
and runtime behavior), not the OSS standalone server mode.

Why this distinction matters:

- This mode focuses on LangGraph Platform runtime behavior.
- Agent exposure is controlled by licensed graph configuration.
- Operational setup centers on platform persistence, MCP integrations, and optional tracing.

## 2. Deployment Mode and OSS Differences

### 2.1 Licensed Runtime Mode

This guide deploys the licensed DeepAgents runtime built for LangGraph Platform (`langgraph build` flow), published as:

- OCI image: `copilot-deepagents-server`
- Helm chart: `copilot-deepagents-server`
- Stack chart: `copilot-deepagents-server-stack`

### 2.2 Key Differences from OSS Server Deployment

This deployment mode is intentionally different from the OSS standalone server mode.

Key differences:

1. Licensed deployment uses LangGraph Platform runtime semantics.
2. Agent exposure is controlled by licensed graph configuration and runtime settings.
3. Runtime behavior is oriented around platform persistence and external MCP backend connectivity.
4. Optional tracing and observability are configured at deployment/runtime level when enabled.

## 3. Artifact Sources and Access

### 3.1 Registry Locations

- Registry host: `copilotoci.azurecr.io`
- Canonical artifact prefix: `spotfirecopilot`

Licensed artifact examples:

- Image: `copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server:<image-tag>`
- App chart: `oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server`
- Stack chart: `oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-stack`

### 3.2 Prerequisites

- Kubernetes 1.27+
- Helm 3.11+
- `kubectl`
- OCI pull credentials for `copilotoci.azurecr.io`
- LLM provider credentials for the selected `deepagentsModel`
- LangSmith API key provisioned for licensed deployment operations (required when LangSmith tracing is enabled)
- Required MCP servers must be installed, running, and reachable, with their URLs available for the corresponding `*_MCP_SERVER_URL` settings

If you deploy the app-only chart, managed PostgreSQL and Redis endpoints are required.

Before deploying this server, complete the relevant MCP server setup guides:

- [MCP server guide index](../mcp-servers/README.md)
- For each MCP dependency you plan to enable, follow its installation and user/tool guides first, then set `*_MCP_SERVER_URL` and credentials in this deployment.

### 3.3 OCI Credentials and Login

```bash
helm registry login copilotoci.azurecr.io
docker login copilotoci.azurecr.io
```

Validate chart and image pull access:

```bash
helm show chart oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server \
  --version <chart-version>

docker pull copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server:<image-tag>
```

### 3.4 Version Selection Policy

- Use operator-approved chart versions via `--version <chart-version>`.
- Use operator-approved image tags via chart values.
- Do not assume a fixed chart-to-image mapping unless your platform team publishes one.

## 4. Runtime Agent Exposure

### 4.1 Licensed Agent Set

Licensed runtime graph exposure is based on configured graphs. Current set:

- `osdu_agent`
- `databricks_agent`
- `databricks_genie_agent`
- `snowflake_agent`
- `dv_agent`
- `sf_lib_md_agent`
- `sf_lic_agent`
- `tavily_agent`
- `milvus_agent`
- `ddr_agent`

### 4.2 Notes

- Only configured and packaged graphs are exposed in licensed runtime.
- Each MCP-backed agent requires its corresponding MCP server URL and credentials.
- This runtime does not use OSS standalone agent selection variables.

## 5. Kubernetes Installation with Helm from OCI

Primary audience: platform operators.

Two chart choices are available:

1. `copilot-deepagents-server`: app only (recommended for production)
2. `copilot-deepagents-server-stack`: app + bundled Postgres + Redis (POC/dev)

### 5.1 App-Only Chart (Production Pattern)

Use this when PostgreSQL and Redis are managed externally.

#### 5.1.1 Create Values File (`values.yaml`)

Use the app-only example in Section 6.1 and adapt values for your environment.

#### 5.1.2 Install

```bash
helm upgrade --install deepagents \
  oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server \
  --version <chart-version> \
  --namespace deepagents \
  --create-namespace \
  -f values.yaml
```

### 5.2 Full Stack Chart (App + Postgres + Redis)

Use this when you want bundled PostgreSQL and Redis.

#### 5.2.1 Create Values File (`stack-values.yaml`)

```yaml
copilot-deepagents-server:
  image:
    registry: copilotoci.azurecr.io
    repository: spotfirecopilot/copilot-deepagents-server
    tag: "<image-tag>"

  config:
    deepagentsModel: "openai:gpt-5.1"
    osduMcpServerUrl: "https://mcp-osdu.example.com/mcp"

  secret:
    openaiApiKey: "<openai-key>"

postgresql:
  enabled: true

redis:
  enabled: true
```

#### 5.2.2 Install

```bash
helm upgrade --install deepagents \
  oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-stack \
  --version <chart-version> \
  --namespace deepagents \
  --create-namespace \
  -f stack-values.yaml
```

## 6. Configuration Reference

### 6.1 Minimal `values.yaml` (App-Only)

```yaml
image:
  registry: copilotoci.azurecr.io
  repository: spotfirecopilot/copilot-deepagents-server
  tag: "<image-tag>"

config:
  deepagentsModel: "openai:gpt-5.1"
  postgresUri: "postgres://USER:PASS@HOST:5432/DB?sslmode=require"
  redisUri: "redis://HOST:6379"

  osduMcpServerUrl: "https://mcp-osdu.example.com/mcp"
  osduMcpServerTransport: "streamable-http"

secret:
  openaiApiKey: "<openai-key>"
  mcpBearerToken: "<optional-global-mcp-token>"
  # Optional: outbound MCP auth via Keycloak client_credentials (aud=mcp).
  # When config.mcpClientId, secret.mcpClientSecret, and
  # config.keycloakTokenUrl are all set, the server mints fresh tokens per
  # request and the static *_MCP_BEARER_TOKEN values are ignored.
  # mcpClientSecret: "<keycloak-client-secret>"
```

### 6.2 Environment Variables Reference (Licensed Source .env)

The licensed runtime source uses `.env` conventions similar to these keys.

Quick-start minimum set:

- Always set `DEEPAGENTS_MODEL`.
- Set one provider key matching the selected model family:
  - `OPENAI_API_KEY` for `openai:*`
  - `ANTHROPIC_API_KEY` for `anthropic:*`
  - `GOOGLE_API_KEY` for `google:*`
- For each enabled agent integration, set its `*_MCP_SERVER_URL`.
- Set per-server `*_MCP_BEARER_TOKEN` values as required by your MCP backends, or set `MCP_BEARER_TOKEN` as a shared fallback.
- Alternatively, configure outbound Keycloak client_credentials by setting all three of `MCP_CLIENT_ID`, `MCP_CLIENT_SECRET`, and `KEYCLOAK_TOKEN_URL`. When these are present the server mints fresh `aud=mcp` tokens per request and the static `*_MCP_BEARER_TOKEN` values are ignored.
- Set `LANGSMITH_API_KEY` when `LANGSMITH_TRACING=true`.

Commonly optional:

- `LANGSMITH_TRACING` and `LANGSMITH_PROJECT`
- `*_MCP_SERVER_TRANSPORT` (defaults to `streamable-http` in most deployments)
- `*_MCP_ALLOW_DEGRADED_STARTUP` and timeout/retry tuning variables

| Variable | Required | Description | Example |
|---|---|---|---|
| DEEPAGENTS_MODEL | Yes | Model spec in `<provider>:<model>` format. | `openai:gpt-5.1` |
| OPENAI_API_KEY | Conditional | Required when using an OpenAI model. | `<openai-key>` |
| ANTHROPIC_API_KEY | Conditional | Required when using an Anthropic model. | `<anthropic-key>` |
| GOOGLE_API_KEY | Conditional | Required when using a Google model. | `<google-key>` |
| MCP_BEARER_TOKEN | No | Global fallback token for MCP backends. Ignored when the Keycloak minter is active (all three of `MCP_CLIENT_ID`, `MCP_CLIENT_SECRET`, `KEYCLOAK_TOKEN_URL` set). | `<mcp-token>` |
| MCP_CLIENT_ID | Conditional | Keycloak client_id for outbound MCP auth (`aud=mcp`). Required to enable the in-process token minter; must be set together with `MCP_CLIENT_SECRET` and `KEYCLOAK_TOKEN_URL`. | `mcp-clients` |
| MCP_CLIENT_SECRET | Conditional | Keycloak client_secret paired with `MCP_CLIENT_ID`. | `<secret>` |
| KEYCLOAK_TOKEN_URL | Conditional | Keycloak token endpoint used by the minter. | `https://keycloak.example.com/realms/master/protocol/openid-connect/token` |
| MCP_TOKEN_REFRESH_BEFORE_EXP_SECONDS | No | Seconds before token expiry at which the minter proactively refreshes. | `60` |
| MCP_TOKEN_MINT_TIMEOUT_SECONDS | No | HTTP timeout (seconds) for token-endpoint POST. | `10` |
| OSDU_MCP_SERVER_URL | Conditional | OSDU MCP endpoint for `osdu_agent`. | `https://mcp-osdu.example.com/mcp` |
| OSDU_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for OSDU MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<osdu-token>` |
| DATABRICKS_MCP_SERVER_URL | Conditional | Databricks MCP endpoint for `databricks_agent`. | `https://mcp-databricks.example.com/mcp` |
| DATABRICKS_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for Databricks MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<databricks-token>` |
| GENIE_MCP_SERVER_URL | Conditional | Databricks Genie MCP endpoint for `databricks_genie_agent`. | `https://mcp-databricks-genie.example.com/mcp` |
| GENIE_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for Databricks Genie MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<genie-token>` |
| DV_MCP_SERVER_URL | Conditional | DV MCP endpoint for `dv_agent`. | `https://mcp-dv.example.com/mcp` |
| DV_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for DV MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<dv-token>` |
| SFLIB_MCP_SERVER_URL | Conditional | Spotfire Library MCP endpoint for `sf_lib_md_agent`. | `https://mcp-spotfire-lib.example.com/mcp` |
| SFLIB_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for Spotfire Library MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<sflib-token>` |
| SFLIC_MCP_SERVER_URL | Conditional | Spotfire License MCP endpoint for `sf_lic_agent`. | `https://mcp-spotfire-lic.example.com/mcp` |
| SFLIC_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for Spotfire Licensing MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<sflic-token>` |
| TAVILY_MCP_SERVER_URL | Conditional | Tavily MCP endpoint for `tavily_agent`. | `https://mcp-tavily.example.com/mcp` |
| TAVILY_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for Tavily MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<tavily-token>` |
| MILVUS_MCP_SERVER_URL | Conditional | Milvus MCP endpoint for `milvus_agent`. | `https://mcp-milvus.example.com/mcp` |
| MILVUS_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for Milvus MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<milvus-token>` |
| DDR_MCP_SERVER_URL | Conditional | DDR Neo4j MCP endpoint for `ddr_agent`. | `https://mcp-energy-ddr-neo4j.example.com/mcp` |
| DDR_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for DDR MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<ddr-token>` |
| SNOWFLAKE_MCP_SERVER_URL | Conditional | Snowflake MCP endpoint for `snowflake_agent`. | `https://mcp-snowflake.example.com/mcp` |
| SNOWFLAKE_MCP_BEARER_TOKEN | Conditional | Per-server bearer token for Snowflake MCP; falls back to `MCP_BEARER_TOKEN` if unset. | `<snowflake-token>` |
| <PREFIX>_MCP_SERVER_TRANSPORT | No | Transport mode for an enabled MCP integration. | `streamable-http` |
| <PREFIX>_MCP_ALLOW_DEGRADED_STARTUP | No | Allows startup to continue if that MCP backend is unavailable. | `false` |
| <PREFIX>_MCP_CALL_TIMEOUT | No | Per-tool call timeout in seconds. | `60` |
| <PREFIX>_MCP_INIT_TIMEOUT | No | MCP session initialize timeout in seconds. | `10` |
| <PREFIX>_MCP_CONNECT_TIMEOUT | No | HTTP connect timeout in seconds. | `5` |
| <PREFIX>_MCP_READ_TIMEOUT | No | HTTP read timeout in seconds. | `30` |
| <PREFIX>_MCP_INIT_RETRY_COUNT | No | Retry count for MCP initialization. | `3` |
| <PREFIX>_MCP_INIT_RETRY_BACKOFF_SECONDS | No | Retry backoff factor for MCP initialization. | `0.5` |
| <PREFIX>_MCP_SCHEMA_TTL_SECONDS | No | MCP tools schema cache TTL in seconds. | `300` |
| LANGSMITH_TRACING | No | Enables LangSmith tracing when `true`. | `true` |
| LANGSMITH_API_KEY | Conditional | Obtain this key for licensed deployments; required at runtime when `LANGSMITH_TRACING=true`. | `<langsmith-key>` |
| LANGSMITH_PROJECT | No | LangSmith project name. | `deepagents-workspace` |

Supported `<PREFIX>` values in this guide: `OSDU`, `DATABRICKS`, `GENIE`, `SNOWFLAKE`, `DV`, `SFLIB`, `SFLIC`, `TAVILY`, `MILVUS`, `DDR`.

### 6.3 Key Terms (Quick Reference)

| Term | Meaning in this guide |
|---|---|
| Base URL | Root URL of an external backend API used by the server. |
| Transport | MCP protocol transport mode. This guide uses `streamable-http`. |
| Required = Yes | Must be set for the deployment to function correctly. |
| Required = No | Optional; default behavior is used when omitted. |
| Required = Conditional | Required only when a related mode/setting is enabled. |

## 7. Post-Deploy Validation

### 7.1 Kubernetes Checks

```bash
kubectl -n deepagents get pods
kubectl -n deepagents get svc
kubectl -n deepagents logs -l app.kubernetes.io/instance=deepagents --tail=200
```

Validation goals:

1. Pods become `Ready`.
2. No startup failures in logs for model credentials.
3. Enabled MCP backends connect without repeated initialization failures.

## 8. Upgrade

```bash
helm upgrade deepagents \
  oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server \
  --version <new-chart-version> \
  -n deepagents \
  -f values.yaml
```

## 9. Uninstall

```bash
helm uninstall deepagents -n deepagents
```

If you deployed the stack chart and want to remove persisted state, also delete related PVCs for that release.

## 10. Troubleshooting

1. Image/chart pull failures:
  - Confirm registry credentials were provided and logins succeeded.
  - Verify pull permission for `spotfirecopilot/copilot-deepagents-server*`.
  - Verify repository path and selected chart/image version.

2. Runtime startup failures:
  - Verify provider credentials for the selected `deepagentsModel`.
  - Verify `postgresUri` and `redisUri` connectivity and credentials.

3. Enabled agent has no tools:
  - Verify each enabled agent has corresponding `*_MCP_SERVER_URL` and token values.
  - Verify bearer token and transport configuration (`streamable-http`).

4. MCP backends intermittently time out:
  - Increase per-prefix MCP timeout and retry tunables (`*_MCP_CALL_TIMEOUT`, `*_MCP_READ_TIMEOUT`, `*_MCP_INIT_RETRY_COUNT`).

## 11. Related Documentation

- [OSS deployment guide](Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) — deploy the open-source LangGraph library-based server instead of the licensed runtime.
- [MCP Servers](../mcp-servers/README.md) — deployment guides for each backend dependency you enable.
- [Artifact Sources and Access](../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version selection policy.
- [Agent Registry Installation Guide](../../Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md) and [Installation Guide — Backend Setup](../../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md) — orchestrator deployment and A2A agent registration.