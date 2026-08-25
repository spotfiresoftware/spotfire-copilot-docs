#############################################################################
#  Spotfire Copilot - Troubleshooting Bundle
#  Version: 2.3.x
#
#  Purpose: Validates environment variables for Orchestrator and Admin Console,
#           and collects container logs into a single zipped troubleshooting
#           bundle. Supports AWS ECS/Fargate, Azure Container Apps, on-prem
#           Docker Compose, and Kubernetes (EKS/AKS/GKE).
#
#  Usage:
#    .\spotfire-copilot-troubleshooting-bundle.ps1
#    .\spotfire-copilot-troubleshooting-bundle.ps1 -Logs   # collect logs into a bundle only
#
#  Supports:
#    - AWS ECS/Fargate (identify by ECS service name or task definition)
#    - Azure Container Apps (single or multiple apps)
#    - Docker Compose (on-prem)
#    - Kubernetes (EKS / AKS / GKE)
#    - Template-based validation or interactive schema builder
#    - Saved answers with resume (troubleshooting-bundle-answers.env)
#    - Log collection zipped as "Spotfire Copilot Troubleshooting Bundle <date>.zip"
#    - No-CLI fallback (manual JSON import)
#############################################################################

param(
    [switch]$Logs
)

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
# Docker Compose (on-prem)
$ComposeFile = ""
$ComposeProject = ""
$ComposeServices = @()
$ComposeServiceRoles = @()
# Kubernetes (EKS/AKS/GKE)
$K8sContext = ""
$K8sNamespace = ""
$K8sWorkloads = @()
$K8sWorkloadRoles = @()
$K8sIncludePrevious = $false
# Log time window (default 1h). Override with $env:LOG_SINCE.
$LogSince = if ($env:LOG_SINCE) { $env:LOG_SINCE } else { "1h" }
# Directory logs are written to before bundling (set by Bundle-ContainerLogs)
$LogOutputDir = "."
$HasTemplate = $false
$TemplateFile = ""
$LLMProvider = ""
$HasAdminConsole = $false
$OrchestratorVars = @()
$AdminConsoleVars = @()
$OptionalVars = @()
$ReportFile = ""
$ValidationErrors = 0
$ValidationWarnings = 0
$ValidationDetails = @()  # per-container results captured for the report

# Saved-answers file (resume support). Override with $env:TROUBLESHOOTING_ANSWERS_FILE.
$AnswersFile = if ($env:TROUBLESHOOTING_ANSWERS_FILE) { $env:TROUBLESHOOTING_ANSWERS_FILE } else { "troubleshooting-bundle-answers.env" }
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
        "# Spotfire Copilot Troubleshooting Bundle - saved answers"
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
        "COMPOSE_FILE=$($script:ComposeFile)"
        "COMPOSE_PROJECT=$($script:ComposeProject)"
        "COMPOSE_SERVICES=$($script:ComposeServices -join ' ')"
        "COMPOSE_SERVICE_ROLES=$($script:ComposeServiceRoles -join ' ')"
        "K8S_CONTEXT=$($script:K8sContext)"
        "K8S_NAMESPACE=$($script:K8sNamespace)"
        "K8S_WORKLOADS=$($script:K8sWorkloads -join ' ')"
        "K8S_WORKLOAD_ROLES=$($script:K8sWorkloadRoles -join ' ')"
        "K8S_INCLUDE_PREVIOUS=$(if ($script:K8sIncludePrevious) { 'true' } else { 'false' })"
        "LLM_PROVIDER=$($script:LLMProvider)"
        "HAS_ADMIN_CONSOLE=$(if ($script:HasAdminConsole) { 'true' } else { 'false' })"
        "HAS_TEMPLATE=$(if ($script:HasTemplate) { 'true' } else { 'false' })"
        "TEMPLATE_FILE=$($script:TemplateFile)"
    )
    $lines | Set-Content -Path $script:AnswersFile -Encoding UTF8
    Write-Host ""
    Write-Success "Answers saved to $($script:AnswersFile)"
    Write-Info "Next time, re-run this tool and choose 'resume' to skip re-entering these."
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
            'COMPOSE_FILE'         { $script:ComposeFile = $value }
            'COMPOSE_PROJECT'      { $script:ComposeProject = $value }
            'COMPOSE_SERVICES'     { $script:ComposeServices = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'COMPOSE_SERVICE_ROLES' { $script:ComposeServiceRoles = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'K8S_CONTEXT'          { $script:K8sContext = $value }
            'K8S_NAMESPACE'        { $script:K8sNamespace = $value }
            'K8S_WORKLOADS'        { $script:K8sWorkloads = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'K8S_WORKLOAD_ROLES'   { $script:K8sWorkloadRoles = @($value -split '\s+' | Where-Object { $_ -ne '' }) }
            'K8S_INCLUDE_PREVIOUS' { $script:K8sIncludePrevious = ($value -match '^(?i)(true|1|yes)$') }
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

    switch ($script:CloudPlatform) {
        'aws'     { Preflight-CheckPrereqs; Preflight-CheckAws }
        'azure'   { Preflight-CheckPrereqs; Preflight-CheckAzure }
        'compose' { Preflight-CheckDocker }
        'k8s'     { Preflight-CheckKubectl }
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
        Write-Host "No local CLI? Use the AWS CloudShell export fallback (see README.md)."
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
        Write-Host "No local CLI? Use the Azure Cloud Shell export fallback (see README.md)."
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

    # 4) Ensure the 'az containerapp' command group is available.
    #    Disable dynamic-install so a missing extension errors immediately instead of prompting.
    Write-Host ""
    Write-Info "Checking for the 'az containerapp' command group..."
    $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = "no"
    az containerapp --help 2>&1 | Out-Null
    $caRc = $LASTEXITCODE
    Remove-Item Env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL -ErrorAction SilentlyContinue
    if ($caRc -ne 0) {
        Write-Error "The 'az containerapp' command group is not available."
        Write-Host ""
        Write-Host "Install/enable it, then re-run this validator:"
        Write-Host "  az extension add --name containerapp --upgrade"
        Write-Host "  az provider register --namespace Microsoft.App"
        Write-Host "  Docs: https://learn.microsoft.com/en-us/azure/container-apps/get-started"
        Write-Host ""
        exit 1
    }
    Write-Success "'az containerapp' command group available."

    Write-Host ""
    Write-Success "Preflight passed - the Azure CLI can talk to your resources."
}

function Preflight-CheckDocker {
    # Docker Compose (on-prem): only the local Docker engine is needed - no cloud CLI/auth.
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Docker is not installed (required to read Docker Compose logs)."
        Write-Host ""
        Write-Host "Install Docker Engine 20.10+ with Compose V2, then re-run this tool."
        Write-Host "  Docs: https://docs.docker.com/engine/install/"
        exit 1
    }
    Write-Success "Docker found: $((docker --version) 2>&1 | Select-Object -First 1)"

    Write-Host ""
    Write-Info "Checking Docker engine connectivity (docker info)..."
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "The Docker CLI is installed but cannot reach the Docker engine."
        Write-Host "Start Docker Desktop / the Docker daemon, then re-run this tool."
        exit 1
    }
    docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "'docker compose' (Compose V2) was not detected - log collection needs Compose V2."
    }
    Write-Host ""
    Write-Success "Preflight passed - the Docker engine is reachable."
}

function Preflight-CheckKubectl {
    # Kubernetes (EKS/AKS/GKE): a working kubectl context is all that is needed.
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "kubectl is not installed (required to read Kubernetes logs)."
        Write-Host ""
        Write-Host "Install kubectl, then re-run this tool:"
        Write-Host "  https://kubernetes.io/docs/tasks/tools/"
        Write-Host "  For EKS, first run: aws eks update-kubeconfig --name <cluster> --region <region>"
        exit 1
    }
    Write-Success "kubectl found."

    Write-Host ""
    Write-Info "Checking cluster connectivity (kubectl cluster-info)..."
    kubectl cluster-info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "kubectl is installed but cannot reach a cluster."
        Write-Host "Configure your kubeconfig/context, then re-run this tool:"
        Write-Host "  aws eks update-kubeconfig --name <cluster> --region <region>"
        Write-Host "  kubectl config current-context"
        exit 1
    }
    Write-Host ""
    Write-Success "Preflight passed - kubectl can reach your cluster."
}

##############################################################################
# Phase 1: Platform & Topology Detection
##############################################################################

function Phase1-DetectPlatform {
    Write-Host ""
    Write-Info "Phase 1: Platform Detection"
    Write-Host ""
    Write-Host "Where is the backend deployed?"
    Write-Host "  1) AWS ECS/Fargate"
    Write-Host "  2) Azure Container Apps"
    Write-Host "  3) Docker Compose (on-prem)"
    Write-Host "  4) Kubernetes (EKS / AKS / GKE)"
    Write-Host ""
    
    $platformChoice = Read-Choice -Prompt "Enter choice (1-4)" -MaxChoice 4
    
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
        3 {
            $script:CloudPlatform = "compose"
            Preflight-CheckCli
            Phase1-DetectComposeTopology
        }
        4 {
            $script:CloudPlatform = "k8s"
            Preflight-CheckCli
            Phase1-DetectK8sTopology
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

function Phase1-DetectComposeTopology {
    Write-Host ""
    $used = Read-Host "Did you deploy with the Spotfire Copilot deployment scripts? (y/n) [y]"
    if (-not $used) { $used = "y" }

    $script:ComposeFile = Read-Host "Path to your docker-compose file [docker-compose.yml]"
    if (-not $script:ComposeFile) { $script:ComposeFile = "docker-compose.yml" }
    $script:ComposeProject = Read-Host "Compose project name (press Enter to use the folder name)"

    if ($used -match '^(?i)y') {
        # Standard service names emitted by the deploy scripts
        $script:ComposeServices = @("orchestrator", "admin-console")
        $script:ComposeServiceRoles = @("orchestrator", "admin")
        Write-Info "Using standard service names: orchestrator, admin-console"
    }
    else {
        Write-Host ""
        Write-Host "How are your services deployed?"
        Write-Host "  1) Both services in one compose file (default)"
        Write-Host "  2) Orchestrator only"
        Write-Host ""
        $topo = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2
        $svcOrch = Read-Host "Orchestrator service name [orchestrator]"
        if (-not $svcOrch) { $svcOrch = "orchestrator" }
        if ($topo -eq 1) {
            $svcAdmin = Read-Host "Admin Console service name [admin-console]"
            if (-not $svcAdmin) { $svcAdmin = "admin-console" }
            $script:ComposeServices = @($svcOrch, $svcAdmin)
            $script:ComposeServiceRoles = @("orchestrator", "admin")
        }
        else {
            $script:ComposeServices = @($svcOrch)
            $script:ComposeServiceRoles = @("orchestrator")
        }
    }
    Write-Info "Compose file: $($script:ComposeFile)"
}

function Phase1-DetectK8sTopology {
    Write-Host ""
    $script:K8sContext = Read-Host "kubectl context (press Enter for the current context)"
    $script:K8sNamespace = Read-Host "Kubernetes namespace [copilot]"
    if (-not $script:K8sNamespace) { $script:K8sNamespace = "copilot" }

    $used = Read-Host "Did you deploy with the Spotfire Copilot deployment scripts? (y/n) [y]"
    if (-not $used) { $used = "y" }

    if ($used -match '^(?i)y') {
        # Standard deployment names emitted by the deploy scripts / manifests
        $script:K8sWorkloads = @("deployment/orchestrator", "deployment/admin-console")
        $script:K8sWorkloadRoles = @("orchestrator", "admin")
        Write-Info "Using standard deployments: orchestrator, admin-console"
    }
    else {
        Write-Host ""
        Write-Host "How do you want to identify the workloads?"
        Write-Host "  1) Deployment names (recommended)"
        Write-Host "  2) Label selectors"
        Write-Host ""
        $idc = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2
        if ($idc -eq 2) {
            $orch = Read-Host "Orchestrator label selector [app=orchestrator]"
            if (-not $orch) { $orch = "app=orchestrator" }
            $admin = Read-Host "Admin Console label selector (blank if not deployed)"
            $script:K8sWorkloads = @("-l|$orch")
            $script:K8sWorkloadRoles = @("orchestrator")
            if ($admin) {
                $script:K8sWorkloads += "-l|$admin"
                $script:K8sWorkloadRoles += "admin"
            }
        }
        else {
            $orch = Read-Host "Orchestrator deployment name [orchestrator]"
            if (-not $orch) { $orch = "orchestrator" }
            $admin = Read-Host "Admin Console deployment name (blank if not deployed)"
            $script:K8sWorkloads = @("deployment/$orch")
            $script:K8sWorkloadRoles = @("orchestrator")
            if ($admin) {
                $script:K8sWorkloads += "deployment/$admin"
                $script:K8sWorkloadRoles += "admin"
            }
        }
    }

    $prev = Read-Host "Also fetch logs from previous (crashed/restarted) pods? (y/n) [y]"
    if (-not $prev) { $prev = "y" }
    $script:K8sIncludePrevious = ($prev -match '^(?i)y')
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
        "LOG_LEVEL",
        "SECRET_KEY",
        "HASHED_ADMIN_PASSWORD",
        "SYNC_DATABASE_URL",
        "DB_SSLMODE"
    )

    # Informational-only vars: required for Docker Compose but NOT for cloud.
    # ECS / Container Apps carry the image tag in the image reference, so these
    # are reported but never fail validation.
    $script:OptionalVars = @(
        "IMAGE_TAG",
        "FASTAPI_APP_VERSION"
    )
}

# Report optional/informational vars. Present or not, these never fail validation.
function Test-OptionalVars {
    param([string[]]$PresentNames)
    if (-not $script:OptionalVars -or $script:OptionalVars.Count -eq 0) { return }
    $script:ValidationDetails += "  Optional variables (informational):"
    foreach ($var in $script:OptionalVars) {
        if ($var -in $PresentNames) {
            Write-Info "$var - present (optional)"
            $script:ValidationDetails += "    [INFO] $var - present (optional)"
        }
        else {
            Write-Info "$var - not set (optional; cloud carries the image tag in the image reference)"
            $script:ValidationDetails += "    [INFO] $var - not set (optional; not required for cloud)"
        }
    }
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
# Retriever credentials, GPT-5 flag, and value-sanity checks
##############################################################################

# Case-insensitive test for a GPT-5.x / o-series model name.
function Test-IsGpt5Model {
    param([string]$ModelName)
    if ($null -eq $ModelName) { return $false }
    return ($ModelName.ToLowerInvariant() -match '^(gpt-5|gpt5|o1|o3|o4)')
}

# Non-fatal WARN checks that the fixed required-var schema cannot express:
#   1. retriever plugin set without its backing credentials
#   2. GPT-5.x / o-series MODEL_NAME without OPENAI_GPT5_COMPATIBLE=true
#   3. malformed/whitespace values (bare-name and URL sanity)
# Only meaningful for the orchestrator schema. All findings are warnings.
function Test-RuntimeConfig {
    param(
        [string]$Role,
        [string[]]$Present,
        [hashtable]$Values
    )
    if ($Role -eq 'admin') { return }

    $retriever = [string]$Values['RETRIEVER_PLUGIN_ENTRY_POINT']
    $model     = [string]$Values['MODEL_NAME']
    $gpt5      = [string]$Values['OPENAI_GPT5_COMPATIBLE']

    # --- 1. Retriever credential completeness (keyed off the plugin entry point) ---
    if ($retriever -like '*az_cog_search*') {
        foreach ($req in @('AZURE_COGNITIVE_SEARCH_SERVICE_NAME', 'AZURE_COGNITIVE_SEARCH_API_KEY')) {
            if ($req -notin $Present) {
                Write-Warning "RETRIEVER_PLUGIN_ENTRY_POINT is Azure AI Search but $req is not set - RAG warmup will fail"
                $script:ValidationDetails += "    [WARN] $req missing while RETRIEVER_PLUGIN_ENTRY_POINT is Azure AI Search"
                $script:ValidationWarnings++
            }
        }
        $svc = [string]$Values['AZURE_COGNITIVE_SEARCH_SERVICE_NAME']
        if ($svc -and ($svc -match '://' -or $svc -match '\.search\.windows\.net' -or $svc -match '\s')) {
            Write-Warning "AZURE_COGNITIVE_SEARCH_SERVICE_NAME='$svc' looks malformed - use the BARE service name (no https://, no .search.windows.net, no spaces)"
            $script:ValidationDetails += "    [WARN] AZURE_COGNITIVE_SEARCH_SERVICE_NAME malformed (expected bare service name, got '$svc')"
            $script:ValidationWarnings++
        }
    }
    elseif ($retriever -like '*milvus*') {
        if ('VECTORDB_URI' -notin $Present) {
            Write-Warning "RETRIEVER_PLUGIN_ENTRY_POINT is Milvus but VECTORDB_URI is not set - RAG warmup will fail"
            $script:ValidationDetails += "    [WARN] VECTORDB_URI missing while RETRIEVER_PLUGIN_ENTRY_POINT is Milvus"
            $script:ValidationWarnings++
        }
    }
    elseif ($retriever -like '*redis*') {
        if ('VECTORDB_URI' -notin $Present) {
            Write-Warning "RETRIEVER_PLUGIN_ENTRY_POINT is Redis but VECTORDB_URI is not set - RAG warmup will fail"
            $script:ValidationDetails += "    [WARN] VECTORDB_URI missing while RETRIEVER_PLUGIN_ENTRY_POINT is Redis"
            $script:ValidationWarnings++
        }
    }

    # --- 2. GPT-5.x / o-series compatibility flag ---
    if (Test-IsGpt5Model $model) {
        $gpt5Norm = ($gpt5 -replace '\s', '').ToLowerInvariant()
        if ($gpt5Norm -ne 'true') {
            $shown = if ([string]::IsNullOrEmpty($gpt5)) { '<unset>' } else { $gpt5 }
            Write-Warning "MODEL_NAME='$model' is a GPT-5.x / o-series model but OPENAI_GPT5_COMPATIBLE is not 'true' - chat completions will fail (temperature/max_tokens mismatch)"
            $script:ValidationDetails += "    [WARN] MODEL_NAME='$model' requires OPENAI_GPT5_COMPATIBLE=true (currently '$shown')"
            $script:ValidationWarnings++
        }
    }

    # --- 3. Value sanity: leading/trailing whitespace in URL/endpoint values ---
    foreach ($name in $Values.Keys) {
        if ($name -match 'URL|ENDPOINT|_EP$' -or $name -eq 'AZSEARCH_EP') {
            $val = [string]$Values[$name]
            if ($val -ne $val.Trim()) {
                Write-Warning "$name has leading/trailing whitespace - trim it or the value will be malformed"
                $script:ValidationDetails += "    [WARN] $name has leading/trailing whitespace (trim required)"
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
    
    # Report optional/informational vars (not required for cloud deployments)
    Test-OptionalVars (@($envVarNames) + @($secretNames))

    # Retriever-credential, GPT-5-flag, and value-sanity checks (non-fatal warnings)
    $plainValues = @{}
    if ($Container.environment) {
        foreach ($e in $Container.environment) { $plainValues[$e.name] = [string]$e.value }
    }
    Test-RuntimeConfig -Role $Role -Present (@($envVarNames) + @($secretNames)) -Values $plainValues
    
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
    $secretBackedNames = @()
    if ($Container.env) {
        $envVarNames = $Container.env | ForEach-Object { $_.name }
        $secretBackedNames = $Container.env | Where-Object { $_.secretRef } | ForEach-Object { $_.name }
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
            if ($var -in $secretBackedNames) {
                Write-Success "$var - present (secret ref)"
                $script:ValidationDetails += "    [PASS] $var - present (secret ref)"
            }
            else {
                Write-Success "$var - present"
                $script:ValidationDetails += "    [PASS] $var - present"
            }
        }
        else {
            Write-Error "$var - MISSING [REQUIRED]"
            $script:ValidationDetails += "    [FAIL] $var - MISSING [REQUIRED]"
            $script:ValidationErrors++
        }
    }
    
    # Report optional/informational vars (not required for cloud deployments)
    Test-OptionalVars $envVarNames

    # Retriever-credential, GPT-5-flag, and value-sanity checks (non-fatal warnings).
    # Only plain (non-secret) env entries carry inspectable values.
    $plainValues = @{}
    if ($Container.env) {
        foreach ($e in $Container.env) { if (-not $e.secretRef) { $plainValues[$e.name] = [string]$e.value } }
    }
    Test-RuntimeConfig -Role $Role -Present $envVarNames -Values $plainValues
    
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
# Container log download (troubleshooting)
##############################################################################

# Ask which container's logs to download. Returns orchestrator|admin|both.
function Prompt-LogTarget {
    Write-Host ""
    Write-Host "Which container's logs do you want to download?"
    Write-Host "  1) Orchestrator"
    Write-Host "  2) Admin Console"
    Write-Host "  3) Both"
    $c = Read-Host "Enter choice (1-3)"
    switch ($c) {
        '1' { return 'orchestrator' }
        '2' { return 'admin' }
        '3' { return 'both' }
        default { return 'orchestrator' }
    }
}

# Download CloudWatch logs for the $Want container from a given task definition.
function Download-EcsLogsFromTaskDef {
    param([string]$TaskDef, [string]$Want)

    try {
        $containers = aws ecs describe-task-definition `
            --task-definition $TaskDef `
            --region $script:AWSRegion `
            --query 'taskDefinition.containerDefinitions' `
            --output json | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to fetch task definition: $TaskDef"
        return
    }

    $c = $containers | Where-Object { $_.name -match $Want } | Select-Object -First 1
    if (-not $c) {
        Write-Warning "No '$Want' container found in task definition '$TaskDef'."
        return
    }

    $lc = $c.logConfiguration
    $driver = if ($lc -and $lc.logDriver) { $lc.logDriver } else { 'none' }
    if ($driver -ne 'awslogs') {
        Write-Warning "Container '$($c.name)' uses log driver '$driver' (not awslogs) - cannot read from CloudWatch."
        Write-Warning "Inspect your logging sink (e.g., FireLens) directly instead."
        return
    }

    $group  = $lc.options.'awslogs-group'
    $prefix = $lc.options.'awslogs-stream-prefix'
    $region = $lc.options.'awslogs-region'
    if (-not $region) { $region = $script:AWSRegion }
    if (-not $group) {
        Write-Warning "Container '$($c.name)' has no awslogs-group configured."
        return
    }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $outfile = Join-Path $script:LogOutputDir "container-logs-$ts-ecs-$Want.log"
    Write-Info "Fetching CloudWatch logs for '$($c.name)' (group '$group', last $($script:LogSince))..."

    $header = @(
        "# Spotfire Copilot container logs"
        "# Generated:       $(Get-Date)"
        "# Platform:        AWS ECS/Fargate"
        "# Region:          $region"
        "# Cluster:         $($script:AWSCluster)"
        "# Task definition: $TaskDef"
        "# Container:       $($c.name) ($Want)"
        "# Log group:       $group"
        "# Stream prefix:   $(if ($prefix) { $prefix } else { '<none>' })"
        "# Window:          last $($script:LogSince)"
        "# --------------------------------------------------------------"
    )
    $header | Set-Content -Path $outfile -Encoding UTF8

    if ($prefix) {
        $logs = aws logs tail $group --since $script:LogSince --region $region --format short --log-stream-name-prefix "$prefix/$($c.name)" 2>&1
    }
    else {
        $logs = aws logs tail $group --since $script:LogSince --region $region --format short 2>&1
    }
    $logs | Add-Content -Path $outfile -Encoding UTF8

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Saved logs to $outfile"
    }
    else {
        Write-Warning "aws logs tail returned an error (see the end of $outfile)."
    }
}

# Resolve the actual container name for $Want inside an Azure Container App.
function Get-AcaContainerName {
    param([string]$App, [string]$Want)
    try {
        $appJson = az containerapp show `
            --resource-group $script:AzureResourceGroup `
            --name $App `
            --output json | ConvertFrom-Json
    }
    catch { return "" }
    $c = $appJson.properties.template.containers | Where-Object { $_.name -match $Want } | Select-Object -First 1
    if ($c) { return $c.name } else { return "" }
}

# Download recent console logs for a container in an Azure Container App.
function Download-AcaLogs {
    param([string]$App, [string]$Container, [string]$Want)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $outfile = Join-Path $script:LogOutputDir "container-logs-$ts-aca-$Want.log"
    Write-Info "Fetching Container App logs for '$App' container '$Container' (recent lines)..."

    $header = @(
        "# Spotfire Copilot container logs"
        "# Generated:       $(Get-Date)"
        "# Platform:        Azure Container Apps"
        "# Resource group:  $($script:AzureResourceGroup)"
        "# Container App:   $App"
        "# Container:       $Container ($Want)"
        "# Window:          most recent 2000 console log lines (ACA has no time-window flag; use Log Analytics for a strict 1h window)"
        "# --------------------------------------------------------------"
    )
    $header | Set-Content -Path $outfile -Encoding UTF8

    $logs = az containerapp logs show `
        --name $App `
        --resource-group $script:AzureResourceGroup `
        --container $Container `
        --tail 2000 2>&1
    $logs | Add-Content -Path $outfile -Encoding UTF8

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Saved logs to $outfile"
    }
    else {
        Write-Warning "az containerapp logs show returned an error (see the end of $outfile)."
    }
}

# Download recent logs for a Docker Compose service (on-prem). Needs only Docker.
function Download-ComposeLogs {
    param([string]$Service, [string]$Want)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $outfile = Join-Path $script:LogOutputDir "container-logs-$ts-compose-$Want.log"
    Write-Info "Fetching Docker Compose logs for service '$Service' (last $($script:LogSince))..."
    $header = @(
        "# Spotfire Copilot container logs"
        "# Generated:       $(Get-Date)"
        "# Platform:        Docker Compose (on-prem)"
        "# Compose file:    $($script:ComposeFile)"
        "# Project:         $(if ($script:ComposeProject) { $script:ComposeProject } else { '<directory default>' })"
        "# Service:         $Service ($Want)"
        "# Window:          last $($script:LogSince)"
        "# --------------------------------------------------------------"
    )
    $header | Set-Content -Path $outfile -Encoding UTF8

    $composeArgs = @('compose', '-f', $script:ComposeFile)
    if ($script:ComposeProject) { $composeArgs += @('-p', $script:ComposeProject) }
    $composeArgs += @('logs', '--no-color', '--since', $script:LogSince, $Service)
    $logs = & docker @composeArgs 2>&1
    $logs | Add-Content -Path $outfile -Encoding UTF8

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Saved logs to $outfile"
    }
    else {
        Write-Warning "docker compose logs returned an error (see the end of $outfile)."
    }
}

# Download recent logs for a Kubernetes workload (deployment/<name> or "-l|<selector>").
function Download-K8sLogs {
    param([string]$Target, [string]$Want)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $outfile = Join-Path $script:LogOutputDir "container-logs-$ts-k8s-$Want.log"

    if ($Target -like '-l|*') {
        $sel = @('-l', $Target.Substring(3))
    }
    else {
        $sel = @($Target)
    }

    $base = @()
    if ($script:K8sContext) { $base += @('--context', $script:K8sContext) }
    $base += @('-n', $script:K8sNamespace)

    Write-Info "Fetching Kubernetes logs for '$Target' in namespace '$($script:K8sNamespace)' (last $($script:LogSince))..."
    $header = @(
        "# Spotfire Copilot container logs"
        "# Generated:       $(Get-Date)"
        "# Platform:        Kubernetes"
        "# Context:         $(if ($script:K8sContext) { $script:K8sContext } else { '<current>' })"
        "# Namespace:       $($script:K8sNamespace)"
        "# Workload:        $Target ($Want)"
        "# Window:          last $($script:LogSince)"
        "# --------------------------------------------------------------"
    )
    $header | Set-Content -Path $outfile -Encoding UTF8

    $logs = & kubectl @base logs @sel "--since=$($script:LogSince)" --all-containers --prefix '--tail=-1' 2>&1
    $logs | Add-Content -Path $outfile -Encoding UTF8
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Saved current logs to $outfile"
    }
    else {
        Write-Warning "kubectl logs returned an error (see the end of $outfile)."
    }

    if ($script:K8sIncludePrevious) {
        @("", "# ---- previous (crashed/restarted) pod logs ----") | Add-Content -Path $outfile -Encoding UTF8
        $prevLogs = & kubectl @base logs @sel --previous --all-containers --prefix '--tail=-1' 2>&1
        $prevLogs | Add-Content -Path $outfile -Encoding UTF8
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Appended previous-pod logs to $outfile"
        }
        else {
            Write-Info "No previous-pod logs available (workload has not restarted)."
        }
    }
}

# Download logs for the selected container(s): orchestrator | admin | both.
function Download-ContainerLogs {
    param([string]$Selection)
    $wants = if ($Selection -eq 'both') { @('orchestrator', 'admin') } else { @($Selection) }

    foreach ($want in $wants) {
        $found = $false
        switch ($script:CloudPlatform) {
            'aws' {
                for ($i = 0; $i -lt $script:AWSTaskDefinitions.Count; $i++) {
                    $role = if ($i -lt $script:AWSTaskRoles.Count) { $script:AWSTaskRoles[$i] } else { 'both' }
                    if ($role -eq 'both' -or $role -eq $want) {
                        Download-EcsLogsFromTaskDef -TaskDef $script:AWSTaskDefinitions[$i] -Want $want
                        $found = $true
                        break
                    }
                }
                if (-not $found) { Write-Warning "Could not locate a task definition hosting the $want container." }
            }
            'azure' {
                for ($i = 0; $i -lt $script:AzureContainerApps.Count; $i++) {
                    $role = if ($i -lt $script:AzureAppRoles.Count) { $script:AzureAppRoles[$i] } else { 'both' }
                    if ($role -eq 'both' -or $role -eq $want) {
                        $app = $script:AzureContainerApps[$i]
                        $cname = Get-AcaContainerName -App $app -Want $want
                        if (-not $cname) { $cname = $want }
                        Download-AcaLogs -App $app -Container $cname -Want $want
                        $found = $true
                        break
                    }
                }
                if (-not $found) { Write-Warning "Could not locate a Container App hosting the $want container." }
            }
            'compose' {
                for ($i = 0; $i -lt $script:ComposeServices.Count; $i++) {
                    $role = if ($i -lt $script:ComposeServiceRoles.Count) { $script:ComposeServiceRoles[$i] } else { 'both' }
                    if ($role -eq 'both' -or $role -eq $want) {
                        Download-ComposeLogs -Service $script:ComposeServices[$i] -Want $want
                        $found = $true
                        break
                    }
                }
                if (-not $found) { Write-Warning "Could not locate a compose service hosting the $want container." }
            }
            'k8s' {
                for ($i = 0; $i -lt $script:K8sWorkloads.Count; $i++) {
                    $role = if ($i -lt $script:K8sWorkloadRoles.Count) { $script:K8sWorkloadRoles[$i] } else { 'both' }
                    if ($role -eq 'both' -or $role -eq $want) {
                        Download-K8sLogs -Target $script:K8sWorkloads[$i] -Want $want
                        $found = $true
                        break
                    }
                }
                if (-not $found) { Write-Warning "Could not locate a Kubernetes workload hosting the $want container." }
            }
        }
    }
}

# Collect logs for the selection into a staging dir, then zip them into a single
# "Spotfire Copilot Troubleshooting Bundle <timestamp>.zip".
function Bundle-ContainerLogs {
    param([string]$Selection)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("sc-troubleshooting-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    $script:LogOutputDir = $staging
    Download-ContainerLogs -Selection $Selection
    $script:LogOutputDir = "."

    $manifest = @(
        "Spotfire Copilot Troubleshooting Bundle"
        "Generated:   $(Get-Date)"
        "Platform:    $($script:CloudPlatform)"
        "Selection:   $Selection"
        "Log window:  $($script:LogSince)"
        "Tool:        spotfire-copilot-troubleshooting-bundle.ps1"
    )
    $manifest | Set-Content -Path (Join-Path $staging "manifest.txt") -Encoding UTF8

    $logFiles = Get-ChildItem -Path $staging -Filter "container-logs-*.log" -ErrorAction SilentlyContinue
    if (-not $logFiles) {
        Write-Warning "No log files were collected - skipping bundle creation."
        Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
        return
    }

    $bundle = Join-Path (Get-Location).Path "Spotfire Copilot Troubleshooting Bundle $ts.zip"
    try {
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $bundle -Force
    }
    catch {
        Write-Warning "Compress-Archive reported an error: $_"
    }
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue

    if (Test-Path $bundle) {
        Write-Host ""
        Write-Success "Bundle saved: $bundle"
        Write-Info "Attach this file to your Spotfire support case."
    }
    else {
        Write-Error "Failed to create the troubleshooting bundle."
    }
}

# End-of-run offer to grab logs for troubleshooting.
function Invoke-LogDownloadOffer {
    Write-Host ""
    $dl = Read-Host "Download container logs for troubleshooting? (y/n)"
    if ($dl -match '^(?i)y') {
        $sel = Prompt-LogTarget
        Bundle-ContainerLogs -Selection $sel
    }
}

##############################################################################
# Main Flow
##############################################################################

function Main {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Spotfire Copilot Troubleshooting Bundle" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan

    if ($Logs) {
        Write-Info "Log download mode (-Logs): validation will be skipped."
        if (Test-Path $script:AnswersFile) {
            Write-Info "Using saved answers: $($script:AnswersFile)"
            Load-Answers
            Preflight-CheckCli
        }
        else {
            Write-Info "No saved answers found; let's identify your deployment first."
            Phase1-DetectPlatform
        }
        $sel = Prompt-LogTarget
        Bundle-ContainerLogs -Selection $sel
        exit 0
    }

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
    }

    # Docker Compose and Kubernetes: collect logs into a bundle (no env-var validation).
    if ($script:CloudPlatform -eq "compose" -or $script:CloudPlatform -eq "k8s") {
        if (-not $script:Resumed) { Save-Answers }
        Write-Host ""
        Write-Info "Log collection mode for '$($script:CloudPlatform)' - env-variable validation is not applicable to this platform."
        $sel = Prompt-LogTarget
        Bundle-ContainerLogs -Selection $sel
        exit 0
    }

    if (-not $script:Resumed) {
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

    # Offer to download container logs for troubleshooting
    Invoke-LogDownloadOffer
    
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
