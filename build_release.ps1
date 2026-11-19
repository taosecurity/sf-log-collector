# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Richard Bejtlich
<#
.SYNOPSIS
    Builds dist\sf-log-collector-<version>.zip and its .sha256 file.
.DESCRIPTION
    The version comes from $ScriptVersion in Collect-StarfieldTestLogs.ps1. It must have a
    "## <version>" heading in CHANGELOG.md, and with -Tag it must match the tag (v<version>).
    Also writes build\release-notes.md (that CHANGELOG section) for the GitHub release.
#>
param([string]$Tag = '')

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src = Get-Content -LiteralPath (Join-Path $here 'Collect-StarfieldTestLogs.ps1') -Raw
if ($src -notmatch "\`$ScriptVersion = '(\d+\.\d+\.\d+)'") { throw 'No $ScriptVersion in Collect-StarfieldTestLogs.ps1' }
$ver = $Matches[1]
if ($Tag -and $Tag -ne "v$ver") { throw "Tag $Tag does not match the script version $ver" }

$changelog = Get-Content -LiteralPath (Join-Path $here 'CHANGELOG.md') -Raw
$m = [regex]::Match($changelog, "(?ms)^## $([regex]::Escape($ver))\b[^\n]*\n(.*?)(?=^## |\z)")
if (-not $m.Success) { throw "CHANGELOG.md has no '## $ver' section" }

$files = @('Collect-StarfieldTestLogs.ps1', 'Collect-StarfieldTestLogs.cmd', 'README.md', 'AGENTS.md',
           'PRIVACY.md', 'CHANGELOG.md', 'LICENSE', 'tests\Test-Collector.ps1')
foreach ($f in $files) {
    $p = Join-Path $here $f
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing $f" }
}
# Windows PowerShell 5.1 reads a BOM-less script as the ANSI code page: keep the scripts ASCII.
foreach ($f in @('Collect-StarfieldTestLogs.ps1', 'Collect-StarfieldTestLogs.cmd')) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $here $f))
    if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) { throw "$f has non-ASCII characters" }
}

$dist = Join-Path $here 'dist'
$build = Join-Path $here 'build'
foreach ($d in @($dist, $build)) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d) } }
$name = "sf-log-collector-$ver"
$stage = Join-Path $build $name
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
[void](New-Item -ItemType Directory -Path $stage)
foreach ($f in $files) {
    $dest = Join-Path $stage $f
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path -LiteralPath $destDir)) { [void](New-Item -ItemType Directory -Path $destDir) }
    Copy-Item -LiteralPath (Join-Path $here $f) -Destination $dest
}

$zip = Join-Path $dist "$name.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)

$sha = [System.Security.Cryptography.SHA256]::Create()
$fs = [System.IO.File]::OpenRead($zip)
try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLowerInvariant() } finally { $fs.Dispose(); $sha.Dispose() }
[System.IO.File]::WriteAllText("$zip.sha256", "$hash  $name.zip`n")
[System.IO.File]::WriteAllText((Join-Path $build 'release-notes.md'), $m.Groups[1].Value.Trim() + "`n")

Write-Host "Built $zip"
Write-Host "SHA-256 $hash"
