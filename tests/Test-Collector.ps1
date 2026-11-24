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
    The PowerShell to run the collector with: powershell (5.1) or pwsh (7), with or without .exe, or
    the full path of powershell.exe or pwsh.exe. Default: the PowerShell running this test; from a host
    that isn't a console PowerShell (the ISE), the console PowerShell in the same install folder, or the
    one on PATH if that folder has none (the Shell line at the top says so). A \\?\ long-path prefix is
    accepted and dropped, and .. in the path is resolved.
.PARAMETER ResolveOnly
    Only work out and check the shell, print the Shell line and stop (exit 0). The harness uses this
    to test its own -Shell handling.
#>
param([string]$Shell = '', [switch]$ResolveOnly)

$ErrorActionPreference = 'Stop'
$auto = -not $Shell
$autoNote = 'the default for this host'
if ($auto) {
    # Default: the PowerShell running this test. A host such as the ISE isn't one to run the collector
    # with: then the console PowerShell in the same install folder ($PSHOME) is used, or else PATH's.
    $Shell = (Get-Process -Id $PID).Path
    if ([System.IO.Path]::GetFileName($Shell) -notmatch '^(?i)(powershell|pwsh)\.exe$') {
        $exe = $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
        if (Test-Path -LiteralPath (Join-Path $PSHOME $exe)) { $Shell = Join-Path $PSHOME $exe }
        else { $Shell = $exe; $autoNote = "the default for this host, taken from PATH because $PSHOME has no $exe" }
    }
}
# Resolved once, so the log shows the exact program that runs the collector. Accepted, to keep this
# simple: powershell or pwsh (with or without .exe, looked up on PATH), or the full path of
# powershell.exe or pwsh.exe (backslashes or forward slashes).
$given = $(if ($auto) { "$Shell ($autoNote)" } else { $Shell })
$usage = 'Pass -Shell powershell, pwsh or the full path of powershell.exe or pwsh.exe.'
$bare = $Shell -replace '(?i)\.exe$', ''
if ($bare -eq 'powershell' -or $bare -eq 'pwsh') {
    $found = @(Get-Command -Name "$bare.exe" -CommandType Application -ErrorAction SilentlyContinue |
               Where-Object { [System.IO.Path]::GetExtension($_.Source) -eq '.exe' })
    if ($found.Count -eq 0) { Write-Host "Shell '$given' not found on PATH. $usage" -ForegroundColor Red; exit 1 }
    $Shell = $found[0].Source
} elseif ($Shell -match '^([A-Za-z]:[\\/]|\\\\|//)' -and [System.IO.Path]::GetFileName($Shell) -match '^(?i)(powershell|pwsh)\.exe$') {
    # Slashes first: GetFullPath keeps the separators of a \\?\ long path as they are. It also leaves
    # .. unresolved after \\?\, and Windows PowerShell 5.1 can't start through a \\?\ path, so the
    # prefix is dropped (\\?\UNC\server\share becomes \\server\share). A PowerShell path is never
    # long enough to need it.
    # The same goes for the \\.\ device prefix. What is left must be a full drive or UNC path:
    # \\?\Volume{...}\ or \\?\C:pwsh.exe would otherwise resolve against the current folder.
    $p = $Shell -replace '/', '\'
    if ($p -match '^(?i)\\\\[?.]\\UNC\\(.*)$') { $p = '\\' + $Matches[1] }
    elseif ($p -match '^\\\\[?.]\\(.*)$') { $p = $Matches[1] }
    if ($p -notmatch '^([A-Za-z]:\\|\\\\[^\\?.])') {
        Write-Host "Shell '$given' is not a full drive or network path. $usage" -ForegroundColor Red; exit 1
    }
    try { $Shell = [System.IO.Path]::GetFullPath($p) }
    catch { Write-Host "Shell '$given' is not a usable path. $usage" -ForegroundColor Red; exit 1 }
    if ([System.IO.Path]::GetFileName($Shell) -notmatch '^(?i)(powershell|pwsh)\.exe$') {
        Write-Host "Shell '$given' is not accepted. $usage" -ForegroundColor Red; exit 1
    }
    $exists = $false
    try { $exists = Test-Path -LiteralPath $Shell -PathType Leaf -ErrorAction Stop } catch { }
    if (-not $exists) { Write-Host "Shell '$given' not found or not readable. $usage" -ForegroundColor Red; exit 1 }
} else {
    Write-Host "Shell '$given' is not accepted. $usage" -ForegroundColor Red; exit 1
}
# A nonzero exit must reach the check below, not become an error (PowerShell 7.4+ can do that).
$PSNativeCommandUseErrorActionPreference = $false
try { $ShellEdition = (@(& $Shell -NoProfile -Command '$PSVersionTable.PSEdition; $PSVersionTable.PSVersion.ToString()') -join ' ').Trim() }
catch { Write-Host "Shell '$given' ($Shell) failed to run: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
if ($LASTEXITCODE -ne 0 -or $ShellEdition -notmatch '^(Desktop|Core) \d') {
    Write-Host "Shell '$given' ($Shell) did not answer as PowerShell (exit $LASTEXITCODE, said '$ShellEdition')." -ForegroundColor Red; exit 1
}
$shellLine = "Shell    : $Shell ($ShellEdition$(if ($auto) { ", $autoNote" }))"
if ($ResolveOnly) { Write-Host $shellLine; exit 0 }
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
    # An error the collector prints must become a failed check, not stop Windows PowerShell 5.1 here.
    $ErrorActionPreference = 'Continue'
    $out =& $Shell -NoProfile -ExecutionPolicy Bypass -File $Collector @CollectorArgs 2>&1 | Out-String
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
    Write-Host $shellLine
    Write-Host "Harness  : PowerShell $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
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

    # ---------------- 1b: -Log (short form of -LogFile) and -Verbose
    Write-Host ''
    Write-Host 'Test 1b: -Log and -Verbose'
    $out1b = Join-Path $Root 'out1b'
    $log1b = Join-Path $Root 'run1b.log'
    $r = Invoke-Collector ($common + @('-GamePath', (Join-Path $Root 'Game'), '-OutDir', $out1b, '-Log', $log1b, '-Verbose', '-DryRun'))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    if ($r.code -ne 0) { Write-Host $r.text }
    Assert (Test-Path -LiteralPath $log1b) '-Log written'
    $log1bText = $(if (Test-Path -LiteralPath $log1b) { Get-Content -LiteralPath $log1b -Raw } else { '' })
    Assert ($log1bText -match 'Collect-StarfieldTestLogs \d+\.\d+\.\d+, PowerShell') '-Log file holds the run log'
    Assert ($r.text -match "Log     : $([regex]::Escape($log1b))") 'summary names the -Log file'
    Assert ($r.text -match 'VERBOSE: Collect-StarfieldTestLogs \d') '-Verbose shows the log on screen'
    $verboseLines = ($r.text -split "`r?`n" | Where-Object { $_ -match '^VERBOSE:' }) -join "`n"
    Assert (-not ($verboseLines.ToLowerInvariant().Contains($prof.ToLowerInvariant()))) '-Verbose lines hide the Windows user folder'
    $z = Open-Zip $out1b
    Assert ($z.names -contains 'collector-log.txt') 'collector-log.txt still in the zip with -Log'

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

    # ---------------- 5: -GamePath on a drive that doesn't exist only warns
    Write-Host ''
    Write-Host 'Test 5: -GamePath on a missing drive'
    # A letter PowerShell has no drive for at all (a disconnected network drive still has one).
    $known = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() })
    $free = @([char[]]([int][char]'G'..[int][char]'Z') | ForEach-Object { [string]$_ } |
              Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) -and ($known -notcontains $_) })
    if ($free.Count -eq 0) {
        Write-Host '  skip (every drive letter from G to Z is in use)'
    } else {
        $out5 = Join-Path $Root 'out5'
        $r = Invoke-Collector ($common + @('-GamePath', "$($free[-1]):\NoSuchGame", '-OutDir', $out5))
        Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
        $z = Open-Zip $out5
        Assert (@($z.manifest.warnings | Where-Object { $_ -match 'No Starfield.exe in -GamePath' }).Count -eq 1) 'warns about the missing drive'
        Assert (@($z.manifest.warnings | Where-Object { $_ -match 'Path not found' }).Count -eq 1) 'names the path on the missing drive'
    }

    # ---------------- 5b: a damaged marker falls back to 12 hours
    Write-Host ''
    Write-Host 'Test 5b: damaged last-run marker'
    $out5b = Join-Path $Root 'out5b'
    [void](New-Item -ItemType Directory -Path $out5b -Force)
    [System.IO.File]::WriteAllText((Join-Path $out5b ('.last-run-' + $env:USERNAME)), 'not a date')
    $r = Invoke-Collector ($common[3..($common.Count - 1)] + @('-NoPrompt', '-GamePath', (Join-Path $Root 'Game'), '-OutDir', $out5b))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out5b
    Assert ($z.manifest.window.how -match '12 hours') "window falls back to 12 hours ($($z.manifest.window.how))"
    Assert (@($z.manifest.warnings | Where-Object { $_ -match 'marker' }).Count -eq 1) 'warns about the marker'

    # ---------------- 5c: same screenshot name in two folders
    Write-Host ''
    Write-Host 'Test 5c: same screenshot name in two folders'
    New-File 'ShotsA\same.png' 'one' | Out-Null
    New-File 'ShotsB\same.png' 'two' | Out-Null
    $out5c = Join-Path $Root 'out5c'
    $args5c = @('-NoPrompt', '-Hours', '2', '-MyGamesDir', (Join-Path $Root 'MyGames'), '-PluginsTxtDir', (Join-Path $Root 'LocalApp\Starfield'),
        '-DownloadsDir', (Join-Path $Root 'Downloads'), '-SavesDir', (Join-Path $Root 'Saves'), '-GamePath', (Join-Path $Root 'Game'),
        '-ScreenshotDir', ((Join-Path $Root 'ShotsA') + ';' + (Join-Path $Root 'ShotsB')), '-OutDir', $out5c)
    $r = Invoke-Collector $args5c
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out5c
    Assert (@($z.names | Where-Object { $_ -match '^screenshots/same(-2)?\.png$' }).Count -eq 2) 'both screenshots kept'
    $texts = @('same.png', 'same-2.png' | ForEach-Object { Get-Content -LiteralPath (Join-Path $z.dir "screenshots\$_") -Raw -ErrorAction SilentlyContinue }) | Sort-Object
    Assert (($texts -join ',') -eq 'one,two') "the two screenshots are the two files ($($texts -join ','))"

    # ---------------- 5d: the user folder is hidden at the end of a sentence too
    Write-Host ''
    Write-Host 'Test 5d: user folder at the end of a warning'
    $out5d = Join-Path $Root 'out5d'
    $prof5 = $env:USERPROFILE.TrimEnd('\')
    $r = Invoke-Collector @('-NoPrompt', '-Hours', '1', '-MyGamesDir', (Join-Path $Root 'MyGames'), '-PluginsTxtDir', (Join-Path $Root 'LocalApp\Starfield'),
        '-DownloadsDir', (Join-Path $Root 'Downloads'), '-ScreenshotDir', (Join-Path $Root 'Shots'), '-GamePath', (Join-Path $Root 'Game'),
        '-SavesDir', $prof5, '-IncludeSaves', '-OutDir', $out5d)
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out5d
    Assert (@($z.manifest.warnings | Where-Object { $_ -match 'No save files found in %USERPROFILE%\.' }).Count -eq 1) 'warning ends with %USERPROFILE%.'
    Assert (-not ($z.raw.ToLowerInvariant().Contains(($prof5 -replace '\\', '\\').ToLowerInvariant()))) 'manifest hides the user folder'
    $log5d = Get-Content -LiteralPath (Join-Path $z.dir 'collector-log.txt') -Raw
    Assert ($log5d -match '\.last-run-%USERNAME%') 'collector-log.txt names the marker as .last-run-%USERNAME%'
    Assert (-not ($log5d -match [regex]::Escape('.last-run-' + $env:USERNAME) + '(?![\w~-])')) 'collector-log.txt hides the user name in the marker name'
    Assert (-not ($log5d.ToLowerInvariant().Contains($prof5.ToLowerInvariant()))) 'collector-log.txt hides the user folder'
    $z5b = Open-Zip $out5b
    Assert (@($z5b.manifest.warnings | Where-Object { $_ -match '\.last-run-%USERNAME%' }).Count -eq 1) 'marker warning hides the user name'

    # ---------------- 5g: a marker that can't be read or written (a folder by that name)
    Write-Host ''
    Write-Host 'Test 5g: marker that cannot be written'
    $out5g = Join-Path $Root 'out5g'
    [void](New-Item -ItemType Directory -Path (Join-Path $out5g ('.last-run-' + $env:USERNAME)) -Force)
    $r = Invoke-Collector ($common[3..($common.Count - 1)] + @('-NoPrompt', '-GamePath', (Join-Path $Root 'Game'), '-OutDir', $out5g))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out5g
    Assert (@($z.manifest.warnings | Where-Object { $_ -match "can't be written" }).Count -eq 1) 'the zip carries the marker-write warning'
    Assert (-not ($r.text -match 'Could not update the last-run marker')) 'no second warning for the same marker problem'
    # ---------------- 5h: a hidden marker is read and updated
    Write-Host ''
    Write-Host 'Test 5h: hidden marker'
    $out5h = Join-Path $Root 'out5h'
    [void](New-Item -ItemType Directory -Path $out5h -Force)
    $mk = Join-Path $out5h ('.last-run-' + $env:USERNAME)
    [System.IO.File]::WriteAllText($mk, (Get-Date).AddHours(-3).ToString('o', [Globalization.CultureInfo]::InvariantCulture))
    (Get-Item -LiteralPath $mk -Force).Attributes = 'Hidden'
    $before = (Get-Content -LiteralPath $mk -Raw)
    $r = Invoke-Collector ($common[3..($common.Count - 1)] + @('-NoPrompt', '-GamePath', (Join-Path $Root 'Game'), '-OutDir', $out5h))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out5h
    Assert (@($z.manifest.warnings | Where-Object { $_ -match 'marker' }).Count -eq 0) 'no marker warning'
    Assert ((Get-Content -LiteralPath $mk -Raw) -ne $before) 'hidden marker updated'
    Assert ($z.manifest.window.how -eq 'since last run') "window from the hidden marker ($($z.manifest.window.how))"

    # ---------------- 5f: Resolve-MO2Dir, loaded from the script (no run)
    Write-Host ''
    Write-Host 'Test 5f: MO2 folder values'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Collector, [ref]$null, [ref]$null)
    foreach ($name in 'ConvertFrom-QtIniValue', 'Resolve-MO2Dir') {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    # Raw INI text, decoded as MO2 (Qt) decodes it, then resolved. Q: need not exist: it's text only.
    $cases = @(
        @('Q:\MO2', '', 'profiles', 'Q:\MO2\profiles'),
        @('Q:\MO2', 'Q:/Games/MO2/profiles', '', 'Q:\Games\MO2\profiles'),
        @('Q:\MO2', '"Q:/Games, Mods/MO2/profiles"', '', 'Q:\Games, Mods\MO2\profiles'),
        @('Q:\MO2', '%BASE_DIR%/profiles', '', 'Q:\MO2\profiles'),
        @('Q:\Mods$1\MO2', '%BASE_DIR%/profiles', '', 'Q:\Mods$1\MO2\profiles'),
        @('Q:\MO2', '//nas/share/profiles', '', '\\nas\share\profiles'),
        @('Q:\MO2', '\\\\nas\\share\\profiles', '', '\\nas\share\profiles'),
        @('Q:\MO2', '\\\\nas\\share\\\\profiles', '', '\\nas\share\profiles'),
        @('Q:\MO2', '/Profiles', '', 'Q:\Profiles'),
        @('Q:\MO2', '\\Profiles', '', 'Q:\Profiles'),
        @('Q:\MO2', '\\Mods\\Profiles', '', 'Q:\Mods\Profiles'),
        @('Q:\MO2', 'Q:profiles', '', 'Q:\profiles'),
        # Qt drops unknown escapes with their backslash, so MO2 itself reads a hand-typed D:\Games\... this way:
        @('Q:\MO2', 'Q:\Games\Tools\Xbox\Backup', '', 'Q:\amesoolsboxackup'),
        @('Q:\MO2', '@@odd/profiles', '', 'Q:\MO2\@odd\profiles'),
        @('Q:\MO2', 'sub/profiles', '', 'Q:\MO2\sub\profiles'))
    foreach ($c in $cases) {
        $got = Resolve-MO2Dir $c[0] (ConvertFrom-QtIniValue $c[1]) $c[2]
        Assert ($got -eq $c[3]) "MO2 value '$($c[1])' -> $got (want $($c[3]))"
    }
    $prof = ConvertFrom-QtIniValue '@ByteArray(\xc3\x89quipe)'
    Assert ($prof -eq ([string][char]0xC9 + 'quipe')) "@ByteArray UTF-8 bytes decoded ($prof)"
    Assert ((ConvertFrom-QtIniValue '@ByteArray(Star Wars Genesis Compiler)') -eq 'Star Wars Genesis Compiler') '@ByteArray plain text'
    Assert ((ConvertFrom-QtIniValue 'D:/x\x00e9y') -eq ('D:/x' + [char]0xE9 + 'y')) '\xHHHH escape in a plain value'
    Assert ((ConvertFrom-QtIniValue '@ByteArray(@@odd)') -ceq '@@odd') '@@ inside @ByteArray stays literal'
    Assert ((ConvertFrom-QtIniValue '@ByteArray(@Invalid())') -ceq '@Invalid()') '@Invalid() inside @ByteArray stays literal'
    Assert ((ConvertFrom-QtIniValue '@Invalid()') -ceq '') '@Invalid() is no value'
    Assert ((ConvertFrom-QtIniValue '\x40@foo') -ceq '@foo') 'escapes decoded before the @ forms'
    Assert ((ConvertFrom-QtIniValue '@ByteArray(\x4e00Team)') -ceq '?Team') '@ByteArray character above 255 becomes ? as in Qt'
    # Compared ordinally: -ceq uses the culture, which ignores the soft hyphen.
    Assert ([string]::Equals((ConvertFrom-QtIniValue '\x00ad@@foo'), ([string][char]0xAD + '@@foo'), [StringComparison]::Ordinal)) 'leading-@ checks are ordinal'
    Assert ((ConvertFrom-QtIniValue 'a\x0041BCz') -ceq ('a' + [char]0x41BC + 'z')) '\x reads every hex digit'
    Assert ((ConvertFrom-QtIniValue 'a\x12345z') -ceq ('a' + [char]0x2345 + 'z')) '\x keeps the low 16 bits'
    Assert ((ConvertFrom-QtIniValue 'a\101b') -ceq 'aAb') 'octal escape'
    Assert ((ConvertFrom-QtIniValue 'a\1234567') -ceq ('a' + [char]0x3977)) 'octal keeps the low 16 bits (01234567 = 0x53977)'
    Assert ((ConvertFrom-QtIniValue 'D:/a\xyz') -ceq 'D:/ayz') '\x with no hex digit is dropped'
    Assert ((ConvertFrom-QtIniValue 'abc\') -ceq 'abc') 'a lone trailing backslash is dropped'
    Assert ((ConvertFrom-QtIniValue 'a"b, c"d') -ceq 'ab, cd') 'quotes toggle anywhere; comma inside quotes stays'
    Assert ((ConvertFrom-QtIniValue '  abc  ') -ceq 'abc') 'unquoted edge spaces cut'
    Assert ((ConvertFrom-QtIniValue '"abc  "') -ceq 'abc  ') 'quoted trailing spaces kept'
    Assert ((ConvertFrom-QtIniValue '@String(x)') -ceq 'x') '@String(...)'
    Assert ((ConvertFrom-QtIniValue 'a, b') -ceq '') 'an unquoted comma makes a list, which MO2 reads as ""'
    Assert ((ConvertFrom-QtIniValue 'abc,') -ceq '') 'a trailing comma makes a list too'
    Assert ((ConvertFrom-QtIniValue 'abc  \') -ceq 'abc  ') 'a trailing backslash keeps the spaces before it'
    Assert ((ConvertFrom-QtIniValue '@Variant(\0\0\0\x7f)') -ceq '') '@Variant(...) is read as ""'
    Assert ((ConvertFrom-QtIniValue '@Point(1 2)') -ceq '') '@Point with 2 arguments is not a string'
    Assert ((ConvertFrom-QtIniValue '@Point(D:/x)') -ceq '@Point(D:/x)') '@Point with the wrong argument count stays text, as in Qt'
    Assert ((ConvertFrom-QtIniValue '@Rect(1 2 3 4)') -ceq '') '@Rect with 4 arguments is not a string'
    # Read-MO2Ini joins a line that ends in a backslash with the next one, as Qt does.
    foreach ($name in 'Split-QtIniLines', 'ConvertFrom-QtIniKey', 'Read-MO2Ini') {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    Assert ((ConvertFrom-QtIniValue '@Point(1  2)') -ceq '@Point(1  2)') '@Point keeps empty arguments as Qt does, so 3 arguments stay text'
    # Lines as Qt's readIniLine reads them: continuation, ';' comments, no '#' comments, quotes over lines.
    $iniText = "[General]`r`nselected_profile=@ByteArray(Test)`r`n[Settings]`r`n" +
               "profiles_directory=D:/Mods/x\`r`nmod_directory=E:/m`r`n" +      # continued: one value
               ";old D:\Mods\`r`noverwrite_directory=D:/ow`r`n" +              # ';' comment doesn't continue
               "download_directory=D:/dl ; moved`r`n" +                         # inline ';' ends the line
               "#note x\`r`ncache_directory=D:/c`r`n" +                          # '#' is text: continues
               "base_directory=`"D:/a`r`nb`"`r`n" +                              # line break inside quotes
               "  plugin_directory = D:/p  `r`n"                                  # spaces around key and value
    $iniC = New-File 'IniCont\ModOrganizer.ini' $iniText
    $vals = Read-MO2Ini $iniC
    Assert ($vals['settings/profiles_directory'] -ceq 'D:/Mods/xmod_directory=E:/m') "continued line joined as Qt reads it ($($vals['settings/profiles_directory']))"
    Assert (-not $vals.ContainsKey('settings/mod_directory')) 'the continued line is not a key of its own'
    Assert ($vals['settings/overwrite_directory'] -ceq 'D:/ow') "a ';' comment line ending in a backslash doesn't swallow the next line"
    Assert ($vals['settings/download_directory'] -ceq 'D:/dl') "an inline ';' ends the value ($($vals['settings/download_directory']))"
    Assert (-not $vals.ContainsKey('settings/cache_directory')) "'#' is not a comment in Qt: the line continues"
    Assert ($vals['settings/base_directory'] -ceq "D:/a`r`nb") "a quoted value runs over the line break ($($vals['settings/base_directory'] -replace "`r`n", '<CRLF>'))"
    Assert ($vals['settings/plugin_directory'] -ceq 'D:/p') 'spaces around key and value trimmed'
    Assert ($vals['selected_profile'] -ceq 'Test') '[General] key read bare'
    Assert ((ConvertFrom-QtIniValue '@Point(1)2)') -ceq '') "@Point splitArgs as Qt: ')' adds the item without clearing it"
    Assert ((ConvertFrom-QtIniKey 'a\b%41%U0042%zz%') -ceq 'a/bAB%zz%') 'keys: \ to /, %XX and %UXXXX decoded, bad % kept'
    $iniK = New-File 'IniKeys\ModOrganizer.ini' ("[General]`r`nsettings\overwrite_directory=D:/o`r`n[Sett%69ngs]`r`nprofiles_directory=D:/p`r`n" +
                                                 "[%General]`r`nx=1`r`n")
    # Read while another program holds the file open for writing, as a running MO2 may.
    $hold = [System.IO.File]::Open($iniK, 'Open', 'ReadWrite', [System.IO.FileShare]'ReadWrite, Delete')
    try { $vals = Read-MO2Ini $iniK } finally { $hold.Dispose() }
    Assert ($vals['settings/overwrite_directory'] -ceq 'D:/o') '[General] settings\key is the same key as [Settings] key'
    Assert ($vals['settings/profiles_directory'] -ceq 'D:/p') 'section names are unescaped (%69)'
    Assert ($vals['general/x'] -ceq '1') '[%General] is a real section named General'
    $iniP = New-File 'IniPrec\ModOrganizer.ini' "[Settings]`r`nprofiles_directory=D:/A`r`n[General]`r`nsettings\profiles_directory=D:/B`r`n"
    Assert ((Read-MO2Ini $iniP)['settings/profiles_directory'] -ceq 'D:/A') '[Settings] wins over [General] settings\key, as in Qt'
    $iniS = New-File 'IniSort\ModOrganizer.ini' "[Settings/Sub]`r`nx=1`r`n[Settings]`r`nsub\x=2`r`n"
    Assert ((Read-MO2Ini $iniS)['settings/sub/x'] -ceq '1') 'sections apply in sorted name order (settings/ before settings/sub/), as in Qt'
    $iniKeys = New-File 'IniKeysName\ModOrganizer.ini' "[General]`r`nkeys=k`r`nselected_profile=P`r`n"
    $vk = Read-MO2Ini $iniKeys
    Assert ($vk['selected_profile'] -ceq 'P' -and $vk['keys'] -ceq 'k') 'a key named "keys" does not break the merge'

    # ---------------- 5e: MO2 folder at a drive root (\\ in the INI) is not taken for a UNC path
    Write-Host ''
    Write-Host 'Test 5e: MO2 profiles folder at the drive root'
    New-File 'MO2root\ModOrganizer.ini' "[General]`r`nselected_profile=@ByteArray(Test)`r`n[Settings]`r`nprofiles_directory=\\sflc-no-such-root`r`n" | Out-Null
    $out5e = Join-Path $Root 'out5e'
    $r = Invoke-Collector ($common + @('-GamePath', (Join-Path $Root 'Game'), '-MO2Path', (Join-Path $Root 'MO2root'), '-OutDir', $out5e))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out5e
    Assert (@($z.manifest.warnings | Where-Object { $_ -match 'MO2 profile folder not found: [A-Z]:\\sflc-no-such-root\\Test' }).Count -eq 1) 'drive-root profiles folder read as a local path'

    # ---------------- 8: -Redact (fake user, computer and profile set for the child run)
    Write-Host ''
    Write-Host 'Test 8: -Redact'
    function Get-Sha([string]$Path) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($Path)
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLowerInvariant() }
        finally { $fs.Dispose(); $sha.Dispose() }
    }
    function New-Bytes([string]$Rel, [byte[]]$Bytes) {
        $p = Join-Path $Root $Rel
        $d = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
        [System.IO.File]::WriteAllBytes($p, $Bytes)
        return $p
    }
    function Invoke-WithEnv([hashtable]$Env, [scriptblock]$Do) {
        $old = @{}
        foreach ($k in $Env.Keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
        try { return (& $Do) } finally { foreach ($k in $old.Keys) { [Environment]::SetEnvironmentVariable($k, $old[$k]) } }
    }
    $fUser = 'Zqxuser'; $fPc = 'ZQXPC77'; $fSteam = '123456789'
    $fLeafRel = 'R\Users\Zqxuser-longprofile'
    $fProf = Join-Path $Root $fLeafRel
    [void](New-Item -ItemType Directory -Path $fProf -Force)
    $fShort = $fProf
    try { $fso = New-Object -ComObject Scripting.FileSystemObject; $fShort = $fso.GetFolder($fProf).ShortPath.TrimEnd('\') } catch { }
    $fSlash = $fProf -replace '\\', '/'
    $fJson = $fProf -replace '\\', '\\'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $docsRel = "$fLeafRel\Documents\My Games\Starfield"
    $papText = "Papyrus log opened (PC-64)`r`nscript at $fProf\Documents\x.pex`r`nuser $fUser on $fPc, not ${fUser}s or x$fPc`r`n" +
               "steam C:\Program Files (x86)\Steam\userdata\$fSteam\760`r`nMyMod.esm 0x01000ABC SomeQuest`r`nbackup in D:\Old\Zqxuser-longprofile\saves`r`n"
    $pap8 = New-File "$docsRel\Logs\Script\Papyrus.0.log" $papText
    New-File "$docsRel\StarfieldCustom.ini" "[Papyrus]`r`nbEnableLogging=1`r`nsPath=$fSlash/Documents`r`n" | Out-Null
    $vtx8 = New-File "$fLeafRel\Downloads\vortex-starfield-default-backup-20261119.json" ('{"path":"' + $fJson + '\\Downloads\\a.zip","machine":"' + $fPc + '"}')
    New-File "$docsRel\SFSE\Logs\report.zzz" "unknown extension at $fProf\x`r`n" | Out-Null
    New-File "$docsRel\SFSE\Logs\short.txt" "temp $fShort\AppData\Local\Temp\x.tmp`r`n" | Out-Null
    $plain8 = New-File "$docsRel\SFSE\Logs\plain.txt" "nothing private here`r`n"
    $wide = New-Object System.Text.StringBuilder
    [void]$wide.Append("start $fProf\a on $fPc`r`n")
    for ($i = 0; $i -lt 90000; $i++) { [void]$wide.Append("filler line $i of the wide log`r`n") }
    [void]$wide.Append("end $fProf\b`r`n")
    $wide8 = Join-Path $Root "$docsRel\SFSE\Logs\wide.log"
    [System.IO.File]::WriteAllText($wide8, $wide.ToString(), [System.Text.Encoding]::Unicode)   # UTF-16 LE with BOM, over 4 MB
    $big = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt 300000; $i++) {
        if ($i % 50000 -eq 0) { [void]$big.Append("hit $i $fProf\c by $fUser`n") }
        [void]$big.Append("filler line $i of the big log`n")
    }
    $big8 = New-File "$docsRel\SFSE\Logs\big.log" $big.ToString()                          # several 4 MB pieces
    $bom8 = Join-Path $Root "$docsRel\SFSE\Logs\bom.txt"
    [System.IO.File]::WriteAllText($bom8, "bom $fProf\d`r`n", (New-Object System.Text.UTF8Encoding($true)))
    $ansiBytes = [byte[]](@([byte][char]'c', [byte][char]'a', [byte][char]'f', 0xE9, 32) + [System.Text.Encoding]::ASCII.GetBytes("$fProf\e`r`n"))
    $ansi8 = New-Bytes "$docsRel\SFSE\Logs\ansi.txt" $ansiBytes
    # A crash-cut log ending in zero padding, and a UTF-16 LE text file without a byte-order mark.
    $nulBytes = [byte[]]([System.Text.Encoding]::ASCII.GetBytes("[11/24/2026 - 10:00:00PM] error: File `"$fProf\Documents\My Games\Starfield\Data\Scripts\x.pex`" not found`r`n") + (New-Object byte[] 4096))
    New-Bytes "$docsRel\SFSE\Logs\cut.log" $nulBytes | Out-Null
    New-Bytes "$docsRel\SFSE\Logs\nobom.txt" ([System.Text.Encoding]::Unicode.GetBytes("nobom $fProf\f on $fPc`r`n")) | Out-Null
    $blob8 = New-Bytes "$docsRel\SFSE\Logs\blob.bin" ([byte[]](@(0, 1, 2) + [System.Text.Encoding]::ASCII.GetBytes($fProf)))
    $save8 = New-File "$fLeafRel\Saves\Save1_ABCD1234_000102_20261119100000_1_2.sfs" "save at $fProf by $fUser"
    $shot8 = New-File "$fLeafRel\Shots\s.png" "png at $fProf"
    $args8 = @('-NoPrompt', '-Hours', '2', '-MyGamesDir', (Join-Path $Root $docsRel), '-PluginsTxtDir', (Join-Path $fProf 'AppData\Local\Starfield'),
        '-DownloadsDir', (Join-Path $fProf 'Downloads'), '-ScreenshotDir', (Join-Path $fProf 'Shots'), '-SavesDir', (Join-Path $fProf 'Saves'),
        '-IncludeSaves', '-GamePath', (Join-Path $Root 'Game'), '-Note', "redact check by $fUser", '-DryRun')
    $env8 = @{ USERPROFILE = $fProf; USERNAME = $fUser; COMPUTERNAME = $fPc }
    $out8 = Join-Path $Root 'out8'
    $log8 = Join-Path $Root 'run8.log'
    $r = Invoke-WithEnv $env8 { Invoke-Collector ($args8 + @('-Redact', '-OutDir', $out8, '-LogFile', $log8)) }
    Assert ($r.code -eq 0) "-Redact run exit code 0 (got $($r.code))"
    if ($r.code -ne 0) { Write-Host $r.text }
    $secretRx = @(
        ('(?i)' + [regex]::Escape($fProf)), ('(?i)' + [regex]::Escape($fSlash)), ('(?i)' + [regex]::Escape($fJson)),
        ('(?i)' + [regex]::Escape($fShort)), ('(?i)(?<!\w)' + $fUser + '(?!\w)'), ('(?i)(?<!\w)' + $fPc + '(?!\w)'),
        ('(?i)Zqxuser-longprofile'), $fSteam)
    $z8 = $null
    if (@(Get-ChildItem -LiteralPath $out8 -Filter '*.zip' -ErrorAction SilentlyContinue).Count -gt 0) { $z8 = Open-Zip $out8 }
    $leftAlone = @('saves/Save1_ABCD1234_000102_20261119100000_1_2.sfs', 'screenshots/s.png', 'docs/SFSE/Logs/blob.bin')
    if ($z8) {
        $leaks = @()
        foreach ($name in $z8.names) {
            if ($leftAlone -contains $name) { continue }
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $z8.dir $name))
            $text = $(if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [System.Text.Encoding]::Unicode.GetString($bytes) }
                      else { [System.Text.Encoding]::GetEncoding(28591).GetString($bytes) })
            foreach ($rx in $secretRx) { if ($text -match $rx) { $leaks += "$name ($rx)" } }
        }
        Assert ($leaks.Count -eq 0) "no fake user, computer, profile or Steam ID in any text entry ($($leaks -join '; '))"
        Assert ($z8.names.Count -ge 15) "the redacted zip has the files ($($z8.names.Count))"
        $p8 = [System.IO.File]::ReadAllText((Join-Path $z8.dir 'docs\Logs\Script\Papyrus.0.log'))
        Assert ($p8.Contains('script at %USERPROFILE%\Documents\x.pex')) 'profile path becomes %USERPROFILE%'
        Assert ($p8.Contains('user <user> on <computer>, not Zqxusers or xZQXPC77')) 'names become <user> and <computer>, whole words only'
        Assert ($p8.Contains('userdata\<steam-id>\760')) 'Steam account folder becomes userdata\<steam-id>'
        Assert ($p8.Contains('MyMod.esm 0x01000ABC SomeQuest')) 'plugin names and form IDs untouched'
        Assert ($p8.Contains('D:\Old\<user>\saves')) 'profile folder name elsewhere becomes <user>'
        Assert ([System.IO.File]::ReadAllText((Join-Path $z8.dir 'docs\StarfieldCustom.ini')).Contains('sPath=%USERPROFILE%/Documents')) 'forward-slash form hidden'
        Assert ([System.IO.File]::ReadAllText((Join-Path $z8.dir 'vortex\vortex-starfield-default-backup-20261119.json')).Contains('"path":"%USERPROFILE%\\Downloads\\a.zip","machine":"<computer>"')) 'JSON \\ form hidden'
        Assert ([System.IO.File]::ReadAllText((Join-Path $z8.dir 'docs\SFSE\Logs\report.zzz')).Contains('%USERPROFILE%\x')) 'a file with an unknown extension under SFSE\Logs is redacted'
        if ($fShort -ne $fProf) { Assert ([System.IO.File]::ReadAllText((Join-Path $z8.dir 'docs\SFSE\Logs\short.txt')).Contains('temp %USERPROFILE%\AppData')) '8.3 short form hidden' }
        else { Write-Host '  skip 8.3 check (this volume makes no short names)' }
        $wb = [System.IO.File]::ReadAllBytes((Join-Path $z8.dir 'docs\SFSE\Logs\wide.log'))
        $wt = [System.Text.Encoding]::Unicode.GetString($wb, 2, $wb.Length - 2)
        Assert ($wb[0] -eq 0xFF -and $wb[1] -eq 0xFE -and $wt.StartsWith("start %USERPROFILE%\a on <computer>`r`n") -and $wt.EndsWith("end %USERPROFILE%\b`r`n")) 'UTF-16 file keeps its byte-order mark and is redacted'
        Assert (([regex]::Matches($wt, 'filler line \d+ of the wide log')).Count -eq 90000) 'UTF-16 file over 4 MB keeps every line'
        $bt = [System.IO.File]::ReadAllText((Join-Path $z8.dir 'docs\SFSE\Logs\big.log'))
        Assert (([regex]::Matches($bt, 'hit \d+ %USERPROFILE%\\c by <user>')).Count -eq 6 -and ([regex]::Matches($bt, "`n")).Count -eq 300006) 'big file redacted across 4 MB pieces, every line kept'
        $bb = [System.IO.File]::ReadAllBytes((Join-Path $z8.dir 'docs\SFSE\Logs\bom.txt'))
        Assert ($bb[0] -eq 0xEF -and $bb[1] -eq 0xBB -and $bb[2] -eq 0xBF -and $utf8.GetString($bb, 3, $bb.Length - 3) -eq "bom %USERPROFILE%\d`r`n") 'UTF-8 byte-order mark kept'
        $ab = [System.IO.File]::ReadAllBytes((Join-Path $z8.dir 'docs\SFSE\Logs\ansi.txt'))
        $want = [byte[]](@([byte][char]'c', [byte][char]'a', [byte][char]'f', 0xE9, 32) + [System.Text.Encoding]::ASCII.GetBytes("%USERPROFILE%\e`r`n"))
        Assert ([System.BitConverter]::ToString($ab) -eq [System.BitConverter]::ToString($want)) 'a non-UTF-8 byte (Latin-1) is kept as it was'
        Assert ((Get-Sha (Join-Path $z8.dir 'docs\SFSE\Logs\plain.txt')) -eq (Get-Sha $plain8)) 'a file with nothing to hide stays byte-identical'
        Assert ((Get-Sha (Join-Path $z8.dir 'docs\SFSE\Logs\blob.bin')) -eq (Get-Sha $blob8)) 'a binary-looking file is left as it is'
        $cb = [System.IO.File]::ReadAllBytes((Join-Path $z8.dir 'docs\SFSE\Logs\cut.log'))
        $ct = [System.Text.Encoding]::GetEncoding(28591).GetString($cb)
        Assert ($ct.StartsWith("[11/24/2026 - 10:00:00PM] error: File `"%USERPROFILE%\Documents\My Games\Starfield\Data\Scripts\x.pex`" not found`r`n") -and $ct.EndsWith([string][char]0 * 4096)) 'a .log ending in zero padding (Papyrus-style line) is redacted and keeps its padding'
        $nb = [System.IO.File]::ReadAllBytes((Join-Path $z8.dir 'docs\SFSE\Logs\nobom.txt'))
        Assert ([System.Text.Encoding]::Unicode.GetString($nb) -eq "nobom %USERPROFILE%\f on <computer>`r`n") 'a UTF-16 .txt without a byte-order mark is redacted'
        Assert ((Get-Sha (Join-Path $z8.dir 'saves\Save1_ABCD1234_000102_20261119100000_1_2.sfs')) -eq (Get-Sha $save8)) 'the save is left as it is'
        Assert ((Get-Sha (Join-Path $z8.dir 'screenshots\s.png')) -eq (Get-Sha $shot8)) 'the screenshot is left as it is'
        $m8 = $z8.manifest
        Assert ($m8.redact -eq $true) 'manifest says redact: true'
        Assert ($m8.note -eq 'redact check by <user>') "the note is redacted in the manifest ($($m8.note))"
        $pe = @($m8.files | Where-Object { $_.package -eq 'docs/Logs/Script/Papyrus.0.log' })[0]
        $pz = Join-Path $z8.dir 'docs\Logs\Script\Papyrus.0.log'
        Assert ($pe.redacted -eq $true -and $pe.sourceSize -eq (Get-Item -LiteralPath $pap8).Length -and $pe.size -eq (Get-Item -LiteralPath $pz).Length -and $pe.sha256 -eq (Get-Sha $pz)) 'manifest: redacted, sourceSize, and size and sha256 of the zip copy'
        $ple = @($m8.files | Where-Object { $_.package -eq 'docs/SFSE/Logs/plain.txt' })[0]
        Assert ($null -eq $ple.redacted -and $null -eq $ple.sourceSize) 'manifest: an unchanged file has no redacted fields'
        Assert (@($m8.files | Where-Object { $_.source -notmatch '^(%USERPROFILE%|[A-Za-z]:\\)' }).Count -eq 0 -and @($m8.files | Where-Object { $_.source -like '%USERPROFILE%*' }).Count -ge 10) 'manifest sources start with %USERPROFILE%'
        $cl8 = [System.IO.File]::ReadAllText((Join-Path $z8.dir 'collector-log.txt'))
        Assert ($cl8 -match 'redact: docs/Logs/Script/Papyrus\.0\.log \(\d+ replacements\)' -and $cl8 -match 'redact: left as is \(does not look like text\): docs/SFSE/Logs/blob\.bin') 'collector log counts replacements per file and names the left-alone file'
        Assert ($cl8 -match '\.last-run-%USERNAME%') 'collector log still names the marker as .last-run-%USERNAME%'
    } else { Assert $false 'the -Redact run made a zip' }
    $l8 = $(if (Test-Path -LiteralPath $log8) { [System.IO.File]::ReadAllText($log8) } else { $fUser })
    Assert (-not (@($secretRx | Where-Object { $l8 -match $_ }).Count)) 'the -LogFile copy has no fake user, computer or profile'
    Assert ($r.text -match 'Redacted: \d+ file\(s\) changed; saves and screenshots left as they are') 'summary has the Redacted line'

    # 8b: the same files without -Redact are copied exactly as they are
    $out8b = Join-Path $Root 'out8b'
    $r = Invoke-WithEnv $env8 { Invoke-Collector ($args8 + @('-OutDir', $out8b)) }
    Assert ($r.code -eq 0) "run without -Redact exit code 0 (got $($r.code))"
    $z8b = Open-Zip $out8b
    $same = $true
    foreach ($pair in @(@('docs/Logs/Script/Papyrus.0.log', $pap8), @('vortex/vortex-starfield-default-backup-20261119.json', $vtx8),
                        @('docs/SFSE/Logs/wide.log', $wide8), @('docs/SFSE/Logs/big.log', $big8), @('docs/SFSE/Logs/ansi.txt', $ansi8))) {
        $e = @($z8b.manifest.files | Where-Object { $_.package -eq $pair[0] })[0]
        if (-not $e -or $e.sha256 -ne (Get-Sha $pair[1]) -or (Get-Sha (Join-Path $z8b.dir $pair[0])) -ne (Get-Sha $pair[1])) { $same = $false }
    }
    Assert $same 'without -Redact the copies are byte-identical to the originals'
    Assert ($z8b.manifest.redact -eq $false -and @($z8b.manifest.files | Where-Object { $_.redacted }).Count -eq 0) 'without -Redact: redact false, no file marked redacted'
    Assert (-not ($r.text -match 'Redacted:')) 'without -Redact: no Redacted line'

    # 8c: a two-letter user name is hidden only in \Users\<name> paths
    $sProf = Join-Path $Root 'S\Users\zq'
    [void](New-Item -ItemType Directory -Path $sProf -Force)
    New-File 'S\MyGames\Logs\Script\Papyrus.0.log' "UI zq button`r`nfile D:\Users\zq\x.txt`r`n" | Out-Null
    New-File 'S\MyGames\StarfieldCustom.ini' "[Papyrus]`r`nbEnableLogging=1`r`n" | Out-Null
    $out8c = Join-Path $Root 'out8c'
    $r = Invoke-WithEnv @{ USERPROFILE = $sProf; USERNAME = 'zq'; COMPUTERNAME = $fPc } {
        Invoke-Collector @('-NoPrompt', '-Hours', '2', '-MyGamesDir', (Join-Path $Root 'S\MyGames'), '-PluginsTxtDir', (Join-Path $Root 'S\none'),
            '-DownloadsDir', (Join-Path $Root 'S\none'), '-ScreenshotDir', (Join-Path $Root 'S\none'), '-GamePath', (Join-Path $Root 'Game'),
            '-Redact', '-DryRun', '-OutDir', $out8c) }
    Assert ($r.code -eq 0) "two-letter name run exit code 0 (got $($r.code))"
    $p8c = ''; $l8c = ''
    if (@(Get-ChildItem -LiteralPath $out8c -Filter '*.zip' -ErrorAction SilentlyContinue).Count -gt 0) {
        $z8c = Open-Zip $out8c
        $p8c = [System.IO.File]::ReadAllText((Join-Path $z8c.dir 'docs\Logs\Script\Papyrus.0.log'))
        $l8c = [System.IO.File]::ReadAllText((Join-Path $z8c.dir 'collector-log.txt'))
    }
    Assert ($p8c -eq "UI zq button`r`nfile D:\Users\<user>\x.txt`r`n") "two-letter name replaced only in the path ($($p8c.Trim() -replace "`r`n", ' | '))"
    Assert ($l8c -match 'under 3 characters') 'collector log says the short name is hidden only in paths'

    # 8e: a user name with a letter outside English, in a UTF-8 log with one invalid byte (read as Latin-1)
    $nUser = 'Zqx' + [char]0xE9 + 'ra'
    $nProf = Join-Path $Root "N\Users\$nUser"
    [void](New-Item -ItemType Directory -Path $nProf -Force)
    New-File 'N\MyGames\StarfieldCustom.ini' "[Papyrus]`r`nbEnableLogging=1`r`n" | Out-Null
    $nTail = [byte[]](@(0xFF) + [System.Text.Encoding]::ASCII.GetBytes("`r`n"))
    New-Bytes 'N\MyGames\Logs\Script\Papyrus.0.log' ([byte[]]($utf8.GetBytes("file $nProf\x.txt by $nUser`r`n") + $nTail)) | Out-Null
    $out8e = Join-Path $Root 'out8e'
    $r = Invoke-WithEnv @{ USERPROFILE = $nProf; USERNAME = $nUser; COMPUTERNAME = $fPc } {
        Invoke-Collector @('-NoPrompt', '-Hours', '2', '-MyGamesDir', (Join-Path $Root 'N\MyGames'), '-PluginsTxtDir', (Join-Path $Root 'N\none'),
            '-DownloadsDir', (Join-Path $Root 'N\none'), '-ScreenshotDir', (Join-Path $Root 'N\none'), '-GamePath', (Join-Path $Root 'Game'),
            '-Redact', '-DryRun', '-OutDir', $out8e) }
    Assert ($r.code -eq 0) "non-English name run exit code 0 (got $($r.code))"
    $p8e = $null
    if (@(Get-ChildItem -LiteralPath $out8e -Filter '*.zip' -ErrorAction SilentlyContinue).Count -gt 0) {
        $p8e = [System.IO.File]::ReadAllBytes((Join-Path (Open-Zip $out8e).dir 'docs\Logs\Script\Papyrus.0.log'))
    }
    $want8e = [byte[]]([System.Text.Encoding]::ASCII.GetBytes("file %USERPROFILE%\x.txt by <user>`r`n") + $nTail)
    Assert ($p8e -and [System.BitConverter]::ToString($p8e) -eq [System.BitConverter]::ToString($want8e)) 'a UTF-8 name with a letter outside English is hidden in a file that is not valid UTF-8, and the bad byte is kept'

    # 8f: a computer name that holds the user name is <computer> whole; a plugin named after the user is
    # <user>.esm in the manifest's listing too
    $mUser = 'Zqxmike'
    $mProf = Join-Path $Root "M\Users\$mUser"
    [void](New-Item -ItemType Directory -Path $mProf -Force)
    New-File 'M\MyGames\StarfieldCustom.ini' "[Papyrus]`r`nbEnableLogging=1`r`n" | Out-Null
    New-File 'M\MyGames\Logs\Script\Papyrus.0.log' "Computer: ZQXMIKE-PC`r`n" | Out-Null
    New-File 'M\Game\Starfield.exe' 'not a real exe' | Out-Null
    New-File "M\Game\Data\$mUser.esm" 'plugin' | Out-Null
    $out8f = Join-Path $Root 'out8f'
    $r = Invoke-WithEnv @{ USERPROFILE = $mProf; USERNAME = $mUser; COMPUTERNAME = 'ZQXMIKE-PC' } {
        Invoke-Collector @('-NoPrompt', '-Hours', '2', '-MyGamesDir', (Join-Path $Root 'M\MyGames'), '-PluginsTxtDir', (Join-Path $Root 'M\none'),
            '-DownloadsDir', (Join-Path $Root 'M\none'), '-ScreenshotDir', (Join-Path $Root 'M\none'), '-GamePath', (Join-Path $Root 'M\Game'),
            '-Redact', '-DryRun', '-OutDir', $out8f) }
    Assert ($r.code -eq 0) "user-in-computer-name run exit code 0 (got $($r.code))"
    $p8f = ''; $dp8f = @()
    if (@(Get-ChildItem -LiteralPath $out8f -Filter '*.zip' -ErrorAction SilentlyContinue).Count -gt 0) {
        $z8f = Open-Zip $out8f
        $p8f = [System.IO.File]::ReadAllText((Join-Path $z8f.dir 'docs\Logs\Script\Papyrus.0.log'))
        $dp8f = @($z8f.manifest.listing.dataPlugins | ForEach-Object { $_.name })
    }
    Assert ($p8f -eq "Computer: <computer>`r`n") "a computer name holding the user name becomes <computer> ($($p8f.Trim()))"
    Assert ($dp8f -contains '<user>.esm' -and -not ($dp8f -contains "$mUser.esm")) "manifest listing hides a plugin named after the user ($($dp8f -join ', '))"

    # 8d: double-click: the new question turns -Redact on with y and stays off with Enter
    $out8d = Join-Path $Root 'out8d'
    $ask = @('-Hours', '2', '-MyGamesDir', (Join-Path $Root 'S\MyGames'), '-PluginsTxtDir', (Join-Path $Root 'S\none'),
        '-DownloadsDir', (Join-Path $Root 'S\none'), '-ScreenshotDir', (Join-Path $Root 'S\none'), '-GamePath', (Join-Path $Root 'Game'),
        '-Note', 'asked', '-IncludeSaves', '-SavesDir', (Join-Path $Root 'S\none'), '-DryRun', '-OutDir', $out8d)
    function Invoke-Asked([string]$Answer) {
        $ErrorActionPreference = 'Continue'
        $o = $Answer | & $Shell -NoProfile -ExecutionPolicy Bypass -File $Collector @ask 2>&1 | Out-String
        $c = $LASTEXITCODE
        $red = $null
        $zp = @(Get-ChildItem -LiteralPath $out8d -Filter '*.zip' -ErrorAction SilentlyContinue)
        if ($zp.Count -gt 0) { $red = (Open-Zip $out8d).manifest.redact; Remove-Item -LiteralPath $out8d -Recurse -Force }
        return @{ code = $c; text = $o; redact = $red }
    }
    $a = Invoke-Asked "y`n"
    Assert ($a.code -eq 0 -and $a.text -match 'Redacted:' -and $a.redact -eq $true) "answering y to the question turns -Redact on (exit $($a.code), manifest redact $($a.redact))"
    $a = Invoke-Asked "`n"
    Assert ($a.code -eq 0 -and $a.redact -eq $false -and -not ($a.text -match 'Redacted:')) "Enter at the question leaves -Redact off (exit $($a.code), manifest redact $($a.redact))"

    # ---------------- 6: the launcher passes the exit code on
    Write-Host ''
    Write-Host 'Test 6: .cmd launcher'
    $cmd = Join-Path (Split-Path $PSScriptRoot -Parent) 'Collect-StarfieldTestLogs.cmd'
    $out6 = Join-Path $Root 'out6'
    $q = { param($p) '"' + (Join-Path $Root $p) + '"' }
    $fake = "-MyGamesDir $(& $q 'MyGames') -PluginsTxtDir $(& $q 'LocalApp\Starfield') -DownloadsDir $(& $q 'Downloads') " +
            "-ScreenshotDir $(& $q 'Shots') -SavesDir $(& $q 'Saves') -GamePath $(& $q 'Game')"
    $null = cmd.exe /c "echo.| `"$cmd`" -NoPrompt -Hours 1 $fake -OutDir `"$out6`" >nul 2>&1"
    Assert ($LASTEXITCODE -eq 0) "launcher exit code 0 (got $LASTEXITCODE)"
    Assert (@(Get-ChildItem -LiteralPath $out6 -Filter '*.zip' -ErrorAction SilentlyContinue).Count -eq 1) 'launcher made a zip'
    $null = cmd.exe /c "echo.| `"$cmd`" -NoSuchOption $fake -OutDir `"$out6`" >nul 2>&1"
    Assert ($LASTEXITCODE -ne 0) "launcher passes a failure on (got $LASTEXITCODE)"

    # ---------------- 7: this harness's own -Shell handling (via -ResolveOnly)
    Write-Host ''
    Write-Host 'Test 7: harness -Shell'
    function Invoke-Self([string[]]$A = @()) {
        $o = & $Shell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @A -ResolveOnly 2>&1 | Out-String
        return @{ code = $LASTEXITCODE; text = $o }
    }
    $r = Invoke-Self
    Assert ($r.code -eq 0 -and $r.text -match 'Shell    : .+, the default for this host') "default shell is named as the default ($($r.text.Trim()))"
    $exeDir = Split-Path $Shell -Parent
    $long = '\\?\' + $exeDir + '\..\' + (Split-Path $exeDir -Leaf) + '\' + (Split-Path $Shell -Leaf)
    $r = Invoke-Self @('-Shell', $long)
    Assert ($r.code -eq 0) "\\?\ path with .. accepted (got $($r.code): $($r.text.Trim()))"
    Assert ($r.text -match ('Shell    : ' + [regex]::Escape($Shell) + ' \(')) 'the \\?\ prefix is dropped and .. resolved'
    $r = Invoke-Self @('-Shell', ('\\?\' + $exeDir + '\..\sflc-no-such-dir\' + (Split-Path $Shell -Leaf)))
    Assert ($r.code -eq 1 -and $r.text -match 'not found') "missing \\?\ path reported as not found (got $($r.code))"
    $r = Invoke-Self @('-Shell', ('\\.\' + $exeDir + '\..\' + (Split-Path $exeDir -Leaf) + '\' + (Split-Path $Shell -Leaf)))
    Assert ($r.code -eq 0 -and $r.text -match ('Shell    : ' + [regex]::Escape($Shell) + ' \(')) "\\.\ prefix handled like \\?\ (got $($r.code))"
    $r = Invoke-Self @('-Shell', ('\\?\' + $exeDir.Substring(0, 2) + (Split-Path $Shell -Leaf)))
    # PowerShell 7 already refuses it at the name check ("not accepted"); 5.1 reaches the full-path check.
    Assert ($r.code -eq 1 -and $r.text -match 'not a full drive or network path|is not accepted') "drive-relative path after \\?\ refused (got $($r.code))"
} finally {
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:Passes passed, $script:Failures failed"
if ($script:Failures -gt 0) { exit 1 }
exit 0
