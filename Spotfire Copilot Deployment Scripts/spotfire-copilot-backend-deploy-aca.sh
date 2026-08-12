#!/usr/bin/env bash
# ==============================================================================
#  Spotfire Copilot — Azure Container Apps Deployment Script
#  Version: 2.3.x
#
#  Usage:
#    ./spotfire-copilot-backend-deploy-aca.sh  (with Phase 1-2 variables exported from main script)
#    ./spotfire-copilot-backend-deploy-aca.sh --dir /opt/spotfire-copilot/backend
#    ./spotfire-copilot-backend-deploy-aca.sh --help
#
#  Flow:
#    Phase 1-2 SKIPPED (handled by main script: spotfire-copilot-backend-deploy.sh)
#    Phase 3  — Collect Azure Container Apps-specific inputs (resource group, app name, etc.)
#    Phase 4  — Check if Azure CLI is installed
#               YES → deploy directly (or write + offer to run)
#               NO  → write azcli-deploy.sh for Azure Cloud Shell
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_DIR="$(pwd)"
DEFAULT_IMAGE_TAG="${DEFAULT_IMAGE_TAG:-2.3.4}"
COPILOT_ROOT_DIR="${COPILOT_ROOT_DIR:-$START_DIR/spotfire-copilot}"
OUT_DIR="${OUT_DIR:-$COPILOT_ROOT_DIR/$DEFAULT_IMAGE_TAG/backend}"
OUT_DIR_EXPLICIT="${OUT_DIR_EXPLICIT:-no}"
CREDENTIALS_SCRIPT=""
CREDENTIALS_FILE=""
PYTHON_BIN="${PYTHON_BIN:-}"

# ── colour helpers ──────────────────────────────────────────────────────────
USE_COLOR="yes"
[[ -t 1 ]] || USE_COLOR="no"
[[ "${FORCE_COLOR:-}" == "no" ]] && USE_COLOR="no"
c_reset=""; c_cyan=""; c_green=""; c_yellow=""; c_red=""; c_magenta=""
if [[ "$USE_COLOR" == "yes" ]]; then
  c_reset="\033[0m"; c_cyan="\033[0;36m"; c_green="\033[0;32m"
  c_yellow="\033[0;33m"; c_red="\033[0;31m"; c_magenta="\033[0;35m"
fi
section() { echo; echo -e "${c_magenta}== $1 ==${c_reset}"; }
info()    { echo -e "${c_cyan}INFO:${c_reset} $1"; }
ok()      { echo -e "${c_green}OK:${c_reset} $1"; }
warn()    { echo -e "${c_yellow}WARN:${c_reset} $1"; }
die()     { echo -e "${c_red}ERROR:${c_reset} $1" >&2; exit 1; }

# ── arg parsing ─────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      echo "Spotfire Copilot Azure Container Apps Deployment Script"
      echo "Usage: $0 [--dir DIR] [--image-tag TAG] [--yes] [--no-color]"
      exit 0 ;;
    --dir)        OUT_DIR="${2:-}"; OUT_DIR_EXPLICIT="yes"; shift 2 ;;
    --image-tag)  DEFAULT_IMAGE_TAG="${2:-}"; shift 2 ;;
    --yes|-y)     ASSUME_YES="yes"; shift ;;
    --no-color)   USE_COLOR="no"; shift ;;
    *) die "Unknown option: $1. Use --help." ;;
  esac
done

# ── prompt helpers ───────────────────────────────────────────────────────────
prompt() {
  local _var="$1" _label="$2" _default="${3:-}" _secret="${4:-no}"
  local _input=""
  if [[ "$_secret" == "true" || "$_secret" == "yes" ]]; then
    read -r -s -p "$_label${_default:+ [$_default]}: " _input; echo
  else
    read -r -p "$_label${_default:+ [$_default]}: " _input
  fi
  _input="$(printf '%s' "$_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$_input" ]] && _input="$_default"
  printf -v "$_var" '%s' "$_input"
}

yes_no() {
  local _var="$1" _label="$2" _default="${3:-yes}"
  local _input=""
  while true; do
    read -r -p "$_label [${_default}] (yes/no): " _input
    _input="${_input:-$_default}"
    case "${_input,,}" in
      y|yes) printf -v "$_var" 'yes'; return ;;
      n|no)  printf -v "$_var" 'no';  return ;;
      *) warn "Please enter yes or no." ;;
    esac
  done
}

choose_num() {
  local _var="$1" _label="$2" _default="$3"; shift 3
  local _opts=("$@") _i=1
  echo; echo "$_label:"
  for _o in "${_opts[@]}"; do echo "  $_i) ${_o#*|}"; ((_i++)); done
  local _input=""
  while true; do
    read -r -p "Choice [${_default}]: " _input
    _input="${_input:-$_default}"
    if [[ "$_input" =~ ^[0-9]+$ ]] && (( _input >= 1 && _input <= ${#_opts[@]} )); then
      local _chosen="${_opts[((_input-1))]}"
      printf -v "$_var" '%s' "${_chosen%%|*}"
      return
    fi
    warn "Enter a number between 1 and ${#_opts[@]}."
  done
}

# ── credential helpers ───────────────────────────────────────────────────────
get_existing() {
  local key="$1"; shift
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    local val
    val="$(grep -E "^[[:space:]]*${key}=" "$f" 2>/dev/null | tail -1 | sed "s/^[^=]*=//" | tr -d '\r')" || true
    [[ -n "$val" ]] && echo "$val" && return 0
  done
  return 1
}

get_from_credentials_file() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 1
  local val
  val="$(grep -E "^[[:space:]]*${key}[[:space:]]*[:=]" "$file" 2>/dev/null | tail -1 | sed 's/^[^:=]*[:=][[:space:]]*//' | tr -d '\r')" || true
  [[ -n "$val" ]] && echo "$val" && return 0
  return 1
}

random_hex_32() { openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))"; }

select_python_bin() {
  for cand in "${PYTHON_BIN:-}" python3.12 python3.11 python3; do
    [[ -n "$cand" ]] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c "import sys; raise SystemExit(0 if sys.version_info>=(3,11) else 1)" >/dev/null 2>&1; then
      PYTHON_BIN="$(command -v "$cand")"; return 0
    fi
  done
  return 1
}

python_has_bcrypt() {
  [[ -n "${PYTHON_BIN:-}" ]] || select_python_bin || return 1
  "$PYTHON_BIN" -c "import bcrypt" >/dev/null 2>&1
}

find_credentials_script() {
  [[ -n "${CREDENTIALS_SCRIPT:-}" ]] && [[ -f "$CREDENTIALS_SCRIPT" ]] && echo "$CREDENTIALS_SCRIPT" && return 0
  for cand in "$SCRIPT_DIR/generate_credentials.py" "$START_DIR/generate_credentials.py" "$OUT_DIR/generate_credentials.py"; do
    [[ -f "$cand" ]] && echo "$cand" && return 0
  done
  return 1
}

generate_credentials() {
  local out_file="$1"
  select_python_bin || die "Python 3.11+ is required to generate credentials."
  python_has_bcrypt || die "Python bcrypt module is required. Install: pip install bcrypt"
  local cred_script
  cred_script="$(find_credentials_script)" || die "generate_credentials.py not found. Place it next to this script."
  info "Running generate_credentials.py …"
  local tmp; tmp="$(mktemp -d)"
  ( cd "$tmp" && "$PYTHON_BIN" "$cred_script" ) 2>&1
  local produced; produced="$(find "$tmp" -maxdepth 1 -type f 2>/dev/null | head -1 || true)"
  if [[ -n "$produced" ]]; then cp "$produced" "$out_file"; else cp "$tmp"/*.log "$out_file" 2>/dev/null || true; fi
  rm -rf "$tmp"
  chmod 600 "$out_file" 2>/dev/null || true
  ok "Credentials written to $out_file"
}

# ── LLM provider collection ──────────────────────────────────────────────────
category_block_commented() {
  local prefix="$1" primary="$2" temp_reasoning="${3:-0.2}"
  cat <<EOM
# OPTIONAL per-category model overrides. Each category falls back to MODEL_NAME (${primary}) unless BOTH
# the *_MODEL and *_TEMPERATURE for that category are set. Uncomment and edit to override the image defaults.
#${prefix}_FAST_MODEL=${primary}
#${prefix}_FAST_TEMPERATURE=0.3
#${prefix}_LARGE_MODEL=${primary}
#${prefix}_LARGE_TEMPERATURE=0.2
#${prefix}_VISION_MODEL=${primary}
#${prefix}_VISION_TEMPERATURE=0.1
#${prefix}_CODE_MODEL=${primary}
#${prefix}_CODE_TEMPERATURE=0.0
#${prefix}_REASONING_MODEL=${primary}
#${prefix}_REASONING_TEMPERATURE=${temp_reasoning}
EOM
}

collect_llm_provider() {
  choose_num LLM_PROVIDER "Select LLM provider" "1" \
    "azure_openai|Azure OpenAI" \
    "openai|OpenAI" \
    "aws_bedrock|AWS Bedrock" \
    "vertex_ai|Google Vertex AI" \
    "gemini|Google Gemini API" \
    "nvidia_nim|NVIDIA NIM" \
    "ollama|Ollama / self-hosted test"

  case "$LLM_PROVIDER" in
    azure_openai)
      prompt OPENAI_API_KEY        "Azure OpenAI API key"        "" "yes"
      prompt AZURE_OPENAI_ENDPOINT "Azure OpenAI endpoint"       "https://your-resource.openai.azure.com/"
      prompt OPENAI_API_VERSION    "Azure OpenAI API version"    "2024-02-15-preview"
      prompt PRIMARY_MODEL         "Primary deployment name"     "gpt-4o"
      MODEL_PLUGIN="plugins.models.azure_openai_enhanced:AzureOpenAIPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
OPENAI_API_TYPE=azure
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
OPENAI_API_VERSION=${OPENAI_API_VERSION}
MODEL_NAME=${PRIMARY_MODEL}"
      LLM_SECRETS_BLOCK="OPENAI_API_KEY=${OPENAI_API_KEY}"
      ;;
    openai)
      prompt OPENAI_API_KEY  "OpenAI API key"             "" "yes"
      prompt OPENAI_API_BASE "Custom base URL (optional)" ""
      prompt PRIMARY_MODEL   "Primary model name"         "gpt-4o"
      MODEL_PLUGIN="plugins.models.openai_enhanced:OpenAIPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
OPENAI_API_TYPE=openai
MODEL_NAME=${PRIMARY_MODEL}${OPENAI_API_BASE:+
OPENAI_API_BASE=${OPENAI_API_BASE}}"
      LLM_SECRETS_BLOCK="OPENAI_API_KEY=${OPENAI_API_KEY}"
      ;;
    aws_bedrock)
      prompt AWS_REGION    "AWS region"     "us-east-1"
      prompt PRIMARY_MODEL "Bedrock model ID" "anthropic.claude-3-5-sonnet-20241022-v2:0"
      yes_no USE_AWS_KEYS  "Use explicit AWS keys (No = IAM role)" "no"
      LLM_SECRETS_BLOCK=""
      if [[ "$USE_AWS_KEYS" == "yes" ]]; then
        prompt AWS_ACCESS_KEY_ID     "AWS_ACCESS_KEY_ID"     "" "yes"
        prompt AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY" "" "yes"
        LLM_SECRETS_BLOCK="AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
      fi
      MODEL_PLUGIN="plugins.models.bedrock_enhanced:BedrockPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
AWS_REGION=${AWS_REGION}
MODEL_NAME=${PRIMARY_MODEL}"
      ;;
    vertex_ai)
      prompt PROJECT_ID                    "GCP project ID"            "your-gcp-project"
      prompt LOCATION_ID                   "GCP location"              "us-central1"
      prompt GOOGLE_APPLICATION_CREDENTIALS "SA JSON path in container" "/app/credentials/sa.json"
      prompt PRIMARY_MODEL                 "Vertex AI model"           "gemini-2.0-flash"
      MODEL_PLUGIN="plugins.models.vertexai_enhanced:VertexAIPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
PROJECT_ID=${PROJECT_ID}
LOCATION_ID=${LOCATION_ID}
GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}
MODEL_NAME=${PRIMARY_MODEL}"
      LLM_SECRETS_BLOCK=""
      ;;
    gemini)
      prompt GOOGLE_API_KEY "Google Gemini API key" "" "yes"
      prompt PRIMARY_MODEL  "Gemini model"          "gemini-2.0-flash"
      MODEL_PLUGIN="plugins.models.gemini_enhanced:GeminiPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
MODEL_NAME=${PRIMARY_MODEL}"
      LLM_SECRETS_BLOCK="GOOGLE_API_KEY=${GOOGLE_API_KEY}"
      ;;
    nvidia_nim)
      prompt NVIDIA_API_KEY  "NVIDIA API key"  "" "yes"
      prompt NVIDIA_BASE_URL "NVIDIA base URL" "https://integrate.api.nvidia.com/v1"
      prompt PRIMARY_MODEL   "NIM model"       "meta/llama-3.1-70b-instruct"
      MODEL_PLUGIN="plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
NVIDIA_BASE_URL=${NVIDIA_BASE_URL}
MODEL_NAME=${PRIMARY_MODEL}"
      LLM_SECRETS_BLOCK="NVIDIA_API_KEY=${NVIDIA_API_KEY}"
      ;;
    ollama)
      prompt OLLAMA_BASE_URL "Ollama base URL" "http://host.docker.internal:11434"
      prompt PRIMARY_MODEL   "Ollama model"    "llama3.1:8b"
      MODEL_PLUGIN="plugins.models.ollama_enhanced:OllamaPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
OLLAMA_BASE_URL=${OLLAMA_BASE_URL}
MODEL_NAME=${PRIMARY_MODEL}"
      LLM_SECRETS_BLOCK=""
      ;;
  esac

  # Append optional per-category model overrides (commented out) to the LLM env block.
  local _cat_prefix="" _cat_reason="0.2"
  case "$LLM_PROVIDER" in
    azure_openai) _cat_prefix="AZURE" ;;
    openai)       _cat_prefix="OPENAI" ;;
    aws_bedrock)  _cat_prefix="BEDROCK";  _cat_reason="1.0" ;;
    vertex_ai)    _cat_prefix="VERTEXAI"; _cat_reason="0.1" ;;
    gemini)       _cat_prefix="GEMINI";   _cat_reason="0.1" ;;
    nvidia_nim)   _cat_prefix="NVIDIA" ;;
    ollama)       _cat_prefix="OLLAMA" ;;
  esac
  if [[ -n "$_cat_prefix" ]]; then
    LLM_ENV_BLOCK="${LLM_ENV_BLOCK}
$(category_block_commented "$_cat_prefix" "$PRIMARY_MODEL" "$_cat_reason")"
  fi
}

# ── write cloud env checklist ─────────────────────────────────────────────────
write_cloud_env_checklist() {
  local out_file="$OUT_DIR/cloud-env-checklist.txt"
  mkdir -p "$OUT_DIR"
  local db_url="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?ssl=${DB_SSLMODE}}"
  local db_sync_url="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?sslmode=${DB_SSLMODE}}"
  cat > "$out_file" <<CHECKLIST
# ==============================================================================
# Spotfire Copilot — Azure Container Apps Cloud Env Checklist
# Generated: $(date)
# Image tag: ${IMAGE_TAG}
# Store SECRET values in Azure Key Vault or as ACA secrets.
# Use CONFIG values as plain Container App environment variables.
# ==============================================================================

# ── 01 CORE ───────────────────────────────────────────────────────────────────
# CONFIG
IMAGE_TAG=${IMAGE_TAG}
FASTAPI_APP_VERSION=${IMAGE_TAG}
LOG_LEVEL=INFO

# SECRET
SECRET_KEY=${C_SECRET_KEY}
HASHED_ADMIN_PASSWORD=${C_HASHED_ADMIN}
OAUTH2_CLIENT_ID=${C_OAUTH_ID}
OAUTH2_CLIENT_SECRET_HASH=${C_OAUTH_HASH}

# ── 02 DATABASE ───────────────────────────────────────────────────────────────
# SECRET
DATABASE_URL=${db_url}
SYNC_DATABASE_URL=${db_sync_url}

# CONFIG
DB_SSLMODE=${DB_SSLMODE}

# ── 03 LLM PROVIDER ───────────────────────────────────────────────────────────
# CONFIG
${LLM_ENV_BLOCK}

# SECRET
${LLM_SECRETS_BLOCK}

$(if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
cat <<ADMIN
# ── 04 ADMIN CONSOLE ─────────────────────────────────────────────────────────
ENABLE_ADMIN_CONSOLE=true
ADMIN_SECRET_KEY=${C_SECRET_KEY}
ADMIN
fi)

$(if [[ "$ENABLE_AGENT_REGISTRY" == "yes" ]]; then
cat <<AR
# ── 05 AGENT REGISTRY ────────────────────────────────────────────────────────
PORT=${AGENT_PORT:-8050}
BASE_URL=${AGENT_BASE_URL:-http://agent-registry:8050}
AUTH_CLIENT_ID=${AGENT_CLIENT_ID}
AUTH_CLIENT_SECRET=${AGENT_CLIENT_SECRET}
AUTH_SIGNING_KEY=${AGENT_SIGNING_KEY}
ORCHESTRATOR_URL=${ORCHESTRATOR_URL_FOR_AGENT:-http://orchestrator:8080}
AR
fi)
CHECKLIST
  chmod 600 "$out_file" 2>/dev/null || true
  ok "Cloud env checklist written: $out_file"
}

# ── build az containerapp env/secrets args ────────────────────────────────────
# ACA uses --env-vars for plain config and --secrets + secretref: for secrets.
# Secrets are stored directly in the Container App (no Key Vault required).

build_aca_env_args() {
  # Returns a space-separated list of KEY=VALUE pairs for --env-vars
  local block="$1" result=""
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    result+="${line} "
  done <<< "$block"
  echo "${result% }"
}

build_aca_secret_names() {
  # Returns a space-separated list of name=value pairs for --secrets
  local block="$1" result=""
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}" val="${line#*=}"
    [[ -z "$key" || -z "$val" ]] && continue
    # ACA secret names must be lowercase alphanumeric with hyphens
    local secret_name
    secret_name="$(echo "${key,,}" | tr '_' '-')"
    result+="${secret_name}=${val} "
  done <<< "$block"
  echo "${result% }"
}

build_aca_secretref_args() {
  # Returns space-separated KEY=secretref:name pairs for --env-vars (binding secrets)
  local block="$1" result=""
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}"
    [[ -z "$key" ]] && continue
    local secret_name
    secret_name="$(echo "${key,,}" | tr '_' '-')"
    result+="${key}=secretref:${secret_name} "
  done <<< "$block"
  echo "${result% }"
}

# ── write CloudShell deploy script ───────────────────────────────────────────
write_cloudshell_script() {
  local deploy_dir="$1"
  local script_file="${deploy_dir}/azcli-deploy.sh"

  local db_url="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?ssl=${DB_SSLMODE}}"
  local db_sync_url="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?sslmode=${DB_SSLMODE}}"

  # Build the secrets string for the orchestrator
  local orch_secrets="secret-key=${C_SECRET_KEY} hashed-admin-password=${C_HASHED_ADMIN} oauth2-client-id=${C_OAUTH_ID} oauth2-client-secret-hash=${C_OAUTH_HASH} database-url=${db_url} sync-database-url=${db_sync_url}"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}" val="${line#*=}"
    [[ -z "$key" || -z "$val" ]] && continue
    local sname; sname="$(echo "${key,,}" | tr '_' '-')"
    orch_secrets+=" ${sname}=${val}"
  done <<< "${LLM_SECRETS_BLOCK}"

  # Build env vars string for orchestrator (non-secrets)
  local orch_env="IMAGE_TAG=${IMAGE_TAG} FASTAPI_APP_VERSION=${IMAGE_TAG} LOG_LEVEL=INFO DB_SSLMODE=${DB_SSLMODE}"
  orch_env+=" $(build_aca_env_args "${LLM_ENV_BLOCK}")"
  # Add secretrefs for secret env vars
  local orch_secretrefs="SECRET_KEY=secretref:secret-key HASHED_ADMIN_PASSWORD=secretref:hashed-admin-password OAUTH2_CLIENT_ID=secretref:oauth2-client-id OAUTH2_CLIENT_SECRET_HASH=secretref:oauth2-client-secret-hash DATABASE_URL=secretref:database-url SYNC_DATABASE_URL=secretref:sync-database-url"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}"; [[ -z "$key" ]] && continue
    local sname; sname="$(echo "${key,,}" | tr '_' '-')"
    orch_secretrefs+=" ${key}=secretref:${sname}"
  done <<< "${LLM_SECRETS_BLOCK}"

  local admin_block=""
  if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
    local admin_secrets="secret-key=${C_SECRET_KEY} database-url=${db_url} sync-database-url=${db_sync_url}"
    local admin_env="IMAGE_TAG=${IMAGE_TAG} FASTAPI_APP_VERSION=${IMAGE_TAG} LOG_LEVEL=INFO ENABLE_ADMIN_CONSOLE=true"
    local admin_secretrefs="SECRET_KEY=secretref:secret-key DATABASE_URL=secretref:database-url SYNC_DATABASE_URL=secretref:sync-database-url"
    admin_block="
echo '==> Deploying Admin Console Container App...'
az containerapp create \\
  --name \"\${APP_PREFIX}-admin-console\" \\
  --resource-group \"\${RESOURCE_GROUP}\" \\
  --environment \"\${ACA_ENVIRONMENT}\" \\
  --image \"copilotoci.azurecr.io/spotfirecopilot/admin-console:\${IMAGE_TAG}\" \\
  --registry-server \"copilotoci.azurecr.io\" \\
  --registry-username \"\${ACR_USERNAME}\" \\
  --registry-password \"\${ACR_PASSWORD}\" \\
  --target-port 3000 \\
  --ingress external \\
  --min-replicas 1 \\
  --max-replicas 3 \\
  --cpu \"\${APP_CPU}\" \\
  --memory \"\${APP_MEMORY}\" \\
  --secrets \"${admin_secrets}\" \\
  --env-vars \"${admin_env} ${admin_secretrefs}\" 2>/dev/null || \\
az containerapp update \\
  --name \"\${APP_PREFIX}-admin-console\" \\
  --resource-group \"\${RESOURCE_GROUP}\" \\
  --image \"copilotoci.azurecr.io/spotfirecopilot/admin-console:\${IMAGE_TAG}\" \\
  --set-env-vars \"${admin_env} ${admin_secretrefs}\"
echo \"Admin Console URL: \$(az containerapp show --name \"\${APP_PREFIX}-admin-console\" --resource-group \"\${RESOURCE_GROUP}\" --query properties.configuration.ingress.fqdn --output tsv)\"
"
  fi

  cat > "$script_file" <<DEPLOY
#!/usr/bin/env bash
# ==============================================================================
#  Spotfire Copilot — Azure Container Apps CloudShell Deploy Script
#  Generated: $(date)
#  Run in Azure Cloud Shell: bash azcli-deploy.sh
# ==============================================================================
set -Eeuo pipefail

RESOURCE_GROUP="${ACA_RESOURCE_GROUP}"
ACA_ENVIRONMENT="${ACA_ENVIRONMENT}"
LOCATION="${ACA_LOCATION}"
APP_PREFIX="${ACA_APP_PREFIX}"
IMAGE_TAG="${IMAGE_TAG}"
APP_CPU="${ACA_CPU}"
APP_MEMORY="${ACA_MEMORY}"
MIN_REPLICAS="${ACA_MIN_REPLICAS}"
MAX_REPLICAS="${ACA_MAX_REPLICAS}"
ACR_USERNAME="${ACR_USERNAME}"
ACR_PASSWORD="${ACR_PASSWORD}"

echo "================================================================"
echo " Spotfire Copilot — Azure Container Apps Deployment"
echo " Resource Group:   \${RESOURCE_GROUP}"
echo " ACA Environment:  \${ACA_ENVIRONMENT}"
echo " Location:         \${LOCATION}"
echo "================================================================"

# ── Step 1: Create resource group (idempotent) ──────────────────────
echo "==> Creating/verifying resource group: \${RESOURCE_GROUP}"
az group create --name "\${RESOURCE_GROUP}" --location "\${LOCATION}" --output none

# ── Step 2: Create Container Apps environment (idempotent) ──────────
echo "==> Creating/verifying Container Apps environment: \${ACA_ENVIRONMENT}"
az containerapp env create \\
  --name "\${ACA_ENVIRONMENT}" \\
  --resource-group "\${RESOURCE_GROUP}" \\
  --location "\${LOCATION}" --output none 2>/dev/null || \\
  echo "  (environment already exists)"

# ── Step 3: Deploy Orchestrator Container App ───────────────────────
echo "==> Deploying Orchestrator Container App: \${APP_PREFIX}-orchestrator"
az containerapp create \\
  --name "\${APP_PREFIX}-orchestrator" \\
  --resource-group "\${RESOURCE_GROUP}" \\
  --environment "\${ACA_ENVIRONMENT}" \\
  --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:\${IMAGE_TAG}" \\
  --registry-server "copilotoci.azurecr.io" \\
  --registry-username "\${ACR_USERNAME}" \\
  --registry-password "\${ACR_PASSWORD}" \\
  --target-port 8080 \\
  --ingress external \\
  --min-replicas "\${MIN_REPLICAS}" \\
  --max-replicas "\${MAX_REPLICAS}" \\
  --cpu "\${APP_CPU}" \\
  --memory "\${APP_MEMORY}" \\
  --secrets "${orch_secrets}" \\
  --env-vars "${orch_env} ${orch_secretrefs}" 2>/dev/null || \\
az containerapp update \\
  --name "\${APP_PREFIX}-orchestrator" \\
  --resource-group "\${RESOURCE_GROUP}" \\
  --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:\${IMAGE_TAG}" \\
  --set-env-vars "${orch_env} ${orch_secretrefs}"

ORCH_URL=\$(az containerapp show \\
  --name "\${APP_PREFIX}-orchestrator" \\
  --resource-group "\${RESOURCE_GROUP}" \\
  --query properties.configuration.ingress.fqdn --output tsv)
echo "Orchestrator URL: https://\${ORCH_URL}"

${admin_block}

echo "================================================================"
echo " Deployment complete."
echo " Orchestrator: https://\${ORCH_URL}"
echo " Note: Update ORCHESTRATOR_BASE_URL in the Spotfire Copilot"
echo "       frontend configuration to point to the orchestrator URL."
echo "================================================================"
DEPLOY

  chmod 700 "$script_file"
  ok "CloudShell deploy script written: $script_file"
}

# ── direct Azure CLI deployment ───────────────────────────────────────────────
run_az_cli_deploy() {
  local deploy_dir="$1"

  section "Live Azure CLI Deployment"

  # Resource group
  info "Creating/verifying resource group: ${ACA_RESOURCE_GROUP}"
  az group create --name "${ACA_RESOURCE_GROUP}" --location "${ACA_LOCATION}" --output none
  ok "Resource group ready."

  # ACA environment
  info "Creating/verifying Container Apps environment: ${ACA_ENVIRONMENT}"
  az containerapp env create \
    --name "${ACA_ENVIRONMENT}" \
    --resource-group "${ACA_RESOURCE_GROUP}" \
    --location "${ACA_LOCATION}" --output none 2>/dev/null || \
    info "  (environment already exists)"
  ok "ACA environment ready."

  # Build secrets and env vars
  local db_url="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?ssl=${DB_SSLMODE}}"
  local db_sync_url="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?sslmode=${DB_SSLMODE}}"

  local orch_secrets="secret-key=${C_SECRET_KEY} hashed-admin-password=${C_HASHED_ADMIN} oauth2-client-id=${C_OAUTH_ID} oauth2-client-secret-hash=${C_OAUTH_HASH} database-url=${db_url} sync-database-url=${db_sync_url}"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}" val="${line#*=}"
    [[ -z "$key" || -z "$val" ]] && continue
    local sname; sname="$(echo "${key,,}" | tr '_' '-')"
    orch_secrets+=" ${sname}=${val}"
  done <<< "${LLM_SECRETS_BLOCK}"

  local orch_env="IMAGE_TAG=${IMAGE_TAG} FASTAPI_APP_VERSION=${IMAGE_TAG} LOG_LEVEL=INFO DB_SSLMODE=${DB_SSLMODE}"
  orch_env+=" $(build_aca_env_args "${LLM_ENV_BLOCK}")"
  local orch_secretrefs="SECRET_KEY=secretref:secret-key HASHED_ADMIN_PASSWORD=secretref:hashed-admin-password OAUTH2_CLIENT_ID=secretref:oauth2-client-id OAUTH2_CLIENT_SECRET_HASH=secretref:oauth2-client-secret-hash DATABASE_URL=secretref:database-url SYNC_DATABASE_URL=secretref:sync-database-url"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}"; [[ -z "$key" ]] && continue
    local sname; sname="$(echo "${key,,}" | tr '_' '-')"
    orch_secretrefs+=" ${key}=secretref:${sname}"
  done <<< "${LLM_SECRETS_BLOCK}"

  # Deploy orchestrator
  info "Deploying orchestrator Container App: ${ACA_APP_PREFIX}-orchestrator"
  # shellcheck disable=SC2086
  az containerapp create \
    --name "${ACA_APP_PREFIX}-orchestrator" \
    --resource-group "${ACA_RESOURCE_GROUP}" \
    --environment "${ACA_ENVIRONMENT}" \
    --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}" \
    --registry-server "copilotoci.azurecr.io" \
    --registry-username "${ACR_USERNAME}" \
    --registry-password "${ACR_PASSWORD}" \
    --target-port 8080 \
    --ingress external \
    --min-replicas "${ACA_MIN_REPLICAS}" \
    --max-replicas "${ACA_MAX_REPLICAS}" \
    --cpu "${ACA_CPU}" \
    --memory "${ACA_MEMORY}" \
    --secrets $orch_secrets \
    --env-vars $orch_env $orch_secretrefs 2>/dev/null || \
  az containerapp update \
    --name "${ACA_APP_PREFIX}-orchestrator" \
    --resource-group "${ACA_RESOURCE_GROUP}" \
    --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}" \
    --set-env-vars $orch_env $orch_secretrefs

  local orch_url
  orch_url="$(az containerapp show \
    --name "${ACA_APP_PREFIX}-orchestrator" \
    --resource-group "${ACA_RESOURCE_GROUP}" \
    --query properties.configuration.ingress.fqdn --output tsv)"
  ok "Orchestrator deployed: https://${orch_url}"

  # Deploy admin console if enabled
  if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
    local admin_secrets="secret-key=${C_SECRET_KEY} database-url=${db_url} sync-database-url=${db_sync_url}"
    local admin_env="IMAGE_TAG=${IMAGE_TAG} FASTAPI_APP_VERSION=${IMAGE_TAG} LOG_LEVEL=INFO ENABLE_ADMIN_CONSOLE=true"
    local admin_secretrefs="SECRET_KEY=secretref:secret-key DATABASE_URL=secretref:database-url SYNC_DATABASE_URL=secretref:sync-database-url"
    info "Deploying Admin Console Container App: ${ACA_APP_PREFIX}-admin-console"
    # shellcheck disable=SC2086
    az containerapp create \
      --name "${ACA_APP_PREFIX}-admin-console" \
      --resource-group "${ACA_RESOURCE_GROUP}" \
      --environment "${ACA_ENVIRONMENT}" \
      --image "copilotoci.azurecr.io/spotfirecopilot/admin-console:${IMAGE_TAG}" \
      --registry-server "copilotoci.azurecr.io" \
      --registry-username "${ACR_USERNAME}" \
      --registry-password "${ACR_PASSWORD}" \
      --target-port 3000 \
      --ingress external \
      --min-replicas "${ACA_MIN_REPLICAS}" \
      --max-replicas "${ACA_MAX_REPLICAS}" \
      --cpu "${ACA_CPU}" \
      --memory "${ACA_MEMORY}" \
      --secrets $admin_secrets \
      --env-vars $admin_env $admin_secretrefs 2>/dev/null || \
    az containerapp update \
      --name "${ACA_APP_PREFIX}-admin-console" \
      --resource-group "${ACA_RESOURCE_GROUP}" \
      --image "copilotoci.azurecr.io/spotfirecopilot/admin-console:${IMAGE_TAG}" \
      --set-env-vars $admin_env $admin_secretrefs

    local admin_url
    admin_url="$(az containerapp show \
      --name "${ACA_APP_PREFIX}-admin-console" \
      --resource-group "${ACA_RESOURCE_GROUP}" \
      --query properties.configuration.ingress.fqdn --output tsv)"
    ok "Admin Console deployed: https://${admin_url}"
  fi

  echo ""
  echo "================================================================"
  echo " Deployment complete."
  echo " Resource Group:  ${ACA_RESOURCE_GROUP}"
  echo " Orchestrator:    https://${orch_url}"
  echo " Note: Update ORCHESTRATOR_BASE_URL in the Spotfire Copilot"
  echo "       frontend configuration to point to the orchestrator URL."
  echo "================================================================"
}

# ════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════
echo "================================================================"
echo " Spotfire Copilot — Azure Container Apps Deployment (Phase 3-4)"
echo " This script runs Phases 3-4 only. Phase 1-2 must be run first."
echo "================================================================"

echo ""
info "Verifying Phase 1-2 variables are exported from main script..."
echo ""

# Verify required Phase 1-2 variables are set
for var in IMAGE_TAG FASTAPI_APP_VERSION LLM_PROVIDER LLM_ENV_BLOCK LLM_SECRETS_BLOCK SECRET_KEY HASHED_ADMIN_PASSWORD OAUTH2_CLIENT_ID OAUTH2_CLIENT_SECRET_HASH DATABASE_URL SYNC_DATABASE_URL DB_SSLMODE; do
  [[ -n "${!var:-}" ]] || die "Required variable not exported: $var. Ensure main script completed Phase 1-2."
done

if [[ "$OUT_DIR_EXPLICIT" == "no" ]]; then
  OUT_DIR="${COPILOT_ROOT_DIR}/${IMAGE_TAG}/backend"
fi
mkdir -p "${OUT_DIR}"
cd "${OUT_DIR}"; OUT_DIR="$(pwd)"
info "Using output directory: ${OUT_DIR}"

ok "Phase 1-2 variables validated ✓"
echo ""
section "Phase 3: Deployment method ──────────────────────────────────────"
section "Deployment method"
choose_num CLI_CHOICE "How would you like to deploy?" "1" \
  "cli_deploy|I have the Azure CLI installed and configured — deploy directly from this machine" \
  "no_cli|I don't have the Azure CLI installed yet" \
  "generate_only|I don't want to use the CLI — just generate the commands for me"

case "$CLI_CHOICE" in
  no_cli)
    echo ""
    info "Please install and configure the Azure CLI, then re-run this script."
    echo ""
    echo "  Install:    https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    echo "  Login:      az login"
    echo "  Set sub:    az account set --subscription <your-subscription-id>"
    echo ""
    info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
    echo "  ${OUT_DIR}/cloud-env-checklist.txt"
    echo "  ${OUT_DIR}/copilot-generated-values.txt"
    echo ""
    echo "Re-run with:  ./spotfire-copilot-deploy-aca.sh --dir ${OUT_DIR}"
    exit 0
    ;;

  cli_deploy|generate_only)
    yes_no HAVE_DETAILS "Do you have your Azure infrastructure details ready? (resource group, location, ACA environment name, ACR credentials)" "yes"
    if [[ "$HAVE_DETAILS" == "no" ]]; then
      echo ""
      info "Please gather the following details, then re-run this script:"
      echo ""
      echo "  Azure Container Apps details required:"
      echo "  ─────────────────────────────────────────────────────────"
      echo "  • Azure subscription ID"
      echo "  • Resource group name    (will be created if it doesn't exist)"
      echo "  • Azure region/location  (e.g. eastus, westeurope)"
      echo "  • ACA environment name   (will be created if it doesn't exist)"
      echo "  • Container App prefix   (e.g. spotfire-copilot)"
      echo "  • CPU cores per app      (e.g. 1.0)"
      echo "  • Memory per app         (e.g. 2.0Gi)"
      echo "  • Min / max replicas     (e.g. 1 / 3)"
      echo ""
      echo "  ACR pull credentials (from copilotoci.azurecr.io):"
      echo "  • ACR username"
      echo "  • ACR password"
      echo ""
      info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
      echo "  ${OUT_DIR}/cloud-env-checklist.txt"
      echo "  ${OUT_DIR}/copilot-generated-values.txt"
      echo ""
      echo "Re-run with:  ./spotfire-copilot-deploy-aca.sh --dir ${OUT_DIR}"
      exit 0
    fi

    # ── Collect ACA infrastructure details ────────────────────────────
    section "Azure Container Apps infrastructure details"
    prompt ACA_RESOURCE_GROUP "Resource group name"              "rg-spotfire-copilot"
    prompt ACA_LOCATION        "Azure location"                  "eastus"
    prompt ACA_ENVIRONMENT     "Container Apps environment name" "cae-spotfire-copilot"
    prompt ACA_APP_PREFIX      "Container App name prefix"       "spotfire-copilot"
    prompt ACA_CPU             "CPU cores per container app"     "1.0"
    prompt ACA_MEMORY          "Memory per container app (Gi)"   "2.0Gi"
    prompt ACA_MIN_REPLICAS    "Minimum replicas"                "1"
    prompt ACA_MAX_REPLICAS    "Maximum replicas"                "3"

    section "ACR pull credentials"
    info "Provide ACR credentials to pull images from copilotoci.azurecr.io."
    prompt ACR_USERNAME "ACR username" "spotfirecopilot"
    prompt ACR_PASSWORD "ACR password" "" "yes"

    DEPLOY_DIR="${OUT_DIR}/aca"
    mkdir -p "${DEPLOY_DIR}"

    if [[ "$CLI_CHOICE" == "cli_deploy" ]]; then
      section "Deploying via Azure CLI"
      run_az_cli_deploy "${DEPLOY_DIR}"
    else
      section "Generating Cloud Shell deploy script"
      write_cloudshell_script "${DEPLOY_DIR}"
    fi
    ;;
esac

echo ""
echo "================================================================"
echo " Output files:"
echo "   ${OUT_DIR}/cloud-env-checklist.txt"
[[ -d "${DEPLOY_DIR:-}" ]] && echo "   ${DEPLOY_DIR}/azcli-deploy.sh"
echo ""
if [[ "${CLI_CHOICE:-}" == "generate_only" ]]; then
  echo " To deploy from Azure Cloud Shell:"
  echo "   1. Upload azcli-deploy.sh to Cloud Shell"
  echo "   2. bash azcli-deploy.sh"
  echo ""
fi
echo " Note: Update ORCHESTRATOR_BASE_URL in the Spotfire Copilot"
echo "       frontend to point at the deployed orchestrator URL."
echo "================================================================"
