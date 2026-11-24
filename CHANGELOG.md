# Changelog

## 2.1.0 (2026-11-24)

### What's new

The new `-Redact` option hides your Windows user name, your computer name, your user folder and your Steam account number in the files the collector copies, so you can send the zip to a mod author or hand it to an AI assistant without them. When you double-click the `.cmd` file, it asks one new question about it, and pressing Enter leaves it off. Without `-Redact`, the collector copies every file exactly as 2.0.1 did.

### Example

This is a real run on a made-up test setup (the options that point at the test setup's folders are left out, and the paths are shortened):

    > powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Note "quest stuck at step 3" -Hours 2 -NoPrompt -Redact

    Starfield log collector 2.1.0

    Collecting files changed last 2 hours (2026-11-24 10:53)
      ! Crash log found! (1 new log(s) in SFSE\Crashlogs)

    Done.
      Package : C:\Users\<you>\Documents\StarfieldLogs\StarfieldLogs-20261124-125335-quest-stuck-at-step-3.zip
      Size    : 0.0 MB, 5 files
      Contents: papyrus 1, gameIni 1, sfseLogs 1, crashLogger 1, pluginsTxt 1
      Redacted: 2 file(s) changed; saves and screenshots left as they are

    Warnings:
      - Crash log found! (1 new log(s) in SFSE\Crashlogs)

    Send this zip to whoever asked for your logs. Look inside first if you share it in public.

In the zip, the SFSE log's `config path = C:\Users\<you>\Documents\My Games\Starfield\SFSE\sfse.ini` line reads `config path = %USERPROFILE%\Documents\My Games\Starfield\SFSE\sfse.ini`, and the crash log's `Computer:` line reads `Computer: <computer>`.

### Changes

- New `-Redact` switch. In every copied text file (logs, `plugins.txt`, INIs, crash logs, SFSE reports, Vortex exports, console transcripts) and in the collector's own files, it replaces your user folder with `%USERPROFILE%` (in the `\`, `/`, JSON `\\` and short 8.3 forms), your Windows user name with `<user>`, your computer name with `<computer>`, and `userdata\<number>` with `userdata\<steam-id>`. Plugin names, form IDs and mod names are not touched, unless one of them is your user name or computer name as a whole word.
- Saves, screenshots, files that don't look like text, and file names are left as they are, and the README, PRIVACY.md and the help text say so. A user name under 3 letters is hidden only in `\Users\<name>` paths.
- A text file that can't be redacted, or whose copy fails partway, is left out of the zip with a warning, so it is never sent unredacted. If its unredacted copy can't be removed from the staging folder, the run stops without making a zip.
- The plugin and DLL names in the manifest's `listing` follow the same rules, so a plugin named after you is `<user>.esm` there too.
- Files named `.log`, `.txt`, `.ini`, `.json`, `.toml`, `.xml`, `.csv`, `.cfg`, `.yaml` or `.yml` are always redacted as text, so a log that a crash cut off with zero bytes at its end, or a UTF-16 file without a byte-order mark, is not passed over as binary.
- The double-click run asks `Hide your Windows user name, computer name and user folder in the copied files? [y/N]`. With `-NoPrompt` and no `-Redact`, nothing is redacted.
- `manifest.json` has a new top-level `redact` field. A file that redaction changed has `"redacted": true`, `size` and `sha256` for the copy in the zip, and `sourceSize` for the original.
- The test script has new checks for `-Redact` and now reports a collector that fails to start as a failed check instead of stopping.

### Fixes

- `Get-Help .\Collect-StarfieldTestLogs.ps1 -Detailed` shows the help text and every option again. In 2.0.0 and 2.0.1 the license lines directly above the help text kept PowerShell from finding it, so `Get-Help` showed only the list of option names.
- Answers piped into the questions from Windows PowerShell 5.1 now count. 5.1 puts an invisible byte-order mark before the first answer, so a piped `y` was read as no; the collector now strips it and any spaces around an answer.

## 2.0.1 (2026-11-20)

### What's new

This is a small release. `-Log <file>` is now a documented short form of `-LogFile <file>`, and the README and AGENTS.md say plainly where the troubleshooting log goes and how to see it as it runs. `-Verbose` no longer shows your Windows user folder on screen. Otherwise the collector works as it did in 2.0.0.

### Example

This is a real run on a made-up test setup (the options that point at the test setup's folders are left out, and the paths are shortened):

    > powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Note "menu test" -NoPrompt -Log sf-logs.txt

    Starfield log collector 2.0.1

    Collecting files changed last 12 hours (first run) (2026-11-20 05:32)

    Done.
      Package : C:\Users\<you>\Documents\StarfieldLogs\StarfieldLogs-20261120-173252-menu-test.zip
      Size    : 0.0 MB, 4 files
      Contents: papyrus 1, gameIni 2, pluginsTxt 1

    Send this zip to whoever asked for your logs. Look inside first if you share it in public.
      Log     : C:\Users\<you>\sf-logs.txt

    > Get-Content sf-logs.txt -TotalCount 2
    17:32:52.711 Collect-StarfieldTestLogs 2.0.1, PowerShell 5.1.26100.9818
    17:32:52.747 note: menu test; saves: newest=False pair=False

The same log is always inside the zip as `collector-log.txt`. Add `-Verbose` to see it on screen as it runs.

### Changes

- `-Log <file>` is a short form of `-LogFile <file>`.
- The README's Options and Troubleshooting sections and AGENTS.md describe the log: where it goes, that `-Log` adds to the end of an existing file, and that `-Verbose` shows it on screen.

### Fixes

- `-Verbose` now hides your Windows user folder as `%USERPROFILE%` on screen, the same way the log does. In 2.0.0 the on-screen lines showed the real folder, so console text pasted into a public issue could name your Windows user.
- A run that stopped very early with `-LogFile sf-logs.txt` now writes the log in the folder you ran it from. Before, a relative name could land in another folder.
- Test script: when it picks the shell for you, the `Shell` line at the top now says so (for example "the default for this host, taken from PATH"), as its help promised.
- Test script: `-Shell '\\?\C:\...\..\pwsh.exe'` was reported as not found, because `..` isn't resolved after a `\\?\` prefix. The prefix is now dropped before the path is resolved, which also lets Windows PowerShell 5.1 be tested through such a path (5.1 can't start when launched through a `\\?\` path). The `\\.\` prefix is handled the same way, and what's left after either prefix must be a full drive or network path.
- Test script: it has new checks for `-Log`, `-Verbose` and its own `-Shell` handling (a new `-ResolveOnly` switch checks the shell and stops).

### Download

Download `sf-log-collector-2.0.1.zip` and its `.sha256` file below, unzip it anywhere and follow the Quick start in the README. If you already have 2.0.0, nothing changes in how the collector runs.

## 2.0.0 (2026-11-19)

### What's new

This is the first public release; versions 1.0.0 to 1.1.1 were private builds. sf-log-collector gathers your Starfield logs into one zip with a single double-click, so you can attach that one file to a bug report. It picks up the Papyrus script logs, SFSE and crash logs, your game INIs, `plugins.txt`, mod settings, new screenshots and Windows crash events, and saves if you ask. It only reads, and it never connects to the network.

### Example

This is a real run on a made-up test setup (only the zip's folder is changed, to the default one):

    > powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Note "quest stuck at step 3" -Hours 2 -IncludeSaves

    Starfield log collector 2.0.0

    Collecting files changed last 2 hours (2026-11-20 13:36)
      ! Crash log found! (1 new log(s) in SFSE\Crashlogs)

    Done.
      Package : C:\Users\<you>\Documents\StarfieldLogs\StarfieldLogs-20261120-153652-quest-stuck-at-step-3.zip
      Size    : 0.0 MB, 12 files
      Contents: papyrus 3, gameIni 2, sfseLogs 1, crashLogger 1, pluginsTxt 1, pluginIni 1, consoleTranscripts 1, screenshots 1, saves 1

    Warnings:
      - Crash log found! (1 new log(s) in SFSE\Crashlogs)

    Send this zip to whoever asked for your logs. Look inside first if you share it in public.

Most players never type this: double-clicking `Collect-StarfieldTestLogs.cmd` asks the two questions (what you tested, and whether to add saves) and does the same.

### Changes since the private builds

- The zip now goes to `Documents\StarfieldLogs` by default (`-OutDir` moves it).
- It finds Game Pass installs (`<drive>:\XboxGames\Starfield\Content`, and the folder in each drive's `.GamingRoot`) as well as every Steam library. `-GamePath` also takes the `Data` folder.
- Mod Organizer 2: `-MO2Path` and `-MO2Profile` add the profile's `plugins.txt`, `loadorder.txt`, `modlist.txt` and INIs, MO2's `overwrite\SFSE` reports and settings, and MO2's logs.
- Screenshots default to Steam's Starfield screenshots and photo mode's folder, and `-ScreenshotDir` takes several folders (`"dir1;dir2"`).
- New `-DownloadsDir`, `-MyGamesDir` and `-PluginsTxtDir` options cover non-standard folders.
- A troubleshooting log is added: `collector-log.txt` in every zip, `-LogFile <file>`, and `-Verbose`.
- The manifest, the log and `events.txt` show `%USERPROFILE%` in place of the Windows user folder, and they no longer record the computer or user name.
- Errors stop with exit code 2 and a message naming the problem, and the launcher passes the exit code on.
- A Game Pass save container (not `.sfs` files) gets a warning saying how to export the saves.
- SHA-256 is computed with .NET, so Windows PowerShell 5.1 started from PowerShell 7 no longer fails to copy files.

### Download

Download `sf-log-collector-2.0.0.zip` and its `.sha256` file below, unzip it anywhere and follow the Quick start in the README. It needs only Windows 10 or 11 and the PowerShell that ships with them.

## 1.1.1 (private)

- The collector no longer stops when another Windows user can't read the default game folder.

## 1.1.0 (private)

- A before/after save pair (`-SavePair`) is added.

## 1.0.1 (private)

- The collector always includes `Papyrus.1.log`.

## 1.0.0 (private)

- This is the first version.
