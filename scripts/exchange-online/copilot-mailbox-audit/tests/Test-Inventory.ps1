#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$inventoryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Get-CopilotUsersWithoutCloudMailbox.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $inventoryPath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw ($parseErrors | Out-String)
}

$fixtures = @{
    SkuId = [guid]'11111111-1111-1111-1111-111111111111'
    MailboxGuid = [guid]'22222222-2222-2222-2222-222222222222'
    GraphContext = $null
    ExchangeConnections = @()
    Skus = @()
    Users = @()
    CloudMailboxes = @()
    MailUsers = @()
    CloudFailure = $false
}
$script:Passed = 0

function Reset-Fixtures {
    $fixtures.GraphContext = [pscustomobject]@{ TenantId = 'synthetic-tenant' }
    $fixtures.ExchangeConnections = @(
        [pscustomobject]@{ State = 'Connected'; TenantID = 'synthetic-tenant' }
    )
    $fixtures.Skus = @(
        [pscustomobject]@{
            SkuId = $fixtures.SkuId
            SkuPartNumber = 'Microsoft_365_Copilot'
            ServicePlans = @()
        }
    )
    $fixtures.Users = @(
        foreach ($name in @('cloud-id', 'cloud-upn', 'likely', 'empty-guid', 'unknown', 'not-synced', 'disabled')) {
            [pscustomobject]@{
                Id = $name
                DisplayName = $name
                UserPrincipalName = "$name@example.test"
                Mail = "$name@example.test"
                AccountEnabled = $name -ne 'disabled'
                OnPremisesSyncEnabled = $name -ne 'not-synced'
                AssignedLicenses = @([pscustomobject]@{ SkuId = $fixtures.SkuId })
            }
        }
    )
    $fixtures.CloudMailboxes = @(
        [pscustomobject]@{
            ExternalDirectoryObjectId = 'cloud-id'
            UserPrincipalName = 'different-upn@example.test'
        }
        [pscustomobject]@{
            ExternalDirectoryObjectId = $null
            UserPrincipalName = 'CLOUD-UPN@example.test'
        }
    )
    $fixtures.MailUsers = @(
        foreach ($name in @('likely', 'empty-guid', 'not-synced', 'disabled')) {
            [pscustomobject]@{
                ExternalDirectoryObjectId = $name
                IsDirSynced = $name -ne 'not-synced'
                ExchangeGuid = $(if ($name -eq 'empty-guid') {
                    [guid]::Empty
                } else {
                    $fixtures.MailboxGuid
                })
            }
        }
    )
    $fixtures.CloudFailure = $false
}

# Local functions shadow service cmdlets: no modules, authentication or tenant access.
function Connect-MgGraph { throw 'Unexpected Microsoft Graph authentication attempt.' }
function Connect-ExchangeOnline { throw 'Unexpected Exchange Online authentication attempt.' }
function Get-MgContext { $fixtures.GraphContext }
function Get-ConnectionInformation { $fixtures.ExchangeConnections }
function Get-MgSubscribedSku {
    param([switch]$All)
    if (-not $All) { throw 'SKU query must retrieve all pages.' }
    $fixtures.Skus
}
function Get-MgUser {
    param($Filter, $Property, $ConsistencyLevel, $CountVariable, [switch]$All)
    if (-not $All -or $ConsistencyLevel -ne 'eventual' -or
        $Filter -notmatch [string]$fixtures.SkuId) {
        throw 'User query must include license filtering, pagination and eventual consistency.'
    }
    $fixtures.Users
}
function Get-EXOMailbox {
    param($ResultSize, $Properties)
    if ($fixtures.CloudFailure) { throw 'Synthetic recipient access denied.' }
    if ($ResultSize -ne 'Unlimited' -or 'ExternalDirectoryObjectId' -notin $Properties) {
        throw 'Mailbox query must retrieve all recipients and directory IDs.'
    }
    $fixtures.CloudMailboxes
}
function Get-MailUser {
    param($ResultSize)
    if ($ResultSize -ne 'Unlimited') { throw 'MailUser query must retrieve all recipients.' }
    $fixtures.MailUsers
}

function Assert-Scenario {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
    Write-Host "PASS: $Name"
}

function Assert-ExpectedError {
    param([scriptblock]$Action, [string]$MessagePattern, [string]$Name)
    $matched = $false
    try {
        & $Action | Out-Null
    } catch {
        if ($_.Exception.Message -notlike $MessagePattern) {
            throw
        }
        $matched = $true
    }
    Assert-Scenario -Condition $matched -Name $Name
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('copilot-mailbox-tests-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($temporaryDirectory)
try {
    $helpText = Get-Help $inventoryPath -Full | Out-String -Width 200
    Assert-Scenario ($helpText -match 'DISCLAIMER:' -and
        $helpText -match 'Copyright \(c\) 2026 Nuno Costa') 'Expose the embedded disclaimer through comment-based help'
    Reset-Fixtures
    $results = @(& $inventoryPath -UseExistingConnections -WarningAction SilentlyContinue)
    Assert-Scenario ($results.Count -eq 5) 'Exclude active cloud mailboxes by object ID and case-insensitive UPN'
    Assert-Scenario (@($results | Where-Object MailboxStatus -eq 'OnPremisesLikely').Count -eq 2) 'Classify synchronized MailUsers with mailbox GUID as likely'
    Assert-Scenario (@($results | Where-Object MailboxStatus -eq 'NoCloudMailboxUnconfirmed').Count -eq 3) 'Keep empty GUID, missing recipient and unsynchronized MailUser unconfirmed'
    Assert-Scenario (($results | Where-Object DisplayName -eq 'disabled').AccountEnabled -eq $false) 'Include disabled licensed accounts'
    Assert-Scenario (@($results | Where-Object MailboxStatus -eq 'OnPremisesConfirmed').Count -eq 0) 'Never claim on-premises confirmation without a local session'
    Assert-Scenario (($results | Where-Object DisplayName -eq 'likely').CopilotLicenses -eq 'Microsoft_365_Copilot') 'Preserve assigned SKU names'
    $fieldNames = @($results[0].PSObject.Properties.Name)
    Assert-Scenario (($fieldNames -join ',') -eq 'DisplayName,UserPrincipalName,Mail,AccountEnabled,OnPremisesSyncEnabled,CopilotLicenses,MailboxStatus,ExchangeGuid,EntraObjectId') 'Return the documented nine-column object shape'

    $filtered = @(& $inventoryPath -UseExistingConnections -OnlyOnPremises -WarningAction SilentlyContinue)
    Assert-Scenario ($filtered.Count -eq 2) 'OnlyOnPremises excludes unconfirmed users'

    $explicit = @(& $inventoryPath -UseExistingConnections -CopilotSkuId $fixtures.SkuId -WarningAction SilentlyContinue)
    Assert-Scenario ($explicit.Count -eq 5) 'Accept an explicit tenant SKU ID'
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections -CopilotSkuId '33333333-3333-3333-3333-333333333333'
    } 'SKU IDs not found*' 'Reject unknown SKU IDs'

    $fixtures.Skus[0].SkuPartNumber = 'Alternative-Sku-Name'
    $fixtures.Skus[0].ServicePlans = @([pscustomobject]@{ ServicePlanName = 'M365_COPILOT' })
    $byPlan = @(& $inventoryPath -UseExistingConnections -WarningAction SilentlyContinue)
    Assert-Scenario ($byPlan.Count -eq 5) 'Detect Copilot by service plan when the SKU name differs'
    $fixtures.Skus[0].ServicePlans = @([pscustomobject]@{ ServicePlanName = 'COPILOT_STUDIO' })
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections
    } 'No Microsoft 365 Copilot SKU detected*' 'Do not auto-select unrelated Copilot products'

    Reset-Fixtures
    $fixtures.GraphContext = $null
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections
    } 'No Microsoft Graph connection*' 'Reject a missing Graph connection'

    Reset-Fixtures
    $fixtures.ExchangeConnections[0].TenantID = 'different-tenant'
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections
    } 'Use exactly one active Exchange Online connection*' 'Reject a Graph/Exchange tenant mismatch'

    Reset-Fixtures
    $fixtures.ExchangeConnections += $fixtures.ExchangeConnections[0]
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections
    } 'Use exactly one active Exchange Online connection*' 'Reject multiple active Exchange connections'

    Reset-Fixtures
    $fixtures.ExchangeConnections = @()
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections
    } 'Use exactly one active Exchange Online connection*' 'Reject a missing Exchange connection'

    Reset-Fixtures
    $fixtures.CloudFailure = $true
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections
    } 'Synthetic recipient access denied*' 'Propagate service errors instead of treating failures as empty inventories'

    Reset-Fixtures
    $csvPath = Join-Path $temporaryDirectory 'synthetic-results.csv'
    $exported = @(& $inventoryPath -UseExistingConnections -OutputPath $csvPath -WarningAction SilentlyContinue)
    $csvRows = @(Import-Csv -LiteralPath $csvPath)
    Assert-Scenario ($csvRows.Count -eq 5 -and $exported.Count -eq 5) 'Export all rows while preserving pipeline objects'
    $originalHash = (Get-FileHash -LiteralPath $csvPath -Algorithm SHA256).Hash
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections -OutputPath $csvPath
    } 'OutputPath already exists*' 'Refuse to overwrite an existing export'
    Assert-Scenario ((Get-FileHash -LiteralPath $csvPath -Algorithm SHA256).Hash -eq $originalHash) 'Leave an existing export unchanged'

    $missingDirectoryPath = Join-Path (Join-Path $temporaryDirectory 'missing') 'results.csv'
    Assert-ExpectedError {
        & $inventoryPath -UseExistingConnections -OutputPath $missingDirectoryPath
    } 'Output directory does not exist*' 'Reject a nonexistent output directory'

    $fixtures.Users = @()
    $emptyCsvPath = Join-Path $temporaryDirectory 'empty.csv'
    $emptyResults = @(& $inventoryPath -UseExistingConnections -OutputPath $emptyCsvPath -WarningAction SilentlyContinue)
    Assert-Scenario ($emptyResults.Count -eq 0 -and -not (Test-Path -LiteralPath $emptyCsvPath)) 'Return no users and create no CSV for an empty result'

    Write-Host "$($script:Passed) scenarios passed on PowerShell $($PSVersionTable.PSVersion)."
} finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
}
