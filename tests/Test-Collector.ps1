# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Richard Bejtlich
<#
.SYNOPSIS
    Tests Collect-StarfieldTestLogs.ps1 against a fake Starfield setup in a temp folder.
.DESCRIPTION
    Builds a fake Documents\My Games\Starfield, game folder, MO2 instance, saves and
    screenshots, runs the collector with -NoPrompt, and checks the zip. It needs no game.
    Exit code 0 = all passed, 1 = a check failed.
.PARAMETER Shell
    The PowerShell to run the collector with: powershell (5.1) or pwsh (7). Default: the current one.
#>
param([string]$Shell = '')

$ErrorActionPreference = 'Stop'
if (-not $Shell) { $Shell = (Get-Process -Id $PID).Path }
$Collector = Join-Path (Split-Path $PSScriptRoot -Parent) 'Collect-StarfieldTestLogs.ps1'
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ('sflc-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:Failures = 0
$script:Passes = 0

function Assert([bool]$Cond, [string]$What) {
    if ($Cond) { $script:Passes++; Write-Host "  ok   $What" }
    else { $script:Failures++; Write-Host "  FAIL $What" -ForegroundColor Red }
}

function New-File([string]$Rel, [string]$Text = 'x', [double]$AgeHours = 0) {
    $p = Join-Path $Root $Rel
    $d = Split-Path $p -Parent
    if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    [System.IO.File]::WriteAllText($p, $Text)
    if ($AgeHours -gt 0) { (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddHours(-$AgeHours) }
    return $p
}

function Invoke-Collector([string[]]$CollectorArgs) {
    $out = & $Shell -NoProfile -ExecutionPolicy Bypass -File $Collector @CollectorArgs 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; text = $out }
}

function Open-Zip([string]$Dir) {
    $zip = @(Get-ChildItem -LiteralPath $Dir -Filter 'StarfieldLogs-*.zip' | Sort-Object LastWriteTime -Descending)[0]
    $x = Join-Path $Root ('x-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $x)
    $names = @(Get-ChildItem -LiteralPath $x -Recurse -File | ForEach-Object { $_.FullName.Substring($x.Length + 1) -replace '\\', '/' })
    return @{ zip = $zip; dir = $x; names = $names; manifest = (Get-Content -LiteralPath (Join-Path $x 'manifest.json') -Raw | ConvertFrom-Json); raw = (Get-Content -LiteralPath (Join-Path $x 'manifest.json') -Raw) }
}

try {
    Write-Host "Collector: $Collector"
    Write-Host "Shell    : $Shell"
    Write-Host "Temp     : $Root"

    # ---------------- fake setup
    New-File 'MyGames\Logs\Script\Papyrus.0.log' 'Papyrus log opened (PC-64)' | Out-Null
    New-File 'MyGames\Logs\Script\Papyrus.1.log' 'older session' 30 | Out-Null       # always copied
    New-File 'MyGames\Logs\Script\Papyrus.3.log' 'old' 30 | Out-Null                 # outside the window
    New-File 'MyGames\Logs\Script\User\MyMod.0.log' 'user log' | Out-Null
    New-File 'MyGames\StarfieldCustom.ini' "[Papyrus]`r`nbEnableLogging=1`r`n" 30 | Out-Null
    New-File 'MyGames\StarfieldPrefs.ini' '[Display]' 30 | Out-Null
    New-File 'MyGames\SFSE\Logs\sfse.txt' 'sfse log' | Out-Null
    New-File 'MyGames\SFSE\Logs\minidump.dmp' 'dump' | Out-Null                       # never copied
    New-File 'MyGames\SFSE\Crashlogs\crash-2026-11-19.log' 'crash' | Out-Null
    New-File 'LocalApp\Starfield\plugins.txt' "*MyMod.esm`r`n" 30 | Out-Null
    New-File 'Game\Starfield.exe' 'not a real exe' | Out-Null
    New-File 'Game\Data\MyMod.esm' 'plugin' | Out-Null
    New-File 'Game\Data\SFSE\Plugins\Foo.ini' 'a=1' 30 | Out-Null                    # settings: always
    New-File 'Game\Data\SFSE\Plugins\Foo_202611010000.ini' 'old backup' 30 | Out-Null # old backup: skipped
    New-File 'Game\Data\SFSE\Plugins\Foo.dll' 'binary' | Out-Null                    # never copied
    New-File 'Game\Data\SFSE\Plugins\Foo.log' 'plugin log' | Out-Null
    New-File 'Downloads\sfconsole_20261119.txt' 'console' | Out-Null
    New-File 'Downloads\vortex-starfield-default-backup-20261119.json' '{}' | Out-Null
    New-File 'Shots\a.png' 'png' | Out-Null
    New-File 'Shots\old.png' 'png' 30 | Out-Null
    New-File 'Shots2\b.jpg' 'jpg' | Out-Null                                        # second folder ("a;b")
    New-File 'Saves\Save1_ABCD1234_000102_20261119100000_1_2.sfs' 'before' | Out-Null
    New-File 'Saves\Save2_ABCD1234_000203_20261119110000_1_2.sfs' 'after' | Out-Null
    New-File 'Saves\Save3_FFFF0000_000001_20261118090000_1_2.sfs' 'other character' | Out-Null
    New-File 'Saves\Autosave1_ABCD1234_000300_20261119120000_1_2.sfs' 'auto' | Out-Null
    New-File 'MO2\ModOrganizer.ini' "[General]`r`nselected_profile=@ByteArray(Test)`r`n[Settings]`r`n" | Out-Null
    New-File 'MO2\profiles\Test\plugins.txt' "*MyMod.esm`r`n" 30 | Out-Null
    New-File 'MO2\profiles\Test\modlist.txt' "+MyMod`r`n" 30 | Out-Null
    New-File 'MO2\profiles\Test\StarfieldCustom.ini' "[Papyrus]`r`nbEnableLogging=1`r`n" 30 | Out-Null
    New-File 'MO2\overwrite\SFSE\Plugins\Bar.ini' 'b=2' 30 | Out-Null
    New-File 'MO2\logs\mo_interface.log' 'mo2 log' | Out-Null

    $common = @('-NoPrompt', '-Hours', '2',
        '-MyGamesDir', (Join-Path $Root 'MyGames'), '-PluginsTxtDir', (Join-Path $Root 'LocalApp\Starfield'),
        '-DownloadsDir', (Join-Path $Root 'Downloads'), '-ScreenshotDir', ((Join-Path $Root 'Shots') + ';' + (Join-Path $Root 'Shots2')),
        '-SavesDir', (Join-Path $Root 'Saves'))

    # ---------------- 1: full run (Steam-style game folder + MO2 + save pair)
    Write-Host ''
    Write-Host 'Test 1: full run'
    $out1 = Join-Path $Root 'out1'
    $log1 = Join-Path $Root 'run1.log'
    $r = Invoke-Collector ($common + @('-Note', 'Test one: checks 1-3', '-GamePath', (Join-Path $Root 'Game'),
        '-MO2Path', (Join-Path $Root 'MO2'), '-SavePair', '-OutDir', $out1, '-LogFile', $log1, '-DryRun'))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    if ($r.code -ne 0) { Write-Host $r.text }
    $z = Open-Zip $out1
    $n = $z.names
    Assert ($z.zip.Name -match '^StarfieldLogs-\d{8}-\d{6}-Test-one-checks-1-3\.zip$') "zip name carries the note ($($z.zip.Name))"
    foreach ($want in @('docs/Logs/Script/Papyrus.0.log', 'docs/Logs/Script/Papyrus.1.log', 'docs/Logs/Script/User/MyMod.0.log',
                        'docs/StarfieldCustom.ini', 'docs/StarfieldPrefs.ini', 'docs/SFSE/Logs/sfse.txt',
                        'docs/SFSE/Crashlogs/crash-2026-11-19.log', 'appdata/plugins.txt',
                        'game/Data/SFSE/Plugins/Foo.ini', 'game/Data/SFSE/Plugins/Foo.log',
                        'downloads/sfconsole_20261119.txt', 'vortex/vortex-starfield-default-backup-20261119.json',
                        'screenshots/a.png', 'screenshots/b.jpg', 'saves/before-Save1_ABCD1234_000102_20261119100000_1_2.sfs',
                        'saves/after-Save2_ABCD1234_000203_20261119110000_1_2.sfs',
                        'mo2/profile/plugins.txt', 'mo2/profile/modlist.txt', 'mo2/profile/StarfieldCustom.ini',
                        'mo2/overwrite/SFSE/Plugins/Bar.ini', 'mo2/logs/mo_interface.log',
                        'manifest.json', 'collector-log.txt')) {
        Assert ($n -contains $want) "has $want"
    }
    foreach ($nope in @('docs/Logs/Script/Papyrus.3.log', 'game/Data/SFSE/Plugins/Foo_202611010000.ini',
                        'game/Data/SFSE/Plugins/Foo.dll', 'screenshots/old.png')) {
        Assert (-not ($n -contains $nope)) "leaves out $nope"
    }
    Assert (-not ($n | Where-Object { $_ -match '\.(esm|exe|dll)$' })) 'no .esm/.exe/.dll in the zip'
    $m = $z.manifest
    Assert ($m.tool -match '^Collect-StarfieldTestLogs \d+\.\d+\.\d+$') "manifest tool ($($m.tool))"
    Assert ($m.savePair.character -eq 'ABCD1234') 'save pair picked the newest manual save''s character'
    Assert ($m.mo2.profile -eq 'Test') 'MO2 profile read from ModOrganizer.ini'
    Assert (@($m.listing.dataPlugins | Where-Object { $_.name -eq 'MyMod.esm' }).Count -eq 1) 'Data plugins listed by name'
    Assert (@($m.warnings | Where-Object { $_ -match 'Crash log found' }).Count -ge 1) 'crash log warning'
    Assert ($m.dryRun -eq $true) 'dryRun recorded'
    $prof = $env:USERPROFILE.TrimEnd('\')
    Assert (-not ($z.raw.ToLowerInvariant().Contains(($prof -replace '\\', '\\').ToLowerInvariant()))) 'manifest hides the Windows user folder'
    Assert (-not ($z.raw -match '"computer"|"user"')) 'manifest has no computer or user name'
    Assert (Test-Path -LiteralPath $log1) '-LogFile written'
    $logText = Get-Content -LiteralPath $log1 -Raw
    Assert ($logText -match 'skip \(blocked type\).*minidump\.dmp') 'log says why minidump.dmp was skipped'
    Assert (-not ($n -contains 'docs/SFSE/Logs/minidump.dmp')) 'leaves out the .dmp'
    Assert (@($m.skipped | Where-Object { $_ -match 'minidump\.dmp' }).Count -eq 1) 'manifest lists the skipped .dmp'
    Assert (-not ($logText.ToLowerInvariant().Contains($prof.ToLowerInvariant()))) 'log hides the Windows user folder'
    Assert (-not (Test-Path -LiteralPath (Join-Path $out1 ('.last-run-' + $env:USERNAME)))) '-DryRun leaves no marker'

    # ---------------- 2: no game folder, bad MO2 path, marker written
    Write-Host ''
    Write-Host 'Test 2: missing game folder and bad MO2 path'
    $out2 = Join-Path $Root 'out2'
    $r = Invoke-Collector ($common + @('-GamePath', (Join-Path $Root 'NoGame'), '-MO2Path', (Join-Path $Root 'NoMO2'), '-OutDir', $out2))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out2
    Assert (@($z.manifest.warnings | Where-Object { $_ -match 'No Starfield.exe in -GamePath' }).Count -eq 1) 'warns about -GamePath'
    Assert (@($z.manifest.warnings | Where-Object { $_ -match 'No ModOrganizer.ini' }).Count -eq 1) 'warns about -MO2Path'
    Assert ($z.names -contains 'docs/Logs/Script/Papyrus.0.log') 'still collects the Papyrus log'
    Assert (Test-Path -LiteralPath (Join-Path $out2 ('.last-run-' + $env:USERNAME))) 'marker written'

    # ---------------- 3: second run uses the marker
    Write-Host ''
    Write-Host 'Test 3: since last run'
    $r = Invoke-Collector @('-NoPrompt', '-MyGamesDir', (Join-Path $Root 'MyGames'), '-PluginsTxtDir', (Join-Path $Root 'LocalApp\Starfield'),
        '-DownloadsDir', (Join-Path $Root 'Downloads'), '-ScreenshotDir', (Join-Path $Root 'Shots'), '-GamePath', (Join-Path $Root 'Game'),
        '-OutDir', $out2)
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out2
    Assert ($z.manifest.window.how -eq 'since last run') "window is 'since last run' ($($z.manifest.window.how))"
    Assert (-not ($z.names -contains 'docs/SFSE/Logs/sfse.txt')) 'unchanged SFSE log not collected again'
    Assert ($z.names -contains 'appdata/plugins.txt') 'plugins.txt always collected'

    # ---------------- 4: -GamePath given as the Data folder, relative -OutDir
    Write-Host ''
    Write-Host 'Test 4: Data folder as -GamePath, relative -OutDir'
    Push-Location $Root
    try {
        $r = Invoke-Collector ($common + @('-GamePath', (Join-Path $Root 'Game\Data'), '-OutDir', 'out4'))
    } finally { Pop-Location }
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $Root 'out4') -Filter '*.zip' -ErrorAction SilentlyContinue).Count -eq 1) 'zip in the relative out folder'
} finally {
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:Passes passed, $script:Failures failed"
if ($script:Failures -gt 0) { exit 1 }
exit 0
