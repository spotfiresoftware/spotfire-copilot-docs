# Semantica MCP Server Deployment Guide

## Table of Contents

- [1. Introduction](#1-introduction)
  - [1.1 Purpose of This Document](#11-purpose-of-this-document)
  - [1.2 Scope](#12-scope)
- [2. Deployment Inputs](#2-deployment-inputs)
  - [2.1 Required Runtime Configuration](#21-required-runtime-configuration)
  - [2.2 Network Endpoints](#22-network-endpoints)
  - [2.3 Artifact Sources and Access](#23-artifact-sources-and-access)
- [3. Docker Compose Deployment](#3-docker-compose-deployment)
  - [3.1 Create `.env`](#31-create-env)
  - [3.2 Create `docker-compose.yml`](#32-create-docker-composeyml)
  - [3.3 Start](#33-start)
  - [3.4 Environment Variables Reference (.env)](#34-environment-variables-reference-env)
  - [3.5 Key Terms (Quick Reference)](#35-key-terms-quick-reference)
- [4. Kubernetes Deployment (Helm)](#4-kubernetes-deployment-helm)
  - [4.1 Create values file](#41-create-values-file)
  - [4.2 Install](#42-install)
- [5. Post-Deploy Validation](#5-post-deploy-validation)
  - [5.1 Docker Compose](#51-docker-compose)
  - [5.2 Kubernetes](#52-kubernetes)
- [6. Upgrade](#6-upgrade)
  - [6.1 Docker Compose](#61-docker-compose)
  - [6.2 Kubernetes](#62-kubernetes)
- [7. Uninstall](#7-uninstall)
  - [7.1 Docker Compose](#71-docker-compose)
  - [7.2 Kubernetes](#72-kubernetes)
- [8. Troubleshooting](#8-troubleshooting)
- [9. Related Documentation](#9-related-documentation)


## 1. Introduction

### 1.1 Purpose of This Document

This guide explains how to deploy the Semantica MCP server from OCI artifacts.

### 1.2 Scope

This guide covers Docker Compose and Kubernetes deployment paths, plus validation, upgrade, and
uninstall. The server reads an **industry data model loaded into a Neo4j knowledge graph**;
loading the data model into Neo4j is a separate step performed by your data-model loader and is
out of scope for this guide. The server's **schema tools are published only when a Neo4j graph
is configured** and the model is loaded.

## 2. Deployment Inputs

### 2.1 Required Runtime Configuration

At minimum, provide values for:

- **Knowledge graph (required for the schema tools):** `NEO4J_URI`, `NEO4J_USERNAME`,
  `NEO4J_PASSWORD`, `NEO4J_DATABASE`.
- **Hydration:** `SEMANTICA_HYDRATE_FROM_NEO4J=true` so the server loads the data model from
  Neo4j at startup and keeps it current; `SEMANTICA_HYDRATION_POLL_SECONDS` controls the refresh
  interval across replicas.
- **Server:** `TRANSPORT`, `HOST`, `PORT`.
- **Optional surface control:** `SEMANTICA_ENABLED_TOOL_CATEGORIES` to restrict which Semantica
  tool categories are published (see reference below).

Client-side connection setting:

- `SEMANTICA_OILGAS_MCP_SERVER_URL=http(s)://<host>/mcp`
- `SEMANTICA_OILGAS_MCP_SERVER_TRANSPORT=streamable-http`

> Run a **single replica** for the simplest coherence, or multiple replicas with
> `SEMANTICA_HYDRATE_FROM_NEO4J=true` and a poll interval — each replica refreshes from the
> shared Neo4j graph and converges within the poll window.

### 2.2 Network Endpoints

- MCP endpoint (streamable-http): `http(s)://<host>/mcp`
- Health endpoint: `http(s)://<host>/healthz`
- Ready endpoint: `http(s)://<host>/readyz`

### 2.3 Artifact Sources and Access

Deployment artifacts for this server are pulled from:

- Container image: `copilotoci.azurecr.io/spotfirecopilot/mcp-semantica:<image-tag>`
- Helm chart: `oci://copilotoci.azurecr.io/spotfirecopilot/mcp-semantica`

Before deploying, authenticate to the OCI registry:

```bash
helm registry login copilotoci.azurecr.io
docker login copilotoci.azurecr.io
```

Validate artifact access with your credentials:

```bash
helm show chart oci://copilotoci.azurecr.io/spotfirecopilot/mcp-semantica \
  --version <chart-version>

docker pull copilotoci.azurecr.io/spotfirecopilot/mcp-semantica:<image-tag>
```

Version selection policy:

- Use operator-approved chart versions (`--version <chart-version>`).
- Use operator-approved image tags (`<image-tag>` in compose/values).
- Do not assume a fixed chart-to-image mapping unless your platform team publishes one.

## 3. Docker Compose Deployment

> Ready-to-use [`docker-compose.yml`](docker-compose.yml) and [`.env.example`](.env.example)
> are provided alongside this guide in the same folder. Copy [`.env.example`](.env.example) to
> `.env`, fill in your values, then run `docker compose up -d`.

### 3.1 Create `.env`

```env
MCP_IMAGE_REF=copilotoci.azurecr.io/spotfirecopilot/mcp-semantica:<image-tag>
HOST=0.0.0.0
PORT=8074
TRANSPORT=streamable-http

# --- Knowledge graph (Neo4j) — the loaded industry data model ---
NEO4J_URI=neo4j+s://<neo4j-host>:7687
NEO4J_USERNAME=<username>
NEO4J_PASSWORD=<password>
NEO4J_DATABASE=neo4j

# --- Hydration (load + refresh the model from Neo4j) ---
SEMANTICA_HYDRATE_FROM_NEO4J=true
SEMANTICA_HYDRATION_POLL_SECONDS=60

# --- Optional: restrict published tool categories ---
# SEMANTICA_ENABLED_TOOL_CATEGORIES=
```

### 3.2 Create `docker-compose.yml`

```yaml
services:
  mcp-semantica:
    image: ${MCP_IMAGE_REF}
    ports:
      - "8074:8074"
    env_file:
      - .env
```

### 3.3 Start

```bash
docker compose up -d
```

### 3.4 Environment Variables Reference (.env)

| Variable | Required | Description | Example |
|---|---|---|---|
| MCP_IMAGE_REF | Yes | OCI image reference for this server. | copilotoci.azurecr.io/spotfirecopilot/mcp-semantica:1.0.0 |
| HOST | Yes | Server bind address. | 0.0.0.0 |
| PORT | Yes | Server listening port. | 8074 |
| TRANSPORT | Yes | MCP transport mode. Use `streamable-http` in this guide. | streamable-http |
| NEO4J_URI | Yes | Neo4j connection URI holding the loaded data model. | neo4j+s://graph.example.com:7687 |
| NEO4J_USERNAME | Yes | Neo4j username. | neo4j |
| NEO4J_PASSWORD | Yes | Neo4j password. | replace-me |
| NEO4J_DATABASE | No | Neo4j database name. | neo4j |
| SEMANTICA_HYDRATE_FROM_NEO4J | Yes | Load the data model from Neo4j at startup and keep it refreshed. Required for the schema tools. | true |
| SEMANTICA_HYDRATION_POLL_SECONDS | No | Refresh interval (seconds) for multi-replica convergence. | 60 |
| SEMANTICA_ENABLED_TOOL_CATEGORIES | No | Comma-separated list of Semantica tool categories to publish (`extraction`, `decisions`, `graph`, `reasoning`, `export`, `retrieval`). Default: all. The schema tools are published independently when Neo4j is configured. | extraction,graph,retrieval |
| SEMANTICA_LOG_LEVEL | No | Log verbosity. | INFO |
| MCP_AUTH_ENABLED | No | Enables inbound bearer/JWT auth for MCP endpoints. | false |
| MCP_AUTH_TOKENS | Conditional | Comma-separated static bearer tokens. Required when auth is enabled and `MCP_AUTH_JWKS_URL` is empty. | token-a,token-b |
| MCP_AUTH_ISSUER_URL | Conditional | OAuth issuer URL for MCP auth metadata. Required when auth is enabled. | https://auth.example.com |
| MCP_AUTH_RESOURCE_SERVER_URL | Conditional | Public resource server URL for MCP auth metadata. Required when auth is enabled. | https://mcp.example.com |
| MCP_AUTH_REQUIRED_SCOPES | Conditional | Comma-separated scopes enforced for MCP calls when auth is enabled. | user |
| MCP_AUTH_JWKS_URL | No | JWKS endpoint for JWT validation. Leave empty to use static `MCP_AUTH_TOKENS`. | https://auth.example.com/.well-known/jwks.json |
| MCP_AUTH_AUDIENCE | No | Optional JWT audience claim (`aud`) to enforce. | mcp-semantica |

### 3.5 Key Terms (Quick Reference)

| Term | Meaning in this guide |
|---|---|
| Knowledge graph | The Neo4j graph holding the loaded industry data model. |
| Hydration | Loading (and periodically refreshing) the model from Neo4j into the server. |
| Tool category | A named group of Semantica tools (`extraction`, `graph`, …) published by the server. |
| Schema tools | The `schema_*` data-model tools published when Neo4j is configured. |
| Transport | MCP protocol transport mode. This guide uses `streamable-http`. |
| Required = Yes | Must be set for the deployment to function correctly. |
| Required = No | Optional; default behavior is used when omitted. |
| Required = Conditional | Required only when a related mode/setting is enabled. |

## 4. Kubernetes Deployment (Helm)

### 4.1 Create values file

```yaml
image:
  registry: copilotoci.azurecr.io
  repository: spotfirecopilot/mcp-semantica
  tag: "<image-tag>"

replicaCount: 1

env:
  HOST: "0.0.0.0"
  PORT: "8074"
  TRANSPORT: "streamable-http"
  NEO4J_URI: "neo4j+s://<neo4j-host>:7687"
  NEO4J_DATABASE: "neo4j"
  SEMANTICA_HYDRATE_FROM_NEO4J: "true"
  SEMANTICA_HYDRATION_POLL_SECONDS: "60"

secretEnv:
  NEO4J_USERNAME: "<username>"
  NEO4J_PASSWORD: "<password>"
```

### 4.2 Install

```bash
helm upgrade --install mcp-semantica oci://copilotoci.azurecr.io/spotfirecopilot/mcp-semantica \
  --namespace mcp-semantica \
  --create-namespace \
  -f values.yaml
```

## 5. Post-Deploy Validation

### 5.1 Docker Compose

```bash
docker compose ps
docker compose logs mcp-semantica --tail=200
curl -fsS http://localhost:8074/healthz
curl -fsS http://localhost:8074/readyz
```

### 5.2 Kubernetes

```bash
kubectl -n mcp-semantica get pods
kubectl -n mcp-semantica get svc
kubectl -n mcp-semantica logs deploy/mcp-semantica --tail=200
curl -fsS http://<service-or-ingress-host>/healthz
curl -fsS http://<service-or-ingress-host>/readyz
```

After startup, confirm the data model is visible by calling `schema_list_industries` from an
MCP client — it should return the loaded industries (e.g. `oil_gas`) with domain/table counts.

## 6. Upgrade

### 6.1 Docker Compose

```bash
export MCP_IMAGE_REF=copilotoci.azurecr.io/spotfirecopilot/mcp-semantica:<new-image-tag>
docker compose pull mcp-semantica
docker compose up -d
```

### 6.2 Kubernetes

```bash
helm upgrade mcp-semantica oci://copilotoci.azurecr.io/spotfirecopilot/mcp-semantica -n mcp-semantica -f values.yaml
```

## 7. Uninstall

### 7.1 Docker Compose

```bash
docker compose down
```

### 7.2 Kubernetes

```bash
helm uninstall mcp-semantica -n mcp-semantica
```

## 8. Troubleshooting

1. **`schema_*` tools are missing or return nothing:**
   - Confirm `NEO4J_URI` (and credentials) are set and reachable, `SEMANTICA_HYDRATE_FROM_NEO4J`
     is `true`, and the industry data model is actually loaded into the graph. The schema tools
     are published only when Neo4j is configured.
2. **`schema_list_industries` returns an empty list:**
   - The graph is reachable but no data model is loaded. Load the model into Neo4j, then let the
     server re-hydrate (or restart the pod).
3. **Multiple replicas return stale results:**
   - Ensure `SEMANTICA_HYDRATE_FROM_NEO4J=true` on every replica and set a reasonable
     `SEMANTICA_HYDRATION_POLL_SECONDS`; replicas converge within the poll window. For strict
     freshness, run a single replica.
4. **Neo4j auth/connectivity failures:**
   - Verify URI scheme, credentials, and network reachability.

## 9. Related Documentation

- [Semantica MCP Server User Guide](Spotfire%20Copilot%20-%20Semantica%20MCP%20Server%20User%20Guide.md) — the tools this server exposes.
- [Semantica Oil & Gas Agent User Guide](../../agents/Spotfire%20Copilot%20-%20Semantica%20Oil%20%26%20Gas%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
