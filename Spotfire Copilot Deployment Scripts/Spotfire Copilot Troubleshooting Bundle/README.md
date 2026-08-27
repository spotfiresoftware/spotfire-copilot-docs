# Spotfire Copilot Troubleshooting Bundle

Post-deployment troubleshooting toolkit for Spotfire Copilot environments. Use it to **validate environment variables** across deployed services, and to **collect container logs** into a single zipped **Troubleshooting Bundle** you can attach to a Spotfire support case.

---

## Table of Contents

- [Overview](#overview)
- [When to use](#when-to-use)
- [Scripts](#scripts)
- [Quick start](#quick-start)
- [Collecting logs into a bundle](#collecting-logs-into-a-bundle)
- [How it works](#how-it-works)
- [Requirements](#requirements)

---

## Overview

After deploying Spotfire Copilot to AWS ECS/Fargate, Azure Container Apps, on-prem Docker Compose, or Kubernetes (EKS/AKS/GKE), operators often need to verify that:

- ✅ All required environment variables are present
- ✅ Secret references are correctly configured
- ✅ LLM provider variables match the selected provider (no orphaned keys)
- ✅ Database connection strings use correct formats
- ✅ No typos or misconfigurations are present

… or simply to **collect container logs** quickly when something is failing.

This toolkit provides an **interactive, multi-phase audit** (for AWS ECS and Azure Container Apps) without resolving actual secret values (for security), plus **one-command log collection** on all four platforms that packages everything into a single **Troubleshooting Bundle** zip.

---

## When to use

**Best time:** After deployment, before users access the system

**Typical workflow:**
1. Run deployment script (`spotfire-copilot-backend-deploy*.sh/ps1`)
2. Deploy to cloud platform (AWS ECS / Azure ACA)
3. **Run the troubleshooting bundle** to catch configuration errors (or collect logs)
4. Fix issues if needed
5. Start the application services

**Also useful for:**
- Day-2 operations audits
- Post-upgrade validation
- Configuration drift detection
- Troubleshooting startup failures

---

## Scripts

### `spotfire-copilot-troubleshooting-bundle.sh` / `.ps1`

Validates environment variables for **Spotfire Copilot Orchestrator** and **Admin Console** (on AWS ECS/Fargate or Azure Container Apps), and collects container logs into a **Troubleshooting Bundle** zip on any supported platform.

**Supported platforms:**
- AWS ECS/Fargate — identify by ECS **service name** (resolves the running task definition) or task definition name; single or separate deployments
- Azure Container Apps (single or multiple Container Apps)
- Docker Compose (on-prem) — *log collection*
- Kubernetes / EKS / AKS / GKE — *log collection*

> **Validation** (env-variable auditing) applies to AWS ECS and Azure Container Apps. **Log collection** (the bundle) works on all four platforms. On Docker Compose and Kubernetes the tool runs in log-collection mode only.

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
cd "Spotfire Copilot Troubleshooting Bundle"
chmod +x spotfire-copilot-troubleshooting-bundle.sh
./spotfire-copilot-troubleshooting-bundle.sh
```

**Windows (PowerShell)**

```powershell
cd "Spotfire Copilot Troubleshooting Bundle"
.\spotfire-copilot-troubleshooting-bundle.ps1
```

Then answer the interactive prompts:

1. **Platform:** AWS ECS, Azure Container Apps, Docker Compose (on-prem), or Kubernetes (EKS/AKS/GKE)? *(Compose and Kubernetes run in log-collection mode only.)*
2. **Preflight (Phase 0):** The validator first checks local prerequisites (`jq` for the Bash script; PowerShell needs none), then confirms the matching CLI (AWS or Azure) is **installed**, **authenticated**, and can **reach your resources** — it lists your ECS clusters / Azure resource groups to prove connectivity. If any check fails, it prints the exact install/configure command **for your OS** and stops.
3. **Topology:** On AWS, identify what to validate by **ECS service name** (recommended — the validator resolves the task definition each service is actually running) or by **task definition name** directly. Then choose all-in-one or separate (orchestrator + admin-console). On Azure, the validator **auto-discovers** your subscriptions, resource groups, and Container Apps and lets you **pick from a numbered list** — the region is derived automatically from the chosen resource group (you can still type a name manually if something isn't listed).
4. **Schema:** Do you have a config template from our deploy script?
   - Yes → Load LLM provider + Admin Console settings from template
   - No → Interactively select LLM provider + whether Admin Console is deployed
5. **Validation:** Fetch env vars from live services and check against schema
6. **Report:** Write timestamped report file to current directory

> **Your answers are saved.** After you finish entering the prompts, the tool writes them to `troubleshooting-bundle-answers.env` in the current directory. On the next run it offers to **resume** with those answers so you don't have to re-enter everything if you need to re-run (for example after fixing a misconfiguration). Delete the file to start fresh, or set `TROUBLESHOOTING_ANSWERS_FILE` (Bash) / `$env:TROUBLESHOOTING_ANSWERS_FILE` (PowerShell) to change its location.

---

## Collecting logs into a bundle

Run with `--logs` (Bash) / `-Logs` (PowerShell) to **skip validation** and go straight to log collection. On **Docker Compose** and **Kubernetes** the tool is always in this mode (there is no env-variable validation for those platforms).

```bash
# Linux / macOS
./spotfire-copilot-troubleshooting-bundle.sh --logs

# Windows
.\spotfire-copilot-troubleshooting-bundle.ps1 -Logs
```

The tool asks which container's logs you want (**Orchestrator / Admin Console / Both**), collects them, and packages everything — one log file per container plus a `manifest.txt` — into a single zip named:

```
Spotfire Copilot Troubleshooting Bundle <YYYYMMDD-HHMMSS>.zip
```

Attach that file to your Spotfire support case.

**How logs are collected per platform:**

| Platform | Command | Notes |
| --- | --- | --- |
| AWS ECS/Fargate | `aws logs tail <group> --since <window>` | Requires the `awslogs` log driver and CloudWatch read access |
| Azure Container Apps | `az containerapp logs show --tail 2000` | ACA has no time-window flag; a 2000-line cap is used |
| Docker Compose (on-prem) | `docker compose -f <file> logs --since <window> <service>` | Needs only Docker — no cloud CLI/auth |
| Kubernetes (EKS/AKS/GKE) | `kubectl -n <ns> logs deployment/<name> --since=<window>` | Adds `--previous` to also grab crashed/restarted pod logs |

**Docker Compose prompts:** whether you deployed with the Spotfire Copilot deployment scripts (if yes, standard service names `orchestrator` / `admin-console` are used automatically), the compose file path, and an optional project name.

**Kubernetes prompts:** kubectl context (blank = current), namespace (default `copilot`), whether you used the deployment scripts (standard deployments `orchestrator` / `admin-console`), and whether to include previous (crashed) pod logs.

**Log window:** defaults to `1h`. Override with the `LOG_SINCE` environment variable (applies to AWS ECS, Docker Compose, and Kubernetes — not Azure ACA):

```bash
LOG_SINCE=6h ./spotfire-copilot-troubleshooting-bundle.sh --logs
```

---

## How it works

### Phase 0: Prerequisites & CLI Preflight

Immediately after you pick a platform, the validator confirms the environment is ready **before** asking for cluster/app names.

First it checks local **prerequisites**:

- **Bash (`.sh`):** requires `jq` for JSON parsing. If it's missing, the script prints the install command for your OS (e.g. `brew install jq` on macOS) and stops.
- **PowerShell (`.ps1`):** parses JSON natively (`ConvertFrom-Json`), so **no `jq` is needed** — it just confirms PowerShell 5.1+.

Then it runs three checks against the matching CLI. All install guidance is **OS-aware** — you only see the command for the OS you're running on (macOS `brew`, Windows `winget`/MSI, or Linux).

**AWS ECS**

| Check | Command run | If it fails |
| --- | --- | --- |
| CLI installed | `aws --version` | Prints the install command for your OS (macOS brew / Windows winget or MSI / Linux zip) and exits |
| Authenticated | `aws sts get-caller-identity` | Prints `aws configure` / `aws configure sso` / env-var guidance and exits |
| Can reach ECS | `aws ecs list-clusters` | Prints IAM/region guidance and exits; lists visible clusters on success |

**Azure Container Apps**

| Check | Command run | If it fails |
| --- | --- | --- |
| CLI installed | `az version` | Prints the install command for your OS (macOS brew / Windows winget or MSI / Linux) and exits |
| Logged in | `az account show` | Prints `az login` / `az login --use-device-code` / `az account set` guidance and exits |
| Can reach resources | `az group list` | Prints permission/subscription guidance and exits; lists visible resource groups on success |

On success it prints the clusters / resource groups the identity can see, so you can confirm you are pointed at the right account and region before continuing.

### Phase 1: Platform & Topology Detection

Asks which cloud platform and whether services are in a single task/Container App or separate ones:

- **All-in-one** — both Orchestrator and Admin Console share one task definition / Container App. The validator picks each service container by name (`orchestrator` / `admin`).
- **Separate (individual containers)** — you enter the Orchestrator name first, then the Admin Console name. The schema is bound to that **entry order**, not the container's name, so the audit works even if your containers use custom names.

**Identify by ECS service or task definition (AWS)**

On AWS you first choose how to name what to validate:

- **ECS service name (recommended)** — enter the service name(s) and the validator resolves the task definition each service is *currently running* via `aws ecs describe-services ... --query 'services[0].taskDefinition'`. This validates exactly what's deployed and live, so you don't have to know the revision number.
- **Task definition name** — enter the task definition name directly (existing behaviour).

Azure Container Apps are already the deployable/running unit, so on Azure the validator **auto-discovers** the subscription, resource group, and Container Apps and lets you pick from a numbered list — no separate service-vs-definition choice is needed, and the region is derived automatically from the resource group.

### Resume: saved answers

After you complete the prompts (Phase 1 + Phase 2), the tool writes your answers to `troubleshooting-bundle-answers.env` in the current directory (`KEY=VALUE`, `chmod 600` on Bash). On the next run it shows a summary of the saved answers and asks **"Resume with these saved answers? (y/n)"**:

- **Yes** — it loads every answer, re-runs the Phase 0 CLI preflight (so connectivity is always re-checked), and goes straight to validation. Nothing is re-typed.
- **No** — it walks the prompts normally and overwrites the file with your new answers.

This means an interrupted or failed run (or one where you fixed a misconfiguration and want to re-check) never forces you to start over. The file is shared by both the Bash and PowerShell scripts. Delete it to start fresh, or point `TROUBLESHOOTING_ANSWERS_FILE` / `$env:TROUBLESHOOTING_ANSWERS_FILE` elsewhere.

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

### AWS ECS/Fargate prerequisites

Before running the validator against AWS, make sure the CLI is **installed** and **configured to reach your account** (the Phase 0 preflight checks all of this and stops with guidance if anything is missing):

1. **Install the AWS CLI v2** (Phase 0 prints only the line for your OS)
   - Windows: `winget install -e --id Amazon.AWSCLI` (or the MSI: https://awscli.amazonaws.com/AWSCLIV2.msi)
   - macOS: `brew install awscli`
   - Linux: `curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install`
   - Docs: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
2. **Configure credentials + default region** (any one of):
   - `aws configure` (static access key + secret + region)
   - `aws configure sso` (IAM Identity Center / SSO)
   - Export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION`
3. **Verify connectivity** — these must succeed and show your cluster:
   ```bash
   aws sts get-caller-identity          # confirms who you are
   aws ecs list-clusters                # must list your ECS cluster
   ```
4. **IAM permissions required:** `sts:GetCallerIdentity`, `ecs:ListClusters`, `ecs:DescribeTaskDefinition`.

### Azure Container Apps prerequisites

1. **Install the Azure CLI** (Phase 0 prints only the line for your OS)
   - Windows: `winget install -e --id Microsoft.AzureCLI` (or the MSI: https://aka.ms/installazurecliwindows)
   - macOS: `brew install azure-cli`
   - Linux: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`
   - Docs: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
2. **Log in and select the subscription:**
   - `az login` (or `az login --use-device-code` for headless hosts)
   - `az account set --subscription <SUBSCRIPTION_ID>`
3. **Verify connectivity** — these must succeed and show your app:
   ```bash
   az account show                      # confirms subscription
   az group list                        # must list your resource group
   az containerapp show --resource-group <RG> --name <APP>   # confirms app access
   ```
4. **Permissions required:** `Reader` on the resource group (or `Microsoft.App/containerApps/read`).

### Linux / macOS (`spotfire-copilot-troubleshooting-bundle.sh`)

- Bash 4 or newer
- `jq` (JSON parsing for AWS/Azure validation — the script prints the install command for your OS if it's missing; **not needed for Docker Compose or Kubernetes log collection**)
- AWS CLI (for AWS ECS validation) — or manually export env vars to JSON for offline validation
- Azure CLI (for Azure Container Apps validation) — or manually export env vars to JSON for offline validation
- Docker Engine 20.10+ with Compose V2 (for Docker Compose log collection)
- `kubectl` with a working context (for Kubernetes log collection; for EKS run `aws eks update-kubeconfig` first)
- `zip` (optional — the Bash script falls back to `python3 -m zipfile`, then `tar`, to build the bundle)

### Windows (`spotfire-copilot-troubleshooting-bundle.ps1`)

- PowerShell 5.1 or newer (parses JSON natively — **no `jq` required**; `Compress-Archive` builds the bundle)
- AWS CLI (for AWS ECS validation) — install via `winget install -e --id Amazon.AWSCLI`, or manually export env vars to JSON for offline validation
- Azure CLI (for Azure Container Apps validation) — install via `winget install -e --id Microsoft.AzureCLI`, or manually export env vars to JSON for offline validation
- Docker Desktop with Compose V2 (for Docker Compose log collection)
- `kubectl` with a working context (for Kubernetes log collection)

### No-CLI scenario

If you don't have AWS CLI or Azure CLI installed locally:

**Option 1: CloudShell export**
```bash
# In AWS CloudShell:
aws ecs describe-task-definition --cluster CLUSTER_NAME --task-definition TASK_NAME \
  --query taskDefinition.containerDefinitions[0].[environment,secrets] > export.json

# Download export.json locally, then:
./spotfire-copilot-troubleshooting-bundle.sh --import export.json
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
| `Could not resolve a task definition for ECS service` | Verify the ECS service name, cluster, and region. The service must exist in that cluster and your IAM identity needs `ecs:DescribeServices`. |
| `HASHED_ADMIN_PASSWORD — MISSING` | Ensure SECRET_KEY and HASHED_ADMIN_PASSWORD are stored in AWS Secrets Manager or Azure Key Vault, and task definition references them. |
| `OPENAI_API_KEY — orphaned` | You selected provider X but have keys for provider Y. Remove the orphaned key or update the LLM provider. |
| `Invalid DATABASE_URL format` | Use `postgresql://user:pass@host:port/db?sslmode=require` for sync, or `postgresql+asyncpg://...` for async. |
| `PowerShell execution policy` | Run `powershell -ExecutionPolicy Bypass -File .\spotfire-copilot-troubleshooting-bundle.ps1` to bypass. |

---

**Related documentation:**
[Backend Deployment Scripts User Guide](../Spotfire%20Copilot%20-%20Backend%20Deployment%20Scripts%20User%20Guide.md) ·
[Backend Setup Installation Guide](../../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md) ·
[Admin Console Guide](../../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Admin%20Console%20Guide.md)
