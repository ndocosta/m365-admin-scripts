# Copilot Mailbox Audit

A read-only PowerShell utility that identifies users licensed for **Microsoft 365 Copilot** who **do not have an active Exchange Online mailbox**.

It distinguishes users who likely have an on-premises mailbox from users whose on-premises mailbox has been positively confirmed. Use it to support migration planning, license reviews, and investigation of provisioning or synchronization issues.

> A missing Exchange Online mailbox does not, by itself, prove that an on-premises mailbox exists.

## How it works

1. Identify the subscribed Microsoft 365 Copilot SKUs in the tenant.
2. Retrieve all users assigned those licenses, including disabled accounts.
3. Exclude users who have an active Exchange Online mailbox.
4. Inspect synchronized MailUsers and, optionally, query actual mailboxes through an existing on-premises Exchange session.
5. Return PowerShell objects and optionally export them to a CSV file.

The script does not assign or remove licenses, create mailboxes, or start migrations.

## Prerequisites

| Component | Requirement |
|---|---|
| PowerShell | Windows PowerShell 5.1 or PowerShell 7 on a platform supported by the required modules |
| Microsoft Graph modules | `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, `Microsoft.Graph.Identity.DirectoryManagement` |
| Exchange Online module | `ExchangeOnlineManagement` version 3 or later |
| Graph delegated permissions | `User.Read.All` and `LicenseAssignment.Read.All`; administrator consent may be required |
| Exchange permissions | Read access to all relevant Exchange Online recipients |
| Optional on-premises confirmation | An existing Exchange Server remote PowerShell session with permission to run `Get-Mailbox` |

Graph scopes do not replace tenant role requirements, consent policies, or access restrictions. Restricted Exchange RBAC scopes can produce incomplete results.

### Install the modules

Run once:

```powershell
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
Install-Module ExchangeOnlineManagement -MinimumVersion 3.0.0 -Scope CurrentUser
```

Use supported, current module versions approved by your organization.

## Quick start

From the repository root:

```powershell
Set-Location .\scripts\exchange-online\copilot-mailbox-audit

.\Get-CopilotUsersWithoutCloudMailbox.ps1 `
    -OutputPath .\Copilot-NoCloudMailbox.csv `
    -Verbose
```

The script prompts you to authenticate to Microsoft Graph and Exchange Online. Connect both services to **the same tenant**. Exactly one active Exchange Online connection is required.

The output file must not already exist, and its parent directory must exist. No CSV file is created when there are no matching users.

### Display results without exporting

```powershell
.\Get-CopilotUsersWithoutCloudMailbox.ps1 |
    Format-Table DisplayName, UserPrincipalName, MailboxStatus -AutoSize
```

### Return likely on-premises users only

```powershell
.\Get-CopilotUsersWithoutCloudMailbox.ps1 `
    -OnlyOnPremises `
    -OutputPath .\Copilot-OnPremisesLikely.csv
```

Without an on-premises session, this is an **inference, not confirmation**. Unconfirmed users are excluded with a warning.

## Interpret the results

| `MailboxStatus` | Meaning |
|---|---|
| `OnPremisesConfirmed` | A matching mailbox was found through the supplied on-premises Exchange session, with no matching active Exchange Online mailbox. |
| `OnPremisesLikely` | A synchronized Exchange Online MailUser has a nonempty `ExchangeGuid`. The actual on-premises mailbox has not been queried. |
| `NoCloudMailboxUnconfirmed` | No active Exchange Online mailbox was found, but an on-premises mailbox was not confirmed. Possible causes include pending provisioning, no mailbox at all, or inconsistent synchronization. |

When an on-premises session is supplied, only matches found through that session receive `OnPremisesConfirmed`. Other users remain `NoCloudMailboxUnconfirmed`.

### Output fields

| Field | Contents |
|---|---|
| `DisplayName` | User's display name |
| `UserPrincipalName` | User's UPN |
| `Mail` | Email address recorded in Microsoft Entra ID |
| `AccountEnabled` | Whether the account is enabled |
| `OnPremisesSyncEnabled` | User's synchronization state in Entra ID |
| `CopilotLicenses` | Assigned Copilot SKU names, separated by `;` |
| `MailboxStatus` | Mailbox location classification |
| `ExchangeGuid` | Mailbox GUID reported by the cloud MailUser, when available |
| `EntraObjectId` | User's Entra ID object identifier |

CSV files use UTF-8 and a comma delimiter. In Excel, use **Data > From Text/CSV** and select that delimiter if needed.

## Confirm on-premises mailboxes

Create a remote session using your organization's approved procedure. This example targets **Windows PowerShell 5.1** on a computer with access to Exchange Server and Kerberos authentication:

```powershell
# Replace this fictional server with your organization's approved endpoint.
$exchangeSession = New-PSSession `
    -ConfigurationName Microsoft.Exchange `
    -ConnectionUri 'http://exchange.contoso.test/PowerShell/' `
    -Authentication Kerberos `
    -Credential (Get-Credential)

try {
    .\Get-CopilotUsersWithoutCloudMailbox.ps1 `
        -OnPremisesSession $exchangeSession `
        -OnlyOnPremises `
        -OutputPath .\Copilot-OnPremisesConfirmed.csv
}
finally {
    Remove-PSSession -Session $exchangeSession
}
```

The hostname is fictional. **Do not use Basic authentication or store passwords in the script.** Use HTTPS and a different approved authentication method when required by your environment. Use the HTTP/Kerberos example only where that configuration is approved and correctly secured.

The script runs `Get-Mailbox` inside the supplied session. It does not import on-premises cmdlets or replace Exchange Online cmdlets.

Matching prioritizes the cloud MailUser's `ExchangeGuid`. When that GUID is unavailable, the script matches the user's UPN or email address against the local mailbox's UPN, primary SMTP address, and SMTP aliases. Manually review recycled identities, recent changes, and inconsistent hybrid metadata.

## Use existing connections

To explicitly select the tenant:

```powershell
$tenantId = Read-Host 'Tenant ID'
$adminUpn = Read-Host 'Administrative account UPN'

Connect-MgGraph `
    -TenantId $tenantId `
    -Scopes 'User.Read.All', 'LicenseAssignment.Read.All' `
    -NoWelcome

Connect-ExchangeOnline -UserPrincipalName $adminUpn -ShowBanner:$false

.\Get-CopilotUsersWithoutCloudMailbox.ps1 `
    -UseExistingConnections `
    -OutputPath .\Copilot-NoCloudMailbox.csv
```

The script leaves your connections open to avoid interrupting other work. When you no longer need them:

```powershell
Disconnect-MgGraph
Disconnect-ExchangeOnline -Confirm:$false
```

## Select SKUs explicitly

Automatic detection recognizes `Microsoft_365_Copilot` and `M365_COPILOT`, or SKUs containing the `M365_COPILOT` service plan. It does not automatically select Copilot Studio or unlicensed Copilot Chat.

If your product uses a different name, inspect the subscribed SKUs:

```powershell
Get-MgSubscribedSku -All |
    Select-Object SkuPartNumber, SkuId
```

Then provide the relevant IDs:

```powershell
# Enter real Microsoft 365 Copilot SKU IDs from the connected tenant.
$skuIds = (Read-Host 'M365 Copilot SKU IDs, separated by commas') -split ',' |
    ForEach-Object { [guid]$_.Trim() }

.\Get-CopilotUsersWithoutCloudMailbox.ps1 `
    -UseExistingConnections `
    -CopilotSkuId $skuIds
```

The script verifies that explicitly supplied SKU IDs exist in the tenant, but it does not verify that a manually selected SKU is a Microsoft 365 Copilot product. That selection is the operator's responsibility.

## Parameters

| Parameter | Purpose |
|---|---|
| `-OutputPath` | Export to a new CSV file |
| `-CopilotSkuId` | Explicitly select one or more SKU GUIDs |
| `-OnPremisesSession` | Query actual mailboxes through an existing Exchange Server session |
| `-OnlyOnPremises` | Exclude unconfirmed users; without a local session, include likely users only |
| `-UseExistingConnections` | Do not initiate new authentication |
| `-Verbose` | Display progress information |

Built-in help:

```powershell
Get-Help .\Get-CopilotUsersWithoutCloudMailbox.ps1 -Full
```

## Limitations

- This checks **assigned licenses**, not actual usage or the availability of each licensed service. A disabled service plan does not exclude a user.
- Inactive and soft-deleted cloud mailboxes do not count as active mailboxes.
- Restricted recipient scopes can hide mailboxes. Ensure that your account's queries cover the intended organization.
- Graph uses eventual consistency. Recent licensing, synchronization, and migration changes may not appear immediately.
- The queries are not a transactional snapshot. Data can change between requests.
- Reading all Exchange recipients can take time in large tenants and is subject to service throttling.
- The output does not certify every requirement for Microsoft 365 Copilot eligibility or functionality.

## Troubleshooting

| Problem | Action |
|---|---|
| Missing module or cmdlet | Install or update the required modules and open a new PowerShell session |
| Graph consent denied | Ask an administrator to approve the required scopes |
| Exchange access denied | Check the account's roles and RBAC scope |
| Different tenants or multiple active Exchange connections | Disconnect unnecessary Exchange connections and sign in to the correct tenant |
| Copilot SKU not detected | Inspect `Get-MgSubscribedSku` and use `-CopilotSkuId` |
| CSV already exists | Choose a different filename; existing files are not overwritten |
| No matching users | Check SKUs, permissions, and whether the users already have cloud mailboxes |
| Unconfirmed mailbox location | Supply `-OnPremisesSession` and review synchronization and provisioning |

If Windows blocks a downloaded script, review the code first and then unblock that file:

```powershell
Unblock-File .\Get-CopilotUsersWithoutCloudMailbox.ps1
```

Follow your organization's execution policy. Do not permanently weaken it or disable security controls.

## Privacy

Results include personal data and tenant identifiers. Store exports in an authorized location and **do not publish them to GitHub**, issues, logs, or screenshots.

The repository excludes common export and credential formats from Git, but review staged files manually before publishing. No GitHub secrets or Microsoft 365 credentials are required for the synthetic workflow.

## Local scenarios

From this utility folder:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Inventory.ps1
pwsh.exe -NoProfile -File .\tests\Test-Inventory.ps1
```

These scenarios use fictional data and do not require Graph or Exchange modules or authentication. They cover cloud-mailbox exclusion, classification, license selection, connection validation, error propagation, and safe CSV export.

The synthetic scenarios do not exercise a live on-premises session. Validate that integration separately in an authorized environment.

## Support

This is a community utility, not an official Microsoft product or a Microsoft-supported tool. Review the script and use it according to your organization's procedures.
