# Changelog

## 2.0.0 (2026-11-19)

### What's new

This is the first public release; versions 1.0.0 to 1.1.1 were private builds. sf-log-collector gathers your Starfield logs into one zip with a single double-click, so you can attach that one file to a bug report. It picks up the Papyrus script logs, SFSE and crash logs, your game INIs, `plugins.txt`, mod settings, new screenshots and Windows crash events, and saves if you ask. It only reads, and it never connects to the network.

### Example

A real run on a made-up test setup (only the zip's folder is changed, to the default one):

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
- A troubleshooting log: `collector-log.txt` in every zip, `-LogFile <file>`, and `-Verbose`.
- The manifest, the log and `events.txt` show `%USERPROFILE%` in place of the Windows user folder, and they no longer record the computer or user name.
- Errors stop with exit code 2 and a message naming the problem, and the launcher passes the exit code on.
- A Game Pass save container (not `.sfs` files) gets a warning saying how to export the saves.
- SHA-256 is computed with .NET, so Windows PowerShell 5.1 started from PowerShell 7 no longer fails to copy files.

### Download

Download `sf-log-collector-2.0.0.zip` and its `.sha256` file below, unzip it anywhere and follow the Quick start in the README. It needs only Windows 10 or 11 and the PowerShell that ships with them.

## 1.1.1 (private)

- Don't stop when another Windows user can't read the default game folder.

## 1.1.0 (private)

- Before/after save pair (`-SavePair`).

## 1.0.1 (private)

- Always include `Papyrus.1.log`.

## 1.0.0 (private)

- First version.
