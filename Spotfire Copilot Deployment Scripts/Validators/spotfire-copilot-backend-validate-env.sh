#!/bin/bash

##############################################################################
#  Spotfire Copilot — Backend Environment Validation Script
#  Version: 2.3.x
#
#  Purpose: Validates environment variables for Orchestrator and Admin Console
#           deployed on AWS ECS/Fargate or Azure Container Apps
# 
#  Usage:
#    ./spotfire-copilot-backend-validate-env.sh
#
#  Supports:
#    - AWS ECS/Fargate (identify by ECS service name or task definition)
#    - Azure Container Apps (single or multiple apps)
#    - Template-based validation or interactive schema builder
#    - Saved answers with resume (validator-answers.env)
#    - No-CLI fallback (manual JSON import)
##############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

error() {
    echo -e "${RED}[✗]${NC} $*"
}

# Redact values for secret-like variable names when printing them into the report.
# Plain environment values are safe to show; anything whose NAME looks sensitive is masked.
redact_value() {
    local name="$1" value="$2"
    case "$name" in
        *KEY*|*SECRET*|*PASSWORD*|*PASSWD*|*TOKEN*|*HASH*|*CREDENTIAL*|*PRIVATE*|DATABASE_URL|SYNC_DATABASE_URL|*CONNECTION_STRING*|*DSN*)
            echo "********" ;;
        *)
            echo "$value" ;;
    esac
}

# Global variables
CLOUD_PLATFORM=""
AWS_REGION=""
AWS_CLUSTER=""
AWS_TASK_DEFINITIONS=()
AWS_TASK_ROLES=()
AWS_SERVICE_NAMES=()
AZURE_RESOURCE_GROUP=""
AZURE_LOCATION=""
AZURE_CONTAINER_APPS=()
AZURE_APP_ROLES=()
HAS_TEMPLATE=false
TEMPLATE_FILE=""
LLM_PROVIDER=""
HAS_ADMIN_CONSOLE=false
ORCHESTRATOR_VARS=()
ADMIN_CONSOLE_VARS=()
REPORT_FILE=""
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0
VALIDATION_DETAILS=()  # per-container results captured for the report

# Saved-answers file (resume support). Override with VALIDATOR_ANSWERS_FILE=... if desired.
ANSWERS_FILE="${VALIDATOR_ANSWERS_FILE:-validator-answers.env}"
RESUMED=false

##############################################################################
# Answer persistence — save/resume interactive answers
##############################################################################

save_answers() {
    cat > "$ANSWERS_FILE" <<EOF
# Spotfire Copilot validator - saved answers
# Generated: $(date)
# Delete this file to start fresh, or re-run and choose 'resume' to reuse it.
CLOUD_PLATFORM=$CLOUD_PLATFORM
AWS_REGION=$AWS_REGION
AWS_CLUSTER=$AWS_CLUSTER
AWS_TASK_DEFINITIONS=${AWS_TASK_DEFINITIONS[*]:-}
AWS_TASK_ROLES=${AWS_TASK_ROLES[*]:-}
AWS_SERVICE_NAMES=${AWS_SERVICE_NAMES[*]:-}
AZURE_RESOURCE_GROUP=$AZURE_RESOURCE_GROUP
AZURE_LOCATION=$AZURE_LOCATION
AZURE_CONTAINER_APPS=${AZURE_CONTAINER_APPS[*]:-}
AZURE_APP_ROLES=${AZURE_APP_ROLES[*]:-}
LLM_PROVIDER=$LLM_PROVIDER
HAS_ADMIN_CONSOLE=$HAS_ADMIN_CONSOLE
HAS_TEMPLATE=$HAS_TEMPLATE
TEMPLATE_FILE=$TEMPLATE_FILE
EOF
    chmod 600 "$ANSWERS_FILE" 2>/dev/null || true
    echo ""
    success "Answers saved to $ANSWERS_FILE"
    info "Next time, re-run the validator and choose 'resume' to skip re-entering these."
}

load_answers() {
    local key value
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        case "$key" in
            CLOUD_PLATFORM)        CLOUD_PLATFORM="$value" ;;
            AWS_REGION)            AWS_REGION="$value" ;;
            AWS_CLUSTER)           AWS_CLUSTER="$value" ;;
            AWS_TASK_DEFINITIONS)  read -ra AWS_TASK_DEFINITIONS <<< "$value" ;;
            AWS_TASK_ROLES)        read -ra AWS_TASK_ROLES <<< "$value" ;;
            AWS_SERVICE_NAMES)     read -ra AWS_SERVICE_NAMES <<< "$value" ;;
            AZURE_RESOURCE_GROUP)  AZURE_RESOURCE_GROUP="$value" ;;
            AZURE_LOCATION)        AZURE_LOCATION="$value" ;;
            AZURE_CONTAINER_APPS)  read -ra AZURE_CONTAINER_APPS <<< "$value" ;;
            AZURE_APP_ROLES)       read -ra AZURE_APP_ROLES <<< "$value" ;;
            LLM_PROVIDER)          LLM_PROVIDER="$value" ;;
            HAS_ADMIN_CONSOLE)     HAS_ADMIN_CONSOLE="$value" ;;
            HAS_TEMPLATE)          HAS_TEMPLATE="$value" ;;
            TEMPLATE_FILE)         TEMPLATE_FILE="$value" ;;
        esac
    done < "$ANSWERS_FILE"
}

# Resolve the task definition an ECS service is currently running.
# Prints the task definition ARN to stdout; diagnostics go to stderr.
resolve_task_def_from_service() {
    local svc="$1"
    local td
    td=$(aws ecs describe-services \
        --cluster "$AWS_CLUSTER" \
        --services "$svc" \
        --region "$AWS_REGION" \
        --query 'services[0].taskDefinition' \
        --output text 2>/dev/null)
    if [[ -z "$td" || "$td" == "None" ]]; then
        error "Could not resolve a task definition for ECS service '$svc'." >&2
        error "Check the service name, cluster ('$AWS_CLUSTER'), and region ('$AWS_REGION')." >&2
        exit 1
    fi
    info "Service '$svc' -> task definition '$td'" >&2
    echo "$td"
}

##############################################################################
# Phase 0: CLI Preflight — install, auth & connectivity check
##############################################################################

detect_os() {
    case "$(uname -s)" in
        Darwin)               echo "macos" ;;
        Linux)                echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)                    echo "unknown" ;;
    esac
}

preflight_check_prereqs() {
    # jq is required to parse the JSON returned by the cloud CLI
    if ! command -v jq &> /dev/null; then
        error "jq is not installed (required to parse task definition / container app JSON)."
        echo ""
        echo "Install it, then re-run this validator:"
        case "$(detect_os)" in
            macos) echo "  brew install jq" ;;
            linux) echo "  sudo apt-get install -y jq     # Debian/Ubuntu"
                   echo "  sudo dnf install -y jq         # Fedora/RHEL" ;;
            *)     echo "  https://jqlang.github.io/jq/download/" ;;
        esac
        echo ""
        exit 1
    fi
    success "jq found: $(jq --version 2>&1)"
}

preflight_check_cli() {
    echo ""
    info "Phase 0: CLI Preflight Check"
    echo ""

    preflight_check_prereqs

    if [[ "$CLOUD_PLATFORM" == "aws" ]]; then
        preflight_check_aws
    else
        preflight_check_azure
    fi
}

preflight_check_aws() {
    # 1) Is the AWS CLI installed?
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed."
        echo ""
        echo "Install it, then re-run this validator:"
        case "$(detect_os)" in
            macos) echo "  brew install awscli" ;;
            linux) echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install" ;;
            *)     echo "  Download and run: https://awscli.amazonaws.com/AWSCLIV2.msi" ;;
        esac
        echo "  Docs: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        echo ""
        echo "No local CLI? Use the AWS CloudShell export fallback (see Validators/README.md)."
        exit 1
    fi
    success "AWS CLI found: $(aws --version 2>&1 | head -n1)"

    # 2) Is it configured / authenticated?
    echo ""
    info "Verifying AWS credentials (aws sts get-caller-identity)..."
    local caller
    if ! caller=$(aws sts get-caller-identity --query 'Arn' --output text 2>&1); then
        error "AWS CLI is installed but not configured, or the credentials are invalid/expired."
        echo ""
        echo "Configure it, then re-run this validator:"
        echo "  aws configure                 # static access key + secret + default region"
        echo "  # or use SSO:"
        echo "  aws configure sso"
        echo "  # or export temporary credentials:"
        echo "  export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=... AWS_DEFAULT_REGION=..."
        echo ""
        echo "Detail: $caller"
        exit 1
    fi
    success "Authenticated as: $caller"

    # 3) Prove connectivity to ECS by listing clusters
    echo ""
    info "Checking ECS connectivity (aws ecs list-clusters)..."
    local clusters
    if ! clusters=$(aws ecs list-clusters --query 'clusterArns' --output text 2>&1); then
        error "Could not list ECS clusters. Check IAM permission 'ecs:ListClusters' and your region."
        echo "Detail: $clusters"
        exit 1
    fi
    if [[ -z "$clusters" ]]; then
        warn "No ECS clusters are visible with these credentials/region."
        warn "Confirm you are pointed at the correct AWS account and region before continuing."
    else
        success "ECS reachable. Clusters visible to this identity:"
        echo "$clusters" | tr '\t' '\n' | sed 's#.*/##; s/^/    • /'
    fi
    echo ""
    success "Preflight passed — the AWS CLI can talk to your resources."
}

preflight_check_azure() {
    # 1) Is the Azure CLI installed?
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed."
        echo ""
        echo "Install it, then re-run this validator:"
        case "$(detect_os)" in
            macos) echo "  brew install azure-cli" ;;
            linux) echo "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash" ;;
            *)     echo "  Download and run: https://aka.ms/installazurecliwindows" ;;
        esac
        echo "  Docs: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        echo ""
        echo "No local CLI? Use the Azure Cloud Shell export fallback (see Validators/README.md)."
        exit 1
    fi
    success "Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo 'installed')"

    # 2) Is it logged in?
    echo ""
    info "Verifying Azure login (az account show)..."
    local account
    if ! account=$(az account show --query 'name' --output tsv 2>&1); then
        error "Azure CLI is installed but you are not logged in (or the session expired)."
        echo ""
        echo "Log in, then re-run this validator:"
        echo "  az login                       # interactive browser login"
        echo "  # or device code (headless):"
        echo "  az login --use-device-code"
        echo "  # then select the right subscription:"
        echo "  az account set --subscription <SUBSCRIPTION_ID>"
        echo ""
        echo "Detail: $account"
        exit 1
    fi
    success "Logged in to subscription: $account"

    # 3) Prove connectivity by listing resource groups
    echo ""
    info "Checking connectivity (az group list)..."
    local groups
    if ! groups=$(az group list --query '[].name' --output tsv 2>&1); then
        error "Could not list resource groups. Check your permissions and selected subscription."
        echo "Detail: $groups"
        exit 1
    fi
    if [[ -z "$groups" ]]; then
        warn "No resource groups are visible with this account/subscription."
        warn "Confirm you selected the correct subscription before continuing."
    else
        success "Azure reachable. Resource groups visible to this account:"
        echo "$groups" | sed 's/^/    • /'
    fi
    echo ""
    success "Preflight passed — the Azure CLI can talk to your resources."
}

##############################################################################
# Phase 1: Platform & Topology Detection
##############################################################################

phase1_detect_platform() {
    echo ""
    info "Phase 1: Platform Detection"
    echo ""
    echo "Which cloud platform are you using?"
    echo "  1) AWS ECS/Fargate"
    echo "  2) Azure Container Apps"
    echo ""
    read -p "Enter choice (1 or 2): " platform_choice
    
    case "$platform_choice" in
        1)
            CLOUD_PLATFORM="aws"
            preflight_check_cli
            phase1_detect_aws_topology
            ;;
        2)
            CLOUD_PLATFORM="azure"
            preflight_check_cli
            phase1_detect_azure_topology
            ;;
        *)
            error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

phase1_detect_aws_topology() {
    echo ""
    read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
    read -p "Enter ECS cluster name: " AWS_CLUSTER

    echo ""
    echo "How do you want to identify what to validate?"
    echo "  1) ECS service names (recommended - resolves the task definition each service is actually running)"
    echo "  2) Task definition names"
    echo ""
    read -p "Enter choice (1 or 2): " id_choice

    echo ""
    echo "How are your services deployed?"
    echo "  1) All in one (both containers in a single service / task definition)"
    echo "  2) Separate (orchestrator + admin-console)"
    echo ""
    read -p "Enter choice (1 or 2): " topology_choice

    case "$id_choice" in
        1)
            # Identify by ECS service -> resolve the running task definition
            case "$topology_choice" in
                1)
                    read -p "Enter ECS service name: " svc
                    AWS_SERVICE_NAMES=("$svc")
                    AWS_TASK_DEFINITIONS=("$(resolve_task_def_from_service "$svc")")
                    AWS_TASK_ROLES=("both")
                    info "Service '$svc' (will validate both orchestrator and admin-console containers)"
                    ;;
                2)
                    read -p "Enter Orchestrator ECS service name: " svc_orch
                    read -p "Enter Admin Console ECS service name: " svc_admin
                    AWS_SERVICE_NAMES=("$svc_orch" "$svc_admin")
                    AWS_TASK_DEFINITIONS=("$(resolve_task_def_from_service "$svc_orch")" "$(resolve_task_def_from_service "$svc_admin")")
                    AWS_TASK_ROLES=("orchestrator" "admin")
                    info "Services: $svc_orch (orchestrator), $svc_admin (admin-console)"
                    ;;
                *)
                    error "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
            ;;
        2)
            # Identify by task definition name (direct)
            case "$topology_choice" in
                1)
                    read -p "Enter task definition name (e.g., spotfire-copilot-services): " task_def
                    AWS_TASK_DEFINITIONS=("$task_def")
                    AWS_TASK_ROLES=("both")
                    info "Task definition: $task_def (will validate both orchestrator and admin-console containers)"
                    ;;
                2)
                    read -p "Enter Orchestrator task definition name: " task_orch
                    read -p "Enter Admin Console task definition name: " task_admin
                    AWS_TASK_DEFINITIONS=("$task_orch" "$task_admin")
                    AWS_TASK_ROLES=("orchestrator" "admin")
                    info "Task definitions: $task_orch (orchestrator), $task_admin (admin-console)"
                    ;;
                *)
                    error "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
            ;;
        *)
            error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

phase1_detect_azure_topology() {
    echo ""
    read -p "Enter Azure resource group name: " AZURE_RESOURCE_GROUP
    read -p "Enter Azure location (e.g., eastus): " AZURE_LOCATION
    
    echo ""
    echo "How are your services deployed?"
    echo "  1) All in one Container App"
    echo "  2) Separate Container Apps (orchestrator + admin-console)"
    echo ""
    read -p "Enter choice (1 or 2): " topology_choice
    
    case "$topology_choice" in
        1)
            read -p "Enter Container App name (e.g., spotfire-copilot-services): " app_name
            AZURE_CONTAINER_APPS=("$app_name")
            AZURE_APP_ROLES=("both")
            info "Container App: $app_name (will validate both services)"
            ;;
        2)
            read -p "Enter Orchestrator Container App name: " app_orch
            read -p "Enter Admin Console Container App name: " app_admin
            AZURE_CONTAINER_APPS=("$app_orch" "$app_admin")
            AZURE_APP_ROLES=("orchestrator" "admin")
            info "Container Apps: $app_orch (orchestrator), $app_admin (admin-console)"
            ;;
        *)
            error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

##############################################################################
# Phase 2: Template or Schema Builder
##############################################################################

phase2_template_or_schema() {
    echo ""
    info "Phase 2: Configuration Schema"
    echo ""
    echo "The validator always reads the live environment variables from your ECS task"
    echo "definition / Container App. A deploy-script template is OPTIONAL and only used to"
    echo "auto-detect your LLM provider and whether the Admin Console is deployed."
    echo ""
    echo "Do you have a configuration template from our deploy script?"
    echo "  1) Yes - auto-detect from cloud-env-checklist.txt or spotfire-copilot-config.json"
    echo "  2) No  - pick the LLM provider interactively (default)"
    echo ""
    read -p "Enter choice (1 or 2) [2]: " template_choice
    template_choice="${template_choice:-2}"

    case "$template_choice" in
        1)
            phase2_load_template
            ;;
        2)
            phase2_build_schema_interactive
            ;;
        *)
            warn "Unrecognized choice '$template_choice'; building schema interactively."
            phase2_build_schema_interactive
            ;;
    esac
}

phase2_load_template() {
    echo ""
    read -p "Enter path to template file (leave blank to pick the provider manually): " template_path

    if [[ -z "$template_path" ]]; then
        info "No template provided - switching to interactive provider selection."
        phase2_build_schema_interactive
        return
    fi

    if [[ ! -f "$template_path" ]]; then
        warn "Template file not found: $template_path"
        info "Switching to interactive provider selection..."
        phase2_build_schema_interactive
        return
    fi
    
    HAS_TEMPLATE=true
    TEMPLATE_FILE="$template_path"
    success "Template loaded: $TEMPLATE_FILE"
    
    # Parse template to detect LLM provider and admin console.
    # Primary signal: the MODEL_PLUGIN_ENTRY_POINT plugin path (emitted for every provider).
    # Note: check azure_openai before openai (azure_openai_enhanced contains openai_enhanced).
    if grep -q "azure_openai_enhanced" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="azure_openai"
    elif grep -q "openai_enhanced" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="openai"
    elif grep -q "bedrock_enhanced" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="aws_bedrock"
    elif grep -q "vertexai_enhanced" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="vertex_ai"
    elif grep -q "gemini_enhanced" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="gemini"
    elif grep -q "nvidia_nim_enhanced" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="nvidia_nim"
    elif grep -q "ollama_enhanced" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="ollama"
    # Fallbacks for older/hand-written templates without the plugin path
    elif grep -q "AZURE_OPENAI_ENDPOINT" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="azure_openai"
    elif grep -q "GOOGLE_API_KEY" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="gemini"
    elif grep -q "NVIDIA_API_KEY" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="nvidia_nim"
    elif grep -q "OLLAMA_BASE_URL" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="ollama"
    elif grep -q "OPENAI_API_KEY" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="openai"
    fi
    
    if grep -q "ADMIN_CONSOLE" "$TEMPLATE_FILE" || grep -q "admin.console" "$TEMPLATE_FILE"; then
        HAS_ADMIN_CONSOLE=true
    fi
    
    info "Detected LLM provider: $LLM_PROVIDER"
    info "Admin Console deployed: $([ "$HAS_ADMIN_CONSOLE" = true ] && echo 'Yes' || echo 'No')"
}

phase2_build_schema_interactive() {
    echo ""
    echo "Let's build a validation schema based on your setup."
    echo ""
    echo "Which LLM provider are you using?"
    echo "  1) Azure OpenAI"
    echo "  2) OpenAI"
    echo "  3) AWS Bedrock"
    echo "  4) Vertex AI"
    echo "  5) Google Gemini"
    echo "  6) NVIDIA NIM"
    echo "  7) Ollama"
    echo ""
    read -p "Enter choice (1-7): " llm_choice
    
    case "$llm_choice" in
        1) LLM_PROVIDER="azure_openai" ;;
        2) LLM_PROVIDER="openai" ;;
        3) LLM_PROVIDER="aws_bedrock" ;;
        4) LLM_PROVIDER="vertex_ai" ;;
        5) LLM_PROVIDER="gemini" ;;
        6) LLM_PROVIDER="nvidia_nim" ;;
        7) LLM_PROVIDER="ollama" ;;
        *) error "Invalid choice."; exit 1 ;;
    esac
    
    success "LLM Provider selected: $LLM_PROVIDER"
    
    echo ""
    echo "Is Admin Console deployed?"
    echo "  1) Yes"
    echo "  2) No"
    echo ""
    read -p "Enter choice (1 or 2): " admin_choice
    
    case "$admin_choice" in
        1) HAS_ADMIN_CONSOLE=true ;;
        2) HAS_ADMIN_CONSOLE=false ;;
        *) error "Invalid choice."; exit 1 ;;
    esac
    
    success "Admin Console deployed: $([ "$HAS_ADMIN_CONSOLE" = true ] && echo 'Yes' || echo 'No')"
}

##############################################################################
# Build Validation Schemas
##############################################################################

build_validation_schemas() {
    # Core required vars for Orchestrator
    ORCHESTRATOR_VARS=(
        "IMAGE_TAG"
        "FASTAPI_APP_VERSION"
        "LOG_LEVEL"
        "SECRET_KEY"
        "HASHED_ADMIN_PASSWORD"
        "OAUTH2_CLIENT_ID"
        "OAUTH2_CLIENT_SECRET_HASH"
        "DATABASE_URL"
        "DB_SSLMODE"
        # Model plumbing — emitted for EVERY provider by the deploy script
        "MODEL_PLUGIN_ENTRY_POINT"
        "SECONDARY_MODEL_PLUGIN_ENTRY_POINT"
        "MODEL_NAME"
    )
    
    # Add LLM-specific vars (matches the deploy script's per-provider blocks)
    case "$LLM_PROVIDER" in
        azure_openai)
            ORCHESTRATOR_VARS+=(
                "OPENAI_API_TYPE"
                "OPENAI_API_KEY"
                "AZURE_OPENAI_ENDPOINT"
                "OPENAI_API_VERSION"
            )
            ;;
        openai)
            ORCHESTRATOR_VARS+=(
                "OPENAI_API_TYPE"
                "OPENAI_API_KEY"
            )
            ;;
        aws_bedrock)
            ORCHESTRATOR_VARS+=("AWS_REGION")
            ;;
        vertex_ai)
            ORCHESTRATOR_VARS+=(
                "PROJECT_ID"
                "LOCATION_ID"
                "GOOGLE_APPLICATION_CREDENTIALS"
            )
            ;;
        gemini)
            ORCHESTRATOR_VARS+=("GOOGLE_API_KEY")
            ;;
        nvidia_nim)
            ORCHESTRATOR_VARS+=(
                "NVIDIA_API_KEY"
                "NVIDIA_BASE_URL"
            )
            ;;
        ollama)
            ORCHESTRATOR_VARS+=("OLLAMA_BASE_URL")
            ;;
    esac
    
    # Admin Console schema (subset of Orchestrator)
    ADMIN_CONSOLE_VARS=(
        "IMAGE_TAG"
        "FASTAPI_APP_VERSION"
        "LOG_LEVEL"
        "SECRET_KEY"
        "HASHED_ADMIN_PASSWORD"
        "SYNC_DATABASE_URL"
        "DB_SSLMODE"
    )
}

##############################################################################
# Category-based model overrides
##############################################################################

# Provider -> environment prefix used for optional per-category model overrides.
provider_env_prefix() {
    case "$1" in
        azure_openai) echo "AZURE" ;;
        openai)       echo "OPENAI" ;;
        aws_bedrock)  echo "BEDROCK" ;;
        vertex_ai)    echo "VERTEXAI" ;;
        gemini)       echo "GEMINI" ;;
        nvidia_nim)   echo "NVIDIA" ;;
        ollama)       echo "OLLAMA" ;;
        *)            echo "" ;;
    esac
}

# Validate optional per-category model overrides (<PREFIX>_<CATEGORY>_MODEL / _TEMPERATURE).
# These are OPTIONAL, so all findings are WARNINGS:
#   - an incomplete pair (only _MODEL or only _TEMPERATURE) makes the category silently
#     fall back to MODEL_NAME
#   - a category override whose prefix does not match the active provider is orphaned
# $1 = newline-separated list of env var names present in the container.
check_category_overrides() {
    local names="$1"
    local active_prefix
    active_prefix="$(provider_env_prefix "$LLM_PROVIDER")"
    local all_prefixes=("AZURE" "OPENAI" "BEDROCK" "VERTEXAI" "GEMINI" "NVIDIA" "OLLAMA")
    local categories=("FAST" "LARGE" "VISION" "CODE" "REASONING")
    local prefix cat has_model has_temp

    for prefix in "${all_prefixes[@]}"; do
        for cat in "${categories[@]}"; do
            has_model=false; has_temp=false
            if echo "$names" | grep -q "^${prefix}_${cat}_MODEL$"; then has_model=true; fi
            if echo "$names" | grep -q "^${prefix}_${cat}_TEMPERATURE$"; then has_temp=true; fi

            if [[ "$prefix" == "$active_prefix" ]]; then
                if [[ "$has_model" == true && "$has_temp" == false ]]; then
                    warn "${prefix}_${cat}_MODEL is set without ${prefix}_${cat}_TEMPERATURE — category falls back to MODEL_NAME"
                    VALIDATION_DETAILS+=("    [WARN] ${prefix}_${cat}_MODEL set without ${prefix}_${cat}_TEMPERATURE (incomplete pair; category falls back to MODEL_NAME)")
                    ((VALIDATION_WARNINGS++)) || true
                elif [[ "$has_model" == false && "$has_temp" == true ]]; then
                    warn "${prefix}_${cat}_TEMPERATURE is set without ${prefix}_${cat}_MODEL — category falls back to MODEL_NAME"
                    VALIDATION_DETAILS+=("    [WARN] ${prefix}_${cat}_TEMPERATURE set without ${prefix}_${cat}_MODEL (incomplete pair; category falls back to MODEL_NAME)")
                    ((VALIDATION_WARNINGS++)) || true
                fi
            else
                if [[ "$has_model" == true || "$has_temp" == true ]]; then
                    warn "${prefix}_${cat}_* override present but active provider is $LLM_PROVIDER — orphaned"
                    VALIDATION_DETAILS+=("    [WARN] ${prefix}_${cat}_* override orphaned (active provider is $LLM_PROVIDER, expected prefix ${active_prefix:-<none>})")
                    ((VALIDATION_WARNINGS++)) || true
                fi
            fi
        done
    done
}

##############################################################################
# AWS ECS Validation
##############################################################################

validate_aws_ecs() {
    info "Validating AWS ECS environment..."
    echo ""
    # CLI install/auth/connectivity already verified in Phase 0 preflight.

    # Validate each task definition (schema bound to entry order via AWS_TASK_ROLES)
    for i in "${!AWS_TASK_DEFINITIONS[@]}"; do
        validate_aws_task_definition "${AWS_TASK_DEFINITIONS[$i]}" "${AWS_TASK_ROLES[$i]}"
    done
}

validate_aws_task_definition() {
    local task_def="$1"
    local role="$2"
    
    info "Fetching task definition: $task_def"
    
    local task_json
    task_json=$(aws ecs describe-task-definition \
        --task-definition "$task_def" \
        --region "$AWS_REGION" \
        --query 'taskDefinition.containerDefinitions' \
        --output json 2>&1) || {
        error "Failed to fetch task definition: $task_def"
        return 1
    }
    
    if [[ "$role" == "both" ]]; then
        # All-in-one task definition: identify each service container by name
        while read -r container_name; do
            if [[ "$container_name" == *"orchestrator"* ]]; then
                validate_container_env "$container_name" "$task_json" "orchestrator"
            elif [[ "$container_name" == *"admin"* ]]; then
                validate_container_env "$container_name" "$task_json" "admin"
            fi
        done < <(echo "$task_json" | jq -r '.[] | .name')
    else
        # Separate task definition: schema is bound to $role (entry order), not the container name
        local target
        target=$(echo "$task_json" | jq -r --arg r "$role" '.[] | select(.name | test($r; "i")) | .name' | head -n1)
        if [[ -z "$target" ]]; then
            local count
            count=$(echo "$task_json" | jq 'length')
            target=$(echo "$task_json" | jq -r '.[0].name')
            if [[ "$count" -gt 1 ]]; then
                warn "Task definition '$task_def' has $count containers; none match '$role'. Validating first container ('$target') against the $role schema."
            fi
        fi
        validate_container_env "$target" "$task_json" "$role"
    fi
}

validate_container_env() {
    local container_name="$1"
    local task_json="$2"
    local role="$3"
    
    echo ""
    info "Validating container: $container_name (schema: $role)"
    
    local env_vars
    env_vars=$(echo "$task_json" | jq -r ".[] | select(.name == \"$container_name\") | .environment // [] | map(.name) | .[]")
    
    local secret_refs
    secret_refs=$(echo "$task_json" | jq -r ".[] | select(.name == \"$container_name\") | .secrets // [] | map(.name) | .[]")
    
    # name<TAB>value rows for the plain (non-secret) environment variables
    local env_pairs
    env_pairs=$(echo "$task_json" | jq -r ".[] | select(.name == \"$container_name\") | .environment // [] | .[] | [.name, (.value // \"\")] | @tsv")
    
    # Capture the variables discovered in this container.
    # Plain environment values are shown; secret refs and sensitive-looking names are redacted.
    local _n _v
    VALIDATION_DETAILS+=("")
    VALIDATION_DETAILS+=("Container: $container_name (schema: $role)")
    if [[ -n "$env_pairs" ]]; then
        VALIDATION_DETAILS+=("  Environment variables found (name = value):")
        while IFS=$'\t' read -r _n _v; do
            [[ -z "$_n" ]] && continue
            VALIDATION_DETAILS+=("    - $_n = $(redact_value "$_n" "$_v")")
        done <<< "$env_pairs"
    else
        VALIDATION_DETAILS+=("  Environment variables found: (none)")
    fi
    if [[ -n "$secret_refs" ]]; then
        VALIDATION_DETAILS+=("  Secret references found (values not shown):")
        while IFS= read -r _n; do
            [[ -n "$_n" ]] && VALIDATION_DETAILS+=("    - $_n")
        done <<< "$secret_refs"
    fi
    
    # Determine which schema to use (bound to role, not container name)
    local vars_to_check=()
    if [[ "$role" == "admin" ]]; then
        vars_to_check=("${ADMIN_CONSOLE_VARS[@]}")
    else
        vars_to_check=("${ORCHESTRATOR_VARS[@]}")
    fi
    
    # Check required vars
    VALIDATION_DETAILS+=("  Required variables:")
    for var in "${vars_to_check[@]}"; do
        if echo "$env_vars" | grep -q "^${var}$"; then
            success "$var — present"
            VALIDATION_DETAILS+=("    [PASS] $var — present")
        elif echo "$secret_refs" | grep -q "^${var}$"; then
            success "$var — present (secret ref)"
            VALIDATION_DETAILS+=("    [PASS] $var — present (secret ref)")
        else
            error "$var — MISSING [REQUIRED]"
            VALIDATION_DETAILS+=("    [FAIL] $var — MISSING [REQUIRED]")
            ((VALIDATION_ERRORS++)) || true
        fi
    done
    
    # Check for orphaned vars
    echo ""
    info "Checking for orphaned variables..."
    
    # Define known LLM provider vars
    local all_llm_vars=(
        "AZURE_OPENAI_ENDPOINT" "OPENAI_API_KEY" "OPENAI_API_VERSION"
        "AWS_REGION" "AWS_BEDROCK" "MODEL_NAME"
        "GOOGLE_PROJECT_ID" "GOOGLE_REGION" "GOOGLE_API_KEY"
        "NVIDIA_API_KEY" "NVIDIA_BASE_URL"
        "OLLAMA_BASE_URL" "OLLAMA_MODEL"
        "VERTEX_AI"
    )
    
    for var in $env_vars $secret_refs; do
        # Check if it's a known LLM var but not for our provider
        for llm_var in "${all_llm_vars[@]}"; do
            if [[ "$var" == "$llm_var" ]]; then
                # Check if it's for a different provider
                if [[ "$LLM_PROVIDER" != "openai" && "$LLM_PROVIDER" != "azure_openai" ]] && [[ "$var" == "OPENAI_API_KEY" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not OpenAI)"
                    VALIDATION_DETAILS+=("    [WARN] $var — orphaned (using $LLM_PROVIDER, not OpenAI)")
                    ((VALIDATION_WARNINGS++)) || true
                elif [[ "$LLM_PROVIDER" != "azure_openai" ]] && [[ "$var" == "AZURE_OPENAI_ENDPOINT" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not Azure OpenAI)"
                    VALIDATION_DETAILS+=("    [WARN] $var — orphaned (using $LLM_PROVIDER, not Azure OpenAI)")
                    ((VALIDATION_WARNINGS++)) || true
                fi
            fi
        done
    done

    # Validate optional per-category model overrides (pair completeness + provider-prefix match)
    check_category_overrides "$env_vars"
}

##############################################################################
# Azure Container Apps Validation
##############################################################################

validate_azure_aca() {
    info "Validating Azure Container Apps environment..."
    echo ""
    # CLI install/auth/connectivity already verified in Phase 0 preflight.

    # Validate each container app (schema bound to entry order via AZURE_APP_ROLES)
    for i in "${!AZURE_CONTAINER_APPS[@]}"; do
        validate_azure_container_app "${AZURE_CONTAINER_APPS[$i]}" "${AZURE_APP_ROLES[$i]}"
    done
}

validate_azure_container_app() {
    local app_name="$1"
    local role="$2"
    
    info "Fetching Container App: $app_name"
    
    local app_json
    app_json=$(az containerapp show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$app_name" \
        --output json 2>&1) || {
        error "Failed to fetch Container App: $app_name"
        return 1
    }
    
    if [[ "$role" == "both" ]]; then
        # All-in-one Container App: identify each service container by name
        while read -r container_name; do
            if [[ "$container_name" == *"orchestrator"* ]]; then
                validate_aca_container_env "$app_name" "$container_name" "$app_json" "orchestrator"
            elif [[ "$container_name" == *"admin"* ]]; then
                validate_aca_container_env "$app_name" "$container_name" "$app_json" "admin"
            fi
        done < <(echo "$app_json" | jq -r '.properties.template.containers[].name')
    else
        # Separate Container App: schema is bound to $role (entry order), not the container name
        local target
        target=$(echo "$app_json" | jq -r --arg r "$role" '.properties.template.containers[] | select(.name | test($r; "i")) | .name' | head -n1)
        if [[ -z "$target" ]]; then
            local count
            count=$(echo "$app_json" | jq '.properties.template.containers | length')
            target=$(echo "$app_json" | jq -r '.properties.template.containers[0].name')
            if [[ "$count" -gt 1 ]]; then
                warn "Container App '$app_name' has $count containers; none match '$role'. Validating first container ('$target') against the $role schema."
            fi
        fi
        validate_aca_container_env "$app_name" "$target" "$app_json" "$role"
    fi
}

validate_aca_container_env() {
    local app_name="$1"
    local container_name="$2"
    local app_json="$3"
    local role="$4"
    
    echo ""
    info "Validating Container App: $app_name, Container: $container_name (schema: $role)"
    
    local env_vars
    env_vars=$(echo "$app_json" | jq -r ".properties.template.containers[] | select(.name == \"$container_name\") | .env[].name")
    
    # name<TAB>value<TAB>secretRef rows for each env entry
    local env_rows
    env_rows=$(echo "$app_json" | jq -r ".properties.template.containers[] | select(.name == \"$container_name\") | .env // [] | .[] | [.name, (.value // \"\"), (.secretRef // \"\")] | @tsv")
    
    # Capture the variables discovered in this container.
    # Plain values are shown; secret refs and sensitive-looking names are redacted.
    local _n _v _sref
    VALIDATION_DETAILS+=("")
    VALIDATION_DETAILS+=("Container: $app_name / $container_name (schema: $role)")
    if [[ -n "$env_rows" ]]; then
        VALIDATION_DETAILS+=("  Environment variables found (name = value):")
        while IFS=$'\t' read -r _n _v _sref; do
            [[ -z "$_n" ]] && continue
            if [[ -n "$_sref" ]]; then
                VALIDATION_DETAILS+=("    - $_n (secret ref: $_sref)")
            else
                VALIDATION_DETAILS+=("    - $_n = $(redact_value "$_n" "$_v")")
            fi
        done <<< "$env_rows"
    else
        VALIDATION_DETAILS+=("  Environment variables found: (none)")
    fi
    
    # Determine which schema to use (bound to role, not container name)
    local vars_to_check=()
    if [[ "$role" == "admin" ]]; then
        vars_to_check=("${ADMIN_CONSOLE_VARS[@]}")
    else
        vars_to_check=("${ORCHESTRATOR_VARS[@]}")
    fi
    
    # Check required vars
    VALIDATION_DETAILS+=("  Required variables:")
    for var in "${vars_to_check[@]}"; do
        if echo "$env_vars" | grep -q "^${var}$"; then
            success "$var — present"
            VALIDATION_DETAILS+=("    [PASS] $var — present")
        else
            error "$var — MISSING [REQUIRED]"
            VALIDATION_DETAILS+=("    [FAIL] $var — MISSING [REQUIRED]")
            ((VALIDATION_ERRORS++)) || true
        fi
    done
    
    # Check for orphaned vars
    echo ""
    info "Checking for orphaned variables..."
    
    local all_llm_vars=(
        "AZURE_OPENAI_ENDPOINT" "OPENAI_API_KEY" "OPENAI_API_VERSION"
        "AWS_REGION" "AWS_BEDROCK" "MODEL_NAME"
        "GOOGLE_PROJECT_ID" "GOOGLE_REGION" "GOOGLE_API_KEY"
        "NVIDIA_API_KEY" "NVIDIA_BASE_URL"
        "OLLAMA_BASE_URL" "OLLAMA_MODEL"
        "VERTEX_AI"
    )
    
    for var in $env_vars; do
        for llm_var in "${all_llm_vars[@]}"; do
            if [[ "$var" == "$llm_var" ]]; then
                if [[ "$LLM_PROVIDER" != "openai" && "$LLM_PROVIDER" != "azure_openai" ]] && [[ "$var" == "OPENAI_API_KEY" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not OpenAI)"
                    VALIDATION_DETAILS+=("    [WARN] $var — orphaned (using $LLM_PROVIDER, not OpenAI)")
                    ((VALIDATION_WARNINGS++)) || true
                elif [[ "$LLM_PROVIDER" != "azure_openai" ]] && [[ "$var" == "AZURE_OPENAI_ENDPOINT" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not Azure OpenAI)"
                    VALIDATION_DETAILS+=("    [WARN] $var — orphaned (using $LLM_PROVIDER, not Azure OpenAI)")
                    ((VALIDATION_WARNINGS++)) || true
                fi
            fi
        done
    done

    # Validate optional per-category model overrides (pair completeness + provider-prefix match)
    check_category_overrides "$env_vars"
}

##############################################################################
# Report Generation
##############################################################################

generate_report() {
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    
    local platform_label="$CLOUD_PLATFORM"
    if [[ "$CLOUD_PLATFORM" == "aws" ]]; then
        platform_label="ecs"
    elif [[ "$CLOUD_PLATFORM" == "azure" ]]; then
        platform_label="aca"
    fi
    
    REPORT_FILE="validation-report-${timestamp}-${platform_label}.txt"
    
    {
        echo "========================================================================"
        echo "Spotfire Copilot Environment Validation Report"
        echo "========================================================================"
        echo ""
        echo "Generated: $(date)"
        echo "Platform: $([ "$CLOUD_PLATFORM" = "aws" ] && echo "AWS ECS/Fargate" || echo "Azure Container Apps")"
        echo ""
        
        if [[ "$CLOUD_PLATFORM" == "aws" ]]; then
            echo "Region: $AWS_REGION"
            echo "Cluster: $AWS_CLUSTER"
            if [[ ${#AWS_SERVICE_NAMES[@]} -gt 0 ]]; then
                echo "Services: ${AWS_SERVICE_NAMES[*]}"
            fi
            echo "Task Definitions: ${AWS_TASK_DEFINITIONS[*]}"
        else
            echo "Resource Group: $AZURE_RESOURCE_GROUP"
            echo "Location: $AZURE_LOCATION"
            echo "Container Apps: ${AZURE_CONTAINER_APPS[*]}"
        fi
        
        echo ""
        echo "LLM Provider: $LLM_PROVIDER"
        echo "Admin Console Deployed: $([ "$HAS_ADMIN_CONSOLE" = true ] && echo "Yes" || echo "No")"
        echo ""
        echo "========================================================================"
        echo ""
        echo "Summary:"
        echo "  Errors:   $VALIDATION_ERRORS"
        echo "  Warnings: $VALIDATION_WARNINGS"
        echo ""
        
        if [[ $VALIDATION_ERRORS -eq 0 ]]; then
            echo "Status: ✓ VALIDATION PASSED"
        else
            echo "Status: ✗ VALIDATION FAILED"
        fi
        
        echo ""
        echo "========================================================================"
        echo ""
        echo "Validation Details (variables discovered per container):"
        echo "(Plain environment values are shown; secrets and sensitive-looking values are redacted as ********.)"
        if [[ ${#VALIDATION_DETAILS[@]} -gt 0 ]]; then
            printf '%s\n' "${VALIDATION_DETAILS[@]}"
        else
            echo "  (no per-container details were captured)"
        fi
        echo ""
        echo "========================================================================"
        
    } > "$REPORT_FILE"
    
    success "Report written to: $REPORT_FILE"
}

##############################################################################
# Main Flow
##############################################################################

main() {
    echo ""
    echo "================================================"
    echo "  Spotfire Copilot Environment Validator"
    echo "================================================"

    # Offer to resume from previously saved answers
    if [[ -f "$ANSWERS_FILE" ]]; then
        echo ""
        info "Found saved answers: $ANSWERS_FILE"
        grep -E '^(CLOUD_PLATFORM|AWS_REGION|AWS_CLUSTER|AWS_TASK_DEFINITIONS|AWS_SERVICE_NAMES|AZURE_RESOURCE_GROUP|AZURE_LOCATION|AZURE_CONTAINER_APPS|LLM_PROVIDER|HAS_ADMIN_CONSOLE)=' "$ANSWERS_FILE" 2>/dev/null | sed 's/^/    /' || true
        echo ""
        read -p "Resume with these saved answers? (y/n): " resume_choice
        if [[ "$resume_choice" =~ ^[Yy] ]]; then
            load_answers
            RESUMED=true
            success "Resumed from saved answers."
        fi
    fi

    if [[ "$RESUMED" == true ]]; then
        # Still verify the CLI is installed, authenticated, and can reach resources
        preflight_check_cli
    else
        phase1_detect_platform
        phase2_template_or_schema
        save_answers
    fi

    build_validation_schemas
    
    echo ""
    info "Phase 3: Validation Execution"
    echo ""
    
    if [[ "$CLOUD_PLATFORM" == "aws" ]]; then
        validate_aws_ecs
    else
        validate_azure_aca
    fi
    
    echo ""
    info "Phase 4: Report Generation"
    generate_report
    
    echo ""
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        success "Validation passed!"
        exit 0
    else
        error "Validation failed with $VALIDATION_ERRORS error(s)"
        exit 1
    fi
}

# Run main function
main "$@"
