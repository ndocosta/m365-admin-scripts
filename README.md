# Microsoft 365 Admin Scripts

Practical PowerShell utilities for Microsoft 365 administration, reporting, and troubleshooting.

Each utility lives in its own service-specific folder, with a dedicated README covering prerequisites, permissions, examples, and limitations. Scripts are standalone: install only the dependencies required by the utility you want to run.

> Community utilities, not official Microsoft products. Review the code, follow your organization's policies, and validate results before making administrative decisions.

## Script catalog

| Service | Utility | Purpose | Access |
|---|---|---|---|
| Exchange Online | [Copilot Mailbox Audit](scripts/exchange-online/copilot-mailbox-audit/README.md) | Find Microsoft 365 Copilot-licensed users without an active cloud mailbox and distinguish likely from confirmed on-premises mailboxes. | Read-only |

## Getting started

Clone the repository:

```powershell
git clone https://github.com/ndocosta/m365-admin-scripts.git
Set-Location .\m365-admin-scripts
```

Choose a utility from the catalog and read its README before running it. For the Copilot Mailbox Audit:

```powershell
Set-Location .\scripts\exchange-online\copilot-mailbox-audit

Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
Install-Module ExchangeOnlineManagement -MinimumVersion 3.0.0 -Scope CurrentUser

.\Get-CopilotUsersWithoutCloudMailbox.ps1 `
    -OutputPath .\Copilot-NoCloudMailbox.csv
```

This example authenticates to Microsoft Graph and Exchange Online. It does not change licenses or mailboxes. See the [utility README](scripts/exchange-online/copilot-mailbox-audit/README.md) for permissions, tenant selection, and on-premises confirmation.

If you prefer not to use Git, select **Code > Download ZIP** on GitHub and extract the archive.

## Repository structure

```text
.
|-- .github/
|   `-- workflows/
|       `-- validate.yml
|-- scripts/
|   `-- exchange-online/
|       `-- copilot-mailbox-audit/
|           |-- Get-CopilotUsersWithoutCloudMailbox.ps1
|           |-- README.md
|           `-- tests/
|               `-- Test-Inventory.ps1
|-- tests/
|   `-- Invoke-Tests.ps1
|-- .gitattributes
|-- .gitignore
|-- CONTRIBUTING.md
|-- LICENSE
`-- README.md
```

Create additional service folders only when adding an actual utility, for example `entra-id`, `sharepoint-online`, `teams`, or `microsoft-graph`. This keeps the collection organized without empty placeholder folders.

## Adding more utilities

Keep one utility per folder: `scripts/<service>/<utility-name>/`.

Each addition should include its script, a US English README, and credential-free scenarios in a `tests` subfolder. Update the catalog above and follow [CONTRIBUTING.md](CONTRIBUTING.md).

The shared runner automatically discovers `Test-*.ps1` files in the utilities' test folders. GitHub Actions runs them on Windows PowerShell 5.1 and PowerShell 7 without Microsoft 365 credentials.

For breaking changes or independently distributed tools, consider a dedicated repository later. Simple standalone utilities can remain in this collection.

## Local validation

Run from the repository root:

```powershell
powershell.exe -NoProfile -File .\tests\Invoke-Tests.ps1
pwsh.exe -NoProfile -File .\tests\Invoke-Tests.ps1
```

Synthetic scenarios validate local behavior. They do not establish live tenant access, prove organization-wide RBAC coverage, or replace authorized integration checks.

## Privacy and safe use

Do not commit tenant exports, personal data, credentials, tokens, connection files, or production logs. Use only fictional examples in documentation and issues.

The `.gitignore` excludes common report and credential formats, but it is not a security boundary and does not remove previously tracked files. Review every staged change before pushing.

Utilities must document whether they are read-only or make changes. A future write-enabled utility should use explicit confirmation and safe defaults. This repository does not require GitHub secrets for its synthetic validation workflow.

## Publishing future updates

After reviewing and validating a change:

```powershell
git switch -c add-new-utility
git add scripts README.md
git diff --cached
git commit -m "Add a new Microsoft 365 utility"
git push -u origin add-new-utility
gh pr create --fill
```

Use a descriptive branch name and commit message for each utility. Prefer pull requests so changes and their automated results remain easy to review.

## License

This collection is available under the [MIT License](LICENSE).
