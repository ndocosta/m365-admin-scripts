#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$utilitiesRoot = Join-Path $repositoryRoot 'scripts'
$powerShellFiles = @(Get-ChildItem -LiteralPath $utilitiesRoot -Recurse -File -Filter '*.ps1')
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "PowerShell syntax errors in $($file.FullName): $($parseErrors | Out-String)"
    }
}

$scenarioFiles = @($powerShellFiles | Where-Object {
    $_.Name -like 'Test-*.ps1' -and $_.Directory.Name -eq 'tests'
} | Sort-Object FullName)
if ($scenarioFiles.Count -eq 0) {
    throw 'No utility scenario files were found. Add Test-*.ps1 files in utility tests folders.'
}

foreach ($scenario in $scenarioFiles) {
    Write-Host "Running $($scenario.FullName.Substring($repositoryRoot.Length + 1))"
    & $scenario.FullName
}

Write-Host "$($scenarioFiles.Count) scenario file(s) completed on PowerShell $($PSVersionTable.PSVersion)."
