# Spotfire Copilot Environment Validators

Post-deployment validation scripts for Spotfire Copilot environments. Use these to audit and validate environment variables across deployed services.

---

## Table of Contents

- [Overview](#overview)
- [When to use](#when-to-use)
- [Scripts](#scripts)
- [Quick start](#quick-start)
- [How validators work](#how-validators-work)
- [Requirements](#requirements)

---

## Overview

After deploying Spotfire Copilot to AWS ECS/Fargate or Azure Container Apps, operators often need to verify that:

- ✅ All required environment variables are present
- ✅ Secret references are correctly configured
- ✅ LLM provider variables match the selected provider (no orphaned keys)
- ✅ Database connection strings use correct formats
- ✅ No typos or misconfigurations are present

The validators in this folder provide an **interactive, multi-phase audit** without resolving actual secret values (for security).

---

## When to use

**Best time:** After deployment, before users access the system

**Typical workflow:**
1. Run deployment script (`spotfire-copilot-backend-deploy*.sh/ps1`)
2. Deploy to cloud platform (AWS ECS / Azure ACA)
3. **Run validator** to catch configuration errors
4. Fix issues if needed
5. Start the application services

**Also useful for:**
- Day-2 operations audits
- Post-upgrade validation
- Configuration drift detection
- Troubleshooting startup failures

---

## Scripts

### `spotfire-copilot-backend-validate-env.sh` / `.ps1`

Validates environment variables for **Spotfire Copilot Orchestrator** and **Admin Console** on AWS ECS/Fargate or Azure Container Apps.

**Supported platforms:**
- AWS ECS/Fargate (single or multiple task definitions)
- Azure Container Apps (single or multiple Container Apps)

**What it checks:**
- Required core variables (IMAGE_TAG, DATABASE_URL, credentials, etc.)
- LLM provider-specific variables (Azure OpenAI, OpenAI, Bedrock, Vertex AI, Gemini, NVIDIA NIM, Ollama)
- Database URL format and SSL mode
- Bcrypt hash format for HASHED_ADMIN_PASSWORD
- Orphaned variables (e.g., OPENAI_API_KEY when using Azure OpenAI)
- Admin Console vs. Orchestrator schema differences

**Output:** Timestamped validation report file (e.g., `validation-report-20260804-143022-ecs.txt`)

---

## Quick start

**Linux / macOS**

```bash
cd Validators
chmod +x spotfire-copilot-backend-validate-env.sh
./spotfire-copilot-backend-validate-env.sh
```

**Windows (PowerShell)**

```powershell
cd Validators
.\spotfire-copilot-backend-validate-env.ps1
```

Then answer the interactive prompts:

1. **Platform:** AWS ECS or Azure Container Apps?
2. **Topology:** Single or multiple task definitions / Container Apps?
3. **Schema:** Do you have a config template from our deploy script?
   - Yes → Load LLM provider + Admin Console settings from template
   - No → Interactively select LLM provider + whether Admin Console is deployed
4. **Validation:** Fetch env vars from live services and check against schema
5. **Report:** Write timestamped report file to current directory

---

## How validators work

### Phase 1: Platform & Topology Detection

Asks which cloud platform and whether services are in a single container/task or separate ones.

### Phase 2: Configuration Schema

Asks if you have a template from the deployment script. If yes, auto-detects:
- LLM provider (Azure OpenAI, OpenAI, Bedrock, etc.)
- Whether Admin Console is deployed

If no template, interactively builds schema by asking:
- Which LLM provider?
- Is Admin Console deployed?

### Phase 3: Validation Execution

For each service:
- Fetches environment variables from live task definition or Container App
- Validates against the schema (required vars, format checks)
- Detects orphaned variables (e.g., OPENAI_API_KEY with wrong provider)
- Detects typos (e.g., DATABSE_URL → DATABASE_URL)
- Reports errors, warnings, and pass/fail status

### Phase 4: Report Generation

Writes a timestamped report file with:
- Platform and topology info
- LLM provider and Admin Console deployment status
- Summary: errors, warnings, OK variables
- Pass/fail status
- Recommendations for fixing issues

---

## Requirements

### Common

- Approved Spotfire Copilot image tags (from Spotfire Support or your platform team)
- Deployed Orchestrator and/or Admin Console on AWS ECS/Fargate or Azure Container Apps

### Linux / macOS (`spotfire-copilot-backend-validate-env.sh`)

- Bash 4 or newer
- AWS CLI (for AWS ECS validation) — or manually export env vars to JSON for offline validation
- Azure CLI (for Azure Container Apps validation) — or manually export env vars to JSON for offline validation

### Windows (`spotfire-copilot-backend-validate-env.ps1`)

- PowerShell 5.1 or newer
- AWS CLI (for AWS ECS validation) — or manually export env vars to JSON for offline validation
- Azure CLI (for Azure Container Apps validation) — or manually export env vars to JSON for offline validation

### No-CLI scenario

If you don't have AWS CLI or Azure CLI installed locally:

**Option 1: CloudShell export**
```bash
# In AWS CloudShell:
aws ecs describe-task-definition --cluster CLUSTER_NAME --task-definition TASK_NAME \
  --query taskDefinition.containerDefinitions[0].[environment,secrets] > export.json

# Download export.json locally, then:
./spotfire-copilot-backend-validate-env.sh --import export.json
```

**Option 2: Manual checklist**
Review the deployment script's generated `cloud-env-checklist.txt` and manually verify env vars in the AWS/Azure console.

---

## Example Report Output

```
========================================================================
Spotfire Copilot Environment Validation Report
========================================================================

Generated: Mon Aug  4 14:30:22 UTC 2026
Platform: AWS ECS/Fargate
Region: us-east-1
Cluster: spotfire-copilot
Task Definitions: spotfire-copilot-orchestrator, spotfire-copilot-admin-console

LLM Provider: azure_openai
Admin Console Deployed: Yes

========================================================================

Validating container: spotfire-copilot-orchestrator
  ✓ IMAGE_TAG — present
  ✓ FASTAPI_APP_VERSION — present
  ✓ LOG_LEVEL — present
  ✓ SECRET_KEY — present (secret ref)
  ✓ HASHED_ADMIN_PASSWORD — present (secret ref)
  ✓ DATABASE_URL — present
  ✗ OPENAI_API_KEY — MISSING [REQUIRED for Azure OpenAI]
  ⚠ NVIDIA_API_KEY — orphaned (you're using azure_openai, not NVIDIA NIM)

Validating container: spotfire-copilot-admin-console
  ✓ IMAGE_TAG — present
  ✓ SYNC_DATABASE_URL — present
  ✓ HASHED_ADMIN_PASSWORD — present (secret ref)

Summary:
  Errors:   1 (OPENAI_API_KEY missing)
  Warnings: 1 (orphaned NVIDIA_API_KEY)
  OK:       8 vars

Status: ✗ VALIDATION FAILED

========================================================================
```

---

## Troubleshooting

| Issue | Solution |
| --- | --- |
| `AWS CLI not found` | Install AWS CLI, or export env vars manually from CloudShell and import the JSON file locally. |
| `Azure CLI not found` | Install Azure CLI, or export env vars manually from Azure Portal and import the JSON file locally. |
| `Failed to fetch task definition` | Verify cluster name, region, and task definition name are correct. Check AWS IAM permissions. |
| `HASHED_ADMIN_PASSWORD — MISSING` | Ensure SECRET_KEY and HASHED_ADMIN_PASSWORD are stored in AWS Secrets Manager or Azure Key Vault, and task definition references them. |
| `OPENAI_API_KEY — orphaned` | You selected provider X but have keys for provider Y. Remove the orphaned key or update the LLM provider. |
| `Invalid DATABASE_URL format` | Use `postgresql://user:pass@host:port/db?sslmode=require` for sync, or `postgresql+asyncpg://...` for async. |
| `PowerShell execution policy` | Run `powershell -ExecutionPolicy Bypass -File .\spotfire-copilot-backend-validate-env.ps1` to bypass. |

---

**Related documentation:**
[Backend Deployment Scripts User Guide](../Spotfire%20Copilot%20-%20Backend%20Deployment%20Scripts%20User%20Guide.md) ·
[Backend Setup Installation Guide](../../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md) ·
[Admin Console Guide](../../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Admin%20Console%20Guide.md)
