# GraphRAG MCP Server Deployment Guide

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

This guide explains how to deploy the GraphRAG MCP server from OCI artifacts.

### 1.2 Scope

This guide covers Docker Compose and Kubernetes deployment paths, plus validation, upgrade,
and uninstall. The GraphRAG server is **stateless** — it reads an existing Milvus/Zilliz
collection and an existing Neo4j graph. Standing up those backends and loading the corpus is
covered in the [GraphRAG Corpus Loading Guide](Spotfire%20Copilot%20-%20GraphRAG%20Corpus%20Loading%20Guide.md).

## 2. Deployment Inputs

### 2.1 Required Runtime Configuration

The GraphRAG server connects to a vector store and (optionally) a knowledge graph. At minimum,
provide values for:

- **Vector store (required):** `MILVUS_URI`, `MILVUS_TOKEN`, `MILVUS_COLLECTION`.
- **Embeddings (required):** `EMBEDDING_PROVIDER`, `EMBEDDING_MODEL`, `EMBEDDING_API_KEY`,
  `EMBEDDING_DIMENSION` — these **must match the model used to load the corpus**.
- **Knowledge graph (optional but recommended):** `NEO4J_URI`, `NEO4J_USERNAME`,
  `NEO4J_PASSWORD`, `NEO4J_DATABASE`. Without these, the server runs documentation-only and the
  graph / feature-lifecycle / DDR tools return `not_configured`.
- **Server:** `TRANSPORT`, `HOST`, `PORT`.

Client-side connection setting:

- `GRAPHRAG_MCP_SERVER_URL=http(s)://<host>/mcp`
- `GRAPHRAG_MCP_SERVER_TRANSPORT=streamable-http`

> The embedding model and dimension **must be identical** to the model used by the loader when
> the collection was built; otherwise query vectors will not match the stored vectors.

### 2.2 Network Endpoints

- MCP endpoint (streamable-http): `http(s)://<host>/mcp`
- Health endpoint: `http(s)://<host>/healthz`
- Ready endpoint: `http(s)://<host>/readyz`

### 2.3 Artifact Sources and Access

Deployment artifacts for this server are pulled from:

- Container image: `copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag:<image-tag>`
- Helm chart: `oci://copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag`

Before deploying, authenticate to the OCI registry:

```bash
helm registry login copilotoci.azurecr.io
docker login copilotoci.azurecr.io
```

Validate artifact access with your credentials:

```bash
helm show chart oci://copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag \
  --version <chart-version>

docker pull copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag:<image-tag>
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
MCP_IMAGE_REF=copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag:<image-tag>
HOST=0.0.0.0
PORT=8060
TRANSPORT=streamable-http

# --- Vector store (Milvus / Zilliz) ---
MILVUS_URI=https://<zilliz-endpoint>
MILVUS_TOKEN=<token>
MILVUS_COLLECTION=copilot_docs

# --- Query embeddings (MUST match the loader) ---
EMBEDDING_PROVIDER=openai
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_API_KEY=<api-key>
EMBEDDING_DIMENSION=1536

# --- Knowledge graph (Neo4j) — optional; enables graph/lifecycle/DDR tools ---
NEO4J_URI=neo4j+s://<neo4j-host>:7687
NEO4J_USERNAME=<username>
NEO4J_PASSWORD=<password>
NEO4J_DATABASE=neo4j
```

### 3.2 Create `docker-compose.yml`

```yaml
services:
  mcp-graphrag:
    image: ${MCP_IMAGE_REF}
    ports:
      - "8060:8060"
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
| MCP_IMAGE_REF | Yes | OCI image reference for this server. | copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag:1.0.0 |
| HOST | Yes | Server bind address. | 0.0.0.0 |
| PORT | Yes | Server listening port. | 8060 |
| TRANSPORT | Yes | MCP transport mode. Use `streamable-http` in this guide. | streamable-http |
| MILVUS_URI | Yes | Milvus/Zilliz endpoint URL. | https://in05-xxxx.serverless.gcp-us-west1.cloud.zilliz.com |
| MILVUS_TOKEN | Yes | Milvus/Zilliz access token (use read-only credentials). | replace-me |
| MILVUS_COLLECTION | Yes | Collection to search. | copilot_docs |
| MILVUS_DB | No | Milvus database name. | default |
| EMBEDDING_PROVIDER | Yes | Embedding provider (`openai` or `azure_openai`). | openai |
| EMBEDDING_MODEL | Yes | Embedding model — must match the loader. | text-embedding-3-small |
| EMBEDDING_API_KEY | Yes | API key for the embedding provider. | replace-me |
| EMBEDDING_DIMENSION | Yes | Embedding vector dimension — must match the collection. | 1536 |
| EMBEDDING_API_VERSION | Conditional | Azure OpenAI API version. Required when provider is `azure_openai`. | 2024-02-01 |
| NEO4J_URI | No | Neo4j connection URI. Enables the graph / lifecycle / DDR tools. Omit to run documentation-only. | neo4j+s://graph.example.com:7687 |
| NEO4J_USERNAME | Conditional | Neo4j username. Required when `NEO4J_URI` is set. | neo4j |
| NEO4J_PASSWORD | Conditional | Neo4j password. Required when `NEO4J_URI` is set. | replace-me |
| NEO4J_DATABASE | No | Neo4j database name. | neo4j |
| MCP_AUTH_ENABLED | No | Enables inbound bearer/JWT auth for MCP endpoints. | false |
| MCP_AUTH_TOKENS | Conditional | Comma-separated static bearer tokens. Required when auth is enabled and `MCP_AUTH_JWKS_URL` is empty. | token-a,token-b |
| MCP_AUTH_ISSUER_URL | Conditional | OAuth issuer URL for MCP auth metadata. Required when auth is enabled. | https://auth.example.com |
| MCP_AUTH_RESOURCE_SERVER_URL | Conditional | Public resource server URL for MCP auth metadata. Required when auth is enabled. | https://mcp.example.com |
| MCP_AUTH_REQUIRED_SCOPES | Conditional | Comma-separated scopes enforced for MCP calls when auth is enabled. | user |
| MCP_AUTH_JWKS_URL | No | JWKS endpoint for JWT validation. Leave empty to use static `MCP_AUTH_TOKENS`. | https://auth.example.com/.well-known/jwks.json |
| MCP_AUTH_AUDIENCE | No | Optional JWT audience claim (`aud`) to enforce. | mcp-graphrag |

### 3.5 Key Terms (Quick Reference)

| Term | Meaning in this guide |
|---|---|
| Vector store | The Milvus/Zilliz collection holding embedded document chunks. |
| Knowledge graph | The Neo4j graph of features, documents, entities, and DDR records. |
| Embedding model | The model that turns text into vectors. Query-time and load-time models must match. |
| Transport | MCP protocol transport mode. This guide uses `streamable-http`. |
| Required = Yes | Must be set for the deployment to function correctly. |
| Required = No | Optional; default behavior is used when omitted. |
| Required = Conditional | Required only when a related mode/setting is enabled. |
| MCP_AUTH_JWKS_URL | URL for JWT signing keys. If empty, use static `MCP_AUTH_TOKENS`. |
| MCP_AUTH_AUDIENCE | Optional JWT `aud` claim value enforced during token validation. |

## 4. Kubernetes Deployment (Helm)

### 4.1 Create values file

```yaml
image:
  registry: copilotoci.azurecr.io
  repository: spotfirecopilot/mcp-graphrag
  tag: "<image-tag>"

env:
  HOST: "0.0.0.0"
  PORT: "8060"
  TRANSPORT: "streamable-http"
  MILVUS_URI: "https://<zilliz-endpoint>"
  MILVUS_COLLECTION: "copilot_docs"
  EMBEDDING_PROVIDER: "openai"
  EMBEDDING_MODEL: "text-embedding-3-small"
  EMBEDDING_DIMENSION: "1536"
  NEO4J_URI: "neo4j+s://<neo4j-host>:7687"
  NEO4J_DATABASE: "neo4j"

secretEnv:
  MILVUS_TOKEN: "<token>"
  EMBEDDING_API_KEY: "<api-key>"
  NEO4J_USERNAME: "<username>"
  NEO4J_PASSWORD: "<password>"
```

### 4.2 Install

```bash
helm upgrade --install mcp-graphrag oci://copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag \
  --namespace mcp-graphrag \
  --create-namespace \
  -f values.yaml
```

## 5. Post-Deploy Validation

### 5.1 Docker Compose

```bash
docker compose ps
docker compose logs mcp-graphrag --tail=200
curl -fsS http://localhost:8060/healthz
curl -fsS http://localhost:8060/readyz
```

### 5.2 Kubernetes

```bash
kubectl -n mcp-graphrag get pods
kubectl -n mcp-graphrag get svc
kubectl -n mcp-graphrag logs deploy/mcp-graphrag --tail=200
curl -fsS http://<service-or-ingress-host>/healthz
curl -fsS http://<service-or-ingress-host>/readyz
```

A healthy `/readyz` confirms the Milvus collection schema validated (required fields and vector
dimension) and, when configured, that Neo4j is reachable.

## 6. Upgrade

### 6.1 Docker Compose

```bash
export MCP_IMAGE_REF=copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag:<new-image-tag>
docker compose pull mcp-graphrag
docker compose up -d
```

### 6.2 Kubernetes

```bash
helm upgrade mcp-graphrag oci://copilotoci.azurecr.io/spotfirecopilot/mcp-graphrag -n mcp-graphrag -f values.yaml
```

## 7. Uninstall

### 7.1 Docker Compose

```bash
docker compose down
```

### 7.2 Kubernetes

```bash
helm uninstall mcp-graphrag -n mcp-graphrag
```

## 8. Troubleshooting

1. **`/readyz` fails with a schema error:**
   - Confirm `MILVUS_COLLECTION` exists and `EMBEDDING_DIMENSION` matches the collection's
     vector dimension. The server validates these at startup and never mutates the collection.
2. **Query results look irrelevant or empty:**
   - Verify `EMBEDDING_MODEL` / `EMBEDDING_PROVIDER` are identical to the model used to load the
     corpus. A mismatch makes query vectors incomparable with stored vectors.
3. **Graph / DDR tools return `not_configured`:**
   - `NEO4J_URI` (and credentials) are unset or unreachable. Set them to enable the
     knowledge-graph, feature-lifecycle, and DDR tool families.
4. **Transcript citations show a bare link (no timestamp):**
   - Confirm the collection has an explicit `timestamp_seconds` field and the transcripts were
     loaded with timestamps. See the Corpus Loading Guide.
5. **Neo4j auth/connectivity failures:**
   - Verify URI scheme, credentials, and network reachability.

## 9. Related Documentation

- [GraphRAG MCP Server User Guide](Spotfire%20Copilot%20-%20GraphRAG%20MCP%20Server%20User%20Guide.md) — the tools this server exposes.
- [GraphRAG Corpus Loading Guide](Spotfire%20Copilot%20-%20GraphRAG%20Corpus%20Loading%20Guide.md) — load the vector store and knowledge graph.
- [GraphRAG Agent User Guide](../../agents/Spotfire%20Copilot%20-%20GraphRAG%20Agent%20User%20Guide.md) — the agent backed by this server.
- [Artifact Sources and Access](../../Spotfire%20Copilot%20-%20Artifact%20Sources%20and%20Access.md) — OCI login and version policy.
