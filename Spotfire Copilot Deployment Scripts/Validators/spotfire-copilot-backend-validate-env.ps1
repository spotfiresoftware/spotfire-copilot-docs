#############################################################################
#  Spotfire Copilot — Backend Environment Validation Script
#  Version: 2.3.x
#
#  Purpose: Validates environment variables for Orchestrator and Admin Console
#           deployed on AWS ECS/Fargate or Azure Container Apps
# 
#  Usage:
#    .\spotfire-copilot-backend-validate-env.ps1
#
#  Supports:
#    - AWS ECS/Fargate (single or multiple task definitions)
#    - Azure Container Apps (single or multiple apps)
#    - Template-based validation or interactive schema builder
#    - No-CLI fallback (manual JSON import)
#############################################################################

param()

$ErrorActionPreference = "Stop"

# Global variables
$CloudPlatform = ""
$AWSRegion = ""
$AWSCluster = ""
$AWSTaskDefinitions = @()
$AzureResourceGroup = ""
$AzureLocation = ""
$AzureContainerApps = @()
$HasTemplate = $false
$TemplateFile = ""
$LLMProvider = ""
$HasAdminConsole = $false
$OrchestratorVars = @()
$AdminConsoleVars = @()
$ReportFile = ""
$ValidationErrors = 0
$ValidationWarnings = 0

##############################################################################
# Utility Functions
##############################################################################

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[⚠] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
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
# Phase 1: Platform & Topology Detection
##############################################################################

function Phase1-DetectPlatform {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Spotfire Copilot Environment Validator" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
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
            Phase1-DetectAWSTopology
        }
        2 {
            $script:CloudPlatform = "azure"
            Phase1-DetectAzureTopology
        }
    }
}

function Phase1-DetectAWSTopology {
    Write-Host ""
    $script:AWSRegion = Read-Host "Enter AWS region (e.g., us-east-1)"
    $script:AWSCluster = Read-Host "Enter ECS cluster name"
    
    Write-Host ""
    Write-Host "How are your services deployed?"
    Write-Host "  1) All in one task definition"
    Write-Host "  2) Separate task definitions (orchestrator + admin-console)"
    Write-Host ""
    
    $topologyChoice = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2
    
    switch ($topologyChoice) {
        1 {
            $taskDef = Read-Host "Enter task definition name (e.g., spotfire-copilot-services)"
            $script:AWSTaskDefinitions = @($taskDef)
            Write-Info "Task definition: $taskDef (will validate both orchestrator and admin-console containers)"
        }
        2 {
            $taskOrch = Read-Host "Enter Orchestrator task definition name"
            $taskAdmin = Read-Host "Enter Admin Console task definition name"
            $script:AWSTaskDefinitions = @($taskOrch, $taskAdmin)
            Write-Info "Task definitions: $taskOrch, $taskAdmin"
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
            Write-Info "Container App: $appName (will validate both services)"
        }
        2 {
            $appOrch = Read-Host "Enter Orchestrator Container App name"
            $appAdmin = Read-Host "Enter Admin Console Container App name"
            $script:AzureContainerApps = @($appOrch, $appAdmin)
            Write-Info "Container Apps: $appOrch, $appAdmin"
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
    Write-Host "Do you have a configuration template from our deploy script?"
    Write-Host "  1) Yes, I have cloud-env-checklist.txt or spotfire-copilot-config.json"
    Write-Host "  2) No, build schema interactively"
    Write-Host ""
    
    $templateChoice = Read-Choice -Prompt "Enter choice (1 or 2)" -MaxChoice 2
    
    switch ($templateChoice) {
        1 {
            Phase2-LoadTemplate
        }
        2 {
            Phase2-BuildSchemaInteractive
        }
    }
}

function Phase2-LoadTemplate {
    Write-Host ""
    $templatePath = Read-Host "Enter path to template file"
    
    if (-not (Test-Path $templatePath)) {
        Write-Error "Template file not found: $templatePath"
        Write-Host ""
        Write-Info "Falling back to interactive schema builder..."
        Phase2-BuildSchemaInteractive
        return
    }
    
    $script:HasTemplate = $true
    $script:TemplateFile = $templatePath
    Write-Success "Template loaded: $script:TemplateFile"
    
    # Parse template to detect LLM provider and admin console
    $templateContent = Get-Content $templatePath -Raw
    
    if ($templateContent -match "AZURE_OPENAI_ENDPOINT") {
        $script:LLMProvider = "azure_openai"
    }
    elseif ($templateContent -match "OPENAI_API_KEY") {
        $script:LLMProvider = "openai"
    }
    elseif ($templateContent -match "AWS_BEDROCK") {
        $script:LLMProvider = "aws_bedrock"
    }
    elseif ($templateContent -match "VERTEX_AI") {
        $script:LLMProvider = "vertex_ai"
    }
    elseif ($templateContent -match "GOOGLE_API_KEY") {
        $script:LLMProvider = "gemini"
    }
    elseif ($templateContent -match "NVIDIA_API_KEY") {
        $script:LLMProvider = "nvidia_nim"
    }
    elseif ($templateContent -match "OLLAMA") {
        $script:LLMProvider = "ollama"
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
        "DB_SSLMODE"
    )
    
    # Add LLM-specific vars
    switch ($script:LLMProvider) {
        "azure_openai" {
            $script:OrchestratorVars += @(
                "AZURE_OPENAI_ENDPOINT",
                "OPENAI_API_KEY",
                "OPENAI_API_VERSION"
            )
        }
        "openai" {
            $script:OrchestratorVars += "OPENAI_API_KEY"
        }
        "aws_bedrock" {
            $script:OrchestratorVars += @(
                "AWS_REGION",
                "MODEL_NAME"
            )
        }
        "vertex_ai" {
            $script:OrchestratorVars += @(
                "GOOGLE_PROJECT_ID",
                "GOOGLE_REGION"
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
            $script:OrchestratorVars += @(
                "OLLAMA_BASE_URL",
                "OLLAMA_MODEL"
            )
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
# AWS ECS Validation
##############################################################################

function Validate-AWSECS {
    Write-Info "Validating AWS ECS environment..."
    Write-Host ""
    
    # Check if AWS CLI is installed
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Error "AWS CLI not found. Please install it or use manual import option."
        Write-Host ""
        Write-Host "Option 1: Install AWS CLI"
        Write-Host "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        Write-Host ""
        Write-Host "Option 2: Export from CloudShell and validate locally"
        Write-Host "  aws ecs describe-task-definition --cluster $AWSCluster --task-definition TASK_NAME --query taskDefinition.containerDefinitions[0].[environment,secrets] > export.json"
        Write-Host "  Then re-run with: .\spotfire-copilot-validate.ps1 -Import export.json"
        exit 1
    }
    
    # Validate each task definition
    foreach ($taskDef in $script:AWSTaskDefinitions) {
        Validate-AWSTaskDefinition $taskDef
    }
}

function Validate-AWSTaskDefinition {
    param([string]$TaskDef)
    
    Write-Info "Fetching task definition: $TaskDef"
    
    try {
        $taskJson = aws ecs describe-task-definition `
            --cluster $script:AWSCluster `
            --task-definition $TaskDef `
            --region $script:AWSRegion `
            --query 'taskDefinition.containerDefinitions' `
            --output json | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to fetch task definition: $TaskDef"
        return
    }
    
    # Validate each container
    foreach ($container in $taskJson) {
        if ($container.name -match "orchestrator|admin") {
            Validate-ContainerEnv -ContainerName $container.name -Container $container
        }
    }
}

function Validate-ContainerEnv {
    param(
        [string]$ContainerName,
        [object]$Container
    )
    
    Write-Host ""
    Write-Info "Validating container: $ContainerName"
    
    $envVarNames = @()
    if ($Container.environment) {
        $envVarNames = $Container.environment | ForEach-Object { $_.name }
    }
    
    $secretNames = @()
    if ($Container.secrets) {
        $secretNames = $Container.secrets | ForEach-Object { $_.name }
    }
    
    # Determine which schema to use
    $varsToCheck = if ($ContainerName -match "admin") {
        $script:AdminConsoleVars
    }
    else {
        $script:OrchestratorVars
    }
    
    # Check required vars
    foreach ($var in $varsToCheck) {
        if ($var -in $envVarNames) {
            Write-Success "$var — present"
        }
        elseif ($var -in $secretNames) {
            Write-Success "$var — present (secret ref)"
        }
        else {
            Write-Error "$var — MISSING [REQUIRED]"
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
            if ($script:LLMProvider -ne "openai" -and $var -eq "OPENAI_API_KEY") {
                Write-Warning "$var — orphaned (you're using $($script:LLMProvider), not OpenAI)"
                $script:ValidationWarnings++
            }
            elseif ($script:LLMProvider -ne "azure_openai" -and $var -eq "AZURE_OPENAI_ENDPOINT") {
                Write-Warning "$var — orphaned (you're using $($script:LLMProvider), not Azure OpenAI)"
                $script:ValidationWarnings++
            }
        }
    }
}

##############################################################################
# Azure Container Apps Validation
##############################################################################

function Validate-AzureACA {
    Write-Info "Validating Azure Container Apps environment..."
    Write-Host ""
    
    # Check if Azure CLI is installed
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI not found. Please install it or use manual import option."
        Write-Host ""
        Write-Host "Option 1: Install Azure CLI"
        Write-Host "  https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        Write-Host ""
        Write-Host "Option 2: Export from Azure Portal and validate locally"
        Write-Host "  az containerapp show --resource-group $AzureResourceGroup --name APP_NAME --output json > export.json"
        Write-Host "  Then re-run with: .\spotfire-copilot-validate.ps1 -Import export.json"
        exit 1
    }
    
    # Validate each container app
    foreach ($appName in $script:AzureContainerApps) {
        Validate-AzureContainerApp $appName
    }
}

function Validate-AzureContainerApp {
    param([string]$AppName)
    
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
    
    # Validate each container
    foreach ($container in $appJson.properties.template.containers) {
        if ($container.name -match "orchestrator|admin") {
            Validate-ACAContainerEnv -AppName $AppName -ContainerName $container.name -Container $container
        }
    }
}

function Validate-ACAContainerEnv {
    param(
        [string]$AppName,
        [string]$ContainerName,
        [object]$Container
    )
    
    Write-Host ""
    Write-Info "Validating Container App: $AppName, Container: $ContainerName"
    
    $envVarNames = @()
    if ($Container.env) {
        $envVarNames = $Container.env | ForEach-Object { $_.name }
    }
    
    # Determine which schema to use
    $varsToCheck = if ($ContainerName -match "admin") {
        $script:AdminConsoleVars
    }
    else {
        $script:OrchestratorVars
    }
    
    # Check required vars
    foreach ($var in $varsToCheck) {
        if ($var -in $envVarNames) {
            Write-Success "$var — present"
        }
        else {
            Write-Error "$var — MISSING [REQUIRED]"
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
            if ($script:LLMProvider -ne "openai" -and $var -eq "OPENAI_API_KEY") {
                Write-Warning "$var — orphaned (you're using $($script:LLMProvider), not OpenAI)"
                $script:ValidationWarnings++
            }
            elseif ($script:LLMProvider -ne "azure_openai" -and $var -eq "AZURE_OPENAI_ENDPOINT") {
                Write-Warning "$var — orphaned (you're using $($script:LLMProvider), not Azure OpenAI)"
                $script:ValidationWarnings++
            }
        }
    }
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
"Region: $($script:AWSRegion)
Cluster: $($script:AWSCluster)
Task Definitions: $($script:AWSTaskDefinitions -join ', ')"
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

Status: $(if ($script:ValidationErrors -eq 0) { '✓ VALIDATION PASSED' } else { '✗ VALIDATION FAILED' })

========================================================================
"@
    
    $reportContent | Out-File -FilePath $script:ReportFile -Encoding UTF8
    Write-Success "Report written to: $script:ReportFile"
}

##############################################################################
# Main Flow
##############################################################################

function Main {
    Phase1-DetectPlatform
    Phase2-TemplateOrSchema
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
