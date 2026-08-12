#############################################################################
#  Spotfire Copilot - Backend Environment Validation Script
#  Version: 2.3.x
#
#  Purpose: Validates environment variables for Orchestrator and Admin Console
#           deployed on AWS ECS/Fargate or Azure Container Apps
# 
#  Usage:
#    .\spotfire-copilot-backend-validate-env.ps1
#
#  Supports:
#    - AWS ECS/Fargate (identify by ECS service name or task definition)
#    - Azure Container Apps (single or multiple apps)
#    - Template-based validation or interactive schema builder
#    - Saved answers with resume (validator-answers.env)
#    - No-CLI fallback (manual JSON import)
#############################################################################

param()

$ErrorActionPreference = "Stop"

# Global variables
$CloudPlatform = ""
$AWSRegion = ""
$AWSCluster = ""
$AWSTaskDefinitions = @()
$AWSTaskRoles = @()
$AWSServiceNames = @()
$AzureResourceGroup = ""
$AzureLocation = ""
$AzureContainerApps = @()
$AzureAppRoles = @()
$HasTemplate = $false
$TemplateFile = ""
$LLMProvider = ""
$HasAdminConsole = $false
$OrchestratorVars = @()
$AdminConsoleVars = @()
$ReportFile = ""
$ValidationErrors = 0
$ValidationWarnings = 0
$ValidationDetails = @()  # per-container results captured for the report

# Saved-answers file (resume support). Override with $env:VALIDATOR_ANSWERS_FILE.
$AnswersFile = if ($env:VALIDATOR_ANSWERS_FILE) { $env:VALIDATOR_ANSWERS_FILE } else { "validator-answers.env" }
$Resumed = $false

##############################################################################
# Utility Functions
##############################################################################

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
}

# Redact values for secret-like variable names when printing them into the report.
# Plain environment values are safe to show; anything whose NAME looks sensitive is masked.
function Get-RedactedValue {
    param([string]$Name, [string]$Value)
    if ($Name -match 'KEY|SECRET|PASSWORD|PASSWD|TOKEN|HASH|CREDENTIAL|PRIVATE|DATABASE_URL|SYNC_DATABASE_URL|CONNECTION_STRING|DSN') {
        return "********"
    }
    return $Value
}

function Read-Choice {
    param(
        [string]$Prompt,
        [int]$MaxChoice
    )
    
    do {
        $choice = Read-Host $Prompt
        if ($choice -ge 1 -and $choice -le $MaxChoice) {
            return $choice
        }
        Write-Host "Invalid choice. Please enter a number between 1 and $MaxChoice"
    } while ($true)
}

##############################################################################
# Answer persistence - save/resume interactive answers
##############################################################################

function Save-Answers {
    $lines = @(
        "# Spotfire Copilot validator - saved answers"
        "# Generated: $(Get-Date)"
        "# Delete this file to start fresh, or re-run and choose 'resume' to reuse it."
        "CLOUD_PLATFORM=$($script:CloudPlatform)"
        "AWS_REGION=$($script:AWSRegion)"
        "AWS_CLUSTER=$($script:AWSCluster)"
        "AWS_TASK_DEFINITIONS=$($script:AWSTaskDefinitions -join ' ')"
        "AWS_TASK_ROLES=$($script:AWSTaskRoles -join ' ')"
        "AWS_SERVICE_NAMES=$($script:AWSServiceNames -join ' ')"
        "AZURE_RESOURCE_GROUP=$($script:AzureResourceGroup)"
        "AZURE_LOCATION=$($script:AzureLocation)"
        "AZURE_CONTAINER_APPS=$($script:AzureContainerApps -join ' ')"
        "AZURE_APP_ROLES=$($script:AzureAppRoles -join ' ')"
        "LLM_PROVIDER=$($script:LLMProvider)"
        "HAS_ADMIN_CONSOLE=$(if ($script:HasAdminConsole) { 'true' } else { 'false' })"
        "HAS_TEMPLATE=$(if ($script:HasTemplate) { 'true' } else { 'false' })"
        "TEMPLATE_FILE=$($script:TemplateFile)"
    )
    $lines | Set-Content -Path $script:AnswersFile -Encoding UTF8
    Write-Host ""
    Write-Success "Answers saved to $($script:AnswersFile)"
    Write-Info "Next time, re-run the validator and choose 'resume' to skip re-entering these."
}

function Load-Answers {
    Get-Content -Path $script:AnswersFile | ForEach-Object {
        $line = $_
        if ($line -match '^\s*#' -or $line -notmatch '=') { return }
        $parts = $line -split '=', 2
        $key = $parts[0].Trim()
        $value = $parts[1]
        switch ($key) {
            'CLOUD_PLATFORM'       { $script:CloudPlatform = $value }
            'AWS_REGION'           { $script:AWSRegion = $value }
            'AWS_CLUSTER'          { $script:AWSCluster = $value }
            'AWS_TASK_DEFINITIONS' { $script:AWSTaskDefinitions = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'AWS_TASK_ROLES'       { $script:AWSTaskRoles = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'AWS_SERVICE_NAMES'    { $script:AWSServiceNames = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'AZURE_RESOURCE_GROUP' { $script:AzureResourceGroup = $value }
            'AZURE_LOCATION'       { $script:AzureLocation = $value }
            'AZURE_CONTAINER_APPS' { $script:AzureContainerApps = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'AZURE_APP_ROLES'      { $script:AzureAppRoles = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'LLM_PROVIDER'         { $script:LLMProvider = $value }
            'HAS_ADMIN_CONSOLE'    { $script:HasAdminConsole = ($value -match '^(?i)(true|1|yes)$') }
            'HAS_TEMPLATE'         { $script:HasTemplate = ($value -match '^(?i)(true|1|yes)$') }
            'TEMPLATE_FILE'        { $script:TemplateFile = $value }
        }
    }
}

# Resolve the task definition an ECS service is currently running.
function Resolve-TaskDefFromService {
    param([string]$ServiceName)
    $td = aws ecs describe-services `
        --cluster $script:AWSCluster `
        --services $ServiceName `
        --region $script:AWSRegion `
        --query 'services[0].taskDefinition' `
        --output text 2>$null
    if ($td) { $td = $td.ToString().Trim() }
    if ([string]::IsNullOrWhiteSpace($td) -or $td -eq 'None') {
        Write-Error "Could not resolve a task definition for ECS service '$ServiceName'."
        Write-Error "Check the service name, cluster ('$($script:AWSCluster)'), and region ('$($script:AWSRegion)')."
        exit 1
    }
    Write-Info "Service '$ServiceName' -> task definition '$td'"
    return $td
}

##############################################################################
# Phase 0: CLI Preflight - install, auth and connectivity check
##############################################################################

function Get-OSKind {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($IsMacOS) { return "macos" }
        if ($IsLinux) { return "linux" }
        return "windows"
    }
    return "windows"  # Windows PowerShell 5.1 is Windows-only
}

function Preflight-CheckPrereqs {
    # PowerShell parses JSON natively (ConvertFrom-Json), so no jq is required.
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Error "Windows PowerShell 5.1 or later is required."
        Write-Host ""
        Write-Host "Install it, then re-run this validator:"
        Write-Host "  https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        Write-Host ""
        exit 1
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion) found (JSON parsing built-in, no jq needed)."
}

function Preflight-CheckCli {
    Write-Host ""
    Write-Info "Phase 0: CLI Preflight Check"
    Write-Host ""

    Preflight-CheckPrereqs

    if ($script:CloudPlatform -eq "aws") {
        Preflight-CheckAws
    } else {
        Preflight-CheckAzure
    }
}

function Preflight-CheckAws {
    # 1) Is the AWS CLI installed?
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Error "AWS CLI is not installed."
        Write-Host ""
        Write-Host "Install it, then re-run this validator:"
        switch (Get-OSKind) {
            "macos" { Write-Host "  brew install awscli" }
            "linux" { Write-Host "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip; unzip awscliv2.zip; sudo ./aws/install" }
            default {
                Write-Host "  winget install -e --id Amazon.AWSCLI"
                Write-Host "  # or download and run the MSI: https://awscli.amazonaws.com/AWSCLIV2.msi"
            }
        }
        Write-Host "  Docs: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        Write-Host ""
        Write-Host "No local CLI? Use the AWS CloudShell export fallback (see Validators/README.md)."
        exit 1
    }
    $awsVersion = (aws --version 2>&1 | Select-Object -First 1)
    Write-Success "AWS CLI found: $awsVersion"

    # 2) Is it configured / authenticated?
    Write-Host ""
    Write-Info "Verifying AWS credentials (aws sts get-caller-identity)..."
    $caller = aws sts get-caller-identity --query 'Arn' --output text 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "AWS CLI is installed but not configured, or the credentials are invalid/expired."
        Write-Host ""
        Write-Host "Configure it, then re-run this validator:"
        Write-Host "  aws configure                 # static access key + secret + default region"
        Write-Host "  # or use SSO:"
        Write-Host "  aws configure sso"
        Write-Host "  # or set temporary credentials in this session:"
        Write-Host "  `$env:AWS_ACCESS_KEY_ID='...'; `$env:AWS_SECRET_ACCESS_KEY='...'; `$env:AWS_SESSION_TOKEN='...'; `$env:AWS_DEFAULT_REGION='...'"
        Write-Host ""
        Write-Host "Detail: $caller"
        exit 1
    }
    Write-Success "Authenticated as: $caller"

    # 3) Prove connectivity to ECS by listing clusters
    Write-Host ""
    Write-Info "Checking ECS connectivity (aws ecs list-clusters)..."
    $clusters = aws ecs list-clusters --query 'clusterArns' --output text 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not list ECS clusters. Check IAM permission 'ecs:ListClusters' and your region."
        Write-Host "Detail: $clusters"
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($clusters)) {
        Write-Warning "No ECS clusters are visible with these credentials/region."
        Write-Warning "Confirm you are pointed at the correct AWS account and region before continuing."
    } else {
        Write-Success "ECS reachable. Clusters visible to this identity:"
        foreach ($c in ($clusters -split "\s+")) {
            if ($c) { Write-Host ("    - " + ($c -replace '.*/', '')) }
        }
    }
    Write-Host ""
    Write-Success "Preflight passed - the AWS CLI can talk to your resources."
}

function Preflight-CheckAzure {
    # 1) Is the Azure CLI installed?
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI is not installed."
        Write-Host ""
        Write-Host "Install it, then re-run this validator:"
        switch (Get-OSKind) {
            "macos" { Write-Host "  brew install azure-cli" }
            "linux" { Write-Host "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash" }
            default {
                Write-Host "  winget install -e --id Microsoft.AzureCLI"
                Write-Host "  # or download and run the MSI: https://aka.ms/installazurecliwindows"
            }
        }
        Write-Host "  Docs: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        Write-Host ""
        Write-Host "No local CLI? Use the Azure Cloud Shell export fallback (see Validators/README.md)."
        exit 1
    }
    $azVersion = az version --query '\"azure-cli\"' -o tsv 2>$null
    if (-not $azVersion) { $azVersion = "installed" }
    Write-Success "Azure CLI found: $azVersion"

    # 2) Is it logged in?
    Write-Host ""
    Write-Info "Verifying Azure login (az account show)..."
    $account = az account show --query 'name' --output tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Azure CLI is installed but you are not logged in (or the session expired)."
        Write-Host ""
        Write-Host "Log in, then re-run this validator:"
        Write-Host "  az login                       # interactive browser login"
        Write-Host "  # or device code (headless):"
        Write-Host "  az login --use-device-code"
        Write-Host "  # then select the right subscription:"
        Write-Host "  az account set --subscription <SUBSCRIPTION_ID>"
        Write-Host ""
        Write-Host "Detail: $account"
        exit 1
    }
    Write-Success "Logged in to subscription: $account"

    # 3) Prove connectivity by listing resource groups
    Write-Host ""
    Write-Info "Checking connectivity (az group list)..."
    $groups = az group list --query '[].name' --output tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not list resource groups. Check your permissions and selected subscription."
        Write-Host "Detail: $groups"
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($groups)) {
        Write-Warning "No resource groups are visible with this account/subscription."
        Write-Warning "Confirm you selected the correct subscription before continuing."
    } else {
        Write-Success "Azure reachable. Resource groups visible to this account:"
        foreach ($g in ($groups -split "\r?\n")) {
            if ($g) { Write-Host ("    - " + $g) }
        }
    }
    Write-Host ""
    Write-Success "Preflight passed - the Azure CLI can talk to your resources."
}

##############################################################################
# Phase 1: Platform & Topology Detection
##############################################################################

function Phase1-DetectPlatform {
    Write-Host ""
    Write-Info "Phase 1: Platform Detection"
    Write-Host ""
    Write-Host "Which cloud platform are you using?"
    Write-Host "  1) AWS ECS/Fargate"
    Write-Host "  2) Azure Container Apps"
    Write-Host ""
    
    $platformChoice = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2
    
    switch ($platformChoice) {
        1 {
            $script:CloudPlatform = "aws"
            Preflight-CheckCli
            Phase1-DetectAWSTopology
        }
        2 {
            $script:CloudPlatform = "azure"
            Preflight-CheckCli
            Phase1-DetectAzureTopology
        }
    }
}

function Phase1-DetectAWSTopology {
    Write-Host ""
    $script:AWSRegion = Read-Host "Enter AWS region (e.g., us-east-1)"
    $script:AWSCluster = Read-Host "Enter ECS cluster name"

    Write-Host ""
    Write-Host "How do you want to identify what to validate?"
    Write-Host "  1) ECS service names (recommended - resolves the task definition each service is actually running)"
    Write-Host "  2) Task definition names"
    Write-Host ""
    $idChoice = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2

    Write-Host ""
    Write-Host "How are your services deployed?"
    Write-Host "  1) All in one (both containers in a single service / task definition)"
    Write-Host "  2) Separate (orchestrator + admin-console)"
    Write-Host ""
    $topologyChoice = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2

    if ($idChoice -eq 1) {
        # Identify by ECS service -> resolve the running task definition
        switch ($topologyChoice) {
            1 {
                $svc = Read-Host "Enter ECS service name"
                $script:AWSServiceNames = @($svc)
                $script:AWSTaskDefinitions = @((Resolve-TaskDefFromService -ServiceName $svc))
                $script:AWSTaskRoles = @("both")
                Write-Info "Service '$svc' (will validate both orchestrator and admin-console containers)"
            }
            2 {
                $svcOrch = Read-Host "Enter Orchestrator ECS service name"
                $svcAdmin = Read-Host "Enter Admin Console ECS service name"
                $script:AWSServiceNames = @($svcOrch, $svcAdmin)
                $script:AWSTaskDefinitions = @((Resolve-TaskDefFromService -ServiceName $svcOrch), (Resolve-TaskDefFromService -ServiceName $svcAdmin))
                $script:AWSTaskRoles = @("orchestrator", "admin")
                Write-Info "Services: $svcOrch (orchestrator), $svcAdmin (admin-console)"
            }
        }
    }
    else {
        # Identify by task definition name (direct)
        switch ($topologyChoice) {
            1 {
                $taskDef = Read-Host "Enter task definition name (e.g., spotfire-copilot-services)"
                $script:AWSTaskDefinitions = @($taskDef)
                $script:AWSTaskRoles = @("both")
                Write-Info "Task definition: $taskDef (will validate both orchestrator and admin-console containers)"
            }
            2 {
                $taskOrch = Read-Host "Enter Orchestrator task definition name"
                $taskAdmin = Read-Host "Enter Admin Console task definition name"
                $script:AWSTaskDefinitions = @($taskOrch, $taskAdmin)
                $script:AWSTaskRoles = @("orchestrator", "admin")
                Write-Info "Task definitions: $taskOrch (orchestrator), $taskAdmin (admin-console)"
            }
        }
    }
}

function Phase1-DetectAzureTopology {
    Write-Host ""
    $script:AzureResourceGroup = Read-Host "Enter Azure resource group name"
    $script:AzureLocation = Read-Host "Enter Azure location (e.g., eastus)"
    
    Write-Host ""
    Write-Host "How are your services deployed?"
    Write-Host "  1) All in one Container App"
    Write-Host "  2) Separate Container Apps (orchestrator + admin-console)"
    Write-Host ""
    
    $topologyChoice = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2
    
    switch ($topologyChoice) {
        1 {
            $appName = Read-Host "Enter Container App name (e.g., spotfire-copilot-services)"
            $script:AzureContainerApps = @($appName)
            $script:AzureAppRoles = @("both")
            Write-Info "Container App: $appName (will validate both services)"
        }
        2 {
            $appOrch = Read-Host "Enter Orchestrator Container App name"
            $appAdmin = Read-Host "Enter Admin Console Container App name"
            $script:AzureContainerApps = @($appOrch, $appAdmin)
            $script:AzureAppRoles = @("orchestrator", "admin")
            Write-Info "Container Apps: $appOrch (orchestrator), $appAdmin (admin-console)"
        }
    }
}

##############################################################################
# Phase 2: Template or Schema Builder
##############################################################################

function Phase2-TemplateOrSchema {
    Write-Host ""
    Write-Info "Phase 2: Configuration Schema"
    Write-Host ""
    Write-Host "The validator always reads the live environment variables from your ECS task"
    Write-Host "definition / Container App. A deploy-script template is OPTIONAL and only used to"
    Write-Host "auto-detect your LLM provider and whether the Admin Console is deployed."
    Write-Host ""
    Write-Host "Do you have a configuration template from our deploy script?"
    Write-Host "  1) Yes - auto-detect from cloud-env-checklist.txt or spotfire-copilot-config.json"
    Write-Host "  2) No  - pick the LLM provider interactively (default)"
    Write-Host ""
    
    $templateChoice = Read-Host "Enter choice (1 or 2) [2]"
    if ([string]::IsNullOrWhiteSpace($templateChoice)) { $templateChoice = "2" }
    
    switch ($templateChoice) {
        "1" {
            Phase2-LoadTemplate
        }
        "2" {
            Phase2-BuildSchemaInteractive
        }
        default {
            Write-Warning "Unrecognized choice '$templateChoice'; building schema interactively."
            Phase2-BuildSchemaInteractive
        }
    }
}

function Phase2-LoadTemplate {
    Write-Host ""
    $templatePath = Read-Host "Enter path to template file (leave blank to pick the provider manually)"
    
    if ([string]::IsNullOrWhiteSpace($templatePath)) {
        Write-Info "No template provided - switching to interactive provider selection."
        Phase2-BuildSchemaInteractive
        return
    }
    
    if (-not (Test-Path $templatePath)) {
        Write-Warning "Template file not found: $templatePath"
        Write-Info "Switching to interactive provider selection..."
        Phase2-BuildSchemaInteractive
        return
    }
    
    $script:HasTemplate = $true
    $script:TemplateFile = $templatePath
    Write-Success "Template loaded: $script:TemplateFile"
    
    # Parse template to detect LLM provider and admin console.
    # Primary signal: the MODEL_PLUGIN_ENTRY_POINT plugin path (emitted for every provider).
    # Note: check azure_openai before openai (azure_openai_enhanced contains openai_enhanced).
    $templateContent = Get-Content $templatePath -Raw
    
    if ($templateContent -match "azure_openai_enhanced") {
        $script:LLMProvider = "azure_openai"
    }
    elseif ($templateContent -match "openai_enhanced") {
        $script:LLMProvider = "openai"
    }
    elseif ($templateContent -match "bedrock_enhanced") {
        $script:LLMProvider = "aws_bedrock"
    }
    elseif ($templateContent -match "vertexai_enhanced") {
        $script:LLMProvider = "vertex_ai"
    }
    elseif ($templateContent -match "gemini_enhanced") {
        $script:LLMProvider = "gemini"
    }
    elseif ($templateContent -match "nvidia_nim_enhanced") {
        $script:LLMProvider = "nvidia_nim"
    }
    elseif ($templateContent -match "ollama_enhanced") {
        $script:LLMProvider = "ollama"
    }
    elseif ($templateContent -match "AZURE_OPENAI_ENDPOINT") {
        $script:LLMProvider = "azure_openai"
    }
    elseif ($templateContent -match "GOOGLE_API_KEY") {
        $script:LLMProvider = "gemini"
    }
    elseif ($templateContent -match "NVIDIA_API_KEY") {
        $script:LLMProvider = "nvidia_nim"
    }
    elseif ($templateContent -match "OLLAMA_BASE_URL") {
        $script:LLMProvider = "ollama"
    }
    elseif ($templateContent -match "OPENAI_API_KEY") {
        $script:LLMProvider = "openai"
    }
    
    if ($templateContent -match "ADMIN_CONSOLE|admin.console") {
        $script:HasAdminConsole = $true
    }
    
    Write-Info "Detected LLM provider: $script:LLMProvider"
    Write-Info "Admin Console deployed: $(if ($script:HasAdminConsole) { 'Yes' } else { 'No' })"
}

function Phase2-BuildSchemaInteractive {
    Write-Host ""
    Write-Host "Let's build a validation schema based on your setup."
    Write-Host ""
    Write-Host "Which LLM provider are you using?"
    Write-Host "  1) Azure OpenAI"
    Write-Host "  2) OpenAI"
    Write-Host "  3) AWS Bedrock"
    Write-Host "  4) Vertex AI"
    Write-Host "  5) Google Gemini"
    Write-Host "  6) NVIDIA NIM"
    Write-Host "  7) Ollama"
    Write-Host ""
    
    $llmChoice = Read-Choice -Prompt "Enter choice (1-7)" -MaxChoice 7
    
    switch ($llmChoice) {
        1 { $script:LLMProvider = "azure_openai" }
        2 { $script:LLMProvider = "openai" }
        3 { $script:LLMProvider = "aws_bedrock" }
        4 { $script:LLMProvider = "vertex_ai" }
        5 { $script:LLMProvider = "gemini" }
        6 { $script:LLMProvider = "nvidia_nim" }
        7 { $script:LLMProvider = "ollama" }
    }
    
    Write-Success "LLM Provider selected: $script:LLMProvider"
    
    Write-Host ""
    Write-Host "Is Admin Console deployed?"
    Write-Host "  1) Yes"
    Write-Host "  2) No"
    Write-Host ""
    
    $adminChoice = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2
    
    switch ($adminChoice) {
        1 { $script:HasAdminConsole = $true }
        2 { $script:HasAdminConsole = $false }
    }
    
    Write-Success "Admin Console deployed: $(if ($script:HasAdminConsole) { 'Yes' } else { 'No' })"
}

##############################################################################
# Build Validation Schemas
##############################################################################

function Build-ValidationSchemas {
    # Core required vars for Orchestrator
    $script:OrchestratorVars = @(
        "IMAGE_TAG",
        "FASTAPI_APP_VERSION",
        "LOG_LEVEL",
        "SECRET_KEY",
        "HASHED_ADMIN_PASSWORD",
        "OAUTH2_CLIENT_ID",
        "OAUTH2_CLIENT_SECRET_HASH",
        "DATABASE_URL",
        "DB_SSLMODE",
        # Model plumbing - emitted for EVERY provider by the deploy script
        "MODEL_PLUGIN_ENTRY_POINT",
        "SECONDARY_MODEL_PLUGIN_ENTRY_POINT",
        "MODEL_NAME"
    )
    
    # Add LLM-specific vars (matches the deploy script's per-provider blocks)
    switch ($script:LLMProvider) {
        "azure_openai" {
            $script:OrchestratorVars += @(
                "OPENAI_API_TYPE",
                "OPENAI_API_KEY",
                "AZURE_OPENAI_ENDPOINT",
                "OPENAI_API_VERSION"
            )
        }
        "openai" {
            $script:OrchestratorVars += @(
                "OPENAI_API_TYPE",
                "OPENAI_API_KEY"
            )
        }
        "aws_bedrock" {
            $script:OrchestratorVars += "AWS_REGION"
        }
        "vertex_ai" {
            $script:OrchestratorVars += @(
                "PROJECT_ID",
                "LOCATION_ID",
                "GOOGLE_APPLICATION_CREDENTIALS"
            )
        }
        "gemini" {
            $script:OrchestratorVars += "GOOGLE_API_KEY"
        }
        "nvidia_nim" {
            $script:OrchestratorVars += @(
                "NVIDIA_API_KEY",
                "NVIDIA_BASE_URL"
            )
        }
        "ollama" {
            $script:OrchestratorVars += "OLLAMA_BASE_URL"
        }
    }
    
    # Admin Console schema
    $script:AdminConsoleVars = @(
        "IMAGE_TAG",
        "FASTAPI_APP_VERSION",
        "LOG_LEVEL",
        "SECRET_KEY",
        "HASHED_ADMIN_PASSWORD",
        "SYNC_DATABASE_URL",
        "DB_SSLMODE"
    )
}

##############################################################################
# Category-based model overrides
##############################################################################

# Provider -> environment prefix used for optional per-category model overrides.
function Get-ProviderEnvPrefix {
    param([string]$Provider)
    switch ($Provider) {
        "azure_openai" { "AZURE" }
        "openai"       { "OPENAI" }
        "aws_bedrock"  { "BEDROCK" }
        "vertex_ai"    { "VERTEXAI" }
        "gemini"       { "GEMINI" }
        "nvidia_nim"   { "NVIDIA" }
        "ollama"       { "OLLAMA" }
        default        { "" }
    }
}

# Validate optional per-category model overrides (<PREFIX>_<CATEGORY>_MODEL / _TEMPERATURE).
# These are OPTIONAL, so all findings are warnings:
#   - an incomplete pair (only _MODEL or only _TEMPERATURE) makes the category fall back to MODEL_NAME
#   - a category override whose prefix does not match the active provider is orphaned
function Test-CategoryOverrides {
    param([string[]]$Names)
    $activePrefix = Get-ProviderEnvPrefix $script:LLMProvider
    $allPrefixes  = @("AZURE", "OPENAI", "BEDROCK", "VERTEXAI", "GEMINI", "NVIDIA", "OLLAMA")
    $categories   = @("FAST", "LARGE", "VISION", "CODE", "REASONING")
    foreach ($prefix in $allPrefixes) {
        foreach ($cat in $categories) {
            $hasModel = (("${prefix}_${cat}_MODEL") -in $Names)
            $hasTemp  = (("${prefix}_${cat}_TEMPERATURE") -in $Names)
            if ($prefix -eq $activePrefix) {
                if ($hasModel -and -not $hasTemp) {
                    Write-Warning "${prefix}_${cat}_MODEL is set without ${prefix}_${cat}_TEMPERATURE - category falls back to MODEL_NAME"
                    $script:ValidationDetails += "    [WARN] ${prefix}_${cat}_MODEL set without ${prefix}_${cat}_TEMPERATURE (incomplete pair; category falls back to MODEL_NAME)"
                    $script:ValidationWarnings++
                }
                elseif ($hasTemp -and -not $hasModel) {
                    Write-Warning "${prefix}_${cat}_TEMPERATURE is set without ${prefix}_${cat}_MODEL - category falls back to MODEL_NAME"
                    $script:ValidationDetails += "    [WARN] ${prefix}_${cat}_TEMPERATURE set without ${prefix}_${cat}_MODEL (incomplete pair; category falls back to MODEL_NAME)"
                    $script:ValidationWarnings++
                }
            }
            elseif ($hasModel -or $hasTemp) {
                Write-Warning "${prefix}_${cat}_* override present but active provider is $($script:LLMProvider) - orphaned"
                $script:ValidationDetails += "    [WARN] ${prefix}_${cat}_* override orphaned (active provider is $($script:LLMProvider), expected prefix $activePrefix)"
                $script:ValidationWarnings++
            }
        }
    }
}

##############################################################################
# AWS ECS Validation
##############################################################################

function Validate-AWSECS {
    Write-Info "Validating AWS ECS environment..."
    Write-Host ""
    # CLI install/auth/connectivity already verified in Phase 0 preflight.

    # Validate each task definition (schema bound to entry order via AWSTaskRoles)
    for ($i = 0; $i -lt $script:AWSTaskDefinitions.Count; $i++) {
        Validate-AWSTaskDefinition $script:AWSTaskDefinitions[$i] $script:AWSTaskRoles[$i]
    }
}

function Validate-AWSTaskDefinition {
    param(
        [string]$TaskDef,
        [string]$Role
    )
    
    Write-Info "Fetching task definition: $TaskDef"
    
    try {
        $taskJson = aws ecs describe-task-definition `
            --task-definition $TaskDef `
            --region $script:AWSRegion `
            --query 'taskDefinition.containerDefinitions' `
            --output json | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to fetch task definition: $TaskDef"
        return
    }
    
    if ($Role -eq "both") {
        # All-in-one task definition: identify each service container by name
        foreach ($container in $taskJson) {
            if ($container.name -match "orchestrator") {
                Validate-ContainerEnv -ContainerName $container.name -Container $container -Role "orchestrator"
            }
            elseif ($container.name -match "admin") {
                Validate-ContainerEnv -ContainerName $container.name -Container $container -Role "admin"
            }
        }
    }
    else {
        # Separate task definition: schema is bound to $Role (entry order), not the container name
        $target = $taskJson | Where-Object { $_.name -match $Role } | Select-Object -First 1
        if (-not $target) {
            $target = $taskJson | Select-Object -First 1
            if ($taskJson.Count -gt 1) {
                Write-Warning "Task definition '$TaskDef' has $($taskJson.Count) containers; none match '$Role'. Validating first container ('$($target.name)') against the $Role schema."
            }
        }
        Validate-ContainerEnv -ContainerName $target.name -Container $target -Role $Role
    }
}

function Validate-ContainerEnv {
    param(
        [string]$ContainerName,
        [object]$Container,
        [string]$Role
    )
    
    Write-Host ""
    Write-Info "Validating container: $ContainerName (schema: $Role)"
    
    $envVarNames = @()
    if ($Container.environment) {
        $envVarNames = $Container.environment | ForEach-Object { $_.name }
    }
    
    $secretNames = @()
    if ($Container.secrets) {
        $secretNames = $Container.secrets | ForEach-Object { $_.name }
    }
    
    # Capture the variables discovered in this container.
    # Plain environment values are shown; secret refs and sensitive-looking names are redacted.
    $script:ValidationDetails += ""
    $script:ValidationDetails += "Container: $ContainerName (schema: $Role)"
    if ($Container.environment) {
        $script:ValidationDetails += "  Environment variables found (name = value):"
        foreach ($e in $Container.environment) {
            $script:ValidationDetails += "    - $($e.name) = $(Get-RedactedValue -Name $e.name -Value ([string]$e.value))"
        }
    }
    else {
        $script:ValidationDetails += "  Environment variables found: (none)"
    }
    if ($secretNames.Count -gt 0) {
        $script:ValidationDetails += "  Secret references found (values not shown):"
        foreach ($s in $secretNames) {
            $script:ValidationDetails += "    - $s"
        }
    }
    
    # Determine which schema to use (bound to role, not container name)
    $varsToCheck = if ($Role -eq "admin") {
        $script:AdminConsoleVars
    }
    else {
        $script:OrchestratorVars
    }
    
    # Check required vars
    $script:ValidationDetails += "  Required variables:"
    foreach ($var in $varsToCheck) {
        if ($var -in $envVarNames) {
            Write-Success "$var - present"
            $script:ValidationDetails += "    [PASS] $var - present"
        }
        elseif ($var -in $secretNames) {
            Write-Success "$var - present (secret ref)"
            $script:ValidationDetails += "    [PASS] $var - present (secret ref)"
        }
        else {
            Write-Error "$var - MISSING [REQUIRED]"
            $script:ValidationDetails += "    [FAIL] $var - MISSING [REQUIRED]"
            $script:ValidationErrors++
        }
    }
    
    # Check for orphaned vars
    Write-Host ""
    Write-Info "Checking for orphaned variables..."
    
    $allLLMVars = @(
        "AZURE_OPENAI_ENDPOINT", "OPENAI_API_KEY", "OPENAI_API_VERSION",
        "AWS_REGION", "AWS_BEDROCK", "MODEL_NAME",
        "GOOGLE_PROJECT_ID", "GOOGLE_REGION", "GOOGLE_API_KEY",
        "NVIDIA_API_KEY", "NVIDIA_BASE_URL",
        "OLLAMA_BASE_URL", "OLLAMA_MODEL",
        "VERTEX_AI"
    )
    
    foreach ($var in ($envVarNames + $secretNames)) {
        if ($var -in $allLLMVars) {
            if ($script:LLMProvider -ne "openai" -and $script:LLMProvider -ne "azure_openai" -and $var -eq "OPENAI_API_KEY") {
                Write-Warning "$var - orphaned (you're using $($script:LLMProvider), not OpenAI)"
                $script:ValidationDetails += "    [WARN] $var - orphaned (using $($script:LLMProvider), not OpenAI)"
                $script:ValidationWarnings++
            }
            elseif ($script:LLMProvider -ne "azure_openai" -and $var -eq "AZURE_OPENAI_ENDPOINT") {
                Write-Warning "$var - orphaned (you're using $($script:LLMProvider), not Azure OpenAI)"
                $script:ValidationDetails += "    [WARN] $var - orphaned (using $($script:LLMProvider), not Azure OpenAI)"
                $script:ValidationWarnings++
            }
        }
    }

    # Validate optional per-category model overrides (pair completeness + provider-prefix match)
    Test-CategoryOverrides ($envVarNames + $secretNames)
}

##############################################################################
# Azure Container Apps Validation
##############################################################################

function Validate-AzureACA {
    Write-Info "Validating Azure Container Apps environment..."
    Write-Host ""
    # CLI install/auth/connectivity already verified in Phase 0 preflight.

    # Validate each container app (schema bound to entry order via AzureAppRoles)
    for ($i = 0; $i -lt $script:AzureContainerApps.Count; $i++) {
        Validate-AzureContainerApp $script:AzureContainerApps[$i] $script:AzureAppRoles[$i]
    }
}

function Validate-AzureContainerApp {
    param(
        [string]$AppName,
        [string]$Role
    )
    
    Write-Info "Fetching Container App: $AppName"
    
    try {
        $appJson = az containerapp show `
            --resource-group $script:AzureResourceGroup `
            --name $AppName `
            --output json | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to fetch Container App: $AppName"
        return
    }
    
    if ($Role -eq "both") {
        # All-in-one Container App: identify each service container by name
        foreach ($container in $appJson.properties.template.containers) {
            if ($container.name -match "orchestrator") {
                Validate-ACAContainerEnv -AppName $AppName -ContainerName $container.name -Container $container -Role "orchestrator"
            }
            elseif ($container.name -match "admin") {
                Validate-ACAContainerEnv -AppName $AppName -ContainerName $container.name -Container $container -Role "admin"
            }
        }
    }
    else {
        # Separate Container App: schema is bound to $Role (entry order), not the container name
        $containers = @($appJson.properties.template.containers)
        $target = $containers | Where-Object { $_.name -match $Role } | Select-Object -First 1
        if (-not $target) {
            $target = $containers | Select-Object -First 1
            if ($containers.Count -gt 1) {
                Write-Warning "Container App '$AppName' has $($containers.Count) containers; none match '$Role'. Validating first container ('$($target.name)') against the $Role schema."
            }
        }
        Validate-ACAContainerEnv -AppName $AppName -ContainerName $target.name -Container $target -Role $Role
    }
}

function Validate-ACAContainerEnv {
    param(
        [string]$AppName,
        [string]$ContainerName,
        [object]$Container,
        [string]$Role
    )
    
    Write-Host ""
    Write-Info "Validating Container App: $AppName, Container: $ContainerName (schema: $Role)"
    
    $envVarNames = @()
    if ($Container.env) {
        $envVarNames = $Container.env | ForEach-Object { $_.name }
    }
    
    # Capture the variables discovered in this container.
    # Plain values are shown; secret refs and sensitive-looking names are redacted.
    $script:ValidationDetails += ""
    $script:ValidationDetails += "Container: $AppName / $ContainerName (schema: $Role)"
    if ($Container.env) {
        $script:ValidationDetails += "  Environment variables found (name = value):"
        foreach ($e in $Container.env) {
            if ($e.secretRef) {
                $script:ValidationDetails += "    - $($e.name) (secret ref: $($e.secretRef))"
            }
            else {
                $script:ValidationDetails += "    - $($e.name) = $(Get-RedactedValue -Name $e.name -Value ([string]$e.value))"
            }
        }
    }
    else {
        $script:ValidationDetails += "  Environment variables found: (none)"
    }
    
    # Determine which schema to use (bound to role, not container name)
    $varsToCheck = if ($Role -eq "admin") {
        $script:AdminConsoleVars
    }
    else {
        $script:OrchestratorVars
    }
    
    # Check required vars
    $script:ValidationDetails += "  Required variables:"
    foreach ($var in $varsToCheck) {
        if ($var -in $envVarNames) {
            Write-Success "$var - present"
            $script:ValidationDetails += "    [PASS] $var - present"
        }
        else {
            Write-Error "$var - MISSING [REQUIRED]"
            $script:ValidationDetails += "    [FAIL] $var - MISSING [REQUIRED]"
            $script:ValidationErrors++
        }
    }
    
    # Check for orphaned vars
    Write-Host ""
    Write-Info "Checking for orphaned variables..."
    
    $allLLMVars = @(
        "AZURE_OPENAI_ENDPOINT", "OPENAI_API_KEY", "OPENAI_API_VERSION",
        "AWS_REGION", "AWS_BEDROCK", "MODEL_NAME",
        "GOOGLE_PROJECT_ID", "GOOGLE_REGION", "GOOGLE_API_KEY",
        "NVIDIA_API_KEY", "NVIDIA_BASE_URL",
        "OLLAMA_BASE_URL", "OLLAMA_MODEL",
        "VERTEX_AI"
    )
    
    foreach ($var in $envVarNames) {
        if ($var -in $allLLMVars) {
            if ($script:LLMProvider -ne "openai" -and $script:LLMProvider -ne "azure_openai" -and $var -eq "OPENAI_API_KEY") {
                Write-Warning "$var - orphaned (you're using $($script:LLMProvider), not OpenAI)"
                $script:ValidationDetails += "    [WARN] $var - orphaned (using $($script:LLMProvider), not OpenAI)"
                $script:ValidationWarnings++
            }
            elseif ($script:LLMProvider -ne "azure_openai" -and $var -eq "AZURE_OPENAI_ENDPOINT") {
                Write-Warning "$var - orphaned (you're using $($script:LLMProvider), not Azure OpenAI)"
                $script:ValidationDetails += "    [WARN] $var - orphaned (using $($script:LLMProvider), not Azure OpenAI)"
                $script:ValidationWarnings++
            }
        }
    }

    # Validate optional per-category model overrides (pair completeness + provider-prefix match)
    Test-CategoryOverrides $envVarNames
}

##############################################################################
# Report Generation
##############################################################################

function Generate-Report {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    $platformLabel = if ($script:CloudPlatform -eq "aws") { "ecs" } else { "aca" }
    $script:ReportFile = "validation-report-${timestamp}-${platformLabel}.txt"
    
    $reportContent = @"
========================================================================
Spotfire Copilot Environment Validation Report
========================================================================

Generated: $(Get-Date)
Platform: $(if ($script:CloudPlatform -eq 'aws') { 'AWS ECS/Fargate' } else { 'Azure Container Apps' })

$(if ($script:CloudPlatform -eq 'aws') {
    $awsLines = "Region: $($script:AWSRegion)`nCluster: $($script:AWSCluster)"
    if ($script:AWSServiceNames.Count -gt 0) { $awsLines += "`nServices: $($script:AWSServiceNames -join ', ')" }
    $awsLines += "`nTask Definitions: $($script:AWSTaskDefinitions -join ', ')"
    $awsLines
} else {
"Resource Group: $($script:AzureResourceGroup)
Location: $($script:AzureLocation)
Container Apps: $($script:AzureContainerApps -join ', ')"
})

LLM Provider: $($script:LLMProvider)
Admin Console Deployed: $(if ($script:HasAdminConsole) { 'Yes' } else { 'No' })

========================================================================

Summary:
  Errors:   $($script:ValidationErrors)
  Warnings: $($script:ValidationWarnings)

Status: $(if ($script:ValidationErrors -eq 0) { 'OK VALIDATION PASSED' } else { 'X VALIDATION FAILED' })

========================================================================

Validation Details (variables discovered per container):
(Plain environment values are shown; secrets and sensitive-looking values are redacted as ********.)
$(if ($script:ValidationDetails.Count -gt 0) { ($script:ValidationDetails -join "`n") } else { "  (no per-container details were captured)" })

========================================================================
"@
    
    $reportContent | Out-File -FilePath $script:ReportFile -Encoding UTF8
    Write-Success "Report written to: $script:ReportFile"
}

##############################################################################
# Main Flow
##############################################################################

function Main {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Spotfire Copilot Environment Validator" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan

    # Offer to resume from previously saved answers
    if (Test-Path $script:AnswersFile) {
        Write-Host ""
        Write-Info "Found saved answers: $($script:AnswersFile)"
        Get-Content $script:AnswersFile |
            Where-Object { $_ -match '^(CLOUD_PLATFORM|AWS_REGION|AWS_CLUSTER|AWS_TASK_DEFINITIONS|AWS_SERVICE_NAMES|AZURE_RESOURCE_GROUP|AZURE_LOCATION|AZURE_CONTAINER_APPS|LLM_PROVIDER|HAS_ADMIN_CONSOLE)=' } |
            ForEach-Object { Write-Host "    $_" }
        Write-Host ""
        $resume = Read-Host "Resume with these saved answers? (y/n)"
        if ($resume -match '^(?i)y') {
            Load-Answers
            $script:Resumed = $true
            Write-Success "Resumed from saved answers."
        }
    }

    if ($script:Resumed) {
        # Still verify the CLI is installed, authenticated, and can reach resources
        Preflight-CheckCli
    }
    else {
        Phase1-DetectPlatform
        Phase2-TemplateOrSchema
        Save-Answers
    }

    Build-ValidationSchemas
    
    Write-Host ""
    Write-Info "Phase 3: Validation Execution"
    Write-Host ""
    
    if ($script:CloudPlatform -eq "aws") {
        Validate-AWSECS
    }
    else {
        Validate-AzureACA
    }
    
    Write-Host ""
    Write-Info "Phase 4: Report Generation"
    Generate-Report
    
    Write-Host ""
    if ($script:ValidationErrors -eq 0) {
        Write-Success "Validation passed!"
        exit 0
    }
    else {
        Write-Error "Validation failed with $($script:ValidationErrors) error(s)"
        exit 1
    }
}

# Run main
Main
