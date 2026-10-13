# Contributing

Contributions should keep this collection practical, understandable, and safe to run in an authorized Microsoft 365 environment.

## Add a utility

1. Create a branch for your change.
2. Add `scripts/<service>/<utility-name>/` using lowercase, hyphen-separated folder names.
3. Use approved PowerShell verb-noun names for scripts, such as `Get-ExampleReport.ps1`.
4. Add a README in US English covering purpose, supported PowerShell versions, dependencies, permissions, authentication, parameters, examples, output fields, limitations, and troubleshooting.
5. Add self-contained `Test-*.ps1` scenarios in the utility's `tests` subfolder. Use synthetic data and throw a terminating error when a scenario fails.
6. Add the utility to the root README catalog.
7. Run the collection scenarios locally and review the diff before opening a pull request.

Service folder examples: `exchange-online`, `entra-id`, `sharepoint-online`, `teams`, and `microsoft-graph`. Reuse an existing service folder where possible. Do not create empty folders just to reserve names.

## Script conventions

- Use explicit parameters, comment-based help, and an accurate minimum PowerShell version.
- Return structured objects rather than formatted text on the success stream.
- Do not hard-code tenant IDs, account names, server addresses, or credentials.
- Request only the permissions needed by the utility and explain them.
- Surface failures instead of treating unsuccessful queries as empty or successful results.
- Protect existing output files against accidental overwrites.
- Document read-only behavior. For scripts that change resources, use `SupportsShouldProcess`, appropriate confirmation, and clear warnings.
- Do not weaken authentication, execution policies, or security controls.
- Keep examples fictional and all new documentation, comments, and user-facing messages in US English.

## Scenario conventions

The shared runner parses all tracked utility PowerShell files and invokes discovered scenario scripts:

```powershell
powershell.exe -NoProfile -File .\tests\Invoke-Tests.ps1
pwsh.exe -NoProfile -File .\tests\Invoke-Tests.ps1
```

Scenario scripts must not authenticate to live services, call tenant APIs, or require secrets. Use local mocks and temporary directories, and clean up only artifacts created by the scenario.

Both supported PowerShell engines must pass. If a future utility requires a different platform or engine, update the runner and workflow explicitly rather than silently skipping its scenarios.

Authorized integration validation is separate from the credential-free workflow and should not expose tenant data in public logs.

## Review checklist

- The root catalog links to the correct README.
- All documented commands and relative paths match the repository structure.
- The utility's access level and limitations are clearly stated.
- No credentials, personal data, exports, or production connection details are staged.
- Both local PowerShell runs complete successfully.
- Existing utilities retain their behavior.

## Report an issue

Include the utility name, PowerShell version, relevant module versions, steps to reproduce, and a sanitized error message. Never attach real tenant exports or credentials.

For an issue that could expose credentials or sensitive data, do not post exploit details or real data in a public issue. Contact the maintainer privately through an appropriate channel.
