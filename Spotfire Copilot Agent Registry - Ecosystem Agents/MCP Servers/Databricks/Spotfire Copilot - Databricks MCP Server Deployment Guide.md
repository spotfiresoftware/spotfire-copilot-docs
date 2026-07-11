# Databricks MCP Server Deployment Guide

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

This guide explains how to deploy the Databricks MCP server from OCI artifacts and validate connectivity to Unity Catalog and SQL Warehouse.

### 1.2 Scope

This guide covers Docker Compose and Kubernetes deployment paths, plus validation, upgrade, and uninstall.

## 2. Deployment Inputs

### 2.1 Required Runtime Configuration

- `DATABRICKS_HOST`
- `DATABRICKS_TOKEN`
- `DATABRICKS_SQL_WAREHOUSE_ID`
- `TRANSPORT` (`streamable-http`)
- `HOST`, `PORT`

Client-side connection setting:

- `DATABRICKS_MCP_SERVER_URL=http(s)://<host>/mcp`

### 2.2 Network Endpoints

- MCP endpoint (streamable-http): `http(s)://<host>/mcp`
- Health endpoint: `http(s)://<host>/healthz`
- Ready endpoint: `http(s)://<host>/readyz`

### 2.3 Artifact Sources and Access

Deployment artifacts for this server are pulled from:

- Container image: `copilotoci.azurecr.io/spotfirecopilot/mcp-databricks:<image-tag>`
- Helm chart: `oci://copilotoci.azurecr.io/spotfirecopilot/mcp-databricks`

Before deploying, authenticate to the OCI registry:

```bash
helm registry login copilotoci.azurecr.io
docker login copilotoci.azurecr.io
```

Validate artifact access with your credentials:

```bash
helm show chart oci://copilotoci.azurecr.io/spotfirecopilot/mcp-databricks \
  --version <chart-version>

docker pull copilotoci.azurecr.io/spotfirecopilot/mcp-databricks:<image-tag>
```

Version selection policy:

- Use operator-approved chart versions (`--version <chart-version>`).
- Use operator-approved image tags (`<image-tag>` in compose/values).
- Do not assume a fixed chart-to-image mapping unless your platform team publishes one.

## 3. Docker Compose Deployment

### 3.1 Create `.env`

```env
MCP_IMAGE_REF=copilotoci.azurecr.io/spotfirecopilot/mcp-databricks:<image-tag>
HOST=0.0.0.0
PORT=8060
TRANSPORT=streamable-http

DATABRICKS_HOST=<workspace-host>.cloud.databricks.com
DATABRICKS_TOKEN=<token>
DATABRICKS_SQL_WAREHOUSE_ID=<warehouse-id>
```

### 3.2 Create `docker-compose.yml`

```yaml
services:
  mcp-databricks:
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
| MCP_IMAGE_REF | Yes | OCI image reference for this server. | copilotoci.azurecr.io/spotfirecopilot/mcp-databricks:1.0.0 |
| HOST | Yes | Server bind address. | 0.0.0.0 |
| PORT | Yes | Server listening port. | 8060 |
| TRANSPORT | Yes | MCP transport mode. Use `streamable-http` in this guide. | streamable-http |
| DATABRICKS_HOST | Yes | Databricks workspace base URL. | https://workspace.cloud.databricks.com |
| DATABRICKS_TOKEN | Yes | Databricks access token. | dapi... |
| DATABRICKS_SQL_WAREHOUSE_ID | Yes | Databricks SQL Warehouse identifier. | abcdef1234567890 |
| MCP_AUTH_ENABLED | No | Enables inbound bearer/JWT auth for MCP endpoints. | false |
| MCP_AUTH_TOKENS | Conditional | Comma-separated static bearer tokens. Required when auth is enabled and `MCP_AUTH_JWKS_URL` is empty. | token-a,token-b |
| MCP_AUTH_ISSUER_URL | Conditional | OAuth issuer URL for MCP auth metadata. Required when auth is enabled. | https://auth.example.com |
| MCP_AUTH_RESOURCE_SERVER_URL | Conditional | Public resource server URL for MCP auth metadata. Required when auth is enabled. | https://mcp.example.com |
| MCP_AUTH_REQUIRED_SCOPES | Conditional | Comma-separated scopes enforced for MCP calls when auth is enabled. | user |
| MCP_AUTH_JWKS_URL | No | JWKS endpoint for JWT validation. Leave empty to use static `MCP_AUTH_TOKENS`. | https://auth.example.com/.well-known/jwks.json |
| MCP_AUTH_AUDIENCE | No | Optional JWT audience claim (`aud`) to enforce. | mcp-databricks |

### 3.5 Key Terms (Quick Reference)

| Term | Meaning in this guide |
|---|---|
| Base URL | Root URL of an external backend API used by the MCP server. |
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
  repository: spotfirecopilot/mcp-databricks
  tag: "<image-tag>"

env:
  HOST: "0.0.0.0"
  PORT: "8060"
  TRANSPORT: "streamable-http"
  DATABRICKS_HOST: "<workspace-host>.cloud.databricks.com"

secretEnv:
  DATABRICKS_TOKEN: "<token>"
  DATABRICKS_SQL_WAREHOUSE_ID: "<warehouse-id>"
```

### 4.2 Install

```bash
helm upgrade --install mcp-databricks oci://copilotoci.azurecr.io/spotfirecopilot/mcp-databricks \
  --namespace mcp-databricks \
  --create-namespace \
  -f values.yaml
```

## 5. Post-Deploy Validation

### 5.1 Docker Compose

```bash
docker compose ps
docker compose logs mcp-databricks --tail=200
curl -fsS http://localhost:8060/healthz
curl -fsS http://localhost:8060/readyz
```

### 5.2 Kubernetes

```bash
kubectl -n mcp-databricks get pods
kubectl -n mcp-databricks get svc
kubectl -n mcp-databricks logs deploy/mcp-databricks --tail=200
curl -fsS http://<service-or-ingress-host>/healthz
curl -fsS http://<service-or-ingress-host>/readyz
```

## 6. Upgrade

### 6.1 Docker Compose

```bash
export MCP_IMAGE_REF=copilotoci.azurecr.io/spotfirecopilot/mcp-databricks:<new-image-tag>
docker compose pull mcp-databricks
docker compose up -d
```

### 6.2 Kubernetes

```bash
helm upgrade mcp-databricks oci://copilotoci.azurecr.io/spotfirecopilot/mcp-databricks -n mcp-databricks -f values.yaml
```

## 7. Uninstall

### 7.1 Docker Compose

```bash
docker compose down
```

### 7.2 Kubernetes

```bash
helm uninstall mcp-databricks -n mcp-databricks
```

## 8. Troubleshooting

1. Warehouse-related failures:
- Confirm `DATABRICKS_SQL_WAREHOUSE_ID` is valid and usable by token identity.
2. Permissions failures:
- Validate token identity has catalog/schema/table access and warehouse `CAN_USE`.
3. Connectivity failures:
- Confirm egress to Databricks workspace host.

## 9. Related Documentation

See this community site's Databricks MCP Server overview and tools reference for tool behavior and parameter details.
