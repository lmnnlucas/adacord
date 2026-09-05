[CmdletBinding()]
param(
    [ValidateSet("html", "rst", "xml")]
    [string] $Backend = "html",
    [switch] $Warnings
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repoRoot "docs/generated"
$gnatdoc = Get-Command gnatdoc -ErrorAction SilentlyContinue

if ($null -eq $gnatdoc) {
    throw "gnatdoc is not available in PATH. Install GNATdoc 26 first."
}

$arguments = @(
    "-P", (Join-Path $repoRoot "adacord.gpr"),
    "--backend=$Backend",
    "--generate=public",
    "--style=gnat",
    "-O", $outputDirectory
)
if ($Warnings) {
    $arguments += "--warnings"
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Push-Location $repoRoot
try {
    & alr -n exec -- $gnatdoc.Source @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "gnatdoc failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
