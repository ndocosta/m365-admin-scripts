#requires -Version 5.1

<#
.SYNOPSIS
Lists users licensed for Microsoft 365 Copilot without an active Exchange Online mailbox.

.DESCRIPTION
Read-only inventory using Microsoft Graph and Exchange Online.
Includes disabled accounts and all pages of licensed users.

OnPremisesConfirmed: a matching mailbox was found using OnPremisesSession.
OnPremisesLikely: a synchronized Exchange Online MailUser with a non-empty
ExchangeGuid exists, but the on-premises mailbox has not been verified.
NoCloudMailboxUnconfirmed: no active cloud mailbox exists; location is unknown.
This last category can include provisioning delays or users without any mailbox.
Soft-deleted and inactive cloud mailboxes do not count as active mailboxes.

Requires Microsoft.Graph.Authentication, Microsoft.Graph.Users,
Microsoft.Graph.Identity.DirectoryManagement, and ExchangeOnlineManagement 3+.
Graph delegated permissions: User.Read.All and LicenseAssignment.Read.All
(admin consent may be required). Exchange requires read access to all recipients.
An optional existing on-premises Exchange PSSession needs permission to run
Get-Mailbox across the organization. Restricted RBAC scope produces partial results.

.NOTES
Copyright (c) 2026 Nuno Costa.
Licensed under the MIT License. See LICENSE at the repository root.

DISCLAIMER: This community utility is provided "AS IS", without warranty of
any kind. It is not an official Microsoft product and is not supported or
endorsed by Microsoft. Use only in environments you are authorized to
administer. Review the code, permissions, and results, and follow your
organization's policies before use. Use at your own risk.
The MIT License contains the applicable warranty disclaimer and limitation
of liability.

.PARAMETER OutputPath
Optional CSV destination. An existing file is NOT overwritten.

.PARAMETER CopilotSkuId
Explicit tenant SKU IDs. When omitted, detects Microsoft_365_Copilot and
M365_COPILOT SKU names, or SKUs containing the M365_COPILOT service plan.
Copilot Chat without a paid license and Copilot Studio are not included.

.PARAMETER OnPremisesSession
Existing Exchange Server remote PowerShell session. Enables positive
confirmation of on-premises mailboxes, rather than relying on hybrid metadata.

.PARAMETER OnlyOnPremises
Returns only confirmed or likely on-premises users. Unconfirmed users are
excluded with a warning. Without OnPremisesSession, results remain inferred.

.PARAMETER UseExistingConnections
Uses existing Graph and Exchange Online connections without opening sign-in.

.EXAMPLE
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement, ExchangeOnlineManagement -Scope CurrentUser
.\Get-CopilotUsersWithoutCloudMailbox.ps1 -OutputPath .\Copilot-NoCloudMailbox.csv

.EXAMPLE
# Create $exchangeSession using your organization's approved Exchange Server
# connection procedure, then pass that existing PSSession:
.\Get-CopilotUsersWithoutCloudMailbox.ps1 -OnPremisesSession $exchangeSession -OnlyOnPremises

.EXAMPLE
.\Get-CopilotUsersWithoutCloudMailbox.ps1 -UseExistingConnections |
    Format-Table DisplayName, UserPrincipalName, MailboxStatus -AutoSize
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [guid[]]$CopilotSkuId,
    [System.Management.Automation.Runspaces.PSSession]$OnPremisesSession,
    [switch]$OnlyOnPremises,
    [switch]$UseExistingConnections
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($OutputPath) {
    if (Test-Path -LiteralPath $OutputPath) {
        throw "OutputPath already exists: $OutputPath. Choose a new file to avoid overwriting data."
    }
    $outputDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        throw "Output directory does not exist: $outputDirectory"
    }
}
if ($OnPremisesSession -and $OnPremisesSession.State -ne 'Opened') {
    throw 'OnPremisesSession must be an open Exchange Server PowerShell session.'
}

$dependencies = @(
    @{ Command = 'Connect-MgGraph'; Module = 'Microsoft.Graph.Authentication' }
    @{ Command = 'Get-MgUser'; Module = 'Microsoft.Graph.Users' }
    @{ Command = 'Get-MgSubscribedSku'; Module = 'Microsoft.Graph.Identity.DirectoryManagement' }
    @{ Command = 'Connect-ExchangeOnline'; Module = 'ExchangeOnlineManagement' }
)
foreach ($dependency in $dependencies) {
    if (-not (Get-Command $dependency.Command -ErrorAction SilentlyContinue)) {
        Import-Module $dependency.Module -ErrorAction Stop
    }
}

if (-not $UseExistingConnections) {
    Connect-MgGraph -Scopes 'User.Read.All', 'LicenseAssignment.Read.All' -NoWelcome
    Connect-ExchangeOnline -ShowBanner:$false
}
$graphContext = Get-MgContext
if (-not $graphContext -or -not $graphContext.TenantId) {
    throw 'No Microsoft Graph connection. Run Connect-MgGraph first.'
}
$exchangeConnections = @(Get-ConnectionInformation | Where-Object {
    $_.State -eq 'Connected'
})
if ($exchangeConnections.Count -ne 1 -or
    [string]$exchangeConnections[0].TenantID -ne [string]$graphContext.TenantId) {
    throw 'Use exactly one active Exchange Online connection, in the same tenant as Microsoft Graph.'
}

Write-Verbose 'Resolving Copilot licenses in the connected tenant.'
$subscribedSkus = @(Get-MgSubscribedSku -All)
if ($CopilotSkuId) {
    $copilotSkus = @($subscribedSkus | Where-Object {
        [guid]$_.SkuId -in $CopilotSkuId
    })
    $missingIds = @($CopilotSkuId | Where-Object {
        $_ -notin @($copilotSkus | ForEach-Object { [guid]$_.SkuId })
    })
    if ($missingIds.Count -gt 0) {
        throw "SKU IDs not found in this tenant: $($missingIds -join ', ')"
    }
} else {
    $copilotSkus = @($subscribedSkus | Where-Object {
        $_.SkuPartNumber -in @('Microsoft_365_Copilot', 'M365_COPILOT') -or
        'M365_COPILOT' -in @($_.ServicePlans | ForEach-Object { $_.ServicePlanName })
    })
}
if ($copilotSkus.Count -eq 0) {
    throw 'No Microsoft 365 Copilot SKU detected. Inspect Get-MgSubscribedSku and supply -CopilotSkuId if your SKU uses a different name.'
}
$skuNames = @{}
foreach ($sku in $copilotSkus) {
    $skuNames[[string]$sku.SkuId] = $sku.SkuPartNumber
}
$licenseFilter = ($copilotSkus | ForEach-Object {
    "assignedLicenses/any(x:x/skuId eq $($_.SkuId))"
}) -join ' or '
$licensedUsers = @(Get-MgUser -All -Filter "($licenseFilter)" `
    -ConsistencyLevel eventual -CountVariable licensedUserCount `
    -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled, OnPremisesSyncEnabled, AssignedLicenses)

Write-Verbose "Found $($licensedUsers.Count) licensed users. Reading active cloud mailboxes."
$cloudMailboxIds = @{}
$cloudMailboxUpns = @{}
Get-EXOMailbox -ResultSize Unlimited -Properties ExternalDirectoryObjectId, UserPrincipalName |
    ForEach-Object {
        if ($_.ExternalDirectoryObjectId) {
            $cloudMailboxIds[[string]$_.ExternalDirectoryObjectId] = $true
        }
        if ($_.UserPrincipalName) {
            $cloudMailboxUpns[[string]$_.UserPrincipalName] = $true
        }
    }

$mailUsersById = @{}
Get-MailUser -ResultSize Unlimited | ForEach-Object {
    if ($_.ExternalDirectoryObjectId) {
        $mailUsersById[[string]$_.ExternalDirectoryObjectId] = $_
    }
}

$onPremisesAddresses = @{}
$onPremisesGuids = @{}
if ($OnPremisesSession) {
    Write-Verbose 'Reading actual mailboxes from the supplied Exchange Server session.'
    $onPremisesMailboxes = @(Invoke-Command -Session $OnPremisesSession -ScriptBlock {
        Get-Mailbox -ResultSize Unlimited |
            Select-Object UserPrincipalName, PrimarySmtpAddress, ExchangeGuid, EmailAddresses
    })
    foreach ($mailbox in $onPremisesMailboxes) {
        foreach ($address in @($mailbox.UserPrincipalName, [string]$mailbox.PrimarySmtpAddress)) {
            if ($address) { $onPremisesAddresses[[string]$address] = $true }
        }
        foreach ($proxy in $mailbox.EmailAddresses) {
            if ([string]$proxy -match '^smtp:(.+)$') {
                $onPremisesAddresses[$Matches[1]] = $true
            }
        }
        if ($mailbox.ExchangeGuid -and [guid]$mailbox.ExchangeGuid -ne [guid]::Empty) {
            $onPremisesGuids[[string]([guid]$mailbox.ExchangeGuid)] = $true
        }
    }
} else {
    Write-Warning 'Without -OnPremisesSession, on-premises location is inferred, not confirmed. A missing cloud mailbox alone does not prove an on-premises mailbox exists.'
}

$results = @(
    foreach ($user in $licensedUsers) {
        if ($cloudMailboxIds.ContainsKey([string]$user.Id) -or
            ($user.UserPrincipalName -and $cloudMailboxUpns.ContainsKey([string]$user.UserPrincipalName))) {
            continue
        }
        $mailUser = $mailUsersById[[string]$user.Id]
        $exchangeGuid = $null
        if ($mailUser -and $mailUser.ExchangeGuid -and
            [guid]$mailUser.ExchangeGuid -ne [guid]::Empty) {
            $exchangeGuid = [string]([guid]$mailUser.ExchangeGuid)
        }
        $confirmed = $false
        if ($OnPremisesSession) {
            # Prefer the immutable mailbox GUID when hybrid metadata provides it.
            if ($exchangeGuid) {
                $confirmed = $onPremisesGuids.ContainsKey($exchangeGuid)
            } else {
                $confirmed = ($user.UserPrincipalName -and
                    $onPremisesAddresses.ContainsKey([string]$user.UserPrincipalName)) -or
                    ($user.Mail -and $onPremisesAddresses.ContainsKey([string]$user.Mail))
            }
        }
        $status = 'NoCloudMailboxUnconfirmed'
        if ($confirmed) {
            $status = 'OnPremisesConfirmed'
        } elseif (-not $OnPremisesSession -and $mailUser -and
            $mailUser.IsDirSynced -eq $true -and $exchangeGuid) {
            $status = 'OnPremisesLikely'
        }
        $userSkuNames = @(
            foreach ($license in $user.AssignedLicenses) {
                if ($skuNames.ContainsKey([string]$license.SkuId)) {
                    $skuNames[[string]$license.SkuId]
                }
            }
        )
        [pscustomobject]@{
            DisplayName             = $user.DisplayName
            UserPrincipalName       = $user.UserPrincipalName
            Mail                    = $user.Mail
            AccountEnabled          = $user.AccountEnabled
            OnPremisesSyncEnabled   = $user.OnPremisesSyncEnabled
            CopilotLicenses          = $userSkuNames -join '; '
            MailboxStatus           = $status
            ExchangeGuid            = $exchangeGuid
            EntraObjectId           = $user.Id
        }
    }
)
$unconfirmedCount = @($results | Where-Object {
    $_.MailboxStatus -eq 'NoCloudMailboxUnconfirmed'
}).Count
if ($unconfirmedCount -gt 0) {
    Write-Warning "$unconfirmedCount licensed users have no active cloud mailbox, but an on-premises mailbox could not be confirmed."
}
if ($OnlyOnPremises) {
    $results = @($results | Where-Object { $_.MailboxStatus -ne 'NoCloudMailboxUnconfirmed' })
}
$results = @($results | Sort-Object UserPrincipalName)
Write-Verbose "Returning $($results.Count) users from $($licensedUsers.Count) Copilot-licensed users."
if ($OutputPath) {
    if ($results.Count -gt 0) {
        $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8 -NoClobber
    } else {
        Write-Warning 'No matching users. No CSV file was created.'
    }
}
# Keep objects on the success stream so callers can filter or export them.
$results
