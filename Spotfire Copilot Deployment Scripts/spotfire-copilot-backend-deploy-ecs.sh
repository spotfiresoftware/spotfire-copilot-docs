#!/usr/bin/env bash
# ==============================================================================
#  Spotfire Copilot — AWS ECS / Fargate Deployment Script
#  Version: 2.3.x
#
#  Usage:
#    ./spotfire-copilot-backend-deploy-ecs.sh  (with Phase 1-2 variables exported from main script)
#    ./spotfire-copilot-backend-deploy-ecs.sh --dir /opt/spotfire-copilot/backend
#    ./spotfire-copilot-backend-deploy-ecs.sh --help
#
#  Flow:
#    Phase 1-2 SKIPPED (handled by main script: spotfire-copilot-backend-deploy.sh)
#    Phase 3  — Collect AWS ECS-specific inputs (cluster, subnets, security group, etc.)
#    Phase 4  — Check if AWS CLI is installed
#               YES → deploy directly (or write + offer to run)
#               NO  → write awscli-deploy.sh for AWS CloudShell
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
ASSUME_YES="no"

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
      echo "Spotfire Copilot AWS ECS / Fargate Deployment Script"
      echo "Usage: $0 [--dir DIR] [--image-tag TAG] [--yes]"
      echo "  --dir DIR         Output directory (default: ./spotfire-copilot/<tag>/backend)"
      echo "  --image-tag TAG   Default image tag"
      echo "  --yes             Auto-accept defaults where safe"
      echo "  --no-color        Disable coloured output"
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

prompt_required() {
  local _var="$1" _label="$2"
  local _val=""
  while true; do
    prompt _val "$_label" ""
    [[ -n "$_val" ]] && break
    warn "$_label is required."
  done
  printf -v "$_var" '%s' "$_val"
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
    if "$cand" - <<'PY' >/dev/null 2>&1
import sys; raise SystemExit(0 if sys.version_info>=(3,11) else 1)
PY
    then PYTHON_BIN="$(command -v "$cand")"; return 0; fi
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
  python_has_bcrypt || die "Python bcrypt module is required. Install it: pip install bcrypt"
  local cred_script
  cred_script="$(find_credentials_script)" || die "generate_credentials.py not found. Place it next to this script."
  info "Running generate_credentials.py …"
  local tmp
  tmp="$(mktemp -d)"
  ( cd "$tmp" && "$PYTHON_BIN" "$cred_script" ) 2>&1
  local produced
  produced="$(find "$tmp" -maxdepth 1 -type f 2>/dev/null | head -1 || true)"
  if [[ -n "$produced" ]]; then cp "$produced" "$out_file"; else cp "$tmp"/*.log "$out_file" 2>/dev/null || true; fi
  rm -rf "$tmp"
  chmod 600 "$out_file" 2>/dev/null || true
  ok "Credentials written to $out_file"
}

# ── LLM provider env block builders (same logic as main script) ──────────────
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
      prompt OPENAI_API_KEY     "Azure OpenAI API key"      "" "yes"
      prompt AZURE_OPENAI_ENDPOINT "Azure OpenAI endpoint"  "https://your-resource.openai.azure.com/"
      prompt OPENAI_API_VERSION "Azure OpenAI API version"  "2024-02-15-preview"
      prompt PRIMARY_MODEL      "Primary deployment name"   "gpt-4o"
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
      prompt OPENAI_API_KEY  "OpenAI API key"           "" "yes"
      prompt OPENAI_API_BASE "Custom base URL (optional)" ""
      prompt PRIMARY_MODEL   "Primary model name"        "gpt-4o"
      MODEL_PLUGIN="plugins.models.openai_enhanced:OpenAIPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
OPENAI_API_TYPE=openai
MODEL_NAME=${PRIMARY_MODEL}${OPENAI_API_BASE:+
OPENAI_API_BASE=${OPENAI_API_BASE}}"
      LLM_SECRETS_BLOCK="OPENAI_API_KEY=${OPENAI_API_KEY}"
      ;;
    aws_bedrock)
      prompt AWS_REGION      "AWS region"               "us-east-1"
      prompt PRIMARY_MODEL   "Bedrock model ID"         "anthropic.claude-3-5-sonnet-20241022-v2:0"
      yes_no USE_AWS_KEYS    "Use explicit AWS keys (No = IAM/task role)" "no"
      AWS_KEYS_ENV=""; AWS_KEYS_SECRETS=""
      if [[ "$USE_AWS_KEYS" == "yes" ]]; then
        prompt AWS_ACCESS_KEY_ID     "AWS_ACCESS_KEY_ID"     "" "yes"
        prompt AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY" "" "yes"
        prompt AWS_SESSION_TOKEN     "AWS_SESSION_TOKEN (optional)" "" "yes"
        AWS_KEYS_SECRETS="AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}${AWS_SESSION_TOKEN:+
AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}}"
      fi
      MODEL_PLUGIN="plugins.models.bedrock_enhanced:BedrockPlugin"
      LLM_ENV_BLOCK="MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=${MODEL_PLUGIN}
AWS_REGION=${AWS_REGION}
MODEL_NAME=${PRIMARY_MODEL}"
      LLM_SECRETS_BLOCK="${AWS_KEYS_SECRETS}"
      ;;
    vertex_ai)
      prompt PROJECT_ID                   "GCP project ID"                      "your-gcp-project"
      prompt LOCATION_ID                  "GCP location"                        "us-central1"
      prompt GOOGLE_APPLICATION_CREDENTIALS "Service account JSON path in container" "/app/credentials/sa.json"
      prompt PRIMARY_MODEL                "Vertex AI model"                     "gemini-2.0-flash"
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
}

# ── write cloud env checklist (same as existing cloud mode output) ────────────
write_cloud_env_checklist() {
  local out_file="$OUT_DIR/cloud-env-checklist.txt"
  mkdir -p "$OUT_DIR"
  cat > "$out_file" <<CHECKLIST
# ==============================================================================
# Spotfire Copilot — AWS ECS / Fargate Cloud Env Checklist
# Generated: $(date)
# Image tag: ${IMAGE_TAG}
# ==============================================================================
# Store SECRET values in AWS Secrets Manager.
# Use CONFIG values as plain ECS task definition environment variables.
# ==============================================================================

# ── 01 CORE ──────────────────────────────────────────────────────────────────
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
# SECRET — store full URL in Secrets Manager; reference via valueFrom in task def
DATABASE_URL=postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?ssl=${DB_SSLMODE}}
SYNC_DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?sslmode=${DB_SSLMODE}}

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
# CONFIG
ENABLE_ADMIN_CONSOLE=true
# SECRET — same DATABASE_URL / SECRET_KEY as orchestrator
ADMIN_SECRET_KEY=${C_SECRET_KEY}
ADMIN
fi)

$(if [[ "$ENABLE_AGENT_REGISTRY" == "yes" ]]; then
cat <<AR
# ── 05 AGENT REGISTRY ────────────────────────────────────────────────────────
# CONFIG
PORT=${AGENT_PORT:-8050}
BASE_URL=${AGENT_BASE_URL:-http://agent-registry:8050}
LOG_LEVEL=INFO
# SECRET
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

# ── generate ECS task definition JSON ────────────────────────────────────────
build_env_array() {
  # Outputs a JSON array of {"name":"K","value":"V"} entries from KEY=VALUE lines
  local block="$1"
  local result="["
  local first=1
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}" val="${line#*=}"
    [[ -z "$key" ]] && continue
    [[ $first -eq 0 ]] && result+=","
    result+="{\"name\":\"${key}\",\"value\":\"${val}\"}"
    first=0
  done <<< "$block"
  result+="]"
  echo "$result"
}

build_secrets_array() {
  # Outputs a JSON array of {"name":"K","valueFrom":"<arn>"} entries.
  # Each SECRET_NAME maps to <secret_prefix>/<secret_name> in Secrets Manager.
  local block="$1" secret_prefix="$2"
  local result="["
  local first=1
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}"
    [[ -z "$key" ]] && continue
    local arn="arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:${secret_prefix}/${key}"
    [[ $first -eq 0 ]] && result+=","
    result+="{\"name\":\"${key}\",\"valueFrom\":\"${arn}\"}"
    first=0
  done <<< "$block"
  result+="]"
  echo "$result"
}

write_task_definition() {
  local name="$1" image="$2" port="$3" env_json="$4" secrets_json="$5" out_file="$6"
  cat > "$out_file" <<JSON
{
  "family": "${ECS_SERVICE_PREFIX}-${name}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${TASK_CPU}",
  "memory": "${TASK_MEMORY}",
  "executionRoleArn": "${ECS_EXECUTION_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "${name}",
      "image": "${image}",
      "essential": true,
      "portMappings": [
        {"containerPort": ${port}, "protocol": "tcp"}
      ],
      "repositoryCredentials": {
        "credentialsParameter": "${ACR_SECRET_ARN}"
      },
      "environment": ${env_json},
      "secrets": ${secrets_json},
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${ECS_SERVICE_PREFIX}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "${name}"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -fsS http://localhost:${port}/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
JSON
  ok "Task definition written: $out_file"
}

# ── generate the self-contained CloudShell deploy script ─────────────────────
write_cloudshell_script() {
  local deploy_dir="$1"
  local script_file="$deploy_dir/awscli-deploy.sh"

  # Build the Secrets Manager put-secret-value calls for each secret
  local secrets_cmds=""

  # Core secrets
  secrets_cmds+="
echo '==> Storing core secrets in Secrets Manager...'
aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/SECRET_KEY\" \\
  --description 'Spotfire Copilot SECRET_KEY' \\
  --secret-string \"${C_SECRET_KEY}\" || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/SECRET_KEY\" \\
  --secret-string \"${C_SECRET_KEY}\"

aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/HASHED_ADMIN_PASSWORD\" \\
  --description 'Spotfire Copilot HASHED_ADMIN_PASSWORD' \\
  --secret-string \"${C_HASHED_ADMIN}\" || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/HASHED_ADMIN_PASSWORD\" \\
  --secret-string \"${C_HASHED_ADMIN}\"

aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/OAUTH2_CLIENT_ID\" \\
  --description 'Spotfire Copilot OAUTH2_CLIENT_ID' \\
  --secret-string \"${C_OAUTH_ID}\" || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/OAUTH2_CLIENT_ID\" \\
  --secret-string \"${C_OAUTH_ID}\"

aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/OAUTH2_CLIENT_SECRET_HASH\" \\
  --description 'Spotfire Copilot OAUTH2_CLIENT_SECRET_HASH' \\
  --secret-string \"${C_OAUTH_HASH}\" || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/OAUTH2_CLIENT_SECRET_HASH\" \\
  --secret-string \"${C_OAUTH_HASH}\"

echo '==> Storing DATABASE_URL secret...'
aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/DATABASE_URL\" \\
  --description 'Spotfire Copilot DATABASE_URL' \\
  --secret-string \"postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?ssl=${DB_SSLMODE}}\" || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/DATABASE_URL\" \\
  --secret-string \"postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?ssl=${DB_SSLMODE}}\"

aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/SYNC_DATABASE_URL\" \\
  --description 'Spotfire Copilot SYNC_DATABASE_URL' \\
  --secret-string \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?sslmode=${DB_SSLMODE}}\" || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/SYNC_DATABASE_URL\" \\
  --secret-string \"postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?sslmode=${DB_SSLMODE}}\"
"

  # LLM secrets (non-empty lines only)
  if [[ -n "${LLM_SECRETS_BLOCK}" ]]; then
    secrets_cmds+="
echo '==> Storing LLM provider secrets...'
"
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      local key="${line%%=*}" val="${line#*=}"
      [[ -z "$key" || -z "$val" ]] && continue
      secrets_cmds+="aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/${key}\" --secret-string \"${val}\" || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/${key}\" --secret-string \"${val}\"
"
    done <<< "${LLM_SECRETS_BLOCK}"
  fi

  # ACR credentials secret
  secrets_cmds+="
echo '==> Storing ACR pull credentials...'
aws secretsmanager create-secret --region \"${AWS_REGION}\" \\
  --name \"${SECRETS_PREFIX}/acr-pull\" \\
  --description 'ACR pull credentials for Spotfire Copilot images' \\
  --secret-string '{\"username\":\"${ACR_USERNAME}\",\"password\":\"${ACR_PASSWORD}\"}' || \\
  aws secretsmanager update-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/acr-pull\" \\
  --secret-string '{\"username\":\"${ACR_USERNAME}\",\"password\":\"${ACR_PASSWORD}\"}'
ACR_SECRET_ARN=\$(aws secretsmanager describe-secret --region \"${AWS_REGION}\" \\
  --secret-id \"${SECRETS_PREFIX}/acr-pull\" --query ARN --output text)
echo \"ACR secret ARN: \${ACR_SECRET_ARN}\"
"

  cat > "$script_file" <<DEPLOY
#!/usr/bin/env bash
# ==============================================================================
#  Spotfire Copilot — AWS ECS / Fargate CloudShell Deploy Script
#  Generated: $(date)
#  Run this script in AWS CloudShell or any machine with AWS CLI configured.
#  Usage: bash awscli-deploy.sh
# ==============================================================================
set -Eeuo pipefail

AWS_REGION="${AWS_REGION}"
ECS_CLUSTER="${ECS_CLUSTER}"
ECS_SERVICE_PREFIX="${ECS_SERVICE_PREFIX}"
SUBNETS="${SUBNETS}"
SECURITY_GROUP="${SECURITY_GROUP}"
SECRETS_PREFIX="${SECRETS_PREFIX}"
IMAGE_TAG="${IMAGE_TAG}"
TASK_CPU="${TASK_CPU}"
TASK_MEMORY="${TASK_MEMORY}"
DESIRED_COUNT="${DESIRED_COUNT}"

echo "================================================================"
echo " Spotfire Copilot - AWS ECS Deployment"
echo " Region:  \${AWS_REGION}"
echo " Cluster: \${ECS_CLUSTER}"
echo "================================================================"

# ── Step 1: Resolve AWS account ID ──────────────────────────────────
AWS_ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: \${AWS_ACCOUNT_ID}"

# ── Step 2: Create IAM Execution Role (idempotent) ──────────────────
EXEC_ROLE_NAME="${ECS_SERVICE_PREFIX}-ecs-exec-role"
echo "==> Creating/verifying ECS execution role: \${EXEC_ROLE_NAME}"
aws iam create-role --region "\${AWS_REGION}" \\
  --role-name "\${EXEC_ROLE_NAME}" \\
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }' 2>/dev/null || echo "  (role already exists)"
aws iam attach-role-policy \\
  --role-name "\${EXEC_ROLE_NAME}" \\
  --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" 2>/dev/null || true

# Allow reading secrets from Secrets Manager
aws iam put-role-policy \\
  --role-name "\${EXEC_ROLE_NAME}" \\
  --policy-name "SecretsManagerRead" \\
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{
      \"Effect\":\"Allow\",
      \"Action\":[\"secretsmanager:GetSecretValue\"],
      \"Resource\":\"arn:aws:iam::\${AWS_ACCOUNT_ID}:secret:\${SECRETS_PREFIX}/*\"
    }]
  }"
EXEC_ROLE_ARN=\$(aws iam get-role --role-name "\${EXEC_ROLE_NAME}" --query Role.Arn --output text)
echo "Execution role ARN: \${EXEC_ROLE_ARN}"

# ── Step 3: Create CloudWatch log group ─────────────────────────────
echo "==> Creating CloudWatch log group: /ecs/\${ECS_SERVICE_PREFIX}"
aws logs create-log-group --region "\${AWS_REGION}" \\
  --log-group-name "/ecs/\${ECS_SERVICE_PREFIX}" 2>/dev/null || echo "  (log group already exists)"

# ── Step 4: Store secrets in Secrets Manager ─────────────────────────
${secrets_cmds}

# ── Step 5: Register task definitions ────────────────────────────────
echo "==> Registering orchestrator task definition..."
ORCH_TASK_DEF=\$(cat <<'TASKDEF'
$(cat "${OUT_DIR}/aws-ecs/task-def-orchestrator.json" 2>/dev/null || echo '{}')
TASKDEF
)
# Patch in the resolved execution role ARN and ACR secret ARN
ORCH_TASK_DEF=\$(echo "\${ORCH_TASK_DEF}" | sed \\
  "s|PLACEHOLDER_EXEC_ROLE_ARN|\${EXEC_ROLE_ARN}|g; \\
   s|PLACEHOLDER_ACR_SECRET_ARN|\${ACR_SECRET_ARN}|g; \\
   s|PLACEHOLDER_ACCOUNT_ID|\${AWS_ACCOUNT_ID}|g")
ORCH_TASK_REVISION=\$(aws ecs register-task-definition --region "\${AWS_REGION}" \\
  --cli-input-json "\${ORCH_TASK_DEF}" --query taskDefinition.taskDefinitionArn --output text)
echo "Orchestrator task definition: \${ORCH_TASK_REVISION}"

$(if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
cat <<'ADMINTD'
echo "==> Registering admin console task definition..."
ADMIN_TASK_DEF=$(cat <<'TASKDEF'
PLACEHOLDER_ADMIN_TASK_DEF
TASKDEF
)
ADMIN_TASK_DEF=$(echo "${ADMIN_TASK_DEF}" | sed \
  "s|PLACEHOLDER_EXEC_ROLE_ARN|${EXEC_ROLE_ARN}|g; \
   s|PLACEHOLDER_ACR_SECRET_ARN|${ACR_SECRET_ARN}|g; \
   s|PLACEHOLDER_ACCOUNT_ID|${AWS_ACCOUNT_ID}|g")
ADMIN_TASK_REVISION=$(aws ecs register-task-definition --region "${AWS_REGION}" \
  --cli-input-json "${ADMIN_TASK_DEF}" --query taskDefinition.taskDefinitionArn --output text)
echo "Admin Console task definition: ${ADMIN_TASK_REVISION}"
ADMINTD
fi)

# ── Step 6: Create or update ECS services ────────────────────────────
NETWORK_CONFIG="awsvpcConfiguration={subnets=[\${SUBNETS}],securityGroups=[\${SECURITY_GROUP}],assignPublicIp=DISABLED}"

echo "==> Creating/updating orchestrator ECS service..."
aws ecs create-service --region "\${AWS_REGION}" \\
  --cluster "\${ECS_CLUSTER}" \\
  --service-name "\${ECS_SERVICE_PREFIX}-orchestrator" \\
  --task-definition "\${ORCH_TASK_REVISION}" \\
  --launch-type FARGATE \\
  --desired-count "\${DESIRED_COUNT}" \\
  --network-configuration "\${NETWORK_CONFIG}" 2>/dev/null || \\
aws ecs update-service --region "\${AWS_REGION}" \\
  --cluster "\${ECS_CLUSTER}" \\
  --service "\${ECS_SERVICE_PREFIX}-orchestrator" \\
  --task-definition "\${ORCH_TASK_REVISION}" \\
  --desired-count "\${DESIRED_COUNT}"

$(if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
cat <<'ADMINSVC'
echo "==> Creating/updating admin console ECS service..."
aws ecs create-service --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --service-name "${ECS_SERVICE_PREFIX}-admin-console" \
  --task-definition "${ADMIN_TASK_REVISION}" \
  --launch-type FARGATE \
  --desired-count "${DESIRED_COUNT}" \
  --network-configuration "${NETWORK_CONFIG}" 2>/dev/null || \
aws ecs update-service --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE_PREFIX}-admin-console" \
  --task-definition "${ADMIN_TASK_REVISION}" \
  --desired-count "${DESIRED_COUNT}"
ADMINSVC
fi)

# ── Step 7: Wait for services to stabilise ───────────────────────────
echo "==> Waiting for orchestrator service to become stable (up to 5 min)..."
aws ecs wait services-stable --region "\${AWS_REGION}" \\
  --cluster "\${ECS_CLUSTER}" \\
  --services "\${ECS_SERVICE_PREFIX}-orchestrator"
echo ""
echo "================================================================"
echo " Deployment complete."
echo " Cluster:    \${ECS_CLUSTER}"
echo " Orchestrator service: \${ECS_SERVICE_PREFIX}-orchestrator"
echo " Note: Wire up your ALB target group to this service manually"
echo "       (this script creates the service only — shallow mode)."
echo "================================================================"
DEPLOY

  chmod 700 "$script_file"
  ok "CloudShell deploy script written: $script_file"
}

# ── execute deployment using local AWS CLI ────────────────────────────────────
run_aws_cli_deploy() {
  local deploy_dir="$1"

  section "Live AWS CLI Deployment"
  info "Deploying using the AWS CLI on this machine..."

  # Resolve account ID
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  ok "AWS Account ID: ${AWS_ACCOUNT_ID}"

  # IAM execution role
  local role_name="${ECS_SERVICE_PREFIX}-ecs-exec-role"
  info "Creating/verifying ECS execution role: ${role_name}"
  aws iam create-role --region "${AWS_REGION}" \
    --role-name "${role_name}" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    2>/dev/null || info "  (role already exists)"
  aws iam attach-role-policy \
    --role-name "${role_name}" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" 2>/dev/null || true
  aws iam put-role-policy \
    --role-name "${role_name}" \
    --policy-name "SecretsManagerRead" \
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetSecretValue\"],\"Resource\":\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:${SECRETS_PREFIX}/*\"}]}"
  ECS_EXECUTION_ROLE_ARN="$(aws iam get-role --role-name "${role_name}" --query Role.Arn --output text)"
  ok "Execution role ARN: ${ECS_EXECUTION_ROLE_ARN}"

  # CloudWatch log group
  info "Creating CloudWatch log group: /ecs/${ECS_SERVICE_PREFIX}"
  aws logs create-log-group --region "${AWS_REGION}" \
    --log-group-name "/ecs/${ECS_SERVICE_PREFIX}" 2>/dev/null || true

  # Store secrets
  info "Storing secrets in AWS Secrets Manager (prefix: ${SECRETS_PREFIX})"
  _store_secret "SECRET_KEY"              "${C_SECRET_KEY}"
  _store_secret "HASHED_ADMIN_PASSWORD"   "${C_HASHED_ADMIN}"
  _store_secret "OAUTH2_CLIENT_ID"        "${C_OAUTH_ID}"
  _store_secret "OAUTH2_CLIENT_SECRET_HASH" "${C_OAUTH_HASH}"
  _store_secret "DATABASE_URL" \
    "postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?ssl=${DB_SSLMODE}}"
  _store_secret "SYNC_DATABASE_URL" \
    "postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSLMODE:+?sslmode=${DB_SSLMODE}}"

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key="${line%%=*}" val="${line#*=}"
    [[ -n "$key" && -n "$val" ]] && _store_secret "${key}" "${val}"
  done <<< "${LLM_SECRETS_BLOCK}"

  # ACR credentials
  _store_secret_json "acr-pull" \
    "{\"username\":\"${ACR_USERNAME}\",\"password\":\"${ACR_PASSWORD}\"}"
  ACR_SECRET_ARN="$(aws secretsmanager describe-secret --region "${AWS_REGION}" \
    --secret-id "${SECRETS_PREFIX}/acr-pull" --query ARN --output text)"
  ok "ACR secret ARN: ${ACR_SECRET_ARN}"

  # Write and register task definitions with resolved ARNs
  _write_and_register_tasks "${deploy_dir}"

  # Create/update services
  local network_cfg="awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SECURITY_GROUP}],assignPublicIp=DISABLED}"
  info "Creating/updating orchestrator ECS service..."
  aws ecs create-service --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER}" \
    --service-name "${ECS_SERVICE_PREFIX}-orchestrator" \
    --task-definition "${ORCH_TASK_REVISION}" \
    --launch-type FARGATE --desired-count "${DESIRED_COUNT}" \
    --network-configuration "${network_cfg}" 2>/dev/null || \
  aws ecs update-service --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER}" \
    --service "${ECS_SERVICE_PREFIX}-orchestrator" \
    --task-definition "${ORCH_TASK_REVISION}" \
    --desired-count "${DESIRED_COUNT}"

  if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
    info "Creating/updating admin console ECS service..."
    aws ecs create-service --region "${AWS_REGION}" \
      --cluster "${ECS_CLUSTER}" \
      --service-name "${ECS_SERVICE_PREFIX}-admin-console" \
      --task-definition "${ADMIN_TASK_REVISION}" \
      --launch-type FARGATE --desired-count "${DESIRED_COUNT}" \
      --network-configuration "${network_cfg}" 2>/dev/null || \
    aws ecs update-service --region "${AWS_REGION}" \
      --cluster "${ECS_CLUSTER}" \
      --service "${ECS_SERVICE_PREFIX}-admin-console" \
      --task-definition "${ADMIN_TASK_REVISION}" \
      --desired-count "${DESIRED_COUNT}"
  fi

  info "Waiting for orchestrator service to stabilise (up to 5 min)..."
  aws ecs wait services-stable --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER}" \
    --services "${ECS_SERVICE_PREFIX}-orchestrator"

  echo ""
  echo "================================================================"
  echo " Deployment complete."
  echo " Cluster:   ${ECS_CLUSTER}"
  echo " Service:   ${ECS_SERVICE_PREFIX}-orchestrator"
  echo " Region:    ${AWS_REGION}"
  echo " Note: Wire up your ALB target group to this service to expose it."
  echo "================================================================"
}

_store_secret() {
  local name="$1" val="$2"
  aws secretsmanager create-secret --region "${AWS_REGION}" \
    --name "${SECRETS_PREFIX}/${name}" --secret-string "${val}" 2>/dev/null || \
  aws secretsmanager update-secret --region "${AWS_REGION}" \
    --secret-id "${SECRETS_PREFIX}/${name}" --secret-string "${val}"
  ok "  Secret: ${SECRETS_PREFIX}/${name}"
}

_store_secret_json() {
  local name="$1" json="$2"
  aws secretsmanager create-secret --region "${AWS_REGION}" \
    --name "${SECRETS_PREFIX}/${name}" --secret-string "${json}" 2>/dev/null || \
  aws secretsmanager update-secret --region "${AWS_REGION}" \
    --secret-id "${SECRETS_PREFIX}/${name}" --secret-string "${json}"
  ok "  Secret: ${SECRETS_PREFIX}/${name}"
}

_write_and_register_tasks() {
  local deploy_dir="$1"

  # Build environment and secrets JSON arrays for the orchestrator
  local orch_env_block="IMAGE_TAG=${IMAGE_TAG}
FASTAPI_APP_VERSION=${IMAGE_TAG}
LOG_LEVEL=INFO
DB_SSLMODE=${DB_SSLMODE}
${LLM_ENV_BLOCK}"

  local orch_env_json orch_secrets_json
  orch_env_json="$(build_env_array "${orch_env_block}")"
  local orch_sec_block="SECRET_KEY
HASHED_ADMIN_PASSWORD
OAUTH2_CLIENT_ID
OAUTH2_CLIENT_SECRET_HASH
DATABASE_URL
SYNC_DATABASE_URL"
  # Add LLM secret keys
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    orch_sec_block+="
${line%%=*}"
  done <<< "${LLM_SECRETS_BLOCK}"
  orch_secrets_json="$(build_secrets_array "${orch_sec_block}" "${SECRETS_PREFIX}")"

  write_task_definition \
    "orchestrator" \
    "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}" \
    "8080" \
    "${orch_env_json}" \
    "${orch_secrets_json}" \
    "${deploy_dir}/task-def-orchestrator.json"

  # Register orchestrator task
  ORCH_TASK_REVISION="$(aws ecs register-task-definition --region "${AWS_REGION}" \
    --cli-input-json "file://${deploy_dir}/task-def-orchestrator.json" \
    --query taskDefinition.taskDefinitionArn --output text)"
  ok "Orchestrator task definition: ${ORCH_TASK_REVISION}"

  if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
    local admin_env_block="IMAGE_TAG=${IMAGE_TAG}
FASTAPI_APP_VERSION=${IMAGE_TAG}
LOG_LEVEL=INFO"
    local admin_env_json admin_secrets_json
    admin_env_json="$(build_env_array "${admin_env_block}")"
    local admin_sec_block="SECRET_KEY
DATABASE_URL
SYNC_DATABASE_URL"
    admin_secrets_json="$(build_secrets_array "${admin_sec_block}" "${SECRETS_PREFIX}")"

    write_task_definition \
      "admin-console" \
      "copilotoci.azurecr.io/spotfirecopilot/admin-console:${IMAGE_TAG}" \
      "3000" \
      "${admin_env_json}" \
      "${admin_secrets_json}" \
      "${deploy_dir}/task-def-admin-console.json"

    ADMIN_TASK_REVISION="$(aws ecs register-task-definition --region "${AWS_REGION}" \
      --cli-input-json "file://${deploy_dir}/task-def-admin-console.json" \
      --query taskDefinition.taskDefinitionArn --output text)"
    ok "Admin console task definition: ${ADMIN_TASK_REVISION}"
  fi
}

# ════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════
echo "================================================================"
echo " Spotfire Copilot — AWS ECS / Fargate Deployment (Phase 3-4)"
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
  "cli_deploy|I have the AWS CLI installed and configured — deploy directly from this machine" \
  "no_cli|I don't have the AWS CLI installed yet" \
  "generate_only|I don't want to use the CLI — just generate the commands for me"

case "$CLI_CHOICE" in
  no_cli)
    echo ""
    info "Please install and configure the AWS CLI, then re-run this script."
    echo ""
    echo "  Install:    https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    echo "  Configure:  aws configure"
    echo "              (sets default region, access key ID, secret access key, output format)"
    echo ""
    info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
    echo "  ${OUT_DIR}/cloud-env-checklist.txt"
    echo "  ${OUT_DIR}/copilot-generated-values.txt"
    echo ""
    echo "Re-run with:  ./spotfire-copilot-deploy-ecs.sh --dir ${OUT_DIR}"
    exit 0
    ;;

  cli_deploy|generate_only)
    yes_no HAVE_DETAILS "Do you have your AWS infrastructure details ready? (region, cluster, subnets, security group, ACR credentials)" "yes"
    if [[ "$HAVE_DETAILS" == "no" ]]; then
      echo ""
      info "Please gather the following details, then re-run this script:"
      echo ""
      echo "  AWS ECS / Fargate details required:"
      echo "  ─────────────────────────────────────────────────────────"
      echo "  • AWS region             (e.g. us-east-1)"
      echo "  • ECS cluster name       (pre-existing Fargate cluster)"
      echo "  • Service name prefix    (e.g. spotfire-copilot)"
      echo "  • Subnet IDs             (comma-separated, e.g. subnet-abc,subnet-def)"
      echo "  • Security group ID      (e.g. sg-0abc123def456)"
      echo "  • Secrets Manager prefix (e.g. spotfire-copilot/${IMAGE_TAG})"
      echo "  • Fargate CPU units      (e.g. 1024 = 1 vCPU)"
      echo "  • Fargate memory MB      (e.g. 2048)"
      echo "  • Desired task count     (e.g. 1)"
      echo ""
      echo "  ACR pull credentials (from copilotoci.azurecr.io):"
      echo "  • ACR username"
      echo "  • ACR password"
      echo ""
      info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
      echo "  ${OUT_DIR}/cloud-env-checklist.txt"
      echo "  ${OUT_DIR}/copilot-generated-values.txt"
      echo ""
      echo "Re-run with:  ./spotfire-copilot-deploy-ecs.sh --dir ${OUT_DIR}"
      exit 0
    fi

    # ── Collect ECS infrastructure details ────────────────────────────
    section "AWS ECS infrastructure details"
    prompt AWS_REGION          "AWS region"                     "$(get_existing AWS_REGION "${EXISTING_FILES[@]}" || echo 'us-east-1')"
    prompt ECS_CLUSTER         "ECS cluster name"               "spotfire-copilot"
    prompt ECS_SERVICE_PREFIX  "Service name prefix"            "spotfire-copilot"
    prompt SUBNETS             "Subnet IDs (comma-separated)"   ""
    prompt SECURITY_GROUP      "Security group ID"              ""
    prompt SECRETS_PREFIX      "Secrets Manager path prefix"    "spotfire-copilot/${IMAGE_TAG}"
    prompt TASK_CPU            "Fargate task CPU units"         "1024"
    prompt TASK_MEMORY         "Fargate task memory (MB)"       "2048"
    prompt DESIRED_COUNT       "Desired task count per service" "1"

    section "ACR pull credentials"
    info "Images are pulled from copilotoci.azurecr.io."
    info "These will be stored in AWS Secrets Manager and referenced in the task definition."
    prompt ACR_USERNAME "ACR username" "spotfirecopilot"
    prompt ACR_PASSWORD "ACR password" "" "yes"

    DEPLOY_DIR="${OUT_DIR}/aws-ecs"
    mkdir -p "${DEPLOY_DIR}"

    if [[ "$CLI_CHOICE" == "cli_deploy" ]]; then
      section "Deploying via AWS CLI"
      ECS_EXECUTION_ROLE_ARN="PLACEHOLDER_EXEC_ROLE_ARN"
      ACR_SECRET_ARN="PLACEHOLDER_ACR_SECRET_ARN"
      run_aws_cli_deploy "${DEPLOY_DIR}"
    else
      section "Generating CloudShell deploy script"
      ECS_EXECUTION_ROLE_ARN="PLACEHOLDER_EXEC_ROLE_ARN"
      ACR_SECRET_ARN="PLACEHOLDER_ACR_SECRET_ARN"
      AWS_ACCOUNT_ID="PLACEHOLDER_ACCOUNT_ID"
      local_orch_env="IMAGE_TAG=${IMAGE_TAG}
FASTAPI_APP_VERSION=${IMAGE_TAG}
LOG_LEVEL=INFO
DB_SSLMODE=${DB_SSLMODE}
${LLM_ENV_BLOCK}"
      orch_env_j="$(build_env_array "${local_orch_env}")"
      orch_sec_b="SECRET_KEY
HASHED_ADMIN_PASSWORD
OAUTH2_CLIENT_ID
OAUTH2_CLIENT_SECRET_HASH
DATABASE_URL
SYNC_DATABASE_URL"
      while IFS= read -r l; do
        [[ -z "$l" || "$l" =~ ^# ]] && continue
        orch_sec_b+="
${l%%=*}"
      done <<< "${LLM_SECRETS_BLOCK}"
      orch_sec_j="$(build_secrets_array "${orch_sec_b}" "${SECRETS_PREFIX}")"
      write_task_definition "orchestrator" \
        "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}" \
        "8080" "${orch_env_j}" "${orch_sec_j}" "${DEPLOY_DIR}/task-def-orchestrator.json"
      if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
        admin_env_j="$(build_env_array "IMAGE_TAG=${IMAGE_TAG}
FASTAPI_APP_VERSION=${IMAGE_TAG}
LOG_LEVEL=INFO")"
        admin_sec_j="$(build_secrets_array "SECRET_KEY
DATABASE_URL
SYNC_DATABASE_URL" "${SECRETS_PREFIX}")"
        write_task_definition "admin-console" \
          "copilotoci.azurecr.io/spotfirecopilot/admin-console:${IMAGE_TAG}" \
          "3000" "${admin_env_j}" "${admin_sec_j}" "${DEPLOY_DIR}/task-def-admin-console.json"
      fi
      write_cloudshell_script "${DEPLOY_DIR}"
    fi
    ;;
esac

echo ""
echo "================================================================"
echo " Output files:"
echo "   ${OUT_DIR}/cloud-env-checklist.txt"
[[ -d "${DEPLOY_DIR:-}" ]] && echo "   ${DEPLOY_DIR}/task-def-orchestrator.json"
[[ "${ENABLE_ADMIN_CONSOLE:-}" == "yes" && -d "${DEPLOY_DIR:-}" ]] && echo "   ${DEPLOY_DIR}/task-def-admin-console.json"
[[ -d "${DEPLOY_DIR:-}" ]] && echo "   ${DEPLOY_DIR}/awscli-deploy.sh"
echo ""
if [[ "${CLI_CHOICE:-}" == "generate_only" ]]; then
  echo " To deploy from AWS CloudShell:"
  echo "   1. Upload awscli-deploy.sh + task-def-*.json to CloudShell"
  echo "   2. bash awscli-deploy.sh"
  echo ""
fi
echo " ⚠  Wire your ALB target group to the ECS service to expose it."
echo "================================================================"
