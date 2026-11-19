# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Richard Bejtlich
<#
.SYNOPSIS
    Collects Starfield logs, settings and (optionally) saves into one zip you can send to a mod author.

.DESCRIPTION
    Run it after a play session, after quitting Starfield (double-click
    Collect-StarfieldTestLogs.cmd). It copies the text logs, reports and settings that
    changed since the last run, writes manifest.json and collector-log.txt, and zips
    everything into one file.

    It only reads from the game and your profile. It never copies game code or
    binaries (.exe .dll .pdb .dmp .esm .esp .esl .ba2), never changes the game and
    makes no network connections.

    Works in Windows PowerShell 5.1 and PowerShell 7. Steam, Game Pass (Xbox app),
    Vortex and Mod Organizer 2 setups are supported.

.PARAMETER Note
    What you tested (asked for if not given). Goes into the zip name and manifest.
.PARAMETER Hours
    Collect files changed in the last N hours instead of "since the last run".
    The first run uses 12 hours.
.PARAMETER IncludeSaves
    Also copy the newest save(s). Asked for if not given.
.PARAMETER SaveCount
    How many of the newest saves to copy with -IncludeSaves (default 1).
.PARAMETER SavePair
    Copy a before/after pair: the two newest manual saves (Save<N>_..., not
    Autosave/Quicksave/Exitsave) of the character in the newest manual save.
.PARAMETER SavesDir
    Saves folder (default Documents\My Games\Starfield\Saves).
.PARAMETER IncludeLarge
    Also copy report files over 50 MB.
.PARAMETER GamePath
    Starfield install folder (the one with Starfield.exe). Found by itself for Steam
    libraries and Game Pass's <drive>:\XboxGames\Starfield\Content.
.PARAMETER MO2Path
    Mod Organizer 2 instance folder (the one with ModOrganizer.ini). Adds the
    profile's plugins.txt, loadorder.txt, modlist.txt and INIs, and the SFSE
    reports and settings in MO2's overwrite folder.
.PARAMETER MO2Profile
    MO2 profile to read (default: the profile selected in ModOrganizer.ini).
.PARAMETER ScreenshotDir
    Folder(s) to pick up new screenshots from, several as "dir1;dir2". Default:
    Steam's Starfield screenshots and Starfield's photo-mode folder.
.PARAMETER VortexExportDir
    Folder where Vortex Modlist Backup exports are saved (default: Downloads).
.PARAMETER DownloadsDir
    Downloads folder, for console transcripts (default: your Downloads).
.PARAMETER MyGamesDir
    Documents\My Games\Starfield, if yours is somewhere else.
.PARAMETER PluginsTxtDir
    Folder with the game's plugins.txt (default %LOCALAPPDATA%\Starfield).
.PARAMETER OutDir
    Where the zip goes (default Documents\StarfieldLogs).
.PARAMETER LogFile
    Also write the troubleshooting log to this file (it is always inside the zip).
.PARAMETER NoPrompt
    Ask no questions; use the defaults.
.PARAMETER DryRun
    Build the zip but don't update the "last run" marker.
#>
[CmdletBinding()]
param(
    [string]$Note = '',
    [double]$Hours = 0,
    [switch]$IncludeSaves,
    [int]$SaveCount = 1,
    [switch]$SavePair,
    [string]$SavesDir = '',
    [switch]$IncludeLarge,
    [string]$GamePath = '',
    [string]$MO2Path = '',
    [string]$MO2Profile = '',
    [string[]]$ScreenshotDir = @(),
    [string]$VortexExportDir = '',
    [string]$DownloadsDir = '',
    [string]$MyGamesDir = '',
    [string]$PluginsTxtDir = '',
    [string]$OutDir = '',
    [string]$LogFile = '',
    [switch]$NoPrompt,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2.0.0'
$LargeLimit = 50MB
$MaxScreenshots = 40
$BlockedExt = @('.exe', '.dll', '.pdb', '.dmp', '.esm', '.esp', '.esl', '.ba2')
$StarfieldSteamAppId = '1716740'
$GamePassPackage = 'BethesdaSoftworks.ProjectGold_3275kfvn8vcwc'

# ---------------------------------------------------------------- helpers
$script:Collected = New-Object System.Collections.ArrayList
$script:Warnings = New-Object System.Collections.ArrayList
$script:Skipped = New-Object System.Collections.ArrayList
$script:LogLines = New-Object System.Collections.ArrayList
$script:Stage = $null
$script:Since = $null

# Hide the Windows user folder in what we write, so a shared zip doesn't carry it in every path.
$script:ProfileRx = $null
# The lookahead stops C:\Users\a from matching inside C:\Users\ab or C:\Users\a.b, but still matches
# before a backslash, punctuation, a line break or the end of the text.
if ($env:USERPROFILE) {
    $profForms = @($env:USERPROFILE.TrimEnd('\'))
    # The 8.3 short form (C:\Users\RICHAR~1) shows up in %TEMP% paths inside logs.
    $script:ShortPathNote = $null
    $fso = $null
    $folder = $null
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        $folder = $fso.GetFolder($env:USERPROFILE)
        $profForms += $folder.ShortPath.TrimEnd('\')
    } catch {
        $script:ShortPathNote = "could not get the short (8.3) form of the user folder, so only the long form is hidden: $($_.Exception.Message)"
    } finally {
        foreach ($com in @($folder, $fso)) { if ($com) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($com) } }
    }
    $alts = @($profForms | Select-Object -Unique | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $script:ProfileRx = '(?i)(?:' + $alts + ')(?!\.?[\w~-])'
}
# The marker file carries the Windows user name: .last-run-<user>.
$script:MarkerRx = $null
if ($env:USERNAME) { $script:MarkerRx = '(?i)\.last-run-' + [regex]::Escape($env:USERNAME) + '(?![\w~-])' }
function Hide-Path([string]$Text) {
    if ($null -eq $Text) { return $null }
    if ($script:ProfileRx) { $Text = $Text -replace $script:ProfileRx, '%USERPROFILE%' }
    if ($script:MarkerRx) { $Text = $Text -replace $script:MarkerRx, '.last-run-%USERNAME%' }
    return $Text
}

function Write-Log([string]$Text) {
    $line = '{0} {1}' -f (Get-Date).ToString('HH:mm:ss.fff'), (Hide-Path $Text)
    [void]$script:LogLines.Add($line)
    Write-Verbose $Text
}

function Add-Warning([string]$Text) {
    [void]$script:Warnings.Add((Hide-Path $Text))
    Write-Log "WARNING: $Text"
    Write-Host "  ! $Text" -ForegroundColor Yellow
}

function Copy-ToPackage {
    param([System.IO.FileInfo]$File, [string]$Dest, [switch]$NoSizeLimit)
    if ($BlockedExt -contains $File.Extension.ToLowerInvariant()) {
        [void]$script:Skipped.Add((Hide-Path "$($File.FullName) (binary/game file, never copied)"))
        Write-Log "skip (blocked type): $($File.FullName)"
        return $false
    }
    if (-not $NoSizeLimit -and -not $IncludeLarge -and $File.Length -gt $LargeLimit) {
        [void]$script:Skipped.Add((Hide-Path "$($File.FullName) ($([math]::Round($File.Length / 1MB)) MB; rerun with -IncludeLarge to include)"))
        Write-Log "skip (over 50 MB): $($File.FullName)"
        return $false
    }
    $target = Join-Path $script:Stage $Dest
    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path -LiteralPath $targetDir)) { [void](New-Item -ItemType Directory -Path $targetDir -Force) }
    try {
        # Open with full sharing so files the game still holds open can be read.
        $in = [System.IO.File]::Open($File.FullName, 'Open', 'Read', 'ReadWrite, Delete')
        try {
            $out = [System.IO.File]::Create($target)
            try { $in.CopyTo($out) } finally { $out.Dispose() }
        } finally { $in.Dispose() }
        (Get-Item -LiteralPath $target).LastWriteTime = $File.LastWriteTime
        # .NET rather than Get-FileHash: 5.1 started from PowerShell 7 can fail to load that cmdlet.
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($target)
        try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLowerInvariant() }
        finally { $fs.Dispose(); $sha.Dispose() }
        [void]$script:Collected.Add([ordered]@{
            package  = ($Dest -replace '\\', '/')
            source   = (Hide-Path $File.FullName)
            size     = $File.Length
            modified = $File.LastWriteTime.ToString('s')
            sha256   = $hash
        })
        Write-Log "copy: $($File.FullName) -> $Dest ($($File.Length) bytes)"
        return $true
    } catch {
        Add-Warning "Could not copy $($File.FullName): $($_.Exception.Message) (close the program that has it open, or run as the Windows user who plays)"
        return $false
    }
}

# Copy files from a folder. -Always ignores the time window (except names matching -AlwaysExcept).
function Copy-Matching {
    param([string]$Folder, [string[]]$Patterns, [string]$DestFolder, [switch]$Always, [switch]$Recurse, [string]$AlwaysExcept = '')
    if (-not $Folder) { return 0 }
    $exists = $false
    try { $exists = Test-Path -LiteralPath $Folder -ErrorAction Stop } catch { Write-Log "cannot open folder: $Folder ($($_.Exception.Message))" }
    if (-not $exists) { Write-Log "not found: $Folder"; return 0 }
    # Same spelling as Get-ChildItem's FullName, so the relative path below comes out right.
    $Folder = (Get-Item -LiteralPath $Folder).FullName
    $count = 0
    foreach ($p in $Patterns) {
        $files = @(Get-ChildItem -LiteralPath $Folder -Filter $p -File -Recurse:$Recurse -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $useWindow = (-not $Always) -or ($AlwaysExcept -and $f.Name -match $AlwaysExcept)
            if ($useWindow -and $f.LastWriteTime -lt $script:Since) { continue }
            $rel = $f.FullName.Substring($Folder.TrimEnd('\').Length).TrimStart('\')
            if (Copy-ToPackage -File $f -Dest (Join-Path $DestFolder $rel)) { $count++ }
        }
    }
    Write-Log "scanned $Folder for $($Patterns -join ', '): $count copied"
    return $count
}

function Get-FileVersionText([string]$Path) {
    try {
        if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return $null }
        $i = Get-Item -LiteralPath $Path
        return [ordered]@{
            file     = $i.Name
            version  = $i.VersionInfo.FileVersion
            product  = $i.VersionInfo.ProductVersion
            size     = $i.Length
            modified = $i.LastWriteTime.ToString('s')
        }
    } catch {
        Write-Log "cannot read version of ${Path}: $($_.Exception.Message)"
        return $null
    }
}

function Test-GameFolder([string]$Folder) {
    try { return [bool](Test-Path -LiteralPath (Join-Path $Folder 'Starfield.exe') -ErrorAction Stop) } catch { return $false }
}

function Get-SteamPath {
    foreach ($k in @(@('HKCU:\Software\Valve\Steam', 'SteamPath'), @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'))) {
        try {
            $v = (Get-ItemProperty -Path $k[0] -Name $k[1] -ErrorAction Stop).($k[1])
            if ($v) { return ($v -replace '/', '\') }
        } catch { }
    }
    return $null
}

function Get-SteamLibraries {
    $steam = Get-SteamPath
    if (-not $steam) { Write-Log 'Steam not found in the registry'; return @() }
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    try {
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    } catch { Write-Log "cannot read ${vdf}: $($_.Exception.Message)" }
    return @($libs | Select-Object -Unique)
}

# Game Pass: <drive>:\XboxGames\Starfield\Content, or the folder named in the drive's .GamingRoot file.
function Get-GamePassCandidates {
    $out = @()
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $root = $d.Root
        if (-not $root) { continue }
        $folders = @('XboxGames')
        $gr = Join-Path $root '.GamingRoot'
        try {
            if (Test-Path -LiteralPath $gr -ErrorAction Stop) {
                # 'RGBX', a 4-byte count, then UTF-16 folder names ending in a zero character.
                $bytes = [System.IO.File]::ReadAllBytes($gr)
                if ($bytes.Length -gt 8) {
                    $names = [System.Text.Encoding]::Unicode.GetString($bytes, 8, $bytes.Length - 8).Split([char]0)
                    foreach ($n in $names) { if ($n.Trim()) { $folders += $n.Trim().TrimStart('\') } }
                }
            }
        } catch { }
        foreach ($f in ($folders | Select-Object -Unique)) { $out += (Join-Path $root (Join-Path $f 'Starfield\Content')) }
    }
    return $out
}

function Find-GamePath {
    $default = 'C:\Program Files (x86)\Steam\steamapps\common\Starfield'
    # Another Windows user may not be allowed to read a folder: "access denied" means "not here".
    if (Test-GameFolder $default) { return @{ path = $default; store = 'Steam' } }
    foreach ($l in Get-SteamLibraries) {
        $c = Join-Path $l 'steamapps\common\Starfield'
        if (Test-GameFolder $c) { return @{ path = $c; store = 'Steam' } }
    }
    foreach ($c in Get-GamePassCandidates) {
        if (Test-GameFolder $c) { return @{ path = $c; store = 'Game Pass' } }
    }
    return $null
}

function Get-DefaultScreenshotDirs([string]$MyGames) {
    $dirs = @()
    $steam = Get-SteamPath
    if ($steam) {
        $ud = Join-Path $steam 'userdata'
        foreach ($u in @(Get-ChildItem -LiteralPath $ud -Directory -ErrorAction SilentlyContinue)) {
            $dirs += (Join-Path $u.FullName "760\remote\$StarfieldSteamAppId\screenshots")
        }
    }
    $dirs += (Join-Path $MyGames 'Data\Textures\Photos')
    return $dirs
}

# Decodes one value the way Qt's QSettings (and so MO2 itself) reads its INI. A port of Qt 5.15's
# QSettingsPrivate::iniUnescapedStringList and stringToVariant (qsettings.cpp), checked 2026-11-19:
#   - leading spaces are skipped; trailing spaces are cut unless the value was quoted;
#   - a double quote toggles quoting anywhere and is removed; a comma outside quotes splits a list
#     (a list comes back joined with commas: MO2's folder settings are never lists);
#   - escapes \a \b \f \n \r \t \v \" \? \' \\ (lowercase only); \x plus every hex digit after it, and
#     \ plus octal digits, keep the low 16 bits; \x with no hex digit, an unknown escape (\M in
#     D:\Mods) and a lone trailing backslash are dropped entirely, as Qt drops them;
#   - then the decoded text's @ forms: @ByteArray(...) holds bytes (Latin-1, so a character above 255
#     becomes '?'; MO2 reads them as UTF-8), @String(...), @Invalid() is no value, @@ is a literal @.
# MO2 stores paths with forward slashes, so the escapes matter for quotes, @ and hand edits.
function ConvertFrom-QtIniValue([string]$Raw) {
    $codes = New-Object 'System.Collections.Generic.Dictionary[char,char]'
    foreach ($p in @(@('a', 7), @('b', 8), @('f', 12), @('n', 10), @('r', 13), @('t', 9), @('v', 11),
                     @('"', 34), @('?', 63), @("'", 39), @('\', 92))) {
        $codes[[char]$p[0]] = [char]$p[1]
    }
    $v = $Raw
    $n = $v.Length
    $sb = New-Object System.Text.StringBuilder
    $items = New-Object System.Collections.Generic.List[string]
    $isList = $false; $inQuote = $false; $quoted = $false
    $i = 0
    while ($i -lt $n -and ($v[$i] -eq ' ' -or $v[$i] -eq "`t")) { $i++ }
    $chop = 0
    $isHex = { param($ch) ($ch -ge [char]'0' -and $ch -le [char]'9') -or ($ch -ge [char]'a' -and $ch -le [char]'f') -or ($ch -ge [char]'A' -and $ch -le [char]'F') }
    $cutTrailing = { while ($sb.Length -gt $chop -and ($sb[$sb.Length - 1] -eq ' ' -or $sb[$sb.Length - 1] -eq "`t")) { [void]$sb.Remove($sb.Length - 1, 1) } }
    while ($i -lt $n) {
        $c = $v[$i]
        if ($c -eq '\') {
            $i++
            if ($i -ge $n) { break }
            $e = $v[$i]; $i++
            if ($codes.ContainsKey($e)) { [void]$sb.Append($codes[$e]) }
            elseif ($e -ceq 'x') {
                if ($i -lt $n -and (& $isHex $v[$i])) {
                    $code = 0
                    while ($i -lt $n -and (& $isHex $v[$i])) { $code = (($code -shl 4) + [Convert]::ToInt32([string]$v[$i], 16)) -band 0xFFFF; $i++ }
                    [void]$sb.Append([char]$code)
                }
            }
            elseif ($e -ge [char]'0' -and $e -le [char]'7') {
                $code = [int][string]$e
                while ($i -lt $n -and $v[$i] -ge [char]'0' -and $v[$i] -le [char]'7') { $code = (($code -shl 3) + [int][string]$v[$i]) -band 0xFFFF; $i++ }
                [void]$sb.Append([char]$code)
            }
            elseif ($e -eq "`n" -or $e -eq "`r") {
                if ($i -lt $n -and ($v[$i] -eq "`n" -or $v[$i] -eq "`r") -and $v[$i] -ne $e) { $i++ }
            }
            # any other escaped character is skipped, with its backslash
            $chop = $sb.Length
        }
        elseif ($c -eq '"') {
            $i++; $quoted = $true; $inQuote = -not $inQuote
            if (-not $inQuote) {
                while ($i -lt $n -and ($v[$i] -eq ' ' -or $v[$i] -eq "`t")) { $i++ }
                $chop = $sb.Length
            }
        }
        elseif ($c -eq ',' -and -not $inQuote) {
            if (-not $quoted) { & $cutTrailing }
            $isList = $true
            $items.Add($sb.ToString()); [void]$sb.Clear(); $quoted = $false
            $i++
            while ($i -lt $n -and ($v[$i] -eq ' ' -or $v[$i] -eq "`t")) { $i++ }
            $chop = 0
        }
        else { [void]$sb.Append($c); $i++ }
    }
    if (-not $quoted) { & $cutTrailing }
    if ($isList) { $items.Add($sb.ToString()); $out = $items -join ',' } else { $out = $sb.ToString() }
    $ord = [StringComparison]::Ordinal
    if ($out.StartsWith('@String(', $ord) -and $out.EndsWith(')', $ord)) { return $out.Substring(8, $out.Length - 9) }
    if ($out.StartsWith('@ByteArray(', $ord) -and $out.EndsWith(')', $ord)) {
        $inner = $out.Substring(11, $out.Length - 12)
        # Qt turns the text into bytes with toLatin1 (a character above 255 becomes '?'), then UTF-8.
        $bytes = [byte[]]@($inner.ToCharArray() | ForEach-Object { if ([int]$_ -gt 255) { 63 } else { [int]$_ } })
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    if ($out -ceq '@Invalid()') { return '' }
    if ($out.StartsWith('@@', $ord)) { return $out.Substring(1) }
    return $out
}

# Reads the few ModOrganizer.ini settings we need.
function Read-MO2Ini([string]$Path) {
    # Keys are stored as "section\key" (settings\profiles_directory) and, for [General], also as the bare key.
    $vals = @{}
    $section = ''
    # MO2 (Qt) writes UTF-8; Windows PowerShell 5.1 would read it as ANSI without -Encoding.
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') { $section = $Matches[1].Trim().ToLowerInvariant(); continue }
        if ($line -match '^\s*([A-Za-z_\\]+)\s*=\s*(.*)$') {
            $k = $Matches[1].ToLowerInvariant()
            $v = ConvertFrom-QtIniValue $Matches[2]
            if ($section) { $vals["$section\$k"] = $v }
            if (-not $section -or $section -eq 'general') { $vals[$k] = $v }
        }
    }
    return $vals
}

function Resolve-MO2Dir([string]$Base, [string]$Value, [string]$Default) {
    # [IO.Path]::Combine, not Join-Path: Join-Path fails on a drive letter this PC doesn't have.
    if (-not $Value) { return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Base, $Default)) }
    # $Value is already decoded (ConvertFrom-QtIniValue). MO2 writes forward slashes.
    #   //server/share -> UNC; /dir -> the root of the MO2 instance's own drive;
    #   D:dir (no slash after the colon) -> D:\dir; anything else not rooted -> under $Base.
    $s = $Value -replace '/', '\'
    $kind = 'relative'
    $rest = $s
    if ($s.StartsWith('\\')) { $kind = 'unc'; $rest = $s.TrimStart('\') }
    elseif ($s.StartsWith('\')) { $kind = 'root'; $rest = $s.Substring(1) }
    elseif ($s -match '^([A-Za-z]:)([^\\].*)?$') { $kind = 'drive'; $rest = $s }
    $rest = $rest -replace '\\{2,}', '\'
    # %BASE_DIR% replaced as plain text: a '$' in the folder name must not act as a regex group.
    $rest = [regex]::Replace($rest, '(?i)%BASE_DIR%', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $Base })
    switch ($kind) {
        'unc'  { $v = '\\' + $rest }
        'drive' { $v = $rest.Substring(0, 2) + '\' + $rest.Substring(2) }
        'root' { $v = [System.IO.Path]::Combine([System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Base)), $rest) }
        default { $v = [System.IO.Path]::Combine($Base, $rest) }   # Combine keeps $rest when it is rooted
    }
    return [System.IO.Path]::GetFullPath($v)
}

# ---------------------------------------------------------------- main
$exitCode = 0
$ZipPath = $null
try {
    Write-Host ''
    Write-Host "Starfield log collector $ScriptVersion" -ForegroundColor Cyan
    Write-Host ''
    Write-Log "Collect-StarfieldTestLogs $ScriptVersion, PowerShell $($PSVersionTable.PSVersion)"
    if ($script:ShortPathNote) { Write-Log $script:ShortPathNote }

    # .NET file calls don't follow PowerShell's current folder: make every path option a full path.
    function Resolve-Full([string]$P) {
        if (-not $P) { return $P }
        # A drive that doesn't exist (E:\ on a PC without E:) is left as typed, so the usual
        # "not found" warning names it instead of an error stopping the run.
        try { return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($P) }
        catch {
            $why = $_.Exception
            while ($why.InnerException) { $why = $why.InnerException }
            if ($why -is [System.Management.Automation.DriveNotFoundException]) {
                Add-Warning "Path not found: $P (no drive $($why.ItemName):). Check the drive letter."
            } else {
                Add-Warning "Path not usable: $P ($($why.Message))."
            }
            try { return [System.IO.Path]::GetFullPath($P) } catch { return $P }
        }
    }
    $SavesDir = Resolve-Full $SavesDir; $GamePath = Resolve-Full $GamePath; $MO2Path = Resolve-Full $MO2Path
    $VortexExportDir = Resolve-Full $VortexExportDir; $DownloadsDir = Resolve-Full $DownloadsDir
    $MyGamesDir = Resolve-Full $MyGamesDir; $PluginsTxtDir = Resolve-Full $PluginsTxtDir
    $OutDir = Resolve-Full $OutDir; $LogFile = Resolve-Full $LogFile
    # -File passes "a,b" as one string, so several folders are given as "a;b".
    $ScreenshotDir = @($ScreenshotDir | ForEach-Object { $_ -split ';' } | Where-Object { $_.Trim() } | ForEach-Object { Resolve-Full $_.Trim() })

    if (Get-Process -Name 'Starfield' -ErrorAction SilentlyContinue) {
        Add-Warning 'Starfield is still running. Quit the game first so the logs are complete.'
        if (-not $NoPrompt) {
            $go = Read-Host 'Collect anyway? [y/N]'
            if ($go -notmatch '^[yY]') { Write-Host 'Stopped. Nothing was collected.'; exit 1 }
        }
    }

    if (-not $NoPrompt) {
        if (-not $Note) { $Note = Read-Host 'What did you test? (e.g. "new quest, checks 1-12", Enter to skip)' }
        if (-not $PSBoundParameters.ContainsKey('IncludeSaves') -and -not $PSBoundParameters.ContainsKey('SavePair')) {
            $ans = Read-Host 'Include saves? p = before/after pair, y = newest save, Enter = none [p/y/N]'
            if ($ans -match '^[pP]') { $SavePair = $true }
            elseif ($ans -match '^[yY]') { $IncludeSaves = $true }
        }
    }
    Write-Log "note: $Note; saves: newest=$([bool]$IncludeSaves) pair=$([bool]$SavePair)"

    # Folders
    $Docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $MyGamesDir) { $MyGamesDir = Join-Path $Docs 'My Games\Starfield' }
    if (-not $PluginsTxtDir) { $PluginsTxtDir = Join-Path $env:LOCALAPPDATA 'Starfield' }
    if (-not $DownloadsDir) { $DownloadsDir = Join-Path $env:USERPROFILE 'Downloads' }
    if (-not $VortexExportDir) { $VortexExportDir = $DownloadsDir }
    if (-not $OutDir) { $OutDir = Join-Path $Docs 'StarfieldLogs' }
    if (-not $SavesDir) { $SavesDir = Join-Path $MyGamesDir 'Saves' }
    if ($ScreenshotDir.Count -eq 0) { $ScreenshotDir = Get-DefaultScreenshotDirs $MyGamesDir }
    if (-not (Test-Path -LiteralPath $MyGamesDir)) {
        Add-Warning "Documents\My Games\Starfield not found ($MyGamesDir). Start the game once, or pass -MyGamesDir."
    }

    $Store = 'unknown'
    if ($GamePath) {
        if ((Split-Path $GamePath -Leaf) -ieq 'Data') { $GamePath = Split-Path $GamePath -Parent }
        if (-not (Test-GameFolder $GamePath)) {
            Add-Warning "No Starfield.exe in -GamePath $GamePath; game-folder reports skipped. Pass the folder that holds Starfield.exe."
            $GamePath = $null
        } elseif ($GamePath -match '(?i)\\steamapps\\') { $Store = 'Steam' }
        elseif ($GamePath -match '(?i)\\Content$') { $Store = 'Game Pass' }
    } else {
        $found = Find-GamePath
        if ($found) { $GamePath = $found.path; $Store = $found.store }
        else {
            Add-Warning 'Starfield install folder not found (Steam libraries and <drive>:\XboxGames checked); game-folder reports skipped. Use -GamePath.'
        }
    }
    Write-Log "game folder: $GamePath ($Store)"

    # Mod Organizer 2
    $mo2 = $null
    if ($MO2Path) {
        $mo2Ini = Join-Path $MO2Path 'ModOrganizer.ini'
        if (-not (Test-Path -LiteralPath $mo2Ini)) {
            Add-Warning "No ModOrganizer.ini in -MO2Path $MO2Path; MO2 files skipped. Pass the MO2 instance folder (Settings > Paths shows it)."
        } else {
            try {
                $ini = Read-MO2Ini $mo2Ini
                $base = Resolve-MO2Dir $MO2Path $ini['settings\base_directory'] '.'
                $profilesDir = Resolve-MO2Dir $base $ini['settings\profiles_directory'] 'profiles'
                $overwriteDir = Resolve-MO2Dir $base $ini['settings\overwrite_directory'] 'overwrite'
                if (-not $MO2Profile) { $MO2Profile = $ini['selected_profile'] }
                if (-not $MO2Profile) { $MO2Profile = 'Default' }
                $mo2 = [ordered]@{ instance = (Hide-Path $MO2Path); profile = $MO2Profile; profileDir = [System.IO.Path]::Combine($profilesDir, $MO2Profile); overwrite = $overwriteDir }
                Write-Log "MO2: profile '$MO2Profile' in $profilesDir, overwrite $overwriteDir"
                if (-not (Test-Path -LiteralPath $mo2.profileDir)) { Add-Warning "MO2 profile folder not found: $($mo2.profileDir). Check -MO2Profile." }
            } catch {
                $mo2 = $null
                Add-Warning "Could not read the MO2 folders from $mo2Ini ($($_.Exception.Message)); MO2 files skipped."
            }
        }
    } else {
        $globalMo2 = Join-Path $env:LOCALAPPDATA 'ModOrganizer\Starfield\ModOrganizer.ini'
        if (Test-Path -LiteralPath $globalMo2) {
            Write-Host "  Mod Organizer 2 found ($(Hide-Path (Split-Path $globalMo2 -Parent))). If you play through it, rerun with -MO2Path." -ForegroundColor DarkGray
            Write-Log "MO2 instance found but not used (no -MO2Path): $globalMo2"
        }
    }

    # Time window
    if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
    $Marker = Join-Path $OutDir ('.last-run-' + $env:USERNAME)
    $Now = Get-Date
    # A damaged or empty marker falls back to 12 hours instead of stopping the run.
    $parsed = [datetime]::MinValue
    $markerOk = $false
    $markerBad = $false
    if ($Hours -le 0 -and (Test-Path -LiteralPath $Marker)) {
        try {
            $markerText = ([string](Get-Content -LiteralPath $Marker -Raw)).Trim()
            $markerOk = [datetime]::TryParse($markerText, [Globalization.CultureInfo]::InvariantCulture,
                                             [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)
        } catch { $markerOk = $false }
        if (-not $markerOk) {
            $markerBad = $true
            Add-Warning "The last-run marker $Marker could not be read; using the last 12 hours."
        }
    }
    if ($Hours -gt 0) {
        $script:Since = $Now.AddHours(-$Hours)
        $WindowText = "last $Hours hours"
    } elseif ($markerOk) {
        $script:Since = $parsed
        $WindowText = 'since last run'
    } else {
        $script:Since = $Now.AddHours(-12)
        $WindowText = $(if ($markerBad) { 'last 12 hours (marker unreadable)' } else { 'last 12 hours (first run)' })
    }
    Write-Host "Collecting files changed $WindowText ($($script:Since.ToString('yyyy-MM-dd HH:mm')))"
    Write-Log "window: $WindowText, since $($script:Since.ToString('s')); marker $Marker"

    # Staging folder
    $Stamp = $Now.ToString('yyyyMMdd-HHmmss')
    $Short = ($Note -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if ($Short.Length -gt 40) { $Short = $Short.Substring(0, 40).Trim('-') }
    $ZipName = 'StarfieldLogs-' + $Stamp + $(if ($Short) { '-' + $Short } else { '' }) + '.zip'
    $script:Stage = Join-Path ([System.IO.Path]::GetTempPath()) ('StarfieldLogs-' + $Stamp + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $script:Stage -Force)

    # ------------------------------------------------------------ collect
    $counts = [ordered]@{}

    # Papyrus: the two newest logs always (quitting to the main menu opens a new Papyrus.0.log, so the
    # play session is often Papyrus.1.log), older ones if in the window.
    $papDir = Join-Path $MyGamesDir 'Logs\Script'
    $counts.papyrus = (Copy-Matching -Folder $papDir -Patterns @('Papyrus.0.log', 'Papyrus.1.log') -DestFolder 'docs\Logs\Script' -Always) +
                      (Copy-Matching -Folder $papDir -Patterns @(2..9 | ForEach-Object { "Papyrus.$_.log" }) -DestFolder 'docs\Logs\Script') +
                      (Copy-Matching -Folder (Join-Path $papDir 'User') -Patterns @('*.log') -DestFolder 'docs\Logs\Script\User')
    $pap0 = Join-Path $papDir 'Papyrus.0.log'
    if (-not (Test-Path -LiteralPath $pap0)) {
        Add-Warning 'No Papyrus.0.log found: is Papyrus logging on in StarfieldCustom.ini? (see the README)'
    } elseif ((Get-Item -LiteralPath $pap0).LastWriteTime -lt $script:Since) {
        Add-Warning 'Papyrus.0.log is older than this window: was Papyrus logging on during the test?'
    }

    # Game INIs (always). With MO2 profile-local INIs, the profile's copies are the live ones.
    $counts.gameIni = Copy-Matching -Folder $MyGamesDir -Patterns @('StarfieldCustom.ini', 'StarfieldPrefs.ini') -DestFolder 'docs' -Always
    $customIni = Join-Path $MyGamesDir 'StarfieldCustom.ini'
    if ($mo2 -and (Test-Path -LiteralPath (Join-Path $mo2.profileDir 'StarfieldCustom.ini'))) { $customIni = Join-Path $mo2.profileDir 'StarfieldCustom.ini' }
    if (Test-Path -LiteralPath $customIni) {
        $ci = Get-Content -LiteralPath $customIni -Raw
        if ($ci -notmatch '(?im)^\s*bEnableLogging\s*=\s*1') { Add-Warning "StarfieldCustom.ini does not turn on Papyrus logging (bEnableLogging=1): $customIni" }
    } else {
        Add-Warning 'No StarfieldCustom.ini: Papyrus logging is probably off (see the README).'
    }

    # SFSE logs (SFSE itself and its plugins) and crash loggers in Documents
    $counts.sfseLogs = Copy-Matching -Folder (Join-Path $MyGamesDir 'SFSE\Logs') -Patterns @('*') -DestFolder 'docs\SFSE\Logs'
    $counts.crashLogger = Copy-Matching -Folder (Join-Path $MyGamesDir 'SFSE\Crashlogs') -Patterns @('*.log', '*.txt') -DestFolder 'docs\SFSE\Crashlogs'

    # Load order (always)
    $counts.pluginsTxt = Copy-Matching -Folder $PluginsTxtDir -Patterns @('plugins.txt') -DestFolder 'appdata' -Always

    # Game-folder reports and plugin INIs
    $backupRx = '(_\d{12}|-\d{8}[a-z]?|\.bak|\.old)'
    $crashCount = 0
    $sfseFolders = @()
    if ($GamePath) { $sfseFolders += @{ dir = (Join-Path $GamePath 'Data\SFSE'); dest = 'game\Data\SFSE' } }
    if ($mo2) { $sfseFolders += @{ dir = (Join-Path $mo2.overwrite 'SFSE'); dest = 'mo2\overwrite\SFSE' } }
    $counts.sfseReports = 0; $counts.pluginReports = 0; $counts.pluginIni = 0
    foreach ($sf in $sfseFolders) {
        $counts.sfseReports += Copy-Matching -Folder $sf.dir -Patterns @('*.txt', '*.log') -DestFolder $sf.dest
        $plug = Join-Path $sf.dir 'Plugins'
        $counts.pluginReports += Copy-Matching -Folder $plug -Patterns @('*.txt', '*.log') -DestFolder (Join-Path $sf.dest 'Plugins')
        $counts.pluginIni += Copy-Matching -Folder $plug -Patterns @('*.ini', '*.toml', '*.json') -DestFolder (Join-Path $sf.dest 'Plugins') -Always -AlwaysExcept $backupRx
        $crashCount += @(Get-ChildItem -LiteralPath $plug -Filter 'Crashlog_*' -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.LastWriteTime -ge $script:Since }).Count
    }
    if ($crashCount -gt 0) { Add-Warning "Crash log found! ($crashCount new crash log(s) in Data\SFSE\Plugins)" }
    $newCrash = @(Get-ChildItem -LiteralPath (Join-Path $MyGamesDir 'SFSE\Crashlogs') -Filter 'crash*.log' -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.LastWriteTime -ge $script:Since })
    if ($newCrash.Count -gt 0) { Add-Warning "Crash log found! ($($newCrash.Count) new log(s) in SFSE\Crashlogs)" }

    # Mod Organizer 2 profile (always)
    $counts.mo2 = 0
    if ($mo2) {
        $counts.mo2 = Copy-Matching -Folder $mo2.profileDir -Patterns @('plugins.txt', 'loadorder.txt', 'modlist.txt', 'settings.ini', 'Starfield*.ini') -DestFolder 'mo2\profile' -Always
        $counts.mo2 += Copy-Matching -Folder (Join-Path $MO2Path 'logs') -Patterns @('mo_interface.log', 'usvfs-*.log') -DestFolder 'mo2\logs'
    }

    # Console transcripts (ConsoleAPIEnhanced web console), Vortex Modlist Backup exports
    $counts.consoleTranscripts = Copy-Matching -Folder $DownloadsDir -Patterns @('sfconsole_*.txt') -DestFolder 'downloads'
    $counts.vortexExports = Copy-Matching -Folder $VortexExportDir -Patterns @('vortex-starfield-*-backup-*.json') -DestFolder 'vortex'

    # Screenshots (newest first, capped)
    $counts.screenshots = 0
    $shots = @()
    foreach ($sd in $ScreenshotDir) {
        if ($sd -and (Test-Path -LiteralPath $sd)) {
            $shots += @(Get-ChildItem -LiteralPath $sd -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -match '^\.(png|jpe?g|bmp)$' -and $_.LastWriteTime -ge $script:Since })
        } else { Write-Log "screenshot folder not found: $sd" }
    }
    $usedNames = @{}
    foreach ($s in @($shots | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxScreenshots)) {
        # Two folders can hold the same file name: number the later ones instead of overwriting.
        $name = $s.Name
        $n = 1
        while ($usedNames.ContainsKey($name.ToLowerInvariant())) { $n++; $name = '{0}-{1}{2}' -f $s.BaseName, $n, $s.Extension }
        $usedNames[$name.ToLowerInvariant()] = $true
        if (Copy-ToPackage -File $s -Dest (Join-Path 'screenshots' $name)) { $counts.screenshots++ }
    }
    if ($shots.Count -gt $MaxScreenshots) { Write-Log "screenshots: kept the newest $MaxScreenshots of $($shots.Count)" }

    # Saves (only when asked). Saves can be big: never skipped for size.
    $counts.saves = 0
    $savePairInfo = $null
    if ($IncludeSaves -or $SavePair) {
        $gpSaves = Join-Path $env:LOCALAPPDATA "Packages\$GamePassPackage\SystemAppData\wgs"
        $haveSfs = @(Get-ChildItem -LiteralPath $SavesDir -Filter '*.sfs' -File -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $haveSfs -and (Test-Path -LiteralPath $gpSaves)) {
            Add-Warning 'Game Pass keeps saves in a container, not as .sfs files. Export them first (for example with XGP-save-extractor) and pass -SavesDir.'
        }
    }
    if ($IncludeSaves) {
        $saves = @(Get-ChildItem -LiteralPath $SavesDir -Filter '*.sfs' -File -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First $SaveCount)
        foreach ($s in $saves) {
            if (Copy-ToPackage -File $s -Dest (Join-Path 'saves' $s.Name) -NoSizeLimit) { $counts.saves++ }
        }
        if ($counts.saves -eq 0) { Add-Warning "No save files found in $SavesDir." }
    }
    if ($SavePair) {
        # Starfield names saves itself: Save<N>_<character>_<playtime>_<yyyyMMddHHmmss>_...sfs
        $pairRx = '^Save\d+_(.+)_\d{6}_(\d{14})_'
        $manual = @(Get-ChildItem -LiteralPath $SavesDir -Filter 'Save*.sfs' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $pairRx } |
                    ForEach-Object { $null = $_.Name -match $pairRx; [pscustomobject]@{ File = $_; Char = $Matches[1]; Stamp = $Matches[2] } } |
                    Sort-Object Stamp -Descending)
        if ($manual.Count -eq 0) {
            Add-Warning 'No manual saves found for the before/after pair (make one hard save before the test and one after).'
        } else {
            $char = $manual[0].Char
            $mine = @($manual | Where-Object { $_.Char -eq $char } | Select-Object -First 2)
            if ($mine.Count -lt 2) {
                Add-Warning 'Only one manual save for this character: the before/after pair needs a hard save before the test and one after.'
            }
            $roles = @('after', 'before')
            $savePairInfo = [ordered]@{ character = $char }
            for ($i = 0; $i -lt $mine.Count; $i++) {
                $s = $mine[$i].File
                if (Copy-ToPackage -File $s -Dest (Join-Path 'saves' ("$($roles[$i])-" + $s.Name)) -NoSizeLimit) {
                    $savePairInfo[$roles[$i]] = $s.Name
                    $counts.saves++
                }
            }
        }
    }

    # Windows Application events about Starfield (crashes, hangs)
    $counts.events = 0
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $script:Since } -ErrorAction Stop |
                Where-Object { $_.ProviderName -in @('Application Error', 'Application Hang', 'Windows Error Reporting') -and $_.Message -match 'Starfield' })
        if ($ev.Count -gt 0) {
            $lines = foreach ($e in $ev) { "==== $($e.TimeCreated.ToString('s'))  $($e.ProviderName)  ID $($e.Id)"; (Hide-Path $e.Message); '' }
            [System.IO.File]::WriteAllLines((Join-Path $script:Stage 'events.txt'), [string[]]$lines)
            $counts.events = $ev.Count
            Add-Warning "$($counts.events) Windows event(s) about Starfield (crash or hang) in this window."
        }
    } catch {
        if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound') { Add-Warning "Could not read the Application event log: $($_.Exception.Message)" }
        else { Write-Log 'no Windows events about Starfield in the window' }
    }

    # Check now that the last-run marker can be written, so a warning about it lands in this zip.
    # (Opening an existing marker for writing doesn't change it; a new one is tried with a test file.)
    # The real write after the zip opens the file the same way, so a hidden marker passes both.
    $markerWarned = $false
    if (-not $DryRun) {
        try {
            if (Test-Path -LiteralPath $Marker) {
                $probe = [System.IO.File]::Open($Marker, 'Open', 'Write', 'None'); $probe.Dispose()
            } else {
                $testFile = Join-Path $OutDir ('.write-test-' + [guid]::NewGuid().ToString('N'))
                [System.IO.File]::WriteAllText($testFile, '')
                # A failed clean-up (antivirus holding the new file) is not a marker problem.
                try { Remove-Item -LiteralPath $testFile -Force } catch { Write-Log "could not remove $testFile : $($_.Exception.Message)" }
            }
        } catch {
            $markerWarned = $true
            Add-Warning "The last-run marker $Marker can't be written ($($_.Exception.Message)), so the next run will cover a wider window. Check the folder's permissions."
        }
    }

    # ------------------------------------------------------------ manifest
    $versions = [ordered]@{}
    $listing = [ordered]@{ sfsePluginDlls = @(); dataPlugins = @() }
    if ($GamePath) {
        $versions.starfield = Get-FileVersionText (Join-Path $GamePath 'Starfield.exe')
        $versions.sfseLoader = Get-FileVersionText (Join-Path $GamePath 'sfse_loader.exe')
        $versions.engineFixes = Get-FileVersionText (Join-Path $GamePath 'Data\SFSE\Plugins\StarfieldEngineFixes.dll')
        $listing.sfsePluginDlls = @(Get-ChildItem -LiteralPath (Join-Path $GamePath 'Data\SFSE\Plugins') -Filter '*.dll' -File -ErrorAction SilentlyContinue |
            ForEach-Object { [ordered]@{ name = $_.Name; version = $_.VersionInfo.FileVersion; size = $_.Length; modified = $_.LastWriteTime.ToString('s') } })
        $listing.dataPlugins = @(Get-ChildItem -LiteralPath (Join-Path $GamePath 'Data') -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(esm|esp|esl)$' } |
            ForEach-Object { [ordered]@{ name = $_.Name; size = $_.Length; modified = $_.LastWriteTime.ToString('s') } })
    }
    if ($mo2) { $listing.note = 'With Mod Organizer 2 the mods stay in MO2''s mods folder: see mo2\profile\modlist.txt for the mod list.' }

    $manifest = [ordered]@{
        tool      = "Collect-StarfieldTestLogs $ScriptVersion"
        created   = $Now.ToString('s')
        note      = $Note
        window    = [ordered]@{ since = $script:Since.ToString('s'); how = $WindowText }
        dryRun    = [bool]$DryRun
        store     = $Store
        gamePath  = (Hide-Path $GamePath)
        mo2       = $(if ($mo2) { [ordered]@{ instance = $mo2.instance; profile = $mo2.profile } } else { $null })
        versions  = $versions
        counts    = $counts
        savePair  = $savePairInfo
        warnings  = @($script:Warnings)
        skipped   = @($script:Skipped)
        files     = @($script:Collected)
        listing   = $listing
    }
    $json = $manifest | ConvertTo-Json -Depth 6
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $script:Stage 'manifest.json'), $json, $utf8)

    # ------------------------------------------------------------ zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $ZipPath = Join-Path $OutDir $ZipName
    Write-Log "zip: $ZipPath"
    [System.IO.File]::WriteAllLines((Join-Path $script:Stage 'collector-log.txt'), [string[]]$script:LogLines, $utf8)
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($script:Stage, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    if (-not $DryRun) {
        # The zip is made: a marker that can't be written only means the next run's window is wider.
        try {
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($Now.ToString('o', [Globalization.CultureInfo]::InvariantCulture))
            # OpenOrCreate rather than WriteAllText (FileMode.Create), which refuses a hidden file. The new
            # time is written before the file is trimmed, so an existing marker is never left empty. A failed
            # write can still leave it damaged; the next run then reports it and uses 12 hours.
            $fs = [System.IO.File]::Open($Marker, 'OpenOrCreate', 'Write', 'None')
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.SetLength($bytes.Length) } finally { $fs.Dispose() }
        } catch {
            $msg = "Could not update the last-run marker ${Marker}: $($_.Exception.Message). Delete it, or check this folder's permissions."
            if ($markerWarned) { Write-Log $msg } else { Add-Warning $msg }
        }
    }

    # ------------------------------------------------------------ summary
    $zipInfo = Get-Item -LiteralPath $ZipPath
    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
    Write-Host "  Package : $ZipPath"
    Write-Host ('  Size    : {0:N1} MB, {1} files' -f ($zipInfo.Length / 1MB), $script:Collected.Count)
    $parts = foreach ($k in $counts.Keys) { if ($counts[$k] -gt 0) { "$k $($counts[$k])" } }
    if ($parts) { Write-Host ('  Contents: ' + ($parts -join ', ')) }
    if ($script:Skipped.Count -gt 0) { Write-Host "  Skipped : $($script:Skipped.Count) file(s) (see manifest.json)" }
    if ($script:Warnings.Count -gt 0) {
        Write-Host ''
        Write-Host 'Warnings:' -ForegroundColor Yellow
        foreach ($w in $script:Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
    }
    Write-Host ''
    Write-Host 'Send this zip to whoever asked for your logs. Look inside first if you share it in public.' -ForegroundColor Cyan
} catch {
    $exitCode = 2
    Write-Log "ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  Nothing was zipped. Run it again with -Verbose -LogFile sf-logs.txt and send sf-logs.txt' -ForegroundColor Red
    Write-Host '  with your issue: it says which file or folder failed.' -ForegroundColor Red
} finally {
    if ($script:Stage -and (Test-Path -LiteralPath $script:Stage)) { Remove-Item -LiteralPath $script:Stage -Recurse -Force -ErrorAction SilentlyContinue }
    if ($LogFile) {
        try {
            [System.IO.File]::AppendAllLines($LogFile, [string[]]$script:LogLines)
            Write-Host "  Log     : $LogFile"
        } catch { Write-Host "  Could not write the log to ${LogFile}: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
exit $exitCode
