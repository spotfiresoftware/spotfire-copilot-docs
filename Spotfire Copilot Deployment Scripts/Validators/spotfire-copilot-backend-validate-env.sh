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
#    - AWS ECS/Fargate (single or multiple task definitions)
#    - Azure Container Apps (single or multiple apps)
#    - Template-based validation or interactive schema builder
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

# Global variables
CLOUD_PLATFORM=""
AWS_REGION=""
AWS_CLUSTER=""
AWS_TASK_DEFINITIONS=()
AZURE_RESOURCE_GROUP=""
AZURE_LOCATION=""
AZURE_CONTAINER_APPS=()
HAS_TEMPLATE=false
TEMPLATE_FILE=""
LLM_PROVIDER=""
HAS_ADMIN_CONSOLE=false
ORCHESTRATOR_VARS=()
ADMIN_CONSOLE_VARS=()
REPORT_FILE=""
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

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
    echo "================================================"
    echo "  Spotfire Copilot Environment Validator"
    echo "================================================"
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
    echo "How are your services deployed?"
    echo "  1) All in one task definition"
    echo "  2) Separate task definitions (orchestrator + admin-console)"
    echo ""
    read -p "Enter choice (1 or 2): " topology_choice
    
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
    echo "Do you have a configuration template from our deploy script?"
    echo "  1) Yes, I have cloud-env-checklist.txt or spotfire-copilot-config.json"
    echo "  2) No, build schema interactively"
    echo ""
    read -p "Enter choice (1 or 2): " template_choice
    
    case "$template_choice" in
        1)
            phase2_load_template
            ;;
        2)
            phase2_build_schema_interactive
            ;;
        *)
            error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

phase2_load_template() {
    echo ""
    read -p "Enter path to template file: " template_path
    
    if [[ ! -f "$template_path" ]]; then
        error "Template file not found: $template_path"
        echo ""
        info "Falling back to interactive schema builder..."
        phase2_build_schema_interactive
        return
    fi
    
    HAS_TEMPLATE=true
    TEMPLATE_FILE="$template_path"
    success "Template loaded: $TEMPLATE_FILE"
    
    # Parse template to detect LLM provider and admin console
    if grep -q "AZURE_OPENAI_ENDPOINT" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="azure_openai"
    elif grep -q "OPENAI_API_KEY" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="openai"
    elif grep -q "AWS_BEDROCK" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="aws_bedrock"
    elif grep -q "VERTEX_AI" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="vertex_ai"
    elif grep -q "GOOGLE_API_KEY" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="gemini"
    elif grep -q "NVIDIA_API_KEY" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="nvidia_nim"
    elif grep -q "OLLAMA" "$TEMPLATE_FILE"; then
        LLM_PROVIDER="ollama"
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
    )
    
    # Add LLM-specific vars
    case "$LLM_PROVIDER" in
        azure_openai)
            ORCHESTRATOR_VARS+=(
                "AZURE_OPENAI_ENDPOINT"
                "OPENAI_API_KEY"
                "OPENAI_API_VERSION"
            )
            ;;
        openai)
            ORCHESTRATOR_VARS+=("OPENAI_API_KEY")
            ;;
        aws_bedrock)
            ORCHESTRATOR_VARS+=(
                "AWS_REGION"
                "MODEL_NAME"
            )
            ;;
        vertex_ai)
            ORCHESTRATOR_VARS+=(
                "GOOGLE_PROJECT_ID"
                "GOOGLE_REGION"
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
            ORCHESTRATOR_VARS+=(
                "OLLAMA_BASE_URL"
                "OLLAMA_MODEL"
            )
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
        --cluster "$AWS_CLUSTER" \
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
    
    # Determine which schema to use (bound to role, not container name)
    local vars_to_check=()
    if [[ "$role" == "admin" ]]; then
        vars_to_check=("${ADMIN_CONSOLE_VARS[@]}")
    else
        vars_to_check=("${ORCHESTRATOR_VARS[@]}")
    fi
    
    # Check required vars
    for var in "${vars_to_check[@]}"; do
        if echo "$env_vars" | grep -q "^${var}$"; then
            success "$var — present"
        elif echo "$secret_refs" | grep -q "^${var}$"; then
            success "$var — present (secret ref)"
        else
            error "$var — MISSING [REQUIRED]"
            ((VALIDATION_ERRORS++))
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
                if [[ "$LLM_PROVIDER" != "openai" ]] && [[ "$var" == "OPENAI_API_KEY" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not OpenAI)"
                    ((VALIDATION_WARNINGS++))
                elif [[ "$LLM_PROVIDER" != "azure_openai" ]] && [[ "$var" == "AZURE_OPENAI_ENDPOINT" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not Azure OpenAI)"
                    ((VALIDATION_WARNINGS++))
                fi
            fi
        done
    done
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
    
    # Determine which schema to use (bound to role, not container name)
    local vars_to_check=()
    if [[ "$role" == "admin" ]]; then
        vars_to_check=("${ADMIN_CONSOLE_VARS[@]}")
    else
        vars_to_check=("${ORCHESTRATOR_VARS[@]}")
    fi
    
    # Check required vars
    for var in "${vars_to_check[@]}"; do
        if echo "$env_vars" | grep -q "^${var}$"; then
            success "$var — present"
        else
            error "$var — MISSING [REQUIRED]"
            ((VALIDATION_ERRORS++))
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
                if [[ "$LLM_PROVIDER" != "openai" ]] && [[ "$var" == "OPENAI_API_KEY" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not OpenAI)"
                    ((VALIDATION_WARNINGS++))
                elif [[ "$LLM_PROVIDER" != "azure_openai" ]] && [[ "$var" == "AZURE_OPENAI_ENDPOINT" ]]; then
                    warn "$var — orphaned (you're using $LLM_PROVIDER, not Azure OpenAI)"
                    ((VALIDATION_WARNINGS++))
                fi
            fi
        done
    done
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
        
    } > "$REPORT_FILE"
    
    success "Report written to: $REPORT_FILE"
}

##############################################################################
# Main Flow
##############################################################################

main() {
    phase1_detect_platform
    phase2_template_or_schema
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
