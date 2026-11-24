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
    Also write the troubleshooting log to this file (it is always inside the zip as
    collector-log.txt). The log is added to the end of the file if it exists. -Log is
    the short form. Add -Verbose to see the same lines on screen as it runs.
.PARAMETER Redact
    Hide your Windows user name, computer name, user folder and Steam account number
    in every text file the collector copies (logs, plugins.txt, INIs, crash logs,
    Vortex exports) and in its own manifest and log. They become %USERPROFILE%,
    <user>, <computer> and userdata\<steam-id>. Saves, screenshots and files that
    don't look like text are copied as they are, and zip entry names are not changed.
    Plugin names and form IDs are kept, unless one is your user or computer name as a
    whole word. Asked for if not given (Enter = no).
.PARAMETER NoPrompt
    Ask no questions; use the defaults (no saves, no -Redact).
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
    [Alias('Log')]
    [string]$LogFile = '',
    [switch]$Redact,
    [switch]$NoPrompt,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2.1.0'
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
$profForms = @()
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

# -Redact: the rules, in the order they are applied. The user folder goes first (in the forms logs
# and JSON write it: \, / and \\), so a whole path becomes %USERPROFILE% rather than C:\Users\<user>.
# Names are whole words (no letter, digit or _ either side), any case. A name under 3 characters is
# hidden only after \Users\, so a user called "ui" doesn't turn every "UI" in a log into <user>.
# A file that is not valid UTF-8 is read as Latin-1, where a UTF-8 letter outside English reads as two
# other letters: that pass also gets the rules built from each value's UTF-8 bytes read as Latin-1.
$script:RedactRules = New-Object System.Collections.ArrayList
$script:RedactRulesLatin1 = New-Object System.Collections.ArrayList
$script:RedactNotes = New-Object System.Collections.ArrayList
function Add-RedactRule([string]$Pattern, [string]$With) {
    $rx = New-Object System.Text.RegularExpressions.Regex($Pattern, [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant')
    [void]$script:RedactInto.Add(@{ rx = $rx; with = $With })
}
function Add-RedactRuleSet([System.Collections.ArrayList]$Into, [scriptblock]$Form, [bool]$Notes) {
    $script:RedactInto = $Into
    if ($profForms.Count -gt 0) {
        $redForms = foreach ($f in $profForms) { $f; ($f -replace '\\', '/'); ($f -replace '\\', '\\') }
        $redForms = @($redForms | Select-Object -Unique | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape((& $Form $_)) })
        Add-RedactRule ('(?:' + ($redForms -join '|') + ')(?!\.?[\w~-])') '%USERPROFILE%'
    }
    if ($env:USERNAME) { Add-RedactRule ('\.last-run-' + [regex]::Escape((& $Form $env:USERNAME)) + '(?![\w~-])') '.last-run-%USERNAME%' }
    $userNames = @()
    if ($env:USERNAME) { $userNames += $env:USERNAME }
    if ($env:USERPROFILE) {
        $leaf = Split-Path $env:USERPROFILE.TrimEnd('\') -Leaf
        if ($leaf -and -not ($userNames -contains $leaf)) { $userNames += $leaf }
    }
    # Longest first across user and computer names: a profile folder named <user>-something, or a
    # computer named <user>-PC, is replaced whole, not as <user>-something.
    $words = @()
    foreach ($u in $userNames) {
        if ($u.Length -ge 3) { $words += , @($u, '<user>') }
        else {
            Add-RedactRule ('(?<=[\\/]{1,2}Users[\\/]{1,2})' + [regex]::Escape((& $Form $u)) + '(?!\.?[\w~-])') '<user>'
            if ($Notes) { [void]$script:RedactNotes.Add('redact: the user name is under 3 characters, so it is hidden only in \Users\<name> paths') }
        }
    }
    if ($env:COMPUTERNAME) {
        if ($env:COMPUTERNAME.Length -ge 3) { $words += , @($env:COMPUTERNAME, '<computer>') }
        elseif ($Notes) { [void]$script:RedactNotes.Add('redact: the computer name is under 3 characters, so it is not replaced') }
    }
    foreach ($w in @($words | Sort-Object { $_[0].Length } -Descending)) {
        Add-RedactRule ('(?<!\w)' + [regex]::Escape((& $Form $w[0])) + '(?!\w)') $w[1]
    }
    Add-RedactRule '(?<=(?<!\w)userdata[\\/]{1,2})\d+(?!\w)' '<steam-id>'
}
Add-RedactRuleSet $script:RedactRules { param($s) $s } $true
Add-RedactRuleSet $script:RedactRulesLatin1 { param($s) $s } $false
if ((@($profForms) + @($env:USERNAME, $env:COMPUTERNAME) -join '') -match '[^\x00-\x7F]') {
    $script:Latin1Enc = [System.Text.Encoding]::GetEncoding(28591)
    Add-RedactRuleSet $script:RedactRulesLatin1 { param($s) $script:Latin1Enc.GetString([System.Text.Encoding]::UTF8.GetBytes($s)) } $false
}

# Applies every -Redact rule (or the Latin-1 set); adds the number of replacements to $Hits. Never logs the values.
function ConvertTo-RedactedText([string]$Text, [ref]$Hits, [switch]$Latin1) {
    foreach ($r in $(if ($Latin1) { $script:RedactRulesLatin1 } else { $script:RedactRules })) {
        $c = $r.rx.Matches($Text).Count
        if ($c -gt 0) { $Text = $r.rx.Replace($Text, $r.with); $Hits.Value += $c }
    }
    return $Text
}

function Hide-Path([string]$Text) {
    if ($null -eq $Text) { return $null }
    if ($Redact) { $n = 0; return (ConvertTo-RedactedText $Text ([ref]$n)) }
    if ($script:ProfileRx) { $Text = $Text -replace $script:ProfileRx, '%USERPROFILE%' }
    if ($script:MarkerRx) { $Text = $Text -replace $script:MarkerRx, '.last-run-%USERNAME%' }
    return $Text
}

# -Redact on a staged copy. Saves and screenshots never reach this; a file is text when it starts with
# a UTF-16 byte-order mark, has no zero byte in its first 64 KB, or has a text extension ($RedactTextExt).
$RedactSkipExt = @('.sfs', '.png', '.jpg', '.jpeg', '.bmp')
# These are always read as text, even with a zero byte in them.
$RedactTextExt = @('.log', '.txt', '.ini', '.json', '.toml', '.xml', '.csv', '.cfg', '.yaml', '.yml')
$script:RedactFiles = 0
$script:RedactTotal = 0
$script:RedactLeft = 0

# Where the last complete line in $Data ends (0 = no line break yet). UTF-16 needs the 0A as a whole
# character at an even offset; every piece starts at an even offset after the byte-order mark.
function Find-LineEnd([byte[]]$Data, [int]$Unit, [bool]$BigEndian) {
    $i = $Data.Length - 1
    while ($i -ge 0) {
        $i = [Array]::LastIndexOf($Data, [byte]10, $i)
        if ($i -lt 0) { return 0 }
        if ($Unit -eq 1) { return $i + 1 }
        if ($BigEndian) { if ($i % 2 -eq 1 -and $Data[$i - 1] -eq 0) { return $i + 1 } }
        elseif ($i % 2 -eq 0 -and $i + 1 -lt $Data.Length -and $Data[$i + 1] -eq 0) { return $i + 2 }
        $i--
    }
    return 0
}

# Reads $Path in pieces that end at a line break (no rule crosses one), writes the redacted text to
# $Tmp with the same byte-order mark and encoding, and returns the number of replacements.
function Invoke-RedactStream([string]$Path, [string]$Tmp, [int]$Bom, [System.Text.Encoding]$Enc, [int]$Unit, [bool]$BigEndian, [bool]$Latin1 = $false) {
    $hits = 0
    $in = [System.IO.File]::OpenRead($Path)
    try {
        $out = [System.IO.File]::Create($Tmp)
        try {
            if ($Bom -gt 0) {
                $pre = New-Object byte[] $Bom
                [void]$in.Read($pre, 0, $Bom)
                $out.Write($pre, 0, $Bom)
            }
            $carry = New-Object byte[] 0
            $buf = New-Object byte[] (4MB)
            while ($true) {
                $k = $in.Read($buf, 0, $buf.Length)
                $eof = $k -le 0
                if ($eof) { $k = 0 }
                $data = New-Object byte[] ($carry.Length + $k)
                [Array]::Copy($carry, $data, $carry.Length)
                if ($k -gt 0) { [Array]::Copy($buf, 0, $data, $carry.Length, $k) }
                $cut = $(if ($eof) { $data.Length } else { Find-LineEnd $data $Unit $BigEndian })
                if ($cut -gt 0) {
                    $n = 0
                    $new = ConvertTo-RedactedText ($Enc.GetString($data, 0, $cut)) ([ref]$n) -Latin1:$Latin1
                    $hits += $n
                    $bytes = $Enc.GetBytes($new)
                    $out.Write($bytes, 0, $bytes.Length)
                }
                $carry = New-Object byte[] ($data.Length - $cut)
                [Array]::Copy($data, $cut, $carry, 0, $carry.Length)
                if ($eof) { break }
            }
        } finally { $out.Dispose() }
    } finally { $in.Dispose() }
    return $hits
}

# Redacts a staged copy in place. Returns -1 when it doesn't look like text (left as is), else the
# number of replacements; with none, the file is left byte-identical. Throws when it can't be done.
function Invoke-RedactFile([string]$Path) {
    $head = New-Object byte[] 65536
    $got = 0
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        while ($got -lt $head.Length) { $k = $fs.Read($head, $got, $head.Length - $got); if ($k -le 0) { break }; $got += $k }
    } finally { $fs.Dispose() }
    $bom = 0; $kind = 'plain'
    if ($got -ge 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) { $bom = 3; $kind = 'utf8' }
    elseif ($got -ge 2 -and $head[0] -eq 0xFF -and $head[1] -eq 0xFE) { $bom = 2; $kind = 'utf16le' }
    elseif ($got -ge 2 -and $head[0] -eq 0xFE -and $head[1] -eq 0xFF) { $bom = 2; $kind = 'utf16be' }
    if ($kind -eq 'plain' -and $got -gt 0 -and [Array]::IndexOf($head, [byte]0, 0, $got) -ge 0) {
        # A zero byte means binary, except in a file with a text extension: a log cut off by a crash can
        # end in zero padding, and UTF-16 can come without a byte-order mark (zeros at every odd or even byte).
        if ($RedactTextExt -notcontains [System.IO.Path]::GetExtension($Path).ToLowerInvariant()) { return -1 }
        $odd = 0; $even = 0
        for ($j = 0; $j -lt $got; $j++) { if ($head[$j] -eq 0) { if ($j % 2) { $odd++ } else { $even++ } } }
        if ($got -ge 2 -and $odd -ge [int]($got / 2 * 0.9) -and $even -lt [int]($got / 20) + 1) { $kind = 'utf16le' }
        elseif ($got -ge 2 -and $even -ge [int]($got / 2 * 0.9) -and $odd -lt [int]($got / 20) + 1) { $kind = 'utf16be' }
    }
    $tmp = $Path + '.redact-tmp'
    try {
        if ($kind -like 'utf16*') {
            $be = ($kind -eq 'utf16be')
            $hits = Invoke-RedactStream $Path $tmp $bom (New-Object System.Text.UnicodeEncoding($be, $false, $true)) 2 $be
        } else {
            # UTF-8 when every byte is valid UTF-8, otherwise Latin-1, where every byte round-trips (with the
            # Latin-1 rule set, so a UTF-8 name with letters outside English is still found).
            try { $hits = Invoke-RedactStream $Path $tmp $bom (New-Object System.Text.UTF8Encoding($false, $true)) 1 $false }
            catch {
                $e = $_.Exception
                while ($e -and -not ($e -is [System.Text.DecoderFallbackException])) { $e = $e.InnerException }
                if (-not $e) { throw }
                $hits = Invoke-RedactStream $Path $tmp $bom ([System.Text.Encoding]::GetEncoding(28591)) 1 $false $true
            }
        }
        if ($hits -gt 0) { [System.IO.File]::Copy($tmp, $Path, $true) }
    } finally {
        # A temp file that can't be removed now (antivirus, say) must not lose the good copy; the zip
        # step removes any left over.
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction Stop } }
        catch { Write-Log "redact: could not remove a temp file yet: $($_.Exception.Message)" }
    }
    return $hits
}

# Read-Host without a byte-order mark or spaces around the answer: Windows PowerShell 5.1 piping
# answers into pwsh puts U+FEFF before the first one, so "y" would not count as yes.
function Read-Answer([string]$Prompt) {
    return ([string](Read-Host $Prompt)).Trim([char[]]@([char]0xFEFF, ' ', "`t"))
}

function Write-Log([string]$Text) {
    $line = '{0} {1}' -f (Get-Date).ToString('HH:mm:ss.fff'), (Hide-Path $Text)
    [void]$script:LogLines.Add($line)
    Write-Verbose (Hide-Path $Text)
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
    $redactStop = $false
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
        $pkg = ($Dest -replace '\\', '/')
        $hits = 0
        if ($Redact -and $RedactSkipExt -notcontains $File.Extension.ToLowerInvariant()) {
            # Fail closed: a text file that can't be redacted is left out, never sent unredacted.
            try { $hits = Invoke-RedactFile $target }
            catch {
                $why = $_.Exception.Message
                # If the unredacted copy can't be removed either, stop: it must never reach the zip.
                try { Remove-Item -LiteralPath $target -Force -ErrorAction Stop } catch { }
                if (Test-Path -LiteralPath $target) {
                    $redactStop = $true
                    throw "Stopped: $($File.FullName) could not be redacted, and its unredacted copy in the staging folder could not be removed ($why). Close the program holding it (often antivirus) and run the collector again."
                }
                Add-Warning "Left out $($File.FullName) because it could not be redacted: $why"
                return $false
            }
            if ($hits -lt 0) { $script:RedactLeft++; Write-Log "redact: left as is (does not look like text): $pkg" }
            elseif ($hits -gt 0) {
                (Get-Item -LiteralPath $target).LastWriteTime = $File.LastWriteTime
                $script:RedactFiles++; $script:RedactTotal += $hits
                Write-Log "redact: $pkg ($hits replacements)"
            }
        }
        # .NET rather than Get-FileHash: 5.1 started from PowerShell 7 can fail to load that cmdlet.
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($target)
        try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLowerInvariant() }
        finally { $fs.Dispose(); $sha.Dispose() }
        $entry = [ordered]@{
            package  = $pkg
            source   = (Hide-Path $File.FullName)
            size     = $File.Length
            modified = $File.LastWriteTime.ToString('s')
            sha256   = $hash
        }
        if ($hits -gt 0) {
            # size and sha256 describe the file in the zip; sourceSize is the original's size.
            $entry.size = (Get-Item -LiteralPath $target).Length
            $entry.sourceSize = $File.Length
            $entry.redacted = $true
        }
        [void]$script:Collected.Add($entry)
        Write-Log "copy: $($File.FullName) -> $Dest ($($File.Length) bytes)"
        return $true
    } catch {
        if ($redactStop) { throw }
        if ($Redact -and (Test-Path -LiteralPath $target)) {
            # A copy cut off partway was never redacted: it must not reach the zip.
            try { Remove-Item -LiteralPath $target -Force -ErrorAction Stop } catch { }
            if (Test-Path -LiteralPath $target) {
                throw "Stopped: copying $($File.FullName) failed, and its unredacted partial copy in the staging folder could not be removed. Close the program holding it (often antivirus) and run the collector again."
            }
        }
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

# Decodes one value the way Qt's QSettings (and so MO2 itself) reads its INI. A port of the parts of
# Qt 5.15's QSettingsPrivate::iniUnescapedStringList and stringToVariant (qsettings.cpp, checked
# 2026-11-19) that MO2's folder settings can use. Not handled, on purpose (MO2 never writes them for
# folders): @Variant/@DateTime binary values, which are read as "".
#   - leading spaces are skipped; trailing spaces are cut unless the value was quoted (or ends in a
#     lone backslash);
#   - a double quote toggles quoting anywhere and is removed; a comma outside quotes makes a list,
#     which MO2 reads as an empty string (so the default folder is used);
#   - a backslash + line break (a continued line, kept by Split-QtIniLines) is dropped;
#   - escapes \a \b \f \n \r \t \v \" \? \' \\ (lowercase only); \x plus every hex digit after it, and
#     \ plus octal digits, keep the low 16 bits; \x with no hex digit, an unknown escape (\M in
#     D:\Mods) and a lone trailing backslash are dropped entirely, as Qt drops them;
#   - then the decoded text's @ forms: @ByteArray(...) holds bytes (Latin-1, so a character above 255
#     becomes '?'; MO2 reads them as UTF-8), @String(...), @Invalid() is no value (""), @Rect, @Size
#     and @Point are no string ("") when they have 4, 2 and 2 space-separated arguments (otherwise the
#     text stays), and @@ is a literal @.
# Lines, comments and continuations are Split-QtIniLines' job (Qt's readIniLine).
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
    $skipCut = $false
    $isHex = { param($ch) ($ch -ge [char]'0' -and $ch -le [char]'9') -or ($ch -ge [char]'a' -and $ch -le [char]'f') -or ($ch -ge [char]'A' -and $ch -le [char]'F') }
    $cutTrailing = { while ($sb.Length -gt $chop -and ($sb[$sb.Length - 1] -eq ' ' -or $sb[$sb.Length - 1] -eq "`t")) { [void]$sb.Remove($sb.Length - 1, 1) } }
    while ($i -lt $n) {
        $c = $v[$i]
        if ($c -eq '\') {
            $i++
            # Qt's "goto end": a lone trailing backslash ends the value without cutting spaces.
            if ($i -ge $n) { $skipCut = $true; break }
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
    if (-not $quoted -and -not $skipCut) { & $cutTrailing }
    # A list (two or more items) is a QStringList; MO2 reads it as a string, which gives "".
    if ($isList) { return '' }
    $out = $sb.ToString()
    $ord = [StringComparison]::Ordinal
    if ($out.StartsWith('@String(', $ord) -and $out.EndsWith(')', $ord)) { return $out.Substring(8, $out.Length - 9) }
    # Typed forms. @Rect/@Size/@Point become non-strings ("") only with the right number of
    # space-separated arguments (4, 2, 2), as in Qt; otherwise Qt keeps the text.
    # @Variant/@DateTime hold Qt's binary data stream, which this tool doesn't decode: read as "".
    foreach ($typed in @(@('@Rect(', 4), @('@Size(', 2), @('@Point(', 2))) {
        if ($out.StartsWith($typed[0], $ord) -and $out.EndsWith(')', $ord)) {
            # Qt's splitArgs: a space ends an item (empty items kept); a ')' adds the item without clearing it.
            $args2 = New-Object System.Collections.Generic.List[string]
            $item = ''
            foreach ($ch in $out.Substring($typed[0].Length).ToCharArray()) {
                if ($ch -eq ')') { $args2.Add($item) }
                elseif ($ch -eq ' ') { $args2.Add($item); $item = '' }
                else { $item += $ch }
            }
            if ($args2.Count -eq $typed[1]) { return '' }
            return $out
        }
    }
    foreach ($typed in '@Variant(', '@DateTime(') {
        if ($out.StartsWith($typed, $ord) -and $out.EndsWith(')', $ord)) { return '' }
    }
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

# Splits INI text into logical lines the way Qt 5.15's QConfFileSettingsPrivate::readIniLine does
# (qsettings.cpp, checked 2026-11-19). Returns @{ text; eq } per line, eq = index of the first '='
# outside quotes (or -1). Rules: leading spaces, tabs and line breaks are skipped; a ';' first on a line
# makes the line a comment, and an unquoted ';' later ends the line; a backslash takes the next character
# with it (so backslash + line break continues the line); a line break inside quotes doesn't end it.
function Split-QtIniLines([string]$Data) {
    $out = New-Object System.Collections.Generic.List[object]
    $len = $Data.Length
    $isSpace = { param($c) $c -eq ' ' -or $c -eq "`t" -or $c -eq "`n" -or $c -eq "`r" }
    $pos = 0
    while ($true) {
        $ls = $pos
        while ($ls -lt $len -and (& $isSpace $Data[$ls])) { $ls++ }
        $i = $ls; $inQ = $false; $eq = -1
        while ($i -lt $len) {
            $ch = $Data[$i]
            if ($ch -ne '=' -and $ch -ne "`n" -and $ch -ne "`r" -and $ch -ne '\' -and $ch -ne '"' -and $ch -ne ';') { $i++; continue }
            $i++
            if ($ch -eq '=') { if (-not $inQ -and $eq -eq -1) { $eq = $i - 1 } }
            elseif ($ch -eq "`n" -or $ch -eq "`r") {
                if ($i -eq $ls + 1) { $ls++ } elseif (-not $inQ) { $i--; break }
            }
            elseif ($ch -eq '\') {
                if ($i -lt $len) {
                    $c1 = $Data[$i]; $i++
                    if ($i -lt $len) {
                        $c2 = $Data[$i]
                        if (($c1 -eq "`n" -and $c2 -eq "`r") -or ($c1 -eq "`r" -and $c2 -eq "`n")) { $i++ }
                    }
                }
            }
            elseif ($ch -eq '"') { $inQ = -not $inQ }
            else {
                # ';'
                if ($i -eq $ls + 1) {
                    while ($i -lt $len -and $Data[$i] -ne "`n" -and $Data[$i] -ne "`r") { $i++ }
                    while ($i -lt $len -and (& $isSpace $Data[$i])) { $i++ }
                    $ls = $i
                } elseif (-not $inQ) { $i--; break }
            }
        }
        $pos = $i
        if ($i - $ls -le 0) { break }
        $out.Add(@{ text = $Data.Substring($ls, $i - $ls); eq = $(if ($eq -ge 0) { $eq - $ls } else { -1 }) })
    }
    return $out
}

# Qt 5.15's QSettingsPrivate::iniUnescapedKey: '\' becomes '/', %XX and %UXXXX are hex characters
# (a '%' that can't be read stays as is).
function ConvertFrom-QtIniKey([string]$Key) {
    $sb = New-Object System.Text.StringBuilder
    $i = 0; $to = $Key.Length
    while ($i -lt $to) {
        $ch = $Key[$i]
        if ($ch -eq '\') { [void]$sb.Append('/'); $i++; continue }
        if ($ch -ne '%' -or $i -eq $to - 1) { [void]$sb.Append($ch); $i++; continue }
        $num = 2; $first = $i + 1
        if ($Key[$i + 1] -ceq 'U') { $first++; $num = 4 }
        $code = 0
        if ($first + $num -gt $to -or -not [int]::TryParse($Key.Substring($first, $num), [Globalization.NumberStyles]::AllowHexSpecifier, [Globalization.CultureInfo]::InvariantCulture, [ref]$code)) {
            [void]$sb.Append('%'); $i++; continue
        }
        [void]$sb.Append([char]$code); $i = $first + $num
    }
    return $sb.ToString()
}

# Reads ModOrganizer.ini as Qt 5.15 does (readIniFile, readIniSection). Keys come back lowercased (Qt's
# INI keys ignore case on Windows) with '/' between section and key: "settings/profiles_directory";
# keys in [General] have no section: "selected_profile".
function Read-MO2Ini([string]$Path) {
    # Qt keeps sections in a map sorted by lowercased name ([General] is "" and comes first). This reads
    # every section in that order, as Qt does when it reads the whole file; when two sections give the
    # same full key, the later one in sorted order wins (within a section, the later line). Qt reads
    # sections lazily for single lookups, so for such duplicated keys (which MO2 never writes) MO2 may
    # pick another one. Section names are lowercased with .NET's invariant rules, which differ from
    # Qt's for a few %U-escaped letters.
    $bySection = @{}
    $section = ''
    # Shared read, write and delete, so a running MO2 that holds the file open doesn't stop the read.
    # No sharing mode lets MO2 save meanwhile: Windows refuses to rename a file over one that is open
    # (tested 2026-11-19). What protects MO2's saves is that the file is read in one go and closed at
    # once (milliseconds). UTF-8, and only a UTF-8 byte-order
    # mark is dropped, as in Qt. Limits: a raw non-ASCII byte in a section or key name and a %-escape
    # with a sign or 0x are read slightly differently from Qt; MO2 writes neither.
    $fs = [System.IO.File]::Open($Path, 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
    try { $ms = New-Object System.IO.MemoryStream; $fs.CopyTo($ms); $bytes = $ms.ToArray() } finally { $fs.Dispose() }
    $skip = $(if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 })
    $data = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes, $skip, $bytes.Length - $skip)
    $asciiSpace = [char[]]@(' ', "`t", "`n", [char]11, [char]12, "`r")
    foreach ($line in Split-QtIniLines $data) {
        $t = $line.text
        if ($t.StartsWith('[')) {
            $close = $t.IndexOf(']')
            $name = $(if ($close -ge 0) { $t.Substring(1, $close - 1) } else { $t.Substring(1) }).Trim($asciiSpace)
            if ($name -ieq 'general') { $section = '' }
            elseif ($name -ieq '%general') { $section = $name.Substring(1).ToLowerInvariant() + '/' }
            else { $section = (ConvertFrom-QtIniKey $name).ToLowerInvariant() + '/' }
            continue
        }
        if ($line.eq -lt 0) { continue }
        $k = (ConvertFrom-QtIniKey $t.Substring(0, $line.eq).TrimEnd(' ', "`t")).ToLowerInvariant()
        if (-not $bySection.ContainsKey($section)) { $bySection[$section] = [ordered]@{} }
        $bySection[$section][$section + $k] = ConvertFrom-QtIniValue $t.Substring($line.eq + 1)
    }
    $names = [string[]]@($bySection.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $vals = @{}
    # get_Keys(), not .Keys: a [General] entry named "keys" would hide the .Keys property.
    foreach ($s in $names) { foreach ($key in $bySection[$s].get_Keys()) { $vals[$key] = $bySection[$s][$key] } }
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
            $go = Read-Answer 'Collect anyway? [y/N]'
            if ($go -notmatch '^[yY]') { Write-Host 'Stopped. Nothing was collected.'; exit 1 }
        }
    }

    if (-not $NoPrompt) {
        if (-not $Note) { $Note = Read-Answer 'What did you test? (e.g. "new quest, checks 1-12", Enter to skip)' }
        if (-not $PSBoundParameters.ContainsKey('IncludeSaves') -and -not $PSBoundParameters.ContainsKey('SavePair')) {
            $ans = Read-Answer 'Include saves? p = before/after pair, y = newest save, Enter = none [p/y/N]'
            if ($ans -match '^[pP]') { $SavePair = $true }
            elseif ($ans -match '^[yY]') { $IncludeSaves = $true }
        }
        if (-not $PSBoundParameters.ContainsKey('Redact')) {
            $ans = Read-Answer 'Hide your Windows user name, computer name and user folder in the copied files? [y/N]'
            if ($ans -match '^[yY]') {
                $Redact = $true
                # What was written before the answer gets the same rules.
                foreach ($list in @($script:LogLines, $script:Warnings, $script:Skipped)) {
                    for ($i = 0; $i -lt $list.Count; $i++) { $list[$i] = Hide-Path $list[$i] }
                }
            }
        }
    }
    Write-Log "note: $Note; saves: newest=$([bool]$IncludeSaves) pair=$([bool]$SavePair); redact: $([bool]$Redact)"
    if ($Redact) {
        Write-Log 'redact: on; saves, screenshots and files that do not look like text are copied as they are, and zip entry names are not changed'
        foreach ($rn in $script:RedactNotes) { Write-Log $rn }
    }

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
                $base = Resolve-MO2Dir $MO2Path $ini['settings/base_directory'] '.'
                $profilesDir = Resolve-MO2Dir $base $ini['settings/profiles_directory'] 'profiles'
                $overwriteDir = Resolve-MO2Dir $base $ini['settings/overwrite_directory'] 'overwrite'
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
    if ($Redact) {
        # Same rules as the copied files: a plugin or DLL named after the user is <user>.esm here too.
        foreach ($item in @($listing.sfsePluginDlls) + @($listing.dataPlugins)) { $item.name = Hide-Path $item.name }
    }
    if ($mo2) { $listing.note = 'With Mod Organizer 2 the mods stay in MO2''s mods folder: see mo2\profile\modlist.txt for the mod list.' }

    $manifest = [ordered]@{
        tool      = "Collect-StarfieldTestLogs $ScriptVersion"
        created   = $Now.ToString('s')
        note      = $(if ($Redact) { Hide-Path $Note } else { $Note })
        redact    = [bool]$Redact
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
    if ($Redact) { Write-Log "redact: $($script:RedactFiles) file(s) changed, $($script:RedactTotal) replacement(s); $($script:RedactLeft) file(s) left as is because they do not look like text" }
    Write-Log "zip: $ZipPath"
    [System.IO.File]::WriteAllLines((Join-Path $script:Stage 'collector-log.txt'), [string[]]$script:LogLines, $utf8)
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    if ($Redact) {
        # Temp files -Redact couldn't remove at the time are not part of the package.
        foreach ($t in @(Get-ChildItem -LiteralPath $script:Stage -Filter '*.redact-tmp' -File -Recurse -ErrorAction SilentlyContinue)) {
            try { Remove-Item -LiteralPath $t.FullName -Force -ErrorAction Stop }
            catch { throw "Stopped: a temp file in the staging folder could not be removed ($($_.Exception.Message)). Close the program holding it (often antivirus) and run the collector again." }
        }
    }
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
    if ($Redact) {
        $left = $(if ($script:RedactLeft -gt 0) { ", and $($script:RedactLeft) file(s) that don't look like text" } else { '' })
        Write-Host "  Redacted: $($script:RedactFiles) file(s) changed; saves and screenshots left as they are$left"
    }
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
            # A run that stopped before the paths were resolved still has the -LogFile as typed;
            # .NET would resolve a relative name against its own folder, not the one the user is in.
            if (-not [System.IO.Path]::IsPathRooted($LogFile)) {
                $LogFile = Join-Path (Get-Location -PSProvider FileSystem).Path $LogFile
            }
            [System.IO.File]::AppendAllLines($LogFile, [string[]]$script:LogLines)
            Write-Host "  Log     : $LogFile"
        } catch { Write-Host "  Could not write the log to ${LogFile}: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
exit $exitCode
