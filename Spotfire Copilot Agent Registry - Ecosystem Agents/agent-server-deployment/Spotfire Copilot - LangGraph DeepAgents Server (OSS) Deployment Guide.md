# DeepAgents OSS Deployment Guide (Built with LangChain + Open-Source LangGraph Libraries)

## Table of Contents

- [1. Introduction](#1-introduction)
  - [1.1 Purpose of This Document](#11-purpose-of-this-document)
  - [1.2 Scope](#12-scope)
  - [1.3 What DeepAgents Is (LangChain and LangGraph Context)](#13-what-deepagents-is-langchain-and-langgraph-context)
  - [1.4 Deployment Mode in This Guide (Important)](#14-deployment-mode-in-this-guide-important)
- [2. Artifact Sources and Access](#2-artifact-sources-and-access)
  - [2.1 Registry Locations](#21-registry-locations)
  - [2.2 Prerequisites](#22-prerequisites)
  - [2.3 OCI Credentials and Login](#23-oci-credentials-and-login)
  - [2.4 Version Selection Policy](#24-version-selection-policy)
- [3. Runtime Agent Selection](#3-runtime-agent-selection)
  - [3.1 Available Agents](#31-available-agents)
  - [3.2 Selection Notes and Precedence](#32-selection-notes-and-precedence)
  - [3.3 Selection Examples](#33-selection-examples)
- [4. Docker Compose Installation (OCI Image Pull)](#4-docker-compose-installation-oci-image-pull)
  - [4.1 Create a Deployment Folder](#41-create-a-deployment-folder)
  - [4.2 Create `.env`](#42-create-env)
  - [4.3 Create `docker-compose.yml`](#43-create-docker-composeyml)
  - [4.4 Start Stack](#44-start-stack)
  - [4.5 Environment Variables Reference (.env)](#45-environment-variables-reference-env)
  - [4.6 Per-Agent MCP Variables (Explicit Names)](#46-per-agent-mcp-variables-explicit-names)
  - [4.7 Verify](#47-verify)
  - [4.8 Stop](#48-stop)
- [5. Kubernetes Installation with Helm from OCI](#5-kubernetes-installation-with-helm-from-oci)
  - [5.1 App-Only Chart (Production Pattern)](#51-app-only-chart-production-pattern)
  - [5.2 Full Stack Chart (App + Postgres + Redis)](#52-full-stack-chart-app--postgres--redis)
- [6. Cloud Overlay Usage (When Needed)](#6-cloud-overlay-usage-when-needed)
- [7. Registering A2A Agents with an Orchestrator](#7-registering-a2a-agents-with-an-orchestrator)
  - [7.1 A2A Endpoint Pattern](#71-a2a-endpoint-pattern)
  - [7.2 Registration Inputs](#72-registration-inputs)
  - [7.3 Recommended Flow](#73-recommended-flow)
  - [7.4 Connectivity Pre-Check](#74-connectivity-pre-check)
- [8. Post-Deploy Validation (Docker Compose and Kubernetes)](#8-post-deploy-validation-docker-compose-and-kubernetes)
  - [8.1 Docker Compose Installation](#81-docker-compose-installation)
  - [8.2 Kubernetes Installation](#82-kubernetes-installation)
- [9. Upgrade](#9-upgrade)
  - [9.1 Docker Compose Installation](#91-docker-compose-installation)
  - [9.2 Kubernetes Installation](#92-kubernetes-installation)
- [10. Uninstall](#10-uninstall)
  - [10.1 Docker Compose Installation](#101-docker-compose-installation)
  - [10.2 Kubernetes Installation](#102-kubernetes-installation)
- [11. Troubleshooting](#11-troubleshooting)
- [12. Security Notes](#12-security-notes)


## 1. Introduction

### 1.1 Purpose of This Document

This guide explains how to deploy the DeepAgents OSS server using container images and Helm charts published in OCI.

> 📺 **Video walkthrough:** [Deploy a Databricks MCP server and the DeepAgents (OSS) agent server that hosts it](https://youtu.be/C3DbxVsfdqk) — a hands-on companion to this guide that deploys the OSS agent server with a single agent (Databricks) enabled and wires it to its MCP server.

### 1.2 Scope

This guide covers:

1. Docker Compose deployment using a prebuilt image pull
2. Kubernetes deployment using Helm charts published to OCI

Note: This is an OSS library-based deployment guide for a custom DeepAgents
server. LangSmith/LangGraph Agent Server platform deployment is covered separately in the [Licensed deployment guide](Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).

### 1.3 What DeepAgents Is (LangChain and LangGraph Context)

Deep Agents is an agent harness in the LangChain ecosystem.

- LangChain provides the core building blocks for model/tool agent loops.
- Deep Agents adds a batteries-included harness for complex multi-step tasks,
  including planning, subagents, and context management.
- LangGraph provides open-source orchestration/runtime libraries (including the
  Pregel runtime) used to execute stateful agent workflows.

In short: this deployment runs a Deep Agents application built on LangChain
building blocks and open-source LangGraph libraries.

### 1.4 Deployment Mode in This Guide (Important)

This guide deploys a custom DeepAgents OSS server that uses open-source
LangGraph libraries directly.

It does not deploy the full LangSmith/LangGraph Agent Server platform stack
(assistants/threads/runs control-plane style deployment).

Why this distinction matters:

- LangGraph itself is open source (MIT-licensed) and free to use.
- LangSmith deployment modes include additional platform/runtime components
  and licensing flows that are outside the scope of this guide.

## 2. Artifact Sources and Access

### 2.1 Registry Locations

- Registry host: `copilotoci.azurecr.io`
- Canonical chart/image path prefix: `spotfirecopilot`

Example image:

- `copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss:<image-tag>`

Example Helm charts:

- `oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss`
- `oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss-stack`

### 2.2 Prerequisites

For local Docker Compose installation:

- Docker 24+ with Compose plugin (`docker compose`)

For Kubernetes installation:

- Kubernetes 1.27+ cluster
- `kubectl`
- Helm 3.11+

Required for both installation paths:

- OCI registry read credentials for `copilotoci.azurecr.io`
- Access to an LLM provider and model, with required credentials (for example OpenAI with `DEEPAGENTS_MODEL=openai:gpt-5.1` and `OPENAI_API_KEY`)
- At least one A2A authentication token/key based on your configured `A2A_AUTH_MODE`
- Required MCP servers must be installed, running, and reachable, with their URLs available for the corresponding `*_MCP_SERVER_URL` settings

Before deploying this server, complete the relevant MCP server setup guides:

- [MCP server guide index](../mcp-servers/README.md)
- For each MCP dependency you plan to enable, follow its installation and user/tool guides first, then set `*_MCP_SERVER_URL` and credentials in this deployment.

### 2.3 OCI Credentials and Login

Before running any deployment command, provide credentials that can pull artifacts from `copilotoci.azurecr.io`.

Required credentials:

- Registry username
- Registry password or access token

Login commands:

```bash
# Helm chart pull auth
helm registry login copilotoci.azurecr.io

# Container image pull auth
docker login copilotoci.azurecr.io
```

Validate that artifact pulls work with your credentials:

```bash
# Pull chart metadata
helm show chart oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss \
  --version <chart-version>

# Pull container image
docker pull copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss:<image-tag>
```

### 2.4 Version Selection Policy

This guide uses operator-selected versions.

- Choose the chart version approved for your environment and pass it via `--version <chart-version>`.
- Choose the image tag approved for your environment and set it in values or compose.
- Do not assume a fixed chart-to-image matrix unless your platform team publishes one.

## 3. Runtime Agent Selection

### 3.1 Available Agents

This server image currently exposes these agent IDs at runtime:

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

### 3.2 Selection Notes and Precedence

Notes:

- Agent IDs are the values used in `AGENTS_ENABLED`, `AGENTS_DISABLED`, and A2A endpoints.

Selection precedence (first non-empty wins):

1. `AGENTS_CONFIG_FILE` (YAML mapping with per-agent overrides)
2. `AGENTS_ENABLED` (CSV allow-list)
3. `AGENTS_DISABLED` (CSV deny-list)
4. default (all available agents enabled)

### 3.3 Selection Examples

Docker Compose (`.env`):

```env
# Serve only OSDU + DV
AGENTS_ENABLED=osdu_agent,dv_agent

# Alternative deny-list mode (if AGENTS_ENABLED is empty)
# AGENTS_DISABLED=milvus_agent

# Highest-precedence file mode
# AGENTS_CONFIG_FILE=/etc/deepagents/agents.yaml
```

Helm values (`my-values.yaml`):

```yaml
config:
  # Use one mode at a time. agentsConfigFile takes precedence.
  agentsEnabled: "osdu_agent,dv_agent"
  # agentsDisabled: "milvus_agent"
  # agentsConfigFile: "/etc/deepagents/agents.yaml"
```

## 4. Docker Compose Installation (OCI Image Pull)

Primary audience: app teams.

This option is best for local dev/test and small non-production environments.

> Ready-to-use [`docker-compose.yml`](docker-compose.yml) and [`.env.example`](.env.example) are provided alongside this guide in the same folder. Copy [`.env.example`](.env.example) to `.env`, fill in your values (including `AGENT_IMAGE_REF`), deploy the required MCP server stacks first (see [`../mcp-servers/`](../mcp-servers/)), then run `docker compose up -d`.

### 4.1 Create a Deployment Folder

```bash
mkdir -p deepagents-oss-deploy
cd deepagents-oss-deploy
```

### 4.2 Create `.env`

Use this as a minimal starting point:

```env
AGENT_IMAGE_REF=copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss:<image-tag>
HOST=0.0.0.0
PORT=8000
LOG_LEVEL=INFO
PUBLIC_BASE_URL=http://localhost:8000

POSTGRES_URL=postgresql://postgres:postgres@deepagents-oss-postgres:5432/deepagents_checkpoints
REDIS_URL=redis://deepagents-oss-redis:6379/0

A2A_AUTH_MODE=bearer
A2A_AUTH_PUBLIC_CARD=true
A2A_BEARER_TOKENS=change-me-token-1,change-me-token-2

# LLM: public OpenAI (default).
OPENAI_API_KEY=replace-me
DEEPAGENTS_MODEL=openai:gpt-5.1
# For Azure OpenAI, comment out the two lines above and use these instead
# (the value after the colon is the Azure DEPLOYMENT name, not the model name):
# DEEPAGENTS_MODEL=azure_openai:my-gpt5-deployment
# AZURE_OPENAI_ENDPOINT=https://<resource>.openai.azure.com
# AZURE_OPENAI_API_KEY=replace-me
# OPENAI_API_VERSION=2024-10-21
# DEEPAGENTS_MODEL_PROVIDER is optional and usually unnecessary — the azure_openai:
# prefix already selects Azure. Only set it to "azure" to force Azure when
# DEEPAGENTS_MODEL has NO provider prefix (a bare deployment name).
# DEEPAGENTS_MODEL_PROVIDER=azure

# Enable only the agents you need.
AGENTS_ENABLED=osdu_agent

# Example MCP backend for osdu agent (optional)
# OSDU_MCP_SERVER_URL=https://mcp-osdu.<your-host>/mcp
# OSDU_MCP_BEARER_TOKEN=replace-me
# OSDU_MCP_SERVER_TRANSPORT=streamable-http

# Optional: outbound MCP auth via Keycloak client_credentials (aud=mcp).
# When MCP_CLIENT_ID, MCP_CLIENT_SECRET, and KEYCLOAK_TOKEN_URL are all set,
# the server mints fresh tokens per request and the static *_MCP_BEARER_TOKEN
# values above are ignored. Leave all three blank to keep using static tokens.
# MCP_CLIENT_ID=mcp-clients
# MCP_CLIENT_SECRET=replace-me
# KEYCLOAK_TOKEN_URL=https://keycloak.example.com/realms/master/protocol/openid-connect/token
```

### 4.3 Create `docker-compose.yml`

This compose file uses only OCI image pulls (no local build):

```yaml
name: deepagents-oss

volumes:
  deepagents-oss-postgres-data:

services:
  deepagents-oss-redis:
    image: redis:7-alpine
    ports:
      - "6390:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 2s
      retries: 5

  deepagents-oss-postgres:
    image: postgres:16
    ports:
      - "5443:5432"
    environment:
      POSTGRES_DB: deepagents_checkpoints
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - deepagents-oss-postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d deepagents_checkpoints"]
      interval: 5s
      timeout: 2s
      retries: 10
      start_period: 10s

  deepagents-oss:
    image: ${AGENT_IMAGE_REF}
    # Image is built for linux/amd64; pin platform so it runs under emulation
    # on Apple Silicon (arm64) hosts. Override with AGENT_PLATFORM if needed.
    platform: ${AGENT_PLATFORM:-linux/amd64}
    depends_on:
      deepagents-oss-redis:
        condition: service_healthy
      deepagents-oss-postgres:
        condition: service_healthy
    ports:
      - "8000:8000"
    env_file:
      - .env
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/healthz"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 15s
```

### 4.4 Start Stack

```bash
docker compose up -d
```

If your local Docker daemon is not logged in to `copilotoci.azurecr.io`, image pull will fail with authentication errors.

### 4.5 Environment Variables Reference (.env)

The following table is derived from the OSS environment template published with this deployment and adapted to use `.env` naming for this guide.

Quick-start minimum set:

- Set core server runtime variables: `HOST`, `PORT`, `PUBLIC_BASE_URL`, `POSTGRES_URL`, `REDIS_URL`.
- Always set `DEEPAGENTS_MODEL`.
- Set one provider key matching the selected model family:
  - `OPENAI_API_KEY` for `openai:*`
  - `ANTHROPIC_API_KEY` for `anthropic:*`
  - `GOOGLE_API_KEY` for `google:*`
  - Azure OpenAI: set `DEEPAGENTS_MODEL=azure_openai:<deployment-name>` (the value after the colon is the Azure **deployment** name, not the model name) plus `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, and `OPENAI_API_VERSION`.
- Optional per-agent override: prefix any model variable with an agent's MCP prefix to change just that agent (same convention as `<PREFIX>_MCP_SERVER_URL`). For example, keep the fleet on OpenAI but move only `osdu_agent` to Azure by setting `OSDU_DEEPAGENTS_MODEL=azure_openai:<deployment>` (the `AZURE_*` vars are shared globally, or can be overridden as `OSDU_AZURE_OPENAI_*`). Prefixes: `OSDU`, `DATABRICKS`, `GENIE`, `DV`, `SFLIB`, `SFLIC`, `TAVILY`, `MILVUS`, `DDR`, `SUPPORT`, `SNOWFLAKE`. and set matching credentials (for example `A2A_BEARER_TOKENS` for `bearer`).
- For each enabled agent integration, set `*_MCP_SERVER_URL`.
- Set per-server `*_MCP_BEARER_TOKEN` values as required by your MCP backends, or set `MCP_BEARER_TOKEN` as a shared fallback.
- Alternatively, configure outbound Keycloak client_credentials by setting all three of `MCP_CLIENT_ID`, `MCP_CLIENT_SECRET`, and `KEYCLOAK_TOKEN_URL`. When these are present the server mints fresh `aud=mcp` tokens per request and the static `*_MCP_BEARER_TOKEN` values are ignored.

Commonly optional:

- `AGENTS_CONFIG_FILE` / `AGENTS_ENABLED` / `AGENTS_DISABLED` (depending on selection strategy)
- `A2A_AUTH_PUBLIC_CARD`
- `*_MCP_SERVER_TRANSPORT` (defaults to `streamable-http` in most deployments)
- `*_MCP_ALLOW_DEGRADED_STARTUP` and timeout/retry tuning variables

| Variable | Required | Description | Example |
|---|---|---|---|
| AGENT_IMAGE_REF | Yes | Full OCI image reference (registry/repository:tag) for the DeepAgents server, consumed by the compose `image:` field. | `copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss:<image-tag>` |
| HOST | Yes | Bind address for the server. | `0.0.0.0` |
| PORT | Yes | HTTP listening port. | `8000` |
| LOG_LEVEL | No | Application log level. | `INFO` |
| PUBLIC_BASE_URL | Yes | Public base URL used in A2A AgentCards. Must be reachable by clients. | `https://deepagents.example.com` |
| AGENTS_CONFIG_FILE | No | Optional path to agent configuration file inside container. | `/etc/deepagents/agents.yaml` |
| AGENTS_ENABLED | Conditional | Comma-separated allow-list of agents. Required if you want explicit allow-list behavior. | `osdu_agent,dv_agent` |
| AGENTS_DISABLED | No | Comma-separated deny-list of agents. | `milvus_agent` |
| POSTGRES_URL | Yes | PostgreSQL URL for checkpoints and resumability. | `postgresql://postgres:postgres@deepagents-oss-postgres:5432/deepagents_checkpoints` |
| REDIS_URL | Yes | Redis URL for locks and streaming fan-out in multi-replica scenarios. | `redis://deepagents-oss-redis:6379/0` |
| A2A_AUTH_MODE | Yes | A2A auth mode: `none`, `apikey`, `bearer`, `oidc`, `mtls`. | `bearer` |
| A2A_AUTH_PUBLIC_CARD | No | Expose agent cards without auth when `true`. | `true` |
| A2A_BEARER_TOKENS | Conditional | CSV of bearer tokens when `A2A_AUTH_MODE=bearer`. Required unless token file is used. | `token-1,token-2` |
| A2A_BEARER_TOKEN_FILE | Conditional | Path to file containing bearer tokens (one per line), alternative to `A2A_BEARER_TOKENS`. | `/etc/deepagents/bearer-tokens` |
| A2A_API_KEY_HEADER | Conditional | Header name for API-key mode (`A2A_AUTH_MODE=apikey`). | `X-API-Key` |
| A2A_API_KEYS | Conditional | CSV of API keys when `A2A_AUTH_MODE=apikey`. | `key-1,key-2` |
| A2A_OIDC_ISSUER | Conditional | OIDC issuer URL when `A2A_AUTH_MODE=oidc`. | `https://issuer.example.com/` |
| A2A_OIDC_AUDIENCE | Conditional | Expected OIDC audience. | `deepagents-oss` |
| A2A_OIDC_JWKS_URL | Conditional | JWKS URL when `A2A_AUTH_MODE=oidc`. | `https://issuer.example.com/.well-known/jwks.json` |
| A2A_MTLS_CLIENT_DN_HEADER | Conditional | Header carrying client DN when `A2A_AUTH_MODE=mtls`. | `X-Client-Cert-DN` |
| A2A_THREAD_LOCK_TTL_SECONDS | No | TTL for per-thread lock in seconds. | `60` |
| A2A_THREAD_LOCK_WAIT_SECONDS | No | Max wait to acquire per-thread lock. | `5.0` |
| MCP_TOOLS_CACHE_TTL_SECONDS | No | TTL for cached MCP tool descriptors. | `300` |
| JWKS_CACHE_TTL_SECONDS | No | TTL for cached OIDC JWKS. | `600` |
| OPENAI_API_KEY | Conditional | Required when using `DEEPAGENTS_MODEL=openai:*`. | `<openai-key>` |
| ANTHROPIC_API_KEY | Conditional | Required when using `DEEPAGENTS_MODEL=anthropic:*`. | `<anthropic-key>` |
| GOOGLE_API_KEY | Conditional | Required when using `DEEPAGENTS_MODEL=google:*`. | `<google-key>` |
| DEEPAGENTS_MODEL | Yes | Model spec as `<provider>:<model>`. Use `openai:<model>` for public OpenAI or `azure_openai:<deployment-name>` for Azure OpenAI (the value after the colon is the Azure deployment name). | `openai:gpt-5.1` |
| DEEPAGENTS_MODEL_PROVIDER | No | Optional. Not needed when `DEEPAGENTS_MODEL` uses the `azure_openai:` prefix. Only set to `azure` to force the Azure path when `DEEPAGENTS_MODEL` has no provider prefix (a bare deployment name). | `azure` |
| AZURE_OPENAI_ENDPOINT | Conditional | Azure OpenAI resource endpoint. Required when `DEEPAGENTS_MODEL=azure_openai:*`. | `https://<resource>.openai.azure.com` |
| AZURE_OPENAI_API_KEY | Conditional | Azure OpenAI API key. Required when `DEEPAGENTS_MODEL=azure_openai:*` (unless using Azure AD). | `<azure-openai-key>` |
| OPENAI_API_VERSION | Conditional | Azure OpenAI API version. Required when `DEEPAGENTS_MODEL=azure_openai:*`. `AZURE_OPENAI_API_VERSION` is also accepted. | `2024-10-21` |
| MCP_BEARER_TOKEN | No | Global fallback bearer token for MCP servers when per-server token is not set. | `shared-mcp-token` |
| MCP_CLIENT_ID | Conditional | Keycloak client_id for outbound MCP auth (`aud=mcp`). Required to enable the in-process token minter; must be set together with `MCP_CLIENT_SECRET` and `KEYCLOAK_TOKEN_URL`. | `mcp-clients` |
| MCP_CLIENT_SECRET | Conditional | Keycloak client_secret paired with `MCP_CLIENT_ID`. | `<secret>` |
| KEYCLOAK_TOKEN_URL | Conditional | Keycloak token endpoint used by the minter. | `https://keycloak.example.com/realms/master/protocol/openid-connect/token` |
| MCP_TOKEN_REFRESH_BEFORE_EXP_SECONDS | No | Seconds before token expiry at which the minter proactively refreshes. | `60` |
| MCP_TOKEN_MINT_TIMEOUT_SECONDS | No | HTTP timeout (seconds) for token-endpoint POST. | `10` |
| <PREFIX>_MCP_SERVER_URL | Conditional | MCP server URL for an enabled agent integration. Required to load that integration's tools. | `OSDU_MCP_SERVER_URL=https://mcp-osdu.example.com/mcp` |
| <PREFIX>_MCP_BEARER_TOKEN | Conditional | Per-server bearer token; falls back to `MCP_BEARER_TOKEN` if unset. Ignored when the Keycloak minter is active (all three of `MCP_CLIENT_ID`, `MCP_CLIENT_SECRET`, `KEYCLOAK_TOKEN_URL` set). | `OSDU_MCP_BEARER_TOKEN=<token>` |
| <PREFIX>_MCP_SERVER_TRANSPORT | No | MCP transport. | `streamable-http` |
| <PREFIX>_MCP_ALLOW_DEGRADED_STARTUP | No | Allow startup to continue when that MCP integration fails to initialize. | `false` |
| <PREFIX>_MCP_CALL_TIMEOUT | No | Per-tool call timeout (seconds). | `60` |
| <PREFIX>_MCP_INIT_TIMEOUT | No | MCP initialize timeout (seconds). | `10` |
| <PREFIX>_MCP_CONNECT_TIMEOUT | No | MCP connect timeout (seconds). | `5` |
| <PREFIX>_MCP_READ_TIMEOUT | No | MCP stream read timeout (seconds). | `30` |
| <PREFIX>_MCP_INIT_RETRY_COUNT | No | Retry count for tool-list initialization. | `3` |
| <PREFIX>_MCP_INIT_RETRY_BACKOFF_SECONDS | No | Retry backoff factor for initialization. | `0.5` |
| <PREFIX>_MCP_SCHEMA_TTL_SECONDS | No | Tool-schema cache TTL in seconds. | `300` |

Supported MCP prefixes in the template:

- `OSDU`, `DATABRICKS`, `GENIE`, `SNOWFLAKE`, `DV`, `SFLIB`, `SFLIC`, `TAVILY`, `MILVUS`, `DDR`, `SUPPORT`

### 4.6 Per-Agent MCP Variables (Explicit Names)

Use this table when you want concrete variable names instead of `<PREFIX>` patterns.

| Variable | Required | Description | Example |
|---|---|---|---|
| OSDU_MCP_SERVER_URL | Conditional | OSDU MCP endpoint URL when `osdu_agent` is enabled. | `https://mcp-osdu.example.com/mcp` |
| OSDU_MCP_BEARER_TOKEN | Conditional | Bearer token for OSDU MCP. | `<token>` |
| OSDU_MCP_SERVER_TRANSPORT | No | OSDU MCP transport. | `streamable-http` |
| OSDU_MCP_CALL_TIMEOUT | No | OSDU per-call timeout seconds. | `60` |
| DATABRICKS_MCP_SERVER_URL | Conditional | Databricks MCP endpoint URL when `databricks_agent` is enabled. | `https://mcp-databricks.example.com/mcp` |
| DATABRICKS_MCP_BEARER_TOKEN | Conditional | Bearer token for Databricks MCP. | `<token>` |
| DATABRICKS_MCP_SERVER_TRANSPORT | No | Databricks MCP transport. | `streamable-http` |
| DATABRICKS_MCP_CALL_TIMEOUT | No | Databricks per-call timeout seconds. | `60` |
| GENIE_MCP_SERVER_URL | Conditional | Databricks Genie MCP endpoint URL when `databricks_genie_agent` is enabled. | `https://mcp-databricks-genie.example.com/mcp` |
| GENIE_MCP_BEARER_TOKEN | Conditional | Bearer token for Databricks Genie MCP. | `<token>` |
| GENIE_MCP_SERVER_TRANSPORT | No | Databricks Genie MCP transport. | `streamable-http` |
| GENIE_MCP_CALL_TIMEOUT | No | Databricks Genie per-call timeout seconds. | `60` |
| DV_MCP_SERVER_URL | Conditional | DV MCP endpoint URL when `dv_agent` is enabled. | `https://mcp-dv.example.com/mcp` |
| DV_MCP_BEARER_TOKEN | Conditional | Bearer token for DV MCP. | `<token>` |
| DV_MCP_SERVER_TRANSPORT | No | DV MCP transport. | `streamable-http` |
| DV_MCP_CALL_TIMEOUT | No | DV per-call timeout seconds. | `60` |
| SFLIB_MCP_SERVER_URL | Conditional | Spotfire Library MCP endpoint URL when `sf_lib_md_agent` is enabled. | `https://mcp-spotfire-lib.example.com/mcp` |
| SFLIB_MCP_BEARER_TOKEN | Conditional | Bearer token for Spotfire Library MCP. | `<token>` |
| SFLIB_MCP_SERVER_TRANSPORT | No | Spotfire Library MCP transport. | `streamable-http` |
| SFLIB_MCP_CALL_TIMEOUT | No | Spotfire Library per-call timeout seconds. | `60` |
| SFLIC_MCP_SERVER_URL | Conditional | Spotfire Licensing MCP endpoint URL when `sf_lic_agent` is enabled. | `https://mcp-spotfire-lic.example.com/mcp` |
| SFLIC_MCP_BEARER_TOKEN | Conditional | Bearer token for Spotfire Licensing MCP. | `<token>` |
| SFLIC_MCP_SERVER_TRANSPORT | No | Spotfire Licensing MCP transport. | `streamable-http` |
| SFLIC_MCP_CALL_TIMEOUT | No | Spotfire Licensing per-call timeout seconds. | `60` |
| TAVILY_MCP_SERVER_URL | Conditional | Tavily MCP endpoint URL when `tavily_agent` is enabled. | `https://mcp-tavily.example.com/mcp` |
| TAVILY_MCP_BEARER_TOKEN | Conditional | Bearer token for Tavily MCP. | `<token>` |
| TAVILY_MCP_SERVER_TRANSPORT | No | Tavily MCP transport. | `streamable-http` |
| TAVILY_MCP_CALL_TIMEOUT | No | Tavily per-call timeout seconds. | `60` |
| MILVUS_MCP_SERVER_URL | Conditional | Milvus MCP endpoint URL when `milvus_agent` is enabled. | `https://mcp-milvus.example.com/mcp` |
| MILVUS_MCP_BEARER_TOKEN | Conditional | Bearer token for Milvus MCP. | `<token>` |
| MILVUS_MCP_SERVER_TRANSPORT | No | Milvus MCP transport. | `streamable-http` |
| MILVUS_MCP_CALL_TIMEOUT | No | Milvus per-call timeout seconds. | `60` |
| DDR_MCP_SERVER_URL | Conditional | DDR Neo4j MCP endpoint URL when `ddr_agent` is enabled. | `https://mcp-energy-ddr-neo4j.example.com/mcp` |
| DDR_MCP_BEARER_TOKEN | Conditional | Bearer token for DDR MCP. | `<token>` |
| DDR_MCP_SERVER_TRANSPORT | No | DDR MCP transport. | `streamable-http` |
| DDR_MCP_CALL_TIMEOUT | No | DDR per-call timeout seconds. | `60` |
| SNOWFLAKE_MCP_SERVER_URL | Conditional | Snowflake MCP endpoint URL when `snowflake_agent` is enabled. | `https://mcp-snowflake.example.com/mcp` |
| SNOWFLAKE_MCP_BEARER_TOKEN | Conditional | Bearer token for Snowflake MCP. | `<token>` |
| SNOWFLAKE_MCP_SERVER_TRANSPORT | No | Snowflake MCP transport. | `streamable-http` |
| SNOWFLAKE_MCP_CALL_TIMEOUT | No | Snowflake per-call timeout seconds. | `60` |

### 4.7 Verify

```bash
curl -fsS http://localhost:8000/healthz
curl -fsS http://localhost:8000/readyz
```

If `A2A_AUTH_PUBLIC_CARD=false`, agent-card endpoints require auth.

### 4.8 Stop

```bash
docker compose down
# Optional full reset (deletes Postgres data volume too):
docker compose down -v
```

## 5. Kubernetes Installation with Helm from OCI

Primary audience: platform operators.

Two chart choices are available:

1. `copilot-deepagents-server-oss`: app only (recommended for production)
2. `copilot-deepagents-server-oss-stack`: app + bundled Postgres + Redis (POC/dev)

### 5.1 App-Only Chart (Production Pattern)

#### 5.1.1 Create Values File (`my-values.yaml`)

```yaml
image:
  registry: copilotoci.azurecr.io
  repository: spotfirecopilot/copilot-deepagents-server-oss
  tag: "<image-tag>"

# If your cluster needs explicit pull secret:
# imagePullSecrets:
#   - name: copilot-deepagents-server-oss-acr-pull

config:
  deepagentsModel: "openai:gpt-5.1"
  publicBaseUrl: "https://deepagents.example.com"

  # Bring-your-own managed persistence:
  postgresUrl: "postgresql://USER:PASS@POSTGRES_HOST:5432/deepagents_checkpoints?sslmode=require"
  redisUrl: "redis://REDIS_HOST:6379/0"

  a2aAuthMode: "bearer"
  a2aAuthPublicCard: "false"

  # Load only required agents where possible.
  agentsEnabled: "osdu_agent"

  # Per-agent MCP backends (set only those you use)
  osduMcpServerUrl: "https://mcp-osdu.<your-host>/mcp"
  osduMcpServerTransport: "streamable-http"

  # Per-agent model override (optional): run ONE agent on a different model or
  # provider than deepagentsModel above. Example -- osdu_agent on Azure while the
  # rest stay on OpenAI (uncomment to use):
  # extraEnv:
  #   OSDU_DEEPAGENTS_MODEL: "azure_openai:my-osdu-deployment"
  #   OSDU_AZURE_OPENAI_ENDPOINT: "https://<resource>.openai.azure.com"
  #   OSDU_OPENAI_API_VERSION: "2024-10-21"
  # Prefixes: OSDU, DATABRICKS, GENIE, DV, SFLIB, SFLIC, TAVILY, MILVUS, DDR, SUPPORT, SNOWFLAKE.

secret:
  create: false
  existingSecretName: "deepagents-oss-secrets"
```

Create the referenced secret out-of-band via your external secret manager workflow.

Required keys in `deepagents-oss-secrets` for this example:

- `OPENAI_API_KEY`
- `A2A_BEARER_TOKENS`
- `OSDU_MCP_BEARER_TOKEN`
- `MCP_CLIENT_SECRET` (only when enabling the Keycloak outbound-token minter; pair with `MCP_CLIENT_ID` and `KEYCLOAK_TOKEN_URL` in `config.*`)

> **Azure OpenAI.** To use Azure instead of public OpenAI, set `config.deepagentsModel: "azure_openai:<deployment-name>"` (the value after the colon is the Azure deployment name), `config.azureOpenaiEndpoint: "https://<resource>.openai.azure.com"`, and `config.openaiApiVersion: "2024-10-21"`. Provide `AZURE_OPENAI_API_KEY` in the Secret (via `secret.azureOpenaiApiKey`, or your `existingSecretName` Secret) instead of `OPENAI_API_KEY`. Optionally set `config.modelProvider: "azure"` to force the Azure path regardless of the model prefix.
>
> **Per-agent override (Helm).** To change the model for a single agent, add its `<PREFIX>_`-scoped variables via `config.extraEnv` (non-secret) and `secret.extraSecretEnv` (secret). For example, keep the fleet on OpenAI but move `osdu_agent` to Azure with `config.extraEnv: { OSDU_DEEPAGENTS_MODEL: "azure_openai:<deployment>", AZURE_OPENAI_ENDPOINT: "https://<resource>.openai.azure.com", OPENAI_API_VERSION: "2024-10-21" }` and `secret.extraSecretEnv: { AZURE_OPENAI_API_KEY: "<azure-key>" }`. Prefixes: `OSDU`, `DATABRICKS`, `GENIE`, `DV`, `SFLIB`, `SFLIC`, `TAVILY`, `MILVUS`, `DDR`, `SUPPORT`, `SNOWFLAKE`.

#### 5.1.2 Install

```bash
helm upgrade --install deepagents-oss \
  oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss \
  --version <chart-version> \
  --namespace deepagents-oss \
  --create-namespace \
  -f my-values.yaml
```

### 5.2 Full Stack Chart (App + Postgres + Redis)

Use this for quick environments where in-cluster Postgres/Redis is acceptable.

#### 5.2.1 Create Values File (`my-stack-values.yaml`)

```yaml
copilot-deepagents-server-oss:
  image:
    registry: copilotoci.azurecr.io
    repository: spotfirecopilot/copilot-deepagents-server-oss
    tag: "<image-tag>"

  config:
    deepagentsModel: "openai:gpt-5.1"
    publicBaseUrl: "https://deepagents.example.com"
    agentsEnabled: "osdu_agent"
    osduMcpServerUrl: "https://mcp-osdu.<your-host>/mcp"

  secret:
    create: false
    existingSecretName: "deepagents-oss-secrets"

postgresql:
  enabled: true
  postgres:
    password: "change-me"

redis:
  enabled: true
```

#### 5.2.2 Install

```bash
helm upgrade --install deepagents-oss \
  oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss-stack \
  --version <chart-version> \
  --namespace deepagents-oss \
  --create-namespace \
  -f my-stack-values.yaml
```

## 6. Cloud Overlay Usage (When Needed)

This guide is cloud-neutral by default. AWS overlay commands are provided as the concrete example.

If you need vendor-specific defaults (for example AWS ALB ingress settings), first pull and untar the chart, then apply overlay + your values:

```bash
helm pull oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss \
  --version <chart-version> \
  --untar

helm upgrade --install deepagents-oss ./copilot-deepagents-server-oss \
  --namespace deepagents-oss \
  --create-namespace \
  -f ./values-overlays/aws.yaml \
  -f ./my-values.yaml
```

Notes:

- `aws.yaml` is currently the validated overlay.
- `azure.yaml` and `gcp.yaml` are scaffolds and should be reviewed before production use.

## 7. Registering A2A Agents with an Orchestrator

After the server is deployed, register each agent endpoint in your orchestrator
so clients can invoke it through the A2A protocol.

### 7.1 A2A Endpoint Pattern

For each agent ID, the server exposes:

- Base A2A endpoint: `http(s)://<host>/a2a/<agent_id>`
- Agent card endpoint: `http(s)://<host>/a2a/<agent_id>/.well-known/agent-card.json`

Example (OSDU):

- `https://deepagents.example.com/a2a/osdu_agent`
- `https://deepagents.example.com/a2a/osdu_agent/.well-known/agent-card.json`

### 7.2 Registration Inputs

Use these values when registering an agent in the orchestrator:

- Agent Address: `http(s)://<host>/a2a/<agent_id>`
- Assistant / Agent ID: `<agent_id>` (for example `osdu_agent`)
- Bearer token (optional): only if the agent requires bearer auth
- Token Env Var (optional, preferred): name of env var on orchestrator pod that stores the bearer token

If an assistant/agent ID is provided and the address does not already include
`/a2a/<agent_id>`, the orchestrator appends it during registration.

### 7.3 Recommended Flow

1. Confirm the agent card is reachable from the orchestrator network.
2. In orchestrator UI, open agent registration.
3. Enter Agent Address and optional Assistant / Agent ID.
4. If auth is enabled on the agent, provide token or token env var.
5. Load/preview agent info from the card.
6. Register and verify the agent appears in registered agents list.

### 7.4 Connectivity Pre-Check

From any location that can reach the deployed server:

```bash
curl -fsS \
  -H "Authorization: Bearer <token-if-required>" \
  http://<service-or-ingress-host>/a2a/osdu_agent/.well-known/agent-card.json
```

If this call fails, orchestrator registration will fail for the same reason
(DNS/TLS/network/auth/path issues).

## 8. Post-Deploy Validation (Docker Compose and Kubernetes)

Choose the validation flow that matches your installation path.

### 8.1 Docker Compose Installation

Container and service status:

```bash
docker compose ps
docker compose logs deepagents-oss --tail=200
```

Health checks:

```bash
curl -fsS http://localhost:8000/healthz
curl -fsS http://localhost:8000/readyz
```

Basic A2A verification:

```bash
curl -fsS \
  -H "Authorization: Bearer <token>" \
  http://localhost:8000/a2a/osdu_agent/.well-known/agent-card.json
```

### 8.2 Kubernetes Installation

```bash
kubectl -n deepagents-oss get pods
kubectl -n deepagents-oss get svc
kubectl -n deepagents-oss logs deploy/deepagents-oss-copilot-deepagents-server-oss --tail=200
```

Health checks from inside cluster or via ingress:

```bash
curl -fsS http://<service-or-ingress-host>/healthz
curl -fsS http://<service-or-ingress-host>/readyz
```

Basic A2A verification (replace with one enabled agent id and token):

```bash
curl -fsS \
  -H "Authorization: Bearer <token>" \
  http://<service-or-ingress-host>/a2a/osdu_agent/.well-known/agent-card.json
```

## 9. Upgrade

### 9.1 Docker Compose Installation

To upgrade with a new image tag:

```bash
# Update AGENT_IMAGE_REF in .env to the new <image-tag>, then:
docker compose pull deepagents-oss
docker compose up -d
```

If compose file changes include dependencies or env wiring, run:

```bash
docker compose up -d --force-recreate
```

### 9.2 Kubernetes Installation

```bash
helm upgrade deepagents-oss \
  oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss \
  --version <chart-version> \
  --namespace deepagents-oss \
  -f my-values.yaml
```

## 10. Uninstall

### 10.1 Docker Compose Installation

```bash
docker compose down
```

Optional full wipe (includes local Postgres volume data):

```bash
docker compose down -v
```

### 10.2 Kubernetes Installation

```bash
helm uninstall deepagents-oss -n deepagents-oss
```

For full-stack installs, PVCs may remain and must be deleted explicitly if you want a complete wipe.

## 11. Troubleshooting

1. Pods pending due to image pull errors:
  - Confirm registry credentials were provided and logins succeeded.
  - Confirm repository path and image tag.
   - If required by your cluster, define `imagePullSecrets`.
2. Service starts but agents do not load:
   - Verify each enabled agent has matching `*_MCP_SERVER_URL` and token values.
3. `401`/`403` on A2A endpoints:
   - Confirm `a2aAuthMode` and matching token/key configuration.
4. Readiness failures on startup:
   - Check Postgres/Redis reachability and credentials.
5. Streaming behavior issues under replicas:
   - Ensure Redis is configured (`redisUrl`) for multi-replica fan-out and locks.

## 12. Security Notes

- Do not hardcode production secrets in values files checked into source control.
- Prefer external secret stores and bind with `existingSecretName`.
- For production, prefer app-only chart with managed Postgres/Redis and TLS-enabled ingress.
