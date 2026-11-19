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

    # ---------------- 5e: MO2 folder at a drive root (\\ in the INI) is not taken for a UNC path
    Write-Host ''
    Write-Host 'Test 5e: MO2 profiles folder at the drive root'
    New-File 'MO2root\ModOrganizer.ini' "[General]`r`nselected_profile=@ByteArray(Test)`r`n[Settings]`r`nprofiles_directory=\\sflc-no-such-root`r`n" | Out-Null
    $out5e = Join-Path $Root 'out5e'
    $r = Invoke-Collector ($common + @('-GamePath', (Join-Path $Root 'Game'), '-MO2Path', (Join-Path $Root 'MO2root'), '-OutDir', $out5e))
    Assert ($r.code -eq 0) "exit code 0 (got $($r.code))"
    $z = Open-Zip $out5e
    Assert (@($z.manifest.warnings | Where-Object { $_ -match 'MO2 profile folder not found: [A-Z]:\\sflc-no-such-root\\Test' }).Count -eq 1) 'drive-root profiles folder read as a local path'

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
} finally {
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:Passes passed, $script:Failures failed"
if ($script:Failures -gt 0) { exit 1 }
exit 0
